import Foundation
import ThermalCore

private final class FakeClamshellPower:ClamshellPowerAccess {
    var portable=true
    var ac:Bool?=true
    var disabled:Bool?=false
    var critical=false
    var writes:[Bool]=[]
    var failEnable=false
    var failRestore=false
    var ignoreEnable=false
    var unplugOnEnable=false
    func environment() throws ->ClamshellEnvironment {
        ClamshellEnvironment(portable:portable,acPower:ac,sleepDisabled:disabled,thermalCritical:critical)
    }
    func setSleepDisabled(_ value:Bool) throws {
        writes.append(value)
        if !value,failRestore {throw ScopeError.message("Restore failure")}
        if value,!ignoreEnable {disabled=true}
        if !value {disabled=false}
        if value,unplugOnEnable {ac=false}
        if value,failEnable {throw ScopeError.message("Write acknowledgement failure")}
    }
}
struct ClamshellTests {
    func testPreflightAndOtherOwners() {
        for variant in 0..<6 {
            let power=FakeClamshellPower(),lease=ClamshellLease(power:power)
            switch variant {
            case 0:power.portable=false
            case 1:power.ac=false
            case 2:power.ac=nil
            case 3:power.disabled=nil
            case 4:power.disabled=true
            default:power.critical=true
            }
            expectThrows(try lease.start());expectTrue(power.writes.isEmpty);expectFalse(lease.ownsOverride)
        }
    }
    func testVerifiedLifetimeAndRestoration() throws {
        let power=FakeClamshellPower(),lease=ClamshellLease(power:power)
        try lease.start();expectTrue(lease.ownsOverride);expectEqual(power.disabled,true)
        try lease.start();expectEqual(power.writes,[true]);expectNil(try lease.stopReason())
        power.ac=false;expectNotEqual(try lease.stopReason(),nil)
        try lease.stop();expectEqual(power.disabled,false);expectFalse(lease.ownsOverride)
        try lease.stop();expectEqual(power.writes,[true,false])
        power.ac=true;try lease.start();power.critical=true
        expectEqual(try lease.stopReason(),"系统热压力过高，合盖运行已停止")
        try lease.stop();expectFalse(lease.ownsOverride)
    }
    func testPartialAcquisitionRollsBack() {
        for variant in 0..<3 {
            let power=FakeClamshellPower(),lease=ClamshellLease(power:power)
            if variant==0 {power.failEnable=true}
            if variant==1 {power.ignoreEnable=true}
            if variant==2 {power.unplugOnEnable=true}
            expectThrows(try lease.start());expectFalse(lease.ownsOverride);expectEqual(power.disabled,false)
            expectEqual(power.writes,variant==1 ? [true]:[true,false])
        }
    }
    func testRestoreFailuresRemainRetryable() throws {
        let power=FakeClamshellPower(),lease=ClamshellLease(power:power)
        try lease.start();power.failRestore=true
        expectThrows(try lease.stop());expectTrue(lease.ownsOverride);expectEqual(power.disabled,true)
        power.failRestore=false;try lease.stop();expectFalse(lease.ownsOverride);expectEqual(power.disabled,false)
        try lease.start();power.disabled=false
        expectNotEqual(try lease.stopReason(),nil)
        let previous=power.writes;try lease.stop();expectEqual(power.writes,previous)
        power.failEnable=true;power.failRestore=true
        expectThrows(try lease.start());expectTrue(lease.ownsOverride)
        power.failRestore=false;try lease.stop();expectFalse(lease.ownsOverride)
    }
    func testProtocolAndOldReplies() throws {
        for command in ["clamshell-start","clamshell-stop"] {
            try FanControlPolicy.validate(ControlRequest(command),appleSilicon:true)
            try FanControlPolicy.validate(ControlRequest(command),appleSilicon:false)
            expectThrows(try ControlRequest(command,duration:600).validate())
            expectThrows(try ControlRequest(command,continuous:true).validate())
            expectThrows(try ControlRequest(command,profile:"custom",curve:.balanced).validate())
            expectThrows(try ControlRequest(command,powerPlan:PowerOptimizationPlan(source:.ac)).validate())
        }
        let old=try JSONDecoder().decode(ControlReply.self,from:Data("{\"ok\":true,\"message\":\"old\"}".utf8))
        expectNil(old.clamshell)
        var reply=old;reply.clamshell=ClamshellStatus(active:true,message:"running")
        let roundTrip=try JSONDecoder().decode(ControlReply.self,from:JSONEncoder().encode(reply))
        expectEqual(roundTrip.clamshell,reply.clamshell);expectNil(roundTrip.session)
    }
}
