import AppKit
import SwiftUI
import ThermalCore

struct TimelineEvent: Identifiable {
    let id=UUID()
    let date=Date()
    let title: String
    let detail: String
    let warning: Bool
}

@MainActor final class AppModel: ObservableObject {
    let processes=ProcessObserver()
    let optimization=PowerOptimizationModel()
    let diagnostics=DiagnosisStore()
    let updates=AppUpdateController()
    let navigation=DiagnosticNavigation()
    @Published var language=UserDefaults.standard.string(forKey:"appLanguage") ?? "system" {
        didSet {UserDefaults.standard.set(language,forKey:"appLanguage");AppLocalization.shared.set(language);languageChanged?()}
    }
    var languageChanged:(()->Void)?
    var statusMenuRequested:(()->Void)?
    let readings=LiveReadings()
    let fanControl=FanControlReadings()
    var snapshot:Snapshot? {readings.snapshot}
    var telemetry:SystemTelemetry? {readings.telemetry}
    let timeline=TemperatureTimelineStore()
    let metricHistory=MetricHistoryStore()
    let sensorHistory=SensorHistoryStore()
    let electricity=ElectricityHistoryStore()
    let tokens=TokenUsageStore()
    let widgetPublisher=WidgetPublisher()
    private let controller=NativeControlClient()
    private let fanPreview=CommandLine.arguments.contains("--ui-check") ? FanControlPreview():nil
    var isFanControlPreview:Bool {fanPreview != nil}
    @Published var authorizationReady=false
    private var lastHelperPoll=Date.distantPast
    @Published var menuItems:[MenuMetric]=(UserDefaults.standard.stringArray(forKey:"menuItems") ?? ["temperature","cpu"]).compactMap(MenuMetric.init(rawValue:)) {
        didSet { persistMenuSetting(menuItems.map(\.rawValue),forKey:"menuItems");updateMenu() }
    }
    @Published var menuStyle=UserDefaults.standard.string(forKey:"menuStyle") ?? "custom" {
        didSet { persistMenuSetting(menuStyle,forKey:"menuStyle");updateMenu() }
    }
    @Published var menuComposition=MenuBarComponent.decode(UserDefaults.standard.data(forKey:"menuComposition")) {
        didSet {
            if let menuComposition,let data=try? JSONEncoder().encode(menuComposition) {persistMenuSetting(data,forKey:"menuComposition")}
            else if !isFanControlPreview {UserDefaults.standard.removeObject(forKey:"menuComposition")}
            updateMenu()
        }
    }
    @Published var menuGraph=(UserDefaults.standard.object(forKey:"menuCPUGraph") as? Bool) ?? true {
        didSet {persistMenuSetting(menuGraph,forKey:"menuCPUGraph");updateMenu()}
    }
    @Published var statusMinutes:Int=[2,5,10].contains(UserDefaults.standard.integer(forKey:"statusMinutes")) ? UserDefaults.standard.integer(forKey:"statusMinutes"):2 {
        didSet {persistMenuSetting(statusMinutes,forKey:"statusMinutes")}
    }
    @Published var statusPanel=StatusPanelConfiguration.decode(UserDefaults.standard.data(forKey:"statusPanel")) {
        didSet {if let data=try? JSONEncoder().encode(statusPanel) {persistMenuSetting(data,forKey:"statusPanel")}}
    }
    @Published var statusTemperature:MetricKind={
        let value=MetricKind(rawValue:UserDefaults.standard.string(forKey:"statusTemperature") ?? "") ?? .cpuTemperature
        return value.sensor != nil ? value:.cpuTemperature
    }() {
        didSet {persistMenuSetting(statusTemperature.rawValue,forKey:"statusTemperature")}
    }
    @Published var menuGraphKind=MetricKind(rawValue:UserDefaults.standard.string(forKey:"menuGraphKind") ?? "") ?? .cpuUsage {
        didSet {persistMenuSetting(menuGraphKind.rawValue,forKey:"menuGraphKind");updateMenu()}
    }
    @Published var menuGraphStyle=MenuGraphStyle(rawValue:UserDefaults.standard.string(forKey:"menuGraphStyle") ?? "") ?? .line {
        didSet {persistMenuSetting(menuGraphStyle.rawValue,forKey:"menuGraphStyle");updateMenu()}
    }
    @Published var menuGraphWidth:Double={let n=UserDefaults.standard.double(forKey:"menuGraphWidth");return n.isFinite && (28...100).contains(n) ? n:44}() {
        didSet {persistMenuSetting(menuGraphWidth,forKey:"menuGraphWidth");updateMenu()}
    }
    @Published var menuTileStyles=(UserDefaults.standard.dictionary(forKey:"menuTileStyles") as? [String:String]) ?? [:] {
        didSet {persistMenuSetting(menuTileStyles,forKey:"menuTileStyles");updateMenu()}
    }
    @Published var menuTileColors=(UserDefaults.standard.dictionary(forKey:"menuTileColors") as? [String:String]) ?? [:] {
        didSet {persistMenuSetting(menuTileColors,forKey:"menuTileColors");updateMenu()}
    }
    @Published var menuSpacing=MenuBarLayout.spacing(UserDefaults.standard.object(forKey:"menuSpacing") as? Double) {
        didSet {persistMenuSetting(menuSpacing,forKey:"menuSpacing");updateMenu()}
    }
    @Published var menuOuterPadding:Double={let n=UserDefaults.standard.object(forKey:"menuOuterPadding") as? Double;return n.flatMap{$0.isFinite ? min(20,max(0,$0)):nil} ?? 0}() {
        didSet {persistMenuSetting(menuOuterPadding,forKey:"menuOuterPadding");updateMenu()}
    }
    @Published var menuInnerPadding:Double={let n=UserDefaults.standard.object(forKey:"menuInnerPadding") as? Double;return n.flatMap{$0.isFinite ? min(20,max(0,$0)):nil} ?? 0}() {
        didSet {persistMenuSetting(menuInnerPadding,forKey:"menuInnerPadding");updateMenu()}
    }
    @Published var menuGraphBackground=UserDefaults.standard.bool(forKey:"menuGraphBackground") {
        didSet {persistMenuSetting(menuGraphBackground,forKey:"menuGraphBackground");updateMenu()}
    }
    @Published var menuCPUWarnings=(UserDefaults.standard.object(forKey:"menuCPUWarnings") as? Bool) ?? true {
        didSet {persistMenuSetting(menuCPUWarnings,forKey:"menuCPUWarnings");updateMenu()}
    }
    @Published var menuTileIcons=(UserDefaults.standard.dictionary(forKey:"menuTileIcons") as? [String:String]) ?? [:] {
        didSet {persistMenuSetting(menuTileIcons,forKey:"menuTileIcons");updateMenu()}
    }
    @Published var menuTileLabels=(UserDefaults.standard.dictionary(forKey:"menuTileLabels") as? [String:String]) ?? [:] {
        didSet {persistMenuSetting(menuTileLabels,forKey:"menuTileLabels");updateMenu()}
    }
    @Published var menuTypography:MenuTypography={
        guard let data=UserDefaults.standard.data(forKey:"menuTypography"),let value=try? JSONDecoder().decode(MenuTypography.self,from:data) else{return .standard}
        return value
    }() {
        didSet {if let data=try? JSONEncoder().encode(menuTypography) {persistMenuSetting(data,forKey:"menuTypography")};updateMenu()}
    }
    @Published var menuDividers=UserDefaults.standard.bool(forKey:"menuDividers") {
        didSet {persistMenuSetting(menuDividers,forKey:"menuDividers");updateMenu()}
    }
    private func persistMenuSetting(_ value:Any,forKey key:String) {
        if !isFanControlPreview {UserDefaults.standard.set(value,forKey:key)}
    }
    private var batchingMenuAppearance=false
    @Published var theme=UserDefaults.standard.string(forKey:"theme") ?? "system" {
        didSet { if !isFanControlPreview {UserDefaults.standard.set(theme,forKey:"theme")};applyTheme() }
    }
    var colorScheme:ColorScheme? { theme == "dark" ? .dark:(theme == "light" ? .light:nil) }
    func applyTheme() { NSApp.appearance=theme == "dark" ? NSAppearance(named:.darkAqua):(theme == "light" ? NSAppearance(named:.aqua):nil) }
    func updateMenu() { if !batchingMenuAppearance,let snapshot { statusChanged?(snapshot) } }
    func applyMenuPreset(_ preset:Int) {
        batchingMenuAppearance=true
        defer {batchingMenuAppearance=false;updateMenu()}
        menuComposition=nil;menuStyle="custom";menuTileColors=[:];menuTileIcons=[:];menuTileLabels=[:];menuSpacing=MenuBarLayout.defaultSpacing;menuGraphWidth=44
        let layout=MenuBarPreset(rawValue:preset) ?? .minimal
        menuItems=layout.items;menuTileStyles=layout.styles;menuGraphBackground=layout.background
    }
    func toggleMenu(_ metric:MenuMetric,_ enabled:Bool) {
        if enabled { if !menuItems.contains(metric) { menuItems.append(metric) } }
        else if menuItems.count>1 { menuItems.removeAll { $0==metric } }
    }
    func moveMenu(_ metric:MenuMetric,_ offset:Int) {
        guard let i=menuItems.firstIndex(of:metric),menuItems.indices.contains(i+offset) else { return }
        menuItems.swapAt(i,i+offset)
    }
    var coolingStatus:String {
        if let scene=activeFanScene {return scene.name}
        if let activeProfile { return activeProfile == .custom ? controlName:activeProfile.rawValue+"模式" }
        if coolingToken != nil { return requestedProfile == nil ? "加强散热会话":"等待模式确认" }
        guard let fans=snapshot?.fans,!fans.isEmpty else { return "风扇状态未知" }
        return fans.allSatisfy { $0.manual==false } ? "系统自动":"手动 / 外部控制"
    }
    // Preserve sampling, diagnostics and menu data while hidden; only defer view invalidation.
    private var visualUpdatesEnabled=true
    func setVisualUpdatesEnabled(_ enabled:Bool) {
        guard enabled != visualUpdatesEnabled else{return}
        visualUpdatesEnabled=enabled
        if enabled {
            readings.resumeVisualUpdates();metricHistory.resumeVisualUpdates();sensorHistory.resumeVisualUpdates();timeline.resumeVisualUpdates();fanControl.resumeVisualUpdates();electricity.resumeVisualUpdates()
        }
    }
    private func receiveTelemetry(_ value:SystemTelemetry) {
        readings.update(value,publish:visualUpdatesEnabled)
    }
    private(set) var history:[Snapshot]=[]
    @Published var events:[TimelineEvent]=[]
    @Published var interval:Double=5 { didSet { UserDefaults.standard.set(interval,forKey:"sampleInterval");schedule() } }
    @Published var busy=false
    @Published var coolingToken:String?
    @Published var message="正在读取本机传感器…"
    @Published var messageIsError=false
    @Published var noticeVisible=false
    @Published var lastAction="尚未执行硬件控制"
    @Published var confirmedEnergy:ThermalProfile?
    @Published var controlName="自定义曲线"
    private var queuedCurve:FanCurve?
    private var queuedName="自定义曲线"
    @Published private(set) var sessionCurve:FanCurve?
    @Published var fanScenes:FanSceneConfiguration=FanSceneConfiguration() {
        didSet {if !isFanControlPreview,let data=try? JSONEncoder().encode(fanScenes) {UserDefaults.standard.set(data,forKey:"fanSceneConfiguration")}}
    }
    @Published var activeFanSceneID:String?
    @Published var pendingFanStrategy:FanStrategy?
    @Published var fanStopTimer:FanStopTimer?
    var fanStopWork:DispatchWorkItem?
    @Published var fanAutomation=FanSceneAutomation() {
        didSet {if !isFanControlPreview,let data=try? JSONEncoder().encode(fanAutomation) {UserDefaults.standard.set(data,forKey:"fanSceneAutomation")}}
    }
    @Published var fanAutomationApplication:FanApplication?
    var fanAutomationApplying=false
    var fanAutomationLastAttempt:FanModeSelection?
    var fanAutomationWork:DispatchWorkItem?
    var fanApplicationSnapshot:(()->(running:[FanApplication],frontmost:String?))?
    var queuedFanSelection:FanModeSelection = .strategy(.custom)
    var fanRestorePending=false
    var fanRestoreDeadline=Date.distantPast
    var fanSuspending=false
    var energyMode:ThermalProfile? {
        guard let confirmedEnergy,let state=snapshot?.turbo else { return nil }
        return state == (confirmedEnergy.disablesTurbo ? .disabledDriverLoaded:.driverNotLoaded) ? confirmedEnergy:nil
    }
    func applyFanCurve(_ curve:FanCurve,name:String,selection:FanModeSelection = .strategy(.custom)) {
        guard !busy else{return}
        pauseFanAutomationForManualSelection()
        queuedCurve=curve;queuedName=name;queuedFanSelection=selection;applyProfile(.custom)
    }
    func applyCustomCurve() {
        guard !busy else{return}
        pauseFanAutomationForManualSelection()
        queuedCurve=nil;queuedName="自定义曲线";queuedFanSelection = .strategy(.custom);applyProfile(.custom)
    }
    @Published var tab=0
    @Published var customCurve:FanCurve = .balanced {
        didSet { if !CommandLine.arguments.contains("--ui-check"),(try? customCurve.validate()) != nil,let data=try? JSONEncoder().encode(customCurve) { UserDefaults.standard.set(data,forKey:"customFanCurve") } }
    }
    @Published var requestedProfile:ThermalProfile?
    var activeProfile:ThermalProfile? {
        guard let profile=requestedProfile,coolingToken != nil,let s=snapshot,!s.fans.isEmpty,s.fans.allSatisfy({$0.manual==true}) else { return nil }
        if profile.disablesTurbo && s.turbo != .disabledDriverLoaded { return nil }
        if (profile == .balanced || profile == .performance) && s.turbo != .driverNotLoaded { return nil }
        return profile
    }
    var statusChanged: ((Snapshot)->Void)?
    private let queue=DispatchQueue(label:"local.thermalscope.sampler",qos:.utility)
    private let sampler=HardwareSampler()
    private var timer:DispatchSourceTimer?
    private var lastLimit:Bool?
    private var lastTurbo:TurboState?
    private var observers:[NSObjectProtocol]=[]

    init() {
        tokens.onChange={ [weak self] in self?.updateMenu() }
        optimization.perform={ [weak self] request,completion in
            self?.control(request,completion:completion)
        }
        if menuItems.isEmpty { menuItems=[.temperature] }
        let savedInterval=UserDefaults.standard.double(forKey:"sampleInterval")
        if savedInterval==2 || savedInterval==5 { interval=savedInterval }
        if let data=UserDefaults.standard.data(forKey:"customFanCurve"),let curve=try? JSONDecoder().decode(FanCurve.self,from:data),(try? curve.validate()) != nil { customCurve=curve }
        if !isFanControlPreview {
            fanScenes=FanSceneConfiguration.decode(UserDefaults.standard.data(forKey:"fanSceneConfiguration"))
            fanAutomation=FanSceneAutomation.decode(UserDefaults.standard.data(forKey:"fanSceneAutomation"),scenes:fanScenes.scenes)
        }
        prepareFanRestoration()
        schedule()
        let center=NSWorkspace.shared.notificationCenter
        for notification in [NSWorkspace.didLaunchApplicationNotification,NSWorkspace.didTerminateApplicationNotification,NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName:notification,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated {self?.scheduleFanAutomation()}
            })
        }
        observers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.electricity.suspend();self?.fanSuspending=true;self?.stopCooling() }
        })
        observers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.electricity.resume()
                self?.stopCooling { [weak self] in
                    self?.fanSuspending=false;self?.resumeFanStopTimerAfterWake();self?.fanAutomationLastAttempt=nil;self?.prepareFanRestoration();self?.refresh(reset:true)
                }
            }
        })
    }
    func schedule() {
        timer?.cancel()
        let source=DispatchSource.makeTimerSource(queue:queue)
        let sampler=self.sampler
        source.schedule(deadline:.now(),repeating:interval,leeway:.milliseconds(200))
        var telemetryTick=0
        source.setEventHandler { [weak self] in
            let sample=sampler.sample()
            let telemetry=telemetryTick % 5 == 0 ? SystemTelemetry.read():nil
            telemetryTick+=1
            DispatchQueue.main.async {
                if let telemetry {self?.receiveTelemetry(telemetry)}
                self?.receive(sample)
            }
        }
        timer=source; source.resume()
    }
    func refresh(reset:Bool=false) {
        optimization.refresh()
        let sampler=self.sampler
        queue.async { [weak self] in
            if reset { sampler.reset() }
            sampler.refreshTurbo()
            let s=sampler.sample()
            DispatchQueue.main.async { self?.receive(s) }
        }
    }
    private func receive(_ incoming:Snapshot) {
        let sample=fanPreview?.decorate(incoming) ?? incoming
        let previous=snapshot
        let stateChanged=previous==nil || previous?.turbo != sample.turbo || previous?.fans.map(\.manual) != sample.fans.map(\.manual) || previous?.smcAvailable != sample.smcAvailable
        if stateChanged {objectWillChange.send()}
        readings.update(sample,publish:visualUpdatesEnabled)
        metricHistory.record(sample,telemetry:telemetry,publish:visualUpdatesEnabled)
        sensorHistory.record(sample,menuSensors:retainedSensorReferences,publish:visualUpdatesEnabled)
        if !isFanControlPreview {electricity.record(sample,telemetry:telemetry,publish:visualUpdatesEnabled)}
        widgetPublisher.record(sample,mode:coolingStatus,language:AppLocalization.shared.resolvedLanguage,history:metricHistory)
        optimization.record(sample,telemetry:telemetry)
        diagnostics.receive(sample,telemetry:telemetry,processes:processes,power:optimization)
        let observedMode:String?
        if let activeProfile {
            observedMode=activeProfile == .custom ? (activeFanScene?.name ?? controlName):activeProfile.rawValue
            if ThermalProfile.energyModes.contains(activeProfile),confirmedEnergy != activeProfile { confirmedEnergy=activeProfile }
        }
        else if coolingToken != nil { observedMode=nil }
        else if !sample.fans.isEmpty && sample.fans.allSatisfy({$0.manual==false}) { observedMode="系统自动" }
        else if !sample.fans.isEmpty && sample.fans.allSatisfy({$0.manual==true}) { observedMode="外部控制" }
        else { observedMode=nil }
        timeline.append(sample,mode:observedMode,publish:visualUpdatesEnabled)
        if Date().timeIntervalSince(lastHelperPoll)>=3 {
            lastHelperPoll=Date()
            if let fanPreview {receiveControl(.success(fanPreview.status()),poll:true)}
            else {controller.poll { [weak self] result in
                DispatchQueue.main.async { self?.receiveControl(result,poll:true) }
            }}
        }
        history.append(sample)
        let cutoff=Date().addingTimeInterval(-1800)
        history.removeAll { $0.date<cutoff }
        if (sample.limitKnown || sample.limited),let old=lastLimit,old != sample.limited {
            addEvent(sample.limited ? "检测到性能限制":"系统性能上限恢复",detail:"速度 \(sample.speedLimit.map(String.init) ?? "未知")% · 调度 \(sample.schedulerLimit.map(String.init) ?? "未知")%",warning:sample.limited)
        } else if lastLimit==nil && sample.limited { addEvent("启动时已存在性能限制",detail:sample.assessment,warning:true) }
        if let old=lastTurbo,old != sample.turbo { addEvent("睿频驱动状态改变",detail:sample.turbo.title,warning:false) }
        if sample.limitKnown || sample.limited { lastLimit=sample.limited }
        lastTurbo=sample.turbo
        statusChanged?(sample)
        if message=="正在读取本机传感器…" { message="监测已启动 · 硬件设置保持原样" }
        restoreSavedFanModeIfNeeded()
        evaluateFanAutomation()
    }
    func addEvent(_ title:String,detail:String,warning:Bool) {
        events.insert(TimelineEvent(title:title,detail:detail,warning:warning),at:0)
        if events.count>100 { events.removeLast(events.count-100) }
    }
    private func conflictingApp(_ names:[String]) -> String? {
        NSWorkspace.shared.runningApplications.compactMap(\.localizedName).first { name in names.contains { name.localizedCaseInsensitiveContains($0) } }
    }
    private func receiveControl(_ result:Result<ControlReply,Error>,poll:Bool=false) {
        if !poll { busy=false;pendingFanStrategy=nil }
        switch result {
        case .success(let reply):
            if !authorizationReady {authorizationReady=true}
            fanControl.update(reply.ok && reply.session != nil ? reply.fanStatus:nil,publish:visualUpdatesEnabled)
            let previous=coolingToken
            if coolingToken != reply.session {coolingToken=reply.session;sessionCurve=nil;activeFanSceneID=nil}
            if poll,previous != nil,reply.session==nil,!fanSuspending,!fanRestorePending {
                clearFanStopTimer()
                fanScenes.selection = .strategy(.system)
                pauseFanAutomationForManualSelection()
            }
            let nextProfile=reply.profile.flatMap { command in ThermalProfile.allCases.first(where:{$0.command==command}) }
            if requestedProfile != nextProfile {requestedProfile=nextProfile}
            if let label=reply.label,controlName != label { controlName=label }
            if let fanPreview {sessionCurve=fanPreview.curve}
            if !reply.ok {
                if !fanSuspending {clearFanStopTimer()}
                sessionCurve=nil
                if !messageIsError || message != reply.message { report(reply.message,error:true);addEvent("硬件控制未完成",detail:reply.message,warning:true) }
            } else if !poll || (previous != nil && reply.session==nil) {
                report(reply.message,error:false)
                if !poll {addEvent("操作已确认",detail:reply.message,warning:false)}
            }
            if let mode=requestedProfile,ThermalProfile.energyModes.contains(mode),confirmedEnergy != mode {confirmedEnergy=mode}
        case .failure(let error):
            if !fanSuspending {clearFanStopTimer()}
            fanControl.update(nil,publish:visualUpdatesEnabled)
            authorizationReady=false;coolingToken=nil;requestedProfile=nil;sessionCurve=nil;activeFanSceneID=nil
            report(error.localizedDescription,error:true)
        }
        if !poll {refresh()}
    }
    private func control(_ request:ControlRequest,completion:((Result<ControlReply,Error>)->Void)?=nil) {
        guard AppDistribution.hardwareControlAvailable else {let error=ScopeError.message(L(AppDistribution.monitoringOnlyMessage));report(error.localizedDescription,error:true);completion?(.failure(error));return}
        guard !busy else {completion?(.failure(ScopeError.message("另一项操作尚未完成")));return}
        if request.command=="profile" {
            if case .strategy(let strategy)=queuedFanSelection {pendingFanStrategy=strategy}
            else {pendingFanStrategy = .custom}
        } else if request.command=="auto" {pendingFanStrategy = .system}
        else if request.command=="test-fans" {pendingFanStrategy = .custom}
        else {pendingFanStrategy=nil}
        busy=true
        report(authorizationReady ? "正在应用，等待硬件确认…":"首次控制需要系统授权；本次运行内复用原生连接…",error:false)
        if let fanPreview {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds:700_000_000)
                let result=Result {try fanPreview.handle(request)}
                self?.receiveControl(result);completion?(result)
            }
            return
        }
        controller.request(request) { [weak self] result in
            DispatchQueue.main.async {self?.receiveControl(result);completion?(result)}
        }
    }
    func startCooling() {startFanTest()}
    func stopCooling(after completion:(()->Void)?=nil) {
        guard coolingToken != nil else {completion?();return}
        if let fanPreview {receiveControl(Result{try fanPreview.handle(ControlRequest("auto"))});completion?();return}
        controller.request(ControlRequest("auto"),allowAuthorization:false) { [weak self] result in
            DispatchQueue.main.async {self?.receiveControl(result);completion?()}
        }
    }
    var displayedControlMode:ThermalProfile? {
        if ControlAvailability.isAppleSilicon,activeProfile == .custom,let curve=sessionCurve {
            return [ThermalProfile.balanced,.performance,.quiet].first {$0.curve==curve}
        }
        if let active=activeProfile,ThermalProfile.energyModes.contains(active) {return active}
        if coolingToken==nil,let fans=snapshot?.fans,!fans.isEmpty,fans.allSatisfy({$0.manual==false}) {return .automatic}
        return nil
    }
    func applyProfile(_ profile:ThermalProfile) {
        guard !busy else{return}
        pauseFanAutomationForManualSelection()
        if profile == .automatic {restoreAuto();return}
        if ControlAvailability.isAppleSilicon,profile != .custom {
            queuedCurve=profile.curve;queuedName=profile.rawValue+"模式"
            applyProfile(.custom);return
        }
        if !isFanControlPreview,let app=conflictingApp(["Macs Fan Control","smcFanControl","TG Pro"]) {report("请先退出 \(app)，避免争抢风扇控制。",error:true);return}
        if !isFanControlPreview,profile != .custom,let app=conflictingApp(["Turbo Boost Switcher"]) {report("请先退出 \(app)，避免自动规则覆盖模式。",error:true);return}
        let curve=profile == .custom ? (queuedCurve ?? customCurve):profile.curve
        do {try curve.validate()} catch {report(error.localizedDescription,error:true);return}
        let name=profile == .custom ? queuedName:profile.rawValue
        let selection:FanModeSelection=profile == .custom ? queuedFanSelection:.strategy(profile == .performance ? .cooling:(profile == .quiet || profile == .eco ? .quiet:.balanced))
        let seconds=fanStopTimer?.remaining()
        if let seconds,seconds<=0 {expireFanStopTimerIfNeeded();return}
        let automatic=fanAutomationApplying
        queuedFanSelection=selection
        control(ControlRequest("profile",profile:profile.command,curve:curve,duration:seconds,label:name,continuous:seconds==nil)) { [weak self] result in
            guard case .success(let reply)=result,reply.ok,let session=reply.session,reply.profile==profile.command,self?.coolingToken==session else{
                if automatic {self?.pauseFanAutomationForManualSelection()}
                return
            }
            self?.sessionCurve=curve
            self?.confirmFanSelection(selection,curve:curve,automatic:automatic)
        }
    }
    func restoreAuto() {
        guard !busy else{return}
        if !fanAutomationApplying {clearFanStopTimer()}
        pauseFanAutomationForManualSelection()
        if !fanAutomationApplying {fanAutomation.manualSelection = .strategy(.system)}
        fanRestorePending=false;fanScenes.selection = .strategy(.system)
        queuedFanSelection = .strategy(.system)
        if coolingToken==nil,let fans=snapshot?.fans,!fans.isEmpty,fans.allSatisfy({$0.manual==false}) {
            report("风扇由系统管理",error:false);return
        }
        if !isFanControlPreview,let app=conflictingApp(["Macs Fan Control","smcFanControl","TG Pro"]) {report("请先退出 \(app)，避免它覆盖风扇设置。",error:true);return}
        let automatic=fanAutomationApplying
        control(ControlRequest("auto")) { [weak self] result in
            if automatic {
                if case .success(let reply)=result,reply.ok {return}
                self?.pauseFanAutomationForManualSelection()
            }
        }
    }
    func startFanTest() {
        guard !busy else{return}
        clearFanStopTimer()
        pauseFanAutomationForManualSelection()
        fanRestorePending=false
        if let app=conflictingApp(["Macs Fan Control","smcFanControl","TG Pro"]) {report("请先退出 \(app)，避免争抢风扇控制。",error:true);return}
        control(ControlRequest("test-fans"))
    }
    func changeTurbo(disable:Bool) {
        if let app=conflictingApp(["Turbo Boost Switcher"]) {report("请先退出 \(app)，避免自动规则覆盖睿频设置。",error:true);return}
        confirmedEnergy=nil
        control(ControlRequest(disable ? "turbo-disable":"turbo-enable"))
    }
    func follow(_ action:DiagnosticAction) {
        switch action {
        case .reviewApplication(let id):navigation.applicationID=id
        case .memoryProcesses:processes.sort = .memory;navigation.go(.processes)
        case .diskProcesses:processes.sort = .disk;navigation.go(.processes)
        case .temperatureTimeline:navigation.go(.temperature)
        case .wakeRequests:navigation.showWakeRequests=true
        case .lowPowerPlan:
            guard SystemCapabilities.lowPowerMode else{return}
            if optimization.backup==nil && !optimization.busy {
                optimization.lowPower=true;optimization.scope = .current
                optimization.displaySleep=false;optimization.idleSleep=false;optimization.disableTurbo=false
            }
            navigation.optimizationTab=0;navigation.optimizationExpanded=true;navigation.go(.optimization)
        case .refresh:refresh()
        }
    }
    func report(_ text:String,error:Bool) { message=text; messageIsError=error;noticeVisible=true }
    func dismissNotice() { noticeVisible=false;messageIsError=false }
    func exportCSV() {
        let panel=NSSavePanel()
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyy-MM-dd"
        panel.nameFieldStringValue="showmac-"+formatter.string(from:Date())+".csv"
        panel.title=L("导出最近 30 分钟监测数据")
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do { try Export.csv(history).write(to:url,atomically:true,encoding:.utf8); report(String(format:L("已导出 %d 条采样。"),history.count),error:false) }
        catch { report(error.localizedDescription,error:true) }
    }
    func shutdown() { fanSuspending=true;fanRestorePending=false;fanStopWork?.cancel();fanAutomationWork?.cancel();electricity.shutdown();tokens.shutdown();updates.shutdown();widgetPublisher.shutdown();controller.shutdown(); processes.shutdown();optimization.shutdown();timer?.cancel() }
}
