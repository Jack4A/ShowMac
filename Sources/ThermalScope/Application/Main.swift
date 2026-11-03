import AppKit
import SwiftUI
import ThermalCore
import WidgetShared
import WidgetKit
import WidgetUI

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,NSMenuDelegate,NSPopoverDelegate,NSWindowDelegate {
    let model=AppModel()
    var window:NSWindow!
    var statusItem:NSStatusItem!
    private let statusPopover=NSPopover()
    private let performanceProbe=RunLoopPerformanceProbe(directory:Bundle.main.object(forInfoDictionaryKey:"ThermalScopePerformanceDirectory") as? String)

    func applicationDidFinishLaunching(_ notification:Notification) {
        // Keep one hardware owner when a newer local build is opened.
        if let identifier=Bundle.main.bundleIdentifier {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier:identifier) where app.processIdentifier != getpid() {
                _=app.terminate()
            }
        }
        model.applyTheme()
        model.languageChanged={ [weak self] in self?.installMainMenu();self?.window?.title=L("温控台") }
        model.statusMenuRequested={ [weak self] in self?.showStatusMenu() }
        installMainMenu()
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.title=L("温控台")
        statusPopover.delegate=self
        statusPopover.behavior = .transient
        statusItem.button?.target=self
        statusItem.button?.action=#selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        model.statusChanged={ [weak self] sample in
            guard let self else { return }
            if self.model.menuStyle == "custom" {
                self.statusItem.button?.attributedTitle=NSAttributedString(string:"")
                let image=MenuBarAppearanceRenderer.image(tiles:MenuBarAppearanceRenderer.tiles(model:self.model),ending:self.model.metricHistory.end,spacing:self.model.menuSpacing,graphWidth:self.model.menuGraphWidth,background:self.model.menuGraphBackground,appearance:self.statusItem.button?.effectiveAppearance,warningsEnabled:self.model.menuCPUWarnings,typography:self.model.menuTypography,dividers:self.model.menuDividers,outerPadding:self.model.menuOuterPadding,innerPadding:self.model.menuInnerPadding)
                self.statusItem.button?.image=image
                self.statusItem.button?.imagePosition = .imageOnly
                // The complete image includes the user's padding on both outer edges.
                self.statusItem.length=max(1,ceil(image.size.width))
                self.statusItem.button?.toolTip=self.statusItem.button?.image?.accessibilityDescription
                return
            }
            self.statusItem.length=NSStatusItem.variableLength
            let output=NSMutableAttributedString()
            for (index,metric) in self.model.menuItems.enumerated() {
                if index>0 { output.append(NSAttributedString(string:"  ")) }
                if self.model.menuStyle != "values",let image=NSImage(systemSymbolName:metric.symbol,accessibilityDescription:metric.title) {
                    let attachment=NSTextAttachment();image.size=NSSize(width:14,height:14);image.isTemplate=true
                    attachment.image=image;attachment.bounds=NSRect(x:0,y:-2,width:14,height:14)
                    output.append(NSAttributedString(attachment:attachment))
                    if self.model.menuStyle != "icons" { output.append(NSAttributedString(string:" ")) }
                }
                if self.model.menuStyle != "icons" { output.append(NSAttributedString(string:metric.value(self.model))) }
            }
            output.addAttributes([.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:.medium),.foregroundColor:NSColor.labelColor],range:NSRange(location:0,length:output.length))
            self.statusItem.button?.attributedTitle=self.model.menuStyle == "stacked" ? NSAttributedString(string:""):output
            let graphPoints=self.model.metricHistory.points(self.model.menuGraphKind,minutes:2)
            let graphUpper=max(self.model.menuGraphKind.fixedUpper,graphPoints.compactMap(\.value).max() ?? 0)
            let graph=self.model.menuGraph ? MenuCPUGraph.image(points:graphPoints,ending:self.model.metricHistory.end,width:self.model.menuGraphWidth,upper:graphUpper,style:self.model.menuGraphStyle,warningsEnabled:self.model.menuCPUWarnings,appearance:self.statusItem.button?.effectiveAppearance,kind:self.model.menuGraphKind):nil
            if self.model.menuStyle == "stacked" {
                let values=MenuStackedValues.image(self.model.menuItems.map{($0.shortTitle,$0.value(self.model.readings))},appearance:self.statusItem.button?.effectiveAppearance)
                if let graph {
                    let combined=NSImage(size:NSSize(width:graph.size.width+7+values.size.width,height:22),flipped:false) {_ in
                        graph.draw(in:NSRect(x:0,y:3,width:graph.size.width,height:16))
                        values.draw(in:NSRect(x:graph.size.width+7,y:0,width:values.size.width,height:22));return true
                    }
                    combined.isTemplate=graph.isTemplate && values.isTemplate;combined.accessibilityDescription=(values.accessibilityDescription ?? "")+" · "+L(self.model.menuGraphKind.title)+" · "+L("趋势图")
                    self.statusItem.button?.image=combined
                } else {self.statusItem.button?.image=values}
            } else {
                self.statusItem.button?.image=graph
                self.statusItem.button?.image?.accessibilityDescription=L(self.model.menuGraphKind.title)+" · "+L("趋势图")
            }
            self.statusItem.button?.imagePosition = .imageLeading
            self.statusItem.button?.toolTip=L("温控台")+" · "+L(sample.limitTitle)
        }
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1060,height:860),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.delegate=self
        window.title=L("温控台")
        window.titleVisibility = .hidden
        window.subtitle=""
        window.appearance=nil
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent=true
        window.toolbarStyle = .unified
        window.minSize=NSSize(width:900,height:740)
        window.autorecalculatesKeyViewLoop=true
        window.isReleasedWhenClosed=false
        window.contentViewController=NSHostingController(rootView:ConsoleShell(model:model))
        window.center()
        if CommandLine.arguments.contains("--ui-check") {
            // UI smoke renders never invoke hardware controls.
            let environment=ProcessInfo.processInfo.environment
            if let page=environment["THERMALSCOPE_PREVIEW_PAGE"] {
                if let tab=Int(page) {model.tab=tab}
                else if let destination=ConsolePage(rawValue:page) {model.navigation.page=destination}
                else if let metric=MetricKind(rawValue:page) {model.navigation.showMetric(metric);if let sensor=metric.sensor {model.timeline.sensor=sensor}}
            }
            if environment["THERMALSCOPE_PREVIEW_NOTICE"] == "success" {model.report("界面验证示例：设置已保存。",error:false)}
            if environment["THERMALSCOPE_PREVIEW_NOTICE"] == "busy" {model.busy=true;model.report("界面验证示例：正在等待确认…",error:false)}
            if let language=environment["THERMALSCOPE_PREVIEW_LANGUAGE"] {AppLocalization.shared.set(language)}
            if let theme=environment["THERMALSCOPE_PREVIEW_THEME"] {
                NSApp.appearance=NSAppearance(named:theme == "dark" ? .darkAqua:.aqua)
            }
            if environment["THERMALSCOPE_PREVIEW_ERROR"] == "1" {
                model.report(L("界面验证示例：SMC F0Tg 回读不一致，操作未确认（目标 4000.00，读回 2000.00）"),error:true)
            }
            window.orderFront(nil)
            window.displayIfNeeded()
        } else { updateVisualVisibility() }
    }
    @objc func statusItemClicked(_ sender:Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {showStatusActions()}
        else {showStatusMenu()}
    }
    @objc func showStatusMenu() {
        if statusPopover.isShown {statusPopover.performClose(nil);return}
        guard let button=statusItem.button else{return}
        let available=button.window?.screen?.visibleFrame.height ?? 800
        let height=min(540,max(320,available-32))
        let view=StatusOverview(model:model,height:height,onNavigate:{[weak self] value in
            self?.statusPopover.performClose(nil);self?.navigateStatusDestination(value)
        },onSettings:{[weak self] in
            self?.statusPopover.performClose(nil);self?.model.navigation.preferencesSection = .menubar;self?.showPreferences()
        },onActions:{[weak self] in self?.showStatusActions()},onResize:{[weak self] height in
            self?.statusPopover.contentSize=NSSize(width:390,height:height)
        })
        model.setVisualUpdatesEnabled(true)
        statusPopover.contentViewController=NSHostingController(rootView:view)
        statusPopover.contentSize=NSSize(width:390,height:height)
        statusPopover.appearance=NSApp.appearance
        statusPopover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSApp.activate(ignoringOtherApps:true)
        statusPopover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
        updateVisualVisibility()
        statusPopover.contentViewController?.view.window?.acceptsMouseMovedEvents=true
        statusPopover.contentViewController?.view.window?.makeKey()
    }
    func popoverDidClose(_ notification:Notification) {
        // Offscreen charts must not retain live subscriptions or render work.
        statusPopover.contentViewController=nil
        updateVisualVisibility()
    }
    private func updateVisualVisibility(closing:Bool=false) {
        let visible = !closing && window != nil && !window.isMiniaturized && window.occlusionState.contains(.visible)
        model.setVisualUpdatesEnabled(visible || statusPopover.isShown)
    }
    func windowDidChangeOcclusionState(_ notification:Notification){updateVisualVisibility()}
    func windowDidMiniaturize(_ notification:Notification){updateVisualVisibility()}
    func windowDidDeminiaturize(_ notification:Notification){updateVisualVisibility()}
    func windowWillClose(_ notification:Notification){updateVisualVisibility(closing:true);NSApp.setActivationPolicy(.accessory)}
    @objc func showStatusActions() {
        statusPopover.performClose(nil)
        guard let button=statusItem.button else{return}
        let menu=NSMenu();menu.delegate=self;menuNeedsUpdate(menu)
        menu.popUp(positioning:nil,at:NSPoint(x:button.bounds.minX,y:button.bounds.minY),in:button)
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        menu.removeAllItems()
        func info(_ title:String,_ destination:String="metrics") {
            let item=NSMenuItem(title:title,action:#selector(openStatusDestination(_:)),keyEquivalent:"")
            item.target=self;item.representedObject=destination;menu.addItem(item)
        }
        func action(_ title:String,_ selector:Selector,_ value:String?=nil,_ enabled:Bool=true) {
            let item=NSMenuItem(title:title,action:selector,keyEquivalent:"")
            item.target=self;item.representedObject=value;item.isEnabled=enabled;menu.addItem(item)
        }
        menu.autoenablesItems=false
        info(L("温控台"))
        info(L("诊断与控制")+"  "+L(model.diagnostics.report.state.title),"optimization")
        if let snapshot=model.snapshot {
            info(L("运行模式")+"  "+L(model.coolingStatus),"thermal")
            let turboText=snapshot.turbo == .disabledDriverLoaded ? L("已关闭"):(snapshot.turbo == .driverNotLoaded ? L("允许开启"):L("状态不可用"))
            if !ControlAvailability.isAppleSilicon {info(L("睿频")+"  "+turboText,"thermal")}
            info(L("系统低电量模式")+"  "+L(snapshot.lowPower ? "开启":"关闭"),"optimization")
            info(L("GPU 温度")+"  "+valueText(snapshot.temperature(.gpu))+"°C",MetricKind.gpuTemperature.rawValue)
            info(L("硬盘温度")+"  "+valueText(snapshot.temperature(.storage))+"°C",MetricKind.storageTemperature.rawValue)
            for fan in snapshot.fans {
                let modeText=fan.manual.map { $0 ? L("手动"):L("自动") } ?? L("未知")
                info(L("风扇")+" \(fan.id+1)  "+valueText(fan.rpm)+" RPM  ·  "+modeText,MetricKind.fan.rawValue)
            }
            info(L("热压力")+"  "+L(snapshot.thermalTitle)+"  ·  "+L(snapshot.limitTitle),"optimization")
        }
        info(L("CPU 使用率")+"  "+valueText(model.snapshot?.cpuUsage)+"%",MetricKind.cpuUsage.rawValue)
        info(L("CPU 温度")+"  "+valueText(model.snapshot?.cpuTemperature)+"°C",MetricKind.cpuTemperature.rawValue)
        info(L("电池  ")+valueText(model.telemetry?.batteryPercent)+"%",MetricKind.battery.rawValue)
        if let process=model.processes.allRows.max(by:{$0.reading.cpu<$1.reading.cpu}) {
            info(L("CPU 占用排行")+"  "+process.name+"  "+String(format:"%.1f%%",process.reading.cpu),MetricKind.cpuUsage.rawValue)
        }
        menu.addItem(.separator())
        let modes=NSMenu(title:L("温度控制"))
        modes.autoenablesItems=false
        for mode in FanStrategy.presets {
            let item=NSMenuItem(title:L(mode.title),action:#selector(selectMode(_:)),keyEquivalent:"")
            item.target=self;item.representedObject=mode.rawValue;item.isEnabled = !model.busy && (mode == .system || ControlAvailability.fansAvailable(model.snapshot))
            item.state=model.activeFanStrategy==mode ? .on:.off
            modes.addItem(item)
        }
        let modeItem=NSMenuItem(title:model.busy ? L("温度控制 · 操作中…"):L("温度控制"),action:nil,keyEquivalent:"")
        modeItem.submenu=modes;menu.addItem(modeItem)
        action(L("恢复系统自动风扇"),#selector(restoreFans))
        action(L("风扇故障排查")+"…",#selector(testFans),nil,!model.busy)
        if !ControlAvailability.isAppleSilicon {
        action(L("关闭睿频"),#selector(disableTurbo),nil,!model.busy)
        action(L("允许睿频"),#selector(enableTurbo),nil,!model.busy)
        }
        if model.messageIsError { action("⚠ "+L(model.operationIssue.title)+"…",#selector(showIssue)) }
        if model.snapshot?.limited==true { info(L("系统正在限制性能")) }
        menu.addItem(.separator())
        action(L("打开温控台"),#selector(showWindow))
        action(L("偏好设置…"),#selector(showPreferences))
        menu.addItem(.separator())
        action(L("退出温控台"),#selector(quitApp))
    }
    @objc func openStatusDestination(_ sender:NSMenuItem) {
        navigateStatusDestination(sender.representedObject as? String ?? "metrics")
    }
    func navigateStatusDestination(_ value:String) {
        model.tab=0
        if let kind=MetricKind(rawValue:value) {
            model.navigation.showMetric(kind)
            if let sensor=kind.sensor {model.timeline.sensor=sensor}
        } else {
            model.navigation.metric=nil;model.navigation.page=ConsolePage(rawValue:value) ?? .metrics
        }
        showWindow()
    }
    func application(_ application:NSApplication,open urls:[URL]) {
        guard let url=urls.first,let route=WidgetRoute(url) else{return}
        switch route {case .overview:navigateStatusDestination("metrics");case .thermal:navigateStatusDestination("thermal");case .metric(let kind):navigateStatusDestination(kind.rawValue)}
    }
    @objc func selectMode(_ sender:NSMenuItem) {
        guard let value=sender.representedObject as? String,let mode=FanStrategy(rawValue:value) else{return}
        model.applyFanStrategy(mode)
    }
    @objc func testFans() {model.navigation.showFanTroubleshooting=true;navigateStatusDestination("thermal")}
    @objc func disableTurbo() { model.changeTurbo(disable:true) }
    @objc func enableTurbo() { model.changeTurbo(disable:false) }
    @objc func restoreFans() { model.restoreAuto() }
    @objc func showPreferences() { model.tab=1;showWindow() }
    @objc func showIssue() { model.tab=0;model.navigation.page = .thermal;showWindow() }
    @objc func showWindow() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);updateVisualVisibility()
    }
    @objc func quitApp() { model.shutdown();NSApp.terminate(nil) }
    func installMainMenu() {
        let main=NSMenu()
        let appItem=NSMenuItem();let appMenu=NSMenu(title:L("温控台"))
        appMenu.addItem(withTitle:L("关于温控台"),action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:L("隐藏温控台"),action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
        appMenu.addItem(.separator())
        let quit=NSMenuItem(title:L("退出温控台"),action:#selector(quitApp),keyEquivalent:"q");quit.target=self;appMenu.addItem(quit)
        appItem.submenu=appMenu;main.addItem(appItem)
        let editItem=NSMenuItem();let edit=NSMenu(title:L("编辑"))
        edit.addItem(withTitle:L("拷贝"),action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        edit.addItem(withTitle:L("粘贴"),action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        edit.addItem(withTitle:L("全选"),action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        editItem.submenu=edit;main.addItem(editItem)
        let windowItem=NSMenuItem();let windowMenu=NSMenu(title:L("窗口"))
        let show=NSMenuItem(title:L("显示温控台"),action:#selector(showWindow),keyEquivalent:"0");show.target=self;windowMenu.addItem(show)
        windowMenu.addItem(withTitle:L("最小化"),action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        let quick=NSMenuItem(title:L("打开菜单栏快捷面板"),action:#selector(showStatusMenu),keyEquivalent:"p");quick.target=self;windowMenu.addItem(quick)
        if performanceProbe != nil {
            windowMenu.addItem(.separator())
            let begin=NSMenuItem(title:"开始性能观察",action:#selector(beginPerformanceObservation),keyEquivalent:"");begin.target=self;windowMenu.addItem(begin)
            let end=NSMenuItem(title:"结束性能观察",action:#selector(endPerformanceObservation),keyEquivalent:"");end.target=self;windowMenu.addItem(end)
        }
        windowItem.submenu=windowMenu;main.addItem(windowItem)
        NSApp.mainMenu=main;NSApp.windowsMenu=windowMenu
    }
    @objc func beginPerformanceObservation(){performanceProbe?.start()}
    @objc func endPerformanceObservation(){performanceProbe?.stop()}
    @objc func exportSamples() { model.exportCSV() }
    @objc func refreshSamples() { model.refresh() }
    func applicationWillTerminate(_ notification:Notification) {performanceProbe?.stop();model.shutdown()}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {statusPopover.performClose(nil);showWindow();return true}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }

}

@main struct Entry {
    @MainActor static func main() {
        let args=CommandLine.arguments
        if args.contains("--status-cards-check") {StatusCardsCheck.run();return}
        if args.contains("--curve-warning-check") {CurveWarningCheck.run();return}
        if args.contains("--menu-sensor-check") {MenuSensorCheck.run();return}
        if args.contains("--menu-composition-check") {MenuCompositionCheck.run();return}
        if args.contains("--menu-customization-check") {MenuCustomizationCheck.run();return}
        if args.contains("--stress-check") {StressBenchmark.run();return}
        if args.count==2 && args[1]=="--hidden-view-update-check" {HiddenViewUpdateCheck.run();return}
        if args.count==2 && args[1]=="--render-performance-check" {RenderPerformanceBenchmark.run();return}
        if args.count==2 && args[1]=="--cpu-warning-check" {
            // Explicit test fixtures only; never fed into the running monitor or hardware.
            _=NSApplication.shared
            var h=MetricHistory()
            for (i,n) in [20.0,35,75,85,95,96,97,30].enumerated(){h.append(n,at:Date(timeIntervalSince1970:1000+Double(i*5)))}
            let ending=h.points.last!.date
            for dark in [false,true] {for style in [MenuTileStyle.historyValue,.bars] {
                let tile=MenuBarTile(metric:.cpu,style:style,label:"CPU",value:"30%",number:30,points:h.points,upper:100)
                let image=MenuBarAppearanceRenderer.image(tiles:[tile],ending:ending,spacing:4,graphWidth:88,background:false,appearance:NSAppearance(named:dark ? .darkAqua:.aqua))
                guard !image.isTemplate,let data=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data) else{exit(2)}
                var red=0,orange=0,neutral=0
                for y in 0..<bitmap.pixelsHigh {for x in 0..<bitmap.pixelsWide {
                    guard let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB),c.alphaComponent>0.5 else{continue}
                    if c.redComponent>0.7 && c.greenComponent<0.5 && c.blueComponent<0.6 {red+=1}
                    if c.redComponent>0.7 && c.greenComponent>0.5 && c.greenComponent<0.85 && c.blueComponent<0.4 {orange+=1}
                    if abs(c.redComponent-c.greenComponent)<0.05 && abs(c.greenComponent-c.blueComponent)<0.05 {neutral+=1}
                }}
                guard red>0,orange>0,neutral>0 else{print("Color pixels missing: \(style) red=\(red) orange=\(orange) neutral=\(neutral)");exit(3)}
                let disabled=MenuBarAppearanceRenderer.image(tiles:[tile],ending:ending,spacing:4,graphWidth:88,background:false,warningsEnabled:false)
                guard disabled.isTemplate else{exit(4)}
                let other=MenuBarTile(metric:.fan,style:style,label:"RPM",value:"97",number:97,points:h.points,upper:6000)
                guard MenuBarAppearanceRenderer.image(tiles:[other],ending:ending,spacing:4,graphWidth:88,background:false).isTemplate else{exit(5)}
            }}
            for style in MenuGraphStyle.allCases {
                guard !MenuCPUGraph.image(points:h.points,ending:ending,width:88,style:style,warningsEnabled:true).isTemplate,MenuCPUGraph.image(points:h.points,ending:ending,width:88,style:style,warningsEnabled:false).isTemplate else{exit(6)}
            }
            print("CPU warning test fixtures: light/dark line and bars retain orange, red and normal pixels; monochrome override, disabled warnings, non-CPU and legacy styles passed. No preferences, live readings or hardware modified.")
            return
        }
        if args.count==2 && args[1]=="--menu-appearance-check" {
            _=NSApplication.shared
            let sampler=HardwareSampler();_=sampler.sample();Thread.sleep(forTimeInterval:0.25)
            let sample=sampler.sample();var history=MetricHistory();history.append(sample.cpuUsage,at:sample.date)
            var count=0
            for dark in [false,true] {for missing in [false,true] {for style in MenuTileStyle.allCases {for colored in [false,true] {for width in [44.0,66,88] {
                let n=missing ? nil:sample.cpuUsage
                let tile=MenuBarTile(metric:.cpu,style:style,label:"CPU",value:n.map{String(format:"%.0f%%",$0)} ?? "—%",number:n,points:missing ? []:history.points,upper:100,color:colored ? .systemBlue:nil)
                let image=MenuBarAppearanceRenderer.image(tiles:[tile],ending:sample.date,spacing:4,graphWidth:width,background:true,appearance:NSAppearance(named:dark ? .darkAqua:.aqua),warningsEnabled:false)
                guard image.size.height==22,image.size.width.isFinite,image.size.width>0,image.size.width<200,image.isTemplate == !colored,image.tiffRepresentation != nil else{exit(2)}
                count+=1
            }}}}}
            guard MenuBarAppearanceRenderer.hex(NSColor(srgbRed:1,green:0,blue:0,alpha:1))=="FF0000",MenuBarAppearanceRenderer.color(hex:"invalid")==nil else{exit(3)}
            for dark in [false,true] {
                let tile=MenuBarTile(metric:.cpu,style:.stacked,label:"CPU",value:sample.cpuUsage.map{String(format:"%.0f%%",$0)} ?? "—%",number:sample.cpuUsage,points:[],upper:100)
                let image=MenuBarAppearanceRenderer.image(tiles:[tile],ending:sample.date,spacing:4,graphWidth:44,background:false,appearance:NSAppearance(named:dark ? .darkAqua:.aqua))
                guard let data=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data) else{exit(4)}
                var total=0.0,pixels=0.0
                for y in 0..<bitmap.pixelsHigh {for x in 0..<bitmap.pixelsWide {if let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB),c.alphaComponent>0.5 {total+=(c.redComponent+c.greenComponent+c.blueComponent)/3;pixels+=1}}}
                guard pixels>0,(dark ? total/pixels>0.75:total/pixels<0.25) else{exit(5)}
            }
            print("\(count) native menu images rendered, with actual/missing samples, \(MenuTileStyle.allCases.count) styles, automatic/custom component colors, 3 widths and light/dark appearances; color encoding and light/dark text pixels passed. No preferences or hardware writes.")
            return
        }
        if args.count==2 && args[1]=="--status-menu-check" {
            // Build the real native menu without starting the app or invoking actions.
            _=NSApplication.shared
            let delegate=AppDelegate()
            delegate.model.readings.update(HardwareSampler().sample(),publish:true)
            let menu=NSMenu()
            delegate.menuNeedsUpdate(menu)
            let rows=menu.items.filter{$0.action == #selector(AppDelegate.openStatusDestination(_:))}
            guard !menu.autoenablesItems,rows.count>=7,rows.allSatisfy({$0.isEnabled && $0.target === delegate && $0.representedObject is String}) else {exit(2)}
            for row in rows {print("enabled: \(row.title) -> \(row.representedObject as! String)")}
            print("\(rows.count) native status rows enabled; no actions invoked, no hardware writes.")
            return
        }
        if args.count==2 && args[1]=="--widget-publish-once" {
            let sampler=HardwareSampler();_=sampler.sample();Thread.sleep(forTimeInterval:0.5)
            let sample=sampler.sample(),automatic = !sample.fans.isEmpty && sample.fans.allSatisfy{$0.manual==false}
            var snapshot=WidgetPublisher.snapshot(sample,mode:automatic ? "系统自动":"手动 / 外部控制",language:AppLocalization.shared.resolvedLanguage)
            snapshot.running=false
            do {try WidgetStorage.write(snapshot);WidgetCenter.shared.reloadTimelines(ofKind:WidgetStorage.kind);print("Published one actual read-only snapshot: \(snapshot.date). No hardware writes.")}
            catch {print(error.localizedDescription);exit(1)}
            return
        }
        if args.count==2 && args[1]=="--widget-preview-feed" {
            // A bounded, read-only development feed for system-host rendering checks.
            let sampler=HardwareSampler(),history=MetricHistoryStore();var last:WidgetSnapshot?
            for index in 0..<36 {
                let sample=sampler.sample();history.record(sample,telemetry:nil)
                let automatic = !sample.fans.isEmpty && sample.fans.allSatisfy{$0.manual==false}
                let snapshot=WidgetPublisher.snapshot(sample,mode:automatic ? "系统自动":"手动 / 外部控制",language:AppLocalization.shared.resolvedLanguage,history:history)
                do {try WidgetStorage.write(snapshot)} catch {print(error.localizedDescription);exit(1)}
                last=snapshot
                if index==0 {WidgetCenter.shared.reloadTimelines(ofKind:WidgetStorage.kind);print("Read-only widget preview feed started (3 minute limit).")}
                Thread.sleep(forTimeInterval:5)
            }
            if var last {last.running=false;try? WidgetStorage.write(last);WidgetCenter.shared.reloadTimelines(ofKind:WidgetStorage.kind)}
            print("Preview feed ended; snapshot marked paused. No hardware writes.");return
        }
        if args.count==3 && args[1]=="--widget-render-previews" {
            // Offscreen layout verification only; this does not automate the desktop.
            let directory=URL(fileURLWithPath:args[2],isDirectory:true)
            let snapshot=WidgetStorage.read()
            do {
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                for size in WidgetCardSize.allCases {
                    let dimensions:CGSize=size == .small ? CGSize(width:164,height:164):(size == .medium ? CGSize(width:364,height:170):CGSize(width:364,height:382))
                    let content=WidgetStatusContent(snapshot:snapshot,size:size,linksEnabled:false).padding(16).frame(width:dimensions.width,height:dimensions.height).background(Color.white).environment(\.colorScheme,.light)
                    let renderer=ImageRenderer(content:content);renderer.scale=2
                    guard let image=renderer.cgImage,let data=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else{throw WidgetDataError.invalid}
                    try data.write(to:directory.appendingPathComponent("widget-"+size.rawValue+".png"))
                }
                print("Rendered three layouts from the actual shared snapshot; not a system-host screenshot.")
            } catch {print(error.localizedDescription);exit(1)}
            return
        }
        if args.count==2 && args[1]=="--widget-data-check" {
            guard let snapshot=WidgetStorage.read() else{print("No valid widget snapshot");exit(2)}
            print("Widget schema \(snapshot.schema); actual sample \(snapshot.date); \(snapshot.fans.count) fans; no hardware writes.")
            return
        }
        if args.count==2 && args[1]=="--power-probe" {
            do {
                let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(NativePowerSettings.read()))
                print("\nSleep blockers:")
                FileHandle.standardOutput.write(try encoder.encode(SleepBlocker.read()))
                print()
            } catch {print(error.localizedDescription);exit(1)}
            return
        }
        if args.count==2 && args[1]=="--localization-check" {
            guard let url=Bundle.main.url(forResource:"Localization",withExtension:"json"),let data=try? Data(contentsOf:url),let table=try? JSONDecoder().decode([String:[String:String]].self,from:data) else {exit(1)}
            for language in ["en","ja","ko","de","fr","es"] {
                guard table.values.allSatisfy({!($0[language] ?? "").isEmpty}) else {exit(2)}
                AppLocalization.shared.set(language)
                print(language+": "+L("设置")+" / "+L("关闭睿频"))
            }
            AppLocalization.shared.set("zh-Hant");print("zh-Hant: "+L("系统观测与控制"))
            print("\(table.count) keys; all supported language entries present.")
            return
        }
        if args.count==2 && args[1]=="--process-probe" {
            let sampler=NativeProcessSampler();_=sampler.sample();Thread.sleep(forTimeInterval:0.5)
            let start=ProcessInfo.processInfo.systemUptime
            let rows=sampler.sample()
            print("Native process scan: \(rows.count) readable processes; \(sampler.inaccessible) inaccessible; \(Int((ProcessInfo.processInfo.systemUptime-start)*1000)) ms")
            for row in rows.prefix(8) {print("\(row.pid) \(row.name) CPU=\(String(format:"%.1f",row.cpu))% memory=\(row.memory)")}
            return
        }
        if args.count==2 && args[1]=="--system-probe" {
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            if let data=try? encoder.encode(SystemTelemetry.read()) { FileHandle.standardOutput.write(data) }
            return
        }
        if args.count==2 && args[1]=="--probe" {
            let sampler=HardwareSampler();_=sampler.sample();Thread.sleep(forTimeInterval:0.25)
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];encoder.dateEncodingStrategy = .iso8601
            do { FileHandle.standardOutput.write(try encoder.encode(sampler.sample()));print() }
            catch { print(error);exit(1) }
            return
        }
        let application=NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate=AppDelegate()
        application.delegate=delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
