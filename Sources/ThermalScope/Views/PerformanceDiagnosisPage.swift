import AppKit
import SwiftUI
import ThermalCore

/// One summary, actionable findings, and compact readings. Extra evidence stays on demand.
struct PerformanceDiagnosisPage:View {
    @ObservedObject var model:AppModel
    @ObservedObject var store:DiagnosisStore
    @ObservedObject var optimizer:PowerOptimizationModel
    @ObservedObject var navigation:DiagnosticNavigation
    @State private var showDetails=false
    @State private var showRules=false
    init(model:AppModel) {
        self.model=model;self.store=model.diagnostics;self.optimizer=model.optimization;self.navigation=model.navigation
    }
    private var report:DiagnosticReport {store.report}
    private var metrics:DiagnosticMetrics? {report.metrics}
    private var attention:[DiagnosticFinding] {report.findings.filter{$0.severity != .information}}
    private var observations:[DiagnosticFinding] {report.findings.filter{$0.severity == .information && $0.kind != .unavailable}}
    private var missing:[String] {
        guard let metrics else{return []}
        var names:[String]=[]
        if metrics.cpuUsage==nil {names.append(L("CPU 使用率"))}
        if metrics.cpuTemperature==nil {names.append(L("CPU 温度"))}
        if metrics.memoryPressure==nil {names.append(L("内存压力"))}
        if metrics.performanceLimited==nil {names.append(L("系统性能限制"))}
        if !metrics.processFresh {names.append(L("进程采样"))}
        if !metrics.wakeRequestsKnown {names.append(L("保持唤醒请求"))}
        return names
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            summary.id(ConsoleSection.findings)
            currentReadings
            details
            adjustments.id(ConsoleSection.optimization)
        }.onReceive(navigation.$section) {section in
            if section == .findings,attention.isEmpty,!observations.isEmpty {showDetails=true}
        }
    }
    private var summary:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top,spacing:10) {
                Image(systemName:AppSymbols.resolve(report.state.symbol)).font(.title2).foregroundColor(attention.contains{$0.severity == .critical} ? Color.red:report.state.tone)
                VStack(alignment:.leading,spacing:6) {
                    Text(L(report.state.title)).font(.headline)
                    Text(L(report.state.detail)).font(AppTypography.caption).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
                }
                Spacer(minLength:0)
                if model.isFanControlPreview,DiagnosticPreview.isEnabled {Text(L("模拟")).font(AppTypography.caption).foregroundColor(.orange)}
            }
            if report.state == .sampling {
                ProgressView(value:min(45,max(0,report.observedSeconds)),total:45).progressViewStyle(.linear)
            }
            HStack {
                Text(String(format:L("已观察 %.0f 秒"),report.observedSeconds))
                Spacer()
                if let date=report.date {Text(L("更新于"));Text(date,style:.time).appMonospacedDigit()}
            }.font(AppTypography.caption).foregroundColor(.secondary)
            ForEach(attention) {finding in
                Divider()
                DiagnosticFindingRow(finding:finding,onAction:model.follow)
            }
        }.subtlePanel()
    }
    private var currentReadings:some View {
        VStack(alignment:.leading,spacing:14) {
            Text(L("当前读数")).font(AppTypography.section)
            VStack(alignment:.leading,spacing:10) {
                reading("CPU 使用率",value:valueText(metrics?.cpuUsage,unit:"%"),actionTitle:"查看进程") {showProcesses()}
                Divider()
                reading(metrics?.gpuTemperature==nil ? "CPU 温度":"CPU / GPU 温度",value:temperatureText,actionTitle:"查看温度曲线") {model.follow(.temperatureTimeline)}
                Divider()
                reading("内存压力",value:L(metrics?.memoryPressure?.title ?? "未知"),actionTitle:"查看内存排行") {model.follow(.memoryProcesses)}
                Divider()
                reading("热压力",value:L(metrics?.thermalTitle ?? "未知"))
                Divider()
                reading("系统性能限制",value:L(metrics?.performanceLimited.map{$0 ? "系统正在限制性能":"未检测到系统限速"} ?? "暂不可用"))
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,4)
        }.subtlePanel()
    }
    private var temperatureText:String {
        let cpu=valueText(metrics?.cpuTemperature,unit:"°C")
        guard let gpu=metrics?.gpuTemperature else{return cpu}
        return cpu+" / "+valueText(gpu,unit:"°C")
    }
    private var details:some View {
        DisclosureGroup(L("诊断详情"),isExpanded:$showDetails) {
            VStack(alignment:.leading,spacing:16) {
                if !missing.isEmpty {
                    Text(L("暂不可用：")+missing.joined(separator:AppLocalization.shared.resolvedLanguage.hasPrefix("zh") ? "、":", "))
                        .font(AppTypography.caption).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
                    Text(L("缺失读数不代表正常；结论仅覆盖当前可用信息。")).font(AppTypography.caption).foregroundColor(.secondary)
                }
                VStack(alignment:.leading,spacing:10) {
                    Text(L("负载来源")).font(.headline)
                    if let source=metrics?.cpuSource {
                        sourceRow("CPU 活动最多",source:source,value:String(format:L("平均 %.1f%%（单核 100%%）"),source.averageCPU),seconds:metrics?.processSeconds ?? 0)
                    }
                    if let source=metrics?.diskSource {
                        sourceRow("磁盘读写最多",source:source,value:String(format:L("平均 %@"),diskRateText(source.averageDiskRate)),seconds:source.diskSeconds)
                    }
                    if metrics?.cpuSource==nil && metrics?.diskSource==nil {
                        Text(L("还没有足够的应用采样。")).font(AppTypography.caption).foregroundColor(.secondary)
                    }
                    Text(L("应用 CPU 按单核 100% 计，不代表实际耗电量；编译、渲染和传输也可能是正常任务。"))
                        .font(AppTypography.caption).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
                }
                if !observations.isEmpty {
                    Divider()
                    Text(L("其他观察")).font(.headline)
                    ForEach(observations) {finding in DiagnosticFindingRow(finding:finding,onAction:model.follow)}
                }
                Divider()
                DisclosureGroup(L("判定规则"),isExpanded:$showRules) {
                    Text(L("CPU：观察至少 45 秒，应用平均占用一个核心且当前仍活跃时提示。温度：CPU ≥90°C 或 GPU ≥85°C 持续 30 秒时提示；系统热压力与限速单独判断。内存依据系统压力，磁盘持续传输仅作信息。缺失或过期数据保持未知。"))
                        .font(AppTypography.caption).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true).padding(.top,6)
                }
            }.padding(.top,12)
        }.subtlePanel()
    }
    @ViewBuilder private var adjustments:some View {
        if ControlAvailability.isAppleSilicon && optimizer.backup==nil {
            VStack(alignment:.leading,spacing:8) {
                Text(L("节能选项在系统设置中调整。")).font(AppTypography.caption).foregroundColor(.secondary)
                HStack {
                    Button(L("温度控制")){navigation.metric=nil;navigation.page = .thermal}
                    Button(L("打开系统设置…")){if let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.systempreferences") {NSWorkspace.shared.open(url)}}
                }
            }.buttonStyle(AppNativeButtonStyle())
        } else {
            OptimizationWorkbench(optimizer:optimizer,navigation:navigation,globalBusy:model.busy)
        }
    }
    private func reading(_ title:String,value:String,actionTitle:String?=nil,action:(()->Void)?=nil)->some View {
        HStack(spacing:18) {
            Text(L(title)).frame(maxWidth:.infinity,alignment:.leading)
            Text(value).appMonospacedDigit().appTextSelection()
            if let actionTitle,let action {Button(L(actionTitle),action:action).buttonStyle(.borderless)}
            else {Color.clear.frame(width:0,height:0).accessibilityHidden(true)}
        }
    }
    private func sourceRow(_ title:String,source:DiagnosticSource,value:String,seconds:Double)->some View {
        HStack(alignment:.top) {
            VStack(alignment:.leading,spacing:4) {
                Text(L(title)+" · "+source.name).font(AppTypography.body).appTextSelection()
                Text(value+" · "+String(format:L("近 %.0f 秒"),min(60,seconds))).font(AppTypography.caption).foregroundColor(.secondary).appMonospacedDigit()
            }
            Spacer(minLength:12)
            Button(L("查看相关应用")){model.follow(.reviewApplication(source.id))}.buttonStyle(AppNativeButtonStyle())
        }
    }
    private func showProcesses(){model.processes.sort = .cpu;navigation.go(.processes)}
    private func valueText(_ value:Double?,unit:String)->String {value.map{String(format:"%.0f",$0)+unit} ?? "—"}
}

private struct DiagnosticFindingRow:View {
    let finding:DiagnosticFinding
    let onAction:(DiagnosticAction)->Void
    private var confidence:String {switch finding.confidence {case .confirmed:return "已确认";case .possible:return "可能相关";case .unavailable:return "数据不足"}}
    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            HStack(alignment:.top,spacing:16) {
                VStack(alignment:.leading,spacing:5) {
                    Text(L(finding.title)).font(.headline)
                    if let subject=finding.subject {Text(subject).font(AppTypography.body).appTextSelection()}
                }
                Spacer(minLength:0)
                Button(L(finding.actionTitle)){onAction(finding.action)}.buttonStyle(AppNativeButtonStyle())
            }
            HStack(alignment:.firstTextBaseline,spacing:8) {
                Text(L(confidence)).foregroundColor(finding.severity == .information ? Color.secondary:(finding.severity == .critical ? .red:.orange))
                if let evidence=finding.evidence {Text(evidence).foregroundColor(.secondary).appMonospacedDigit()}
            }.font(AppTypography.caption)
            Text(L(finding.explanation)).font(AppTypography.caption).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}
