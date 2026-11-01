import Foundation
import ThermalCore
import CSMC

final class CoreTests {
    func testNormalizedCPUUsageAndZeroDelta() {
        let old=CPUCounters(user:100,system:100,idle:200,nice:0)
        let next=CPUCounters(user:120,system:110,idle:270,nice:0)
        expectEqual(next.usage(since:old)!,30,accuracy:0.001)
        expectNil(old.usage(since:old))
    }
    func testCPUCounterRollover() {
        let old=CPUCounters(user:UInt32.max-4,system:0,idle:20,nice:0)
        let next=CPUCounters(user:5,system:0,idle:30,nice:0)
        expectEqual(next.usage(since:old)!,50,accuracy:0.001)
    }
    func sample(speed:Int?=100,scheduler:Int?=100,cores:Int?=12,thermal:Int=0,warning:Int?=nil,turbo:TurboState = .disabledDriverLoaded)->Snapshot {
        Snapshot(date:Date(timeIntervalSince1970:0),cpuUsage:nil,sensors:[],fans:[],speedLimit:speed,schedulerLimit:scheduler,availableCPUs:cores,totalCPUs:12,thermalState:thermal,thermalWarning:warning,turbo:turbo,acPower:nil,lowPower:false,smcAvailable:false)
    }
    func testTurboDisabledDoesNotImplySystemThrottling() {
        expectFalse(sample().limited)
        expectTrue(sample(speed:22).limited)
        expectTrue(sample(scheduler:40).limited)
        expectTrue(sample(cores:6).limited)
    }
    func testMissingLimitsStayUnknown() {
        let s=sample(speed:nil,scheduler:nil,cores:nil)
        expectFalse(s.limitKnown)
        expectEqual(s.limitTitle,"限速信息不完整")
        expectFalse(s.assessment.contains("目前没有检测到"))
        let csv=Export.csv([s])
        expectTrue(csv.contains(",,,,,,12,0,,"))
    }
    func testAttributionRequiresEvidence() {
        expectTrue(sample(speed:22,thermal:0).assessment.contains("没有足够"))
        expectTrue(sample(speed:22,thermal:2).assessment.contains("可能"))
        expectTrue(sample(speed:22,warning:255).assessment.contains("没有足够"))
        expectTrue(sample(speed:22,warning:5).assessment.contains("可能"))
        expectTrue(sample(speed:22,warning:10).assessment.contains("可能"))
    }
    func testSMCNumberEncoding() {
        var v=TSValue();v.size=2;v.type=0x66706532 // fpe2
        expectEqual(ts_encode(5500,&v),0)
        expectEqual(ts_decode(&v),5500)
        expectNotEqual(ts_encode(-1,&v),0)
        expectNotEqual(ts_encode(Double.nan,&v),0)
        expectNotEqual(ts_encode(20000,&v),0)
        v.type=0x666c7420;v.size=4 // flt
        expectEqual(ts_encode(5375.5,&v),0)
        expectEqual(ts_decode(&v),5375.5,accuracy:0.01)
    }
    func testShellQuotingDoesNotInterpolate() throws {
        let text="quote' space $HOME `whoami`\nline"
        let result=try ProcessRunner.run("/bin/sh",["-c","printf %s "+ProcessRunner.shellQuote(text)])
        expectEqual(result.status,0)
        expectEqual(result.output,text)
    }
    func testCommandTimeout() {
        expectThrows(try ProcessRunner.run("/bin/sleep",["2"],timeout:0.05))
    }
}
