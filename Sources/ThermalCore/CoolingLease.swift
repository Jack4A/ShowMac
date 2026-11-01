import Foundation

public protocol CoolingHardware: AnyObject {
    func fans() -> [FanReading]
    func target(_ id:Int) -> Double?
    func setTarget(_ id:Int,rpm:Double) throws
    func setManual(_ id:Int,_ manual:Bool) throws
}
extension SMC:CoolingHardware {
    public func target(_ id:Int)->Double? { number("F\(id)Tg") }
    public func setTarget(_ id:Int,rpm:Double) throws { try write("F\(id)Tg",number:rpm) }
}
public enum CoolingLease {
    public static func restoreAuto(_ hardware:CoolingHardware,ids:[Int]) throws {
        var errors:[String]=[]
        for id in ids {
            do { try hardware.setManual(id,false) } catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { throw ScopeError.message("恢复自动风扇失败："+errors.joined(separator:"；")) }
    }
    /// Some Intel SMCs overwrite target writes while automatic control owns the fan.
    /// Validate the inherited target before enabling manual mode, then write and verify.
    /// Callers must restore all fans on any activation failure.
    public static func validateInheritedTarget(_ hardware:CoolingHardware,fan:FanReading) throws {
        guard let low=fan.minimum,let high=fan.maximum,
              let target=hardware.target(fan.id),target.isFinite,target>=low,target<=high else {
            throw ScopeError.message("风扇当前目标转速无法验证，已拒绝切换手动模式")
        }
    }
    /// Injected clock and cancellation make expiry/rollback testable without hardware writes.
    public static func run(hardware:CoolingHardware,duration:Double=300,
                           now:()->Double,isCancelled:()->Bool,wait:()->Void) throws {
        guard duration>0,duration<=300 else { throw ScopeError.message("散热会话必须在 5 分钟以内") }
        if isCancelled() { return }
        let fans=hardware.fans()
        guard !fans.isEmpty,fans.allSatisfy({$0.controllable && $0.manual==false}) else {
            throw ScopeError.message("请先恢复系统自动风扇并退出其他风扇控制软件；也可能是此机型没有可写的风扇接口。")
        }
        let targets=try fans.map { fan -> (Int,Double) in
            guard let maximum=fan.maximum,maximum.isFinite,maximum>0,maximum<=12000,
                  let minimum=fan.minimum,minimum.isFinite,minimum>=0,minimum<=maximum else {
                throw ScopeError.message("风扇额定转速无法验证，已拒绝控制")
            }
            return (fan.id,maximum)
        }
        for fan in fans { try validateInheritedTarget(hardware,fan:fan) }
        let ids=fans.map(\.id),deadline=now()+duration
        do {
            for (id,rpm) in targets {
                guard !isCancelled(),now()<deadline else { throw ScopeError.message("散热会话已取消或超时") }
                try hardware.setManual(id,true)
                try hardware.setTarget(id,rpm:rpm)
            }
            while now()<deadline && !isCancelled() {
                let actualFans=hardware.fans()
                for (id,rpm) in targets {
                    guard actualFans.first(where:{$0.id==id})?.manual==true,
                          let target=hardware.target(id),abs(target-rpm)<2 else {
                        throw ScopeError.message("检测到风扇状态改变或无法读取，散热会话已停止")
                    }
                }
                wait()
            }
        } catch {
            let originalError=error
            do { try restoreAuto(hardware,ids:ids) }
            catch { throw ScopeError.message("\(originalError.localizedDescription)；\(error.localizedDescription)") }
            throw originalError
        }
        try restoreAuto(hardware,ids:ids)
    }
}
