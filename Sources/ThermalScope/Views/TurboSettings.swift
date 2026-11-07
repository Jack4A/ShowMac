import SwiftUI
import ThermalCore

/// Reflects the confirmed extension state, not instantaneous CPU boosting.
struct TurboSettings:View {
    @ObservedObject var model:AppModel
    @ObservedObject var readings:LiveReadings
    init(model:AppModel) {self.model=model;readings=model.readings}
    var body:some View {
        TurboSettingsRow(state:readings.snapshot?.turbo,busy:model.busy) {model.changeTurbo(disable:!$0)}
    }
}

struct TurboSettingsRow:View {
    let state:TurboState?
    let busy:Bool
    let setAllowed:(Bool)->Void
    static func allowed(_ state:TurboState?)->Bool? {
        switch state {
        case .driverNotLoaded:return true
        case .disabledDriverLoaded:return false
        default:return nil
        }
    }
    var body:some View {
        HStack(spacing:12) {
            Text(L("睿频")).font(AppTypography.body)
                .help(L("允许 Intel 睿频。关闭需要本机已安装且获系统批准的禁用扩展。"))
            Spacer(minLength:16)
            if Self.allowed(state)==nil {
                Text(L(state == .unsupported ? "不可用":"状态未知")).font(.caption).foregroundColor(Palette.secondaryText)
            }
            Toggle(L("睿频"),isOn:Binding(get:{Self.allowed(state) ?? false},set:setAllowed))
                .labelsHidden().toggleStyle(.switch).accentColor(Palette.violet)
                .disabled(busy || Self.allowed(state)==nil)
                .accessibilityIdentifier("settingsTurboBoost")
        }
    }
}
