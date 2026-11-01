import AppKit
import SwiftUI
import ThermalCore

enum MenuGraphStyle:String,CaseIterable,Identifiable {
    case line,area,bars
    var id:String {rawValue}
    var title:String {switch self {case .line:return "线条";case .area:return "面积";case .bars:return "柱形"}}
}
enum MenuCPUGraph {
    static func image(points:[MetricPoint],ending:Date,width:Double=44,upper:Double=100,style:MenuGraphStyle = .line,warningsEnabled:Bool=false,appearance:NSAppearance?=nil)->NSImage {
        let image=NSImage(size:NSSize(width:width,height:16),flipped:false) {rect in
            let context=appearance ?? NSAppearance.currentDrawing()
            let foreground:NSColor=context.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? .white:.black
            context.performAsCurrentDrawingAppearance {MenuBarAppearanceRenderer.drawHistory(points,ending:ending,rect:rect.insetBy(dx:1,dy:1),upper:upper,color:foreground,bars:style == .bars,background:false,cpuWarnings:warningsEnabled,fillArea:style == .area)}
            return true
        }
        image.isTemplate = !warningsEnabled || !CPULoadBands.samples(points).contains{$0.level > .normal}
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
    var body:some View {Image(nsImage:MenuCPUGraph.image(points:points,ending:history.end,width:width,upper:max(kind.fixedUpper,points.compactMap(\.value).max() ?? 0),style:style,warningsEnabled:warningsEnabled && kind == .cpuUsage)).accessibilityLabel(L(kind.title)+" · "+L("趋势图"))}
}
struct MetricSparkline:View {
    @ObservedObject var history:MetricHistoryStore
    @AppStorage("menuCPUWarnings") private var warningsEnabled=true
    let kind:MetricKind
    var body:some View {
        let points=history.points(kind,minutes:2),end=history.end,upper=max(kind.fixedUpper,points.compactMap(\.value).max() ?? 0)
        let runs=kind == .cpuUsage && warningsEnabled ? CPULoadBands.runs(points):[CPULoadRun(id:0,level:.normal,points:points)]
        Canvas {context,size in
            for run in runs {
                var line=Path(),area=Path(),previous:Int?,first:CGPoint?,last:CGPoint?
                func finishArea() {
                    guard let first,let last else{return}
                    area.addLine(to:CGPoint(x:last.x,y:size.height));area.addLine(to:CGPoint(x:first.x,y:size.height));area.closeSubpath()
                }
                for point in run.points {
                    guard let value=point.value else {finishArea();first=nil;previous=nil;continue}
                    let position=CGPoint(x:min(1,max(0,point.date.timeIntervalSince(end.addingTimeInterval(-120))/120))*size.width,y:size.height-2-min(1,max(0,value/max(1,upper)))*(size.height-4))
                    if previous==point.segment {line.addLine(to:position);area.addLine(to:position)}
                    else {finishArea();line.move(to:position);area.move(to:position);first=position}
                    previous=point.segment;last=position
                }
                finishArea()
                let color=run.level.plotColor()
                context.fill(area,with:.linearGradient(Gradient(colors:[color.opacity(0.18),color.opacity(0.015)]),startPoint:.zero,endPoint:CGPoint(x:0,y:size.height)))
                context.stroke(line,with:.color(color),style:StrokeStyle(lineWidth:1.5,lineCap:.round,lineJoin:.round))
                if let last {context.fill(Path(ellipseIn:CGRect(x:last.x-2,y:last.y-2,width:4,height:4)),with:.color(color))}
            }
        }.frame(height:32).accessibilityHidden(true)
    }
}
