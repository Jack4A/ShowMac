import SwiftUI
import ThermalCore

struct MetricsDashboard:View {
    @ObservedObject var readings:LiveReadings
    @ObservedObject var history:MetricHistoryStore
    let mode:String
    let onTemperature:(SensorCategory)->Void
    let onControl:()->Void
    let onMode:()->Void
    let onCPU:()->Void
    var sample:Snapshot? {readings.snapshot}
    var body:some View {
        VStack(spacing:16) {
            HStack(spacing:12) {
                MetricSummaryCard(title:"CPU 温度",value:valueText(sample?.cpuTemperature),unit:"°C",detail:sample?.cpuTemperature == nil ? "暂无温度读数":"CPU 传感器最高温度",symbol:"thermometer.medium",trendKind:.cpuTemperature,trend:history.points(.cpuTemperature,minutes:2),trendEnd:history.end,action:{onTemperature(.cpu)})
                MetricSummaryCard(title:"风扇转速",value:valueText(sample?.fans.compactMap(\.rpm).max()),unit:"RPM",detail:sample?.fans.compactMap(\.rpm).max() == nil ? "暂无转速读数":mode,symbol:"fanblades",trendKind:.fan,trend:history.points(.fan,minutes:2),trendEnd:history.end,action:onControl)
                MetricSummaryCard(title:"CPU 使用率",value:valueText(sample?.cpuUsage),unit:"%",detail:"100% 表示全部核心",symbol:"cpu",trendKind:.cpuUsage,trend:history.points(.cpuUsage,minutes:2),trendEnd:history.end,action:onCPU)
            }
            HStack(spacing:12) {
                Button(action:onMode) {Label(L("运行模式")+" · "+L(mode),systemImage:AppSymbols.resolve("slider.horizontal.3")).lineLimit(1)}
                    .buttonStyle(.borderless).foregroundColor(.primary).help(L("温度控制"))
                Spacer(minLength:0)
                if !ControlAvailability.isAppleSilicon {Text(L("睿频")+" · "+L(sample.map {$0.turbo == .disabledDriverLoaded ? "已关闭":($0.turbo == .driverNotLoaded ? "允许开启":"未知")} ?? "未知"))}
                if SystemCapabilities.lowPowerMode {Text(L("系统低电量模式")+" · "+L(sample.map {$0.lowPower ? "开启":"关闭"} ?? "未知"))}
            }.font(.system(size:12)).foregroundColor(Palette.secondaryText).padding(.horizontal,4)
        }
    }
}

struct MetricSummaryCard:View {
    let title:String
    let value:String
    let unit:String
    let detail:String
    let symbol:String
    var localizedDetail=false
    var trendKind:MetricKind?
    var trend:[MetricPoint]=[]
    var trendEnd:Date?
    let action:()->Void
    private var displayDetail:String {localizedDetail ? detail:L(detail)}
    private var tone:Color {trendKind.map{MonitorAppearance.metric($0)} ?? .secondary}
    var body:some View {
        let button=Button(action:action) {cardContent}.buttonStyle(.plain)
        return button.help(L("指标详情")).accessibilityLabel(L(title)+" · "+value+" "+unit+" · "+displayDetail)
    }
    private var cardContent:some View {
        VStack(alignment:.leading,spacing:8) {
            header
            valueRow
            Text(displayDetail).font(.system(size:12)).foregroundColor(Palette.secondaryText).lineLimit(2).frame(minHeight:28,alignment:.topLeading)
        }.frame(maxWidth:.infinity,alignment:.leading).subtlePanel(padding:18).contentShape(Rectangle())
    }
    private var header:some View {
        HStack {
            Label {
                Text(L(title)).foregroundColor(Palette.secondaryText)
            } icon:{
                Image(systemName:AppSymbols.resolve(symbol)).foregroundColor(tone)
            }.font(.system(size:12))
            Spacer(minLength:4)
            Image(systemName:AppSymbols.resolve("chevron.right")).font(.system(size:12,weight:.medium)).foregroundColor(Palette.secondaryText)
        }
    }
    private var valueRow:some View {
        HStack(alignment:.firstTextBaseline,spacing:8) {
            MetricValue(value:value,unit:unit).layoutPriority(1)
            Spacer(minLength:0)
            if let trendKind,let trendEnd {
                VStack(alignment:.trailing,spacing:2) {
                    MetricCardSparkline(points:trend,ending:trendEnd,kind:trendKind).frame(height:24)
                    Text(L("2 分钟")).font(.system(size:11)).foregroundColor(.secondary)
                }.frame(width:60).accessibilityHidden(true)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

/// Small multiples use real samples and the same metric colors as the status panel.
private struct MetricCardSparkline:View {
    @AppStorage("menuCPUWarnings") private var warningsEnabled=true
    let points:[MetricPoint]
    let ending:Date
    let kind:MetricKind
    private var visible:[MetricPoint] {MetricPlot.decimated(points,budget:50)}
    private var scale:ClosedRange<Double> {
        MetricPlot.scale(visible.compactMap(\.value),automatic:true,upper:kind.fixedUpper)
    }
    private var tone:Color {MonitorAppearance.metric(kind)}
    private var runs:[CPULoadRun] {MetricWarningBands.runs(points,kind:kind,enabled:warningsEnabled,budget:50)}
    @ViewBuilder var body:some View {
        MetricPlotView(series:MetricPlotView.metricSeries(runs,normal:tone,filled:true),xRange:ending.addingTimeInterval(-120).timeIntervalSince1970...ending.timeIntervalSince1970,yRange:scale,placeholder:L("采样中")).accessibilityHidden(true)

    }

}

struct SupplementaryMetrics:View {
    @ObservedObject var readings:LiveReadings
    let onTemperature:(MetricKind)->Void
    let onMemory:()->Void
    var sample:Snapshot? {readings.snapshot}
    var unavailable:[MetricKind] {[.gpuTemperature,.storageTemperature].filter{sample?.temperature($0.sensor!) == nil}}
    var memory:String {
        guard let used=readings.telemetry?.memoryUsed,let total=readings.telemetry?.memoryTotal,total>0 else{return "—"}
        return String(format:"%.1f / %.0f",used/1_073_741_824,total/1_073_741_824)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L("其他指标")).font(AppTypography.section)
            HStack(spacing:12) {
                MetricSummaryCard(title:"内存",value:memory,unit:"GB",detail:L("内存压力")+" · "+L(sample?.memoryPressure?.title ?? "未知"),symbol:"memorychip",localizedDetail:true,action:onMemory)
                ForEach([MetricKind.gpuTemperature,.storageTemperature].filter{!unavailable.contains($0)}) {kind in
                    MetricSummaryCard(title:kind.title,value:valueText(sample?.temperature(kind.sensor!)),unit:"°C",detail:"传感器最高温度",symbol:kind == .gpuTemperature ? "display":"internaldrive",action:{onTemperature(kind)})
                }
            }
            if !unavailable.isEmpty {
                HStack(spacing:8) {
                    Image(systemName:AppSymbols.resolve("sensor")).foregroundColor(Palette.secondaryText)
                    Text(L("暂无读数：")).foregroundColor(Palette.secondaryText)
                    ForEach(unavailable) {kind in
                        Button(L(kind.title)){onTemperature(kind)}.buttonStyle(.borderless)
                    }
                }.font(.system(size:12))
            }
        }
    }
}
