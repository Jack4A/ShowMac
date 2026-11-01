import SwiftUI
import ThermalCore

struct PerformanceDiagnosis:View {
    @ObservedObject var store:DiagnosisStore
    let onAction:(DiagnosticAction)->Void
    let onCPU:()->Void
    let onOptimize:()->Void
    @State private var showRules=false
    var metrics:DiagnosticMetrics? {store.report.metrics}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:7) {
                    Label(L(store.report.state.title),systemImage:store.report.state.symbol).font(.system(size:17,weight:.semibold)).foregroundStyle(store.report.state.tone)
                    Text(L(store.report.state.detail)).font(.system(size:11)).foregroundStyle(.secondary)
                }
                Spacer()
                if let date=store.report.date {Text(date,style:.time).font(.caption).foregroundStyle(.secondary)}
            }
            Text(L("采样指标 → 持续诊断 → 审阅措施 → 观察效果")).font(.system(size:11,weight:.medium)).foregroundStyle(Palette.violet)
            HStack {
                Text(L("诊断指标")).font(.system(size:13,weight:.semibold))
                Spacer()
                Text(String(format:L("有效观察 %.0f 秒"),store.report.observedSeconds)).font(.caption).foregroundStyle(.secondary)
            }
            if store.report.state == .sampling {ProgressView(value:min(45,store.report.observedSeconds),total:45).tint(Palette.violet)}
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10),count:3),spacing:10) {
                metric("全机 CPU",valueText(metrics?.cpuUsage)+"%",L("100% 表示全部核心"),action:onCPU)
                metric("应用 CPU 均值",metrics?.cpuSource.map{String(format:"%.1f%%",$0.averageCPU)} ?? "—",sourceDescription(metrics?.cpuSource,seconds:metrics?.processSeconds),action:metrics?.cpuSource.map{source in {onAction(.reviewApplication(source.id))}})
                metric("CPU / GPU 温度",valueText(metrics?.cpuTemperature)+" / "+valueText(metrics?.gpuTemperature)+"°C",L("查看温度趋势与模式切换"),action:{onAction(.temperatureTimeline)})
                metric("内存压力",L(metrics?.memoryPressure?.title ?? "未知"),L("依据系统压力信号"),action:{onAction(.memoryProcesses)})
                metric("磁盘平均读写",diskRateText(metrics?.diskSource?.averageDiskRate),sourceDescription(metrics?.diskSource,seconds:metrics?.diskSource?.diskSeconds),action:{if let source=metrics?.diskSource {onAction(.reviewApplication(source.id))} else {onAction(.diskProcesses)}})
                metric("热压力",L(metrics?.thermalTitle ?? "未知"),L(metrics?.performanceLimited.map{$0 ? "系统正在限制性能":"未检测到系统限速"} ?? "性能上限未知"),action:{onAction(.temperatureTimeline)})
            }
            Text(L("应用 CPU 按单核 100% 计，不代表实际耗电量；编译、渲染和传输也可能是正常任务。")).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                DisclosureGroup(L("判定规则"),isExpanded:$showRules) {
                    Text(L("CPU：观察至少 45 秒，应用平均占用一个核心且当前仍活跃时提示。温度：CPU ≥90°C 或 GPU ≥85°C 持续 30 秒时提示；系统热压力与限速单独判断。内存依据系统压力，磁盘持续传输仅作信息。缺失或过期数据保持未知。")).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).padding(.top,8)
                }
                Spacer(minLength:12)
                Button(L("审阅优化措施"),action:onOptimize).buttonStyle(.bordered)
            }
        }.padding(22).subtlePanel()
    }
    func sourceDescription(_ source:DiagnosticSource?,seconds:Double?)->String {
        guard let source,let seconds,seconds>0 else{return L("暂无有效进程窗口")}
        return source.name+" · "+String(format:L("近 %.0f 秒"),min(60,seconds))
    }
    func metric(_ title:String,_ value:String,_ detail:String,action:(()->Void)?)->some View {
        Button {action?()} label: {
            VStack(alignment:.leading,spacing:7) {
                Text(L(title)).font(.system(size:10)).foregroundStyle(.secondary)
                Text(value).font(.system(size:18,weight:.medium,design:.rounded)).monospacedDigit().foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.65)
                Text(detail).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(2).frame(minHeight:24,alignment:.topLeading)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).disabled(action==nil)
    }
}
