import Foundation

public enum ElectricitySource:String,Codable,CaseIterable,Identifiable,Sendable {
    case system,dcInput,battery
    public var id:String {rawValue}
    public var title:String {switch self {case .system:return "设备总功耗";case .dcInput:return "直流输入功耗";case .battery:return "电池放电功率"}}
    public var detail:String {switch self {
    case .system:return "设备内部报告的总功耗，不包含所有插座侧损耗。"
    case .dcInput:return "直流输入侧功耗，可能包含充电，不包含电源适配器损耗。"
    case .battery:return "仅统计电池放电；费用为等效估算，不包含充电损耗。"
    }}
}

public enum ElectricityPeriod:String,CaseIterable,Identifiable,Codable {
    case day,week,month,year
    public var id:String {rawValue}
    public var title:String {switch self {case .day:return "日";case .week:return "周";case .month:return "月";case .year:return "年"}}
    public var currentTitle:String {switch self {case .day:return "今天";case .week:return "本周";case .month:return "本月";case .year:return "今年"}}
    public var component:Calendar.Component {switch self {case .day:return .day;case .week:return .weekOfYear;case .month:return .month;case .year:return .year}}
    public func interval(containing date:Date,calendar:Calendar = .current)->DateInterval {
        calendar.dateInterval(of:component,for:date) ?? DateInterval(start:date,duration:0)
    }
    public func chartIntervals(containing date:Date,calendar:Calendar = .current)->[DateInterval] {
        let range=interval(containing:date,calendar:calendar)
        let unit:Calendar.Component=self == .day ? .hour:(self == .year ? .month:.day)
        var result:[DateInterval]=[],cursor=range.start
        while cursor<range.end,result.count<32 {
            guard let next=calendar.date(byAdding:unit,value:1,to:cursor),next>cursor else{break}
            result.append(DateInterval(start:cursor,end:min(next,range.end)));cursor=next
        }
        return result
    }
}

public struct ElectricityTotals:Equatable {
    public var wattHours:Double=0
    public var observedSeconds:Double=0
    public var kilowattHours:Double {wattHours/1000}
    public var averageWatts:Double? {observedSeconds>0 ? wattHours*3600/observedSeconds:nil}
    public func cost(rate:Double?)->Double? {
        guard observedSeconds>0,let rate,rate.isFinite,(0...10000).contains(rate) else{return nil}
        return kilowattHours*rate
    }
}

/// UTC-hour aggregates remain compact across years; sources never get added together.
/// Only two valid, nearby observations form an interval. Anchors are intentionally not persisted.
public struct ElectricityHistory {
    public struct Bucket:Codable,Sendable {
        public let source:ElectricitySource
        public let hour:Int64
        public var first:Date
        public var last:Date
        public var wattHours:Double
        public var seconds:Double
    }
    public struct Archive:Codable,Sendable {
        public let version:Int
        public let createdAt:Date
        public let buckets:[Bucket]
    }
    private struct Key:Hashable {let source:ElectricitySource;let hour:Int64}
    private struct Anchor {let date:Date;let watts:Double}
    private var buckets:[Key:Bucket]=[:]
    private var anchors:[ElectricitySource:Anchor]=[:]
    private var latest:[ElectricitySource:Date]=[:]
    private var earliest:[ElectricitySource:Date]=[:]
    public let createdAt:Date
    public init(createdAt:Date=Date()) {self.createdAt=createdAt}
    public init(archive:Archive)throws {
        guard archive.version==1,Self.valid(archive.createdAt),archive.buckets.count<=500_000 else{throw ScopeError.message("用电历史格式无效")}
        createdAt=archive.createdAt
        for bucket in archive.buckets {
            let start=Double(bucket.hour)*3600
            guard start.isFinite,abs(start)<10_000_000_000,Self.valid(bucket.first),Self.valid(bucket.last),
                  bucket.first.timeIntervalSince1970>=start,bucket.last.timeIntervalSince1970<=start+3600,
                  bucket.last>bucket.first,bucket.seconds.isFinite,bucket.seconds>0,
                  bucket.seconds<=bucket.last.timeIntervalSince(bucket.first)+0.001,
                  bucket.wattHours.isFinite,bucket.wattHours>=0,bucket.wattHours<=10000*bucket.seconds/3600+0.001 else{throw ScopeError.message("用电历史记录无效")}
            let key=Key(source:bucket.source,hour:bucket.hour)
            guard buckets[key]==nil else{throw ScopeError.message("用电历史记录重复")}
            buckets[key]=bucket;latest[bucket.source]=max(latest[bucket.source] ?? bucket.last,bucket.last)
            earliest[bucket.source]=min(earliest[bucket.source] ?? bucket.first,bucket.first)
        }
    }
    public var archive:Archive {Archive(version:1,createdAt:createdAt,buckets:buckets.values.sorted{$0.hour==$1.hour ? $0.source.rawValue<$1.source.rawValue:$0.hour<$1.hour})}
    public var sources:[ElectricitySource] {ElectricitySource.allCases.filter{earliest[$0] != nil}}
    public func firstDate(for source:ElectricitySource)->Date? {earliest[source]}
    public mutating func breakContinuity() {anchors.removeAll()}
    public mutating func record(_ watts:Double?,source:ElectricitySource,at date:Date,maximumGap:Double=15) {
        guard Self.valid(date) else{return}
        guard let watts,watts.isFinite,(0...10000).contains(watts) else{anchors.removeValue(forKey:source);return}
        // Ignore duplicates and backwards clock jumps without accumulating the same span twice.
        if let latest=latest[source],date<latest {return}
        let previous=anchors[source]
        if let previous,date<=previous.date {return}
        latest[source]=date;anchors[source]=Anchor(date:date,watts:watts)
        guard let previous else{return}
        let duration=date.timeIntervalSince(previous.date)
        guard duration>0,duration<=maximumGap else{return}
        earliest[source]=min(earliest[source] ?? previous.date,previous.date)
        var cursor=previous.date
        while cursor<date {
            let hour=Int64(floor(cursor.timeIntervalSince1970/3600))
            let end=min(date,Date(timeIntervalSince1970:Double(hour+1)*3600))
            let a=cursor.timeIntervalSince(previous.date)/duration,b=end.timeIntervalSince(previous.date)/duration
            let seconds=end.timeIntervalSince(cursor)
            let energy=((previous.watts+(watts-previous.watts)*a)+(previous.watts+(watts-previous.watts)*b))/2*seconds/3600
            let key=Key(source:source,hour:hour)
            var bucket=buckets[key] ?? Bucket(source:source,hour:hour,first:cursor,last:end,wattHours:0,seconds:0)
            bucket.first=min(bucket.first,cursor);bucket.last=max(bucket.last,end)
            bucket.wattHours+=energy;bucket.seconds+=seconds;buckets[key]=bucket
            cursor=end
        }
    }
    public func totals(source:ElectricitySource,in interval:DateInterval)->ElectricityTotals {
        var total=ElectricityTotals()
        guard interval.duration>0,Self.valid(interval.start),Self.valid(interval.end),let first=earliest[source],let last=latest[source] else{return total}
        let start=max(first,interval.start),end=min(last,interval.end)
        guard end>start else{return total}
        let firstHour=Int64(floor(start.timeIntervalSince1970/3600)),lastHour=Int64(ceil(end.timeIntervalSince1970/3600))-1
        for hour in firstHour...lastHour {
            guard let bucket=buckets[Key(source:source,hour:hour)],bucket.last>interval.start,bucket.first<interval.end else{continue}
            let seconds=min(bucket.last,interval.end).timeIntervalSince(max(bucket.first,interval.start))
            let fraction=seconds/bucket.last.timeIntervalSince(bucket.first)
            total.wattHours+=bucket.wattHours*fraction;total.observedSeconds+=bucket.seconds*fraction
        }
        return total
    }
    private static func valid(_ date:Date)->Bool {date.timeIntervalSince1970.isFinite && abs(date.timeIntervalSince1970)<10_000_000_000}
}
