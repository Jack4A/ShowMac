import Foundation
import ThermalCore

/// Explicit UI fixtures only; real runs always use the live, read-only diagnostic engine.
enum DiagnosticPreview {
    private static var scenario:String? {
        guard CommandLine.arguments.contains("--ui-check"),
              let value=ProcessInfo.processInfo.environment["THERMALSCOPE_PREVIEW_DIAGNOSIS"],
              ["sampling","stable","attention","observing","partial"].contains(value) else{return nil}
        return value
    }
    static var isEnabled:Bool {scenario != nil}
    static func report(at date:Date)->DiagnosticReport? {
        guard let scenario else{return nil}
        let partial=scenario=="partial",attention=scenario=="attention",observing=scenario=="observing"
        let seconds=scenario=="sampling" ? 0:60
        let source=DiagnosticSource(id:"diagnosis-preview",name:"Example App",averageCPU:attention ? 180:20,currentCPU:attention ? 150:10,averageDiskRate:observing ? 30*1024*1024:1024*1024,currentDiskRate:observing ? 10*1024*1024:512*1024,diskSeconds:Double(seconds))
        var engine=DiagnosticEngine(),result:DiagnosticReport?
        for elapsed in stride(from:0,through:seconds,by:5) {
            let time=date.addingTimeInterval(Double(elapsed-seconds))
            let sensors=partial ? []:[SensorReading(key:"TC0P",label:"CPU",celsius:observing ? 82:60),SensorReading(key:"TG0P",label:"GPU",celsius:45)]
            let sample=Snapshot(date:time,cpuUsage:partial ? nil:(attention ? 75:20),sensors:sensors,fans:[],speedLimit:partial ? nil:100,schedulerLimit:partial ? nil:100,availableCPUs:partial ? nil:8,totalCPUs:8,thermalState:0,thermalWarning:nil,turbo:.unsupported,acPower:true,lowPower:false,smcAvailable:!partial,memoryPressure:partial ? nil:(attention ? .warning:.normal))
            result=engine.evaluate(DiagnosticInput(snapshot:sample,sources:partial ? []:[source],processSeconds:Double(elapsed),processDate:partial ? nil:time,blockers:partial ? nil:(observing ? 2:0),batteryPercent:80))
        }
        return result
    }
}
