import SwiftUI
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
    @ViewBuilder var body:some View {
        let runs=MetricWarningBands.runs(points,kind:warningKind,enabled:warningsEnabled,budget:80)
        MetricPlotView(series:MetricPlotView.metricSeries(runs),xRange:sensorTrendStart(points,end:end,minutes:minutes).timeIntervalSince1970...end.timeIntervalSince1970,yRange:sensorTrendScale(points,kind:kind)).accessibilityHidden(true)

    }

}

struct SensorTrendSheet:View {
    @AppStorage("menuCPUWarnings") private var warningsEnabled=true
    @ObservedObject var history:SensorHistoryStore
    let initial:CommonSensorReading
    @Binding var minutes:Int
    @Environment(\.presentationMode) private var presentationMode
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
                    Text(L(initial.explanation)).font(AppTypography.caption).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
                }
                Spacer(minLength:16)
                Button(L("完成")){presentationMode.wrappedValue.dismiss()}.keyboardShortcut(.cancelAction)
            }
            HStack(alignment:.firstTextBaseline) {
                Text(sensorValueText(reading?.value,kind:initial.kind)).font(AppTypography.number(30)).appMonospacedDigit()
                Spacer()
                SensorTrendRangePicker(minutes:$minutes)
            }
            if reading?.value==nil {
                Text(L("当前读数暂时中断，以下为已有历史采样。")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            }
            trendChart
            HStack {
                if let hovered {
                    Text(hovered.date,style:.time)
                    Text(sensorValueText(hovered.value,kind:initial.kind)).foregroundColor(.primary)
                } else {Text(L("悬停或点击查看读数"))}
                Spacer()
                Text(String(format:L("已记录 %d 分 %d 秒"),recordedSeconds/60,recordedSeconds%60))
            }.font(AppTypography.caption).appMonospacedDigit().foregroundColor(Palette.secondaryText).frame(height:18)
            Divider().opacity(0.5)
            HStack(spacing:36) {
                stat("最低",values.min())
                stat("采样均值",values.isEmpty ? nil:values.reduce(0,+)/Double(values.count))
                stat("最高",values.max())
                Spacer()
            }
            Text(L("仅保留本次运行最近 30 分钟；退出后清空。")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
        }.padding(24).frame(width:620).background(Palette.canvas)
            .onChange(of:minutes){_ in hovered=nil}
    }
    @ViewBuilder private var trendChart:some View {
        MetricPlotView(series:MetricPlotView.metricSeries(runs),xRange:start.timeIntervalSince1970...end.timeIntervalSince1970,yRange:scale,axes:true,xLabel:MetricPlotView.timeLabel,selection:hovered.flatMap{point in point.value.map{.init(x:point.date.timeIntervalSince1970,y:$0)}},onInspect:{value in
            hovered=value.flatMap{MetricPlot.nearest(full,to:Date(timeIntervalSince1970:$0),maximumDistance:15)}
        }).frame(height:220).accessibilityLabel(title+" · "+L("趋势图"))

    }


    private func stat(_ title:String,_ value:Double?)->some View {
        VStack(alignment:.leading,spacing:5) {
            Text(L(title)).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            Text(sensorValueText(value,kind:initial.kind)).font(AppTypography.number(16)).appMonospacedDigit()
        }
    }
}
