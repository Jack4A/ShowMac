import Foundation
import Combine
import ThermalCore

/// Isolated fixtures: verifies deferring view invalidation never pauses history collection.
enum HiddenViewUpdateCheck {
    @MainActor static func run() {
        let readings=LiveReadings(),history=MetricHistoryStore(),timeline=TemperatureTimelineStore()
        var notifications=0
        let subscriptions=[readings.objectWillChange.sink{notifications+=1},history.objectWillChange.sink{notifications+=1},timeline.objectWillChange.sink{notifications+=1}]
        for i in 0..<120 {
            let sample=Snapshot(date:Date(timeIntervalSince1970:10_000+Double(i*5)),cpuUsage:Double(i%100),sensors:[SensorReading(key:"TC0P",label:"CPU",celsius:Double(40+i%40))],fans:[],speedLimit:100,schedulerLimit:100,availableCPUs:4,totalCPUs:4,thermalState:0,thermalWarning:nil,turbo:.driverNotLoaded,acPower:true,lowPower:false,smcAvailable:true)
            readings.update(sample,publish:false);history.record(sample,telemetry:nil,publish:false);timeline.append(sample,mode:"system",publish:false)
        }
        guard notifications==0,readings.snapshot?.cpuUsage==19,history.points(.cpuUsage,minutes:10).count==120,history.points(.cpuUsage,minutes:10).last?.value==19,history.end==readings.snapshot?.date,timeline.points.isEmpty else{print("Hidden collection failed");exit(2)}
        readings.resumeVisualUpdates();history.resumeVisualUpdates();timeline.resumeVisualUpdates()
        guard notifications==3,history.revision==1,timeline.fullPoints.count==120,timeline.latest==79,timeline.end==history.end else{print("Visible catch-up failed");exit(3)}
        withExtendedLifetime(subscriptions){}
        print("PASS: 120 hidden samples retained without view notifications; visible readings and timeline catch up once.")
    }
}
