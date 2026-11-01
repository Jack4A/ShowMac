import Foundation
import ThermalCore

struct DiagnosticTests {
    func sample(_ second:Double,temp:Double?=60,gpu:Double?=nil,cpu:Double?=20,pressure:MemoryPressure? = .normal,thermal:Int=0,limited:Bool=false,lowPower:Bool=false,battery:Bool=false,known:Bool=true)->Snapshot {
        let sensors=(temp.map{[SensorReading(key:"TC0F",label:"CPU",celsius:$0)]} ?? [])+(gpu.map{[SensorReading(key:"TG0P",label:"GPU",celsius:$0)]} ?? [])
        return Snapshot(date:Date(timeIntervalSince1970:1000+second),cpuUsage:cpu,sensors:sensors,fans:[],speedLimit:known ? (limited ? 70:100):nil,schedulerLimit:known ? 100:nil,availableCPUs:known ? 12:nil,totalCPUs:12,thermalState:thermal,thermalWarning:nil,turbo:.disabledDriverLoaded,acPower:!battery,lowPower:lowPower,smcAvailable:temp != nil,memoryPressure:pressure)
    }
    func input(_ second:Double,sources:[DiagnosticSource]=[],duration:Double=60,age:Double=0,blockers:Int?=0)->DiagnosticInput {
        let s=sample(second)
        return DiagnosticInput(snapshot:s,sources:sources,processSeconds:duration,processDate:s.date.addingTimeInterval(-age),blockers:blockers)
    }
    func warm(_ engine:inout DiagnosticEngine)->DiagnosticReport {
        var report=DiagnosticReport()
        for second in stride(from:0.0,through:50.0,by:5) {report=engine.evaluate(input(second))}
        return report
    }
    func testNormalAndTurboIndependence() {
        var engine=DiagnosticEngine()
        expectEqual(engine.evaluate(input(0)).state,.sampling)
        for second in stride(from:5.0,through:50.0,by:5) {_=engine.evaluate(input(second))}
        let report=engine.evaluate(input(55))
        expectEqual(report.state,.stable);expectTrue(report.findings.isEmpty);expectEqual(report.attentionCount,0)
    }
    func testSustainedVersusShortCPU() {
        let source=DiagnosticSource(id:"app:1",name:"Build",averageCPU:150,currentCPU:110)
        var engine=DiagnosticEngine()
        expectFalse(engine.evaluate(input(0,sources:[source],duration:10)).findings.contains{$0.kind == .sustainedCPU})
        let report=engine.evaluate(input(5,sources:[source]))
        let finding=report.findings.first!
        expectEqual(finding.kind,.sustainedCPU);expectEqual(finding.action,.reviewApplication("app:1"));expectEqual(finding.confidence,.possible)
        expectEqual(report.state,.attention)
        expectFalse(engine.evaluate(input(10,sources:[source],age:30)).findings.contains{$0.kind == .sustainedCPU})
        let finished=DiagnosticSource(id:"app:1",name:"Build",averageCPU:150,currentCPU:0)
        expectFalse(engine.evaluate(input(15,sources:[finished])).findings.contains{$0.kind == .sustainedCPU})
    }
    func testHeatDurationAndGapReset() {
        var engine=DiagnosticEngine(),report=DiagnosticReport()
        for second in stride(from:0.0,through:25.0,by:5) {
            let s=sample(second,temp:95)
            report=engine.evaluate(DiagnosticInput(snapshot:s,processSeconds:60,processDate:s.date,blockers:0))
            expectFalse(report.findings.contains{$0.kind == .temperature})
        }
        let s=sample(30,temp:95)
        expectTrue(engine.evaluate(DiagnosticInput(snapshot:s,processSeconds:60,processDate:s.date,blockers:0)).findings.contains{$0.kind == .temperature})
        let gap=sample(70,temp:95)
        report=engine.evaluate(DiagnosticInput(snapshot:gap,processSeconds:0,processDate:gap.date,blockers:0))
        expectFalse(report.findings.contains{$0.kind == .temperature});expectEqual(report.state,.sampling)
        var startedLater=DiagnosticEngine()
        _=startedLater.evaluate(DiagnosticInput(snapshot:sample(0)))
        for time in stride(from:5.0,through:30.0,by:5) {
            let hot=sample(time,temp:95)
            expectFalse(startedLater.evaluate(DiagnosticInput(snapshot:hot)).findings.contains{$0.kind == .temperature})
        }
        expectTrue(startedLater.evaluate(DiagnosticInput(snapshot:sample(35,temp:95))).findings.contains{$0.kind == .temperature})
        var switched=DiagnosticEngine()
        for time in stride(from:0.0,through:25.0,by:5) {_=switched.evaluate(DiagnosticInput(snapshot:sample(time,temp:95)))}
        for time in stride(from:30.0,through:55.0,by:5) {
            expectFalse(switched.evaluate(DiagnosticInput(snapshot:sample(time,temp:60,gpu:90))).findings.contains{$0.kind == .temperature})
        }
        let gpu=switched.evaluate(DiagnosticInput(snapshot:sample(60,temp:60,gpu:90))).findings.first{$0.kind == .temperature}
        expectEqual(gpu?.subject,"GPU");expectEqual(gpu?.seconds,30)
    }
    func testElevatedTemperatureIsObservation() {
        var engine=DiagnosticEngine();_=warm(&engine)
        let sample=sample(55,temp:86)
        let report=engine.evaluate(DiagnosticInput(snapshot:sample,processSeconds:60,processDate:sample.date,blockers:0))
        expectEqual(report.state,.observing);expectEqual(report.attentionCount,0)
        expectTrue(report.findings.contains{$0.kind == .temperatureObservation && $0.severity == .information})
    }
    func testThermalAndMemoryPriorities() {
        var engine=DiagnosticEngine()
        let s=sample(0,pressure:.critical,thermal:3,limited:true)
        let report=engine.evaluate(DiagnosticInput(snapshot:s,sources:[.init(id:"load",name:"App",averageCPU:1000,currentCPU:1000)],processSeconds:60,processDate:s.date,blockers:0))
        expectEqual(report.findings.first?.kind,.thermalLimit);expectEqual(report.findings.first?.confidence,.confirmed)
        expectEqual(report.findings.first?.severity,.critical);expectTrue(report.findings.contains{$0.kind == .memoryPressure})
        let normal=sample(5,lowPower:true)
        expectFalse(engine.evaluate(DiagnosticInput(snapshot:normal,processSeconds:60,processDate:normal.date,blockers:0)).findings.contains{$0.kind == .memoryPressure})
        let policy=sample(10,limited:true,lowPower:true)
        let info=engine.evaluate(DiagnosticInput(snapshot:policy,processSeconds:60,processDate:policy.date,blockers:0)).findings.first{$0.kind == .performanceLimit}
        expectEqual(info?.severity,.information)
    }
    func testWakeAndDiskAreInformation() {
        var engine=DiagnosticEngine();_=warm(&engine)
        let source=DiagnosticSource(id:"backup",name:"Backup",averageCPU:10,currentCPU:10,averageDiskRate:25*1024*1024,currentDiskRate:10*1024*1024,diskSeconds:60)
        let report=engine.evaluate(input(55,sources:[source],blockers:2))
        expectEqual(report.attentionCount,0);expectEqual(report.state,.observing)
        expectEqual(report.findings.first{$0.kind == .diskActivity}?.action,.reviewApplication("backup"))
        expectEqual(report.findings.first{$0.kind == .wakeRequests}?.severity,.information)
        expectEqual(engine.evaluate(input(60,blockers:2)).state,.stable)
    }
    func testBatteryOnlyPreparesPlan() {
        var engine=DiagnosticEngine()
        let battery=sample(0,battery:true)
        let report=engine.evaluate(DiagnosticInput(snapshot:battery,processSeconds:60,processDate:battery.date,blockers:0,batteryPercent:20))
        expectEqual(report.findings.first{$0.kind == .batteryPolicy}?.action,.lowPowerPlan)
        let ac=sample(5)
        expectFalse(engine.evaluate(DiagnosticInput(snapshot:ac,processDate:ac.date,batteryPercent:20)).findings.contains{$0.kind == .batteryPolicy})
        let already=sample(10,lowPower:true,battery:true)
        expectFalse(engine.evaluate(DiagnosticInput(snapshot:already,processDate:already.date,batteryPercent:20)).findings.contains{$0.kind == .batteryPolicy})
    }
    func testMissingAndStaleNeverHealthy() {
        var engine=DiagnosticEngine();_=warm(&engine)
        let s=sample(55,temp:nil,cpu:nil,pressure:nil,known:false)
        let report=engine.evaluate(DiagnosticInput(snapshot:s))
        expectEqual(report.state,.partial)
        expectEqual(report.findings.first{$0.kind == .unavailable}?.confidence,.unavailable)
        let invalid=DiagnosticSource(id:"invalid",name:"Unknown",averageCPU:.nan,currentCPU:.infinity)
        expectFalse(engine.evaluate(input(60,sources:[invalid])).findings.contains{$0.kind == .sustainedCPU})
    }
    func testDiskCountersAndGroupedActivity() {
        expectEqual(ProcessCPU.rate(previous:0,current:100,elapsed:2,sameIdentity:true),50)
        expectNil(ProcessCPU.rate(previous:100,current:0,elapsed:1,sameIdentity:true))
        expectNil(ProcessCPU.rate(previous:0,current:100,elapsed:1,sameIdentity:false))
        var window=CPUActivityWindow()
        window.record([.init(id:"a",name:"A",cpu:0,diskRate:0)],at:0)
        window.record([.init(id:"a",name:"A",cpu:10,diskRate:100),.init(id:"a",name:"A",cpu:10,diskRate:200)],at:5)
        expectEqual(window.rows[0].averageDiskRate,300);expectEqual(window.rows[0].currentDiskRate,300)
        window.record([.init(id:"a",name:"A",cpu:10,diskRate:nil)],at:10)
        expectNil(window.rows[0].currentDiskRate)
    }
    func testBaselineUsesActualWriteTime() {
        let old=OptimizationMetric(date:Date(timeIntervalSince1970:1000),cpu:99,temperature:99,dischargeWatts:nil,source:.ac)
        let fresh=(0..<6).map {i in OptimizationMetric(date:Date(timeIntervalSince1970:10000+Double(i*5)),cpu:20,temperature:60,dischargeWatts:nil,source:.ac)}
        let baseline=OptimizationSummary.baseline([old]+fresh,before:Date(timeIntervalSince1970:10030))
        expectEqual(baseline.count,6);expectEqual(baseline.cpu,20)
        expectFalse(OptimizationSummary.baseline(fresh,before:nil).sufficient)
        let changed=OptimizationSummary((0..<6).map {i in OptimizationMetric(date:Date(timeIntervalSince1970:11000+Double(i*5)),cpu:70,temperature:50,dischargeWatts:nil,source:.ac)})
        expectEqual(baseline.assessment(after:changed),.loadChanged)
        let sourceChanged=OptimizationSummary((0..<6).map {i in OptimizationMetric(date:Date(timeIntervalSince1970:11000+Double(i*5)),cpu:20,temperature:50,dischargeWatts:10,source:.battery)})
        expectEqual(baseline.assessment(after:sourceChanged),.powerChanged)
    }
}
