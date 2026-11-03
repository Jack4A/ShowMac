import Foundation
import Combine
import ThermalCore

/// Isolated fixtures: verifies deferring view invalidation never pauses history collection.
enum HiddenViewUpdateCheck {
    @MainActor static func run() {
        let readings=LiveReadings(),history=MetricHistoryStore(),sensors=SensorHistoryStore(),timeline=TemperatureTimelineStore(),fans=FanControlReadings()
        var notifications=0
        let subscriptions=[readings.objectWillChange.sink{notifications+=1},history.objectWillChange.sink{notifications+=1},sensors.objectWillChange.sink{notifications+=1},timeline.objectWillChange.sink{notifications+=1},fans.objectWillChange.sink{notifications+=1}]
        for i in 0..<120 {
            let sample=Snapshot(date:Date(timeIntervalSince1970:10_000+Double(i*5)),cpuUsage:Double(i%100),sensors:[SensorReading(key:"TC0P",label:"CPU",celsius:Double(40+i%40))],fans:[],speedLimit:100,schedulerLimit:100,availableCPUs:4,totalCPUs:4,thermalState:0,thermalWarning:nil,turbo:.driverNotLoaded,acPower:true,lowPower:false,smcAvailable:true)
            fans.update(FanSessionStatus(remainingSeconds:1800-Double(i*5),targets:[FanTarget(id:0,rpm:2000)],protectionActive:false),at:Double(i*5),publish:false)
            readings.update(sample,publish:false);history.record(sample,telemetry:nil,publish:false);sensors.record(sample,menuSensors:[MenuSensorReference(key:"TC0P",kind:.temperature)],publish:false);timeline.append(sample,mode:"system",publish:false)
        }
        guard notifications==0,readings.snapshot?.cpuUsage==19,history.points(.cpuUsage,minutes:10).count==120,history.points(.cpuUsage,minutes:10).last?.value==19,history.end==readings.snapshot?.date,timeline.points.isEmpty else{print("Hidden collection failed");exit(2)}
        guard sensors.points(for:"cpu",minutes:10).count==120,sensors.points(for:"cpu",minutes:10).last?.value==79 else{print("Hidden sensor collection failed");exit(5)}
        guard sensors.menuPoints(for:MenuSensorReference(key:"TC0P",kind:.temperature)).count==25,sensors.menuPoints(for:MenuSensorReference(key:"TC0P",kind:.temperature)).last?.value==79 else{print("Hidden menu sensor collection failed");exit(6)}
        readings.resumeVisualUpdates();history.resumeVisualUpdates();sensors.resumeVisualUpdates();timeline.resumeVisualUpdates();fans.resumeVisualUpdates()
        guard notifications==5,sensors.revision==1,fans.remaining(at:600)==1200,fans.status?.targets.first?.rpm==2000,history.revision==1,timeline.fullPoints.count==120,timeline.latest==79,timeline.end==history.end else{print("Visible catch-up failed");exit(3)}
        fans.update(nil,at:600,publish:false)
        guard fans.remaining(at:600)==nil,fans.status==nil,notifications==5 else{print("Fan session clearing failed");exit(4)}
        withExtendedLifetime(subscriptions){}
        print("PASS: 120 hidden samples retained without view notifications; common sensor histories, readings, timeline and fan telemetry catch up once.")
    }
}
