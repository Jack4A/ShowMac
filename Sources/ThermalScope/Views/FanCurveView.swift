import SwiftUI
import Charts
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
                Text(L(automatic ? "拖动曲线，启用自定义调速":"拖动控制点，松手即生效")).font(.system(size:12)).foregroundStyle(Palette.secondaryText)
                Spacer(minLength:8)
                if let index=dragging,curve.points.indices.contains(index) {
                    Text(String(format:"%.0f°C → %.0f RPM",curve.points[index].temperature,rpm(curve.points[index].percent))).font(.system(size:12,weight:.medium)).monospacedDigit()
                }
            }
            if !available {Text(L("风扇或温度读数不可用，暂不能调速。")).font(.system(size:12)).foregroundStyle(.orange)}
        }.subtlePanel()
    }
    var curveChart:some View {
        Chart {
            ForEach(Array(curve.points.enumerated()),id:\.offset) {index,point in
                LineMark(x:.value(L("温度"),point.temperature),y:.value("RPM",rpm(point.percent)))
                    .foregroundStyle(Palette.violet.opacity(automatic ? 0.4:1)).lineStyle(StrokeStyle(lineWidth:2.5,lineCap:.round)).interpolationMethod(.linear)
                PointMark(x:.value(L("温度"),point.temperature),y:.value("RPM",rpm(point.percent)))
                    .foregroundStyle(Palette.violet.opacity(automatic ? 0.6:1)).symbolSize(dragging==index ? 120:70)
                    .annotation(position:.top) {if dragging==index {Text(String(format:"%.0f°C · %.0f RPM",point.temperature,rpm(point.percent))).font(.system(size:12)).foregroundStyle(Palette.secondaryText)}}
            }
            if let sample,let temperature=curve.sensor.temperature(in:sample) {
                RuleMark(x:.value(L("当前温度"),temperature)).foregroundStyle(.primary.opacity(0.2)).lineStyle(StrokeStyle(lineWidth:1,dash:[4,4]))
            }
        }.chartXScale(domain:30...100).chartYScale(domain:minimum...(maximum+(maximum-minimum)*0.12))
            .chartXAxis {AxisMarks(values:[30,40,50,60,70,80,90,100]) {value in
                AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                AxisValueLabel {if let number=value.as(Int.self) {Text("\(number)°C").foregroundStyle(Palette.secondaryText)}}
            }}
            .chartYAxis {AxisMarks(position:.leading,values:.automatic(desiredCount:4)) {value in
                AxisGridLine(stroke:StrokeStyle(lineWidth:0.5,dash:[3,4])).foregroundStyle(.primary.opacity(0.1))
                AxisValueLabel().foregroundStyle(Palette.secondaryText)
            }}
            .chartOverlay {proxy in GeometryReader {geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0).onChanged {value in
                        guard !busy,available else{return}
                        let frame=geometry[proxy.plotAreaFrame]
                        let location=CGPoint(x:value.location.x-frame.minX,y:value.location.y-frame.minY)
                        if dragging==nil {
                            let distances=curve.points.enumerated().compactMap {index,point -> (Int,Double)? in
                                guard let x=proxy.position(forX:point.temperature),let y=proxy.position(forY:rpm(point.percent)) else{return nil}
                                return (index,hypot(location.x-x,location.y-y))
                            }
                            if let nearest=distances.min(by:{$0.1<$1.1}),nearest.1<32 {dragging=nearest.0;selectedPoint=nearest.0;original=curve}
                        }
                        if let index=dragging,let temperature:Double=proxy.value(atX:location.x),let target:Double=proxy.value(atY:location.y) {
                            setPoint(index,temperature:temperature,percent:CurvePolicy.percent(rpm:target,minimum:minimum,maximum:maximum))
                        }
                    }.onEnded {_ in
                        let changed=original.map{$0 != curve} ?? false
                        dragging=nil;original=nil
                        if changed {onApply()}
                    })
            }}
            .focusable().onMoveCommand {direction in
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
            .accessibilityLabel(L("可拖动的温度风扇转速曲线"))
            .help(L("拖动控制点调节温度和转速；方向键微调选中点。"))
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
