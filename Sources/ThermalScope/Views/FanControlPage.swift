import SwiftUI
import ThermalCore

struct FanControlPage:View {
    @ObservedObject var model:AppModel
    @ObservedObject var readings:LiveReadings
    @ObservedObject var control:FanControlReadings
    @ObservedObject var navigation:DiagnosticNavigation
    @State private var curve=FanCurve.balanced
    @State private var confirmTest=false
    @State private var manageScenes=false
    init(model:AppModel) {self.model=model;self.readings=model.readings;self.control=model.fanControl;self.navigation=model.navigation}
    var selected:FanStrategy? {
        if model.busy,let pending=model.pendingFanStrategy {return pending}
        return model.activeFanStrategy
    }
    var body:some View {
        ScrollView(showsIndicators:false) {
        VStack(alignment:.leading,spacing:16) {
            statusLine
            FanSceneControls(model:model,onManage:{manageScenes=true})
            FanStrategySelector(selected:selected,busy:model.busy,available:ControlAvailability.fansAvailable(readings.snapshot),onSelect:choose)
            if model.systemFanHeatWarning {
                Label(L("温度较高，风扇仍接近最低转速。当前由 macOS 控制，可选择“均衡”或“强劲”主动散热。"),systemImage:AppSymbols.resolve("exclamationmark.triangle"))
                    .font(.system(size:12)).foregroundColor(.orange).fixedSize(horizontal:false,vertical:true)
            }
            FanCurveEditor(curve:$curve,sample:readings.snapshot,automatic:selected == .system || selected==nil,busy:model.busy,onApply:applyCurve)
            HStack(alignment:.top,spacing:12) {
                Text(L(AppDistribution.isAppStore ? AppDistribution.monitoringOnlyMessage:model.fanControlSummary)).font(.system(size:12)).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:8)
                HStack(spacing:14) {
                    Button {navigation.page = .sensors} label:{Label(L("查看传感器"),systemImage:AppSymbols.resolve("sensor"))}
                        .buttonStyle(.borderless).font(.system(size:12))
                    Button(L("风扇测试…")){confirmTest=true}.buttonStyle(.borderless).font(.system(size:12)).disabled(model.busy || !ControlAvailability.fansAvailable(readings.snapshot))
                }.fixedSize()
            }
        }.consolePageContent().padding(.bottom,20)
        }.onAppear {
                curve=model.sessionCurve ?? model.customCurve
                if navigation.showFanTroubleshooting {confirmTest=true;navigation.showFanTroubleshooting=false}
                if navigation.showFanSceneManager {manageScenes=true;navigation.showFanSceneManager=false}
            }
            .sheet(isPresented:$manageScenes){FanSceneManager(model:model,curve:curve,onClose:{manageScenes=false})}
            .onChange(of:model.sessionCurve) {value in if let value {curve=value}}
            .onChange(of:model.busy) {busy in
                if !busy,!model.messageIsError {model.noticeVisible=false}
            }
            .onChange(of:navigation.showFanTroubleshooting) {show in
                if show {confirmTest=true;navigation.showFanTroubleshooting=false}
            }
            .onChange(of:navigation.showFanSceneManager) {show in
                if show {manageScenes=true;navigation.showFanSceneManager=false}
            }
            .alert(isPresented:$confirmTest) {
                Alert(title:Text(L("开始 5 秒满速测试？")),message:Text(L("风扇将短暂提高至最高目标转速，声音会变大；测试后恢复自动。")),primaryButton:.default(Text(L("开始测试"))){model.startFanTest()},secondaryButton:.cancel(Text(L("取消"))))
            }
    }
    var statusLine:some View {
        HStack(spacing:16) {
            if model.isFanControlPreview {Text(L("模拟")).font(.system(size:12)).foregroundColor(.orange).help(L("界面模拟 · 不会控制硬件"))}
            Label(valueText(readings.snapshot?.cpuTemperature)+"°C",systemImage:AppSymbols.resolve("thermometer.medium"))
            ForEach(readings.snapshot?.fans ?? []) {fan in
                Label(valueText(fan.rpm)+" RPM",systemImage:AppSymbols.resolve("fanblades")).help(String(format:L("风扇 %d"),fan.id+1))
            }
            Spacer(minLength:8)
            if model.busy {ProgressView().appControlSize(.small);Text(L("正在应用…"))}
            else if control.status?.protectionActive==true {Label(L("高温保护中"),systemImage:AppSymbols.resolve("shield.lefthalf.filled")).foregroundColor(.orange)}
            else if model.coolingToken != nil {
                AppTimelineView(interval:1) {_ in
                    if control.status?.continuous==true {Text(L("持续控制"))}
                    else if let seconds=control.remaining() {Text(seconds>0 ? String(format:L("剩余 %02d:%02d"),Int(ceil(seconds))/60,Int(ceil(seconds))%60):L("正在恢复自动…")).appMonospacedDigit()}
                    else {Text(L("控制中"))}
                }
            } else {Text(L(model.fanStrategyTitle))}
        }.font(.system(size:13)).foregroundColor(Palette.secondaryText)
    }
    func choose(_ strategy:FanStrategy) {
        guard !model.busy else{return}
        if strategy != .system,!ControlAvailability.fansAvailable(readings.snapshot) {return}
        if let preset=strategy.curve {curve=preset}
        else {curve=model.customCurve}
        model.applyFanStrategy(strategy)
    }
    func applyCurve() {
        guard !model.busy,ControlAvailability.fansAvailable(readings.snapshot),(try? curve.validate()) != nil else{return}
        model.applyEditedFanCurve(curve)
    }
}
