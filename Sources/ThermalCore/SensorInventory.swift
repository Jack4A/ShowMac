import Foundation

public enum HardwareSensorKind:String,Codable,CaseIterable,Identifiable {
    case fan,temperature,power,voltage,current
    public var id:String {rawValue}
    public var title:String {
        switch self {case .fan:return "风扇";case .temperature:return "温度";case .power:return "功耗";case .voltage:return "电压";case .current:return "电流"}
    }
    public var unit:String {
        switch self {case .fan:return "RPM";case .temperature:return "°C";case .power:return "W";case .voltage:return "V";case .current:return "A"}
    }
    public static func smcKind(key:String,type:UInt32,size:UInt32)->Self? {
        // Only physical scalar formats; integer flags and firmware parameters are not sensors.
        let bytes=[UInt8((type>>24)&255),UInt8((type>>16)&255),UInt8((type>>8)&255),UInt8(type&255)]
        let fixed=String(bytes:bytes,encoding:.ascii) ?? ""
        let isFixed=size==2 && (fixed.hasPrefix("fp") || fixed.hasPrefix("sp"))
        guard (type==0x666c7420 && size==4) || isFixed else{return nil}
        switch key.first {case "T":return .temperature;case "P":return .power;case "V":return .voltage;case "I":return .current;default:return nil}
    }
    public func valid(_ value:Double?)->Double? {
        guard let value,value.isFinite else{return nil}
        switch self {
        case .temperature:return value>0 && value<130 ? value:nil
        case .fan:return (0...20000).contains(value) ? value:nil
        case .voltage:return (0...1000).contains(value) ? value:nil
        case .current:return abs(value)<=1000 ? value:nil
        case .power:return abs(value)<=10000 ? value:nil
        }
    }
}

public struct HardwareSensorReading:Codable,Identifiable {
    public let key:String
    public let label:String
    public let kind:HardwareSensorKind
    public let value:Double?
    public var id:String {kind.rawValue+":"+key}
    public init(key:String,label:String,kind:HardwareSensorKind,value:Double?) {
        self.key=key;self.label=label;self.kind=kind;self.value=kind.valid(value)
    }
}

public enum SensorInventory {
    /// One row per actual sensor, with no display cap or fabricated physical component names.
    public static func readings(_ snapshot:Snapshot)->[HardwareSensorReading] {
        var result=snapshot.sensors.map {reading in
            HardwareSensorReading(key:reading.key,label:reading.label,kind:.temperature,value:reading.celsius)
        }
        result += snapshot.additionalSensors ?? []
        result += snapshot.fans.map {fan in
            HardwareSensorReading(key:"F\(fan.id)Ac",label:"风扇 \(fan.id+1)",kind:.fan,value:fan.rpm)
        }
        var seen=Set<String>()
        return result.filter{seen.insert($0.id).inserted}.sorted{$0.key.localizedStandardCompare($1.key) == .orderedAscending}
    }
}
