import AppKit
import SwiftUI
import ThermalCore

/// Both entry points share selection states and native segmented controls.
struct FanStrategySelector:View {
    let selected:FanStrategy?
    let busy:Bool
    let available:Bool
    var compact=false
    let onSelect:(FanStrategy)->Void
    var body:some View {
        FullWidthFanStrategyControl(selected:selected,busy:busy,available:available,compact:compact,onSelect:onSelect)
            .frame(maxWidth:.infinity,alignment:.leading)
    }
}

/// AppKit distributes all five segments equally across the proposed content width.
private struct FullWidthFanStrategyControl:NSViewRepresentable {
    let selected:FanStrategy?
    let busy:Bool
    let available:Bool
    let compact:Bool
    let onSelect:(FanStrategy)->Void

    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->NSSegmentedControl {
        let control=NSSegmentedControl(labels:FanStrategy.allCases.map{L($0.shortTitle)},trackingMode:.selectOne,target:context.coordinator,action:#selector(Coordinator.choose(_:)))
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow,for:.horizontal)
        control.setAccessibilityLabel(L("风扇档位"))
        return control
    }
    func updateNSView(_ control:NSSegmentedControl,context:Context) {
        context.coordinator.parent=self
        control.controlSize = compact ? .small:.regular
        for (index,strategy) in FanStrategy.allCases.enumerated() {
            control.setLabel(L(strategy.shortTitle),forSegment:index)
            control.setToolTip(L(strategy.title)+" · "+L(strategy.explanation),forSegment:index)
            control.setEnabled(AppDistribution.hardwareControlAvailable && (strategy == .system || available),forSegment:index)
        }
        control.selectedSegment=selected.flatMap{FanStrategy.allCases.firstIndex(of:$0)} ?? -1
        control.isEnabled = !busy && AppDistribution.hardwareControlAvailable
    }
    @available(macOS 13,*) func sizeThatFits(_ proposal:ProposedViewSize,nsView:NSSegmentedControl,context:Context)->CGSize? {
        CGSize(width:proposal.width ?? nsView.intrinsicContentSize.width,height:nsView.intrinsicContentSize.height)
    }
    final class Coordinator:NSObject {
        var parent:FullWidthFanStrategyControl
        init(_ parent:FullWidthFanStrategyControl){self.parent=parent}
        @objc func choose(_ sender:NSSegmentedControl) {
            let strategies=FanStrategy.allCases
            guard !parent.busy,strategies.indices.contains(sender.selectedSegment) else{return}
            let strategy=strategies[sender.selectedSegment]
            guard strategy == .system || parent.available else{return}
            parent.onSelect(strategy)
        }
    }
}
