import AppKit
import SwiftUI
import ThermalCore

struct ConsoleShell:View {
    @ObservedObject var model:AppModel
    @ObservedObject var navigation:DiagnosticNavigation
    init(model:AppModel) {self.model=model;self.navigation=model.navigation}
    @State private var curveSheet=false
    @State private var diagnostics=false
    @State private var loadEvidence=false
    var body:some View {
        NavigationSplitView {
            navigationSidebar
        } detail: {
            VStack(spacing:0) {
                HStack {
                    VStack(alignment:.leading,spacing:5) {
                        Text(model.tab==1 ? L("设置"):L(navigation.metric?.title ?? navigation.page.title)).font(.system(size:25,weight:.bold))
                        Text(model.tab==1 ? L("让温控台适合你的使用习惯。"):L(navigation.metric != nil ? "指标详情":navigation.page.subtitle)).font(.system(size:12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.horizontal,28).padding(.top,25).padding(.bottom,model.tab==1 ? 20:14)
                ScrollViewReader { proxy in
                ScrollView(showsIndicators:false) {
                    VStack(alignment:.leading,spacing:18) {
                        if model.messageIsError { OperationNotice(model:model) }
                        if model.tab==1 { PreferencesPage(model:model) }
                        else if let sample=model.snapshot {
                            switch navigation.page {
                            case .metrics:
                                if let metric=navigation.metric {
                                    MetricDetailView(model:model,kind:metric).id(metric)
                                } else {
                                    MetricsDashboard(readings:model.readings,history:model.metricHistory,mode:model.coolingStatus,onTemperature:{sensor in showMetric(sensor == .gpu ? .gpuTemperature:(sensor == .storage ? .storageTemperature:.cpuTemperature))},onControl:{showMetric(.fan)},onMode:{navigation.metric=nil;navigation.page = .thermal},onMemory:{showMetric(.memory)},onCPU:{showMetric(.cpuUsage)})
                                    TemperaturePanel(timeline:model.timeline,expanded:false).equatable().id(ConsoleSection.temperature)
                                    OverviewRecommendations(store:model.diagnostics,onAction:model.follow,onReview:{navigation.go(.findings)})
                                    DisclosureGroup(L("状态详情"),isExpanded:$diagnostics) {LiveThermalDetails(readings:model.readings).padding(.top,12)}
                                }
                            case .optimization:
                                PerformanceDiagnosis(store:model.diagnostics,onAction:model.follow,onCPU:{model.processes.sort = .cpu;navigation.go(.processes)},onOptimize:{navigation.optimizationExpanded=true;navigation.optimizationTab=0;navigation.go(.optimization)})
                                DiagnosticFindingsPanel(store:model.diagnostics,onAction:model.follow).id(ConsoleSection.findings)
                                OptimizationWorkbench(optimizer:model.optimization,navigation:navigation,globalBusy:model.busy).id(ConsoleSection.optimization)
                            case .thermal:
                                PowerModes(model:model)
                                fanControls(sample)
                                turboControls(sample)
                            case .processes:
                                ProcessObserverPanel(observer:model.processes,onInspect:{navigation.applicationID=$0}).id(ConsoleSection.processes)
                                DisclosureGroup(L("负载依据"),isExpanded:$loadEvidence) {LoadEvidencePanel(observer:model.processes).padding(.top,12)}
                            case .history:
                                VStack(alignment:.leading,spacing:14) {
                                    HStack { Text(L("最近的操作")).font(.headline);Spacer();Button(L("导出采样")) {model.exportCSV()}.buttonStyle(.borderless) }
                                    if model.events.isEmpty { Text(L("暂无操作记录")).font(.caption).foregroundStyle(.secondary) }
                                    ForEach(model.events.prefix(20)) {event in
                                        VStack(alignment:.leading,spacing:5) {Text(L(event.title)).font(.callout);Text(L(event.detail)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}
                                    }
                                }.padding(22).subtlePanel()
                            }
                        } else { ProgressView(L("正在读取这台 Mac 的状态…")).frame(maxWidth:.infinity,minHeight:400) }
                    }.padding(.horizontal,28).padding(.bottom,24)
                }.id(model.tab==1 ? "settings":(navigation.metric?.rawValue ?? navigation.page.rawValue)).onReceive(navigation.$section) {section in
                    guard model.tab==0,let section else{return}
                    DispatchQueue.main.async {proxy.scrollTo(section,anchor:.top)}
                }
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
                .background(AmbientCanvas())
                .toolbar {
                    ToolbarItem(placement:.navigation) {
                        if model.tab==0,navigation.metric != nil {Button {navigation.metric=nil} label:{Label(L("返回实时监测"),systemImage:"chevron.left")}}
                    }
                    ToolbarItem(placement:.primaryAction) {Button {model.refresh()} label:{Label(L("刷新读数"),systemImage:"arrow.clockwise")}}
                }
        }.navigationSplitViewStyle(.balanced).id(model.language).environment(\.locale,Locale(identifier:AppLocalization.shared.resolvedLanguage)).preferredColorScheme(model.colorScheme).tint(Palette.violet).frame(minWidth:900,minHeight:700).transaction { $0.animation=nil;$0.disablesAnimations=true }
            .sheet(isPresented:Binding(get:{navigation.applicationID != nil},set:{if !$0{navigation.applicationID=nil}})) {
                ApplicationReviewSheet(observer:model.processes,groupID:navigation.applicationID ?? "",onClose:{navigation.applicationID=nil}).preferredColorScheme(model.colorScheme).tint(Palette.violet)
            }
            .sheet(isPresented:$navigation.showWakeRequests) {
                SleepRequestsSheet(optimizer:model.optimization,onInspect:model.processes.openActivityMonitor,onClose:{navigation.showWakeRequests=false}).preferredColorScheme(model.colorScheme).tint(Palette.violet)
            }
            .sheet(isPresented:$curveSheet) {
                VStack(spacing:0) {
                    HStack { VStack(alignment:.leading,spacing:4) { Text(L("自定义风扇曲线")).font(.title2.bold());Text(L("让风扇随温度自动调整。")).font(.caption).foregroundStyle(.secondary) };Spacer();Button(L("完成")) {curveSheet=false}.keyboardShortcut(.cancelAction) }.padding(24)
                    ScrollView(showsIndicators:false) { FanCurveEditor(model:model).padding(.horizontal,24).padding(.bottom,24) }
                }.frame(width:740,height:720).preferredColorScheme(model.colorScheme).tint(Palette.violet)
            }
    }
    func showMetric(_ kind:MetricKind) {
        navigation.showMetric(kind)
        if let sensor=kind.sensor {model.timeline.sensor=sensor}
    }
    var navigationSidebar:some View {
        List(selection:Binding<String?>(get:{model.tab==1 ? "settings":navigation.page.rawValue},set:{value in
            guard let value else{return}
            navigation.metric=nil
            if value=="settings" {model.tab=1}
            else if let page=ConsolePage(rawValue:value) {model.tab=0;navigation.page=page}
        })) {
            Section {
                ForEach(ConsolePage.allCases) {page in
                    Label(L(page.title),systemImage:page.symbol).tag(page.rawValue).help(L(page.subtitle))
                }
            }
            Section {Label(L("设置"),systemImage:"gearshape").tag("settings")}
        }.listStyle(.sidebar).scrollIndicators(.hidden).navigationSplitViewColumnWidth(min:180,ideal:220,max:280)
            .safeAreaInset(edge:.bottom) {Label(L("本机实时监测"),systemImage:"dot.radiowaves.left.and.right").font(.caption).foregroundStyle(.secondary).padding(16)}
    }
    func turboControls(_ sample:Snapshot)->some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label(L("Intel 睿频"),systemImage:"bolt.circle.fill").font(.system(size:15,weight:.semibold));Spacer()
                Text(sample.turbo == .disabledDriverLoaded ? L("已关闭"):(sample.turbo == .driverNotLoaded ? L("允许开启"):L("状态不可用"))).font(.system(size:11,weight:.medium)).foregroundStyle(Palette.violet)
            }
            HStack(spacing:10) {
                Button { model.changeTurbo(disable:true) } label:{Label(L("关闭睿频"),systemImage:"leaf.fill").frame(maxWidth:.infinity)}
                    .disabled(model.busy || sample.turbo == .disabledDriverLoaded || sample.turbo == .unsupported)
                Button { model.changeTurbo(disable:false) } label:{Label(L("允许睿频"),systemImage:"bolt.fill").frame(maxWidth:.infinity)}
                    .disabled(model.busy || sample.turbo == .driverNotLoaded || sample.turbo == .unsupported)
            }.buttonStyle(.bordered).controlSize(.large)
            Text(L("独立切换，不中断风扇策略；状态依据禁用驱动。")).font(.system(size:10)).foregroundStyle(.secondary)
        }.padding(22).subtlePanel()
    }
    func fanControls(_ sample:Snapshot)->some View {
        VStack(alignment:.leading,spacing:12) {
            FanCurveEditor(model:model,compact:true,onShowChart:{curveSheet=true})
            if model.messageIsError {
                Button(L("验证风扇控制 · 5 秒后恢复自动")) {model.startFanTest()}.font(.caption).buttonStyle(.borderless).disabled(model.busy)
            }
        }
    }

}

struct PowerModes:View {
    @ObservedObject var model:AppModel
    func tone(_ mode:ThermalProfile)->Color {Palette.violet}
    func icon(_ mode:ThermalProfile)->String { mode == .automatic ? "arrow.triangle.2.circlepath":(mode == .eco ? "leaf.fill":(mode == .quiet ? "speaker.slash.fill":"bolt.fill")) }
    func detail(_ mode:ThermalProfile)->String { mode == .automatic ? L("系统调节风扇"):(mode == .eco ? L("降低性能峰值"):(mode == .quiet ? L("温和散热，减少噪声"):L("保留性能，积极散热"))) }
    var selectedMode:ThermalProfile? {
        if let active=model.activeProfile,ThermalProfile.energyModes.contains(active) {return active}
        if model.coolingToken==nil,let fans=model.snapshot?.fans,!fans.isEmpty,fans.allSatisfy({$0.manual==false}) {return .automatic}
        return nil
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text(L("运行模式")).font(.system(size:15,weight:.semibold));Spacer();Text(selectedMode.map { $0 == .automatic ? L("当前：系统自动"):L($0.rawValue+"策略已确认") } ?? L(model.coolingStatus)).font(.system(size:10)).foregroundStyle(.secondary) }
            HStack(spacing:12) {
                ForEach([ThermalProfile.automatic]+ThermalProfile.energyModes) { mode in
                    Button {if selectedMode != mode {model.applyProfile(mode)}} label: {
                        VStack(alignment:.leading,spacing:10) {
                            HStack { Image(systemName:icon(mode)).font(.system(size:20)).foregroundStyle(tone(mode));Spacer();if selectedMode==mode {Image(systemName:"checkmark.circle.fill").foregroundStyle(tone(mode))} }
                            Text(mode == .automatic ? L("系统自动"):L(mode.rawValue+"模式")).font(.system(size:14,weight:.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.75)
                            Text(detail(mode)).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2).frame(minHeight:26,alignment:.topLeading)
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(16)
                            .background(selectedMode==mode ? Palette.selection:Palette.surface,in:RoundedRectangle(cornerRadius:17))
                            .overlay(RoundedRectangle(cornerRadius:17).stroke(selectedMode==mode ? Palette.violet.opacity(0.6):Palette.border.opacity(0.65),lineWidth:1))
                    }.buttonStyle(.plain).disabled(model.busy).help(L(mode.explanation))
                }
            }
            Text(model.activeProfile == .custom ? L("性能策略保持不变，风扇由下方设置单独管理。"):L("首次控制授权一次；性能与风扇可分别调整。")).font(.system(size:10)).foregroundStyle(.secondary)
        }
    }
}
