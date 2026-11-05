import AppKit
import SwiftUI
import ThermalCore

/// Both entry points share the same palette, equal widths and confirmed selection.
struct FanStrategySelector:View {
    let selected:FanStrategy?
    let busy:Bool
    let available:Bool
    var compact=false
    let onSelect:(FanStrategy)->Void
    var body:some View {
        AppSegmentedPicker(title:L("风扇档位"),selection:selected,
                           choices:FanStrategy.allCases.map{AppChoice($0,L($0.shortTitle),help:L($0.title)+" · "+L($0.explanation))},expands:true,compact:compact,
                           isEnabled:{AppDistribution.hardwareControlAvailable && ($0 == .system || available)},onSelect:onSelect)
            .disabled(busy || !AppDistribution.hardwareControlAvailable)
            .frame(maxWidth:.infinity,alignment:.leading)
    }
}
