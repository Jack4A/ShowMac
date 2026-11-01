import Foundation
import CoreFoundation
import os

/// Opt-in only in a dedicated performance bundle. Never installs an observer in normal runs.
@MainActor final class RunLoopPerformanceProbe {
    private let directory:URL
    private var observer:CFRunLoopObserver?
    private var awake:Double?
    private var spans:[Double]=[]
    private var started:Date?
    private var dropped=0
    private let log=OSLog(subsystem:"local.jack.ThermalScope",category:"PerformanceScene")
    init?(directory:String?) {
        guard let directory,directory.hasPrefix("/") else{return nil}
        self.directory=URL(fileURLWithPath:directory,isDirectory:true)
    }
    func start() {
        if observer != nil {stop()}
        spans=[];dropped=0;awake=nil;started=Date()
        let mask=CFRunLoopActivity.afterWaiting.rawValue|CFRunLoopActivity.beforeWaiting.rawValue
        observer=CFRunLoopObserverCreateWithHandler(nil,mask,true,Int.max-1) {[weak self] _,activity in
            MainActor.assumeIsolated {self?.observe(activity)}
        }
        if let observer {CFRunLoopAddObserver(CFRunLoopGetMain(),observer,.commonModes)}
        os_signpost(.event,log:log,name:"PerformanceScene", "begin")
    }
    private func observe(_ activity:CFRunLoopActivity) {
        let now=ProcessInfo.processInfo.systemUptime
        if activity == .afterWaiting {awake=now}
        else if activity == .beforeWaiting,let awake {
            if spans.count<100_000 {spans.append(max(0,(now-awake)*1000))} else {dropped+=1}
            self.awake=nil
        }
    }
    func stop() {
        guard let observer,let started else{return}
        CFRunLoopRemoveObserver(CFRunLoopGetMain(),observer,.commonModes)
        self.observer=nil;self.started=nil;awake=nil
        let values=spans.sorted(),ended=Date()
        func quantile(_ p:Double)->Any {guard values.count>=20 else{return NSNull()};return values[max(0,Int(ceil(Double(values.count)*p))-1)]}
        let report:[String:Any]=["schema":1,"started_epoch":started.timeIntervalSince1970,"ended_epoch":ended.timeIntervalSince1970,"duration_s":ended.timeIntervalSince(started),"main_run_loop_busy_spans":values.count,"busy_p95_ms":quantile(0.95),"busy_p99_ms":quantile(0.99),"busy_max_ms":values.last ?? 0,"spans_over_16_7_ms":values.filter{$0>16.7}.count,"spans_over_100_ms":values.filter{$0>100}.count,"dropped_records":dropped,"actual_fps":NSNull(),"animation_hitches":NSNull(),"scope":"passive main-run-loop busy spans; not rendered frame times or FPS"]
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("loop-\(Int(ended.timeIntervalSince1970*1000)).json"),options:.atomic)
        } catch {NSLog("Performance capture failed: %@",error.localizedDescription)}
        os_signpost(.event,log:log,name:"PerformanceScene", "end")
    }
}
