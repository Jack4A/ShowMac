import AppKit
import SwiftUI
import ThermalCore

func valueText(_ value:Double?,_ format:String="%.0f")->String { value.map { String(format:format,$0) } ?? "—" }

struct PreferencesPage:View {
    @ObservedObject var model:AppModel
    init(model:AppModel){self.model=model}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            settingsGroup("通用") {
                LoginItemSettings(login:model.loginItem)
                rowDivider
                preferenceRow("主题") {
                    AppChoicePicker(title:L("主题"),selection:$model.theme,
                                    choices:[AppChoice("system",L("跟随系统")),AppChoice("light",L("浅色")),AppChoice("dark",L("深色"))])
                        .frame(width:160,alignment:.trailing)
                        .accessibilityIdentifier("appTheme")
                }
                rowDivider
                preferenceRow("界面语言") {
                    AppChoicePicker(title:L("界面语言"),selection:$model.language,
                                    choices:AppLanguage.allCases.map{AppChoice($0.rawValue,$0.title)})
                        .frame(width:160,alignment:.trailing)
                }
                rowDivider
                preferenceRow("采样频率") {
                    HStack(spacing:10) {
                        AppChoicePicker(title:L("采样频率"),selection:$model.interval,
                                        choices:[AppChoice(2.0,L("2 秒")),AppChoice(5.0,L("5 秒"))])
                            .frame(width:100,alignment:.trailing)
                        Button {model.refresh()} label:{Image(systemName:AppSymbols.resolve("arrow.clockwise"))}
                            .buttonStyle(AppNativeButtonStyle()).disabled(model.busy)
                            .help(L("刷新读数")).accessibilityLabel(L("刷新读数"))
                    }.frame(width:160,alignment:.trailing)
                }
            }.id(PreferencesSection.general)
            settingsGroup("状态栏") {
                MenuSettings(model:model)
            }.id(PreferencesSection.menubar)
            settingsGroup("功能") {
                if !AppDistribution.isAppStore {
                    ClamshellModeSettings(mode:model.clamshell,busy:model.busy,embedded:true)
                        .padding(.horizontal,16).frame(minHeight:38)
                    rowDivider
                }
                WidgetSettings(model:model).padding(.horizontal,16).frame(minHeight:38).id(PreferencesSection.widgets)
            }
            aboutSection
        }.appControlSize(.small)
    }
    private var rowDivider:some View {Divider().opacity(0.5).padding(.horizontal,16)}
    private func settingsGroup<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:8) {
            Text(L(title)).font(.system(size:12,weight:.semibold)).foregroundColor(Palette.secondaryText).padding(.leading,2)
            VStack(spacing:0,content:content).subtlePanel(padding:0)
        }
    }
    private var aboutSection:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:10) {
                if let icon=AppInfo.icon {
                    Image(nsImage:icon).resizable().aspectRatio(contentMode:.fit)
                        .frame(width:32,height:32).accessibilityHidden(true)
                }
                VStack(alignment:.leading,spacing:4) {
                    HStack(spacing:8) {
                        Text("ShowMac").font(AppTypography.body.weight(.semibold))
                        Text(AppInfo.versionLabel).font(.caption).foregroundColor(Palette.secondaryText)
                    }
                    HStack(spacing:8) {
                        Link("@"+AppInfo.developer,destination:AppInfo.developerURL).help(L("开发者"))
                        Text("MIT").foregroundColor(Palette.secondaryText).help(L("免费开源 · MIT 许可证"))
                    }.font(.caption)
                }
                Spacer()
                Link("GitHub",destination:AppInfo.repositoryURL)
                    .buttonStyle(AppNativeButtonStyle()).appControlSize(.small)
            }
            Divider()
            AppUpdateSettings(updates:model.updates)
        }.subtlePanel(padding:14)
            .accessibilityElement(children:.contain)
            .accessibilityLabel(L("关于ShowMac"))
            .accessibilityIdentifier("settingsAbout")
    }
    func preferenceRow<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        HStack(spacing:12) {
            Text(L(title)).font(AppTypography.body)
            Spacer(minLength:16)
            content()
        }.padding(.horizontal,16).frame(minHeight:38)
    }
}
