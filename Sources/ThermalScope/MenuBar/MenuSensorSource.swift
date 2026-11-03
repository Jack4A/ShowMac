import AppKit
import ThermalCore

/// Physical keys, rather than localized labels or positions, identify a menu sensor.
struct MenuSensorReference:Codable,Hashable,Identifiable {
    let key:String
    let kind:HardwareSensorKind
    var isCommon=false
    var id:String {(isCommon ? "common:":"")+kind.rawValue+":"+key}
    var isValid:Bool {
        if isCommon {return kind == .temperature && ["cpu","gpu","memory","storage"].contains(key)}
        return !key.isEmpty && key.utf8.count<=80 && !key.unicodeScalars.contains{CharacterSet.controlCharacters.contains($0)}
    }
    static func hardware(_ reading:HardwareSensorReading)->Self {Self(key:reading.key,kind:reading.kind)}
    static func common(_ reading:CommonSensorReading)->Self {
        if reading.kind == .temperature,["cpu","gpu","memory","storage"].contains(reading.id) {
            return Self(key:reading.id,kind:reading.kind,isCommon:true)
        }
        return Self(key:reading.sources.first ?? "",kind:reading.kind)
    }
    var metric:MenuMetric {kind == .fan ? .fan:(isCommon && key=="gpu" ? .gpu:.temperature)}
    var symbol:String {
        switch kind {
        case .temperature:
            if isCommon {return ["cpu":"cpu","gpu":"display","memory":"memorychip","storage":"internaldrive"][key] ?? "thermometer.medium"}
            return "thermometer.medium"
        case .fan:return "fanblades"
        case .power:return "bolt"
        case .voltage:return "bolt.circle"
        case .current:return "bolt.horizontal.circle"
        }
    }
    var reservedValue:String {
        switch kind {case .temperature:return "100.0 °C";case .fan:return "20000 RPM";case .power:return "-100.00 W";case .voltage:return "12.000 V";case .current:return "-10.000 A"}
    }
    var upper:Double {
        switch kind {case .temperature:return 130;case .fan:return 6000;case .power:return 100;case .voltage:return 12;case .current:return 10}
    }
    var fallbackTitle:String {
        if isCommon {return L(["cpu":"处理器温度","gpu":"图形处理器温度","memory":"内存附近温度","storage":"存储温度"][key] ?? kind.title)}
        if kind == .fan {return localizedFanTitle(key)}
        let reading=HardwareSensorReading(key:key,label:key,kind:kind,value:nil)
        return L(SensorCatalog.meaning(reading,platform:.current)?.title ?? kind.title)+" · "+key
    }
}

enum MenuComponentSource:Hashable {
    case metric(MenuMetric)
    case sensor(MenuSensorReference)
    var metric:MenuMetric {switch self {case .metric(let metric):return metric;case .sensor(let sensor):return sensor.metric}}
    var symbol:String {switch self {case .metric(let metric):return metric.symbol;case .sensor(let sensor):return sensor.symbol}}
    @MainActor func title(in model:AppModel)->String {
        switch self {case .metric(let metric):return metric.title;case .sensor(let sensor):return model.menuSensorOptions.first{$0.reference==sensor}?.title ?? sensor.fallbackTitle}
    }
}

struct MenuSensorOption:Identifiable {
    let reference:MenuSensorReference
    let title:String
    let detail:String
    let value:Double?
    var id:String {reference.id}
}

extension AppModel {
    var menuCommonSensorOptions:[MenuSensorOption] {
        guard let snapshot=readings.snapshot else{return []}
        return SensorCatalog.common(SensorInventory.readings(snapshot),platform:.current).map {
            MenuSensorOption(reference:.common($0),title:commonSensorTitle($0),detail:$0.sources.joined(separator:" · "),value:$0.value)
        }
    }
    var menuHardwareSensorOptions:[MenuSensorOption] {
        guard let snapshot=readings.snapshot else{return []}
        return NamedSensor.rows(SensorInventory.readings(snapshot)).map {
            MenuSensorOption(reference:.hardware($0.reading),title:$0.title,detail:$0.reading.key,value:$0.reading.value)
        }
    }
    var menuSensorOptions:[MenuSensorOption] {menuCommonSensorOptions+menuHardwareSensorOptions}
}
