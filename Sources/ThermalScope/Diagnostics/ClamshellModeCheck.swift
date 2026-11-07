import AppKit
import SwiftUI
import ThermalCore

/// Fixture-only control and appearance checks; never launch a privileged helper.
@MainActor enum ClamshellModeCheck {
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else {exit(2)}
        _=NSApplication.shared
        do {try check();try automaticCheck();try interruptionCheck();print("PASS: manual and automatic power conditions, saved rules, waiting/active/error states, one attempt per power interval, explicit retry, busy deferral, unknown power, in-flight cancellation, partial activation rollback, stop failure and interrupted-session handling, shutdown isolation, desktop/battery gating, localized light/dark layouts. Fixtures only; no hardware writes.");exit(0)}
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
    private static func automaticCheck() throws {
        let suite="showmac-clamshell-check-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        var state=ClamshellEnvironment(portable:true,acPower:false,sleepDisabled:false)
        let model=ClamshellModeModel(defaults:defaults,readEnvironment:{state})
        var commands:[String]=[]
        var denied=false
        var allowed=true
        model.canPerform={allowed}
        func connect(_ target:ClamshellModeModel) {
            target.perform={request,completion in
                commands.append(request.command)
                if denied {completion(.failure(ScopeError.message("Fixture authorization denied")));return}
                let enabled=request.command=="clamshell-start"
                state=ClamshellEnvironment(portable:true,acPower:state.acPower,sleepDisabled:enabled)
                var reply=ControlReply(ok:true,message:"fixture")
                reply.clamshell=ClamshellStatus(active:enabled,message:enabled ? "合盖运行中 · 仅接电":"合盖运行已关闭")
                completion(.success(reply))
            }
        }
        connect(model)
        model.setActivation(.whenPowered)
        try require(!model.isEnabled && commands.isEmpty,"Selecting a condition enabled the feature")
        model.setEnabled(true)
        try require(model.isEnabled && !model.status.active && commands.isEmpty,"Battery arming wrote power settings")
        try require(model.detail=="自动规则已开启，等待接通电源","Waiting rule presented an active lease")
        for language in ["zh-Hans","en"] {
            AppLocalization.shared.set(language)
            for dark in [false,true] {try capture(model,dark:dark,language:language,name:"automatic-waiting")}
        }
        state=ClamshellEnvironment(portable:true,acPower:true,sleepDisabled:false)
        allowed=false;model.refresh()
        try require(commands.isEmpty,"A busy hardware control did not defer automation")
        allowed=true;model.refresh();model.refresh()
        try require(model.status.active && commands==["clamshell-start"],"External power did not enable exactly once")
        for language in ["zh-Hans","en"] {
            AppLocalization.shared.set(language)
            for dark in [false,true] {try capture(model,dark:dark,language:language,name:"automatic-active")}
        }
        state=ClamshellEnvironment(portable:true,acPower:false,sleepDisabled:true)
        model.refresh();model.refresh()
        try require(!model.status.active && model.isEnabled && commands==["clamshell-start","clamshell-stop"],"Unplug did not release while keeping the rule armed")
        state=ClamshellEnvironment(portable:true,acPower:true,sleepDisabled:false)
        denied=true;model.refresh()
        for _ in 0..<5 {model.refresh();model.receive(ClamshellStatus())}
        try require(commands.count==3 && model.automaticIssue != nil && !model.status.active,"Rejected authorization caused a retry loop or active state")
        for language in ["zh-Hans","en"] {
            AppLocalization.shared.set(language)
            for dark in [false,true] {try capture(model,dark:dark,language:language,name:"automatic-error")}
        }
        denied=false;model.retryAutomatic()
        try require(model.status.active && commands.count==4 && model.automaticIssue==nil,"Explicit retry did not recover")
        // The independent guard or another system change can end the lease.
        state=ClamshellEnvironment(portable:true,acPower:true,sleepDisabled:false)
        model.refresh();model.refresh()
        try require(!model.status.active && commands.count==4 && model.automaticIssue != nil,"Interrupted override was silently reacquired")
        model.retryAutomatic()
        try require(model.status.active && commands.count==5,"Interrupted rule could not be retried")
        denied=true;model.setEnabled(false)
        for _ in 0..<5 {model.refresh()}
        try require(model.status.active && commands.count==6,"Failed stop caused repeated commands")
        denied=false;model.setEnabled(false)
        try require(!model.isEnabled && commands.count==7,"Failed stop could not be explicitly retried")
        model.setEnabled(true)
        try require(model.status.active && commands.count==8,"Automatic rule did not re-enable")
        model.shutdown()
        state=ClamshellEnvironment(portable:true,acPower:true,sleepDisabled:false)
        model.refresh()
        try require(commands.count==8,"Shutdown restarted hardware control")
        let restored=ClamshellModeModel(defaults:defaults,readEnvironment:{state})
        try require(restored.isEnabled && restored.activation == .whenPowered && !restored.status.active,"Relaunch lost the explicit rule or invented an active lease")
        connect(restored);restored.refresh()
        try require(restored.status.active && commands.count==9,"Saved rule did not resume when eligible")
        restored.setActivation(.manual)
        let manual=ClamshellModeModel(defaults:defaults,readEnvironment:{state})
        try require(!manual.isEnabled && manual.activation == .manual,"Manual mode auto-resumed")
        restored.setEnabled(false)
        state=ClamshellEnvironment(portable:true,acPower:true,sleepDisabled:true)
        let foreign=ClamshellModeModel(readEnvironment:{state});connect(foreign)
        foreign.setActivation(.whenPowered);foreign.setEnabled(true);foreign.refresh()
        try require(!foreign.status.active && commands.count==10,"A foreign sleep override was overwritten")
        state=ClamshellEnvironment(portable:false,acPower:true,sleepDisabled:false)
        let desktop=ClamshellModeModel(readEnvironment:{state});connect(desktop)
        desktop.setActivation(.whenPowered);desktop.setEnabled(true)
        try require(!desktop.isEnabled && commands.count==10,"Desktop automation was armed")
    }
    private static func interruptionCheck() throws {
        var state=ClamshellEnvironment(portable:true,acPower:true,sleepDisabled:false)
        var unreadable=false
        let model=ClamshellModeModel(readEnvironment:{
            if unreadable {throw ScopeError.message("fixture unavailable")}
            return state
        })
        var commands:[String]=[]
        model.perform={request,completion in
            commands.append(request.command)
            completion(.failure(ScopeError.message("fixture rejection")))
        }
        model.setActivation(.whenPowered);model.setEnabled(true)
        unreadable=true;model.refresh()
        unreadable=false;model.refresh()
        try require(commands.count==1,"An unreadable power source reset the authorization backoff")
        model.setEnabled(false)
        model.setActivation(.manual)
        var pending:[(Result<ControlReply,Error>)->Void]=[]
        model.perform={request,completion in commands.append(request.command);pending.append(completion)}
        model.setEnabled(true);model.setEnabled(false)
        try require(model.changing && !model.enabled && pending.count==1,"In-flight cancellation was ignored")
        state=ClamshellEnvironment(portable:true,acPower:true,sleepDisabled:true)
        var reply=ControlReply(ok:true,message:"fixture")
        reply.clamshell=ClamshellStatus(active:true)
        pending.removeFirst()(.success(reply))
        try require(model.changing && commands.last=="clamshell-stop" && pending.count==1,"Late activation was not released after cancellation")
        state=ClamshellEnvironment(portable:true,acPower:true,sleepDisabled:false)
        reply.clamshell=ClamshellStatus()
        pending.removeFirst()(.success(reply))
        try require(!model.isEnabled && !model.changing,"Cancelled activation stayed on")
        model.perform={request,completion in
            commands.append(request.command)
            let active=request.command=="clamshell-start"
            state=ClamshellEnvironment(portable:true,acPower:true,sleepDisabled:active)
            var reply=ControlReply(ok:!active,message:"fixture partial activation")
            reply.clamshell=ClamshellStatus(active:active,failed:active)
            completion(.success(reply))
        }
        model.setEnabled(true)
        try require(!model.isEnabled && !model.status.active && Array(commands.suffix(2))==["clamshell-start","clamshell-stop"],"A failed start with a live override was not released")
    }
    private static func capture(_ model:ClamshellModeModel,dark:Bool,language:String,name:String="manual")throws {
        NSApp.appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
        let content=ClamshellModeSettings(mode:model,busy:false).padding(20)
            .frame(width:600,height:300).appBackground{Palette.canvas}.preferredColorScheme(dark ? .dark:.light)
        let controller=NSHostingController(rootView:content)
        let window=NSWindow(contentRect:CGRect(x:0,y:0,width:600,height:300),styleMask:.borderless,backing:.buffered,defer:false)
        window.contentViewController=controller
        let host=controller.view;host.frame=CGRect(x:0,y:0,width:600,height:300);host.layoutSubtreeIfNeeded()
        guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {throw ScopeError.message("Missing closed-lid settings bitmap")}
        host.cacheDisplay(in:host.bounds,to:bitmap)
        guard let data=bitmap.representation(using:.png,properties:[:]),data.count>1000 else {throw ScopeError.message("Empty closed-lid settings bitmap")}
        if let output=ProcessInfo.processInfo.environment["THERMALSCOPE_CLAMSHELL_OUTPUT"] {
            let folder=URL(fileURLWithPath:output,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try data.write(to:folder.appendingPathComponent(name+"-"+language+"-"+(dark ? "dark":"light")+".png"))
        }
        window.contentViewController=nil
    }
}
