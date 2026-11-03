import AppKit
import SwiftUI

final class StoreDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    let model=StoreModel()
    var window:NSWindow!
    var item:NSStatusItem!
    let popover=NSPopover()
    func applicationDidFinishLaunching(_ notification:Notification) {
        let hosting=NSHostingView(rootView:StoreRoot(model:model))
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1080,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title="ShowMac";window.titlebarAppearsTransparent=true;window.titleVisibility = .hidden
        window.contentView=hosting;window.minSize=NSSize(width:900,height:680);window.delegate=self;window.isReleasedWhenClosed=false;window.center()
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.target=self;item.button?.action=#selector(togglePopover)
        popover.behavior = .transient;popover.contentViewController=NSHostingController(rootView:StorePopover(model:model,open:{[weak self] in self?.showWindow()}))
        model.didSample = { [weak self] in self?.updateMenu() }
        installMenu();updateMenu();model.start();showWindow()
    }
    func updateMenu() {
        var values:[String]=[]
        if model.menuCPU { values.append(model.percent(model.latest?.cpu)) }
        if model.menuMemory { values.append(model.memory(model.latest?.memoryBytes)) }
        if model.menuBattery, let battery=model.latest?.battery { values.append(model.percent(battery)) }
        let text=values.isEmpty ? "ShowMac" : values.joined(separator:String(repeating:" ",count:max(0,Int(model.menuSpacing/3))))
        let color:NSColor
        switch model.menuColor {case "purple":color=NSColor(calibratedRed:0.72,green:0.60,blue:0.86,alpha:1);case "blue":color = .systemBlue;case "green":color = .systemGreen;default:color = .labelColor}
        item.button?.attributedTitle=NSAttributedString(string:text,attributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:12,weight:.medium),.foregroundColor:color])
        item.button?.toolTip="ShowMac · "+model.thermalText(model.latest?.thermal)
    }
    func installMenu() {
        let menu=NSMenu(),appItem=NSMenuItem(),app=NSMenu()
        app.addItem(withTitle:"About ShowMac",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        app.addItem(.separator())
        app.addItem(withTitle:"Quit ShowMac",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appItem.submenu=app;menu.addItem(appItem)
        let editItem=NSMenuItem(),edit=NSMenu(title:"Edit")
        for (title,action,key) in [("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] { edit.addItem(withTitle:title,action:action,keyEquivalent:key) }
        editItem.submenu=edit;menu.addItem(editItem);NSApp.mainMenu=menu
    }
    @objc func showWindow() {popover.performClose(nil);NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)}
    @objc func togglePopover() {guard let button=item.button else{return};if popover.isShown {popover.performClose(nil)}else{popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)}}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {showWindow();return true}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
}
if CommandLine.arguments.contains("--self-check") {
    let a=CPUTicks(user:10,system:20,idle:30,nice:0),b=CPUTicks(user:20,system:30,idle:110,nice:0)
    precondition(b.utilization(since:a)==20)
    precondition(a.utilization(since:a)==nil)
    let wrapped=CPUTicks(user:2,system:0,idle:4,nice:0),old=CPUTicks(user:UInt32.max-1,system:0,idle:0,nice:0)
    precondition(wrapped.utilization(since:old)==50)
    let sampler=StoreSampler();precondition(sampler.sample().cpu==nil)
    Thread.sleep(forTimeInterval:0.3)
    let sample=sampler.sample()
    precondition(sample.cpu.map{(0...100).contains($0)} ?? false)
    precondition(sample.memoryBytes.map{$0>0 && $0<=Double(ProcessInfo.processInfo.physicalMemory)} ?? false)
    print("ShowMac Store checks passed: CPU deltas, rollover, missing first sample, live public CPU and memory readings.")
    exit(0)
}
let app=NSApplication.shared
let delegate=StoreDelegate()
app.setActivationPolicy(.regular);app.delegate=delegate;app.run()
