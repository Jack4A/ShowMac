import AppKit
import SwiftUI
import ThermalCore

extension DiagnosticState {
    var title:String {switch self {case .sampling:return "正在建立观察基线";case .attention:return "有情况需要关注";case .observing:return "有活动值得观察";case .stable:return "当前无需调整";case .partial:return "部分信息暂不可用"}}
    var detail:String {switch self {case .sampling:return "先观察持续活动，再生成处理建议。";case .attention:return "先查看证据，再选择适合当前任务的措施。";case .observing:return "当前活动可能属于正常任务，可检查相关来源。";case .stable:return "可用指标未发现需要处理的持续异常。";case .partial:return "当前结论仅覆盖可用指标，缺失读数保持未知。"}}
    var symbol:String {switch self {case .sampling:return "waveform.path";case .attention:return "exclamationmark.circle.fill";case .observing:return "eye.fill";case .stable:return "checkmark.shield.fill";case .partial:return "questionmark.circle.fill"}}
    var tone:Color {switch self {case .attention:return .orange;case .stable:return Palette.violet;case .sampling,.observing:return Palette.violet;case .partial:return .secondary}}
}
extension DiagnosticFinding {
    var title:String {
        switch kind {
        case .thermalPressure:return "系统热压力升高"
        case .thermalLimit:return "热压力与性能限制同时存在"
        case .performanceLimit:return "系统报告了性能限制"
        case .temperature:return "温度持续偏高"
        case .temperatureObservation:return "温度偏高，继续观察"
        case .sustainedCPU:return "应用持续占用 CPU"
        case .memoryPressure:return "系统内存压力升高"
        case .diskActivity:return "磁盘传输持续活跃"
        case .wakeRequests:return "存在保持唤醒请求"
        case .batteryPolicy:return "电池电量较低，可查看节能设置"
        case .unavailable:return "部分读数暂不可用"
        }
    }
    var explanation:String {
        switch kind {
        case .thermalPressure,.thermalLimit:return "先检查持续负载和散热；这些信号不能单独确定发热原因。"
        case .performanceLimit:return "限制可能来自电源或平台策略；睿频状态单独判断。"
        case .temperature:return "持续高温值得检查，先确认当前工作负载是否符合预期。"
        case .temperatureObservation:return "当前未见明确热限制，可结合负载和温度趋势继续观察。"
        case .sustainedCPU:return "持续负载可能参与发热；编译和渲染等任务也可能属于正常工作。"
        case .memoryPressure:return "依据系统内存压力信号，建议先查看内存占用较高的应用。"
        case .diskActivity:return "可能是正常传输或后台任务，建议查看关联进程后再决定。"
        case .wakeRequests:return "远程、会议、播放和下载任务可能需要保持唤醒，请确认后处理。"
        case .batteryPolicy:return "可准备系统低电量方案；应用前会展示性能影响和具体改动。"
        case .unavailable:return "缺失值不会当作零或正常；可以重新读取并检查可用范围。"
        }
    }
    var actionTitle:String {
        switch action {case .reviewApplication:return "查看相关应用";case .memoryProcesses:return "查看内存排行";case .diskProcesses:return "查看磁盘排行";case .temperatureTimeline:return "查看温度曲线";case .wakeRequests:return "检查保持唤醒任务";case .lowPowerPlan:return "查看节能方案";case .refresh:return "重新读取"}
    }
    var evidence:String? {
        if kind == .sustainedCPU,let value,let seconds {return String(format:L("近 %.0f 秒平均 CPU %.1f%%（单核 100%%）"),seconds,value)}
        if kind == .diskActivity,let value,let seconds {return String(format:L("近 %.0f 秒平均磁盘读写 %@"),seconds,diskRateText(value))}
        if kind == .wakeRequests,let value {return String(format:L("已读取 %.0f 项保持唤醒请求"),value)}
        if kind == .batteryPolicy,let value {return String(format:L("当前电池电量 %.0f%%"),value)}
        if kind == .temperature,let value,let seconds {return String(format:L("当前 %.1f°C · 已持续 %.0f 秒"),value,seconds)}
        if kind == .temperatureObservation,let value {return String(format:L("当前温度 %.1f°C"),value)}
        if kind == .memoryPressure,let value,let pressure=MemoryPressure(rawValue:Int(value)) {return L("内存压力")+" · "+L(pressure.title)}
        return nil
    }
}
struct DiagnosticFindingsPanel:View {
    @ObservedObject var store:DiagnosisStore
    let onAction:(DiagnosticAction)->Void
    @State private var showAll=false
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Label(L("发现与依据"),systemImage:"text.magnifyingglass").font(.system(size:15,weight:.semibold))
                Spacer()
                if let date=store.report.date {Text(date,style:.time).font(.system(size:9)).foregroundStyle(.secondary)}
            }
            if store.report.findings.isEmpty {Text(L(store.report.state == .sampling ? "持续观察后再生成建议。":"当前没有需要处理的建议。")).font(.system(size:12)).foregroundStyle(.secondary)}
            ForEach(Array(store.report.findings.prefix(showAll ? 10:3))) {finding in
                VStack(alignment:.leading,spacing:9) {
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:4) {
                            Text(L(finding.title)).font(.system(size:13,weight:.semibold))
                            if let subject=finding.subject {Text(subject).font(.system(size:12)).textSelection(.enabled)}
                        }
                        Spacer()
                        Text(L(finding.confidence == .confirmed ? "已确认":(finding.confidence == .possible ? "可能相关":"数据不足"))).font(.system(size:9)).foregroundStyle(finding.severity == .information ? Color.secondary:Color.orange).padding(.horizontal,7).padding(.vertical,4).background(.primary.opacity(0.045),in:Capsule())
                    }
                    if let evidence=finding.evidence {Text(evidence).font(.system(size:10,weight:.medium)).monospacedDigit().foregroundStyle(Palette.violet)}
                    Text(L(finding.explanation)).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Button(L(finding.actionTitle)){onAction(finding.action)}.buttonStyle(.borderless).font(.system(size:11,weight:.medium))
                }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background((finding.severity == .information ? Palette.violet:Color.orange).opacity(0.045),in:RoundedRectangle(cornerRadius:13))
            }
            if store.report.findings.count>3 {Button(L(showAll ? "收起":"查看全部依据")){showAll.toggle()}.buttonStyle(.borderless).font(.caption)}
        }.padding(22).subtlePanel()
    }
}
struct ApplicationReviewSheet:View {
    @ObservedObject var observer:ProcessObserver
    let groupID:String
    let onClose:()->Void
    @State private var candidate:ObservedProcess?
    var matches:[ObservedProcess] {observer.allRows.filter{$0.groupID==groupID}}
    var title:String {matches.first?.application?.localizedName ?? matches.first?.name ?? L("相关应用")}
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Text(title).font(.title2.bold());Spacer();Button(L("完成"),action:onClose).keyboardShortcut(.cancelAction)}
            Text(L("以下是当前关联进程。退出应用需要确认，并可能影响正在进行的任务。")).font(.caption).foregroundStyle(.secondary)
            ScrollView(showsIndicators:false) {
                VStack(alignment:.leading,spacing:12) {
                    if matches.isEmpty {Text(L("该应用或进程已结束，当前没有可审阅的读数。")).font(.caption).foregroundStyle(.secondary)}
                    ForEach(matches.prefix(30)) {row in
                        HStack {
                            VStack(alignment:.leading,spacing:3) {Text(row.name).font(.system(size:12,weight:.medium));Text(verbatim:"PID \(row.reading.pid)").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)}
                            Spacer();Text(String(format:"%.1f%%",row.reading.cpu)).monospacedDigit().frame(width:70,alignment:.trailing)
                            Text(diskRateText(row.reading.diskRate)).monospacedDigit().frame(width:95,alignment:.trailing)
                        }.font(.system(size:11)).padding(.vertical,4)
                    }
                }
            }
            HStack {
                Button(L("活动监视器")){observer.openActivityMonitor()}
                if let target=matches.first(where:{$0.application?.activationPolicy == .regular})?.application {
                    Button(L("打开应用")){_ = target.activate(options:.activateIgnoringOtherApps)}
                }
                Spacer()
                Button(L("请求正常退出")){candidate=matches.first(where:{$0.canQuit})}.disabled(!matches.contains(where:{$0.canQuit}))
            }
            if !observer.actionMessage.isEmpty {Text(L(observer.actionMessage)).font(.caption).foregroundStyle(.secondary)}
        }.padding(24).frame(width:650,height:500)
            .confirmationDialog(L("请求应用正常退出？"),isPresented:Binding(get:{candidate != nil},set:{if !$0{candidate=nil}}),titleVisibility:.visible) {
                if let row=candidate {Button(L("退出应用"),role:.destructive){observer.quit(row);candidate=nil}}
                Button(L("取消"),role:.cancel){candidate=nil}
            } message:{Text(L("将退出所属应用：")+(candidate?.application?.localizedName ?? candidate?.name ?? "")+"\n"+L("有未保存内容时，应用可能要求你先保存。系统进程和其他用户的进程不会在这里结束。"))}
    }
}
