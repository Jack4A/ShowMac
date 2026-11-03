import AppKit
import SwiftUI
import ThermalCore

enum PlatformUI {
    /// Allows the macOS 11 path to be exercised on a current development machine.
    static let classic = ProcessInfo.processInfo.environment["THERMALSCOPE_CLASSIC_UI"] == "1"
}

/// One renderer keeps axes, real samples, gaps and warning colors stable on macOS 11+.
struct MetricPlotView: View {
    struct Point {
        let x: Double
        let y: Double
        var segment: Int = 0
    }
    struct Series: Identifiable {
        let id: String
        let points: [Point]
        var color: Color = Palette.violet
        var filled = false
        var dash: [CGFloat] = []
        var markers = false
    }
    struct Rule: Identifiable {
        let id: String
        let x: Double
        var color: Color = .secondary
    }
    let series: [Series]
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    var rules: [Rule] = []
    var axes = false
    var xTicks: [Double]?
    var xLabel: (Double) -> String = { _ in "" }
    var selection: Point?
    var selectionColor: Color = Palette.violet
    var placeholder: String?
    var onInspect: ((Double?) -> Void)?
    var onDrag: ((CGPoint, ChartCoordinates) -> Void)?
    var onDragEnd: (() -> Void)?
    var onNudge: ((MoveCommandDirection) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let frame = CGRect(x: axes ? 44 : 3, y: 8,
                               width: max(1, geometry.size.width - (axes ? 68 : 6)),
                               height: max(1, geometry.size.height - (axes ? 32 : 12)))
            let coordinates = ChartCoordinates(frame: frame, xRange: xRange, yRange: yRange)
            ZStack(alignment: .topLeading) {
                if axes { axisLabels(coordinates) }
                ForEach(series) { item in
                    let paths = paths(item, coordinates)
                    if item.filled {
                        paths.area.fill(LinearGradient(gradient: Gradient(colors: [item.color.opacity(0.18), item.color.opacity(0.01)]), startPoint: .top, endPoint: .bottom))
                    }
                    paths.line.stroke(item.color, style: StrokeStyle(lineWidth: axes ? 2.1 : 1.7, lineCap: .round, lineJoin: .round, dash: item.dash))
                    paths.markers.fill(item.color)
                }
                if let selection {
                    let position=coordinates.position(x:selection.x,y:selection.y)
                    Path {path in path.move(to:CGPoint(x:position.x,y:frame.minY));path.addLine(to:CGPoint(x:position.x,y:frame.maxY))}
                        .stroke(Palette.secondaryText.opacity(0.4),lineWidth:1)
                    Circle().fill(selectionColor).frame(width:7,height:7).position(position)
                }
                if let placeholder,!series.contains(where: {!$0.points.isEmpty}) {
                    Text(placeholder).font(AppTypography.caption).foregroundColor(Palette.secondaryText).frame(maxWidth:.infinity,maxHeight:.infinity)
                }
                ForEach(rules) { rule in
                    Path { path in
                        let x = coordinates.position(x: rule.x, y: yRange.lowerBound).x
                        path.move(to: CGPoint(x: x, y: frame.minY))
                        path.addLine(to: CGPoint(x: x, y: frame.maxY))
                    }.stroke(rule.color.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                if onInspect != nil || onDrag != nil {
                    PlotInteraction(onMove: { location in
                        onInspect?(location.flatMap { coordinates.value(at: $0)?.x })
                    }, onDrag: { location in onDrag?(location, coordinates) }, onEnd: { onDragEnd?() },onKey:onNudge)
                }
            }.clipped()
        }
    }

    private func axisLabels(_ coordinates: ChartCoordinates) -> some View {
        let ticks=ChartCoordinates.ticks(in:yRange)
        let step=ticks.count>1 ? ticks[1]-ticks[0]:1
        let magnitude=pow(10,floor(log10(max(Double.leastNormalMagnitude,step))))
        let digits=max(0,min(4,Int(-floor(log10(max(Double.leastNormalMagnitude,step))))+(abs(step/magnitude-2.5)<0.001 ? 1:0)))
        let horizontal=xTicks ?? [0.1,0.5,0.9].map{xRange.lowerBound+$0*(xRange.upperBound-xRange.lowerBound)}
        return ZStack(alignment: .topLeading) {
            ForEach(ticks,id:\.self) { value in
                let y = coordinates.position(x: xRange.lowerBound, y: value).y
                Text(String(format:"%.*f",digits,value)).font(.system(size: 10)).foregroundColor(Palette.secondaryText)
                    .frame(width: 38, alignment: .trailing).position(x: 19, y: y)
                Path { path in
                    path.move(to: CGPoint(x: coordinates.frame.minX, y: y))
                    path.addLine(to: CGPoint(x: coordinates.frame.maxX, y: y))
                }.stroke(Palette.secondaryText.opacity(0.18), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
            }
            ForEach(horizontal,id:\.self) { value in
                Text(xLabel(value)).font(.system(size: 10)).foregroundColor(Palette.secondaryText)
                    .position(x: coordinates.position(x: value, y: yRange.lowerBound).x, y: coordinates.frame.maxY + 15)
            }
        }
    }

    private func paths(_ series: Series, _ coordinates: ChartCoordinates) -> (line: Path, area: Path, markers:Path) {
        var line = Path(), area = Path(), markers=Path(), previous: Int?, first: CGPoint?, last: CGPoint?
        func close() {
            guard let first, let last else { return }
            area.addLine(to: CGPoint(x: last.x, y: coordinates.frame.maxY))
            area.addLine(to: CGPoint(x: first.x, y: coordinates.frame.maxY))
            area.closeSubpath()
        }
        for (index,sample) in series.points.enumerated() {
            guard sample.x.isFinite, sample.y.isFinite else { close(); previous = nil; first = nil; continue }
            let point = coordinates.position(x: sample.x, y: sample.y)
            if previous == sample.segment { line.addLine(to: point); area.addLine(to: point) }
            else { close(); line.move(to: point); area.move(to: point); first = point }
            previous = sample.segment; last = point
            if series.markers || series.points.count==1 || (!axes && index==series.points.count-1) {
                let diameter:CGFloat=series.markers ? 8:3.5
                markers.addEllipse(in:CGRect(x:point.x-diameter/2,y:point.y-diameter/2,width:diameter,height:diameter))
            }
        }
        close()
        return (line, area, markers)
    }

    static func metricSeries(_ runs: [CPULoadRun], normal: Color = Palette.violet, filled: Bool = false) -> [Series] {
        runs.map { run in
            Series(id: String(run.id), points: run.points.compactMap { point in
                point.value.map { Point(x: point.date.timeIntervalSince1970, y: $0, segment: point.segment) }
            }, color: run.level.plotColor(normal: normal), filled: filled)
        }
    }
    static func timeLabel(_ value: Double) -> String {
        DateFormatter.localizedString(from: Date(timeIntervalSince1970: value), dateStyle: .none, timeStyle: .short)
    }
}

/// NSTrackingArea supplies continuous pointer positions on Big Sur as well.
private struct PlotInteraction: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void
    let onDrag: (CGPoint) -> Void
    let onEnd: () -> Void
    let onKey: ((MoveCommandDirection)->Void)?
    func makeNSView(context: Context) -> TrackingView { TrackingView() }
    func updateNSView(_ view: TrackingView, context: Context) {
        view.onMove = onMove; view.onDrag = onDrag; view.onEnd = onEnd;view.onKey=onKey
    }
    final class TrackingView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        var onDrag: ((CGPoint) -> Void)?
        var onEnd: (() -> Void)?
        var onKey: ((MoveCommandDirection)->Void)?
        override var acceptsFirstResponder:Bool {onKey != nil}
        override var isFlipped: Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self))
        }
        override func mouseMoved(with event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)) }
        override func mouseExited(with event: NSEvent) { onMove?(nil) }
        override func mouseDown(with event: NSEvent) {
            if onKey != nil {window?.makeFirstResponder(self)}
            let location = convert(event.locationInWindow, from: nil)
            onMove?(location); onDrag?(location)
        }
        override func mouseDragged(with event: NSEvent) { mouseDown(with: event) }
        override func mouseUp(with event: NSEvent) { onEnd?() }
        override func keyDown(with event:NSEvent) {
            guard let onKey else{super.keyDown(with:event);return}
            switch event.keyCode {
            case 123:onKey(.left)
            case 124:onKey(.right)
            case 125:onKey(.down)
            case 126:onKey(.up)
            default:super.keyDown(with:event)
            }
        }
    }
}
