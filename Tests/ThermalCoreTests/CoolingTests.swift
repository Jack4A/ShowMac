import Foundation
import ThermalCore

final class FakeFans:CoolingHardware {
    var modes=[false,false]
    var targets=[2000.0,2000.0]
    var writes:[String]=[]
    var rejectAutomaticTargetWrites=false
    var failTarget:Int?
    var failEnable:Int?
    var failRestore:Int?
    var maxRPM=5500.0
    func fans()->[FanReading] {
        (0..<2).map { FanReading(id:$0,rpm:targets[$0],minimum:1800,maximum:maxRPM,manual:modes[$0],controllable:true) }
    }
    func target(_ id:Int)->Double? { targets[id] }
    func setTarget(_ id:Int,rpm:Double) throws {
        writes.append("target\(id)")
        if failTarget==id || (rejectAutomaticTargetWrites && !modes[id]) { throw ScopeError.message("target write rejected") }
        targets[id]=rpm
    }
    func setManual(_ id:Int,_ manual:Bool) throws {
        writes.append("mode\(id)=\(manual)")
        if (manual && failEnable==id) || (!manual && failRestore==id) { throw ScopeError.message("simulated write failure") }
        modes[id]=manual
    }
}
final class CoolingTests {
    func testExpirationRestoresAllAndManualPrecedesTarget() throws {
        let fans=FakeFans();var now=0.0
        try CoolingLease.run(hardware:fans,duration:2,now:{now},isCancelled:{false},wait:{now+=1})
        expectEqual(fans.writes,["mode0=true","target0","mode1=true","target1","mode0=false","mode1=false"])
        expectEqual(fans.modes,[false,false])
        expectEqual(now,2)
    }
    func testSMCWithAutomaticTargetOwnership() throws {
        let fans=FakeFans();fans.rejectAutomaticTargetWrites=true;var now=0.0
        try CoolingLease.run(hardware:fans,duration:1,now:{now},isCancelled:{false},wait:{now+=1})
        expectEqual(fans.modes,[false,false])
        fans.failTarget=1
        expectThrows(try CoolingLease.run(hardware:fans,now:{0},isCancelled:{false},wait:{}))
        expectEqual(fans.modes,[false,false])
        fans.failTarget=nil;fans.targets[0]=0;fans.writes=[]
        expectThrows(try CoolingLease.run(hardware:fans,now:{0},isCancelled:{false},wait:{}))
        expectTrue(fans.writes.isEmpty)
    }
    func testPartialWriteFailureRollsBackBothFans() {
        let fans=FakeFans();fans.failEnable=1
        expectThrows(try CoolingLease.run(hardware:fans,now:{0},isCancelled:{false},wait:{}))
        expectEqual(fans.modes,[false,false])
        expectEqual(Array(fans.writes.suffix(2)),["mode0=false","mode1=false"])
    }
    func testCancellationBeforeStartHasNoWrites() throws {
        let fans=FakeFans()
        try CoolingLease.run(hardware:fans,now:{0},isCancelled:{true},wait:{})
        expectTrue(fans.writes.isEmpty)
    }
    func testOwnerExitOrStopRestoresAutomatic() throws {
        let fans=FakeFans();var stopped=false
        try CoolingLease.run(hardware:fans,now:{0},isCancelled:{stopped},wait:{stopped=true})
        expectEqual(fans.modes,[false,false])
    }
    func testSleepDoesNotExtendLease() throws {
        let fans=FakeFans();var now=0.0;var waits=0
        try CoolingLease.run(hardware:fans,now:{now},isCancelled:{false},wait:{now+=3600;waits+=1})
        expectEqual(waits,1)
        expectEqual(fans.modes,[false,false])
    }
    func testManualModeAndInvalidRPMRefuseBeforeWrites() {
        let fans=FakeFans();fans.modes[0]=true
        expectThrows(try CoolingLease.run(hardware:fans,now:{0},isCancelled:{false},wait:{}))
        expectTrue(fans.writes.isEmpty)
        fans.modes[0]=false;fans.maxRPM=Double.nan
        expectThrows(try CoolingLease.run(hardware:fans,now:{0},isCancelled:{false},wait:{}))
        expectTrue(fans.writes.isEmpty)
    }
    func testRestoreFailureStillAttemptsOtherFan() {
        let fans=FakeFans();fans.failRestore=0
        expectThrows(try CoolingLease.restoreAuto(fans,ids:[0,1]))
        expectEqual(fans.writes,["mode0=false","mode1=false"])
    }
}
