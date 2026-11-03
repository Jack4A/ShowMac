import SwiftUI
import ThermalCore

@MainActor final class SensorHistoryStore:ObservableObject {
    @Published private(set) var revision=0
    private var history=CommonSensorHistory()
    private var menuHistories:[String:MetricHistory]=[:]
    private var menuEnd:Date?
    var readings:[CommonSensorReading] {history.readings}
    var end:Date {history.end ?? Date()}
    func record(_ sample:Snapshot,menuSensors:[MenuSensorReference]=[],publish:Bool=true) {
        history.record(sample,platform:SensorNamingPlatform.current)
        if sample.date.timeIntervalSince1970.isFinite,menuEnd.map({sample.date>$0}) ?? true {
            let selected=Set(menuSensors.filter{!$0.isCommon && $0.isValid})
            let ids=Set(selected.map(\.id))
            menuHistories=menuHistories.filter{ids.contains($0.key)}
            let values=Dictionary(uniqueKeysWithValues:SensorInventory.readings(sample).map{($0.id,$0)})
            for sensor in selected {
                var series=menuHistories[sensor.id] ?? MetricHistory(allowsNegativeValues:sensor.kind == .power || sensor.kind == .current)
                series.append(values[sensor.id]?.value,at:sample.date)
                menuHistories[sensor.id]=series
            }
            menuEnd=sample.date
        }
        if publish {resumeVisualUpdates()}
    }
    func points(for id:String,minutes:Int)->[MetricPoint] {history.points(for:id,minutes:minutes)}
    func menuPoints(for sensor:MenuSensorReference)->[MetricPoint] {
        points(for:sensor,minutes:2)
    }
    func points(for sensor:MenuSensorReference,minutes:Int)->[MetricPoint] {
        if sensor.isCommon {return history.points(for:sensor.key,minutes:minutes)}
        return menuHistories[sensor.id]?.window(ending:menuEnd ?? end,seconds:Double(max(1,min(30,minutes)))*60) ?? []
    }
    func resumeVisualUpdates(){revision &+= 1}
}
