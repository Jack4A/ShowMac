import Foundation

public struct ModeRecord:Identifiable {
    public let date:Date
    public let mode:String
    public let temperature:Double
    public let load:Double?
    public let segment:Int
    public let elapsed:Double
    public var turboDisabled:Bool?=nil
    public var id:Date { date }
    public var series:String { "\(mode)-\(segment)" }
}
public struct ModeHistory {
    public private(set) var records:[ModeRecord]=[]
    private var lastMode:String?
    private var lastSession:String?
    private var lastDate:Date?
    private var origin=Date()
    private var segment=0
    public init() {}
    public mutating func append(date:Date,mode:String?,session:String?,temperature:Double?,load:Double?) {
        records.removeAll { $0.date<date.addingTimeInterval(-1800) }
        guard let mode,let temperature,temperature.isFinite else { lastMode=nil;lastDate=nil;return }
        if lastMode != mode || lastSession != session || lastDate.map({date.timeIntervalSince($0)>15 || date <= $0}) != false {
            segment+=1;origin=date
        }
        records.append(ModeRecord(date:date,mode:mode,temperature:temperature,load:load,segment:segment,elapsed:date.timeIntervalSince(origin)))
        lastMode=mode;lastSession=session;lastDate=date
    }
}
