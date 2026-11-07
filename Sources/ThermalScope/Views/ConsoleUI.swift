import AppKit
import SwiftUI
import ThermalCore

struct ConsoleShell:View {
    @ObservedObject var model:AppModel
    @ObservedObject var navigation:DiagnosticNavigation
    init(model:AppModel) {self.model=model;self.navigation=model.navigation}
    @State private var diagnostics=false
    @State private var loadEvidence=false
    private var monitorSample:Bool {model.tab==0 && navigation.page == .metrics && navigation.metric==nil}
    var body:some View {
        ConsoleNavigation {
            ConsoleSidebar(model:model)
        } detail: {
            VStack(spacing:0) {
                if model.tab==0 {HStack {
                    VStack(alignment:.leading,spacing:6) {
                        if model.tab==0,let metric=navigation.metric {
                            Text(L(metric.title)).font(AppTypography.title)
                        }
                        Text(L(navigation.metric != nil ? "指标详情":(navigation.page == .thermal && AppDistribution.isAppStore ? AppDistribution.monitoringOnlyMessage:(navigation.page == .thermal && ControlAvailability.isAppleSilicon ? "选择档位，或直接拖动曲线调速。":navigation.page.subtitle)))).font(.system(size:12)).foregroundColor(Palette.secondaryText)
                    }
                    Spacer()
                }.consolePageContent().padding(.top,navigation.metric != nil ? 25:20).padding(.bottom,14)}
                if model.noticeVisible,(model.tab==1 || navigation.page != .thermal || model.messageIsError) {OperationNotice(model:model).padding(.horizontal,28).padding(.bottom,12)}
                if model.tab==0,navigation.page == .thermal {
                    FanControlPage(model:model)
                } else if model.tab==0,navigation.page == .sensors {
                    SensorInventoryPage(model:model,readings:model.readings,history:model.sensorHistory).consolePageContent().padding(.bottom,24)
                } else {
                ScrollViewReader { proxy in
                ScrollView(showsIndicators:false) {
                    VStack(alignment:.leading,spacing:monitorSample ? 20:16) {
                        if model.tab==1 { PreferencesPage(model:model) }
                        else if navigation.page == .electricity {ElectricityUsagePage(model:model)}
                        else if model.snapshot != nil {
                            switch navigation.page {
                            case .metrics:
                                if let metric=navigation.metric {
                                    MetricDetailView(model:model,kind:metric).id(metric)
                                } else {
                                    MetricsDashboard(readings:model.readings,history:model.metricHistory,mode:model.coolingStatus,onTemperature:{sensor in showMetric(sensor == .gpu ? .gpuTemperature:(sensor == .storage ? .storageTemperature:.cpuTemperature))},onControl:{showMetric(.fan)},onMode:{navigation.metric=nil;navigation.page = .thermal},onCPU:{showMetric(.cpuUsage)})
                                    ElectricityOverviewCard(store:model.electricity,tokens:model.tokens,onOpen:{navigation.metric=nil;navigation.usageTab = .electricity;navigation.page = .electricity},onTokens:{navigation.metric=nil;navigation.usageTab = .tokens;navigation.page = .electricity})
                                    TemperaturePanel(timeline:model.timeline,expanded:false,initialArea:true).equatable().id(ConsoleSection.temperature)
                                    SupplementaryMetrics(readings:model.readings,onTemperature:{showMetric($0)},onMemory:{showMetric(.memory)})
                                    OverviewRecommendations(store:model.diagnostics,onAction:model.follow,onReview:{navigation.go(.findings)})
                                    AppDisclosureGroup(L("状态详情"),isExpanded:$diagnostics) {LiveThermalDetails(readings:model.readings).padding(.top,12)}
                                }
                            case .optimization:
                                PerformanceDiagnosisPage(model:model)
                            case .electricity:EmptyView()
                            case .thermal:EmptyView()
                            case .sensors:EmptyView()
                            case .processes:
                                ProcessObserverPanel(observer:model.processes,onInspect:{navigation.applicationID=$0}).id(ConsoleSection.processes)
                                AppDisclosureGroup(L("负载依据"),isExpanded:$loadEvidence) {LoadEvidencePanel(observer:model.processes).padding(.top,12)}
                            case .history:
                                VStack(alignment:.leading,spacing:14) {
                                    HStack { Text(L("最近的操作")).font(AppTypography.section);Spacer();Button(L("导出采样")) {model.exportCSV()}.buttonStyle(.borderless) }
                                    if model.events.isEmpty { Text(L("暂无操作记录")).font(.system(size:12)).foregroundColor(Palette.secondaryText) }
                                    ForEach(model.events.prefix(20)) {event in
                                        HStack(alignment:.top,spacing:12) {
                                            Image(systemName:AppSymbols.resolve(event.warning ? "exclamationmark.circle":"checkmark.circle")).foregroundColor(event.warning ? Color.orange:Palette.violet)
                                            VStack(alignment:.leading,spacing:5) {Text(L(event.title)).font(.callout);Text(L(event.detail)).font(.system(size:12)).foregroundColor(Palette.secondaryText).appTextSelection()}
                                            Spacer()
                                            Text(DateFormatter.localizedString(from:event.date,dateStyle:.short,timeStyle:.medium)).font(.system(size:12)).foregroundColor(Palette.secondaryText).appMonospacedDigit()
                                        }.padding(.vertical,6)
                                    }
                                }.subtlePanel()
                            }
                        } else { ProgressView(L("正在读取这台 Mac 的状态…")).frame(maxWidth:.infinity,minHeight:400) }
                    }.consolePageContent().padding(.top,model.tab==1 ? 20:0).padding(.bottom,24)
                }.id(model.tab==1 ? "settings":(navigation.metric?.rawValue ?? navigation.page.rawValue)).onReceive(navigation.$section) {section in
                    guard model.tab==0,let section else{return}
                    DispatchQueue.main.async {proxy.scrollTo(section,anchor:.top)}
                }
                .onReceive(navigation.$preferencesSection) {section in
                    guard model.tab==1 else{return}
                    DispatchQueue.main.async {proxy.scrollTo(section,anchor:.top)}
                }
                .onAppear {
                    if model.tab==1 {DispatchQueue.main.async {proxy.scrollTo(navigation.preferencesSection,anchor:.top)}}
                }
                }
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
                .modifier(ConsoleDetailCorners())
                .environment(\.neutralPanels,monitorSample)
                .toolbar {
                    ToolbarItem(placement:.navigation) {
                        if model.tab==0,navigation.metric != nil {
                            Button {navigation.metric=nil;navigation.page = .metrics} label:{Label(L("返回实时监测"),systemImage:AppSymbols.resolve("chevron.left"))}
                                .accessibilityIdentifier("backToOverview")
                        }
                    }
                }
        }
            .appBackground {ConsoleWindowBackdrop()}
            .appHideToolbarBackground()
            .foregroundColor(Palette.primaryText).font(AppTypography.body).id(model.language).environment(\.locale,Locale(identifier:AppLocalization.shared.resolvedLanguage)).preferredColorScheme(model.colorScheme).frame(minWidth:900,minHeight:700).transaction { $0.animation=nil;$0.disablesAnimations=true }
            .sheet(isPresented:Binding(get:{navigation.applicationID != nil},set:{if !$0{navigation.applicationID=nil}})) {
                ApplicationReviewSheet(observer:model.processes,groupID:navigation.applicationID ?? "",onClose:{navigation.applicationID=nil}).preferredColorScheme(model.colorScheme)
            }
            .sheet(isPresented:$navigation.showWakeRequests) {
                SleepRequestsSheet(optimizer:model.optimization,onInspect:model.processes.openActivityMonitor,onClose:{navigation.showWakeRequests=false}).preferredColorScheme(model.colorScheme)
            }

    }
    func showMetric(_ kind:MetricKind) {
        navigation.showMetric(kind)
        if let sensor=kind.sensor {model.timeline.sensor=sensor}
    }
}

extension View {
    /// Shared reading width and leading edge for all main pages; wide windows stay readable.
    func consolePageContent()->some View {
        self.frame(maxWidth:1120,alignment:.leading).padding(.horizontal,28)
            .frame(maxWidth:.infinity,alignment:.leading)
    }
}

private struct ConsoleNavigation<Sidebar:View,Detail:View>:View {
    let sidebar:Sidebar
    let detail:Detail
    init(@ViewBuilder sidebar:()->Sidebar,@ViewBuilder detail:()->Detail) {self.sidebar=sidebar();self.detail=detail()}
    var body:some View {
        HStack(spacing:0) {
            sidebar.frame(width:220).frame(maxHeight:.infinity)
            detail.frame(minWidth:620,maxWidth:.infinity,maxHeight:.infinity)
        }
    }
}
