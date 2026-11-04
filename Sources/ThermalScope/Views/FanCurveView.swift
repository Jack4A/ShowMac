import SwiftUI
import ThermalCore

struct FanCurveEditor:View {
    @Binding var curve:FanCurve
    let sample:Snapshot?
    let automatic:Bool
    let busy:Bool
    let onApply:()->Void
    @State private var dragging:Int?
    @State private var original:FanCurve?
    @State private var selectedPoint=2
    var fan:FanReading? {sample?.fans.sorted{$0.id<$1.id}.first}
    var minimum:Double {fan?.minimum ?? 0}
    var maximum:Double {max(minimum+1,fan?.maximum ?? 6000)}
    var available:Bool {ControlAvailability.fansAvailable(sample)}
    var cpuSelected:Bool {curve.sensor != .gpu}
    var gpuSelected:Bool {curve.sensor != .cpu}
    var controlTemperature:Double? {sample.flatMap{curve.sensor.temperature(in:$0)}}
    func rpm(_ percent:Double)->Double {CurvePolicy.rpm(percent:percent,minimum:minimum,maximum:maximum)}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(L(automatic && !AppDistribution.isAppStore ? "自定义曲线 · 未启用":"温度曲线")+" · RPM").font(AppTypography.section).lineLimit(1)
                Spacer()
                HStack(spacing:14) {
                    sourceToggle(.cpu)
                    sourceToggle(.gpu)
                    if curve.sensor == .hottest {
                        Text("MAX "+valueText(controlTemperature,"%.1f")+"°C")
                            .foregroundColor(Palette.secondaryText).appMonospacedDigit()
                            .accessibilityLabel(L("取最高温")+" · "+valueText(controlTemperature,"%.1f")+"°C")
                    }
                }.font(.system(size:12))
                    .fixedSize(horizontal:true,vertical:false)
                    .accessibilityElement(children:.contain).accessibilityLabel(L("温度来源"))
            }
            curveChart.frame(height:260)
            HStack {
                Text(L(AppDistribution.isAppStore ? "温度与风扇读数实时更新":"连续拖动调节，末端点设置最高转速")).font(.system(size:12)).foregroundColor(Palette.secondaryText)
                    .help(L("最高转速不超过风扇额定范围；高温保护可能超过曲线上限。"))
                Spacer(minLength:8)
                if curve.points.indices.contains(dragging ?? selectedPoint) {
                    let point=curve.points[dragging ?? selectedPoint]
                    Text(String(format:"%.1f°C → %.0f RPM",point.temperature,rpm(point.percent))).font(.system(size:12,weight:.medium)).appMonospacedDigit()
                }
            }
            if !available && !AppDistribution.isAppStore {Text(L("风扇或温度读数不可用，暂不能调速。")).font(.system(size:12)).foregroundColor(.orange)}
            else if gpuSelected,sample?.temperature(.gpu)==nil {
                Text(L(curve.sensor == .hottest ? "GPU 温度暂不可读，当前参考 CPU。":"GPU 温度暂不可读，无法按 GPU 调速。"))
                    .font(.system(size:12)).foregroundColor(.orange)
            }
        }.subtlePanel()
    }
    private func sourceToggle(_ source:CurveSensor)->some View {
        let selected=source == .cpu ? cpuSelected:gpuSelected
        let temperature=sample.flatMap{source.temperature(in:$0)}
        let isOnlySource=curve.sensor==source
        let otherTemperature=sample.flatMap{(source == .cpu ? CurveSensor.gpu:.cpu).temperature(in:$0)}
        return Toggle(source.rawValue+" "+valueText(temperature,"%.1f")+"°C",isOn:Binding(get:{selected},set:{enabled in
            if enabled {curve.sensor = .hottest}
            else {curve.sensor = source == .cpu ? .gpu:.cpu}
            onApply()
        })).toggleStyle(.checkbox).fixedSize()
            .disabled(busy || !available || isOnlySource || (!selected && temperature==nil) || (selected && otherTemperature==nil))
            .help(L(isOnlySource ? "至少保留一个温度来源":"勾选 CPU 和 GPU 时，按两者最高温度调速。"))
            .accessibilityIdentifier(source == .cpu ? "curveSourceCPU":"curveSourceGPU")
    }
    @ViewBuilder var curveChart:some View {
        MetricPlotView(series:[.init(id:"fan",points:curve.points.map{.init(x:$0.temperature,y:rpm($0.percent))},color:Palette.violet.opacity(automatic ? 0.5:1),markers:true)],xRange:30...100,yRange:minimum...(maximum+(maximum-minimum)*0.12),rules:sample.flatMap{curve.sensor.temperature(in:$0)}.map{[.init(id:"current",x:$0)]} ?? [],axes:true,xTicks:[30,40,50,60,70,80,90,100],xLabel:{String(format:"%.0f°C",$0)},onDrag:{location,coordinates in
            guard !busy,available else{return}
            if dragging==nil {
                let distances=curve.points.enumerated().map {index,point in
                    let p=coordinates.position(x:point.temperature,y:rpm(point.percent))
                    return (index,hypot(location.x-p.x,location.y-p.y))
                }
                if let nearest=distances.min(by:{$0.1<$1.1}),nearest.1<32 {dragging=nearest.0;selectedPoint=nearest.0;original=curve}
            }
            if let index=dragging,let value=coordinates.value(at:location,clamped:true) {
                setPoint(index,temperature:value.x,percent:CurvePolicy.percent(rpm:value.y,minimum:minimum,maximum:maximum))
            }
        },onDragEnd:{
            let changed=original.map{$0 != curve} ?? false
            dragging=nil;original=nil
            if changed {onApply()}
        },onNudge:moveSelectedPoint).focusable().onMoveCommand(perform:moveSelectedPoint)
            .accessibilityLabel(L(AppDistribution.isAppStore ? "温度曲线":"可拖动的温度风扇转速曲线"))
            .help(L(AppDistribution.isAppStore ? AppDistribution.monitoringOnlyMessage:"拖动控制点调节温度和转速；方向键微调选中点。"))

    }
    private func moveSelectedPoint(_ direction:MoveCommandDirection) {
        guard !busy,available,curve.points.indices.contains(selectedPoint) else{return}
        let point=curve.points[selectedPoint]
        switch direction {
        case .left:setPoint(selectedPoint,temperature:point.temperature-0.1,percent:point.percent)
        case .right:setPoint(selectedPoint,temperature:point.temperature+0.1,percent:point.percent)
        case .up:setPoint(selectedPoint,temperature:point.temperature,percent:point.percent+1)
        case .down:setPoint(selectedPoint,temperature:point.temperature,percent:point.percent-1)
        @unknown default:return
        }
        onApply()
    }

    func setPoint(_ index:Int,temperature:Double,percent:Double) {
        // Reversing an endpoint drag restores the original shape below its new
        // ceiling instead of leaving points flattened by an earlier pointer move.
        var edited=dragging==curve.points.count-1 ? (original ?? curve):curve
        edited.movePoint(index,temperature:temperature,percent:percent)
        curve=edited
    }
}
