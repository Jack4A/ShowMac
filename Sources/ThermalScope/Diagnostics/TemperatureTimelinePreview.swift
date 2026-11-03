import Foundation
import ThermalCore

/// Reproduce densely spaced mode changes without requesting any hardware controls.
enum TemperatureTimelinePreview {
    static func samples()->[TimelineSample]? {
        guard CommandLine.arguments.contains("--ui-check"),ProcessInfo.processInfo.environment["THERMALSCOPE_PREVIEW_TIMELINE"]=="dense" else{return nil}
        let start=Date().addingTimeInterval(-600),modes=["系统自动","安静优先","自定义曲线","均衡"]
        return (0..<120).map {index in
            let mode=index<104 ? modes[0]:modes[(index-104)%modes.count]
            let temperature=Double(index<25 ? 68+index%9:50+index%7)
            let sample=Snapshot(date:start.addingTimeInterval(Double(index*5)),cpuUsage:20,sensors:[SensorReading(key:"TC0P",label:"CPU",celsius:temperature)],fans:[],speedLimit:100,schedulerLimit:100,availableCPUs:8,totalCPUs:8,thermalState:0,thermalWarning:nil,turbo:.unsupported,acPower:true,lowPower:false,smcAvailable:true)
            return TimelineSample(sample,mode:mode)
        }
    }
}
