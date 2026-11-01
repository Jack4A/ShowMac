import AppKit
import SwiftUI
import ThermalCore

struct OptimizationWorkbench:View {
    @ObservedObject var optimizer:PowerOptimizationModel
    @ObservedObject var navigation:DiagnosticNavigation
    let globalBusy:Bool
    var body:some View {
        DisclosureGroup(isExpanded:$navigation.optimizationExpanded) {
            VStack(alignment:.leading,spacing:16) {
                Text(L("由建议准备方案，应用前可审阅每项改动。")).font(.system(size:10)).foregroundStyle(.secondary)
                Picker(L("优化面板"),selection:$navigation.optimizationTab) {
                    Text(L("措施")).tag(0);Text(L("效果")).tag(1)
                }.labelsHidden().pickerStyle(.segmented).tint(Palette.action)
                if navigation.optimizationTab==0 {OptimizationPlanView(optimizer:optimizer,globalBusy:globalBusy)}
                else {OptimizationResults(optimizer:optimizer)}
            }.padding(.top,14)
        } label:{
            HStack {
                Label(L("优化与恢复"),systemImage:"slider.horizontal.3").font(.system(size:15,weight:.semibold))
                Spacer()
                Text(L(optimizer.backup != nil ? "有可恢复的改动":"按需调整")).font(.system(size:10)).foregroundStyle(.secondary)
            }
        }.padding(22).subtlePanel()
            .onAppear{if optimizer.backup != nil {navigation.optimizationExpanded=true}}
    }
}
struct LoadEvidencePanel:View {
    @ObservedObject var observer:ProcessObserver
    var body:some View {VStack(alignment:.leading,spacing:10) {
        EnergySources(observer:observer)
        Text(L("依据 CPU 活动推断负载来源，不代表实际功率；未计入独立的 GPU、显示器等耗电。")).font(.system(size:9)).foregroundStyle(.secondary)
    }}
}
struct SleepRequestsSheet:View {
    @ObservedObject var optimizer:PowerOptimizationModel
    let onInspect:()->Void
    let onClose:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {Text(L("休眠阻止来源")).font(.title2.bold());Spacer();Button(L("完成"),action:onClose).keyboardShortcut(.cancelAction)}
            ScrollView(showsIndicators:false) {SleepFindings(optimizer:optimizer,onInspect:onInspect)}
        }.padding(24).frame(width:650,height:480)
    }
}
private struct SleepFindings:View {
    @ObservedObject var optimizer:PowerOptimizationModel
    let onInspect:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Label(L("休眠阻止来源"),systemImage:"moon.zzz.fill").font(.system(size:12,weight:.medium))
                Spacer()
                Button(L("刷新")){optimizer.refresh()}.buttonStyle(.borderless).disabled(optimizer.reading)
                Button(L("活动监视器"),action:onInspect).buttonStyle(.borderless)
            }.font(.caption)
            if !optimizer.sleepKnown {Text(L("休眠阻止状态不可读取")).font(.caption).foregroundStyle(.secondary)}
            else if optimizer.blockers.isEmpty {Text(L("未检测到应用阻止自动休眠。")).font(.caption).foregroundStyle(.secondary)}
            else {
                ForEach(optimizer.blockers.prefix(6)) {blocker in
                    VStack(alignment:.leading,spacing:3) {
                        Text(NSRunningApplication(processIdentifier:blocker.pid)?.localizedName ?? blocker.name).font(.system(size:12,weight:.medium))
                        Text(blocker.reason).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                    }
                }
                Text(L("远程、会议、播放和下载任务可能需要保持唤醒，请确认后处理。")).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}
private struct OptimizationPlanView:View {
    @ObservedObject var optimizer:PowerOptimizationModel
    let globalBusy:Bool
    func value(_ number:Int,for key:PowerSetting)->String {
        key == .lowpowermode ? L(number==1 ? "开启":"关闭"):(number==0 ? L("从不"):String(format:L("%d 分钟"),number))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:13) {
            HStack {
                Text(L("具体措施")).font(.system(size:13,weight:.semibold))
                Spacer()
                Text(L("当前供电")+" · "+L(optimizer.source?.title ?? "未知")).font(.caption).foregroundStyle(.secondary)
                Button(L("刷新")){optimizer.refresh()}.buttonStyle(.borderless).font(.caption).disabled(optimizer.reading)
            }
            Group {
                Toggle(L("使用系统低电量模式"),isOn:$optimizer.lowPower)
                if optimizer.lowPower {
                    Picker(L("节能范围"),selection:$optimizer.scope) {
                        Text(L("当前供电模式")).tag(PowerScope.current)
                        Text(L("电池开启，插电关闭")).tag(PowerScope.batteryAutomatic)
                    }.pickerStyle(.menu)
                    Text(L("由 macOS 按供电状态使用配置；可能降低性能峰值。")).font(.system(size:10)).foregroundStyle(.secondary)
                }
                Toggle(L("显示器闲置 5 分钟后休眠"),isOn:$optimizer.displaySleep)
                Toggle(L("系统闲置 15 分钟后休眠"),isOn:$optimizer.idleSleep)
                    .disabled(!optimizer.idleSleep && (!optimizer.sleepKnown || !optimizer.blockers.isEmpty))
                if !optimizer.blockers.isEmpty {Text(L("检测到保持唤醒任务，系统休眠措施暂不可选。")).font(.system(size:10)).foregroundStyle(.secondary)}
                Toggle(L("额外关闭 Intel 睿频"),isOn:$optimizer.disableTurbo).disabled(optimizer.turboDisabled==nil && !optimizer.disableTurbo)
                Text(L("睿频单独选择；风扇保持当前策略和高温保护。")).font(.system(size:10)).foregroundStyle(.secondary)
            }.toggleStyle(.checkbox).font(.system(size:12)).disabled(optimizer.busy || optimizer.backup != nil || globalBusy)
            if let backup=optimizer.backup {
                Divider()
                Text(L("本次优化的恢复记录")).font(.system(size:12,weight:.medium))
                ForEach(backup.edits) {edit in editRow(edit)}
                if backup.turboBefore != nil {Text(L("额外关闭 Intel 睿频")).font(.caption)}
                Text(L("先恢复原设置，再应用另一套措施。恢复记录在重启软件后保留。")).font(.system(size:10)).foregroundStyle(.secondary)
                Button {optimizer.restore()} label:{Label(L("恢复原设置"),systemImage:"arrow.uturn.backward")}.buttonStyle(.bordered).disabled(optimizer.busy || globalBusy)
            } else {
                Divider()
                Text(L("将要修改")).font(.system(size:12,weight:.medium))
                ForEach(optimizer.edits) {edit in editRow(edit)}
                if optimizer.disableTurbo,optimizer.turboDisabled==false {Text(L("睿频")+" · "+L("允许开启")+" → "+L("关闭")).font(.caption)}
                if !optimizer.hasChanges {Text(L(optimizer.hasSelection ? "所选设置已满足":"选择需要调整的项目，再检查改动预览。")).font(.caption).foregroundStyle(.secondary)}
                Button {optimizer.apply()} label:{Label(L("应用所选措施"),systemImage:"checkmark.shield.fill")}.buttonStyle(.borderedProminent).tint(Palette.action).controlSize(.large).disabled(!optimizer.canApply || globalBusy)
            }
            if optimizer.busy {ProgressView().controlSize(.small)}
            if !optimizer.status.isEmpty {Text(L(optimizer.status)).font(.caption).foregroundStyle(optimizer.failed ? Color.orange:Color.secondary).textSelection(.enabled)}
            if !optimizer.environmentError.isEmpty {Text(L(optimizer.environmentError)).font(.caption).foregroundStyle(.orange)}
            else if let issue=optimizer.planIssue {Text(L(issue)).font(.caption).foregroundStyle(.orange)}
            Text(L("电源设置会持续保留，恢复按钮撤回本次改动；应用退出需在下方单独确认。")).font(.system(size:9)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    func editRow(_ edit:PowerEdit)->some View {
        HStack {
            Text(L(edit.source.title)+" · "+L(edit.key.title)).lineLimit(2)
            Spacer()
            Text(value(edit.before,for:edit.key)+" → "+value(edit.after,for:edit.key)).monospacedDigit()
        }.font(.system(size:11)).padding(.vertical,2)
    }
}
private struct OptimizationResults:View {
    @ObservedObject var optimizer:PowerOptimizationModel
    func text(_ summary:OptimizationSummary?,_ metric:KeyPath<OptimizationSummary,Double?>,_ suffix:String)->String {
        guard let summary,summary.sufficient,let value=summary[keyPath:metric] else{return "—"}
        return String(format:"%.1f",value)+suffix
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            if optimizer.before==nil {Text(L("应用措施后，观察优化前后的真实采样变化。")).font(.caption).foregroundStyle(.secondary)}
            else {
                HStack {Text(L("采样均值"));Spacer();Text(L("优化前")).frame(width:90,alignment:.trailing);Text(L("优化后")).frame(width:90,alignment:.trailing)}.font(.system(size:11)).foregroundStyle(.secondary)
                row("CPU 使用率",\.cpu,"%")
                row("CPU 温度",\.temperature,"°C")
                row("电池放电功率",\.watts," W")
                if optimizer.collecting {Text(String(format:L("正在观察：%d / 60 秒"),optimizer.observationSeconds)).font(.caption).foregroundStyle(Palette.violet)}
                else if let before=optimizer.before,let after=optimizer.after {
                    Text(L(assessment(before.assessment(after:after)))).font(.system(size:12,weight:.medium)).foregroundStyle(Palette.violet)
                }
                if optimizer.before?.sufficient != true {Text(L("优化前采样不足，暂不作前后对比。")).font(.caption).foregroundStyle(.secondary)}
                Text(L("应用后等待 10 秒，再观察最多 60 秒；采样足够时才展示均值。")).font(.system(size:10)).foregroundStyle(.secondary)
            }
            Text(L("插电、充电、供电切换或电池样本不足时，不展示放电功率对比。")).font(.system(size:10)).foregroundStyle(.secondary)
            Text(L("工作负载和环境可能不同；数值变化不等于优化带来的节电量。")).font(.system(size:10)).foregroundStyle(.secondary)
        }.fixedSize(horizontal:false,vertical:true)
    }
    func assessment(_ result:OptimizationAssessment)->String {
        switch result {
        case .insufficient:return "样本不足，无法确认变化。"
        case .powerChanged:return "供电条件不同，无法直接比较。"
        case .loadChanged:return "工作负载变化较大，未作优化归因。"
        case .lowerTemperature:return "观察到温度下降；尚不能确定是否由措施带来。"
        case .higherTemperature:return "观察到温度上升，建议继续查看负载来源。"
        case .noClearChange:return "暂未观察到明确温度变化。"
        }
    }
    func row(_ title:String,_ metric:KeyPath<OptimizationSummary,Double?>,_ suffix:String)->some View {
        HStack {
            Text(L(title));Spacer()
            Text(text(optimizer.before,metric,suffix)).frame(width:90,alignment:.trailing)
            Text(text(optimizer.after,metric,suffix)).frame(width:90,alignment:.trailing)
        }.font(.system(size:12)).monospacedDigit()
    }
}
private struct EnergySources:View {
    @ObservedObject var observer:ProcessObserver
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(L("主要负载来源")).font(.system(size:12,weight:.medium))
                Spacer()
                Text(String(format:L("已观测 %.0f 秒 · 最长 1 分钟"),min(60,observer.observedSeconds))).font(.system(size:9)).foregroundStyle(.secondary)
            }
            if observer.observedSeconds<5 {
                Text(L("正在分析持续负载…")).font(.caption).foregroundStyle(.secondary)
            } else if observer.activity.first?.averageCPU ?? 0 < 1 {
                Text(L("当前可读进程的 CPU 活动较低。")).font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {Text(L("应用与关联进程"));Spacer();Text(L("平均 CPU")).frame(width:70,alignment:.trailing);Text(L("当前 CPU")).frame(width:70,alignment:.trailing)}.font(.system(size:9)).foregroundStyle(.secondary)
                ForEach(observer.activity) {source in
                    VStack(alignment:.leading,spacing:5) {
                        HStack {
                            Text(source.name).font(.system(size:12,weight:.medium)).lineLimit(1)
                            Spacer()
                            Text(String(format:"%.1f%%",source.averageCPU)).monospacedDigit().frame(width:70,alignment:.trailing)
                            Text(String(format:"%.1f%%",source.currentCPU)).monospacedDigit().foregroundStyle(.secondary).frame(width:70,alignment:.trailing)
                        }.font(.system(size:12))
                        GeometryReader {proxy in
                            Capsule().fill(Palette.violet.opacity(0.1)).overlay(alignment:.leading) {
                                Capsule().fill(Palette.violet.opacity(0.7)).frame(width:proxy.size.width*min(1,max(0,source.cpuShare/100)))
                            }
                        }.frame(height:4)
                    }.accessibilityElement(children:.combine)
                }
                Text(L("进度条表示可读进程中的 CPU 活动占比；同一应用的子进程已合并。")).font(.system(size:9)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}
