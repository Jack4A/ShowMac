import Foundation

/// Retained points always contain an observed wattage and its original timestamp.
/// First/min/max/last samples bound storage while preserving real peaks and gaps.
public struct ElectricityPowerHistory {
    public struct Sample:Codable,Equatable,Sendable {public let date:Date;public let watts:Double}
    public struct Envelope:Codable,Sendable {
        public let source:ElectricitySource
        public let segment:Int
        public let resolution:Int
        public let index:Int64
        public var samples:[Sample]
    }
    public struct Archive:Codable,Sendable {public let version:Int;public let envelopes:[Envelope]}
    private struct Key:Hashable {let source:ElectricitySource;let segment:Int;let resolution:Int;let index:Int64}
    private struct Anchor {let date:Date;let segment:Int}
    private var envelopes:[Key:Envelope]=[:]
    private var anchors:[ElectricitySource:Anchor]=[:]
    private var latest:[ElectricitySource:Date]=[:]
    private var earliest:[ElectricitySource:Date]=[:]
    private var recent:[ElectricitySource:[MetricPoint]]=[:]
    private var nextSegment=0
    private var compactedHour:Int64?
    public init(){}
    public init(archive:Archive)throws {
        guard archive.version==1,archive.envelopes.count<=250_000 else{throw ScopeError.message("功率历史格式无效")}
        for envelope in archive.envelopes {
            guard [60,3600].contains(envelope.resolution),(0..<1_000_000_000).contains(envelope.segment),
                  !envelope.samples.isEmpty,envelope.samples.count<=4,
                  envelope.samples.allSatisfy({Self.valid($0.date) && $0.watts.isFinite && (0...10000).contains($0.watts) &&
                      Int64(floor($0.date.timeIntervalSince1970/Double(envelope.resolution)))==envelope.index}),
                  zip(envelope.samples,envelope.samples.dropFirst()).allSatisfy({$0.date<$1.date}) else{throw ScopeError.message("功率历史记录无效")}
            let key=Key(source:envelope.source,segment:envelope.segment,resolution:envelope.resolution,index:envelope.index)
            guard envelopes[key]==nil else{throw ScopeError.message("功率历史记录重复")}
            envelopes[key]=envelope
            latest[envelope.source]=max(latest[envelope.source] ?? envelope.samples.last!.date,envelope.samples.last!.date)
            earliest[envelope.source]=min(earliest[envelope.source] ?? envelope.samples[0].date,envelope.samples[0].date)
            nextSegment=max(nextSegment,envelope.segment+1)
        }
    }
    public var archive:Archive {Archive(version:1,envelopes:envelopes.values.sorted{
        if $0.source != $1.source {return $0.source.rawValue<$1.source.rawValue}
        if $0.segment != $1.segment {return $0.segment<$1.segment}
        if $0.resolution != $1.resolution {return $0.resolution<$1.resolution}
        return $0.index<$1.index
    })}
    public var sources:[ElectricitySource] {ElectricitySource.allCases.filter{earliest[$0] != nil}}
    public func firstDate(for source:ElectricitySource)->Date? {earliest[source]}
    public mutating func breakContinuity(){anchors.removeAll()}
    public mutating func record(_ watts:Double?,source:ElectricitySource,at date:Date,maximumGap:Double=15) {
        guard Self.valid(date),let watts,watts.isFinite,(0...10000).contains(watts) else{anchors.removeValue(forKey:source);return}
        if let last=latest[source],date<=last {return}
        let previous=anchors[source]
        let segment:Int
        if let previous,date.timeIntervalSince(previous.date)<=maximumGap {segment=previous.segment}
        else {guard nextSegment<1_000_000_000 else{return};segment=nextSegment;nextSegment+=1}
        anchors[source]=Anchor(date:date,segment:segment);latest[source]=date
        earliest[source]=min(earliest[source] ?? date,date)
        let index=Int64(floor(date.timeIntervalSince1970/60)),key=Key(source:source,segment:segment,resolution:60,index:index)
        var envelope=envelopes[key] ?? Envelope(source:source,segment:segment,resolution:60,index:index,samples:[])
        envelope.samples=Self.extrema(envelope.samples+[Sample(date:date,watts:watts)]);envelopes[key]=envelope
        var live=recent[source] ?? []
        live.append(MetricPoint(date:date,value:watts,segment:segment))
        live.removeAll{$0.date<date.addingTimeInterval(-1800)}
        if live.count>1200 {live.removeFirst(live.count-1200)}
        recent[source]=live
        compact(at:date)
    }
    public mutating func compact(at date:Date) {
        guard Self.valid(date) else{return}
        let hour=Int64(floor(date.timeIntervalSince1970/3600))
        guard hour != compactedHour else{return};compactedHour=hour
        let cutoff=date.addingTimeInterval(-7*86400)
        let old=envelopes.filter{$0.value.resolution==60 && ($0.value.samples.last?.date ?? date)<cutoff}
        for (key,envelope) in old {
            envelopes.removeValue(forKey:key)
            let index=Int64(floor(envelope.samples[0].date.timeIntervalSince1970/3600))
            let coarse=Key(source:envelope.source,segment:envelope.segment,resolution:3600,index:index)
            var merged=envelopes[coarse] ?? Envelope(source:envelope.source,segment:envelope.segment,resolution:3600,index:index,samples:[])
            merged.samples=Self.extrema(merged.samples+envelope.samples);envelopes[coarse]=merged
        }
    }
    public func records(source:ElectricitySource,in interval:DateInterval)->[MetricPoint] {
        let saved=envelopes.values.filter{$0.source==source}.flatMap {envelope in
            envelope.samples.filter{interval.contains($0.date)}.map{MetricPoint(date:$0.date,value:$0.watts,segment:envelope.segment)}
        }
        var seen=Set<Date>()
        return (saved+(recent[source] ?? []).filter{interval.contains($0.date)}).sorted{$0.date<$1.date}.filter{seen.insert($0.date).inserted}
    }
    public static func nearest(in groups:[Int:[MetricPoint]],at date:Date,pointTolerance:TimeInterval=0)->MetricPoint? {
        // Never snap across a missing segment; display the actual retained sample time.
        guard Self.valid(date),let group=groups.values.first(where:{points in
            guard let first=points.first,let last=points.last else{return false}
            return date>=first.date && date<=last.date || (points.count==1 && abs(first.date.timeIntervalSince(date))<=pointTolerance)
        }) else{return nil}
        return group.min{abs($0.date.timeIntervalSince(date))<abs($1.date.timeIntervalSince(date))}
    }
    private static func extrema(_ samples:[Sample])->[Sample] {
        let ordered=samples.sorted{$0.date<$1.date}
        guard let first=ordered.first,let last=ordered.last,let low=ordered.min(by:{$0.watts<$1.watts}),let high=ordered.max(by:{$0.watts<$1.watts}) else{return []}
        var seen=Set<Date>()
        return [first,low,high,last].sorted{$0.date<$1.date}.filter{seen.insert($0.date).inserted}
    }
    private static func valid(_ date:Date)->Bool {date.timeIntervalSince1970.isFinite && abs(date.timeIntervalSince1970)<10_000_000_000}
}
