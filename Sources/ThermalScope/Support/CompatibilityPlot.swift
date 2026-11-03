import AppKit
import SwiftUI
import ThermalCore

enum PlatformUI {
    /// Allows the macOS 11 path to be exercised on a current development machine.
    static let classic = ProcessInfo.processInfo.environment["THERMALSCOPE_CLASSIC_UI"] == "1"
}

/// Path-based charts keep real samples, gaps and warning colors on macOS 11/12.
/// Swift Charts remains the renderer on newer systems.
struct CompatibilityPlot: View {
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
    var xLabel: (Double) -> String = { _ in "" }
    var yLabel: (Double) -> String = { String(format: "%.0f", $0) }
    var onInspect: ((Double?) -> Void)?
    var onDrag: ((CGPoint, ChartCoordinates) -> Void)?
    var onDragEnd: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let frame = CGRect(x: axes ? 44 : 3, y: 8,
                               width: max(1, geometry.size.width - (axes ? 56 : 6)),
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
                    ForEach(Array(item.points.enumerated()), id: \.offset) { index, point in
                        if item.markers || item.points.count == 1 || (!axes && index == item.points.count - 1) {
                            let position = coordinates.position(x: point.x, y: point.y)
                            Circle().fill(item.color).frame(width: item.markers ? 8 : 3.5, height: item.markers ? 8 : 3.5).position(position)
                        }
                    }
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
                    }, onDrag: { location in onDrag?(location, coordinates) }, onEnd: { onDragEnd?() })
                }
            }.clipped()
        }
    }

    private func axisLabels(_ coordinates: ChartCoordinates) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<5) { index in
                let value = yRange.lowerBound + Double(index) / 4 * (yRange.upperBound - yRange.lowerBound)
                let y = coordinates.position(x: xRange.lowerBound, y: value).y
                Text(yLabel(value)).font(.system(size: 10)).foregroundColor(.secondary)
                    .frame(width: 38, alignment: .trailing).position(x: 19, y: y)
                Path { path in
                    path.move(to: CGPoint(x: coordinates.frame.minX, y: y))
                    path.addLine(to: CGPoint(x: coordinates.frame.maxX, y: y))
                }.stroke(Color.primary.opacity(0.10), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
            }
            ForEach(0..<3) { index in
                let value = xRange.lowerBound + (0.1 + Double(index) * 0.4) * (xRange.upperBound - xRange.lowerBound)
                Text(xLabel(value)).font(.system(size: 10)).foregroundColor(.secondary)
                    .position(x: coordinates.position(x: value, y: yRange.lowerBound).x, y: coordinates.frame.maxY + 15)
            }
        }
    }

    private func paths(_ series: Series, _ coordinates: ChartCoordinates) -> (line: Path, area: Path) {
        var line = Path(), area = Path(), previous: Int?, first: CGPoint?, last: CGPoint?
        func close() {
            guard let first, let last else { return }
            area.addLine(to: CGPoint(x: last.x, y: coordinates.frame.maxY))
            area.addLine(to: CGPoint(x: first.x, y: coordinates.frame.maxY))
            area.closeSubpath()
        }
        for sample in series.points {
            guard sample.x.isFinite, sample.y.isFinite else { close(); previous = nil; first = nil; continue }
            let point = coordinates.position(x: sample.x, y: sample.y)
            if previous == sample.segment { line.addLine(to: point); area.addLine(to: point) }
            else { close(); line.move(to: point); area.move(to: point); first = point }
            previous = sample.segment; last = point
        }
        close()
        return (line, area)
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
    func makeNSView(context: Context) -> TrackingView { TrackingView() }
    func updateNSView(_ view: TrackingView, context: Context) {
        view.onMove = onMove; view.onDrag = onDrag; view.onEnd = onEnd
    }
    final class TrackingView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        var onDrag: ((CGPoint) -> Void)?
        var onEnd: (() -> Void)?
        override var isFlipped: Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self))
        }
        override func mouseMoved(with event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)) }
        override func mouseExited(with event: NSEvent) { onMove?(nil) }
        override func mouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            onMove?(location); onDrag?(location)
        }
        override func mouseDragged(with event: NSEvent) { mouseDown(with: event) }
        override func mouseUp(with event: NSEvent) { onEnd?() }
    }
}
