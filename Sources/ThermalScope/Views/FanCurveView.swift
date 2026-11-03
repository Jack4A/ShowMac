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
    func rpm(_ percent:Double)->Double {CurvePolicy.rpm(percent:percent,minimum:minimum,maximum:maximum)}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(L("温度曲线")+" · RPM").font(AppTypography.section)
                Spacer()
                Picker(L("温度来源"),selection:Binding(get:{curve.sensor},set:{curve.sensor=$0;onApply()})) {
                    Text(L("自动选择温度")).tag(CurveSensor.hottest)
                    Text("CPU").tag(CurveSensor.cpu)
                    Text("GPU").tag(CurveSensor.gpu).disabled(sample?.temperature(.gpu)==nil)
                }.labelsHidden().frame(width:160).disabled(busy || !available)
            }
            curveChart.frame(height:260)
            HStack {
                Text(L(AppDistribution.isAppStore ? "温度与风扇读数实时更新":(automatic ? "拖动曲线，启用自定义调速":"拖动控制点，松手即生效"))).font(.system(size:12)).foregroundColor(Palette.secondaryText)
                Spacer(minLength:8)
                if let index=dragging,curve.points.indices.contains(index) {
                    Text(String(format:"%.0f°C → %.0f RPM",curve.points[index].temperature,rpm(curve.points[index].percent))).font(.system(size:12,weight:.medium)).appMonospacedDigit()
                }
            }
            if !available && !AppDistribution.isAppStore {Text(L("风扇或温度读数不可用，暂不能调速。")).font(.system(size:12)).foregroundColor(.orange)}
        }.subtlePanel()
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
            .accessibilityLabel(L("可拖动的温度风扇转速曲线"))
            .help(L("拖动控制点调节温度和转速；方向键微调选中点。"))

    }
    private func moveSelectedPoint(_ direction:MoveCommandDirection) {
        guard !busy,available,curve.points.indices.contains(selectedPoint) else{return}
        let point=curve.points[selectedPoint]
        switch direction {
        case .left:setPoint(selectedPoint,temperature:point.temperature-2,percent:point.percent)
        case .right:setPoint(selectedPoint,temperature:point.temperature+2,percent:point.percent)
        case .up:setPoint(selectedPoint,temperature:point.temperature,percent:point.percent+5)
        case .down:setPoint(selectedPoint,temperature:point.temperature,percent:point.percent-5)
        @unknown default:return
        }
        onApply()
    }

    func setPoint(_ index:Int,temperature:Double,percent:Double) {
        guard curve.points.indices.contains(index),temperature.isFinite,percent.isFinite else{return}
        let points=curve.points,last=index==points.count-1
        let lowT=index>0 ? points[index-1].temperature+2:30
        let highT=last ? 90:points[index+1].temperature-2
        let lowP=index>0 ? points[index-1].percent:0
        let highP=last ? 100:points[index+1].percent
        curve.points[index]=CurvePoint(min(highT,max(lowT,temperature.rounded())),last ? 100:min(highP,max(lowP,percent.rounded())))
    }
}
