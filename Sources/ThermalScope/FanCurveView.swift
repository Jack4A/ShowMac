import SwiftUI
import Charts
import ThermalCore

struct FanCurveEditor:View {
    @ObservedObject var model:AppModel
    @ObservedObject var readings:LiveReadings
    var compact=false
    var onShowChart:(()->Void)?
    @State private var dragging:Int?
    init(model:AppModel,compact:Bool=false,onShowChart:(()->Void)?=nil) {
        self.model=model;self.readings=model.readings;self.compact=compact;self.onShowChart=onShowChart
    }
    var curveStatus:String {
        if model.busy {return "正在应用，等待硬件确认…"}
        guard model.activeProfile == .custom,model.coolingToken != nil,let confirmed=model.sessionCurve else{return "曲线草稿"}
        return confirmed==model.customCurve ? "曲线已应用":"有未应用的修改"
    }
    var canApply:Bool {
        guard !model.busy,let sample=readings.snapshot,!sample.fans.isEmpty,let cpu=sample.cpuTemperature,cpu.isFinite,let temperature=model.customCurve.sensor.temperature(in:sample),temperature.isFinite else{return false}
        return (try? model.customCurve.validate()) != nil
    }
    var body:some View {
        if compact {entryCard} else {editorBody}
    }
    var editorBody:some View {
        VStack(alignment:.leading,spacing:12) {
            VStack(alignment:.leading,spacing:compact ? 8:18) {
                HStack {
                    VStack(alignment:.leading,spacing:5) {
                        Text(L(compact ? "风扇控制":"温度 → 风扇转速")).font(.title3.weight(.semibold))
                        Text(L(compact ? "温度变化时，风扇按曲线自动调整。":"拖动控制点绘制你的散热策略")).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment:.trailing,spacing:4) {
                        if compact {Text(L(model.coolingStatus)).font(.system(size:11,weight:.medium))}
                        Text(L(curveStatus)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment:.leading,spacing:7) {
                    guideStep(1,"选择性能、均衡或静音预设作为起点。")
                    guideStep(2,"拖动曲线控制点，或在下方输入温度与转速。")
                    guideStep(3,"检查草稿后点击应用；编辑本身不会改变风扇。")
                }.padding(12).background(Palette.violet.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
                HStack {
                    Text(L("跟随传感器")).font(.body).foregroundStyle(.secondary)
                    Picker(L("跟随传感器"),selection:$model.customCurve.sensor) {
                        ForEach(CurveSensor.allCases) { sensor in Text(L(sensor.rawValue)).tag(sensor) }
                    }.labelsHidden().frame(width:190)
                    Spacer()
                    Menu(L("载入预设")) {
                        Button(L("性能曲线")) { model.customCurve = .performance }
                        Button(L("均衡曲线")) { model.customCurve = .balanced }
                        Button(L("静音曲线")) { model.customCurve = .quiet }
                    }
                }.disabled(model.busy)
                if !compact {curveChart.frame(height:260).disabled(model.busy)}
                if let s=readings.snapshot,let cpu=s.cpuTemperature,cpu.isFinite,let t=model.customCurve.sensor.temperature(in:s),t.isFinite {
                    Text(String(format:L("曲线目标 %.1f°C → %.0f%%"),t,model.customCurve.percent(at:t))).font(.callout.monospaced()).foregroundStyle(Palette.violet)
                } else {
                    Text(L("控制温度读数不可用，暂不能应用曲线。")).font(.caption).foregroundStyle(.orange)
                }
                Divider().opacity(0.5)
                HStack {
                    Text(L("温度")).frame(width:110,alignment:.leading)
                    Text(L("风扇转速"))
                    Spacer()
                    if let onShowChart {Button(L("查看曲线图"),action:onShowChart).buttonStyle(.borderless)}
                }.font(.caption).foregroundStyle(.secondary)
                ForEach(model.customCurve.points.indices,id:\.self) { index in pointEditor(index).disabled(model.busy) }
                Text(L("两点之间按温度平滑插值；高温保护优先。")).font(.caption).foregroundStyle(.secondary)
                Text(L("0% 为额定最低转速，100% 为最高转速。")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(L("修改会保存；点击应用后才控制硬件。")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("恢复系统自动")) { model.restoreAuto() }.disabled(model.busy)
                    Button(L("应用曲线 · 30 分钟")) { model.applyCustomCurve() }.buttonStyle(.borderedProminent).tint(Palette.action).disabled(!canApply)
                }
            }.padding(20).subtlePanel()
            Label(L("高温保护优先于曲线；关键传感器失效、退出或会话到期会恢复系统自动。"),systemImage:"shield.lefthalf.filled")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
    var entryCard:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {Label(L("风扇控制"),systemImage:"fanblades").font(.title3.weight(.semibold));Spacer();Text(L(model.coolingStatus)).font(.body)}
            HStack(spacing:18) {
                Chart {ForEach(Array(model.customCurve.points.enumerated()),id:\.offset) {_,p in
                    AreaMark(x:.value(L("温度"),p.temperature),y:.value(L("风扇转速"),p.percent)).foregroundStyle(Palette.violet.opacity(0.12))
                    LineMark(x:.value(L("温度"),p.temperature),y:.value(L("风扇转速"),p.percent)).foregroundStyle(Palette.violet).lineStyle(StrokeStyle(lineWidth:2))
                }}.chartXScale(domain:30...100).chartYScale(domain:0...100).chartXAxis(.hidden).chartYAxis(.hidden).frame(width:110,height:65).accessibilityLabel(L("曲线草稿"))
                VStack(alignment:.leading,spacing:6) {
                    Text(L("根据温度自动调整转速")).font(.headline)
                    Text(L("设置温度与转速的对应关系，让散热跟随负载变化。")).font(.body).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Text(L(curveStatus)).font(.callout).foregroundStyle(Palette.violet)
                }
            }
            HStack {
                Button(L("恢复系统自动")){model.restoreAuto()}.disabled(model.busy)
                Spacer()
                Button{onShowChart?()}label:{Label(L("编辑温度曲线"),systemImage:"slider.horizontal.3")}.buttonStyle(.borderedProminent).tint(Palette.action).controlSize(.regular).disabled(model.busy)
            }
            Text(L("先编辑草稿，再点击应用；进入编辑不会改变当前风扇状态。")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(20).subtlePanel()
    }
    func guideStep(_ number:Int,_ text:String)->some View {
        HStack(alignment:.top,spacing:8){Text("\(number)").font(.caption.monospacedDigit()).frame(width:20,height:20).background(Palette.violet.opacity(0.12),in:Circle());Text(L(text)).font(.callout).fixedSize(horizontal:false,vertical:true)}
    }
    var curveChart:some View {
        Chart {
            ForEach(Array(model.customCurve.points.enumerated()),id:\.offset) { index,p in
                LineMark(x:.value(L("温度"),p.temperature),y:.value(L("转速范围"),p.percent)).foregroundStyle(Palette.violet).lineStyle(StrokeStyle(lineWidth:3)).interpolationMethod(.linear)
                PointMark(x:.value(L("温度"),p.temperature),y:.value(L("转速范围"),p.percent)).foregroundStyle(dragging==index ? Palette.violet:Palette.violet).symbolSize(dragging==index ? 100:60)
                    .annotation(position:.top) { Text("\(Int(p.temperature))° · \(Int(p.percent))%").font(.caption).foregroundStyle(.secondary) }
            }
            if let s=readings.snapshot,let t=model.customCurve.sensor.temperature(in:s),t.isFinite {
                RuleMark(x:.value(L("当前温度"),t)).foregroundStyle(Palette.violet.opacity(0.5)).lineStyle(StrokeStyle(lineWidth:1,dash:[4,4]))
            }
        }
        .chartXScale(domain:30...100).chartYScale(domain:0...110)
        .chartXAxis { AxisMarks(values:[30,40,50,60,70,80,90,100]) { value in AxisGridLine().foregroundStyle(.primary.opacity(0.06));AxisValueLabel { if let n=value.as(Int.self) { Text("\(n)°C").foregroundStyle(.primary.opacity(0.6)) } } } }
        .chartYAxis { AxisMarks(position:.leading,values:[0,25,50,75,100]) { value in AxisGridLine(stroke:StrokeStyle(lineWidth:0.5,dash:[3,4])).foregroundStyle(.primary.opacity(0.12));AxisValueLabel { if let n=value.as(Int.self) { Text("\(n)%").foregroundStyle(.primary.opacity(0.6)) } } } }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0).onChanged { value in
                        let frame=geometry[proxy.plotAreaFrame]
                        let point=CGPoint(x:value.location.x-frame.minX,y:value.location.y-frame.minY)
                        if dragging==nil {
                            let distances=model.customCurve.points.enumerated().compactMap { index,p -> (Int,Double)? in
                                guard let x=proxy.position(forX:p.temperature),let y=proxy.position(forY:p.percent) else { return nil }
                                return (index,hypot(point.x-x,point.y-y))
                            }
                            if let closest=distances.min(by:{$0.1<$1.1}),closest.1<32 { dragging=closest.0 }
                        }
                        if let index=dragging,let temperature:Double=proxy.value(atX:point.x),let percent:Double=proxy.value(atY:point.y) { setPoint(index,temperature:temperature,percent:percent) }
                    }.onEnded { _ in dragging=nil })
            }
        }.accessibilityLabel(L("可拖动的温度风扇转速曲线"))
    }
    func pointEditor(_ index:Int)->some View {
        HStack(spacing:12) {
            Text("\(index+1)").font(.caption.monospaced()).foregroundStyle(.tertiary).frame(width:20)
            TextField(L("温度"),value:Binding(get:{model.customCurve.points[index].temperature},set:{setPoint(index,temperature:$0,percent:model.customCurve.points[index].percent)}),format:.number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder).frame(width:55).accessibilityLabel(String(format:L("控制点 %d 温度"),index+1))
            Text("°C").font(.callout).foregroundStyle(.secondary)
            Image(systemName:"arrow.right").font(.system(size:9)).foregroundStyle(.tertiary)
            Slider(value:Binding(get:{model.customCurve.points[index].percent},set:{setPoint(index,temperature:model.customCurve.points[index].temperature,percent:$0)}),in:0...100,step:1)
                .disabled(index==model.customCurve.points.count-1).tint(Palette.violet).accessibilityLabel(String(format:L("控制点 %d 风扇转速"),index+1))
            TextField(L("风扇转速"),value:Binding(get:{model.customCurve.points[index].percent},set:{setPoint(index,temperature:model.customCurve.points[index].temperature,percent:$0)}),format:.number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder).frame(width:55).disabled(index==model.customCurve.points.count-1).accessibilityLabel(String(format:L("控制点 %d 转速百分比"),index+1))
            Text("%").font(.callout).foregroundStyle(.secondary)
            Image(systemName:"lock.fill").font(.system(size:9)).foregroundStyle(.tertiary).opacity(index==model.customCurve.points.count-1 ? 1:0).frame(width:12).accessibilityHidden(true)
        }
    }
    func setPoint(_ index:Int,temperature:Double,percent:Double) {
        guard model.customCurve.points.indices.contains(index),temperature.isFinite,percent.isFinite else { return }
        let points=model.customCurve.points,last=index==points.count-1
        let lowT=index>0 ? points[index-1].temperature+2:30
        let highT=last ? 90:points[index+1].temperature-2
        let lowP=index>0 ? points[index-1].percent:0
        let highP=last ? 100:points[index+1].percent
        model.customCurve.points[index]=CurvePoint(min(highT,max(lowT,temperature.rounded())),last ? 100:min(highP,max(lowP,percent.rounded())))
    }
}
