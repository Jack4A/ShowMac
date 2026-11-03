import SwiftUI
import AppKit
import ThermalCore

enum MenuMetric:String,CaseIterable,Identifiable,Codable {
    case cpu,temperature,gpu,battery,fan
    var id:String { rawValue }
    var title:String {switch self {case .cpu:return L("CPU 使用率");case .temperature:return L("CPU 温度");case .gpu:return L("GPU 温度");case .battery:return L("电池电量");case .fan:return L("风扇转速")}}
    var symbol:String {switch self {case .cpu:return "cpu";case .temperature:return "thermometer.medium";case .gpu:return "display";case .battery:return "battery.75percent";case .fan:return "fanblades"}}
    var shortTitle:String {switch self {case .cpu:return "CPU";case .temperature:return L("温度");case .gpu:return "GPU";case .battery:return L("电池");case .fan:return L("风扇")}}
    @MainActor func value(_ readings:LiveReadings)->String {
        switch self {
        case .cpu:return valueText(readings.snapshot?.cpuUsage)+"%"
        case .temperature:return valueText(readings.snapshot?.cpuTemperature)+"°"
        case .gpu:return valueText(readings.snapshot?.temperature(.gpu))+"°"
        case .battery:return valueText(readings.telemetry?.batteryPercent)+"%"
        case .fan:return valueText(readings.snapshot?.fans.compactMap(\.rpm).max())
        }
    }
    @MainActor func value(_ model:AppModel)->String {value(model.readings)+(self == .fan ? " rpm":"")}
}

struct MenuSettings:View {
    @ObservedObject var model:AppModel
    @State private var editing:MenuBarComponent?
    @State private var showAppearance=false
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            if model.menuStyle == "custom" {
                MenuCompositionCanvas(model:model,onEdit:{editing=$0})
            } else {
                VStack(alignment:.leading,spacing:14) {
                    Text(L("状态栏定制")).font(AppTypography.section)
                    MenuLivePreview(readings:model.readings,items:model.menuItems,style:model.menuStyle)
                    Text(L("当前使用兼容布局，可切换为逐项定制。")).font(AppTypography.body)
                    Button(L("启用逐项定制")){enableCustomization()}.buttonStyle(AppNativeButtonStyle())
                }
                .subtlePanel(padding:18)
            }
            StatusCardEditor(model:model,embedded:true).subtlePanel(padding:18)
            if model.menuStyle == "custom" {
                DisclosureGroup(L("字体与外观"),isExpanded:$showAppearance) {
                    VStack(alignment:.leading,spacing:18) {
                        MenuFontControls(model:model)
                        Divider().opacity(0.45)
                        MenuAppearanceControls(model:model)
                    }.padding(.top,14)
                }.font(AppTypography.body).subtlePanel(padding:18)
            }
        }.sheet(item:$editing) {component in
            MenuTileEditor(model:model,componentID:component.id,metric:component.metric,onClose:{editing=nil})
                .preferredColorScheme(model.colorScheme)
        }
    }
    func enableCustomization() {
        let legacy=model.menuStyle
        for metric in model.menuItems {
            let style:MenuTileStyle=legacy=="icons" ? .icon:(legacy=="both" ? .iconValue:(legacy=="values" ? .value:.stacked))
            model.menuTileStyles[metric.rawValue]=style.rawValue
        }
        model.menuStyle="custom"
    }
}
