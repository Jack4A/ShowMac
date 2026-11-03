import Foundation
import ThermalCore

/// Display colors only. Thresholds mirror the existing CPU/GPU diagnostic bands.
enum MetricWarningBands {
    static func supports(_ kind:MetricKind?)->Bool {kind == .cpuUsage || kind == .cpuTemperature || kind == .gpuTemperature}
    static func kind(commonID:String)->MetricKind? {commonID == "cpu" ? .cpuTemperature:(commonID == "gpu" ? .gpuTemperature:nil)}
    static func kind(sensor:MenuSensorReference)->MetricKind? {
        guard sensor.kind == .temperature else{return nil}
        if sensor.isCommon {return kind(commonID:sensor.key)}
        let reading=HardwareSensorReading(key:sensor.key,label:sensor.key,kind:.temperature,value:nil)
        switch SensorCatalog.meaning(reading,platform:.current)?.component {
        case .cpu:return .cpuTemperature
        case .gpu:return .gpuTemperature
        default:return nil
        }
    }
    static func level(_ value:Double?,kind:MetricKind?)->CPULoadLevel {
        guard supports(kind) else{return .normal}
        if kind == .cpuUsage {return CPULoadBands.baseLevel(value)}
        guard let value,value.isFinite,value>=0 else{return .unknown}
        let warm=kind == .gpuTemperature ? 75.0:80.0,hot=kind == .gpuTemperature ? 85.0:90.0
        return value>=hot ? .critical:(value>=warm ? .elevated:.normal)
    }
    static func samples(_ points:[MetricPoint],kind:MetricKind?)->[CPULoadSample] {
        if kind == .cpuUsage {return CPULoadBands.samples(points)}
        return points.map {CPULoadSample(point:$0,level:$0.date.timeIntervalSince1970.isFinite ? level($0.value,kind:kind):.unknown)}
    }
    static func runs(_ points:[MetricPoint],kind:MetricKind?,enabled:Bool=true,budget:Int=140)->[CPULoadRun] {
        guard enabled,supports(kind) else{return [CPULoadRun(id:0,level:.normal,points:MetricPlot.decimated(points,budget:budget))]}
        return CPULoadBands.runs(samples:samples(points,kind:kind),budget:budget)
    }
    static func current(_ value:Double?,points:[MetricPoint],at date:Date,kind:MetricKind?,enabled:Bool=true)->CPULoadLevel {
        guard enabled else{return .normal}
        return kind == .cpuUsage ? CPULoadBands.current(value,points:points,at:date):level(value,kind:kind)
    }
    static func title(_ level:CPULoadLevel,kind:MetricKind?)->String {
        kind == .cpuUsage ? level.title:(level == .critical ? "高温":"温度偏高")
    }
}
