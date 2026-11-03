import AppKit
import SwiftUI
import ThermalCore

enum MenuGraphStyle:String,CaseIterable,Identifiable {
    case line,area,bars
    var id:String {rawValue}
    var title:String {switch self {case .line:return "线条";case .area:return "面积";case .bars:return "柱形"}}
}
enum MenuCPUGraph {
    static func image(points:[MetricPoint],ending:Date,width:Double=44,upper:Double=100,style:MenuGraphStyle = .line,warningsEnabled:Bool=false,appearance:NSAppearance?=nil,kind:MetricKind = .cpuUsage)->NSImage {
        let image=NSImage(size:NSSize(width:width,height:16),flipped:false) {rect in
            let context=appearance ?? NSAppearance.currentDrawing()
            let foreground:NSColor=context.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? .white:.black
            context.performAsCurrentDrawingAppearance {MenuBarAppearanceRenderer.drawHistory(points,ending:ending,rect:rect.insetBy(dx:1,dy:1),upper:upper,color:foreground,bars:style == .bars,background:false,fillArea:style == .area,warningKind:warningsEnabled ? kind:nil)}
            return true
        }
        image.isTemplate = !warningsEnabled || !MetricWarningBands.samples(points,kind:kind).contains{$0.level > .normal}
        return image
    }
}
struct MenuCPUPreview:View {
    @ObservedObject var history:MetricHistoryStore
    var kind:MetricKind = .cpuUsage
    var style:MenuGraphStyle = .line
    var width:Double=44
    var warningsEnabled=true
    var points:[MetricPoint] {history.points(kind,minutes:2)}
    var body:some View {Image(nsImage:MenuCPUGraph.image(points:points,ending:history.end,width:width,upper:max(kind.fixedUpper,points.compactMap(\.value).max() ?? 0),style:style,warningsEnabled:warningsEnabled,kind:kind)).accessibilityLabel(L(kind.title)+" · "+L("趋势图"))}
}
struct MetricSparkline:View {
    @ObservedObject var history:MetricHistoryStore
    @AppStorage("menuCPUWarnings") private var warningsEnabled=true
    let kind:MetricKind
    var body:some View {
        let points=history.points(kind,minutes:2),end=history.end,upper=max(kind.fixedUpper,points.compactMap(\.value).max() ?? 0)
        let runs=MetricWarningBands.runs(points,kind:kind,enabled:warningsEnabled)
        MetricPlotView(series:MetricPlotView.metricSeries(runs,filled:true),xRange:end.addingTimeInterval(-120).timeIntervalSince1970...end.timeIntervalSince1970,yRange:0...upper)
            .frame(height:32).accessibilityHidden(true)
    }
}
