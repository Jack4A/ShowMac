import Foundation

/// Owns only a bounded fan-control session. Never changes fan minima or power settings.
/// The injected I/O keeps acquisition and rollback testable without touching hardware.
public final class AppleSiliconFanControl {
    private let read:(String)->Double?
    private let write:(String,Double)throws->Void
    private let wait:()->Void
    private let now:()->Double
    private var originals:[Int:(String,Double)]=[:]
    private var unlockOriginal:Double?
    public init(read:@escaping(String)->Double?,write:@escaping(String,Double)throws->Void,wait:@escaping()->Void,now:@escaping()->Double = {ProcessInfo.processInfo.systemUptime}) {
        self.read=read;self.write=write;self.wait=wait;self.now=now
    }
    public func modeKey(_ id:Int)->String? {
        guard (0..<10).contains(id) else{return nil}
        return ["F\(id)Md","F\(id)md"].first {read($0) != nil}
    }
    public func setManual(_ id:Int,_ manual:Bool) throws {
        guard let key=modeKey(id) else {throw ScopeError.message("此风扇没有可识别的 Apple Silicon 模式接口")}
        if !manual {try restore(id,key:key);return}
        guard let original=read(key),original==0 || original==3 else {
            throw ScopeError.message("风扇未处于系统自动，请先退出其他风扇控制程序")
        }
        if originals.isEmpty,let unlock=read("Ftst"),unlock != 0 {
            throw ScopeError.message("风扇控制交接已被占用，请先恢复系统自动")
        }
        originals[id]=(key,original)
        do {
            do {try write(key,1);return} catch {
                // Some M3/M4 firmware refuses mode writes until thermalmonitord yields.
                guard let unlock=read("Ftst"),unlock==0 || unlockOriginal != nil else {throw error}
                if unlockOriginal==nil {
                    unlockOriginal=unlock
                    try write("Ftst",1)
                }
                var last=error
                let deadline=now()+4
                for _ in 0..<40 {
                    guard now()<deadline else {break}
                    wait()
                    do {try write(key,1);return} catch {last=error}
                }
                throw last
            }
        } catch {
            let originalError=error
            do {try restore(id,key:key)} catch {
                throw ScopeError.message("\(originalError.localizedDescription)；恢复自动风扇失败：\(error.localizedDescription)")
            }
            throw originalError
        }
    }
    private func restore(_ id:Int,key:String) throws {
        let original=originals[id]?.1 ?? 0
        var failure:Error?
        do {try write(key,original)} catch {failure=error}
        // Release the global handoff even when the per-fan write failed.
        if originals.keys.allSatisfy({$0==id}),let unlock=unlockOriginal {
            do {try write("Ftst",unlock);unlockOriginal=nil} catch {failure=error}
        }
        // Other owned fans may still legitimately need the shared handoff.
        let hasOtherFans=originals.keys.contains{$0 != id}
        guard SMCVerification.manualState(local:read(key),flags:nil,id:id,handoff:hasOtherFans ? nil:read("Ftst"))==false,
              unlockOriginal==nil || hasOtherFans else {
            throw failure ?? ScopeError.message("未能确认风扇恢复系统自动")
        }
        originals.removeValue(forKey:id)
    }
}

public enum FanControlPolicy {
    /// The privileged helper independently enforces this allowlist.
    public static func validate(_ request:ControlRequest,appleSilicon:Bool) throws {
        try request.validate()
        guard appleSilicon else{return}
        let allowed=["hello","status","auto","test-fans","shutdown"]
        guard allowed.contains(request.command) || (request.command=="profile" && request.profile=="custom") else {
            throw ScopeError.message("Apple Silicon 当前仅支持独立风扇控制，不支持 Intel 睿频或电源设置控制")
        }
    }
}
