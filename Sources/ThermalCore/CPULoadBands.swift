import Foundation

public enum CPULoadLevel:Int,Comparable {case unknown = -1,normal,elevated,critical
    public static func <(lhs:Self,rhs:Self)->Bool {lhs.rawValue<rhs.rawValue}
}
public struct CPULoadSample {
    public let point:MetricPoint
    public let level:CPULoadLevel
    public init(point:MetricPoint,level:CPULoadLevel){self.point=point;self.level=level}
}
public struct CPULoadRun:Identifiable {
    public let id:Int
    public let level:CPULoadLevel
    public var points:[MetricPoint]
    public init(id:Int,level:CPULoadLevel,points:[MetricPoint]){self.id=id;self.level=level;self.points=points}
}
/// Display thresholds for whole-machine CPU usage, independent of hardware control/diagnosis.
public enum CPULoadBands {
    public static let elevatedThreshold=70.0
    public static let criticalThreshold=90.0
    public static let sustainedSeconds=10.0
    public static func baseLevel(_ value:Double?)->CPULoadLevel {
        guard let value,value.isFinite,(0...100).contains(value) else{return .unknown}
        return value>=elevatedThreshold ? .elevated:.normal
    }
    public static func samples(_ points:[MetricPoint])->[CPULoadSample] {
        var previous:MetricPoint?,highSince:Date?
        return points.map {point in
            let base=baseLevel(point.value)
            guard base != .unknown,point.date.timeIntervalSince1970.isFinite else{previous=nil;highSince=nil;return CPULoadSample(point:point,level:.unknown)}
            let contiguous=previous.map{point.segment==$0.segment && point.date>$0.date && point.date.timeIntervalSince($0.date)<=15} ?? false
            if !contiguous {highSince=nil}
            var level=base
            if point.value!>=criticalThreshold {
                if highSince==nil {highSince=point.date}
                if point.date.timeIntervalSince(highSince!)>=sustainedSeconds {level = .critical}
            } else {highSince=nil}
            previous=point
            return CPULoadSample(point:point,level:level)
        }
    }
    public static func current(_ value:Double?,points:[MetricPoint],at date:Date)->CPULoadLevel {
        let base=baseLevel(value)
        guard base != .unknown,let last=samples(points).last,last.point.value==value,date.timeIntervalSince(last.point.date)>=0,date.timeIntervalSince(last.point.date)<=15 else{return base}
        return last.level
    }
    /// Runs preserve color transitions and sampling gaps before any drawing reduction.
    public static func runs(_ points:[MetricPoint],budget:Int=140)->[CPULoadRun] {
        var result:[CPULoadRun]=[],previous:CPULoadSample?
        for sample in samples(points) {
            guard sample.level != .unknown else{previous=nil;continue}
            let contiguous=previous.map{sample.point.segment==$0.point.segment && sample.point.date>$0.point.date && sample.point.date.timeIntervalSince($0.point.date)<=15} ?? false
            if contiguous {
                if result.last?.level==sample.level {result[result.count-1].points.append(sample.point)}
                else {
                    // The newly confirmed state starts at this actual sample, never earlier.
                    result[result.count-1].points.append(sample.point)
                    result.append(CPULoadRun(id:result.count,level:sample.level,points:[sample.point]))
                }
            } else {result.append(CPULoadRun(id:result.count,level:sample.level,points:[sample.point]))}
            previous=sample
        }
        let perRun=max(4,budget/max(1,result.count))
        return result.map{CPULoadRun(id:$0.id,level:$0.level,points:MetricPlot.decimated($0.points,budget:perRun))}
    }
}
