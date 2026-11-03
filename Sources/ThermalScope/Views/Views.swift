import AppKit
import SwiftUI
import Charts
import ThermalCore

struct ChartOptions:View {
    @Binding var automatic:Bool
    @Binding var filled:Bool
    let paused:Bool
    let onPause:()->Void
    var body:some View {
        HStack(spacing:10) {
            Button(action:onPause) {Label(L(paused ? "继续实时":"暂停图表"),systemImage:AppSymbols.resolve(paused ? "play.fill":"pause.fill"))}.buttonStyle(AppNativeButtonStyle()).appControlSize(.small)
            Picker(L("纵轴刻度"),selection:$automatic) {Text(L("固定刻度")).tag(false);Text(L("自动刻度")).tag(true)}.pickerStyle(.segmented).labelsHidden().fixedSize()
            Picker(L("图形样式"),selection:$filled) {Text(L("线条")).tag(false);Text(L("面积")).tag(true)}.pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer(minLength:0)
        }.font(.system(size:12)).appControlSize(.small)
    }
}
struct ChartReadout:View {
    let date:Date?
    let value:String
    var mode:String?=nil
    var color:Color=Palette.violet
    let paused:Bool
    var supportsClickInspection=false
    @Environment(\.neutralPanels) private var neutralPanels
    private var accent:Color {neutralPanels ? MonitorAppearance.accent:Palette.violet}
    var body:some View {
        HStack(spacing:10) {
            if let date {
                Text(value).font(AppTypography.number(16,weight:.semibold)).appMonospacedDigit()
                Text(date,style:.time).font(.system(size:12)).appMonospacedDigit().foregroundColor(Palette.secondaryText)
                if let mode {Text(L(mode)).font(.system(size:12)).lineLimit(1).foregroundColor(color).help(L(mode))}
            } else {Image(systemName:AppSymbols.resolve("cursorarrow.rays")).foregroundColor(accent);Text(L(supportsClickInspection ? "悬停或点击查看读数":"悬停查看真实采样")).font(.system(size:12)).foregroundColor(Palette.secondaryText)}
            Spacer(minLength:0)
            Label(L(paused ? "已暂停图表":"实时"),systemImage:AppSymbols.resolve(paused ? "pause.circle":"waveform.path")).font(.system(size:12)).foregroundColor(accent)
        }.frame(minHeight:24).accessibilityElement(children:.combine)
    }
}
struct TemperaturePanel:View,Equatable {
    @ObservedObject var timeline:TemperatureTimelineStore
    @AppStorage("menuCPUWarnings") private var warningsEnabled=true
    @Environment(\.neutralPanels) private var neutralPanels
    static func ==(lhs:Self,rhs:Self)->Bool {lhs.timeline === rhs.timeline && lhs.expanded==rhs.expanded && lhs.allowsSensorSelection==rhs.allowsSensorSelection}
    let expanded:Bool
    var allowsSensorSelection=true
    @State private var showOptions=false
    @State private var hovered:ModeRecord?
    @State private var frozen:[ModeRecord]?
    @State private var frozenEnd:Date?
    @State private var automatic=false
    @State private var filled=false
    init(timeline:TemperatureTimelineStore,expanded:Bool,allowsSensorSelection:Bool=true,initialArea:Bool=false) {
        self.timeline=timeline;self.expanded=expanded;self.allowsSensorSelection=allowsSensorSelection
        self._filled=State(initialValue:initialArea)
    }
    var end:Date {frozenEnd ?? timeline.end}
    var start:Date {end.addingTimeInterval(-Double(timeline.minutes*60))}
    var full:[ModeRecord] {frozen ?? timeline.fullPoints}
    var points:[ModeRecord] {frozen.map{SensorTimeline.decimated($0)} ?? timeline.points}
    var modes:[String] {Array(Set(full.map(\.mode))).sorted()}
    var scale:ClosedRange<Double> {MetricPlot.scale(full.map(\.temperature),automatic:automatic,baseline:20,upper:130)}
    var average:Double? {full.isEmpty ? nil:full.map(\.temperature).reduce(0,+)/Double(full.count)}
    private var warningKind:MetricKind? {timeline.sensor == .cpu ? .cpuTemperature:(timeline.sensor == .gpu ? .gpuTemperature:nil)}
    private var warningRuns:[CPULoadRun] {
        MetricWarningBands.runs(full.map{MetricPoint(date:$0.date,value:$0.temperature,segment:$0.segment)},kind:warningKind,enabled:warningsEnabled,budget:300).filter{$0.level > .normal}
    }
    private var accent:Color {neutralPanels ? MonitorAppearance.accent:Palette.violet}
    func color(_ mode:String)->Color {neutralPanels ? MonitorAppearance.mode(mode):Palette.mode(mode)}
    var transitions:[ModeRecord] {
        zip(full,full.dropFirst()).compactMap {previous,next in previous.mode != next.mode && next.date.timeIntervalSince(previous.date)<=15 ? next:nil}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(L("温度趋势")).font(.system(size:14,weight:.semibold));Spacer()
                if timeline.isPreview {Text(L("模拟")).font(AppTypography.caption).foregroundColor(.orange)}
                if allowsSensorSelection {Picker(L("温度来源"),selection:$timeline.sensor) {Text("CPU").tag(SensorCategory.cpu);Text("GPU").tag(SensorCategory.gpu);Text(L("硬盘 / 存储")).tag(SensorCategory.storage);Text(L("电池")).tag(SensorCategory.battery)}.labelsHidden().frame(width:135)}
                Text("°C").font(.system(size:12)).foregroundColor(Palette.secondaryText)
                Picker(L("时间范围"),selection:$timeline.minutes) {Text(L("5 分钟")).tag(5);Text(L("10 分钟")).tag(10);Text(L("30 分钟")).tag(30)}.labelsHidden().frame(width:90)
            }
            if points.isEmpty {
                SensorUnavailableNotice()
            } else {
            if expanded {ChartOptions(automatic:$automatic,filled:$filled,paused:frozen != nil,onPause:togglePause)}
            else if !neutralPanels {options}
            if modes.count>1 || (!neutralPanels && !modes.isEmpty) {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:180),alignment:.leading)],alignment:.leading,spacing:8) {
                    ForEach(modes,id:\.self) {mode in HStack(spacing:6) {Circle().fill(color(mode)).frame(width:6,height:6);Text(L(mode)).font(.system(size:12)).foregroundColor(Palette.secondaryText)}}
                }
            }
            temperatureChart
            ChartReadout(date:hovered?.date,value:hovered.map{String(format:"%.1f°C",$0.temperature)} ?? "—",mode:hovered?.mode,color:hovered.map{color($0.mode)} ?? accent,paused:frozen != nil,supportsClickInspection:true)
            Divider().opacity(0.4)
            if neutralPanels {
                HStack(spacing:20) {
                    summary(L("最新温度"),full.last?.temperature,"°C").frame(maxWidth:.infinity,alignment:.leading)
                    Divider().frame(height:36).opacity(0.45)
                    summary(L("区间均温"),average,"°C").frame(maxWidth:.infinity,alignment:.leading)
                    Divider().frame(height:36).opacity(0.45)
                    summary(L("最高"),full.map(\.temperature).max(),"°C").frame(maxWidth:.infinity,alignment:.leading)
                }
            } else {
                HStack(spacing:24) {
                    summary(L("最新温度"),full.last?.temperature,"°C");summary(L("区间均温"),average,"°C");summary(L("最高"),full.map(\.temperature).max(),"°C");Spacer()
                }
            }
            if expanded || !transitions.isEmpty {
                Text(L(ControlAvailability.isAppleSilicon ? "竖线：检测到运行模式切换。":"虚线：睿频关闭；竖线：检测到切换。")).font(.system(size:12)).foregroundColor(Palette.secondaryText)
            }
            if neutralPanels && !expanded {options}
            }
        }.modifier(TemperaturePanelSurface(neutral:neutralPanels)).onChange(of:timeline.sensor){_ in resume()}.onChange(of:timeline.minutes){_ in resume()}.onDisappear{resume()}
    }
    private var options:some View {
        DisclosureGroup(L("图表选项"),isExpanded:$showOptions) {
            ChartOptions(automatic:$automatic,filled:$filled,paused:frozen != nil,onPause:togglePause).padding(.top,8)
        }.font(.system(size:12))
    }
    @ViewBuilder var temperatureChart:some View {
        if #available(macOS 13,*),!PlatformUI.classic {modernTemperatureChart}
        else {
            let grouped=Dictionary(grouping:points,by:\.segment)
            let base=grouped.keys.sorted().map {segment in
                let values=grouped[segment]!
                return CompatibilityPlot.Series(id:"mode:\(segment)",points:values.map{.init(x:$0.date.timeIntervalSince1970,y:$0.temperature,segment:$0.segment)},color:color(values[0].mode),filled:filled,dash:values[0].turboDisabled == true ? [5,3]:[])
            }
            let warnings=CompatibilityPlot.metricSeries(warningRuns)
            CompatibilityPlot(series:base+warnings,xRange:start.timeIntervalSince1970...end.timeIntervalSince1970,yRange:scale,rules:transitions.map{.init(id:String(describing:$0.id),x:$0.date.timeIntervalSince1970,color:color($0.mode))},axes:true,xLabel:CompatibilityPlot.timeLabel,onInspect:{value in
                guard let value,let nearest=full.min(by:{abs($0.date.timeIntervalSince1970-value)<abs($1.date.timeIntervalSince1970-value)}),abs(nearest.date.timeIntervalSince1970-value)<=15 else {hovered=nil;return}
                hovered=nearest
            }).frame(height:expanded ? 250:160).padding(.top,8).accessibilityLabel(L("按运行模式分色的温度时间线"))
        }
    }
    @available(macOS 13,*) private var modernTemperatureChart:some View {
        let counts=Dictionary(grouping:points,by:\.segment).mapValues(\.count)
        return Chart {
            ForEach(points) {p in
                if filled {AreaMark(x:.value(L("时间"),p.date),yStart:.value(L("温度"),scale.lowerBound),yEnd:.value(L("温度"),p.temperature),series:.value(L("连续记录"),p.series)).foregroundStyle(LinearGradient(gradient:Gradient(colors:[color(p.mode).opacity(0.22),color(p.mode).opacity(0.015)]),startPoint:.top,endPoint:.bottom))}
                LineMark(x:.value(L("时间"),p.date),y:.value(L("温度"),p.temperature),series:.value(L("连续记录"),p.series)).foregroundStyle(by:.value(L("模式"),L(p.mode))).lineStyle(StrokeStyle(lineWidth:2.1,lineCap:.round,dash:p.turboDisabled == true ? [5,3]:[]))
                if points.count<3 || counts[p.segment]==1 {PointMark(x:.value(L("时间"),p.date),y:.value(L("温度"),p.temperature)).foregroundStyle(color(p.mode)).symbolSize(18)}
            }
            ForEach(warningRuns) {run in ForEach(run.points) {point in
                LineMark(x:.value(L("时间"),point.date),y:.value(L("温度"),point.value!),series:.value(L("连续记录"),"warning:\(run.id):\(point.segment)"))
                    .foregroundStyle(run.level.plotColor(normal:accent)).lineStyle(StrokeStyle(lineWidth:2.3,lineCap:.round))
                if run.points.count==1 {PointMark(x:.value(L("时间"),point.date),y:.value(L("温度"),point.value!)).foregroundStyle(run.level.plotColor(normal:accent)).symbolSize(18)}
            }}
            ForEach(transitions) {change in
                RuleMark(x:.value(L("切换"),change.date)).foregroundStyle(color(change.mode).opacity(0.3)).lineStyle(StrokeStyle(lineWidth:1,dash:[4,4]))
            }
            if let hovered {
                RuleMark(x:.value(L("时间"),hovered.date)).foregroundStyle(.primary.opacity(0.25))
                PointMark(x:.value(L("时间"),hovered.date),y:.value(L("温度"),hovered.temperature)).foregroundStyle(color(hovered.mode)).symbolSize(36)
            }
        }.chartXScale(domain:start...end).chartYScale(domain:scale)
            .chartForegroundStyleScale(domain:modes.map{L($0)},range:modes.map{color($0)}).chartLegend(.hidden)
            .chartYAxis {AxisMarks(position:.leading,values:.automatic(desiredCount:4)) {_ in AxisGridLine(stroke:StrokeStyle(lineWidth:0.5,dash:[3,4])).foregroundStyle(.primary.opacity(0.10));AxisValueLabel().foregroundStyle(Color.secondary)}}
            .chartXAxis {AxisMarks(values:[0.1,0.5,0.9].map{start.addingTimeInterval(end.timeIntervalSince(start)*$0)}) {_ in AxisValueLabel(format:.dateTime.hour().minute()).foregroundStyle(Color.secondary)}}
            .chartOverlay {proxy in GeometryReader {geometry in
                Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover {phase in
                    switch phase {
                    case .active(let location):inspect(location,proxy:proxy,geometry:geometry)
                    case .ended:hovered=nil
                    }
                }
                .gesture(DragGesture(minimumDistance:0).onChanged {value in inspect(value.location,proxy:proxy,geometry:geometry)})
            }}.frame(height:expanded ? 250:160).padding(.top,8)
            .appOverlay {if points.isEmpty {Text(L("当前来源暂无温度读数")).font(.system(size:12)).foregroundStyle(Palette.secondaryText)}}
            .accessibilityLabel(L("按运行模式分色的温度时间线"))
    }
    @available(macOS 13,*) func inspect(_ location:CGPoint,proxy:ChartProxy,geometry:GeometryProxy) {
        let plot=geometry[proxy.plotAreaFrame],x=location.x-plot.minX
        guard plot.contains(location),let date:Date=proxy.value(atX:x),let nearest=full.min(by:{abs($0.date.timeIntervalSince(date))<abs($1.date.timeIntervalSince(date))}),abs(nearest.date.timeIntervalSince(date))<=15 else {hovered=nil;return}
        if hovered?.id != nearest.id {hovered=nearest}
    }
    func togglePause() {if frozen != nil {resume()} else {frozen=timeline.fullPoints;frozenEnd=timeline.end;hovered=nil}}
    func resume() {frozen=nil;frozenEnd=nil;hovered=nil}
    func summary(_ title:String,_ value:Double?,_ unit:String)->some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.system(size:12)).foregroundColor(.secondary)
            if neutralPanels {MetricValue(value:value.map{String(format:"%.1f",$0)} ?? "—",unit:unit,size:21,unitSize:11)}
            else {Text(value.map{String(format:"%.1f",$0)+unit} ?? "—").font(AppTypography.number(21,weight:.medium)).appMonospacedDigit()}
        }
    }
}
private struct TemperaturePanelSurface:ViewModifier {
    let neutral:Bool
    @ViewBuilder func body(content:Content)->some View {
        if neutral {content.padding(20).modifier(NeutralPanelSurface())}
        else {content.subtlePanel()}
    }
}
struct AmbientCanvas:View {
    var body:some View {
        MonitorCanvas()
    }
}
struct PanelSurface:ViewModifier {
    func body(content:Content)->some View {
        content.modifier(NeutralPanelSurface())
    }
}
/// Keep native GroupBox semantics with the shared application surface.
private struct AppPanelStyle:GroupBoxStyle {
    let padding:CGFloat
    @Environment(\.neutralPanels) private var neutralPanels
    @ViewBuilder func makeBody(configuration:Configuration)->some View {
        if neutralPanels {
            configuration.content.frame(maxWidth:.infinity,alignment:.leading)
                .padding(padding).modifier(NeutralPanelSurface())
        } else {
            configuration.content.frame(maxWidth:.infinity,alignment:.leading)
                .padding(padding).modifier(PanelSurface())
        }
    }
}
extension View {
    func subtlePanel(padding:CGFloat=22)->some View {
        GroupBox {self}.groupBoxStyle(AppPanelStyle(padding:padding))
    }
}

struct SensorUnavailableNotice:View {
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Label(L("未发现可读传感器"),systemImage:AppSymbols.resolve("sensor")).font(AppTypography.section)
            Text(L("此设备可能未提供该传感器，或当前读取失败。可刷新重试；缺失读数不会当作零。"))
                .font(.system(size:13)).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,minHeight:100,alignment:.leading).padding(.vertical,12)
    }
}
