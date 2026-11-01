import SwiftUI
import ThermalCore

struct MetricsDashboard:View {
    @ObservedObject var readings:LiveReadings
    @ObservedObject var history:MetricHistoryStore
    let mode:String
    let onTemperature:(SensorCategory)->Void
    let onControl:()->Void
    let onMode:()->Void
    let onMemory:()->Void
    let onCPU:()->Void
    var sample:Snapshot? {readings.snapshot}
    var telemetry:SystemTelemetry? {readings.telemetry}
    var memory:String {
        guard let used=telemetry?.memoryUsed,let total=telemetry?.memoryTotal,total>0 else{return "—"}
        return String(format:"%.1f / %.0f GB",used/1_073_741_824,total/1_073_741_824)
    }
    var body:some View {
        VStack(spacing:12) {
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:3),spacing:12) {
                metric(.cpuTemperature,"CPU 温度",valueText(sample?.cpuTemperature)+"°C","CPU 传感器最高温度","thermometer.medium",Color.primary,help:"查看温度曲线") {onTemperature(.cpu)}
                metric(.gpuTemperature,"GPU 温度",valueText(sample?.temperature(.gpu))+"°C","图形处理器","display",Color.primary,help:"查看温度曲线") {onTemperature(.gpu)}
                metric(.storageTemperature,"存储温度",valueText(sample?.temperature(.storage))+"°C","存储传感器最高温度","internaldrive",Color.primary,help:"查看温度曲线") {onTemperature(.storage)}
                metric(.memory,"内存",memory,L("内存压力")+" · "+L(sample?.memoryPressure?.title ?? "未知"),"memorychip",sample?.memoryPressure.map {$0 == .normal ? Color.primary:Color.orange} ?? Color.secondary,help:"指标详情",localizedDetail:true,smaller:true,action:onMemory)
                metric(.fan,"风扇转速",valueText(sample?.fans.compactMap(\.rpm).max())+" RPM",mode,"fanblades",Color.primary,help:"指标详情",action:onControl)
                metric(.cpuUsage,"CPU 使用率",valueText(sample?.cpuUsage)+"%","100% 表示全部核心","cpu",Color.primary,help:"指标详情",action:onCPU)
            }
            HStack(spacing:16) {
                Button(action:onMode) {
                    Label(L("运行模式")+" · "+L(mode),systemImage:"slider.horizontal.3").lineLimit(1)
                }.buttonStyle(.borderless).foregroundStyle(.primary).help(L("温度控制"))
                Spacer(minLength:0)
                Text(L("睿频")+" · "+L(sample.map {$0.turbo == .disabledDriverLoaded ? "已关闭":($0.turbo == .driverNotLoaded ? "允许开启":"未知")} ?? "未知"))
                Text(L("系统低电量模式")+" · "+L(sample.map {$0.lowPower ? "开启":"关闭"} ?? "未知"))
            }.font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,4).padding(.top,3)
        }
    }
    func metric(_ kind:MetricKind,_ title:String,_ value:String,_ detail:String,_ symbol:String,_ color:Color,help:String,localizedDetail:Bool=false,smaller:Bool=false,action:@escaping ()->Void)->some View {
        Button(action:action) {
            VStack(alignment:.leading,spacing:7) {
                HStack {
                    Label {Text(L(title)).foregroundStyle(.secondary)} icon:{Image(systemName:symbol).foregroundStyle(Palette.violet)}.font(.system(size:10))
                    Spacer(minLength:4)
                    Image(systemName:"chevron.right").font(.system(size:8,weight:.medium)).foregroundStyle(.tertiary)
                }
                Text(value).font(.system(size:smaller ? 21:26,weight:.medium,design:.rounded)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)
                Text(localizedDetail ? detail:L(detail)).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
                MetricSparkline(history:history,kind:kind).padding(.top,3)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(16).subtlePanel()
                .modifier(MetricHover(tint:Palette.violet,cornerRadius:20))
        }.buttonStyle(.plain).help(L(help))
    }
}
struct MetricHover:ViewModifier {
    let tint:Color
    let cornerRadius:CGFloat
    @State private var hovered=false
    func body(content:Content)->some View {
        content.overlay(RoundedRectangle(cornerRadius:cornerRadius).stroke(hovered ? tint.opacity(0.6):Palette.border.opacity(0.65),lineWidth:1))
            .onHover{hovered=$0}
    }
}
