import SwiftUI
import ThermalCore

struct ClamshellModeSettings:View {
    @ObservedObject var mode:ClamshellModeModel
    let busy:Bool
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:12) {
                Image(systemName:AppSymbols.resolve("laptopcomputer"))
                    .font(.system(size:20)).foregroundColor(Palette.violet).frame(width:30)
                VStack(alignment:.leading,spacing:4) {
                    Text(L("合盖运行")).font(AppTypography.body.weight(.semibold))
                    Text(L("像台式机一样，合盖后继续运行任务。")).font(.caption).foregroundColor(Palette.secondaryText)
                }
                Spacer(minLength:8)
                if mode.changing {ProgressView().appControlSize(.small)}
                Toggle(L("合盖运行"),isOn:Binding(get:{mode.status.active},set:{mode.setEnabled($0)}))
                    .labelsHidden().toggleStyle(.switch).accentColor(Palette.violet)
                    .disabled(busy || mode.changing || (!mode.status.active && !mode.canEnable))
                    .help(L("开启期间阻止系统休眠，屏幕仍可熄灭。"))
                    .accessibilityIdentifier("settingsClamshellMode")
            }
            Text(L(mode.detail)).font(.caption)
                .foregroundColor(mode.status.failed ? Color.orange:Palette.secondaryText)
                .fixedSize(horizontal:false,vertical:true)
            Text(L("仅接电时生效；拔电、关闭开关或退出 ShowMac 后恢复休眠。请保持通风，放入包前关闭。"))
                .font(.caption).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
        }.subtlePanel(padding:18)
    }
}

struct ClamshellStatusButton:View {
    @ObservedObject var mode:ClamshellModeModel
    let busy:Bool
    var body:some View {
        if mode.environment?.portable==true {
            Button {mode.setEnabled(!mode.status.active)} label:{
                Image(systemName:AppSymbols.resolve("laptopcomputer"))
                    .foregroundColor(mode.status.active ? Palette.violet:Palette.secondaryText)
            }
            .help(L("合盖运行")+" · "+L(mode.detail))
            .accessibilityLabel(L("合盖运行")+" · "+L(mode.status.active ? "已开启":"已关闭"))
            .accessibilityIdentifier("statusClamshellMode")
            .disabled(busy || mode.changing || (!mode.status.active && !mode.canEnable))
        }
    }
}
