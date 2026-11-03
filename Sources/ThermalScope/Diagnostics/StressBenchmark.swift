import AppKit
import Combine
import Foundation
import ThermalCore

/// Deterministic, isolated synthetic workload. Never constructs AppModel or hardware samplers.
enum StressBenchmark {
    struct Generator {
        var state:UInt64
        mutating func next()->UInt64 {state=state &* 6364136223846793005 &+ 1442695040888963407;return state}
    }
    static func snapshot(_ date:Date,_ value:Double?)->Snapshot {
        Snapshot(date:date,cpuUsage:value,sensors:value.map{[SensorReading(key:"TC0P",label:"CPU",celsius:40+$0/2)]} ?? [],fans:[],speedLimit:100,schedulerLimit:100,availableCPUs:4,totalCPUs:4,thermalState:0,thermalWarning:nil,turbo:.driverNotLoaded,acPower:true,lowPower:false,smcAvailable:true)
    }
    @MainActor static func run() {
        let args=CommandLine.arguments
        func option(_ key:String)->String? {guard let i=args.firstIndex(of:key),i+1<args.count else{return nil};return args[i+1]}
        guard let seconds=Double(option("--stress-seconds") ?? "8"),seconds.isFinite,(0...3600).contains(seconds),
              let count=Int(option("--stress-samples") ?? "20000"),(100...200000).contains(count),
              let seed=UInt64(option("--stress-seed") ?? "1") else {fputs("Invalid stress options\n",stderr);exit(2)}
        let scenario=option("--stress-scenario") ?? "mixed"
        guard ["hidden","visible","mixed"].contains(scenario) else{exit(2)}
        _=NSApplication.shared
        var failures:[String]=[]
        func check(_ condition:Bool,_ name:String){if !condition && !failures.contains(name){failures.append(name)}}
        // Fault probes intentionally precede workload so failures have a short reproducer.
        let probe=MetricHistoryStore(),timelineProbe=TemperatureTimelineStore()
        let base=Date(timeIntervalSince1970:1_000_000)
        probe.record(snapshot(base,25),telemetry:nil,publish:false)
        probe.record(snapshot(base.addingTimeInterval(5),50),telemetry:nil,publish:false)
        probe.record(snapshot(base,10),telemetry:nil,publish:false)
        check(probe.end==base.addingTimeInterval(5),"history_end_must_not_rewind_on_stale_sample")
        timelineProbe.append(snapshot(base,25),mode:"fixture",publish:false)
        timelineProbe.append(snapshot(base.addingTimeInterval(5),50),mode:"fixture",publish:false)
        timelineProbe.append(snapshot(base,10),mode:"fixture",publish:false)
        timelineProbe.resumeVisualUpdates()
        check(timelineProbe.end==base.addingTimeInterval(5),"timeline_must_reject_stale_sample")
        let invalidDate=Date(timeIntervalSince1970:Double.nan)
        probe.record(snapshot(invalidDate,99),telemetry:nil,publish:false)
        timelineProbe.append(snapshot(invalidDate,99),mode:"invalid",publish:false)
        timelineProbe.append(snapshot(base.addingTimeInterval(5),99),mode:"duplicate",publish:false)
        timelineProbe.resumeVisualUpdates()
        check(probe.end==base.addingTimeInterval(5),"history_must_reject_nonfinite_timestamp")
        check(timelineProbe.fullPoints.count==2 && timelineProbe.latest==65,"timeline_must_reject_invalid_and_duplicate_timestamps")
        // 1 kHz fixture stream occupies only 20 simulated seconds, exposing count leaks.
        let bounded=TemperatureTimelineStore()
        for i in 0..<count {bounded.append(snapshot(base.addingTimeInterval(Double(i)/1000),50),mode:"fixture",publish:false)}
        bounded.resumeVisualUpdates()
        check(bounded.fullPoints.count<=1000,"timeline_retained_sample_cap_1000")
        let history=MetricHistoryStore(),timeline=TemperatureTimelineStore(),readings=LiveReadings()
        var notifications=0,expectedNotifications=0
        let subscription=readings.objectWillChange.sink{notifications+=1}
        var random=Generator(state:seed),latencies:[Double]=[],plotLatencies:[Double]=[]
        var total=0,batches=0,checksum=0,invalid=0,switches=0
        let started=ProcessInfo.processInfo.systemUptime
        let colors:[NSColor]=[.systemBlue,.systemOrange]
        repeat {
            autoreleasepool {
                let begin=ProcessInfo.processInfo.systemUptime
                let visible=scenario == "visible" || (scenario == "mixed" && batches%2==0)
                if scenario == "mixed" {switches+=1}
                for _ in 0..<200 {
                    let roll=random.next()%101
                    let value:Double?=roll%13==0 ? nil:(roll%17==0 ? .nan:Double(roll))
                    if value==nil || value?.isFinite==false {invalid+=1}
                    let sample=snapshot(base.addingTimeInterval(Double(total)/10),value)
                    readings.update(sample,publish:visible)
                    history.record(sample,telemetry:nil,publish:visible)
                    timeline.append(sample,mode:total%400<200 ? "A":"B",publish:visible)
                    if visible {expectedNotifications+=1}
                    total+=1
                }
                if !visible && scenario == "mixed" {readings.resumeVisualUpdates();history.resumeVisualUpdates();timeline.resumeVisualUpdates();expectedNotifications+=1}
                latencies.append((ProcessInfo.processInfo.systemUptime-begin)*1000)
                let plotStart=ProcessInfo.processInfo.systemUptime
                let points=history.points(.cpuUsage,minutes:30)
                let reduced=MetricPlot.decimated(points)
                let runs=CPULoadBands.runs(points)
                let tiles=[MenuBarTile(metric:.cpu,style:.historyValue,label:"CPU",value:"50%",number:50,points:points,upper:100,color:colors[batches%2])]
                let image=MenuBarAppearanceRenderer.image(tiles:tiles,ending:history.end,spacing:4,graphWidth:88,background:true,appearance:NSAppearance(named:batches%2==0 ? .aqua:.darkAqua))
                checksum &+= reduced.count+runs.count+Int(image.size.width)
                plotLatencies.append((ProcessInfo.processInfo.systemUptime-plotStart)*1000)
                check(points.count<=1000,"metric_history_retained_sample_cap_1000")
                check(points.allSatisfy{$0.value==nil || $0.value!.isFinite},"nonfinite_values_must_be_missing")
                check(zip(points,points.dropFirst()).allSatisfy{$0.date<$1.date},"metric_history_strict_timestamp_order")
                check(timeline.fullPoints.count<=1000,"timeline_retained_sample_cap_1000")
                batches+=1
                // Bound telemetry buffers during long soaks; retain a deterministic reservoir.
                if latencies.count>10000 {latencies.removeFirst(5000);plotLatencies.removeFirst(5000)}
            }
        } while total<count || ProcessInfo.processInfo.systemUptime-started<seconds
        if scenario == "hidden" {
            check(notifications==0,"hidden_stream_must_not_notify_views")
            readings.resumeVisualUpdates();history.resumeVisualUpdates();timeline.resumeVisualUpdates();expectedNotifications+=1
            check(timeline.fullPoints.count<=1000,"hidden_catchup_retained_sample_cap_1000")
        }
        check(notifications==expectedNotifications,"visibility_notification_count")
        check(readings.snapshot?.date==history.end,"live_history_latest_timestamp_matches")
        withExtendedLifetime(subscription){}
        func stats(_ values:[Double])->[String:Any] {
            let v=values.sorted()
            return ["count":v.count,"p50_ms":v[(v.count-1)/2],"p95_ms":v[Int(ceil(Double(v.count)*0.95))-1],"p99_ms":v[Int(ceil(Double(v.count)*0.99))-1],"max_ms":v.last!]
        }
        let elapsed=ProcessInfo.processInfo.systemUptime-started
        let result:[String:Any]=["schema":1,"scenario":scenario,"seed":String(seed),"requested_min_samples":count,"samples":total,"batches":batches,"duration_s":elapsed,"samples_per_second":Double(total)/elapsed,"injected_missing_or_nonfinite":invalid,"visibility_switches":switches,"notifications":notifications,"batch_200_samples":stats(latencies),"history_and_menu_render":stats(plotLatencies),"latency_retention":"latest 5001...10000 batches; full run throughput","invariant_failures":failures,"status":failures.isEmpty ? "passed":"failed","checksum":checksum,"fixture_data":true,"hardware_writes":false,"actual_fps":NSNull(),"scope":"Synthetic in-process model, timeline and CPU-side menu rendering; excludes real UI events, hardware polling, compositor and GPU"]
        do {
            let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
            if let output=option("--stress-out") {try data.write(to:URL(fileURLWithPath:output),options:.atomic)}
            else {FileHandle.standardOutput.write(data);print()}
        } catch {fputs("Stress report write failed: \(error)\n",stderr);exit(3)}
        exit(failures.isEmpty ? 0:1)
    }
}
