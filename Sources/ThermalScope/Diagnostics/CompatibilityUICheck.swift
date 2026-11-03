import AppKit
import SwiftUI
import ThermalCore

/// Exercise the old-system branches with isolated fixtures on a current runner.
@MainActor enum CompatibilityUICheck {
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else {print("Use --compatibility-ui-check --ui-check.");exit(2)}
        setenv("THERMALSCOPE_CLASSIC_UI","1",1)
        _=NSApplication.shared
        let key=Bundle.main.bundleIdentifier ?? "local.jack.ThermalScope"
        let before=NSDictionary(dictionary:UserDefaults.standard.persistentDomain(forName:key) ?? [:])
        let model=AppModel()
        model.shutdown()
        do {
            let end=Date()
            for index in 0..<25 {
                let sample=Snapshot(date:end.addingTimeInterval(Double(index-24)*5),cpuUsage:index>15 ? 95:Double(index*4),sensors:[SensorReading(key:"TC0P",label:"CPU",celsius:Double(60+index)),SensorReading(key:"TG0P",label:"GPU",celsius:50)],fans:[FanReading(id:0,rpm:1500,minimum:1000,maximum:6000,manual:false,controllable:true)],speedLimit:100,schedulerLimit:100,availableCPUs:8,totalCPUs:8,thermalState:0,thermalWarning:nil,turbo:.unsupported,acPower:true,lowPower:false,smcAvailable:true,memoryPressure:.normal)
                model.readings.update(sample,publish:false)
                model.metricHistory.record(sample,telemetry:nil,publish:false)
                model.sensorHistory.record(sample,menuSensors:[],publish:false)
                model.timeline.append(sample,mode:index<12 ? "系统自动":"均衡",publish:false)
            }
            model.timeline.resumeVisualUpdates()
            var count=0
            for theme in ["light","dark"] {
                model.theme=theme
                for page in [ConsolePage.metrics,.thermal,.sensors,.optimization] {
                    model.tab=0;model.navigation.metric=nil;model.navigation.page=page
                    try render(ConsoleShell(model:model),name:theme+"-"+page.rawValue,size:CGSize(width:1000,height:760))
                    count+=1
                }
                model.navigation.metric = .cpuUsage
                model.navigation.page = .metrics
                try render(ConsoleShell(model:model),name:theme+"-metric",size:CGSize(width:1000,height:760));count+=1
                model.tab=1
                try render(ConsoleShell(model:model),name:theme+"-settings",size:CGSize(width:1000,height:760));count+=1
                try render(StatusOverview(model:model,height:640,onNavigate:{_ in},onSettings:{},onActions:{},onResize:{_ in}),name:theme+"-popover",size:CGSize(width:390,height:640));count+=1
            }
            guard before.isEqual(NSDictionary(dictionary:UserDefaults.standard.persistentDomain(forName:key) ?? [:])) else {throw ScopeError.message("Compatibility check changed saved preferences")}
            print("PASS: \(count) classic-path light/dark layouts (overview, fan curve, sensors, diagnosis, metric detail, settings and popover). Current-OS rendering only; not a macOS 11 runtime certification. No hardware writes or saved preference changes.")
        } catch {print("FAIL: "+error.localizedDescription);exit(1)}
    }
    private static func render<V:View>(_ content:V,name:String,size:CGSize)throws {
        let host=NSHostingView(rootView:content.frame(width:size.width,height:size.height))
        let window=NSWindow(contentRect:CGRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView=host
        host.frame=CGRect(origin:.zero,size:size)
        host.layoutSubtreeIfNeeded()
        guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {throw ScopeError.message("Could not allocate layout bitmap: "+name)}
        host.cacheDisplay(in:host.bounds,to:bitmap)
        guard let data=bitmap.representation(using:.png,properties:[:]),data.count>1000 else {throw ScopeError.message("Empty layout: "+name)}
        if let folder=ProcessInfo.processInfo.environment["THERMALSCOPE_COMPATIBILITY_OUTPUT"] {
            let directory=URL(fileURLWithPath:folder,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try data.write(to:directory.appendingPathComponent(name+".png"))
        }
        window.contentView=nil
    }
}
