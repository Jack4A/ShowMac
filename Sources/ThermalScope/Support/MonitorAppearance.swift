import AppKit
import SwiftUI

/// Metric roles share the same surfaces and accent as the rest of the application.
enum MonitorAppearance {
    static let canvas=Palette.canvas
    static let accent=Palette.violet
    static let groupFill=Palette.surface

    static func metric(_ kind:MetricKind)->Color {accent}

    static func symbol(_ kind:MetricKind)->String {
        switch kind {
        case .cpuUsage:return "cpu"
        case .fan:return "fanblades"
        default:return "thermometer.medium"
        }
    }

    static func mode(_ name:String)->Color {
        Palette.mode(name)
    }
}

/// Every destination uses the same quiet canvas, including detail and settings pages.
struct MonitorCanvas:View {
    var body:some View {
        MonitorAppearance.canvas.ignoresSafeArea()
    }
}

private struct NeutralPanelsKey:EnvironmentKey {
    static let defaultValue=false
}
extension EnvironmentValues {
    var neutralPanels:Bool {
        get {self[NeutralPanelsKey.self]}
        set {self[NeutralPanelsKey.self]=newValue}
    }
}

struct NeutralPanelSurface:ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content:Content)->some View {
        content.appBackground {
            RoundedRectangle(cornerRadius:14,style:.continuous).fill(MonitorAppearance.groupFill)
                .shadow(color:.black.opacity(scheme == .light && contrast != .increased ? 0.025:0),radius:scheme == .light ? 8:6,x:0,y:2)
        }
            .appOverlay {
                RoundedRectangle(cornerRadius:14,style:.continuous)
                    .stroke(contrast == .increased ? Color.primary.opacity(0.4):Palette.border.opacity(scheme == .light ? 0.65:0.75),lineWidth:contrast == .increased ? 1:0.5)
                    .allowsHitTesting(false)
            }
    }
}

/// Values share a baseline; units provide context without competing with the number.
struct MetricValue:View {
    let value:String
    let unit:String
    var size:CGFloat=28
    var unitSize:CGFloat=12
    var weight:Font.Weight = .medium
    var foreground:Color = Palette.primaryText
    var body:some View {
        HStack(alignment:.firstTextBaseline,spacing:3) {
            Text(value).font(AppTypography.number(size,weight:weight)).appMonospacedDigit()
                .foregroundColor(foreground).lineLimit(1).minimumScaleFactor(0.8)
            if !unit.isEmpty {
                Text(unit).font(.system(size:unitSize)).foregroundColor(Palette.secondaryText).fixedSize()
            }
        }.accessibilityElement(children:.ignore).accessibilityLabel(value+" "+unit)
    }
}
