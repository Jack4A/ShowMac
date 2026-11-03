import SwiftUI
import ThermalCore

func valueText(_ value:Double?,_ format:String="%.0f")->String { value.map { String(format:format,$0) } ?? "—" }

struct PreferencesPage:View {
    @ObservedObject var model:AppModel
    @State private var showWidgets=false
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            MenuSettings(model:model)
            VStack(spacing:10) {
                preferenceRow("主题",detail:nil) {
                    Picker(L("主题"),selection:$model.theme) {
                        Text(L("跟随系统")).tag("system")
                        Text(L("浅色")).tag("light")
                        Text(L("深色")).tag("dark")
                    }.labelsHidden().frame(width:200,alignment:.trailing)
                        .accessibilityIdentifier("appTheme")
                }
                Divider()
                preferenceRow("界面语言",detail:nil) {
                    Picker(L("界面语言"),selection:$model.language) {
                        ForEach(AppLanguage.allCases) {language in Text(language.title).tag(language.rawValue)}
                    }.labelsHidden().frame(width:200,alignment:.trailing)
                }
                Divider()
                preferenceRow("采样频率",detail:nil) {
                    HStack(spacing:10) {
                        Picker(L("采样频率"),selection:$model.interval) {
                            Text(L("2 秒")).tag(2.0);Text(L("5 秒")).tag(5.0)
                        }.labelsHidden().frame(width:90,alignment:.trailing)
                        Button {model.refresh()} label:{Label(L("刷新读数"),systemImage:"arrow.clockwise")}
                            .buttonStyle(.bordered).disabled(model.busy)
                    }
                }
            }.subtlePanel(padding:18)
            DisclosureGroup(L("系统小组件"),isExpanded:$showWidgets) {
                WidgetSettings(model:model).padding(.top,10)
            }.font(AppTypography.body).subtlePanel(padding:18)
        }
    }
    func preferenceRow<Content:View>(_ title:String,detail:String?,@ViewBuilder content:()->Content)->some View {
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:4) {
                Text(L(title)).font(AppTypography.body)
                if let detail {Text(L(detail)).font(.system(size:12)).foregroundStyle(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)}
            }
            Spacer(minLength:16)
            content()
        }.padding(.vertical,5)
    }
}
