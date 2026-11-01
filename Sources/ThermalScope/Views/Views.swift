import AppKit
import SwiftUI
import Charts
import ThermalCore

struct NativeMaterial:NSViewRepresentable {
    let material:NSVisualEffectView.Material
    func makeNSView(context:Context)->NSVisualEffectView {
        let v=NSVisualEffectView();v.material=material;v.blendingMode = .behindWindow;v.state = .active;return v
    }
    func updateNSView(_ v:NSVisualEffectView,context:Context) { v.material=material }
}
struct ChartOptions:View {
    @Binding var automatic:Bool
    @Binding var filled:Bool
    let paused:Bool
    let onPause:()->Void
    var body:some View {
        HStack(spacing:10) {
            Button(action:onPause) {Label(L(paused ? "继续实时":"暂停图表"),systemImage:paused ? "play.fill":"pause.fill")}.buttonStyle(.bordered).controlSize(.small)
            Spacer()
            Picker(L("纵轴刻度"),selection:$automatic) {Text(L("固定刻度")).tag(false);Text(L("自动刻度")).tag(true)}.pickerStyle(.segmented).labelsHidden().fixedSize()
            Picker(L("图形样式"),selection:$filled) {Text(L("线条")).tag(false);Text(L("面积")).tag(true)}.pickerStyle(.segmented).labelsHidden().fixedSize()
        }.font(.caption).controlSize(.small).tint(Palette.action)
    }
}
struct ChartReadout:View {
    let date:Date?
    let value:String
    var mode:String?=nil
    var color:Color=Palette.violet
    let paused:Bool
    var body:some View {
        HStack(spacing:10) {
            if let date {
                Text(value).font(.system(size:16,weight:.semibold,design:.rounded)).monospacedDigit()
                Text(date,format:.dateTime.hour().minute().second()).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                if let mode {Text(L(mode)).font(.caption).lineLimit(1).foregroundStyle(color)}
            } else {Image(systemName:"cursorarrow.rays").foregroundStyle(Palette.violet);Text(L("悬停查看真实采样")).font(.caption).foregroundStyle(.secondary)}
            Spacer(minLength:0)
            Label(L(paused ? "已暂停图表":"实时"),systemImage:paused ? "pause.circle":"waveform.path").font(.caption).foregroundStyle(Palette.violet)
        }.frame(minHeight:24).accessibilityElement(children:.combine)
    }
}
struct TemperaturePanel:View,Equatable {
    @ObservedObject var timeline:TemperatureTimelineStore
    static func ==(lhs:Self,rhs:Self)->Bool {lhs.timeline === rhs.timeline && lhs.expanded==rhs.expanded && lhs.allowsSensorSelection==rhs.allowsSensorSelection}
    let expanded:Bool
    var allowsSensorSelection=true
    @State private var hovered:ModeRecord?
    @State private var frozen:[ModeRecord]?
    @State private var frozenEnd:Date?
    @State private var automatic=false
    @State private var filled=false
    var end:Date {frozenEnd ?? timeline.end}
    var start:Date {end.addingTimeInterval(-Double(timeline.minutes*60))}
    var full:[ModeRecord] {frozen ?? timeline.fullPoints}
    var points:[ModeRecord] {frozen.map{SensorTimeline.decimated($0)} ?? timeline.points}
    var modes:[String] {Array(Set(full.map(\.mode))).sorted()}
    var scale:ClosedRange<Double> {MetricPlot.scale(full.map(\.temperature),automatic:automatic,baseline:20,upper:130)}
    var average:Double? {full.isEmpty ? nil:full.map(\.temperature).reduce(0,+)/Double(full.count)}
    func color(_ mode:String)->Color {Palette.mode(mode)}
    var transitions:[ModeRecord] {
        zip(points,points.dropFirst()).compactMap {previous,next in previous.mode != next.mode && next.date.timeIntervalSince(previous.date)<=15 ? next:nil}
    }
    func transitionLabel(_ change:ModeRecord)->String {
        guard let index=points.firstIndex(where:{$0.id==change.id}),index>0 else{return "模式切换"}
        if points[index-1].turboDisabled != change.turboDisabled {return change.turboDisabled == true ? "睿频关闭":(change.turboDisabled == false ? "允许睿频":"睿频未知")}
        return change.mode.components(separatedBy:" · ").first ?? "模式切换"
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text(L("温度趋势")).font(.system(size:14,weight:.semibold));Spacer()
                if allowsSensorSelection {Picker(L("温度来源"),selection:$timeline.sensor) {Text("CPU").tag(SensorCategory.cpu);Text("GPU").tag(SensorCategory.gpu);Text(L("硬盘 / 存储")).tag(SensorCategory.storage);Text(L("电池")).tag(SensorCategory.battery)}.labelsHidden().frame(width:135)}
                Text("°C").font(.caption).foregroundStyle(.secondary)
                Picker(L("时间范围"),selection:$timeline.minutes) {Text(L("5 分钟")).tag(5);Text(L("10 分钟")).tag(10);Text(L("30 分钟")).tag(30)}.labelsHidden().frame(width:90)
            }
            ChartOptions(automatic:$automatic,filled:$filled,paused:frozen != nil,onPause:togglePause)
            if !modes.isEmpty {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:180),alignment:.leading)],alignment:.leading,spacing:8) {
                    ForEach(modes,id:\.self) {mode in HStack(spacing:6) {Circle().fill(color(mode)).frame(width:6,height:6);Text(L(mode)).font(.system(size:11)).foregroundStyle(.secondary)}}
                }
            }
            temperatureChart
            ChartReadout(date:hovered?.date,value:hovered.map{String(format:"%.1f°C",$0.temperature)} ?? "—",mode:hovered?.mode,color:hovered.map{color($0.mode)} ?? Palette.violet,paused:frozen != nil)
            Divider().opacity(0.4)
            HStack(spacing:24) {
                summary(L("最新温度"),full.last?.temperature,"°C");summary(L("区间均温"),average,"°C");summary(L("最高"),full.map(\.temperature).max(),"°C");Spacer()
            }
            Text(L("虚线：睿频关闭；竖线：检测到切换。")).font(.system(size:10)).foregroundStyle(.secondary)
        }.padding(22).subtlePanel().onChange(of:timeline.sensor){_ in resume()}.onChange(of:timeline.minutes){_ in resume()}.onDisappear{resume()}
    }
    var temperatureChart:some View {
        Chart {
            ForEach(points) {p in
                if filled {AreaMark(x:.value(L("时间"),p.date),yStart:.value(L("温度"),scale.lowerBound),yEnd:.value(L("温度"),p.temperature),series:.value(L("连续记录"),p.series)).foregroundStyle(LinearGradient(colors:[color(p.mode).opacity(0.22),color(p.mode).opacity(0.015)],startPoint:.top,endPoint:.bottom))}
                LineMark(x:.value(L("时间"),p.date),y:.value(L("温度"),p.temperature),series:.value(L("连续记录"),p.series)).foregroundStyle(by:.value(L("模式"),L(p.mode))).lineStyle(StrokeStyle(lineWidth:2.1,lineCap:.round,dash:p.turboDisabled == true ? [5,3]:[]))
                if points.count<3 {PointMark(x:.value(L("时间"),p.date),y:.value(L("温度"),p.temperature)).foregroundStyle(color(p.mode)).symbolSize(18)}
            }
            ForEach(transitions) {change in
                RuleMark(x:.value(L("切换"),change.date)).foregroundStyle(color(change.mode).opacity(0.45)).lineStyle(StrokeStyle(lineWidth:1,dash:[4,4])).annotation(position:.top,alignment:change.date.timeIntervalSince(start)>end.timeIntervalSince(start)*0.7 ? .trailing:.leading){Text(L(transitionLabel(change))).font(.system(size:9)).foregroundStyle(.secondary)}
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
                    case .active(let location):
                        let plot=geometry[proxy.plotAreaFrame],x=location.x-plot.minX
                        guard plot.contains(location),let date:Date=proxy.value(atX:x),let nearest=full.min(by:{abs($0.date.timeIntervalSince(date))<abs($1.date.timeIntervalSince(date))}),abs(nearest.date.timeIntervalSince(date))<=15 else {hovered=nil;return}
                        if hovered?.id != nearest.id {hovered=nearest}
                    case .ended:hovered=nil
                    }
                }
            }}.frame(height:expanded ? 250:175).padding(.top,8)
            .overlay {if points.isEmpty {Text(L("当前来源暂无温度读数")).font(.caption).foregroundStyle(.secondary)}}
            .accessibilityLabel(L("按运行模式分色的温度时间线"))
    }
    func togglePause() {if frozen != nil {resume()} else {frozen=timeline.fullPoints;frozenEnd=timeline.end;hovered=nil}}
    func resume() {frozen=nil;frozenEnd=nil;hovered=nil}
    func summary(_ title:String,_ value:Double?,_ unit:String)->some View {VStack(alignment:.leading,spacing:6){Text(title).font(.system(size:10)).foregroundStyle(.secondary);Text(value.map{String(format:"%.1f",$0)+unit} ?? "—").font(.system(size:21,weight:.medium,design:.rounded)).monospacedDigit()}}
}
struct AmbientCanvas:View {
    @Environment(\.accessibilityReduceTransparency) private var reduced
    var body:some View {
        Palette.canvas.overlay(alignment:.topLeading) {
            if !reduced {RadialGradient(colors:[Palette.violet.opacity(0.095),.clear],center:.topLeading,startRadius:0,endRadius:650).allowsHitTesting(false)}
        }.ignoresSafeArea()
    }
}
struct PanelSurface:ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduced
    func body(content:Content)->some View {
        content.background {
            RoundedRectangle(cornerRadius:20,style:.continuous).fill(Palette.surface)
                .overlay {if !reduced {RoundedRectangle(cornerRadius:20,style:.continuous).fill(LinearGradient(colors:[Palette.highlight.opacity(0.16),Palette.violet.opacity(0.025),.clear],startPoint:.topLeading,endPoint:.bottomTrailing))}}
        }.overlay {RoundedRectangle(cornerRadius:20,style:.continuous).stroke(LinearGradient(colors:[Palette.highlight.opacity(0.6),Palette.border.opacity(0.65)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.7)}
            .shadow(color:.black.opacity(reduced ? 0:0.045),radius:10,x:0,y:4)
    }
}
extension View {
    func subtlePanel()->some View {modifier(PanelSurface())}
    @ViewBuilder func controlGlass()->some View {
        if #available(macOS 26.0,*) {glassEffect(.regular,in:Capsule())}
        else {background(.regularMaterial,in:Capsule())}
    }
}
