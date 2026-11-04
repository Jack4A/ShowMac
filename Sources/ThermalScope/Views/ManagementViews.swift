import AppKit
import SwiftUI
import ThermalCore

func valueText(_ value:Double?,_ format:String="%.0f")->String { value.map { String(format:format,$0) } ?? "—" }

struct PreferencesPage:View {
    @ObservedObject var model:AppModel
    @State private var showWidgets=false
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            aboutSection
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
                        Button {model.refresh()} label:{Label(L("刷新读数"),systemImage:AppSymbols.resolve("arrow.clockwise"))}
                            .buttonStyle(AppNativeButtonStyle()).disabled(model.busy)
                    }
                }
            }.subtlePanel(padding:18)
            DisclosureGroup(L("系统小组件"),isExpanded:$showWidgets) {
                WidgetSettings(model:model).padding(.top,10)
            }.font(AppTypography.body).subtlePanel(padding:18)
        }
    }
    private var aboutSection:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:10) {
                if let icon=AppInfo.icon {
                    Image(nsImage:icon).resizable().aspectRatio(contentMode:.fit)
                        .frame(width:44,height:44).accessibilityHidden(true)
                }
                VStack(alignment:.leading,spacing:4) {
                    Text(L("关于ShowMac")).font(AppTypography.body.weight(.semibold))
                    Text(L("版本")+" "+AppInfo.versionLabel).font(.caption).foregroundColor(Palette.secondaryText)
                }
                Spacer()
                Link("GitHub",destination:AppInfo.repositoryURL)
                    .buttonStyle(AppNativeButtonStyle()).appControlSize(.small)
            }
            Divider()
            HStack(spacing:6) {
                Text(L("开发者")).foregroundColor(Palette.secondaryText)
                Link("@"+AppInfo.developer,destination:AppInfo.developerURL)
                Spacer(minLength:12)
                Text(L("免费开源 · MIT 许可证")).font(.caption).foregroundColor(Palette.secondaryText)
            }.font(.system(size:12))
            Divider()
            AppUpdateSettings(updates:model.updates)
        }.subtlePanel(padding:18)
            .accessibilityElement(children:.contain)
            .accessibilityLabel(L("关于ShowMac"))
            .accessibilityIdentifier("settingsAbout")
    }
    func preferenceRow<Content:View>(_ title:String,detail:String?,@ViewBuilder content:()->Content)->some View {
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:4) {
                Text(L(title)).font(AppTypography.body)
                if let detail {Text(L(detail)).font(.system(size:12)).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)}
            }
            Spacer(minLength:16)
            content()
        }.padding(.vertical,5)
    }
}
