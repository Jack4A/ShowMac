import Foundation

public enum RecordedTurboMode:String,CaseIterable,Identifiable {
    case on="开启睿频",off="关闭睿频"
    public var id:String { rawValue }
    public init?(_ state:TurboState) {
        switch state { case .driverNotLoaded:self = .on;case .disabledDriverLoaded:self = .off;default:return nil }
    }
}
public struct TemperaturePoint:Identifiable {
    public let date:Date
    public let elapsed:Double
    public let celsius:Double
    public let cpuLoad:Double?
    public let mode:RecordedTurboMode
    public let segment:Int
    public var id:String { "\(segment)-\(date.timeIntervalSince1970)" }
    public var series:String { "\(mode.rawValue)-\(segment)" }
}
public struct TurboTransition:Identifiable {
    public let date:Date
    public let mode:RecordedTurboMode
    public var id:Date { date }
}
public struct TemperatureSummary {
    public let count:Int
    public let average:Double?
    public let maximum:Double?
    public let averageLoad:Double?
}
public enum TurboHistory {
    /// A new series starts after a mode change, unknown reading, or sampling gap.
    /// Never connect disjoint sessions, and never invent the missing comparison state.
    public static func points(_ samples:[Snapshot],maximumGap:Double=15)->[TemperaturePoint] {
        var result:[TemperaturePoint]=[]
        var previous:Snapshot?
        var mode:RecordedTurboMode?
        var start:Date?
        var segment=0
        for sample in samples {
            guard let next=RecordedTurboMode(sample.turbo),let temperature=sample.cpuTemperature,temperature.isFinite else {
                previous=nil;mode=nil;start=nil;continue
            }
            let gap=previous.map { sample.date.timeIntervalSince($0.date) }
            if mode != next || gap==nil || gap!>maximumGap || gap!<=0 {
                segment+=1;start=sample.date
            }
            result.append(TemperaturePoint(date:sample.date,elapsed:sample.date.timeIntervalSince(start!),celsius:temperature,cpuLoad:sample.cpuUsage,mode:next,segment:segment))
            previous=sample;mode=next
        }
        return result
    }
    public static func transitions(_ samples:[Snapshot])->[TurboTransition] {
        var result:[TurboTransition]=[];var previous:RecordedTurboMode?
        for sample in samples {
            guard let next=RecordedTurboMode(sample.turbo) else { previous=nil;continue }
            if let old=previous,old != next { result.append(TurboTransition(date:sample.date,mode:next)) }
            previous=next
        }
        return result
    }
    public static func summary(_ points:[TemperaturePoint],mode:RecordedTurboMode)->TemperatureSummary {
        let selected=points.filter { $0.mode==mode }
        let loads=selected.compactMap(\.cpuLoad)
        return TemperatureSummary(count:selected.count,average:selected.isEmpty ? nil:selected.map(\.celsius).reduce(0,+)/Double(selected.count),maximum:selected.map(\.celsius).max(),averageLoad:loads.isEmpty ? nil:loads.reduce(0,+)/Double(loads.count))
    }
}
