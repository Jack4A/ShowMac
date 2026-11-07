import AppKit
import SwiftUI
import ThermalCore

func valueText(_ value:Double?,_ format:String="%.0f")->String { value.map { String(format:format,$0) } ?? "—" }

struct PreferencesPage:View {
    @ObservedObject var model:AppModel
    @ObservedObject var navigation:DiagnosticNavigation
    @State private var showWidgets=false
    init(model:AppModel){self.model=model;self.navigation=model.navigation}
    var body:some View {
        VStack(alignment:.leading,spacing:24) {
            VStack(alignment:.leading,spacing:12) {
                settingsHeading("通用",detail:"启动、外观与采样")
                VStack(spacing:10) {
                    LoginItemSettings(login:model.loginItem)
                    Divider()
                    preferenceRow("主题",detail:nil) {
                        AppChoicePicker(title:L("主题"),selection:$model.theme,
                                        choices:[AppChoice("system",L("跟随系统")),AppChoice("light",L("浅色")),AppChoice("dark",L("深色"))])
                            .frame(width:180,alignment:.trailing)
                            .accessibilityIdentifier("appTheme")
                    }
                    Divider()
                    preferenceRow("界面语言",detail:nil) {
                        AppChoicePicker(title:L("界面语言"),selection:$model.language,
                                        choices:AppLanguage.allCases.map{AppChoice($0.rawValue,$0.title)})
                            .frame(width:180,alignment:.trailing)
                    }
                    Divider()
                    preferenceRow("采样频率",detail:nil) {
                        HStack(spacing:10) {
                            AppChoicePicker(title:L("采样频率"),selection:$model.interval,
                                            choices:[AppChoice(2.0,L("2 秒")),AppChoice(5.0,L("5 秒"))])
                                .frame(width:82)
                            Button {model.refresh()} label:{Label(L("刷新读数"),systemImage:AppSymbols.resolve("arrow.clockwise"))}
                                .buttonStyle(AppNativeButtonStyle()).disabled(model.busy)
                        }
                    }
                }.subtlePanel(padding:18)
            }.id(PreferencesSection.general)
            MenuSettings(model:model).id(PreferencesSection.menubar)
            if !AppDistribution.isAppStore {
                VStack(alignment:.leading,spacing:12) {
                    settingsHeading("硬件控制",detail:"仅在主动开启时改变系统行为")
                    ClamshellModeSettings(mode:model.clamshell,busy:model.busy)
                }
            }
            AppDisclosureGroup(L("系统小组件"),isExpanded:$showWidgets,inset:18) {
                WidgetSettings(model:model).padding(.top,10)
            }.font(AppTypography.body).subtlePanel(padding:0).id(PreferencesSection.widgets)
                .onReceive(navigation.$preferencesSection){if $0 == .widgets {showWidgets=true}}
            aboutSection
        }
    }
    private func settingsHeading(_ title:String,detail:String)->some View {
        HStack(alignment:.firstTextBaseline,spacing:12) {
            Text(L(title)).font(AppTypography.section)
            Text(L(detail)).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            Spacer(minLength:0)
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
