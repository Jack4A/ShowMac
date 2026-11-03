import Foundation
import CoreGraphics

/// Shared geometry and tick policy for every supported macOS version.
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
    public static func ticks(in range:ClosedRange<Double>,intervals:Int=4)->[Double] {
        let span=range.upperBound-range.lowerBound
        guard range.lowerBound.isFinite,range.upperBound.isFinite,span.isFinite,span>0 else{return range.lowerBound.isFinite ? [range.lowerBound]:[]}
        let raw=span/Double(min(8,max(2,intervals))),magnitude=pow(10,floor(log10(raw)))
        guard magnitude>0,magnitude.isFinite else{return [range.lowerBound,range.upperBound]}
        let unit=raw/magnitude
        let step=([1.0,2,2.5,5,10].min{abs($0-unit)<abs($1-unit)} ?? 1)*magnitude
        let first=ceil(range.lowerBound/step-1e-9),last=floor(range.upperBound/step+1e-9)
        guard first.isFinite,last.isFinite,last>=first,last-first<=20 else{return [range.lowerBound,range.upperBound]}
        return (0...Int(last-first)).map {index in
            let value=(first+Double(index))*step
            return abs(value)<step*1e-9 ? 0:value
        }
    }
}
