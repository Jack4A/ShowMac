import SwiftUI
import AppKit
import ThermalCore

enum MenuMetric:String,CaseIterable,Identifiable,Codable {
    case cpu,temperature,gpu,battery,fan,tokens,tokenQuota
    var id:String { rawValue }
    var title:String {switch self {case .cpu:return L("CPU 使用率");case .temperature:return L("CPU 温度");case .gpu:return L("GPU 温度");case .battery:return L("电池电量");case .fan:return L("风扇转速");case .tokens:return L("Token 用量");case .tokenQuota:return L("额度余量")}}
    var symbol:String {switch self {case .cpu:return "cpu";case .temperature:return "thermometer.medium";case .gpu:return "display";case .battery:return "battery.75percent";case .fan:return "fanblades";case .tokens:return "number.circle";case .tokenQuota:return "chart.pie"}}
    var shortTitle:String {switch self {case .cpu:return "CPU";case .temperature:return L("温度");case .gpu:return "GPU";case .battery:return L("电池");case .fan:return L("风扇");case .tokens:return "Token";case .tokenQuota:return L("余量")}}
    @MainActor func value(_ readings:LiveReadings)->String {
        switch self {
        case .cpu:return valueText(readings.snapshot?.cpuUsage)+"%"
        case .temperature:return valueText(readings.snapshot?.cpuTemperature)+"°"
        case .gpu:return valueText(readings.snapshot?.temperature(.gpu))+"°"
        case .battery:return valueText(readings.telemetry?.batteryPercent)+"%"
        case .fan:return valueText(readings.snapshot?.fans.compactMap(\.rpm).max())
        case .tokens,.tokenQuota:return "—"
        }
    }
    @MainActor func value(_ model:AppModel)->String {isToken ? model.tokenMenuReading(metric:self).text:value(model.readings)+(self == .fan ? " rpm":"")}
}

struct MenuSettings:View {
    @ObservedObject var model:AppModel
    @ObservedObject private var navigation:DiagnosticNavigation
    private enum Editor {case components,cards,appearance}
    @State private var editing:MenuBarComponent?
    @State private var expanded:Editor?
    init(model:AppModel){self.model=model;self.navigation=model.navigation}
    private func selection(_ editor:Editor)->Binding<Bool> {
        Binding(get:{expanded==editor},set:{expanded=$0 ? editor:nil})
    }
    private var divider:some View {Divider().opacity(0.5).padding(.horizontal,16)}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            AppDisclosureGroup(isExpanded:selection(.components),inset:8) {
                if model.menuStyle == "custom" {
                    MenuCompositionCanvas(model:model,embedded:true,onEdit:{editing=$0}).padding(.top,4)
                } else {
                    VStack(alignment:.leading,spacing:14) {
                        MenuLivePreview(readings:model.readings,items:model.menuItems,style:model.menuStyle)
                        Button(L("启用逐项定制")){enableCustomization()}.buttonStyle(AppNativeButtonStyle())
                    }.padding(.top,6)
                }
            } label:{
                rowLabel("菜单栏组件",summary:String(format:L("%d 项"),model.effectiveMenuComponents.count))
            }.accessibilityIdentifier("settingsMenuComponents")
            divider
            AppDisclosureGroup(isExpanded:selection(.cards),inset:8) {
                StatusCardEditor(model:model,embedded:true,showsHeading:false).padding(.top,4)
            } label:{rowLabel("弹窗卡片",summary:String(format:L("%d 张卡片"),model.statusPanel.cards.count))}
                .accessibilityIdentifier("settingsStatusCards")
            if model.menuStyle == "custom" {
                divider
                AppDisclosureGroup(isExpanded:selection(.appearance),inset:8) {
                    VStack(alignment:.leading,spacing:16) {
                        MenuFontControls(model:model)
                        Divider().opacity(0.45)
                        MenuAppearanceControls(model:model)
                    }.padding(.top,8)
                } label:{rowLabel("字体与间距",summary:String(format:"%g pt",model.menuTypography.size))}
                    .accessibilityIdentifier("settingsMenuAppearance")
            }
        }.sheet(item:$editing) {component in
            MenuTileEditor(model:model,componentID:component.id,metric:component.metric,onClose:{editing=nil})
                .preferredColorScheme(model.colorScheme)
        }
        .onReceive(navigation.$preferencesSection){if $0 == .menubar {expanded = .components}}
    }
    private func rowLabel(_ title:String,summary:String)->some View {
        HStack(spacing:12) {
            Text(L(title)).font(AppTypography.body)
            Spacer(minLength:4)
            Text(summary).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
        }.padding(.trailing,4)
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
