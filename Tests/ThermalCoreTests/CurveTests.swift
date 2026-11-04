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
        try FanCurve(points:[.init(40,20),.init(90,80)]).validate()
    }
    func testContinuousEditingAndPersistence() throws {
        var curve=FanCurve.balanced
        curve.movePoint(2,temperature:61.375,percent:37.625)
        try curve.validate()
        expectEqual(curve.points[2].temperature,61.375)
        expectEqual(curve.points[2].percent,37.625)
        let restored=try JSONDecoder().decode(FanCurve.self,from:JSONEncoder().encode(curve))
        expectEqual(restored,curve)
        let before=curve
        curve.movePoint(2,temperature:.nan,percent:50)
        curve.movePoint(99,temperature:60,percent:50)
        expectEqual(curve,before)
        curve.movePoint(2,temperature:500,percent:500)
        try curve.validate()
        expectEqual(curve.points[2].temperature,78)
        expectEqual(curve.points[2].percent,80)
        // Decimal neighbors must remain editable at the exact two-degree boundary.
        var decimal=FanCurve(points:[.init(40.1,10),.init(60.1,30),.init(80.1,70)])
        decimal.movePoint(1,temperature:0,percent:20)
        try decimal.validate()
        expectEqual(decimal.points[1].temperature,42.1,accuracy:1e-9)
    }
    func testMaximumPointLowersCurveCeiling() throws {
        var curve=FanCurve.balanced
        curve.movePoint(4,temperature:88.325,percent:35.25)
        try curve.validate()
        expectEqual(curve.points.last!.temperature,88.325)
        expectEqual(curve.percent(at:90),35.25)
        expectTrue(curve.points.allSatisfy{$0.percent<=35.25})
        expectEqual(curve.points[1].percent,25)
        curve.movePoint(4,temperature:100,percent:-20)
        try curve.validate()
        expectEqual(curve.points.last!.temperature,90)
        expectTrue(curve.points.allSatisfy{$0.percent==0})
        curve.movePoint(4,temperature:90,percent:150)
        try curve.validate()
        expectEqual(curve.points.last!.percent,100)
    }
    func testCappedCurveStillUsesThermalProtection() throws {
        let fans=FakeFans();var clock=0.0
        var curve=FanCurve.balanced
        curve.movePoint(4,temperature:90,percent:45)
        var targets:[Double]=[],protection:[Bool]=[]
        try CurveLease.run(hardware:fans,curve:curve,duration:4,sample:{self.snapshot(clock<2 ? 90:93)},now:{clock},isCancelled:{false},wait:{clock+=2},onUpdate:{progress in
            targets.append(progress.targets[0].rpm)
            protection.append(progress.protectionActive)
        })
        expectEqual(targets,[3465,5500])
        expectEqual(protection,[false,true])
        expectEqual(fans.modes,[false,false])
    }
    func testCPUAndGPUShareOneCurveUsingHighestTemperature() throws {
        let sample=snapshot(55,gpu:82)
        expectEqual(CurveSensor.cpu.temperature(in:sample),55)
        expectEqual(CurveSensor.gpu.temperature(in:sample),82)
        expectEqual(CurveSensor.hottest.temperature(in:sample),82)
        var curve=FanCurve(points:[.init(40,10),.init(65,50),.init(80,100)])
        curve.sensor = .hottest
        let fans=FakeFans();var clock=0.0,progress:[FanControlProgress]=[]
        try CurveLease.run(hardware:fans,curve:curve,duration:2,sample:{sample},now:{clock},isCancelled:{false},wait:{clock+=2},onUpdate:{progress.append($0)})
        expectEqual(progress.first?.targets.first?.rpm,5500)
        expectEqual(progress.first?.protectionActive,false)
        expectEqual(fans.modes,[false,false])
        expectEqual(CurveSensor.hottest.temperature(in:snapshot(84,gpu:55)),84)
        expectEqual(CurveSensor.hottest.temperature(in:snapshot(60)),60)
    }
    func testGPUCurveDoesNotIgnoreOtherComponentProtection() throws {
        var curve=FanCurve(points:[.init(40,0),.init(80,30)])
        curve.sensor = .gpu
        let fans=FakeFans();var clock=0.0,progress:[FanControlProgress]=[]
        try CurveLease.run(hardware:fans,curve:curve,duration:4,sample:{self.snapshot(clock<2 ? 60:93,gpu:60)},now:{clock},isCancelled:{false},wait:{clock+=2},onUpdate:{progress.append($0)})
        expectEqual(progress[0].protectionActive,false)
        expectTrue(progress[0].targets.allSatisfy{$0.rpm<5500})
        expectEqual(progress[1].protectionActive,true)
        expectTrue(progress[1].targets.allSatisfy{$0.rpm==5500})
        expectEqual(fans.modes,[false,false])
        let missing=FakeFans();clock=0
        expectThrows(try CurveLease.run(hardware:missing,curve:curve,duration:4,sample:{self.snapshot(60,gpu:clock<2 ? 60:nil)},now:{clock},isCancelled:{false},wait:{clock+=2}))
        expectEqual(missing.modes,[false,false])
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
