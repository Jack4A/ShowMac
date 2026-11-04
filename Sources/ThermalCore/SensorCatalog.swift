import Foundation
import Darwin

public enum SensorNamingPlatform:Equatable {
    case generic,appleM4,appleM4ProMax
    public static func detect(cpuBrand:String)->Self {
        switch cpuBrand.trimmingCharacters(in:.whitespacesAndNewlines) {
        case "Apple M4":return .appleM4
        case "Apple M4 Pro","Apple M4 Max":return .appleM4ProMax
        default:return .generic
        }
    }
    public static let current:Self = {
        var size=0
        guard sysctlbyname("machdep.cpu.brand_string",nil,&size,nil,0)==0,size>0,size<256 else{return .generic}
        var bytes=[CChar](repeating:0,count:size)
        guard sysctlbyname("machdep.cpu.brand_string",&bytes,&size,nil,0)==0 else{return .generic}
        return detect(cpuBrand:String(cString:bytes))
    }()
}

public enum SensorComponent:String,CaseIterable,Identifiable {
    case cpu,gpu,memory,storage,battery,wireless,fan,power,unknown
    public var id:String {rawValue}
    public var title:String {
        switch self {
        case .cpu:return "处理器";case .gpu:return "图形处理器";case .memory:return "内存"
        case .storage:return "存储";case .battery:return "电池";case .wireless:return "无线网络"
        case .fan:return "风扇";case .power:return "供电";case .unknown:return "用途未识别"
        }
    }
}

public struct SensorMeaning {
    public let component:SensorComponent
    public let title:String
    public let explanation:String
}

public struct CommonSensorReading:Identifiable {
    public let id:String
    public let title:String
    public let explanation:String
    public let kind:HardwareSensorKind
    public let value:Double?
    public let sources:[String]
}

/// Exact component identities shared by display and temperature sources.
/// Unknown or unverified probe IDs remain unclassified.
public enum SensorCatalog {
    // Component identities cross-checked against the referenced SMC catalogs.
    // M4 mappings are deliberately exact and case-sensitive; these are probes, not core counts.
    private static let m4CPU:Set<String>=["Te05","Te0S","Te09","Te0H","Tp01","Tp05","Tp09","Tp0D","Tp0V","Tp0Y","Tp0b","Tp0e"]
    private static let m4GPUShared:Set<String>=["Tg0K","Tg0L","Tg0d","Tg0e","Tg0j","Tg0k"]
    private static let m4Memory:Set<String>=["Tm0p","Tm1p","Tm2p"]
    public static func meaning(_ reading:HardwareSensorReading,platform:SensorNamingPlatform)->SensorMeaning? {
        let key=reading.key
        func named(_ component:SensorComponent,_ title:String,_ explanation:String)->SensorMeaning {
            SensorMeaning(component:component,title:title,explanation:explanation)
        }
        if reading.kind == .fan {return named(.fan,"风扇转速","风扇每分钟实际转动的次数，转速越高通常噪声也越大。")}
        if reading.kind == .temperature {
            if key.hasPrefix("TC") {return named(.cpu,"处理器温度探头","反映处理器内部或附近位置的温度。多个探头不代表多个核心。")}
            if key.hasPrefix("TG") {return named(.gpu,"图形处理器温度探头","反映图形处理器相关位置的温度。")}
            if key.hasPrefix("TH") {return named(.storage,"存储温度探头","反映固态硬盘或存储相关位置的温度。")}
            if key.hasPrefix("TB") {return named(.battery,"电池温度探头","反映电池相关位置的温度。")}
            if key=="TW0P" {return named(.wireless,"无线模块温度","反映无线网络模块附近的温度。")}
            if platform != .generic {
                if m4CPU.contains(key) {return named(.cpu,"处理器温度探头","反映处理器内部或附近位置的温度。多个探头不代表多个核心。")}
                let gpuSpecific:Set<String>=platform == .appleM4 ? ["Tg0G","Tg0H"]:["Tg1U","Tg1k"]
                if m4GPUShared.contains(key) || gpuSpecific.contains(key) {return named(.gpu,"图形处理器温度探头","反映图形处理器相关位置的温度。")}
                if m4Memory.contains(key) {return named(.memory,"内存附近温度探头","反映内存附近的温度，并非内存使用率。")}
            }
        }
        switch (reading.kind,key) {
        case (.power,"PSTR"):return named(.power,"整机功耗","设备内部报告的总功率，单位为瓦；不等同于插座功耗。")
        case (.power,"PDTR"):return named(.power,"直流输入功耗","设备直流输入侧的功率，单位为瓦；不等同于插座功耗。")
        case (.voltage,"VD0R"):return named(.power,"直流输入电压","设备直流输入侧的电压，单位为伏。")
        case (.current,"ID0R"):return named(.power,"直流输入电流","设备直流输入侧的电流，单位为安。")
        case (.power,"PCPC"),(.power,"PCPT"),(.power,"PCTR"),(.power,"PCPR"):
            return named(.cpu,"处理器功耗","处理器相关电路报告的瞬时功率，单位为瓦。")
        case (.power,"PG0C"),(.power,"PG0R"),(.power,"PG1R"):
            return named(.gpu,"图形处理器功耗","图形处理器相关电路报告的瞬时功率，单位为瓦。")
        case (.power,"PMTR"):return named(.memory,"内存功耗","内存相关电路报告的瞬时功率，单位为瓦。")
        default:return nil
        }
    }
    public static func common(_ readings:[HardwareSensorReading],platform:SensorNamingPlatform)->[CommonSensorReading] {
        var result:[CommonSensorReading]=[]
        for component in [SensorComponent.cpu,.gpu,.memory,.storage] {
            let probes=readings.filter{$0.kind == .temperature && meaning($0,platform:platform)?.component==component}
            guard !probes.isEmpty else{continue}
            let title:String
            switch component {case .cpu:title="处理器温度";case .gpu:title="图形处理器温度";case .memory:title="内存附近温度";default:title="存储温度"}
            let explanation:String
            switch component {
            case .cpu:explanation="反映处理器运行时的发热情况。"
            case .gpu:explanation="反映图形处理器运行时的发热情况。"
            case .memory:explanation="内存附近位置的温度，不代表内存占用。"
            default:explanation="反映固态硬盘等存储部件的温度。"
            }
            result.append(CommonSensorReading(id:component.rawValue,title:title,explanation:explanation,kind:.temperature,value:probes.compactMap(\.value).max(),sources:probes.map(\.key)))
        }
        for fan in readings.filter({$0.kind == .fan}) {
            result.append(CommonSensorReading(id:fan.id,title:fan.label,explanation:"风扇每分钟实际转动的次数，转速越高通常噪声也越大。",kind:.fan,value:fan.value,sources:[fan.key]))
        }
        let powers=["PSTR","PDTR"].compactMap {key in readings.first{$0.key==key && $0.kind == .power}}
        if let power=powers.first(where:{$0.value != nil}) ?? powers.first,
           let meaning=meaning(power,platform:platform) {
            result.append(CommonSensorReading(id:power.id,title:meaning.title,explanation:meaning.explanation,kind:.power,value:power.value,sources:[power.key]))
        }
        return result
    }
}
