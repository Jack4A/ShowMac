import Foundation
import Darwin
import IOKit
import CSMC

public struct ClamshellEnvironment:Equatable {
    public let portable:Bool
    public let acPower:Bool?
    public let sleepDisabled:Bool?
    public let thermalCritical:Bool
    public init(portable:Bool,acPower:Bool?,sleepDisabled:Bool?,thermalCritical:Bool=false) {
        self.portable=portable;self.acPower=acPower;self.sleepDisabled=sleepDisabled;self.thermalCritical=thermalCritical
    }
    public var unavailableReason:String? {
        if !portable {return "合盖运行仅适用于 MacBook"}
        if acPower != true {return "连接电源后可开启合盖运行"}
        if thermalCritical {return "系统热压力过高，合盖运行已停止"}
        if sleepDisabled==nil {return "此系统无法确认合盖运行状态"}
        return nil
    }
}
public struct ClamshellStatus:Codable,Equatable {
    public let active:Bool
    public let message:String
    public let failed:Bool
    public init(active:Bool=false,message:String="合盖运行已关闭",failed:Bool=false) {
        self.active=active;self.message=message;self.failed=failed
    }
}
public protocol ClamshellPowerAccess {
    func environment() throws ->ClamshellEnvironment
    func setSleepDisabled(_ disabled:Bool) throws
}
/// A temporary, exclusively owned override. The privileged watchdog controls its
/// lifetime. A boot recovery job is prepared before the privileged write.
public final class ClamshellLease {
    private let power:ClamshellPowerAccess
    public private(set) var ownsOverride=false
    public init(power:ClamshellPowerAccess) {self.power=power}
    public func start() throws {
        guard !ownsOverride else{return}
        let state=try power.environment()
        if let reason=state.unavailableReason {throw ScopeError.message(reason)}
        guard state.sleepDisabled==false else {throw ScopeError.message("其他程序已禁止系统休眠，请先关闭其防休眠功能")}
        // Mark ownership before attempting the write: a failed acknowledgement
        // must still roll back a write which may have reached the kernel.
        ownsOverride=true
        do {
            try power.setSleepDisabled(true)
            let applied=try power.environment()
            guard applied.sleepDisabled==true else {throw ScopeError.message("系统未确认合盖运行生效")}
            if let reason=applied.unavailableReason {throw ScopeError.message(reason)}
        } catch {
            let original=error
            do {try stop()} catch {throw ScopeError.message(original.localizedDescription+"；"+error.localizedDescription)}
            throw original
        }
    }
    public func stop() throws {
        guard ownsOverride else{return}
        if (try? power.environment().sleepDisabled) != false {try power.setSleepDisabled(false)}
        guard try power.environment().sleepDisabled==false else {throw ScopeError.message("尚未确认恢复系统休眠，正在重试")}
        ownsOverride=false
    }
    public func stopReason() throws ->String? {
        let state=try power.environment()
        if let reason=state.unavailableReason {return reason}
        if state.sleepDisabled != true {return "系统休眠设置已变化，合盖运行已停止"}
        return nil
    }
}
public struct NativeClamshellPower:ClamshellPowerAccess {
    public init() {}
    // Reading IOPMrootDomain checks the effective kernel state. Writing this
    // property directly requires an Apple-only entitlement on newer systems;
    // use the system's pmset executable with root authorization instead.
    public static func readEnvironment() throws ->ClamshellEnvironment {
        let root=try rootDomain();defer{IOObjectRelease(root)}
        func boolean(_ key:String)->Bool? {
            guard let value=IORegistryEntryCreateCFProperty(root,key as CFString,kCFAllocatorDefault,0)?.takeRetainedValue(),
                  CFGetTypeID(value)==CFBooleanGetTypeID() else{return nil}
            return (value as! CFBoolean)==kCFBooleanTrue
        }
        let source=ts_ac_power()
        return ClamshellEnvironment(portable:boolean("AppleClamshellState") != nil,
                                    acPower:source<0 ? nil:source==1,sleepDisabled:boolean("SleepDisabled"),
                                    thermalCritical:ProcessInfo.processInfo.thermalState == .critical)
    }
    public static func writeSleepDisabled(_ disabled:Bool) throws {
        guard geteuid()==0 else {throw ScopeError.message("合盖运行需要系统授权")}
        let result=try ProcessRunner.run("/usr/bin/pmset",["-a","disablesleep",disabled ? "1":"0"],timeout:8)
        guard result.status==0 else {throw ScopeError.message("系统拒绝更改合盖运行状态")}
        // powerd applies preferences asynchronously; acknowledge only readback.
        for _ in 0..<30 {
            if try readEnvironment().sleepDisabled==disabled {return}
            usleep(100_000)
        }
        throw ScopeError.message("系统未确认合盖运行生效")
    }
    private static func rootDomain() throws ->io_service_t {
        let root=IOServiceGetMatchingService(kIOMasterPortDefault,IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else {throw ScopeError.message("此系统无法确认合盖运行状态")}
        return root
    }
    public func environment() throws ->ClamshellEnvironment {try Self.readEnvironment()}
    public func setSleepDisabled(_ disabled:Bool) throws {try Self.writeSleepDisabled(disabled)}
}
