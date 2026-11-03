import SwiftUI
import Charts
import ThermalCore

struct MetricDetailView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var readings:LiveReadings
    @ObservedObject var history:MetricHistoryStore
    let kind:MetricKind
    init(model:AppModel,kind:MetricKind) {self.model=model;self.readings=model.readings;self.history=model.metricHistory;self.kind=kind}
    var current:Double? {
        if let sensor=kind.sensor {return readings.snapshot?.temperature(sensor)}
        switch kind {case .cpuUsage:return readings.snapshot?.cpuUsage;case .memory:return readings.telemetry?.memoryPercent;case .fan:return readings.snapshot?.fans.compactMap(\.rpm).max();case .battery:return readings.telemetry?.batteryPercent;default:return nil}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            if kind.sensor != nil,current == nil,model.timeline.fullPoints.isEmpty {
                SensorUnavailableNotice().subtlePanel()
            } else {
            if current == nil {Label(L("当前读数暂时中断，以下为已有历史采样。"),systemImage:"exclamationmark.circle").font(.system(size:12)).foregroundStyle(.orange)}
            HStack(alignment:.firstTextBaseline) {
                Text(valueText(current)+kind.unit).font(AppTypography.number(38,weight:.medium)).monospacedDigit()
                Spacer()
                if let date=kind == .memory || kind == .battery ? readings.telemetry?.date:readings.snapshot?.date {Text(date,style:.time).font(.system(size:12)).foregroundStyle(Palette.secondaryText)}
            }.subtlePanel()
            if kind.sensor != nil {TemperaturePanel(timeline:model.timeline,expanded:true,allowsSensorSelection:false).equatable()}
            else {MetricTrendChart(history:history,kind:kind,warningsEnabled:model.menuCPUWarnings)}
            facts
            if kind == .cpuUsage {MetricCPUProcesses(observer:model.processes,onReview:{model.processes.sort = .cpu;model.navigation.go(.processes)})}
            }
        }.onAppear {if let sensor=kind.sensor {model.timeline.sensor=sensor}}
    }
    var facts:some View {
        VStack(alignment:.leading,spacing:14) {
            Text(L("指标详情")).font(AppTypography.section)
            if let sensor=kind.sensor {
                fact("热压力",L(readings.snapshot?.thermalTitle ?? "未知"))
                fact("运行模式",L(model.coolingStatus))
                DisclosureGroup(L("传感器读数")) {
                    ForEach((readings.snapshot?.sensors ?? []).filter{$0.category==sensor}.sorted{$0.key<$1.key}) {reading in
                        HStack {Text(reading.label+" · "+reading.key).lineLimit(1);Spacer();Text(String(format:"%.1f°C",reading.celsius)).monospacedDigit()}.font(.system(size:12)).padding(.vertical,3)
                    }
                }
                Button(L("查看传感器")){model.navigation.metric=nil;model.navigation.page = .sensors}.buttonStyle(.borderless)
                Text(L("汇总温度取该类可读传感器的最高值。")).font(.system(size:12)).foregroundStyle(Palette.secondaryText)
            } else if kind == .cpuUsage {
                fact("CPU 使用率",valueText(current)+"%")
                Text(L("100% 表示全部核心")).font(.system(size:12)).foregroundStyle(Palette.secondaryText)
            } else if kind == .memory {
                fact("内存",readings.telemetry?.memoryUsed.map{ByteCountFormatter.string(fromByteCount:Int64($0),countStyle:.memory)} ?? "—")
                fact("内存压力",L(readings.snapshot?.memoryPressure?.title ?? "未知"))
                Text(L("内存按实际采样时间记录，使用率不等于内存压力。")).font(.system(size:12)).foregroundStyle(Palette.secondaryText)
                Button(L("查看内存排行")){model.follow(.memoryProcesses)}.buttonStyle(.bordered)
            } else if kind == .fan {
                fact("运行模式",L(model.coolingStatus))
                ForEach(readings.snapshot?.fans ?? []) {fan in
                    fact(L("风扇")+" \(fan.id+1)",valueText(fan.rpm)+" RPM · "+L(fan.manual.map{$0 ? "手动":"自动"} ?? "未知"),translate:false)
                    Text(valueText(fan.minimum)+"–"+valueText(fan.maximum)+" RPM").font(.system(size:12)).foregroundStyle(Palette.secondaryText)
                }
                Text(L("图表显示可读风扇的最高转速。")).font(.system(size:12)).foregroundStyle(Palette.secondaryText)
                Button(L("前往温度控制")){model.navigation.metric=nil;model.navigation.page = .thermal}.buttonStyle(.bordered)
            } else if kind == .battery {
                fact("当前供电",L(readings.snapshot?.acPower.map{$0 ? "插电":"电池供电"} ?? "未知"))
                fact("电池温度",valueText(readings.snapshot?.temperature(.battery))+"°C")
                fact("充电循环",readings.telemetry?.cycles.map(String.init) ?? "—")
            }
        }.subtlePanel()
    }
    func fact(_ title:String,_ value:String,translate:Bool=true)->some View {
        HStack {Text(translate ? L(title):title).foregroundStyle(Palette.secondaryText);Spacer();Text(value).monospacedDigit()}.font(.system(size:12))
    }
}

struct MetricTrendChart:View {
    @ObservedObject var history:MetricHistoryStore
    let kind:MetricKind
    var warningsEnabled=true
    @State private var minutes=10
    @State private var hovered:MetricPoint?
    @State private var frozen:[MetricPoint]?
    @State private var frozenEnd:Date?
    @State private var automatic=false
    @State private var filled=true
    var end:Date {frozenEnd ?? history.end}
    var full:[MetricPoint] {frozen ?? history.points(kind,minutes:minutes)}
    var values:[Double] {full.compactMap(\.value)}
    var points:[MetricPoint] {MetricPlot.decimated(full)}
    var runs:[CPULoadRun] {MetricWarningBands.runs(full,kind:kind,enabled:warningsEnabled,budget:240)}
    var start:Date {end.addingTimeInterval(-Double(minutes*60))}
    var scale:ClosedRange<Double> {MetricPlot.scale(values,automatic:automatic,upper:kind.fixedUpper)}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {Text(L("趋势图")).font(AppTypography.section);Spacer();Text(kind.unit).font(.system(size:12)).foregroundStyle(Palette.secondaryText);Picker(L("时间范围"),selection:$minutes){Text(L("5 分钟")).tag(5);Text(L("10 分钟")).tag(10);Text(L("30 分钟")).tag(30)}.labelsHidden().frame(width:100)}
            ChartOptions(automatic:$automatic,filled:$filled,paused:frozen != nil,onPause:togglePause)
            if kind == .cpuUsage && warningsEnabled {Text(L("全机 CPU ≥70% 显示橙色；≥90% 连续采样满 10 秒显示红色。缺失或断档重新计时。")).font(.system(size:12)).foregroundStyle(Palette.secondaryText)}
            trendChart
            ChartReadout(date:hovered?.date,value:hovered?.value.map{String(format:"%.1f",$0)+kind.unit} ?? "—",paused:frozen != nil)
            Divider().opacity(0.4)
            HStack(spacing:28) {stat("最低",values.min());stat("采样均值",values.isEmpty ? nil:values.reduce(0,+)/Double(values.count));stat("最高",values.max());Spacer()}
        }.subtlePanel().onChange(of:minutes){_ in resume()}.onDisappear{resume()}
    }
    var trendChart:some View {
        Chart {
            ForEach(runs) {run in ForEach(run.points) {point in
                if filled {AreaMark(x:.value(L("时间"),point.date),yStart:.value(L(kind.title),scale.lowerBound),yEnd:.value(L(kind.title),point.value!),series:.value(L("连续记录"),"\(run.id):\(point.segment)")).foregroundStyle(LinearGradient(colors:[run.level.plotColor().opacity(0.26),run.level.plotColor().opacity(0.015)],startPoint:.top,endPoint:.bottom))}
                LineMark(x:.value(L("时间"),point.date),y:.value(L(kind.title),point.value!),series:.value(L("连续记录"),"\(run.id):\(point.segment)")).foregroundStyle(run.level.plotColor()).lineStyle(StrokeStyle(lineWidth:2.1,lineCap:.round))
                if points.count<3 || run.points.count==1 {PointMark(x:.value(L("时间"),point.date),y:.value(L(kind.title),point.value!)).foregroundStyle(run.level.plotColor()).symbolSize(22)}
            }}
            if let hovered,let value=hovered.value {
                RuleMark(x:.value(L("时间"),hovered.date)).foregroundStyle(.primary.opacity(0.25))
                PointMark(x:.value(L("时间"),hovered.date),y:.value(L(kind.title),value)).foregroundStyle(Palette.violet).symbolSize(36)
            }
        }.chartXScale(domain:start...end).chartYScale(domain:scale).chartLegend(.hidden).frame(height:250)
            .chartYAxis {AxisMarks(position:.leading,values:.automatic(desiredCount:4)) {_ in AxisGridLine(stroke:StrokeStyle(lineWidth:0.5,dash:[3,4])).foregroundStyle(.primary.opacity(0.10));AxisValueLabel().foregroundStyle(Color.secondary)}}
            .chartXAxis {AxisMarks(values:[0.1,0.5,0.9].map{start.addingTimeInterval(end.timeIntervalSince(start)*$0)}) {_ in AxisValueLabel(format:.dateTime.hour().minute()).foregroundStyle(Color.secondary)}}
            .accessibilityLabel(L(kind.title)+" · "+L("趋势图"))
            .chartOverlay {proxy in GeometryReader {geometry in
                Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover {phase in
                    switch phase {
                    case .active(let location):
                        let plot=geometry[proxy.plotAreaFrame],x=location.x-plot.minX
                        guard plot.contains(location),let date:Date=proxy.value(atX:x) else {hovered=nil;return}
                        hovered=MetricPlot.nearest(full,to:date,maximumDistance:kind == .memory || kind == .battery ? 30:15)
                    case .ended:hovered=nil
                    }
                }
            }}.overlay {if points.isEmpty {Text(L("正在积累该指标的历史采样…")).font(.system(size:12)).foregroundStyle(Palette.secondaryText)}}
    }
    func togglePause(){if frozen != nil {resume()} else {frozen=full;frozenEnd=history.end;hovered=nil}}
    func resume(){frozen=nil;frozenEnd=nil;hovered=nil}
    func stat(_ title:String,_ value:Double?)->some View {VStack(alignment:.leading,spacing:5){Text(L(title)).font(.system(size:12)).foregroundStyle(Palette.secondaryText);Text(valueText(value,"%.1f")+kind.unit).font(AppTypography.number(18)).monospacedDigit()}}
}

struct MetricCPUProcesses:View {
    @ObservedObject var observer:ProcessObserver
    let onReview:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text(L("CPU 占用排行")).font(AppTypography.section);Spacer();Button(L("查看进程排行"),action:onReview).buttonStyle(.bordered)}
            ForEach(observer.allRows.sorted{$0.reading.cpu>$1.reading.cpu}.prefix(5)) {row in HStack{Text(row.name).lineLimit(1);Spacer();Text(String(format:"%.1f%%",row.reading.cpu)).monospacedDigit()}.font(.system(size:12))}
            Text(L("每 5 秒更新；进程 CPU 以单个核心 100% 计，多线程应用可能超过 100%。")).font(.system(size:12)).foregroundStyle(Palette.secondaryText)
        }.subtlePanel()
    }
}
