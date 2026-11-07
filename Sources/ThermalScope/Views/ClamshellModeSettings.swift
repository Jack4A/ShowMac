import SwiftUI
import ThermalCore

struct ClamshellModeSettings:View {
    @ObservedObject var mode:ClamshellModeModel
    let busy:Bool
    var body:some View {
        HStack(spacing:12) {
                Image(systemName:AppSymbols.resolve("laptopcomputer"))
                    .font(.system(size:20)).foregroundColor(Palette.violet).frame(width:30)
                VStack(alignment:.leading,spacing:4) {
                    Text(L("合盖运行")).font(AppTypography.body.weight(.semibold))
                    Text(L(mode.summary)).font(.caption)
                        .foregroundColor(mode.status.failed || mode.automaticIssue != nil ? Color.orange:Palette.secondaryText)
                        .fixedSize(horizontal:false,vertical:true)
                        .accessibilityIdentifier("clamshellConditionStatus")
                }
                Spacer(minLength:8)
                if mode.changing {ProgressView().appControlSize(.small)}
                Toggle(L("合盖运行"),isOn:Binding(get:{mode.isEnabled},set:{mode.setEnabled($0)}))
                    .labelsHidden().toggleStyle(.switch).accentColor(Palette.violet)
                    .disabled(busy || mode.changing || !mode.canSetEnabled)
                    .help(L(mode.explanation)+" "+L("开启期间阻止系统休眠，屏幕仍可熄灭。"))
                    .accessibilityIdentifier("settingsClamshellMode")
                Menu {
                    Picker(L("运行方式"),selection:Binding(get:{mode.activation},set:{mode.setActivation($0)})) {
                        ForEach(ClamshellActivation.allCases,id:\.self) {value in Text(L(value.title)).tag(value)}
                    }.pickerStyle(.inline)
                    if mode.canRetryAutomatic {
                        Divider()
                        Button(L("重试")){mode.retryAutomatic()}
                    }
                } label:{Image(systemName:AppSymbols.resolve("ellipsis")).frame(width:20,height:24).contentShape(Rectangle())}
                    .menuStyle(BorderlessButtonMenuStyle())
                    .fixedSize()
                    .foregroundColor(Palette.secondaryText)
                    .disabled(busy || mode.changing || !mode.canArmAutomatic)
                    .help(L("更多选项")).accessibilityLabel(L("合盖运行")+" · "+L("更多选项"))
                    .accessibilityIdentifier("clamshellMoreOptions")
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
