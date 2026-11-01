import Foundation

public struct MetricPoint:Identifiable,Equatable {
    public let date:Date
    public let value:Double?
    public let segment:Int
    public var id:Date {date}
}
/// Bounded, timestamped samples. Missing values break a line, never become zero.
public struct MetricHistory {
    public private(set) var points:[MetricPoint]=[]
    private var segment=0
    private let maximumGap:Double
    public init(maximumGap:Double=15){self.maximumGap=maximumGap}
    public mutating func append(_ value:Double?,at date:Date) {
        guard date.timeIntervalSince1970.isFinite else{return}
        if let previous=points.last, date<=previous.date {return}
        let valid=value.flatMap{$0.isFinite && $0>=0 ? $0:nil}
        if let previous=points.last,previous.value==nil || valid==nil || date.timeIntervalSince(previous.date)>maximumGap {segment+=1}
        points.append(MetricPoint(date:date,value:valid,segment:segment))
        points.removeAll{$0.date<date.addingTimeInterval(-1800)}
        if points.count>1000 {points.removeFirst(points.count-1000)}
    }
    public func window(ending date:Date,seconds:Double)->[MetricPoint] {
        points.filter{$0.date>=date.addingTimeInterval(-max(1,min(1800,seconds))) && $0.date<=date}
    }
}

/// Actual samples only. A soft drawing budget preserves segment ends and extrema.
public enum MetricPlot {
    public static func decimated(_ input:[MetricPoint],budget:Int=240)->[MetricPoint] {
        let points=input.filter{$0.value != nil}
        guard points.count>budget,budget>=4 else{return points}
        let chunk=max(2,Int(ceil(Double(points.count)*2/Double(budget))))
        var result:[MetricPoint]=[],index=0
        while index<points.count {
            var end=index+1
            while end<points.count && points[end].segment==points[index].segment {end+=1}
            result.append(points[index])
            var offset=index+1
            while offset<end-1 {
                let upper=min(end-1,offset+chunk),bucket=points[offset..<min(end-1,offset+chunk)]
                if let low=bucket.min(by:{$0.value!<$1.value!}),let high=bucket.max(by:{$0.value!<$1.value!}) {
                    result.append(contentsOf:low.date==high.date ? [low]:[low,high].sorted{$0.date<$1.date})
                }
                offset=upper
            }
            if end-index>1 {result.append(points[end-1])}
            index=end
        }
        return result
    }
    public static func nearest(_ points:[MetricPoint],to date:Date,maximumDistance:Double)->MetricPoint? {
        guard date.timeIntervalSince1970.isFinite,maximumDistance.isFinite,maximumDistance>=0,
              let point=points.filter({$0.value != nil}).min(by:{abs($0.date.timeIntervalSince(date))<abs($1.date.timeIntervalSince(date))}),
              abs(point.date.timeIntervalSince(date))<=maximumDistance else{return nil}
        return point
    }
    public static func scale(_ values:[Double],automatic:Bool,baseline:Double=0,upper:Double=100)->ClosedRange<Double> {
        let finite=values.filter{$0.isFinite && $0>=0},low=finite.min() ?? baseline,high=finite.max() ?? upper
        guard automatic,!finite.isEmpty else{return min(baseline,low)...max(upper,high)}
        let minimumSpan=upper>150 ? 500.0:10.0,padding=max(minimumSpan,(high-low))*0.12
        let center=(high+low)/2,half=max(minimumSpan/2,(high-low)/2+padding)
        return max(0,floor(center-half))...ceil(center+half)
    }
}
