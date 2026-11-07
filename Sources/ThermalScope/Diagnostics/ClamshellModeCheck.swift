import AppKit
import SwiftUI
import ThermalCore

/// Fixture-only control and appearance checks; never launch a privileged helper.
@MainActor enum ClamshellModeCheck {
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else {exit(2)}
        _=NSApplication.shared
        do {try check();print("PASS: closed-lid switch preflight, verified replies, rejected authorization, unplug restoration, desktop/battery gating, light/dark localized layouts. Fixtures only; no hardware writes.");exit(0)}
        catch {print("FAIL: \(error.localizedDescription)");exit(1)}
    }
    private static func require(_ value:Bool,_ message:String)throws {if !value {throw ScopeError.message(message)}}
    private static func check() throws {
        var state=ClamshellEnvironment(portable:true,acPower:true,sleepDisabled:false)
        let model=ClamshellModeModel(readEnvironment:{state})
        var commands:[String]=[]
        model.perform={request,completion in
            commands.append(request.command)
            let enabled=request.command=="clamshell-start"
            state=ClamshellEnvironment(portable:true,acPower:true,sleepDisabled:enabled)
            var reply=ControlReply(ok:true,message:"fixture")
            reply.clamshell=ClamshellStatus(active:enabled,message:enabled ? "合盖运行中 · 仅接电":"合盖运行已关闭")
            completion(.success(reply))
        }
        try require(model.canEnable && !model.status.active && commands.isEmpty,"Mode enabled without a user action")
        model.setEnabled(true)
        try require(model.status.active && !model.changing && !model.canEnable,"Verified activation was not displayed")
        model.setEnabled(true);try require(commands.count==1,"Duplicate activation reached the helper")
        for language in ["zh-Hans","en"] {
            AppLocalization.shared.set(language)
            for dark in [false,true] {try capture(model,dark:dark,language:language)}
        }
        model.setEnabled(false)
        try require(!model.status.active && model.canEnable && commands==["clamshell-start","clamshell-stop"],"Manual stop did not follow verified state")
        model.perform={_,completion in completion(.failure(ScopeError.message("Fixture authorization denied")))}
        model.setEnabled(true)
        try require(!model.status.active && model.status.failed && !model.changing,"Rejected authorization displayed an active mode")
        model.receive(ClamshellStatus())
        state=ClamshellEnvironment(portable:true,acPower:false,sleepDisabled:false);model.refresh()
        try require(!model.canEnable,"Battery mode enabled")
        state=ClamshellEnvironment(portable:false,acPower:true,sleepDisabled:false);model.refresh()
        try require(!model.canEnable && model.detail=="合盖运行仅适用于 MacBook","Desktop support was implied")
        state=ClamshellEnvironment(portable:true,acPower:true,sleepDisabled:true)
        model.receive(ClamshellStatus(active:true,message:"合盖运行中 · 仅接电"))
        state=ClamshellEnvironment(portable:true,acPower:false,sleepDisabled:false);model.refresh()
        try require(!model.status.active,"Unplugged/restored mode retained a stale active state")
    }
    private static func capture(_ model:ClamshellModeModel,dark:Bool,language:String)throws {
        NSApp.appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
        let content=ClamshellModeSettings(mode:model,busy:false).padding(20)
            .frame(width:600,height:210).appBackground{Palette.canvas}.preferredColorScheme(dark ? .dark:.light)
        let controller=NSHostingController(rootView:content)
        let window=NSWindow(contentRect:CGRect(x:0,y:0,width:600,height:210),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentViewController=controller
        let host=controller.view;host.frame=CGRect(x:0,y:0,width:600,height:210);host.layoutSubtreeIfNeeded()
        guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {throw ScopeError.message("Missing closed-lid settings bitmap")}
        host.cacheDisplay(in:host.bounds,to:bitmap)
        guard let data=bitmap.representation(using:.png,properties:[:]),data.count>1000 else {throw ScopeError.message("Empty closed-lid settings bitmap")}
        if let output=ProcessInfo.processInfo.environment["THERMALSCOPE_CLAMSHELL_OUTPUT"] {
            let folder=URL(fileURLWithPath:output,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try data.write(to:folder.appendingPathComponent(language+"-"+(dark ? "dark":"light")+".png"))
        }
        window.contentViewController=nil
    }
}
