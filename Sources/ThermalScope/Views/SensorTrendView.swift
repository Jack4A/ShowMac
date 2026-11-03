import SwiftUI
import Charts
import ThermalCore

struct SensorTrendRangePicker:View {
    @Binding var minutes:Int
    var body:some View {
        Picker(L("时间范围"),selection:$minutes) {
            Text(L("5 分钟")).tag(5)
            Text(L("10 分钟")).tag(10)
            Text(L("30 分钟")).tag(30)
        }.labelsHidden().frame(width:110)
    }
}

/// Share units and bounds between the compact drawing and the detailed chart.
private func sensorTrendScale(_ points:[MetricPoint],kind:HardwareSensorKind)->ClosedRange<Double> {
    let values=points.compactMap(\.value).filter(\.isFinite)
    let minimumSpan:Double
    switch kind {case .fan:minimumSpan=200;case .temperature:minimumSpan=4;case .power:minimumSpan=2;case .voltage,.current:minimumSpan=0.2}
    guard let low=values.min(),let high=values.max() else{return 0...minimumSpan}
    let padding=max(minimumSpan,high-low)*0.15
    let center=(high+low)/2,half=max(minimumSpan/2,(high-low)/2+padding)
    let lower=kind == .power || kind == .current ? center-half:max(0,center-half)
    return lower...max(lower+minimumSpan,center+half)
}

private func sensorTrendStart(_ points:[MetricPoint],end:Date,minutes:Int)->Date {
    let cutoff=end.addingTimeInterval(-Double(minutes*60))
    return max(cutoff,min(points.first?.date ?? end,end.addingTimeInterval(-30)))
}

func sensorTrendPeriodText(_ points:[MetricPoint],end:Date,minutes:Int)->String {
    let seconds=max(0,Int(end.timeIntervalSince(points.first?.date ?? end)))
    if seconds>=minutes*60-15 {return String(format:L("近 %d 分钟"),minutes)}
    return String(format:L("已记录 %d 分 %d 秒"),seconds/60,seconds%60)
}

struct SensorSparkline:View {
    @AppStorage("menuCPUWarnings") private var warningsEnabled=true
    let points:[MetricPoint]
    let end:Date
    let minutes:Int
    let kind:HardwareSensorKind
    var warningKind:MetricKind?
    var body:some View {
        let plotted=MetricPlot.decimated(points,budget:80)
        let scale=sensorTrendScale(points,kind:kind)
        let start=sensorTrendStart(points,end:end,minutes:minutes)
        let runs=MetricWarningBands.runs(points,kind:warningKind,enabled:warningsEnabled,budget:80)
        Chart {
            ForEach(runs) {run in ForEach(run.points) {point in
                LineMark(x:.value(L("时间"),point.date),y:.value(L(kind.title),point.value!),series:.value(L("连续记录"),"\(run.id):\(point.segment)"))
                    .foregroundStyle(run.level.plotColor()).lineStyle(StrokeStyle(lineWidth:1.7,lineCap:.round))
                if run.points.count==1 || point.id==plotted.last?.id {
                    PointMark(x:.value(L("时间"),point.date),y:.value(L(kind.title),point.value!)).foregroundStyle(run.level.plotColor()).symbolSize(12)
                }
            }}
        }.chartXScale(domain:start...end).chartYScale(domain:scale)
            .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
            .padding(.vertical,3).allowsHitTesting(false)
            .overlay(alignment:.leading) {
            if plotted.count<2 {
                Text(L(plotted.isEmpty ? "暂无历史读数":"正在积累趋势…")).font(AppTypography.caption).foregroundStyle(Palette.secondaryText)
            }
        }.accessibilityHidden(true)
    }
}

struct SensorTrendSheet:View {
    @AppStorage("menuCPUWarnings") private var warningsEnabled=true
    @ObservedObject var history:SensorHistoryStore
    let initial:CommonSensorReading
    @Binding var minutes:Int
    @Environment(\.dismiss) private var dismiss
    @State private var hovered:MetricPoint?
    private var reading:CommonSensorReading? {history.readings.first{$0.id==initial.id}}
    private var title:String {commonSensorTitle(initial)}
    private var full:[MetricPoint] {history.points(for:initial.id,minutes:minutes)}
    private var values:[Double] {full.compactMap(\.value)}
    private var points:[MetricPoint] {MetricPlot.decimated(full,budget:240)}
    private var runs:[CPULoadRun] {MetricWarningBands.runs(full,kind:MetricWarningBands.kind(commonID:initial.id),enabled:warningsEnabled,budget:240)}
    private var end:Date {history.end}
    private var start:Date {sensorTrendStart(full,end:end,minutes:minutes)}
    private var scale:ClosedRange<Double> {sensorTrendScale(full,kind:initial.kind)}
    private var recordedSeconds:Int {
        let valid=full.filter{$0.value != nil}
        guard let first=valid.first,let last=valid.last else{return 0}
        return max(0,Int(last.date.timeIntervalSince(first.date)))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:5) {
                    Text(title).font(AppTypography.title)
                    Text(L(initial.explanation)).font(AppTypography.caption).foregroundStyle(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
                }
                Spacer(minLength:16)
                Button(L("完成")){dismiss()}.keyboardShortcut(.cancelAction)
            }
            HStack(alignment:.firstTextBaseline) {
                Text(sensorValueText(reading?.value,kind:initial.kind)).font(AppTypography.number(30)).monospacedDigit()
                Spacer()
                SensorTrendRangePicker(minutes:$minutes)
            }
            if reading?.value==nil {
                Text(L("当前读数暂时中断，以下为已有历史采样。")).font(AppTypography.caption).foregroundStyle(Palette.secondaryText)
            }
            trendChart
            HStack {
                if let hovered {
                    Text(hovered.date,format:.dateTime.hour().minute().second())
                    Text(sensorValueText(hovered.value,kind:initial.kind)).foregroundStyle(.primary)
                } else {Text(L("悬停或点击查看读数"))}
                Spacer()
                Text(String(format:L("已记录 %d 分 %d 秒"),recordedSeconds/60,recordedSeconds%60))
            }.font(AppTypography.caption).monospacedDigit().foregroundStyle(Palette.secondaryText).frame(height:18)
            Divider().opacity(0.5)
            HStack(spacing:36) {
                stat("最低",values.min())
                stat("采样均值",values.isEmpty ? nil:values.reduce(0,+)/Double(values.count))
                stat("最高",values.max())
                Spacer()
            }
            Text(L("仅保留本次运行最近 30 分钟；退出后清空。")).font(AppTypography.caption).foregroundStyle(Palette.secondaryText)
        }.padding(24).frame(width:620).background(Palette.canvas)
            .onChange(of:minutes){_ in hovered=nil}
    }
    private var trendChart:some View {
        return Chart {
            ForEach(runs) {run in ForEach(run.points) {point in
                LineMark(x:.value(L("时间"),point.date),y:.value(title,point.value!),series:.value(L("连续记录"),"\(run.id):\(point.segment)"))
                    .foregroundStyle(run.level.plotColor()).lineStyle(StrokeStyle(lineWidth:2,lineCap:.round))
                if run.points.count==1 {
                    PointMark(x:.value(L("时间"),point.date),y:.value(title,point.value!)).foregroundStyle(run.level.plotColor()).symbolSize(20)
                }
            }}
            if let hovered,let value=hovered.value {
                RuleMark(x:.value(L("时间"),hovered.date)).foregroundStyle(.primary.opacity(0.2))
                PointMark(x:.value(L("时间"),hovered.date),y:.value(title,value)).foregroundStyle(Palette.violet).symbolSize(34)
            }
        }.chartXScale(domain:start...end).chartYScale(domain:scale).chartLegend(.hidden).frame(height:220)
            .chartYAxis {
                AxisMarks(position:.leading,values:.automatic(desiredCount:4)) {value in
                    AxisGridLine(stroke:StrokeStyle(lineWidth:0.5,dash:[3,4])).foregroundStyle(.primary.opacity(0.10))
                    AxisValueLabel {if let number=value.as(Double.self) {Text(valueText(number,initial.kind == .fan ? "%.0f":"%.1f"))}}
                }
            }
            .chartXAxis {
                AxisMarks(values:[0.1,0.5,0.9].map{start.addingTimeInterval(end.timeIntervalSince(start)*$0)}) {value in
                    AxisValueLabel {
                        if let date=value.as(Date.self) {
                            Text(date,format:end.timeIntervalSince(start)<120 ? .dateTime.hour().minute().second():.dateTime.hour().minute()).fixedSize()
                        }
                    }
                }
            }
            .chartOverlay {proxy in GeometryReader {geometry in
                Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover {phase in
                    switch phase {
                    case .active(let location):inspect(location,proxy:proxy,geometry:geometry)
                    case .ended:hovered=nil
                    }
                }
                .gesture(DragGesture(minimumDistance:0).onChanged {value in inspect(value.location,proxy:proxy,geometry:geometry)})
            }}
            .overlay {if points.isEmpty {Text(L("暂无历史读数")).font(AppTypography.caption).foregroundStyle(Palette.secondaryText)}}
            .accessibilityLabel(title+" · "+L("趋势图"))
    }
    private func inspect(_ location:CGPoint,proxy:ChartProxy,geometry:GeometryProxy) {
        let plot=geometry[proxy.plotAreaFrame]
        guard plot.contains(location),let date:Date=proxy.value(atX:location.x-plot.minX) else{hovered=nil;return}
        hovered=MetricPlot.nearest(full,to:date,maximumDistance:15)
    }
    private func stat(_ title:String,_ value:Double?)->some View {
        VStack(alignment:.leading,spacing:5) {
            Text(L(title)).font(AppTypography.caption).foregroundStyle(Palette.secondaryText)
            Text(sensorValueText(value,kind:initial.kind)).font(AppTypography.number(16)).monospacedDigit()
        }
    }
}
