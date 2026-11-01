import Foundation
import Darwin

public struct WidgetPoint:Codable,Equatable,Sendable {
    public var date:Date
    public var value:Double?
    public var segment:Int
    public init(date:Date,value:Double?,segment:Int){self.date=date;self.value=value.flatMap{$0.isFinite && $0>=0 ? $0:nil};self.segment=segment}
}
public struct WidgetFan:Codable,Equatable,Sendable {
    public var id:Int
    public var rpm:Double?
    public var maximum:Double?
    public var manual:Bool?
    public init(id:Int,rpm:Double?,maximum:Double?,manual:Bool?){self.id=id;self.rpm=Self.valid(rpm);self.maximum=Self.valid(maximum);self.manual=manual}
    private static func valid(_ n:Double?)->Double? {n.flatMap{$0.isFinite && (0...30000).contains($0) ? $0:nil}}
}
public enum WidgetMetric:String,CaseIterable,Codable,Sendable {case cpuTemperature,gpuTemperature,storageTemperature,cpuUsage,fan}
public enum WidgetFreshness:Equatable {case recent,previous,paused,unavailable}
public struct WidgetSnapshot:Codable,Equatable,Sendable {
    public var schema=1
    public var date:Date
    public var cpuTemperature:Double?
    public var gpuTemperature:Double?
    public var storageTemperature:Double?
    public var cpuUsage:Double?
    public var fans:[WidgetFan]
    public var mode:String
    public var turbo:String
    public var language:String
    public var running:Bool
    public var trends:[String:[WidgetPoint]]
    public init(date:Date,cpuTemperature:Double?,gpuTemperature:Double?,storageTemperature:Double?,cpuUsage:Double?,fans:[WidgetFan],mode:String,turbo:String,language:String,running:Bool=true,trends:[String:[WidgetPoint]]=[:]) {
        self.date=date;self.cpuTemperature=Self.value(cpuTemperature,in:0...150);self.gpuTemperature=Self.value(gpuTemperature,in:0...150);self.storageTemperature=Self.value(storageTemperature,in:0...150);self.cpuUsage=Self.value(cpuUsage,in:0...100)
        var ids=Set<Int>()
        self.fans=Array(fans.prefix(64).filter{(0..<32).contains($0.id) && ids.insert($0.id).inserted}.prefix(8));self.mode=String(mode.prefix(100));self.turbo=String(turbo.prefix(100));self.language=String(language.prefix(20));self.running=running
        self.trends=Dictionary(uniqueKeysWithValues:WidgetMetric.allCases.map{kind in (kind.rawValue,Array((trends[kind.rawValue] ?? []).filter{$0.date.timeIntervalSince1970.isFinite && $0.date<=date && $0.date>=date.addingTimeInterval(-300)}.sorted{$0.date<$1.date}.suffix(120)))})
    }
    private static func value(_ n:Double?,in range:ClosedRange<Double>)->Double? {n.flatMap{$0.isFinite && range.contains($0) ? $0:nil}}
    public func value(_ metric:WidgetMetric)->Double? {switch metric {case .cpuTemperature:return cpuTemperature;case .gpuTemperature:return gpuTemperature;case .storageTemperature:return storageTemperature;case .cpuUsage:return cpuUsage;case .fan:return fans.compactMap(\.rpm).max()}}
    public func freshness(at now:Date)->WidgetFreshness {
        let age=now.timeIntervalSince(date)
        guard date.timeIntervalSince1970.isFinite,age>=(-120),age<=86400 else{return .unavailable}
        if !running {return .paused}
        return age<=300 ? .recent:.previous
    }
    public static func decode(_ data:Data)throws->Self {
        guard data.count<=262144 else{throw WidgetDataError.invalid}
        let raw=try JSONDecoder().decode(Self.self,from:data)
        guard raw.schema==1,raw.date.timeIntervalSince1970.isFinite else{throw WidgetDataError.invalid}
        return Self(date:raw.date,cpuTemperature:raw.cpuTemperature,gpuTemperature:raw.gpuTemperature,storageTemperature:raw.storageTemperature,cpuUsage:raw.cpuUsage,fans:raw.fans.map{WidgetFan(id:$0.id,rpm:$0.rpm,maximum:$0.maximum,manual:$0.manual)},mode:raw.mode,turbo:raw.turbo,language:raw.language,running:raw.running,trends:raw.trends.mapValues{$0.map{WidgetPoint(date:$0.date,value:$0.value,segment:$0.segment)}})
    }
}
public enum WidgetDataError:Error {case invalid}
public enum WidgetRoute:Equatable {
    case overview,thermal,metric(WidgetMetric)
    public var url:URL {switch self {case .overview:return URL(string:"thermalscope://overview")!;case .thermal:return URL(string:"thermalscope://thermal")!;case .metric(let kind):return URL(string:"thermalscope://metric/"+kind.rawValue)!}}
    public init?(_ url:URL) {
        guard url.scheme=="thermalscope",url.user==nil,url.password==nil,url.port==nil,url.query==nil,url.fragment==nil else{return nil}
        if url.host=="overview",url.path.isEmpty {self = .overview}
        else if url.host=="thermal",url.path.isEmpty {self = .thermal}
        else if url.host=="metric",let metric=WidgetMetric(rawValue:String(url.path.dropFirst())),url.path=="/"+metric.rawValue {self = .metric(metric)}
        else{return nil}
    }
}
public enum WidgetStorage {
    public static let kind="ThermalScopeStatus"
    public static func url(bundle:Bundle = .main)->URL? {
        if let group=bundle.object(forInfoDictionaryKey:"ThermalScopeAppGroup") as? String,!group.isEmpty {return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group)?.appendingPathComponent("status.json")}
        let home=getpwuid(getuid()).flatMap{$0.pointee.pw_dir}.map{String(cString:$0)} ?? NSHomeDirectory()
        return URL(fileURLWithPath:home,isDirectory:true).appendingPathComponent("Library/Application Support/ThermalScope/WidgetSnapshots/status.json")
    }
    public static func read(from url:URL?=nil)->WidgetSnapshot? {
        guard let target=url ?? self.url(),let data=try? Data(contentsOf:target,options:.mappedIfSafe) else{return nil}
        return try? WidgetSnapshot.decode(data)
    }
    public static func write(_ snapshot:WidgetSnapshot,to url:URL?=nil)throws {
        guard let target=url ?? self.url() else{throw WidgetDataError.invalid}
        let directory=target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let data=try JSONEncoder().encode(snapshot)
        try data.write(to:target,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
    }
}

public struct WidgetPublishDecision:Equatable {public let write:Bool;public let reload:Bool}
/// Coalesces state transitions without dropping the final confirmed-state reload.
public struct WidgetPublishSchedule {
    private var lastWrite=Date.distantPast
    private var lastReload=Date.distantPast
    private var signature:String?
    private var pending=false
    public init(){}
    public mutating func receive(date:Date,state:String)->WidgetPublishDecision {
        guard date.timeIntervalSince1970.isFinite else{return WidgetPublishDecision(write:false,reload:false)}
        let changed=state != signature
        guard changed || date.timeIntervalSince(lastWrite)>=60 else{return WidgetPublishDecision(write:false,reload:false)}
        signature=state;lastWrite=date;pending = pending || changed
        let reload=date.timeIntervalSince(lastReload)>=1800 || (pending && date.timeIntervalSince(lastReload)>=60)
        if reload {lastReload=date;pending=false}
        return WidgetPublishDecision(write:true,reload:reload)
    }
}
