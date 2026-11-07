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
                Toggle(L("合盖运行"),isOn:Binding(get:{mode.isEnabled},set:{mode.setEnabled($0)}))
                    .labelsHidden().toggleStyle(.switch).accentColor(Palette.violet)
                    .disabled(busy || mode.changing || !mode.canSetEnabled)
                    .help(L("开启期间阻止系统休眠，屏幕仍可熄灭。"))
                    .accessibilityIdentifier("settingsClamshellMode")
            }
            Divider().opacity(0.5)
            HStack(spacing:12) {
                Text(L("开启条件")).font(AppTypography.body)
                Spacer(minLength:8)
                AppChoicePicker(title:L("开启条件"),selection:Binding(get:{mode.activation},set:{mode.setActivation($0)}),
                                choices:ClamshellActivation.allCases.map{AppChoice($0,L($0.title))})
                    .disabled(busy || mode.changing || !mode.canArmAutomatic)
                    .accessibilityIdentifier("clamshellActivation")
            }
            HStack(alignment:.top,spacing:10) {
                Text(L(mode.detail)).font(.caption)
                    .foregroundColor(mode.status.failed || mode.automaticIssue != nil ? Color.orange:Palette.secondaryText)
                    .fixedSize(horizontal:false,vertical:true)
                    .accessibilityIdentifier("clamshellConditionStatus")
                Spacer(minLength:0)
                if mode.canRetryAutomatic {
                    Button(L("重试")){mode.retryAutomatic()}.buttonStyle(AppNativeButtonStyle()).appControlSize(.small)
                        .disabled(busy || mode.changing).accessibilityIdentifier("retryClamshellAutomatic")
                }
            }
            Text(L(mode.explanation))
                .font(.caption).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
        }.subtlePanel(padding:18)
    }
}

struct ClamshellStatusButton:View {
    @ObservedObject var mode:ClamshellModeModel
    let busy:Bool
    var body:some View {
        if mode.environment?.portable==true {
            Button {mode.setEnabled(!mode.isEnabled)} label:{
                Image(systemName:AppSymbols.resolve("laptopcomputer"))
                    .foregroundColor(mode.status.active ? Palette.violet:Palette.secondaryText)
            }
            .help(L("合盖运行")+" · "+L(mode.detail))
            .accessibilityLabel(L("合盖运行")+" · "+L(mode.detail))
            .accessibilityIdentifier("statusClamshellMode")
            .disabled(busy || mode.changing || !mode.canSetEnabled)
        }
    }
}
