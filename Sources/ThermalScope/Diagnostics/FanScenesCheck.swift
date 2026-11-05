import AppKit
import ThermalCore

/// All control callbacks are simulated by --ui-check; no authorization or hardware writes.
@MainActor enum FanScenesCheck {
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else{print("Use --fan-scenes-check --ui-check.");exit(2)}
        _=NSApplication.shared
        Task { @MainActor in
            do {try await check();print("PASS: named scene activation, continuous/timed telemetry, curve updates, rename/delete, rejected control, resume intent and preference isolation. Simulated helper only; no authorization or hardware writes.");exit(0)}
            catch {print("FAIL: \(error.localizedDescription)");exit(1)}
        }
        NSApp.run()
    }
    private static func require(_ condition:Bool,_ message:String)throws {if !condition {throw ScopeError.message(message)}}
    private static func settled(_ model:AppModel)async throws {
        let deadline=Date().addingTimeInterval(5)
        while Date()<deadline {
            let confirming=model.coolingToken != nil && !(model.snapshot?.fans.isEmpty==false && model.snapshot!.fans.allSatisfy{$0.manual==true})
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
        model.setFanDuration(.hour1);try await settled(model)
        try require(model.fanControl.status?.continuous != true && (model.fanControl.remaining() ?? 0)>3500,"Timed control did not use the selected duration")
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
        setenv("THERMALSCOPE_PREVIEW_FAN_STATE","failure",1)
        let rejected=AppModel();defer{rejected.shutdown()}
        rejected.applyFanScene(rejected.fanScenes.scenes[0].id);try await settled(rejected)
        try require(rejected.fanScenes.selection.isAutomatic && rejected.activeFanSceneID==nil && rejected.messageIsError,"Rejected control was persisted as a confirmed scene")
        try require(preferences().isEqual(to:before as! [AnyHashable:Any]),"Scene fixtures changed user preferences")
    }
}
