import Foundation

/// Session-only histories for exactly the aggregates shown by the common sensor cards.
/// Keep known cards through a temporary outage, but break their lines at missing samples.
public struct CommonSensorHistory {
    public private(set) var end:Date?
    public var readings:[CommonSensorReading] {order.compactMap{latest[$0]}}
    private var order:[String]=[]
    private var latest:[String:CommonSensorReading]=[:]
    private var histories:[String:MetricHistory]=[:]
    private var lastSeen:[String:Date]=[:]
    public init() {}

    public mutating func record(_ snapshot:Snapshot,platform:SensorNamingPlatform) {
        let date=snapshot.date
        guard date.timeIntervalSince1970.isFinite,end.map({date>$0}) ?? true else{return}
        let rows=SensorCatalog.common(SensorInventory.readings(snapshot),platform:platform)
        let active=Set(rows.map(\.id))
        for row in rows {
            if latest[row.id]==nil {order.append(row.id)}
            latest[row.id]=row;lastSeen[row.id]=date
        }
        for id in order {
            guard let row=latest[id] else{continue}
            if !active.contains(id) {
                latest[id]=CommonSensorReading(id:row.id,title:row.title,explanation:row.explanation,kind:row.kind,value:nil,sources:row.sources)
            }
            var history=histories[id] ?? MetricHistory(allowsNegativeValues:row.kind == .power || row.kind == .current)
            history.append(active.contains(id) ? row.value:nil,at:date)
            histories[id]=history
        }
        let expired=order.filter{date.timeIntervalSince(lastSeen[$0] ?? date)>1800}
        for id in expired {latest[id]=nil;histories[id]=nil;lastSeen[id]=nil}
        if !expired.isEmpty {order.removeAll{latest[$0]==nil}}
        end=date
    }

    public func points(for id:String,minutes:Int)->[MetricPoint] {
        guard let end else{return []}
        return histories[id]?.window(ending:end,seconds:Double(max(1,min(30,minutes)))*60) ?? []
    }
}
