import SwiftUI
import ThermalCore

func valueText(_ value:Double?,_ format:String="%.0f")->String { value.map { String(format:format,$0) } ?? "—" }

struct PreferencesPage:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            VStack(spacing:0) {
                preferenceRow("界面语言","globe",detail:"立即切换，无需重启。") {
                    Picker(L("界面语言"),selection:$model.language) {
                        ForEach(AppLanguage.allCases) {language in Text(language.title).tag(language.rawValue)}
                    }.labelsHidden().frame(width:200,alignment:.trailing)
                }
                Divider().opacity(0.45).padding(.leading,36)
                preferenceRow("主题","paintpalette",detail:nil) {
                    Picker(L("主题"),selection:$model.theme) {
                        Text(L("跟随系统")).tag("system")
                        Text(L("浅色")).tag("light")
                        Text(L("深色")).tag("dark")
                    }.labelsHidden().pickerStyle(.segmented).tint(Palette.action).frame(width:270)
                }
                Divider().opacity(0.45).padding(.leading,36)
                preferenceRow("采样频率","timer",detail:"较低频率可减少唤醒。") {
                    Picker(L("采样频率"),selection:$model.interval) {Text(L("2 秒")).tag(2.0);Text(L("5 秒")).tag(5.0)}.labelsHidden().pickerStyle(.segmented).tint(Palette.action).frame(width:145)
                }
            }.padding(.horizontal,18).padding(.vertical,3).subtlePanel()
            MenuSettings(model:model)
            WidgetSettings(model:model)
            HStack(alignment:.top,spacing:10) {
                Image(systemName:model.authorizationReady ? "lock.open.fill":"lock.shield").foregroundStyle(Palette.violet)
                VStack(alignment:.leading,spacing:5) {
                    Text(model.authorizationReady ? L("原生控制会话已授权 · 本次运行无需重复授权"):L("首次硬件控制需要系统授权 · 本次运行内复用连接")).font(.system(size:11))
                    Text(L("所有监测数据保留在本机")).font(.system(size:10)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal,4).padding(.top,3)
        }
    }
    func preferenceRow<Content:View>(_ title:String,_ symbol:String,detail:String?,@ViewBuilder content:()->Content)->some View {
        HStack(spacing:12) {
            Image(systemName:symbol).font(.system(size:15)).foregroundStyle(Palette.violet).frame(width:24)
            VStack(alignment:.leading,spacing:4) {
                Text(L(title)).font(.system(size:12,weight:.medium))
                if let detail {Text(L(detail)).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
            }
            Spacer(minLength:16)
            content()
        }.padding(.vertical,13)
    }
}
