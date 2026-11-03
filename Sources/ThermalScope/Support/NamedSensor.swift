import Foundation
import ThermalCore

/// The inventory and menu bar share names; stable hardware IDs stay separate from labels.
struct NamedSensor:Identifiable {
    let reading:HardwareSensorReading
    let meaning:SensorMeaning?
    let ordinal:Int
    var id:String {reading.id}
    var component:SensorComponent {meaning?.component ?? .unknown}
    var title:String {
        if reading.kind == .fan {return localizedFanTitle(reading.key)}
        guard let meaning else{return String(format:L("未识别的%@探头 %d"),L(reading.kind.title),ordinal)}
        return L(meaning.title)+(meaning.title.hasSuffix("探头") ? " \(ordinal)":"")
    }
    func matches(_ query:String)->Bool {
        let aliases=component == .cpu ? "CPU":(component == .gpu ? "GPU":"")
        return query.isEmpty || [reading.key,title,L(reading.kind.title),L(component.title),aliases].contains{$0.localizedCaseInsensitiveContains(query)}
    }
    static func rows(_ readings:[HardwareSensorReading],platform:SensorNamingPlatform = .current)->[Self] {
        var ordinals:[String:Int]=[:]
        return readings.map {reading in
            let meaning=SensorCatalog.meaning(reading,platform:platform)
            let group=meaning?.title ?? reading.kind.rawValue
            ordinals[group,default:0]+=1
            return Self(reading:reading,meaning:meaning,ordinal:ordinals[group]!)
        }
    }
}
