import SwiftUI
import ThermalCore

enum MetricKind:String,Identifiable,CaseIterable,Codable {
    case cpuTemperature,gpuTemperature,storageTemperature,cpuUsage,memory,fan,battery
    var id:String {rawValue}
    var title:String {switch self {case .cpuTemperature:return "CPU 温度";case .gpuTemperature:return "GPU 温度";case .storageTemperature:return "存储温度";case .cpuUsage:return "CPU 使用率";case .memory:return "内存";case .fan:return "风扇转速";case .battery:return "电池"}}
    var sensor:SensorCategory? {switch self {case .cpuTemperature:return .cpu;case .gpuTemperature:return .gpu;case .storageTemperature:return .storage;default:return nil}}
    var unit:String {self == .fan ? " RPM":(sensor != nil ? "°C":"%")}
    var fixedUpper:Double {self == .fan ? 6000:(sensor != nil ? 130:100)}
}
@MainActor final class MetricHistoryStore:ObservableObject {
    @Published private(set) var revision=0
    private(set) var end=Date()
    private var histories:[MetricKind:MetricHistory]=[:]
    private var latestRecordDate:Date?
    func record(_ sample:Snapshot,telemetry:SystemTelemetry?,publish:Bool=true) {
        guard sample.date.timeIntervalSince1970.isFinite else{return}
        let telemetryDate=telemetry?.date.timeIntervalSince1970.isFinite == true ? telemetry!.date:sample.date
        end=max(latestRecordDate ?? sample.date,max(sample.date,telemetryDate))
        latestRecordDate=end
        append(.cpuUsage,value:sample.cpuUsage.flatMap{$0<=100 ? $0:nil},date:sample.date)
        append(.fan,value:sample.fans.compactMap(\.rpm).max(),date:sample.date)
        for kind in [MetricKind.cpuTemperature,.gpuTemperature,.storageTemperature] {
            append(kind,value:sample.temperature(kind.sensor!),date:sample.date)
        }
        if let telemetry {
            append(.memory,value:telemetry.memoryPercent.flatMap{$0<=100 ? $0:nil},date:telemetry.date)
            append(.battery,value:telemetry.batteryPercent.flatMap{$0<=100 ? $0:nil},date:telemetry.date)
        }
        if publish {resumeVisualUpdates()}
    }
    func resumeVisualUpdates(){revision &+= 1}
    private func append(_ kind:MetricKind,value:Double?,date:Date) {
        var history=histories[kind] ?? MetricHistory(maximumGap:kind == .memory || kind == .battery ? 35:15);history.append(value,at:date);histories[kind]=history
    }
    func points(_ kind:MetricKind,minutes:Int)->[MetricPoint] {histories[kind]?.window(ending:end,seconds:Double(minutes)*60) ?? []}
    var menuCPU:[MetricPoint] {histories[.cpuUsage]?.window(ending:end,seconds:120) ?? []}
}
