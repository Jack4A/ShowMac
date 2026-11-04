import Foundation

public enum SensorCategory:String,CaseIterable,Identifiable,Codable {
    case cpu="CPU",gpu="GPU",storage="存储",battery="电池",other="其他"
    public var id:String { rawValue }
    public static func category(for key:String,platform:SensorNamingPlatform = .current)->Self {
        if key.hasPrefix("TC") { return .cpu }
        if key.hasPrefix("TG") { return .gpu }
        if key.hasPrefix("TH") { return .storage }
        if key.hasPrefix("TB") { return .battery }
        let probe=HardwareSensorReading(key:key,label:key,kind:.temperature,value:nil)
        switch SensorCatalog.meaning(probe,platform:platform)?.component {
        case .cpu:return .cpu
        case .gpu:return .gpu
        default:break
        }
        return .other
    }
}

public struct CPUCounters: Equatable {
    public var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user=user; self.system=system; self.idle=idle; self.nice=nice
    }
    public func usage(since old: Self) -> Double? {
        let busy = UInt64(user &- old.user) + UInt64(system &- old.system) + UInt64(nice &- old.nice)
        let total = busy + UInt64(idle &- old.idle)
        return total > 0 ? 100 * Double(busy) / Double(total) : nil
    }
}
public struct SensorReading: Codable, Identifiable {
    public let key: String
    public let label: String
    public let celsius: Double
    public init(key:String,label:String,celsius:Double) { self.key=key;self.label=label;self.celsius=celsius }
    public var id: String { key }
    public var category:SensorCategory { SensorCategory.category(for:key) }
}
public struct FanReading: Codable, Identifiable {
    public let id: Int
    public let rpm: Double?
    public let minimum: Double?
    public let maximum: Double?
    public let manual: Bool?
    public let controllable: Bool
    public init(id:Int,rpm:Double?,minimum:Double?,maximum:Double?,manual:Bool?,controllable:Bool) {
        self.id=id;self.rpm=rpm;self.minimum=minimum;self.maximum=maximum;self.manual=manual;self.controllable=controllable
    }
}
public enum TurboState: String, Codable {
    case disabledDriverLoaded, driverNotLoaded, unknown, unsupported
    public var title: String {
        switch self {
        case .disabledDriverLoaded: return "禁用驱动已加载"
        case .driverNotLoaded: return "禁用驱动未加载"
        case .unknown: return "状态无法读取"
        case .unsupported: return "不支持此处理器"
        }
    }
}
public enum MemoryPressure:Int,Codable {case normal=1,warning=2,critical=4
    public var title:String {switch self {case .normal:return "正常";case .warning:return "偏高";case .critical:return "严重"}}
}
public struct Snapshot: Codable, Identifiable {
    public let date: Date
    public let cpuUsage: Double?
    public let sensors: [SensorReading]
    public let fans: [FanReading]
    public let speedLimit: Int?
    public let schedulerLimit: Int?
    public let availableCPUs: Int?
    public let totalCPUs: Int
    public let thermalState: Int
    public let thermalWarning: Int?
    public let turbo: TurboState
    public let acPower: Bool?
    public let lowPower: Bool
    public let smcAvailable: Bool
    public let memoryPressure:MemoryPressure?
    public let additionalSensors:[HardwareSensorReading]?
    public init(date:Date,cpuUsage:Double?,sensors:[SensorReading],fans:[FanReading],speedLimit:Int?,schedulerLimit:Int?,availableCPUs:Int?,totalCPUs:Int,thermalState:Int,thermalWarning:Int?,turbo:TurboState,acPower:Bool?,lowPower:Bool,smcAvailable:Bool,memoryPressure:MemoryPressure?=nil,additionalSensors:[HardwareSensorReading]?=nil) {
        self.date=date;self.cpuUsage=cpuUsage;self.sensors=sensors;self.fans=fans
        self.speedLimit=speedLimit;self.schedulerLimit=schedulerLimit;self.availableCPUs=availableCPUs;self.totalCPUs=totalCPUs
        self.thermalState=thermalState;self.thermalWarning=thermalWarning;self.turbo=turbo;self.acPower=acPower;self.lowPower=lowPower;self.smcAvailable=smcAvailable
        self.memoryPressure=memoryPressure
        self.additionalSensors=additionalSensors
    }
    public var id: Date { date }
    public var cpuTemperature: Double? { temperature(.cpu) }
    public func temperature(_ category:SensorCategory,platform:SensorNamingPlatform = .current)->Double? {
        sensors.filter { SensorCategory.category(for:$0.key,platform:platform)==category }
            .compactMap { HardwareSensorKind.temperature.valid($0.celsius) }.max()
    }
    public var limited: Bool {
        speedLimit.map { $0 < 100 } == true || schedulerLimit.map { $0 < 100 } == true ||
        availableCPUs.map { $0 < totalCPUs } == true
    }
    public var limitKnown: Bool { speedLimit != nil && schedulerLimit != nil && availableCPUs != nil }
    public var limitTitle: String { limited ? "系统正在限制性能" : (limitKnown ? "未检测到系统限速" : "限速信息不完整") }
    public var thermalTitle: String {
        switch thermalState { case 0: return "正常"; case 1: return "升温"; case 2: return "较高"; case 3: return "严重"; default: return "未知" }
    }
    public var assessment: String {
        let hasWarning=thermalWarning.map { [5,10,100,110].contains($0) } == true
        if limited && ((2...3).contains(thermalState) || hasWarning) {
            return "系统性能上限下降，同时存在热压力信号；温控可能参与了限制。无法仅凭这些指标确定具体进程或硬件原因。"
        }
        if limited { return "系统报告了性能限制，但没有足够的热压力证据。供电、传感器或其他平台策略仍需排查，不能据此认定为过热或挖矿。" }
        if !limitKnown { return "系统未提供完整限速数据，缺失值不能当作正常。" }
        return "目前没有检测到系统上限下降。睿频禁用状态单独显示；100% 上限不代表睿频一定开启。"
    }
}

public enum ScopeError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(s)=self { return s }; return nil }
}

public enum Export {
    public static func csv(_ samples: [Snapshot]) -> String {
        let iso=ISO8601DateFormatter()
        var lines=["timestamp,cpu_percent,cpu_temperature_c,speed_limit_percent,scheduler_limit_percent,available_cpus,total_cpus,thermal_state,thermal_warning,turbo_driver,ac_power,low_power,fan0_rpm,fan1_rpm"]
        func number(_ x: Double?) -> String { x.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "" }
        func integer(_ x: Int?) -> String { x.map { String($0) } ?? "" }
        for s in samples {
            var fields:[String]=[iso.string(from:s.date),number(s.cpuUsage),number(s.cpuTemperature)]
            fields += [integer(s.speedLimit),integer(s.schedulerLimit),integer(s.availableCPUs)]
            fields += [String(s.totalCPUs),String(s.thermalState),integer(s.thermalWarning),s.turbo.rawValue]
            fields.append(s.acPower.map { $0 ? "1":"0" } ?? "")
            fields.append(s.lowPower ? "1":"0")
            fields.append(number(s.fans.first { $0.id==0 }?.rpm))
            fields.append(number(s.fans.first { $0.id==1 }?.rpm))
            lines.append(fields.joined(separator:","))
        }
        return lines.joined(separator:"\n")+"\n"
    }
}
