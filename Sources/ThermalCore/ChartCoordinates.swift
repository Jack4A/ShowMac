import Foundation
import CoreGraphics

/// Shared mapping for the Big Sur trend inspector and editable fan curve.
public struct ChartCoordinates {
    public let frame: CGRect
    public let xRange: ClosedRange<Double>
    public let yRange: ClosedRange<Double>
    public init(frame: CGRect, xRange: ClosedRange<Double>, yRange: ClosedRange<Double>) {
        self.frame = frame; self.xRange = xRange; self.yRange = yRange
    }
    public func position(x: Double, y: Double) -> CGPoint {
        let dx = max(Double.leastNonzeroMagnitude, xRange.upperBound - xRange.lowerBound)
        let dy = max(Double.leastNonzeroMagnitude, yRange.upperBound - yRange.lowerBound)
        return CGPoint(x: frame.minX + (x - xRange.lowerBound) / dx * frame.width,
                       y: frame.maxY - (y - yRange.lowerBound) / dy * frame.height)
    }
    public func value(at point: CGPoint, clamped: Bool = false) -> (x: Double, y: Double)? {
        guard point.x.isFinite, point.y.isFinite, frame.width > 0, frame.height > 0,
              clamped || frame.contains(point) else { return nil }
        let x = min(frame.maxX, max(frame.minX, point.x)), y = min(frame.maxY, max(frame.minY, point.y))
        return (xRange.lowerBound + (x - frame.minX) / frame.width * (xRange.upperBound - xRange.lowerBound),
                yRange.lowerBound + (frame.maxY - y) / frame.height * (yRange.upperBound - yRange.lowerBound))
    }
}
