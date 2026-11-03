import Foundation
import ThermalCore

private final class FakeFanRegisters {
    var values:[String:Double] = ["F0Md":0,"F1Md":3,"Ftst":0]
    var writes:[String]=[]
    var clock=0.0
    var needsUnlock=false
    var refuseManual=false
    var failRelease=false
    var failModeRestore=false
    var slowWrites=false
    func write(_ key:String,_ value:Double) throws {
        writes.append("\(key)=\(Int(value))")
        if slowWrites {clock+=2}
        if key.hasSuffix("Md") || key.hasSuffix("md") {
            if value==1 && (refuseManual || (needsUnlock && values["Ftst"] != 1)) {throw ScopeError.message("mode denied")}
            if value != 1 && failModeRestore {throw ScopeError.message("restore denied")}
        }
        if key=="Ftst",value==0,failRelease {throw ScopeError.message("handoff release denied")}
        values[key]=value
        if key=="Ftst",value==0 {
            for key in Array(values.keys) where key.hasSuffix("Md") || key.hasSuffix("md") {values[key]=0}
        }
    }
    func controller()->AppleSiliconFanControl {
        AppleSiliconFanControl(read:{self.values[$0]},write:{try self.write($0,$1)},wait:{self.clock+=0.1},now:{self.clock})
    }
}
final class AppleSiliconFanTests {
    func testDirectAndOriginalModeRestore() throws {
        let io=FakeFanRegisters(),control=io.controller()
        try control.setManual(1,true);expectEqual(io.values["F1Md"],1)
        try control.setManual(1,false);expectEqual(io.values["F1Md"],3)
        expectFalse(io.writes.contains{$0.hasPrefix("Ftst")})
        expectTrue(io.writes.allSatisfy{$0.hasPrefix("F1Md=")})
    }
    func testHandoffSharedUntilAllFansRestore() throws {
        let io=FakeFanRegisters();io.needsUnlock=true
        let control=io.controller()
        try control.setManual(0,true);try control.setManual(1,true)
        expectEqual(io.values["Ftst"],1)
        try control.setManual(0,false);expectEqual(io.values["Ftst"],1)
        try control.setManual(1,false);expectEqual(io.values["Ftst"],0)
        expectEqual(io.writes.filter{$0=="Ftst=1"}.count,1)
        expectEqual(io.values["F0Md"],0);expectEqual(io.values["F1Md"],0)
    }
    func testFailedAcquisitionReleasesHandoff() {
        let io=FakeFanRegisters();io.refuseManual=true
        let control=io.controller()
        expectThrows(try control.setManual(0,true))
        expectEqual(io.values["Ftst"],0);expectEqual(io.values["F0Md"],0)
        expectTrue(io.clock>=3.9 && io.clock<4.2)
    }
    func testExistingOwnerAndUnknownModesAreRejected() {
        let io=FakeFanRegisters(),control=io.controller()
        io.values["Ftst"]=1;expectThrows(try control.setManual(0,true));expectTrue(io.writes.isEmpty)
        io.values["Ftst"]=0;io.values["F0Md"]=2
        expectThrows(try control.setManual(0,true));expectTrue(io.writes.isEmpty)
        expectThrows(try control.setManual(10,true));expectTrue(io.writes.isEmpty)
    }
    func testReleaseAttemptedAfterModeRestoreFailure() throws {
        let io=FakeFanRegisters();io.needsUnlock=true;let control=io.controller()
        try control.setManual(0,true);io.failModeRestore=true
        try control.setManual(0,false)
        expectEqual(io.values["Ftst"],0);expectEqual(io.values["F0Md"],0)
    }
    func testReleaseFailureIsReportedAndRetryable() throws {
        let io=FakeFanRegisters();io.needsUnlock=true;let control=io.controller()
        try control.setManual(0,true);io.failRelease=true
        expectThrows(try control.setManual(0,false));expectEqual(io.values["Ftst"],1)
        io.failRelease=false;try control.setManual(0,false);expectEqual(io.values["Ftst"],0)
    }
    func testLowercaseAndNoHandoffFirmware() throws {
        let io=FakeFanRegisters();io.values=["F0md":0];let control=io.controller()
        try control.setManual(0,true);try control.setManual(0,false)
        expectEqual(io.values["F0md"],0);expectEqual(io.writes,["F0md=1","F0md=0"])
    }
    func testSlowWritesRespectDeadline() {
        let io=FakeFanRegisters();io.refuseManual=true;io.slowWrites=true
        expectThrows(try io.controller().setManual(0,true))
        expectTrue(io.writes.filter{$0=="F0Md=1"}.count<=3)
        expectEqual(io.values["Ftst"],0)
    }
    func testARMRequestBoundary() throws {
        for command in ["hello","status","auto","test-fans","shutdown"] {
            try FanControlPolicy.validate(ControlRequest(command),appleSilicon:true)
        }
        try FanControlPolicy.validate(ControlRequest("profile",profile:"custom",curve:.balanced),appleSilicon:true)
        for mode in ["eco","performance","quiet","balanced"] {
            expectThrows(try FanControlPolicy.validate(ControlRequest("profile",profile:mode),appleSilicon:true))
            try FanControlPolicy.validate(ControlRequest("profile",profile:mode),appleSilicon:false)
        }
        expectThrows(try FanControlPolicy.validate(ControlRequest("turbo-disable"),appleSilicon:true))
        expectThrows(try FanControlPolicy.validate(ControlRequest("turbo-enable"),appleSilicon:true))
        expectThrows(try FanControlPolicy.validate(ControlRequest("profile",profile:"custom"),appleSilicon:true))
        expectThrows(try FanControlPolicy.validate(ControlRequest("power-optimize",powerPlan:PowerOptimizationPlan(source:.ac)),appleSilicon:true))
    }
}
