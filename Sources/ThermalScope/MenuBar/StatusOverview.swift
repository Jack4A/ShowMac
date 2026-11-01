import SwiftUI
import Charts
import ThermalCore

/// Exists only while the system popover is open. Sampling stays in the shared stores.
struct StatusOverview:View {
    @ObservedObject var model:AppModel
    @ObservedObject var readings:LiveReadings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let height:CGFloat
    let onNavigate:(String)->Void
    let onSettings:()->Void
    let onActions:()->Void
    init(model:AppModel,height:CGFloat,onNavigate:@escaping(String)->Void,onSettings:@escaping()->Void,onActions:@escaping()->Void) {
        self.model=model;self.readings=model.readings;self.height=height
        self.onNavigate=onNavigate;self.onSettings=onSettings;self.onActions=onActions
    }
    var turbo:String {
        guard let state=readings.snapshot?.turbo else{return "未知"}
        return state == .disabledDriverLoaded ? "已关闭":(state == .driverNotLoaded ? "允许开启":"状态不可用")
    }
    var body:some View {
        VStack(spacing:7) {
            HStack {
                Text(L("温控台")).font(.headline)
                Spacer()
                Picker(L("时间范围"),selection:$model.statusMinutes) {Text(L("2 分钟")).tag(2);Text(L("5 分钟")).tag(5);Text(L("10 分钟")).tag(10)}.labelsHidden().frame(width:100).controlSize(.small)
            }
            HStack(spacing:5) {
                Button {onNavigate("thermal")} label:{HStack(spacing:5){Image(systemName:"slider.horizontal.3");Text(L(model.coolingStatus));Image(systemName:"chevron.right").font(.system(size:7,weight:.semibold))}.lineLimit(1)}.buttonStyle(.plain)
                Spacer(minLength:2)
                Text(L("睿频")+" · "+L(turbo)).lineLimit(1)
            }.font(.body).foregroundStyle(.primary)
            ScrollView(showsIndicators:false) {
                VStack(spacing:7) {
                    StatusGraphCard(readings:readings,history:model.metricHistory,kind:.cpuTemperature,minutes:model.statusMinutes,onOpen:{onNavigate(MetricKind.cpuTemperature.rawValue)})
                    StatusGraphCard(readings:readings,history:model.metricHistory,kind:.cpuUsage,minutes:model.statusMinutes,warningsEnabled:model.menuCPUWarnings,onOpen:{onNavigate(MetricKind.cpuUsage.rawValue)})
                    VStack(spacing:5) {
                        StatusGraphCard(readings:readings,history:model.metricHistory,kind:.fan,minutes:model.statusMinutes,framed:false,onOpen:{onNavigate(MetricKind.fan.rawValue)})
                        StatusFanReadings(readings:readings).padding(.horizontal,9).padding(.bottom,8)
                    }.statusSection()
                    StatusCPUContributor(observer:model.processes,onOpen:{onNavigate(MetricKind.cpuUsage.rawValue)})
                    if model.messageIsError {
                        Button {onNavigate("thermal")} label:{Label(L(model.operationIssue.title),systemImage:"exclamationmark.circle.fill").font(.callout).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).padding(.horizontal,4)
                    }
                }.padding(1)
            }
            HStack(spacing:4) {
                Text(L("采样时间"))
                if let date=readings.snapshot?.date {Text(date,format:.dateTime.hour().minute().second()).monospacedDigit()}
                Spacer(minLength:0)
                Text(L("100% 表示全部核心"))
            }.font(.caption).foregroundStyle(.secondary)
            Divider().opacity(0.55)
            HStack(spacing:12) {
                Button {onNavigate("metrics")} label:{Label(L("打开温控台"),systemImage:"macwindow")}.buttonStyle(.plain)
                Spacer(minLength:0)
                Button {onNavigate("thermal")} label:{Image(systemName:"thermometer.medium")}.help(L("温度控制")).accessibilityLabel(L("温度控制"))
                Button(action:onSettings) {Image(systemName:"gearshape")}.help(L("设置")).accessibilityLabel(L("设置"))
                Button(action:onActions) {Image(systemName:"ellipsis")}.help(L("更多操作")).accessibilityLabel(L("更多操作"))
            }.font(.body).buttonStyle(.borderless).controlSize(.small)
        }.padding(13).frame(width:390,height:height)
            .background {if reduceTransparency {Palette.surface} else {Rectangle().fill(.regularMaterial)}}
            .id(model.language).environment(\.locale,Locale(identifier:AppLocalization.shared.resolvedLanguage)).preferredColorScheme(model.colorScheme).tint(Palette.violet)
            .transaction{$0.animation=nil;$0.disablesAnimations=true}
    }
}

private extension View {
    func statusSection()->some View {
        self.background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
            .overlay(RoundedRectangle(cornerRadius:9).stroke(.primary.opacity(0.09),lineWidth:0.5))
    }
}
struct StatusGraphCard:View {
    @ObservedObject var readings:LiveReadings
    @ObservedObject var history:MetricHistoryStore
    let kind:MetricKind
    let minutes:Int
    var framed=true
    var warningsEnabled=true
    let onOpen:()->Void
    var full:[MetricPoint] {history.points(kind,minutes:minutes)}
    var points:[MetricPoint] {MetricPlot.decimated(full,budget:120)}
    var runs:[CPULoadRun] {kind == .cpuUsage && warningsEnabled ? CPULoadBands.runs(full,budget:120):[CPULoadRun(id:0,level:.normal,points:points)]}
    var loadLevel:CPULoadLevel {kind == .cpuUsage && warningsEnabled ? CPULoadBands.current(current,points:full,at:end):.normal}
    var end:Date {history.end}
    var start:Date {end.addingTimeInterval(-Double(minutes*60))}
    var upper:Double {max(kind.fixedUpper,full.compactMap(\.value).max() ?? 0)}
    var current:Double? {
        if let sensor=kind.sensor {return readings.snapshot?.temperature(sensor)}
        return kind == .fan ? readings.snapshot?.fans.compactMap(\.rpm).max():readings.snapshot?.cpuUsage
    }
    var currentText:String {valueText(current)+kind.unit}
    var body:some View {if framed {content.statusSection()} else {content}}
    var content:some View {
        VStack(alignment:.leading,spacing:4) {
            HStack {
                HStack(spacing:5){Text(L(kind.title)).foregroundStyle(.secondary);if loadLevel > .normal {Text(L(loadLevel.title)).foregroundStyle(loadLevel.plotColor())}}.font(.body)
                Spacer(minLength:2)
                Button(action:onOpen) {HStack(spacing:4){Text(currentText).font(.title2.weight(.semibold)).monospacedDigit();Image(systemName:"chevron.right").font(.system(size:7,weight:.semibold)).foregroundStyle(.secondary)}}.buttonStyle(.plain).help(L("指标详情")).accessibilityLabel(L(kind.title)+" · "+currentText+" · "+L("指标详情"))
            }.frame(height:24)
            Button(action:onOpen) {graph}.buttonStyle(.plain).help(L("指标详情")).accessibilityLabel(L(kind.title)+" · "+L("趋势图")+" · "+L("指标详情"))
            HStack {Text("0–"+valueText(upper)+kind.unit);Spacer(minLength:0);Text(L("固定刻度"))}.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(L("固定刻度")+" 0–"+valueText(upper)+kind.unit)
        }.padding(8)
    }
    var graph:some View {
        Chart {
            ForEach(runs) {run in ForEach(run.points) {point in
                AreaMark(x:.value(L("时间"),point.date),yStart:.value(L(kind.title),0),yEnd:.value(L(kind.title),point.value!),series:.value(L("连续记录"),"\(run.id):\(point.segment)")).foregroundStyle(LinearGradient(colors:[run.level.plotColor().opacity(0.30),run.level.plotColor().opacity(0.045)],startPoint:.top,endPoint:.bottom))
                LineMark(x:.value(L("时间"),point.date),y:.value(L(kind.title),point.value!),series:.value(L("连续记录"),"\(run.id):\(point.segment)")).foregroundStyle(run.level.plotColor()).lineStyle(StrokeStyle(lineWidth:1.3,lineCap:.round))
                if points.count<3 || run.points.count==1 {PointMark(x:.value(L("时间"),point.date),y:.value(L(kind.title),point.value!)).foregroundStyle(run.level.plotColor()).symbolSize(10)}
            }}
        }.chartXScale(domain:start...end).chartYScale(domain:0...upper).chartLegend(.hidden)
            .chartYAxis {AxisMarks(values:[0,upper/2,upper]) {_ in AxisGridLine(stroke:StrokeStyle(lineWidth:0.5,dash:[2,3])).foregroundStyle(.primary.opacity(0.08))}}
            .chartXAxis(.hidden).frame(height:40)
            .overlay {if points.isEmpty {Text(L("正在积累该指标的历史采样…")).font(.caption).foregroundStyle(.secondary)}}
    }
}
struct StatusFanReadings:View {
    @ObservedObject var readings:LiveReadings
    var body:some View {
        let fans=readings.snapshot?.fans ?? []
        if fans.isEmpty {Text(L("风扇状态未知")).font(.callout).foregroundStyle(.secondary)}
        else {
            VStack(spacing:4) {
                ForEach(fans) {fan in
                    HStack(spacing:6) {
                        Image(systemName:"fanblades").foregroundStyle(.secondary)
                        Text(L("风扇")+" \(fan.id+1)")
                        Text(L(fan.manual.map{$0 ? "手动":"自动"} ?? "未知")).foregroundStyle(.primary)
                        Spacer(minLength:2)
                        if let rpm=fan.rpm,let maximum=fan.maximum,maximum>0 {ProgressView(value:max(0,min(maximum,rpm)),total:maximum).progressViewStyle(.linear).tint(Palette.violet).frame(width:40).help(valueText(fan.minimum)+"–"+valueText(maximum)+" RPM")}
                        Text(valueText(fan.rpm)+" RPM").monospacedDigit().frame(minWidth:80,alignment:.trailing)
                    }.font(.callout).accessibilityElement(children:.combine)
                }
            }
        }
    }
}
struct StatusCPUContributor:View {
    @ObservedObject var observer:ProcessObserver
    let onOpen:()->Void
    var rows:[ObservedProcess] {guard let date=observer.sampledAt,Date().timeIntervalSince(date)<20 else{return []};return Array(observer.allRows.sorted{$0.reading.cpu>$1.reading.cpu}.prefix(3))}
    var body:some View {
        let currentRows=rows
        if !currentRows.isEmpty {
            VStack(alignment:.leading,spacing:5) {
                HStack {Text(L("CPU 占用排行"));Spacer();Text(L("单核 100%"))}.font(.caption).foregroundStyle(.secondary)
                ForEach(currentRows) {row in
                    Button(action:onOpen) {
                        HStack(spacing:6) {
                            if let icon=row.application?.icon {Image(nsImage:icon).resizable().frame(width:15,height:15)} else {Image(systemName:"app").frame(width:15,height:15).foregroundStyle(.secondary)}
                            Text(row.name).lineLimit(1);Spacer(minLength:2)
                            Text(String(format:"%.1f%%",row.reading.cpu)).monospacedDigit().fixedSize(horizontal:true,vertical:false)
                        }.font(.body).foregroundStyle(.primary).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(L("每 5 秒更新；进程 CPU 以单个核心 100% 计，多线程应用可能超过 100%。"))
                }
            }.padding(9).statusSection()
        }
    }
}
