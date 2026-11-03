import Foundation
import ThermalCore

/// Keeps independent fan controls separate from Intel-only performance policies.
enum ControlAvailability {
    static var isAppleSilicon:Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}

extension ControlAvailability {
    static func fansAvailable(_ sample:Snapshot?)->Bool {
        guard let sample,!sample.fans.isEmpty,sample.cpuTemperature != nil else{return false}
        return sample.fans.allSatisfy {$0.controllable && $0.minimum != nil && $0.maximum != nil}
    }
}
