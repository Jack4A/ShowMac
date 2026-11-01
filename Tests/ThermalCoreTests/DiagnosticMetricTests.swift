import Foundation
import ThermalCore

extension DiagnosticTests {
    func testMetricsMatchRuleEvidence() {
        var engine=DiagnosticEngine()
        let first=DiagnosticSource(id:"build",name:"Build",averageCPU:180,currentCPU:80,averageDiskRate:30*1024*1024,currentDiskRate:10*1024*1024,diskSeconds:40)
        let second=DiagnosticSource(id:"idle",name:"Idle",averageCPU:10,currentCPU:5)
        let s=sample(0,temp:82,gpu:72,cpu:25)
        let report=engine.evaluate(DiagnosticInput(snapshot:s,sources:[second,first],processSeconds:50,processDate:s.date,blockers:0))
        expectEqual(report.date,s.date);expectEqual(report.metrics?.cpuUsage,25)
        expectEqual(report.metrics?.cpuTemperature,82);expectEqual(report.metrics?.gpuTemperature,72)
        expectEqual(report.metrics?.cpuSource,first);expectEqual(report.metrics?.diskSource,first)
        expectEqual(report.metrics?.processSeconds,50);expectEqual(report.metrics?.performanceLimited,false)
        let finding=report.findings.first{$0.kind == .sustainedCPU}
        expectEqual(finding?.value,report.metrics?.cpuSource?.averageCPU)
        expectEqual(finding?.action,.reviewApplication("build"))
    }
    func testStaleAndInvalidMetricsStayUnavailable() {
        var engine=DiagnosticEngine()
        let source=DiagnosticSource(id:"old",name:"Old",averageCPU:200,currentCPU:150,averageDiskRate:50*1024*1024,currentDiskRate:20*1024*1024,diskSeconds:40)
        let stale=engine.evaluate(input(0,sources:[source],age:20))
        expectEqual(stale.metrics?.processFresh,false);expectEqual(stale.metrics?.processSeconds,0)
        expectTrue(stale.metrics?.cpuSource==nil);expectTrue(stale.metrics?.diskSource==nil)
        expectEqual(stale.metrics?.cpuTemperature,60)
        let missing=sample(5,temp:nil,cpu:nil,pressure:nil,known:false)
        let empty=engine.evaluate(DiagnosticInput(snapshot:missing))
        expectTrue(empty.metrics?.cpuUsage==nil);expectTrue(empty.metrics?.cpuTemperature==nil)
        expectTrue(empty.metrics?.memoryPressure==nil);expectTrue(empty.metrics?.performanceLimited==nil)
        let invalid=sample(10,temp:.infinity,cpu:.nan)
        let report=engine.evaluate(DiagnosticInput(snapshot:invalid,sources:[source],processSeconds:.infinity,processDate:invalid.date))
        expectTrue(report.metrics?.cpuUsage==nil);expectTrue(report.metrics?.cpuTemperature==nil)
        expectEqual(report.metrics?.processSeconds,0)
        expectFalse(report.findings.contains{$0.kind == .sustainedCPU})
    }
}
