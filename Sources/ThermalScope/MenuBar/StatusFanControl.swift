import SwiftUI
import ThermalCore

/// A single mode selector replaces the competing scene/preset selection rows.
struct StatusFanControl:View {
    @ObservedObject var model:AppModel
    @ObservedObject var readings:LiveReadings
    @ObservedObject var control:FanControlReadings
    let onManage:()->Void
    init(model:AppModel,onManage:@escaping()->Void) {self.model=model;readings=model.readings;control=model.fanControl;self.onManage=onManage}
    private var selection:FanModeSelection? {
        if let scene=model.activeFanScene {return .scene(scene.id)}
        return model.activeFanStrategy.map{.strategy($0)}
    }
    private var choices:[AppChoice<FanModeSelection?>] {
        if !ControlAvailability.fansAvailable(readings.snapshot) {return [AppChoice(Optional(.strategy(.system)),L("系统自动"))]}
        return FanStrategy.allCases.map{AppChoice(Optional(FanModeSelection.strategy($0)),L($0.shortTitle),symbol:$0 == .system ? "arrow.triangle.2.circlepath":"fanblades")} +
            model.fanScenes.scenes.map{AppChoice(Optional(FanModeSelection.scene($0.id)),L($0.name),symbol:FanSceneArtwork.symbol($0))}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:6) {
                Image(systemName:AppSymbols.resolve("fanblades")).foregroundColor(Palette.violet)
                Text(L("风扇控制")).font(.system(size:12,weight:.semibold))
                Spacer()
                if model.busy {ProgressView().appControlSize(.mini)}
                else {
                    Text((readings.snapshot?.fans.map{valueText($0.rpm)}.joined(separator:" / ") ?? "—")+" RPM")
                        .font(.system(size:11)).appMonospacedDigit().foregroundColor(Palette.secondaryText)
                }
            }
            if AppDistribution.isAppStore {
                Text(L(AppDistribution.monitoringOnlyMessage)).font(.system(size:11)).foregroundColor(Palette.secondaryText)
            } else {
                HStack(spacing:7) {
                    AppChoicePicker(title:L("风扇模式"),selection:Binding(get:{selection},set:{value in
                        switch value {case .strategy(let strategy):model.applyFanStrategy(strategy);case .scene(let id):model.applyFanScene(id);case nil:break}
                    }),choices:choices,placeholder:L("状态未知"),labelWidth:104,listWidth:250,maximumListHeight:320)
                        .accessibilityIdentifier("statusFanMode")
                    Spacer(minLength:0)
                    FanStopTimerButton(model:model)
                    Button(action:onManage) {Image(systemName:AppSymbols.resolve("slider.horizontal.3"))}
                        .buttonStyle(.plain).foregroundColor(Palette.secondaryText).frame(width:23,height:28)
                        .help(L("场景与应用")).accessibilityLabel(L("场景与应用")).accessibilityIdentifier("fanSceneSettings")
                }.disabled(model.busy)
                HStack(spacing:8) {
                    Toggle(L("按应用切换"),isOn:Binding(get:{model.fanAutomation.enabled},set:{model.setFanAutomationEnabled($0)}))
                        .toggleStyle(.switch).appControlSize(.mini).font(.system(size:11)).accentColor(Palette.violet)
                        .disabled(model.busy || (model.fanAutomation.rules.isEmpty && !model.fanAutomation.enabled))
                        .help(L("在场景与应用设置中关联应用；手动选档会暂停自动切换。"))
                        .accessibilityIdentifier("statusFanAutomation")
                    Spacer(minLength:0)
                    Text(model.fanAutomation.enabled ? (model.fanAutomationApplication?.name ?? L("未匹配应用")):L("手动选择"))
                        .font(.system(size:10)).foregroundColor(Palette.secondaryText).lineLimit(1)
                }
            }
            if control.status?.protectionActive==true || model.systemFanHeatWarning {
                Label(L(control.status?.protectionActive==true ? "高温保护中":"温度较高，系统风扇仍接近最低转速"),systemImage:AppSymbols.resolve("exclamationmark.triangle"))
                    .font(.system(size:10)).foregroundColor(.orange).fixedSize(horizontal:false,vertical:true)
            }
        }.padding(12).modifier(StatusCardSurface())
    }
}
