import Foundation
import ThermalCore

final class CurveTests {
    func snapshot(_ temperature:Double?=60,gpu:Double?=nil,storage:Double?=nil)->Snapshot {
        var sensors:[SensorReading]=[]
        if let t=temperature { sensors.append(.init(key:"TC0F",label:"CPU",celsius:t)) }
        if let t=gpu { sensors.append(.init(key:"TG0P",label:"GPU",celsius:t)) }
        if let t=storage { sensors.append(.init(key:"TH0F",label:"SSD",celsius:t)) }
        return Snapshot(date:Date(),cpuUsage:10,sensors:sensors,fans:[],speedLimit:100,schedulerLimit:100,availableCPUs:12,totalCPUs:12,thermalState:0,thermalWarning:nil,turbo:.driverNotLoaded,acPower:true,lowPower:false,smcAvailable:true)
    }
    func testPresetValidationAndInterpolation() throws {
        for curve in [FanCurve.quiet,.balanced,.performance] { try curve.validate();expectEqual(curve.percent(at:100),100);expectTrue(curve.percent(at:60)<=curve.percent(at:70)) }
        expectEqual(FanCurve.balanced.percent(at:62.5),40,accuracy:0.01)
        expectThrows(try FanCurve(points:[.init(50,80),.init(70,10),.init(90,100)]).validate())
        expectThrows(try FanCurve(points:[.init(40,20),.init(95,100)]).validate())
        expectThrows(try FanCurve(points:[.init(40,20),.init(90,80)]).validate())
    }
    func testSafetyOverridesAndRatedRPM() {
        expectTrue(CurvePolicy.requiresMaximum(snapshot(93)))
        expectTrue(CurvePolicy.requiresMaximum(snapshot(60,gpu:89)))
        expectTrue(CurvePolicy.requiresMaximum(snapshot(60,storage:76)))
        expectFalse(CurvePolicy.requiresMaximum(snapshot(60,gpu:65,storage:40)))
        expectEqual(CurvePolicy.rpm(percent:0,minimum:1800,maximum:5500),1800)
        expectEqual(CurvePolicy.rpm(percent:100,minimum:1800,maximum:5500),5500)
        expectEqual(CurvePolicy.smooth(desired:100,previous:20),100)
        expectEqual(CurvePolicy.smooth(desired:20,previous:80),76)
    }
    func testDynamicCurveAndCleanup() throws {
        let fans=FakeFans();fans.rejectAutomaticTargetWrites=true;var clock=0.0
        try CurveLease.run(hardware:fans,curve:.balanced,duration:4,sample:{self.snapshot(clock<2 ? 60:95)},now:{clock},isCancelled:{false},wait:{clock+=2})
        expectEqual(fans.targets,[5500,5500]);expectEqual(fans.modes,[false,false])
    }
    func testMissingSensorRestoresAutomatic() {
        let fans=FakeFans();var clock=0.0
        expectThrows(try CurveLease.run(hardware:fans,curve:.balanced,duration:10,sample:{self.snapshot(clock<2 ? 60:nil)},now:{clock},isCancelled:{false},wait:{clock+=2}))
        expectEqual(fans.modes,[false,false])
    }
    func testGPUUnavailableAndPartialWriteFailure() {
        let fans=FakeFans();var curve=FanCurve.balanced;curve.sensor = .gpu
        expectThrows(try CurveLease.run(hardware:fans,curve:curve,sample:{self.snapshot()},now:{0},isCancelled:{false},wait:{}))
        expectFalse(fans.writes.contains("mode0=true"))
        fans.failEnable=1
        expectThrows(try CurveLease.run(hardware:fans,curve:.balanced,sample:{self.snapshot()},now:{0},isCancelled:{false},wait:{}))
        expectEqual(fans.modes,[false,false])
    }
    func testStorageClassificationDoesNotMislabelPalmRest() {
        expectEqual(SensorCategory.category(for:"TH0F"),.storage)
        expectEqual(SensorCategory.category(for:"TGDF"),.gpu)
        expectEqual(SensorCategory.category(for:"Ts0P"),.other)
        expectEqual(SensorCategory.category(for:"TS0P"),.other)
    }
}
