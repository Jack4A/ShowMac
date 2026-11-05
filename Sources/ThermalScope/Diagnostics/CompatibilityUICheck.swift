import AppKit
import SwiftUI
import ThermalCore

/// Exercise the old-system branches with isolated fixtures on a current runner.
@MainActor enum CompatibilityUICheck {
    static func run(classic:Bool=true) {
        guard CommandLine.arguments.contains("--ui-check") else {print("Use --compatibility-ui-check --ui-check.");exit(2)}
        setenv("THERMALSCOPE_CLASSIC_UI",classic ? "1":"0",1)
        _=NSApplication.shared
        let key=Bundle.main.bundleIdentifier ?? "local.jack.ThermalScope"
        let before=NSDictionary(dictionary:UserDefaults.standard.persistentDomain(forName:key) ?? [:])
        AppLocalization.shared.set("zh-Hans")
        let model=AppModel()
        model.shutdown()
        do {
            let end=Date(timeIntervalSince1970:1_800_000_000)
            model.statusPanel=StatusPanelConfiguration()
            model.applyMenuPreset(0)
            var evidence:[String:RenderEvidence]=[:]
            for index in 0..<25 {
                let sample=Snapshot(date:end.addingTimeInterval(Double(index-24)*5),cpuUsage:index>15 ? 95:Double(index*4),sensors:[SensorReading(key:"TC0P",label:"CPU",celsius:Double(60+index)),SensorReading(key:"TG0P",label:"GPU",celsius:50),SensorReading(key:"TH0x",label:"Storage",celsius:38)],fans:[FanReading(id:0,rpm:1500,minimum:1000,maximum:6000,manual:false,controllable:true)],speedLimit:100,schedulerLimit:100,availableCPUs:8,totalCPUs:8,thermalState:0,thermalWarning:nil,turbo:.unsupported,acPower:true,lowPower:false,smcAvailable:true,memoryPressure:.normal)
                model.readings.update(sample,publish:false)
                let telemetry=try JSONDecoder().decode(SystemTelemetry.self,from:JSONSerialization.data(withJSONObject:["date":sample.date.timeIntervalSinceReferenceDate,"memoryUsed":8_589_934_592.0,"memoryTotal":17_179_869_184.0,"batteryPercent":65.0]))
                model.readings.update(telemetry,publish:false)
                model.metricHistory.record(sample,telemetry:telemetry,publish:false)
                model.sensorHistory.record(sample,menuSensors:[],publish:false)
                model.timeline.append(sample,mode:index<12 ? "系统自动":"均衡",publish:false)
            }
            model.timeline.resumeVisualUpdates()
            var count=0
            for theme in ["light","dark"] {
                model.theme=theme
                for page in [ConsolePage.metrics,.thermal,.sensors,.optimization] {
                    model.tab=0;model.navigation.metric=nil;model.navigation.page=page
                    evidence[theme+"-"+page.rawValue]=try render(ConsoleShell(model:model),name:theme+"-"+page.rawValue,size:CGSize(width:1000,height:760))
                    count+=1
                }
                model.navigation.metric = .cpuUsage
                model.navigation.page = .metrics
                evidence[theme+"-metric"]=try render(ConsoleShell(model:model),name:theme+"-metric",size:CGSize(width:1000,height:760));count+=1
                model.tab=1
                evidence[theme+"-settings"]=try render(ConsoleShell(model:model),name:theme+"-settings",size:CGSize(width:1000,height:760));count+=1
                evidence[theme+"-popover"]=try render(StatusOverview(model:model,height:640,onNavigate:{_ in},onSettings:{},onActions:{},onResize:{_ in}),name:theme+"-popover",size:CGSize(width:390,height:640));count+=1
                _=try render(FanSceneManager(model:model,curve:.balanced,onClose:{}),name:theme+"-scene-manager-popover",size:CGSize(width:520,height:580));count+=1
                model.fanStopTimer=try FanStopTimer(minutes:30)
                _=try render(FanStopTimerButton(model:model).timerOptions,name:theme+"-stop-timer-popover",size:CGSize(width:260,height:250));count+=1
                model.fanStopTimer=nil
            }
            guard before.isEqual(NSDictionary(dictionary:UserDefaults.standard.persistentDomain(forName:key) ?? [:])) else {throw ScopeError.message("Compatibility check changed saved preferences")}
            if let folder=ProcessInfo.processInfo.environment["THERMALSCOPE_COMPATIBILITY_OUTPUT"] {
                let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
                try encoder.encode(evidence).write(to:URL(fileURLWithPath:folder).appendingPathComponent("appearance-metrics.json"))
            }
            print("PASS: \(count) unified light/dark layouts (overview, fan curve, sensors, diagnosis, metric detail, settings, popover, scene manager and stop timer). Current-OS rendering only; not a macOS 11 runtime certification. No hardware writes or saved preference changes.")
        } catch {print("FAIL: "+error.localizedDescription);exit(1)}
    }
    private struct RenderEvidence:Codable {
        let width:Double
        let height:Double
        let sidebarWidth:Double?
        let sidebarHeight:Double?
        let sidebarTop:Double?
        let settingsTop:Double?
        let selectedColor:[Int]?
        let sidebarColor:[Int]?
        let contentTopColor:[Int]?
    }
    private static func descendants(_ root:NSView)->[NSView] {root.subviews.flatMap{[$0]+descendants($0)}}
    private static func render<V:View>(_ content:V,name:String,size:CGSize)throws->RenderEvidence {
        let controller=NSHostingController(rootView:content)
        let host=controller.view
        let popup=name.hasSuffix("popover")
        let style:NSWindow.StyleMask=popup ? .borderless:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView]
        let window=NSWindow(contentRect:CGRect(origin:.zero,size:size),styleMask:style,backing:.buffered,defer:false)
        window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.toolbarStyle = .unified
        // A fixed backing color keeps offscreen material captures independent of the CI desktop.
        window.backgroundColor = Palette.windowBackground;window.isOpaque=false
        window.contentViewController=controller
        window.setFrame(CGRect(origin:.zero,size:size),display:false)
        host.frame=CGRect(origin:.zero,size:size)
        host.layoutSubtreeIfNeeded()
        host.layoutSubtreeIfNeeded()
        guard let displayBitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {throw ScopeError.message("Could not allocate layout bitmap: "+name)}
        host.cacheDisplay(in:host.bounds,to:displayBitmap)
        // CI Macs carry different display ICC profiles. Convert the bitmap itself
        // before comparing sRGB samples; retagging NSColor would change the meaning.
        guard let bitmap=displayBitmap.converting(to:.sRGB,renderingIntent:.default) else {throw ScopeError.message("Could not normalize capture color space: "+name)}
        guard let data=bitmap.representation(using:.png,properties:[:]),data.count>1000 else {throw ScopeError.message("Empty layout: "+name)}
        if let folder=ProcessInfo.processInfo.environment["THERMALSCOPE_COMPATIBILITY_OUTPUT"] {
            let directory=URL(fileURLWithPath:folder,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try data.write(to:directory.appendingPathComponent(name+".png"))
        }
        var sidebarWidth:Double?,sidebarHeight:Double?,sidebarTop:Double?,settingsTop:Double?,selected:[Int]?,background:[Int]?,contentTop:[Int]?
        if let sidebar=descendants(host).compactMap({$0 as? SidebarScrollView}).first,let table=sidebar.documentView as? NSTableView,let row=table.rowView(atRow:table.selectedRow,makeIfNecessary:true) {
            sidebarWidth=sidebar.bounds.width
            sidebarHeight=sidebar.bounds.height
            sidebarTop=sidebar.convert(.zero,to:host).y
            settingsTop=table.convert(CGPoint(x:0,y:table.rect(ofRow:table.numberOfRows-1).minY),to:host).y
            func color(_ point:CGPoint)->[Int]? {
                let scaleX=Double(bitmap.pixelsWide)/size.width,scaleY=Double(bitmap.pixelsHigh)/size.height
                let y=host.isFlipped ? point.y:size.height-point.y
                guard let rgb=bitmap.colorAt(x:min(bitmap.pixelsWide-1,max(0,Int(point.x*scaleX))),y:min(bitmap.pixelsHigh-1,max(0,Int(y*scaleY)))) else{return nil}
                return [rgb.redComponent,rgb.greenComponent,rgb.blueComponent,rgb.alphaComponent].map{Int(($0*255).rounded())}
            }
            selected=color(row.convert(CGPoint(x:row.bounds.maxX-24,y:row.bounds.midY),to:host))
            background=color(sidebar.convert(CGPoint(x:sidebar.bounds.maxX-5,y:sidebar.bounds.height*0.4),to:host))
            contentTop=color(CGPoint(x:sidebar.bounds.width+28,y:host.isFlipped ? 6:size.height-6))
            let expected=name.hasPrefix("dark") ? [76,69,80,255]:[255,255,255,255]
            guard let selected,zip(selected,expected).allSatisfy({abs($0-$1)<=3}) else {throw ScopeError.message("Selection color drift: "+name+" "+String(describing:selected))}
            let expectedTop=name.hasPrefix("dark") ? [35,33,44,255]:[244,245,247,255]
            guard let contentTop,zip(contentTop,expectedTop).allSatisfy({abs($0-$1)<=3}) else {throw ScopeError.message("Content background does not reach titlebar: "+name+" "+String(describing:contentTop))}
            guard abs(sidebar.bounds.width-220)<=1 else {
                throw ScopeError.message("Sidebar width drift: "+name+" \(sidebar.bounds.width)")
            }
        }
        if !name.hasSuffix("popover"),sidebarWidth==nil {throw ScopeError.message("Missing sidebar measurement: "+name)}
        window.contentViewController=nil
        return RenderEvidence(width:size.width,height:size.height,sidebarWidth:sidebarWidth,sidebarHeight:sidebarHeight,sidebarTop:sidebarTop,settingsTop:settingsTop,selectedColor:selected,sidebarColor:background,contentTopColor:contentTop)
    }
}
