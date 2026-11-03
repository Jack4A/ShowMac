import Foundation
import Darwin
import ThermalCore

final class NativeControlTests {
    func sample(_ i:Int,cpu:Double?,gpu:Double?,storage:Double?)->Snapshot {
        let base=CurveTests().snapshot(cpu,gpu:gpu,storage:storage)
        return Snapshot(date:Date(timeIntervalSince1970:Double(1000+i*2)),cpuUsage:10,sensors:base.sensors,fans:[],speedLimit:100,schedulerLimit:100,availableCPUs:12,totalCPUs:12,thermalState:0,thermalWarning:nil,turbo:.driverNotLoaded,acPower:true,lowPower:false,smcAvailable:true)
    }
    func testSourcesAndGaps() {
        let items=[TimelineSample(sample(0,cpu:60,gpu:45,storage:35),mode:"节能"),TimelineSample(sample(1,cpu:nil,gpu:50,storage:nil),mode:"节能"),TimelineSample(sample(2,cpu:70,gpu:55,storage:37),mode:"节能")]
        let start=Date(timeIntervalSince1970:999)
        let cpu=SensorTimeline.records(items,sensor:.cpu,start:start)
        let gpu=SensorTimeline.records(items,sensor:.gpu,start:start)
        let storage=SensorTimeline.records(items,sensor:.storage,start:start)
        expectEqual(cpu.count,2);expectNotEqual(cpu[0].segment,cpu[1].segment)
        expectEqual(gpu.count,3);expectEqual(gpu.map(\.temperature),[45,50,55])
        expectEqual(storage.map(\.temperature),[35,37]);expectNotEqual(storage[0].segment,storage[1].segment)
        expectTrue(SensorTimeline.records(items,sensor:.battery,start:start).isEmpty)
    }
    func testDecimationPreservesExtremes() {
        let samples=(0..<900).map { i in TimelineSample(sample(i,cpu:i==451 ? 99:60,gpu:nil,storage:nil),mode:i<450 ? "节能":"性能") }
        let full=SensorTimeline.records(samples,sensor:.cpu,start:Date(timeIntervalSince1970:999))
        let start=ProcessInfo.processInfo.systemUptime
        var plotted:[ModeRecord]=[]
        for _ in 0..<100 {plotted=SensorTimeline.decimated(full)}
        print("Timeline benchmark: 100 x 900 samples, \(Int((ProcessInfo.processInfo.systemUptime-start)*1000)) ms; \(plotted.count) plot points")
        expectTrue(plotted.count<330);expectTrue(plotted.contains{$0.temperature==99})
        expectEqual(plotted.first?.date,full.first?.date);expectEqual(plotted.last?.date,full.last?.date)
        expectEqual(Set(plotted.map(\.segment)),Set(full.map(\.segment)))
    }
    func testTurboSegments() {
        let first=sample(0,cpu:70,gpu:55,storage:35)
        let last=Snapshot(date:first.date.addingTimeInterval(2),cpuUsage:10,sensors:first.sensors,fans:[],speedLimit:100,schedulerLimit:100,availableCPUs:12,totalCPUs:12,thermalState:0,thermalWarning:nil,turbo:.disabledDriverLoaded,acPower:true,lowPower:false,smcAvailable:true)
        let values=SensorTimeline.records([TimelineSample(first,mode:"系统自动"),TimelineSample(last,mode:"系统自动")],sensor:.gpu,start:first.date)
        expectEqual(values.count,2);expectNotEqual(values[0].segment,values[1].segment)
        expectEqual(values[0].turboDisabled,false);expectEqual(values[1].turboDisabled,true)
        expectTrue(values[1].mode.contains("睿频关闭"));expectEqual(values[1].temperature,55)
    }
    func testUnsupportedTurboLabels() {
        let base=sample(0,cpu:60,gpu:nil,storage:nil)
        let arm=Snapshot(date:base.date,cpuUsage:10,sensors:base.sensors,fans:[],speedLimit:nil,schedulerLimit:nil,availableCPUs:nil,totalCPUs:12,thermalState:0,thermalWarning:nil,turbo:.unsupported,acPower:true,lowPower:false,smcAvailable:true)
        let values=SensorTimeline.records([TimelineSample(arm,mode:"系统自动")],sensor:.cpu,start:base.date)
        expectEqual(values.first?.mode,"系统自动")
        expectNil(values.first?.turboDisabled)
        let intel=SensorTimeline.records([TimelineSample(base,mode:"系统自动")],sensor:.cpu,start:base.date)
        expectEqual(intel.first?.mode,"系统自动 · 允许睿频")
    }
    func testProcessCPUAccounting() {
        expectEqual(ProcessCPU.percent(previous:0,current:1_000_000_000,elapsed:1,sameIdentity:true),100)
        expectEqual(ProcessCPU.percent(previous:0,current:2_000_000_000,elapsed:1,sameIdentity:true),200)
        expectNil(ProcessCPU.percent(previous:100,current:0,elapsed:1,sameIdentity:true))
        expectNil(ProcessCPU.percent(previous:0,current:100,elapsed:0,sameIdentity:true))
        expectNil(ProcessCPU.percent(previous:0,current:100,elapsed:1,sameIdentity:false))
    }
    func testNativeProcessSampler() {
        let sampler=NativeProcessSampler();_=sampler.sample()
        let until=ProcessInfo.processInfo.systemUptime+0.2
        while ProcessInfo.processInfo.systemUptime<until {}
        let rows=sampler.sample()
        guard let current=rows.first(where:{$0.pid==getpid()}) else {expectTrue(false);return}
        expectTrue(current.cpu>1);expectTrue(current.cpu<150);expectTrue(current.memory>0)
        print("Native process accounting verified for own PID; \(rows.count) readable processes.")
    }
    func testAllowlistAndFraming() throws {
        expectThrows(try ControlRequest("shell").validate())
        expectThrows(try ControlRequest("profile",profile:"automatic").validate())
        expectThrows(try ControlRequest("profile",profile:"custom").validate())
        expectThrows(try ControlRequest("profile",profile:"eco",duration:Double.nan).validate())
        try ControlRequest("profile",profile:"custom",curve:.manual(percent:50)).validate()
        var sockets=[Int32](repeating:0,count:2)
        expectEqual(socketpair(AF_UNIX,SOCK_STREAM,0,&sockets),0)
        defer {close(sockets[0]);close(sockets[1])}
        let app=ControlChannel(fd:sockets[0]),helper=ControlChannel(fd:sockets[1])
        try app.send(ControlRequest("hello"));try app.send(ControlRequest("turbo-disable"))
        let first=try JSONDecoder().decode(ControlRequest.self,from:helper.readLine(timeout:1)!)
        let second=try JSONDecoder().decode(ControlRequest.self,from:helper.readLine(timeout:1)!)
        expectEqual(first.command,"hello");expectEqual(second.command,"turbo-disable")
        try helper.send(ControlReply(ok:true,message:"已确认",session:"test"))
        let reply=try JSONDecoder().decode(ControlReply.self,from:app.readLine(timeout:1)!)
        expectTrue(reply.ok);expectEqual(reply.session,"test")
    }
    func testAppliedOnlyAfterVerifiedWrites() throws {
        let fans=FakeFans();var clock=0.0,confirmed=0
        try CurveLease.run(hardware:fans,curve:.balanced,duration:1,sample:{CurveTests().snapshot()},now:{clock},isCancelled:{false},wait:{clock+=1},onApplied:{
            expectEqual(fans.modes,[true,true]);expectTrue(fans.writes.contains("target1"));confirmed+=1
        })
        expectEqual(confirmed,1)
        fans.failTarget=1;confirmed=0
        expectThrows(try CurveLease.run(hardware:fans,curve:.balanced,duration:1,sample:{CurveTests().snapshot()},now:{0},isCancelled:{false},wait:{},onApplied:{confirmed+=1}))
        expectEqual(confirmed,0);expectEqual(fans.modes,[false,false])
    }
}
