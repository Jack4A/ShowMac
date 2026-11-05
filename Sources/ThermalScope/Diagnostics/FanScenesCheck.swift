import AppKit
import ThermalCore

/// All control callbacks are simulated by --ui-check; no authorization or hardware writes.
@MainActor enum FanScenesCheck {
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else{print("Use --fan-scenes-check --ui-check.");exit(2)}
        _=NSApplication.shared
        Task { @MainActor in
            do {try await check();print("PASS: named scenes, one-shot timers, cancel/expiry/wake recovery, preserved countdown across app switches, rejected control, resume intent and preference isolation. Simulated helper only; no authorization or hardware writes.");exit(0)}
            catch {print("FAIL: \(error.localizedDescription)");exit(1)}
        }
        NSApp.run()
    }
    private static func require(_ condition:Bool,_ message:String)throws {if !condition {throw ScopeError.message(message)}}
    private static func settled(_ model:AppModel)async throws {
        let deadline=Date().addingTimeInterval(5)
        while Date()<deadline {
            let expectedManual=model.coolingToken != nil
            let confirming=model.snapshot?.fans.contains{$0.manual != expectedManual} ?? expectedManual
            if !model.busy,!confirming {return}
            try await Task.sleep(nanoseconds:50_000_000)
        }
        throw ScopeError.message("Fixture control did not settle")
    }
    private static func check()async throws {
        func preferences()->NSDictionary {NSDictionary(dictionary:UserDefaults.standard.persistentDomain(forName:Bundle.main.bundleIdentifier ?? "local.jack.ThermalScope") ?? [:])}
        let original=ProcessInfo.processInfo.environment["THERMALSCOPE_PREVIEW_FAN_STATE"]
        setenv("THERMALSCOPE_PREVIEW_FAN_STATE","multi",1)
        defer {if let original {setenv("THERMALSCOPE_PREVIEW_FAN_STATE",original,1)} else {unsetenv("THERMALSCOPE_PREVIEW_FAN_STATE")}}
        let before=preferences(),model=AppModel()
        defer {model.shutdown()}
        try require(!model.fanRestorePending,"UI fixtures scheduled real startup restoration")
        let scene=model.fanScenes.scenes[0]
        model.applyFanScene(scene.id);try await settled(model)
        try require(model.coolingToken != nil && model.activeFanSceneID==scene.id && model.fanScenes.selection == .scene(scene.id),"Confirmed scene was not shared with app state")
        try require(model.fanControl.status?.continuous==true && model.fanControl.remaining()==nil,"Continuous control displayed an expiry")
        try require(model.startFanStopTimer(minutes:60),"One-shot timer could not be started");try await settled(model)
        try require(model.fanControl.status?.continuous != true && (model.fanControl.remaining() ?? 0)>3500,"Timed control did not use the selected duration")
        try require(model.fanScenes.duration == .continuous,"A one-shot timer replaced the persistent continuous default")
        var curve=scene.curve;curve.sensor = .gpu;curve.movePoint(1,temperature:54.125,percent:45.25)
        model.applyEditedFanCurve(curve);try await settled(model)
        try require(model.fanScenes.scenes.first{$0.id==scene.id}?.curve==curve && model.sessionCurve==curve,"Editing a named curve lost its scene or sensor")
        try require(model.renameFanScene(scene.id,name:"Fixture renamed") && model.activeFanScene?.name=="Fixture renamed","Scene rename lost stable identity")
        let saved=FanSceneConfiguration.decode(try JSONEncoder().encode(model.fanScenes))
        try require(saved.resumeSelection == .scene(scene.id) && saved.curve(custom:.balanced)==curve,"Restart intent or curve did not round trip")
        model.deleteFanScene(scene.id);try await settled(model)
        try require(model.coolingToken==nil && model.activeFanSceneID==nil && model.fanScenes.selection.isAutomatic,"Deleting the active scene did not restore Auto")
        try require(!model.fanScenes.scenes.contains{$0.id==scene.id},"Deleted scene remained selectable")
        try require(model.saveFanScene(name:"Fixture new",curve:.quiet),"Saving a new scene failed");try await settled(model)
        model.fanScenes.restoreOnLaunch=false
        try require(model.fanScenes.resumeSelection==nil,"Disabling restoration retained resume intent")
        model.restoreAuto();try await settled(model)
        try await checkApplicationRules()
        setenv("THERMALSCOPE_PREVIEW_FAN_STATE","failure",1)
        let rejected=AppModel();defer{rejected.shutdown()}
        rejected.applyFanScene(rejected.fanScenes.scenes[0].id);try await settled(rejected)
        try require(rejected.fanScenes.selection.isAutomatic && rejected.activeFanSceneID==nil && rejected.messageIsError,"Rejected control was persisted as a confirmed scene")
        let app=FanApplication(bundleID:"com.fixture.rejected",name:"Rejected app")
        rejected.fanApplicationSnapshot={([app],app.id)}
        rejected.associateFanApplication(app,sceneID:rejected.fanScenes.scenes[0].id)
        rejected.setFanAutomationEnabled(true);try await settled(rejected)
        try require(!rejected.fanAutomation.enabled && rejected.messageIsError && rejected.coolingToken==nil,"Failed automatic control kept retrying or claimed active automation")
        try require(preferences().isEqual(to:before as! [AnyHashable:Any]),"Scene fixtures changed user preferences")
    }
    private static func checkApplicationRules()async throws {
        let model=AppModel();defer{model.shutdown()}
        let editor=FanApplication(bundleID:"com.fixture.editor",name:"Fixture editor")
        let game=FanApplication(bundleID:"com.fixture.game",name:"Fixture game")
        var workspace:(running:[FanApplication],frontmost:String?)=([editor],editor.id)
        model.fanApplicationSnapshot={workspace}
        model.applyFanStrategy(.balanced);try await settled(model)
        let editing=model.fanScenes.scenes[0],gaming=model.fanScenes.scenes[1]
        model.associateFanApplication(editor,sceneID:editing.id);model.associateFanApplication(game,sceneID:gaming.id)
        model.setFanAutomationEnabled(true);try await settled(model)
        try require(model.activeFanSceneID==editing.id && model.fanAutomation.enabled,"Opening an associated app did not select its scene")
        try require(model.fanAutomation.manualSelection == .strategy(.balanced),"Automatic activation overwrote the manual fallback")
        try require(model.startFanStopTimer(minutes:60),"Automation timer could not be started");try await settled(model)
        try require(model.fanAutomation.enabled && (model.fanControl.remaining() ?? 0)>3500,"Changing duration disabled app rules or failed to apply the timer")
        let originalTimer=model.fanStopTimer
        let token=model.coolingToken
        workspace=([editor],"com.fixture.unrelated");model.evaluateFanAutomation();try await settled(model)
        try require(model.coolingToken==token,"An unrelated app restarted the same fan session")
        workspace=([editor,game],game.id);model.evaluateFanAutomation();try await settled(model)
        try require(model.activeFanSceneID==gaming.id,"Foreground matching app did not win")
        try require(model.fanStopTimer==originalTimer,"An application switch restarted the one-shot countdown")
        workspace=([editor],nil);model.evaluateFanAutomation();try await settled(model)
        try require(model.activeFanSceneID==editing.id,"Closing a game did not restore the remaining matched workload")
        workspace=([],nil);model.evaluateFanAutomation();try await settled(model)
        try require(model.activeFanStrategy == .balanced && model.fanAutomation.enabled,"Closing all associated apps did not restore the manual fallback")
        model.applyFanStrategy(.quiet);try await settled(model)
        workspace=([editor],editor.id);model.evaluateFanAutomation();try await settled(model)
        try require(!model.fanAutomation.enabled && model.activeFanStrategy == .quiet,"Automatic rules overrode a manual selection")
        model.setFanAutomationEnabled(true);try await settled(model)
        let decoded=FanSceneAutomation.decode(try JSONEncoder().encode(model.fanAutomation),scenes:model.fanScenes.scenes)
        try require(decoded.enabled && decoded.manualSelection == .strategy(.quiet),"Relaunch lost enabled rules or the manual fallback")
        model.deleteFanScene(editing.id);try await settled(model)
        try require(!model.fanAutomation.enabled && model.systemFansAutomatic && !model.fanAutomation.rules.contains{$0.sceneID==editing.id},"Deleting an automated active scene left an orphan rule or control session")
        model.applyFanScene(gaming.id);try await settled(model)
        try require(model.startFanStopTimer(minutes:15),"Timer did not start after a scene switch");try await settled(model)
        let validTimer=model.fanStopTimer
        try require(!model.startFanStopTimer(minutes:0) && model.fanStopTimer==validTimer,"Invalid minutes replaced an active timer")
        model.cancelFanStopTimer();try await settled(model)
        try require(model.fanStopTimer==nil && model.fanControl.status?.continuous==true && model.activeFanSceneID==gaming.id,"Cancel did not keep the scene running continuously")
        workspace=([game],game.id);model.setFanAutomationEnabled(true);try await settled(model)
        try require(model.startFanStopTimer(minutes:1),"Expiry timer did not start");try await settled(model)
        model.fanStopTimer=try FanStopTimer(minutes:1,now:Date().addingTimeInterval(-120))
        model.expireFanStopTimerIfNeeded();try await settled(model)
        try require(model.systemFansAutomatic && model.fanStopTimer==nil && !model.fanAutomation.enabled && model.fanScenes.selection.isAutomatic,"Timer expiry did not stop control and automatic rules")
        model.fanStopTimer=try FanStopTimer(minutes:1,now:Date().addingTimeInterval(-120))
        model.fanScenes.selection = .scene(gaming.id);model.fanAutomation.enabled=true
        model.resumeFanStopTimerAfterWake()
        try require(model.fanStopTimer==nil && model.fanScenes.selection.isAutomatic && !model.fanAutomation.enabled,"A timer that expired during sleep resumed a saved scene")
        model.restoreAuto();try await settled(model)
    }
}
