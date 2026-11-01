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
    let navigation=DiagnosticNavigation()
    @Published var language=UserDefaults.standard.string(forKey:"appLanguage") ?? "system" {
        didSet {UserDefaults.standard.set(language,forKey:"appLanguage");AppLocalization.shared.set(language);languageChanged?()}
    }
    var languageChanged:(()->Void)?
    var statusMenuRequested:(()->Void)?
    let readings=LiveReadings()
    var snapshot:Snapshot? {readings.snapshot}
    var telemetry:SystemTelemetry? {readings.telemetry}
    let timeline=TemperatureTimelineStore()
    let metricHistory=MetricHistoryStore()
    let widgetPublisher=WidgetPublisher()
    private let controller=NativeControlClient()
    @Published var authorizationReady=false
    private var lastHelperPoll=Date.distantPast
    @Published var menuItems:[MenuMetric]=(UserDefaults.standard.stringArray(forKey:"menuItems") ?? ["temperature","cpu"]).compactMap(MenuMetric.init(rawValue:)) {
        didSet { UserDefaults.standard.set(menuItems.map(\.rawValue),forKey:"menuItems");updateMenu() }
    }
    @Published var menuStyle=UserDefaults.standard.string(forKey:"menuStyle") ?? "custom" {
        didSet { UserDefaults.standard.set(menuStyle,forKey:"menuStyle");updateMenu() }
    }
    @Published var menuGraph=(UserDefaults.standard.object(forKey:"menuCPUGraph") as? Bool) ?? true {
        didSet {UserDefaults.standard.set(menuGraph,forKey:"menuCPUGraph");updateMenu()}
    }
    @Published var statusMinutes:Int=[2,5,10].contains(UserDefaults.standard.integer(forKey:"statusMinutes")) ? UserDefaults.standard.integer(forKey:"statusMinutes"):2 {
        didSet {UserDefaults.standard.set(statusMinutes,forKey:"statusMinutes")}
    }
    @Published var statusTemperature:MetricKind={
        let value=MetricKind(rawValue:UserDefaults.standard.string(forKey:"statusTemperature") ?? "") ?? .cpuTemperature
        return value.sensor != nil ? value:.cpuTemperature
    }() {
        didSet {UserDefaults.standard.set(statusTemperature.rawValue,forKey:"statusTemperature")}
    }
    @Published var menuGraphKind=MetricKind(rawValue:UserDefaults.standard.string(forKey:"menuGraphKind") ?? "") ?? .cpuUsage {
        didSet {UserDefaults.standard.set(menuGraphKind.rawValue,forKey:"menuGraphKind");updateMenu()}
    }
    @Published var menuGraphStyle=MenuGraphStyle(rawValue:UserDefaults.standard.string(forKey:"menuGraphStyle") ?? "") ?? .line {
        didSet {UserDefaults.standard.set(menuGraphStyle.rawValue,forKey:"menuGraphStyle");updateMenu()}
    }
    @Published var menuGraphWidth:Double=[44.0,66,88].contains(UserDefaults.standard.double(forKey:"menuGraphWidth")) ? UserDefaults.standard.double(forKey:"menuGraphWidth"):44 {
        didSet {UserDefaults.standard.set(menuGraphWidth,forKey:"menuGraphWidth");updateMenu()}
    }
    @Published var menuTileStyles=(UserDefaults.standard.dictionary(forKey:"menuTileStyles") as? [String:String]) ?? [:] {
        didSet {UserDefaults.standard.set(menuTileStyles,forKey:"menuTileStyles");updateMenu()}
    }
    @Published var menuTileColors=(UserDefaults.standard.dictionary(forKey:"menuTileColors") as? [String:String]) ?? [:] {
        didSet {UserDefaults.standard.set(menuTileColors,forKey:"menuTileColors");updateMenu()}
    }
    @Published var menuBarTheme=MenuBarTheme(rawValue:UserDefaults.standard.string(forKey:"menuBarTheme") ?? "") ?? .accent {
        didSet {UserDefaults.standard.set(menuBarTheme.rawValue,forKey:"menuBarTheme");updateMenu()}
    }
    @Published var menuSpacing:Double=UserDefaults.standard.double(forKey:"menuSpacing")==9 ? 9:4 {
        didSet {UserDefaults.standard.set(menuSpacing,forKey:"menuSpacing");updateMenu()}
    }
    @Published var menuGraphBackground=UserDefaults.standard.bool(forKey:"menuGraphBackground") {
        didSet {UserDefaults.standard.set(menuGraphBackground,forKey:"menuGraphBackground");updateMenu()}
    }
    @Published var menuCPUWarnings=(UserDefaults.standard.object(forKey:"menuCPUWarnings") as? Bool) ?? true {
        didSet {UserDefaults.standard.set(menuCPUWarnings,forKey:"menuCPUWarnings");updateMenu()}
    }
    private var batchingMenuAppearance=false
    @Published var theme=UserDefaults.standard.string(forKey:"theme") ?? "system" {
        didSet { UserDefaults.standard.set(theme,forKey:"theme");applyTheme() }
    }
    var colorScheme:ColorScheme? { theme == "dark" ? .dark:(theme == "light" ? .light:nil) }
    func applyTheme() { NSApp.appearance=theme == "dark" ? NSAppearance(named:.darkAqua):(theme == "light" ? NSAppearance(named:.aqua):nil) }
    func updateMenu() { if !batchingMenuAppearance,let snapshot { statusChanged?(snapshot) } }
    func applyMenuPreset(_ preset:Int) {
        batchingMenuAppearance=true
        defer {batchingMenuAppearance=false;updateMenu()}
        menuStyle="custom";menuTileColors=[:];menuSpacing=4;menuGraphWidth=44
        let layout=MenuBarPreset(rawValue:preset) ?? .minimal
        menuItems=layout.items;menuTileStyles=layout.styles;menuBarTheme=layout.theme;menuGraphBackground=layout.background
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
            readings.resumeVisualUpdates();metricHistory.resumeVisualUpdates();timeline.resumeVisualUpdates()
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
    @Published var lastAction="尚未执行硬件控制"
    @Published var confirmedEnergy:ThermalProfile?
    @Published var manualPercent:Double=50
    @Published var controlName="自定义曲线"
    private var queuedCurve:FanCurve?
    private var queuedName="自定义曲线"
    @Published private(set) var sessionCurve:FanCurve?
    var energyMode:ThermalProfile? {
        guard let confirmedEnergy,let state=snapshot?.turbo else { return nil }
        return state == (confirmedEnergy.disablesTurbo ? .disabledDriverLoaded:.driverNotLoaded) ? confirmedEnergy:nil
    }
    func applyManual() {
        queuedCurve = .manual(percent:manualPercent);queuedName="手动转速"
        applyProfile(.custom)
    }
    func applyCustomCurve() {
        queuedCurve=nil;queuedName="自定义曲线";applyProfile(.custom)
    }
    @Published var tab=0
    @Published var customCurve:FanCurve = .balanced {
        didSet { if (try? customCurve.validate()) != nil,let data=try? JSONEncoder().encode(customCurve) { UserDefaults.standard.set(data,forKey:"customFanCurve") } }
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
        optimization.perform={ [weak self] request,completion in
            self?.control(request,completion:completion)
        }
        if menuItems.isEmpty { menuItems=[.temperature] }
        let savedInterval=UserDefaults.standard.double(forKey:"sampleInterval")
        if savedInterval==2 || savedInterval==5 { interval=savedInterval }
        if let data=UserDefaults.standard.data(forKey:"customFanCurve"),let curve=try? JSONDecoder().decode(FanCurve.self,from:data),(try? curve.validate()) != nil { customCurve=curve }
        schedule()
        let center=NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopCooling() }
        })
        observers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(reset:true) }
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
    private func receive(_ sample:Snapshot) {
        let previous=snapshot
        let stateChanged=previous==nil || previous?.turbo != sample.turbo || previous?.fans.map(\.manual) != sample.fans.map(\.manual) || previous?.smcAvailable != sample.smcAvailable
        if stateChanged {objectWillChange.send()}
        readings.update(sample,publish:visualUpdatesEnabled)
        metricHistory.record(sample,telemetry:telemetry,publish:visualUpdatesEnabled)
        widgetPublisher.record(sample,mode:coolingStatus,language:AppLocalization.shared.resolvedLanguage,history:metricHistory)
        optimization.record(sample,telemetry:telemetry)
        diagnostics.receive(sample,telemetry:telemetry,processes:processes,power:optimization)
        let observedMode:String?
        if let activeProfile {
            observedMode=activeProfile == .custom ? controlName:activeProfile.rawValue
            if ThermalProfile.energyModes.contains(activeProfile),confirmedEnergy != activeProfile { confirmedEnergy=activeProfile }
        }
        else if coolingToken != nil { observedMode=nil }
        else if !sample.fans.isEmpty && sample.fans.allSatisfy({$0.manual==false}) { observedMode="系统自动" }
        else if !sample.fans.isEmpty && sample.fans.allSatisfy({$0.manual==true}) { observedMode="外部控制" }
        else { observedMode=nil }
        timeline.append(sample,mode:observedMode,publish:visualUpdatesEnabled)
        if Date().timeIntervalSince(lastHelperPoll)>=3 {
            lastHelperPoll=Date()
            controller.poll { [weak self] result in
                DispatchQueue.main.async { self?.receiveControl(result,poll:true) }
            }
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
    }
    func addEvent(_ title:String,detail:String,warning:Bool) {
        events.insert(TimelineEvent(title:title,detail:detail,warning:warning),at:0)
        if events.count>100 { events.removeLast(events.count-100) }
    }
    private func conflictingApp(_ names:[String]) -> String? {
        NSWorkspace.shared.runningApplications.compactMap(\.localizedName).first { name in names.contains { name.localizedCaseInsensitiveContains($0) } }
    }
    private func receiveControl(_ result:Result<ControlReply,Error>,poll:Bool=false) {
        if !poll { busy=false }
        switch result {
        case .success(let reply):
            if !authorizationReady {authorizationReady=true}
            let previous=coolingToken
            if coolingToken != reply.session {coolingToken=reply.session;sessionCurve=nil}
            let nextProfile=reply.profile.flatMap { command in ThermalProfile.allCases.first(where:{$0.command==command}) }
            if requestedProfile != nextProfile {requestedProfile=nextProfile}
            if let label=reply.label,controlName != label { controlName=label }
            if !reply.ok {
                sessionCurve=nil
                if !messageIsError || message != reply.message { report(reply.message,error:true);addEvent("硬件控制未完成",detail:reply.message,warning:true) }
            } else if !poll || (previous != nil && reply.session==nil) {
                report(reply.message,error:false)
                if !poll {addEvent("操作已确认",detail:reply.message,warning:false)}
            }
            if let mode=requestedProfile,ThermalProfile.energyModes.contains(mode),confirmedEnergy != mode {confirmedEnergy=mode}
        case .failure(let error):
            authorizationReady=false;coolingToken=nil;requestedProfile=nil;sessionCurve=nil
            report(error.localizedDescription,error:true)
        }
        if !poll {refresh()}
    }
    private func control(_ request:ControlRequest,completion:((Result<ControlReply,Error>)->Void)?=nil) {
        guard !busy else {completion?(.failure(ScopeError.message("另一项操作尚未完成")));return}
        busy=true
        message=authorizationReady ? "正在应用，等待硬件确认…":"首次控制需要系统授权；本次运行内复用原生连接…"
        messageIsError=false
        controller.request(request) { [weak self] result in
            DispatchQueue.main.async {self?.receiveControl(result);completion?(result)}
        }
    }
    func startCooling() {startFanTest()}
    func stopCooling() {
        guard coolingToken != nil else {return}
        controller.request(ControlRequest("auto"),allowAuthorization:false) { [weak self] result in
            DispatchQueue.main.async {self?.receiveControl(result)}
        }
    }
    func applyProfile(_ profile:ThermalProfile) {
        if profile == .automatic {restoreAuto();return}
        if let app=conflictingApp(["Macs Fan Control","smcFanControl","TG Pro"]) {report("请先退出 \(app)，避免争抢风扇控制。",error:true);return}
        if profile != .custom,let app=conflictingApp(["Turbo Boost Switcher"]) {report("请先退出 \(app)，避免自动规则覆盖模式。",error:true);return}
        let curve=profile == .custom ? (queuedCurve ?? customCurve):profile.curve
        do {try curve.validate()} catch {report(error.localizedDescription,error:true);return}
        let name=profile == .custom ? queuedName:profile.rawValue
        control(ControlRequest("profile",profile:profile.command,curve:curve,duration:1800,label:name)) { [weak self] result in
            guard case .success(let reply)=result,reply.ok,let session=reply.session,reply.profile==profile.command,self?.coolingToken==session else{return}
            self?.sessionCurve=curve
        }
    }
    func restoreAuto() {
        if coolingToken==nil,let fans=snapshot?.fans,!fans.isEmpty,fans.allSatisfy({$0.manual==false}) {
            report("风扇由系统管理",error:false);return
        }
        if let app=conflictingApp(["Macs Fan Control","smcFanControl","TG Pro"]) {report("请先退出 \(app)，避免它覆盖风扇设置。",error:true);return}
        control(ControlRequest("auto"))
    }
    func startFanTest() {
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
            if optimization.backup==nil && !optimization.busy {
                optimization.lowPower=true;optimization.scope = .current
                optimization.displaySleep=false;optimization.idleSleep=false;optimization.disableTurbo=false
            }
            navigation.optimizationTab=0;navigation.optimizationExpanded=true;navigation.go(.optimization)
        case .refresh:refresh()
        }
    }
    func report(_ text:String,error:Bool) { message=text; messageIsError=error }
    func exportCSV() {
        let panel=NSSavePanel()
        panel.nameFieldStringValue="ThermalScope-\(Date().formatted(.iso8601.year().month().day())) .csv".replacingOccurrences(of:" .csv",with:".csv")
        panel.title="导出最近 30 分钟监测数据"
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do { try Export.csv(history).write(to:url,atomically:true,encoding:.utf8); report("已导出 \(history.count) 条采样。",error:false) }
        catch { report(error.localizedDescription,error:true) }
    }
    func shutdown() { widgetPublisher.shutdown();controller.shutdown(); processes.shutdown();optimization.shutdown();timer?.cancel() }
}
