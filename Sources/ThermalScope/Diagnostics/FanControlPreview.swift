import Foundation
import ThermalCore

/// Only constructed by the explicit --ui-check entry point. No privileged requests.
@MainActor final class FanControlPreview {
    private let scenario=ProcessInfo.processInfo.environment["THERMALSCOPE_PREVIEW_FAN_STATE"] ?? "system"
    private(set) var curve:FanCurve?
    private var label=""
    private var token:String?
    private var deadline:TimeInterval=0
    private var lastSample:Snapshot?
    init() {
        if ["active","protection","expiry"].contains(scenario) {
            curve = .balanced;label="均衡";token=UUID().uuidString
            deadline=ProcessInfo.processInfo.systemUptime+(scenario=="expiry" ? 12:1800)
        }
    }
    private func expire() {
        if token != nil,ProcessInfo.processInfo.systemUptime>=deadline {curve=nil;token=nil}
    }
    func decorate(_ source:Snapshot)->Snapshot {
        expire()
        let sensors=scenario=="unavailable" ? []:(scenario=="protection" ? [SensorReading(key:"TC0P",label:"CPU",celsius:95)]:source.sensors)
        let baseFans: [FanReading]
        if scenario=="multi" {
            baseFans=[FanReading(id:0,rpm:1000,minimum:1000,maximum:4900,manual:false,controllable:true),FanReading(id:1,rpm:1500,minimum:1500,maximum:6000,manual:false,controllable:true)]
        } else {baseFans=scenario=="unavailable" ? []:source.fans}
        let temperature=sensors.filter{$0.category == .cpu || $0.category == .gpu}.map(\.celsius).max() ?? 60
        let percent=curve.map{scenario=="protection" ? 100:$0.percent(at:temperature)}
        let fans=baseFans.map {fan in
            let target=percent.flatMap{percent in fan.minimum.flatMap{low in fan.maximum.map{CurvePolicy.rpm(percent:percent,minimum:low,maximum:$0)}}}
            return FanReading(id:fan.id,rpm:target ?? fan.rpm,minimum:fan.minimum,maximum:fan.maximum,manual:token != nil,controllable:fan.controllable)
        }
        let sample=Snapshot(date:source.date,cpuUsage:source.cpuUsage,sensors:sensors,fans:fans,speedLimit:source.speedLimit,schedulerLimit:source.schedulerLimit,availableCPUs:source.availableCPUs,totalCPUs:source.totalCPUs,thermalState:source.thermalState,thermalWarning:source.thermalWarning,turbo:source.turbo,acPower:source.acPower,lowPower:source.lowPower,smcAvailable:source.smcAvailable,memoryPressure:source.memoryPressure,additionalSensors:scenario=="unavailable" ? []:source.additionalSensors)
        lastSample=sample;return sample
    }
    func status()->ControlReply {
        expire()
        let seconds=deadline.isFinite ? max(0,deadline-ProcessInfo.processInfo.systemUptime):0
        let targets=(lastSample?.fans ?? []).compactMap {fan -> FanTarget? in
            guard let curve,let low=fan.minimum,let high=fan.maximum,let sample=lastSample,let temperature=curve.sensor.temperature(in:sample) else{return nil}
            return FanTarget(id:fan.id,rpm:CurvePolicy.rpm(percent:CurvePolicy.requiresMaximum(sample) ? 100:curve.percent(at:temperature),minimum:low,maximum:high))
        }
        return ControlReply(ok:true,message:token==nil ? "模拟：风扇由系统管理":"模拟：策略已确认生效",session:token,profile:token==nil ? nil:"custom",label:token==nil ? nil:label,fanStatus:token==nil ? nil:FanSessionStatus(remainingSeconds:seconds,targets:targets,protectionActive:scenario=="protection",continuous:deadline.isInfinite))
    }
    func handle(_ request:ControlRequest)throws->ControlReply {
        try request.validate()
        if scenario=="failure",request.command != "auto" {throw ScopeError.message("界面模拟：目标转速回读不一致，未确认控制生效。")}
        switch request.command {
        case "auto","shutdown":curve=nil;token=nil
        case "profile":
            guard request.profile=="custom",let next=request.curve else{throw ScopeError.message("界面模拟不执行此控制命令")}
            curve=next;label=request.label ?? "自定义曲线";token=UUID().uuidString;deadline=request.continuous==true ? .infinity:ProcessInfo.processInfo.systemUptime+(request.duration ?? 1800)
        case "test-fans":curve = .manual(percent:100);label="风扇验证";token=UUID().uuidString;deadline=ProcessInfo.processInfo.systemUptime+5
        default:throw ScopeError.message("界面模拟不执行此控制命令")
        }
        return status()
    }
}
