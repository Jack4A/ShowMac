import Foundation
import Darwin
import CSMC
import ThermalCore

/// All operations share a serial request/reply channel to one compiled root helper.
/// The only authentication UI is the native Authorization Services bootstrap.
final class NativeControlClient {
    private let queue=DispatchQueue(label:"local.thermalscope.native-control",qos:.utility)
    private var channel:ControlChannel?
    private var ready=false
    private var polling=false
    private let pollLock=NSLock()
    func request(_ request:ControlRequest,allowAuthorization:Bool=true,completion:@escaping(Result<ControlReply,Error>)->Void) {
        queue.async { [self] in
            do {completion(.success(try perform(request,allowAuthorization:allowAuthorization)))}
            catch {completion(.failure(error))}
        }
    }
    func poll(completion:@escaping(Result<ControlReply,Error>)->Void) {
        pollLock.lock()
        guard !polling else {pollLock.unlock();return}
        polling=true;pollLock.unlock()
        queue.async { [self] in
            defer {pollLock.lock();polling=false;pollLock.unlock()}
            guard ready else{return}
            do {completion(.success(try perform(ControlRequest("status"),allowAuthorization:false)))}
            catch {completion(.failure(error))}
        }
    }
    private func perform(_ request:ControlRequest,allowAuthorization:Bool) throws ->ControlReply {
        try request.validate()
        if channel==nil {
            guard allowAuthorization else {throw ScopeError.message("原生控制会话尚未连接")}
            let helper=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ThermalScopeHelper").path
            guard FileManager.default.isExecutableFile(atPath:helper) else {throw ScopeError.message("找不到原生辅助程序，请运行完整应用包")}
            var fd:Int32 = -1
            let status=helper.withCString {ts_privileged_session_launch($0,getpid(),getuid(),&fd)}
            guard status==0,fd>=0 else {throw ScopeError.message(status == -60006 ? "用户取消了系统授权":"原生授权未完成（\(status)）")}
            signal(SIGPIPE,SIG_IGN);channel=ControlChannel(fd:fd)
        }
        do {
            try channel!.send(request)
            guard let data=try channel!.readLine() else {throw ScopeError.message("原生辅助程序已断开，风扇恢复已请求")}
            let reply=try JSONDecoder().decode(ControlReply.self,from:data)
            ready=true;return reply
        } catch {
            if let channel {close(channel.fd)}
            channel=nil;ready=false;throw error
        }
    }
    func shutdown() {
        queue.async { [self] in
            if let channel {
                try? channel.send(ControlRequest("shutdown"))
                close(channel.fd);self.channel=nil;ready=false
            }
        }
    }
}
