import AppKit
import ThermalCore

extension AppModel {
    func runningFanApplications()->(running:[FanApplication],frontmost:String?) {
        if let fanApplicationSnapshot {return fanApplicationSnapshot()}
        if isFanControlPreview {return ([],nil)}
        let running=NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier}.compactMap {app->FanApplication? in
            guard let id=app.bundleIdentifier,let name=app.localizedName else{return nil}
            let value=FanApplication(bundleID:id,name:name);return value.isValid ? value:nil
        }
        return (running,NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
    var availableFanApplications:[FanApplication] {
        var apps=Dictionary(fanAutomation.rules.map{($0.id,$0.application)},uniquingKeysWith:{first,_ in first})
        for app in runningFanApplications().running {apps[app.id]=app}
        return apps.values.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
    func scheduleFanAutomation() {
        fanAutomationWork?.cancel()
        guard fanAutomation.enabled else{return}
        let work=DispatchWorkItem { [weak self] in MainActor.assumeIsolated {self?.evaluateFanAutomation()} }
        fanAutomationWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:work)
    }
    func pauseFanAutomationForManualSelection() {
        guard !fanAutomationApplying else{return}
        fanAutomationWork?.cancel();fanAutomationApplication=nil;fanAutomationLastAttempt=nil
        if fanAutomation.enabled {fanAutomation.enabled=false}
    }
    func setFanAutomationEnabled(_ enabled:Bool) {
        guard !busy,AppDistribution.hardwareControlAvailable else{return}
        fanAutomation.manualSelection=fanScenes.selection
        fanAutomation.enabled=enabled;fanAutomationLastAttempt=nil;fanAutomationApplication=nil
        fanRestorePending=false
        if enabled {evaluateFanAutomation()}
        else {fanAutomationWork?.cancel()}
    }
    func associateFanApplication(_ app:FanApplication,sceneID:String) {
        guard !busy,fanScenes.scenes.contains(where:{$0.id==sceneID}) else{return}
        do {
            try fanAutomation.associate(app,with:sceneID)
            fanAutomationLastAttempt=nil;scheduleFanAutomation()
        }catch {report(error.localizedDescription,error:true)}
    }
    func removeFanApplication(_ bundleID:String) {
        guard !busy else{return}
        fanAutomation.removeApplication(bundleID)
        fanAutomationLastAttempt=nil;scheduleFanAutomation()
    }
    func chooseFanApplications(sceneID:String) {
        guard !isFanControlPreview,!busy else{return}
        let panel=NSOpenPanel()
        panel.title=L("选择要关联的应用");panel.prompt=L("关联应用")
        panel.directoryURL=URL(fileURLWithPath:"/Applications")
        panel.canChooseFiles=true;panel.canChooseDirectories=false;panel.allowsMultipleSelection=true
        panel.treatsFilePackagesAsDirectories=false;panel.allowedFileTypes=["app"]
        panel.begin { [weak self] response in
            guard response == .OK else{return}
            MainActor.assumeIsolated {
                for url in panel.urls {
                    guard url.pathExtension.lowercased()=="app",let bundle=Bundle(url:url),let id=bundle.bundleIdentifier else {self?.report("无法识别这个应用或场景",error:true);continue}
                    let name=(bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String) ?? (bundle.infoDictionary?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
                    self?.associateFanApplication(.init(bundleID:id,name:name),sceneID:sceneID)
                }
            }
        }
    }
    func evaluateFanAutomation() {
        guard fanAutomation.enabled,!busy,!fanSuspending,AppDistribution.hardwareControlAvailable else{return}
        let apps=runningFanApplications()
        guard var decision=fanAutomation.decision(running:apps.running,frontmost:apps.frontmost,current:fanAutomationApplication?.id,scenes:fanScenes.scenes) else{return}
        if decision.selection == .strategy(.custom),fanScenes.confirmedCustomCurve==nil {decision.selection = .strategy(.system)}
        if fanAutomationApplication != decision.application {fanAutomationApplication=decision.application}
        guard decision.selection != fanAutomationLastAttempt else{return}
        guard let snapshot,ControlAvailability.fansAvailable(snapshot) else{return}
        if coolingToken==nil,!snapshot.fans.allSatisfy({$0.manual==false}) {
            pauseFanAutomationForManualSelection()
            report("风扇正由其他程序控制，按应用切换已暂停。",error:true);return
        }
        var settings=fanScenes;settings.selection=decision.selection
        if let curve=settings.curve(custom:customCurve),curve.sensor.temperature(in:snapshot)==nil {return}
        fanAutomationLastAttempt=decision.selection;fanRestorePending=false
        if decision.selection == fanScenes.selection,(decision.selection.isAutomatic && systemFansAutomatic || activeProfile != nil) {return}
        fanAutomationApplying=true
        defer {fanAutomationApplying=false}
        switch decision.selection {
        case .strategy(.custom):if let curve=settings.curve(custom:customCurve) {applyFanCurve(curve,name:"自定义曲线")}
        case .strategy(let strategy):applyFanStrategy(strategy)
        case .scene(let id):applyFanScene(id)
        }
    }
}
