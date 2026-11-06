import Foundation
import SwiftUI
import ThermalCore

enum ConsoleSection:String,Hashable {case findings,optimization,temperature,processes}
enum PreferencesSection:String,CaseIterable,Identifiable {
    case general,menubar,widgets
    var id:String {rawValue}
    var title:String {switch self {case .general:return "通用";case .menubar:return "状态栏";case .widgets:return "小组件"}}
}
enum ConsolePage:String,CaseIterable,Identifiable {
    case metrics,thermal,optimization,processes,history,sensors,electricity
    var id:String {rawValue}
    var title:String {switch self {case .metrics:return "实时监测";case .optimization:return "性能诊断";case .thermal:return "温度控制";case .processes:return "进程活动";case .history:return "操作记录";case .sensors:return "传感器";case .electricity:return "用量统计"}}
    var subtitle:String {switch self {case .metrics:return "查看当前指标和温度趋势。";case .optimization:return "先看需要关注的问题，再查看原因和处理方式。";case .thermal:return "选择档位，或直接拖动曲线调速。";case .processes:return "找出 CPU、内存和磁盘活动的来源。";case .history:return "回看最近的操作，导出采样记录。";case .sensors:return "查看这台 Mac 实际提供的全部传感器读数。";case .electricity:return "查看用电、实测功率与 AI Token 用量。"}}
    var symbol:String {switch self {case .metrics:return "chart.xyaxis.line";case .optimization:return "stethoscope";case .thermal:return "thermometer.medium";case .processes:return "list.bullet.rectangle";case .history:return "clock.arrow.circlepath";case .sensors:return "sensor";case .electricity:return "chart.bar.fill"}}
}
extension ConsoleSection {
    var page:ConsolePage {switch self {case .findings,.optimization:return .optimization;case .temperature:return .metrics;case .processes:return .processes}}
}
enum UsageTab:String,CaseIterable {
    case electricity,tokens
    var title:String {self == .electricity ? "用电":"Token"}
}
@MainActor final class DiagnosticNavigation:ObservableObject {
    @Published var usageTab:UsageTab = .electricity
    @Published var preferencesSection:PreferencesSection = .general
    @Published var page:ConsolePage = .metrics {didSet {if page != .metrics {metric=nil}}}
    @Published var metric:MetricKind?
    @Published var section:ConsoleSection?
    @Published var applicationID:String?
    @Published var showWakeRequests=false
    @Published var showFanTroubleshooting=false
    @Published var showFanSceneManager=false
    @Published var optimizationExpanded=false
    @Published var optimizationTab=0
    func go(_ section:ConsoleSection) {metric=nil;page=section.page;self.section=nil;self.section=section}
    func showMetric(_ kind:MetricKind) {page = .metrics;metric=kind;section=nil}
}
@MainActor final class DiagnosisStore:ObservableObject {
    @Published private(set) var report=DiagnosticReport()
    private var engine=DiagnosticEngine()
    private var lastBuild=Date.distantPast
    func receive(_ sample:Snapshot,telemetry:SystemTelemetry?,processes:ProcessObserver,power:PowerOptimizationModel) {
        guard sample.date.timeIntervalSince(lastBuild)>=4 || sample.date<lastBuild else{return}
        lastBuild=sample.date
        report=DiagnosticPreview.report(at:sample.date) ?? engine.evaluate(DiagnosticInput(snapshot:sample,sources:processes.diagnosticActivity,processSeconds:processes.observedSeconds,processDate:processes.sampledAt,blockers:power.sleepKnown ? power.blockers.count:nil,batteryPercent:telemetry?.batteryPercent))
    }
}
func diskRateText(_ value:Double?)->String {
    guard let value,value.isFinite,value>=0 else{return "—"}
    if value>=1024*1024 {return String(format:"%.1f MB/s",value/1024/1024)}
    if value>=1024 {return String(format:"%.0f KB/s",value/1024)}
    return String(format:"%.0f B/s",value)
}
