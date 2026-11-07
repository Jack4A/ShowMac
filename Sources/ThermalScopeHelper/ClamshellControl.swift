import Foundation
import Darwin
import CSMC
import ThermalCore

/// Both activation and emergency recovery use the same exclusive lock. A dead
/// guard's parent must not restore over a newly started ShowMac session.
private func clamshellLock() throws ->Int32? {
    let fd=open("/var/run/showmac-clamshell.lock",O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0o600)
    guard fd>=0 else {throw ScopeError.message("无法建立合盖运行会话")}
    var info=stat()
    guard fstat(fd,&info)==0,info.st_uid==0,info.st_mode & S_IFMT == S_IFREG,info.st_mode & 0o077==0 else {
        close(fd);throw ScopeError.message("无法建立合盖运行会话")
    }
    if flock(fd,LOCK_EX|LOCK_NB) != 0 {
        let busy=errno==EWOULDBLOCK;close(fd)
        if busy {return nil}
        throw ScopeError.message("无法建立合盖运行会话")
    }
    return fd
}
private func recoverAfterGuardExit(owned:Bool) throws ->Bool {
    guard let fd=try clamshellLock() else{return false}
    defer{close(fd)}
    // A startup acknowledgement may be lost after pmset applies the write.
    // The prepared recovery job is proof that rollback was armed beforehand.
    guard owned || ClamshellRecovery.isPrepared else{return false}
    try NativeClamshellPower.writeSleepDisabled(false)
    try ClamshellRecovery.clear()
    return true
}

/// Runs separately from the fan helper. Losing the parent IPC connection also
/// releases the override, including when the parent helper is force-terminated.
func runClamshellGuard(_ args:[String]) throws {
    guard geteuid()==0,args.count==5,let owner=Int32(args[2]),let uid=UInt32(args[3]),uid>0,
          let parent=Int32(args[4]),parent>1,getppid()==parent,ts_owner_alive(owner,uid)==1 else {
        throw ScopeError.message("原生授权会话身份验证失败")
    }
    signal(SIGPIPE,SIG_IGN);ts_install_stop_handlers()
    let output=ControlChannel(fd:STDOUT_FILENO)
    guard let lockFD=try clamshellLock() else {throw ScopeError.message("合盖运行会话已被占用")}
    defer{close(lockFD)}
    let lease=ClamshellLease(power:NativeClamshellPower())
    func send(_ status:ClamshellStatus) {
        var reply=ControlReply(ok:!status.failed,message:status.message);reply.clamshell=status
        try? output.send(reply)
    }
    var reason="合盖运行已关闭"
    var failed=false
    do {
        // Verify eligibility before preparing any privileged recovery files.
        let state=try NativeClamshellPower.readEnvironment()
        if let reason=state.unavailableReason {throw ScopeError.message(reason)}
        guard state.sleepDisabled==false else {throw ScopeError.message("其他程序已禁止系统休眠，请先关闭其防休眠功能")}
        try ClamshellRecovery.prepare()
        try lease.start()
        send(ClamshellStatus(active:true,message:"合盖运行中 · 仅接电"))
        while true {
            if ts_should_stop() != 0 || getppid() != parent || ts_owner_alive(owner,uid) != 1 {break}
            if let stop=try lease.stopReason() {reason=stop;break}
            var descriptor=pollfd(fd:STDIN_FILENO,events:Int16(POLLIN|POLLHUP),revents:0)
            let result=poll(&descriptor,1,500)
            if result<0 {if errno==EINTR {continue};break}
            // EOF, a stop byte or a broken pipe all end this session.
            if result>0 {break}
        }
    } catch {reason=error.localizedDescription;failed=true}
    // Keep retrying restoration while this root guard is alive. Never exit
    // claiming success after a failed restore; the main helper reports it too.
    while lease.ownsOverride {
        do {try lease.stop()} catch {
            send(ClamshellStatus(active:true,message:error.localizedDescription,failed:true))
            usleep(500_000)
        }
    }
    if (try? NativeClamshellPower.readEnvironment().sleepDisabled)==false {
        do {try ClamshellRecovery.clear()} catch {reason=error.localizedDescription;failed=true}
    }
    send(ClamshellStatus(message:reason,failed:failed))
}

final class ClamshellController {
    private let lock=NSLock()
    private var process:Process?
    private var stopPipe:FileHandle?
    private var current=ClamshellStatus()
    private let owner:Int32
    private let uid:UInt32
    init(owner:Int32,uid:UInt32) {self.owner=owner;self.uid=uid}
    func status()->ClamshellStatus {lock.lock();defer{lock.unlock()};return current}
    func start() throws {
        lock.lock()
        if process != nil {let status=current;lock.unlock();if status.failed {throw ScopeError.message(status.message)};return}
        lock.unlock()
        let child=Process(),input=Pipe(),output=Pipe()
        child.executableURL=URL(fileURLWithPath:CommandLine.arguments[0])
        child.arguments=["clamshell-guard",String(owner),String(uid),String(getpid())]
        child.standardInput=input;child.standardOutput=output;child.standardError=FileHandle.nullDevice
        try child.run()
        input.fileHandleForReading.closeFile();output.fileHandleForWriting.closeFile()
        let channel=ControlChannel(fd:output.fileHandleForReading.fileDescriptor)
        var startupError:Error?
        lock.lock();process=child;stopPipe=input.fileHandleForWriting;lock.unlock()
        do {
            guard let data=try channel.readLine(timeout:12) else {throw ScopeError.message("合盖运行未启动，请检查是否存在其他运行会话")}
            let reply=try JSONDecoder().decode(ControlReply.self,from:data)
            if let status=reply.clamshell {lock.lock();current=status;lock.unlock()}
            guard reply.ok,reply.clamshell?.active==true else {throw ScopeError.message(reply.message)}
        } catch {
            input.fileHandleForWriting.closeFile()
            startupError=error
        }
        DispatchQueue.global(qos:.utility).async { [self] in
            // Read repeated restoration failures without blocking the session
            // command channel. Read timeouts merely recheck the live process.
            while child.isRunning {
                do {
                    if let data=try channel.readLine(timeout:1),let reply=try? JSONDecoder().decode(ControlReply.self,from:data),let status=reply.clamshell {
                        lock.lock();current=status;lock.unlock()
                    } else {break}
                } catch {continue}
            }
            child.waitUntilExit()
            // The final frame can be buffered immediately before process exit.
            if let data=try? channel.readLine(timeout:1),let reply=try? JSONDecoder().decode(ControlReply.self,from:data),let status=reply.clamshell {
                lock.lock();current=status;lock.unlock()
            }
            output.fileHandleForReading.closeFile()
            lock.lock()
            if current.active || ClamshellRecovery.isPrepared {
                // A killed watchdog cannot run defer/cleanup. The still-live
                // session helper takes responsibility for the runtime override.
                do {
                    let restored=try recoverAfterGuardExit(owned:current.active)
                    current=ClamshellStatus(message:restored ? "合盖运行会话已中断，系统休眠已恢复":"合盖运行已关闭")
                }
                catch {current=ClamshellStatus(active:true,message:error.localizedDescription,failed:true)}
            }
            stopPipe?.closeFile();stopPipe=nil;process=nil
            lock.unlock()
        }
        if let startupError {throw startupError}
    }
    func stop() throws {
        lock.lock();stopPipe?.closeFile();stopPipe=nil;let child=process;lock.unlock()
        let deadline=ProcessInfo.processInfo.systemUptime+12
        while child?.isRunning==true,ProcessInfo.processInfo.systemUptime<deadline {usleep(20_000)}
        if child?.isRunning==true {throw ScopeError.message("尚未确认恢复系统休眠，正在重试")}
        // Wait for the reader to publish the final status before acknowledging.
        while true {
            lock.lock();let pending=process != nil;lock.unlock()
            if !pending || ProcessInfo.processInfo.systemUptime>=deadline {break};usleep(20_000)
        }
        let status=status()
        if status.active {
            _=try recoverAfterGuardExit(owned:true)
            lock.lock();current=ClamshellStatus();lock.unlock()
        }
    }
}
