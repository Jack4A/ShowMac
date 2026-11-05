import Foundation
import SwiftUI
import ThermalCore

/// Retains confirmed helper telemetry without invalidating offscreen views.
@MainActor final class FanControlReadings:ObservableObject {
    @Published private(set) var revision=0
    private(set) var status:FanSessionStatus?
    private var receivedAt:TimeInterval=0
    func update(_ status:FanSessionStatus?,at uptime:TimeInterval=ProcessInfo.processInfo.systemUptime,publish:Bool=true) {
        self.status=status;receivedAt=uptime
        if publish {resumeVisualUpdates()}
    }
    func remaining(at uptime:TimeInterval=ProcessInfo.processInfo.systemUptime)->Double? {
        guard status?.continuous != true else{return nil}
        guard let seconds=status?.remainingSeconds,seconds.isFinite,seconds>=0,receivedAt.isFinite,uptime.isFinite else{return nil}
        return max(0,seconds-max(0,uptime-receivedAt))
    }
    func resumeVisualUpdates() {revision &+= 1}
}

extension AppModel {
    var systemFansAutomatic:Bool {
        coolingToken==nil && snapshot.map{!$0.fans.isEmpty && $0.fans.allSatisfy{$0.manual==false}}==true
    }
    var systemFanHeatWarning:Bool {
        systemFansAutomatic && snapshot.map{CurvePolicy.highTemperatureWithLowFanSpeed($0)}==true
    }
    var activeFanStrategy:FanStrategy? {
        if systemFansAutomatic {return .system}
        guard activeProfile != nil,let curve=sessionCurve else{return nil}
        if activeFanSceneID != nil {return .custom}
        if controlName=="指定转速" || controlName=="手动转速" {return .custom}
        if controlName=="自定义曲线" {return .custom}
        if let preset=FanStrategy.presets.first(where:{$0.curve==curve}) {return preset}
        return .custom
    }
    var fanStrategyTitle:String {
        if let scene=activeFanScene {return scene.name}
        if let activeFanStrategy {return activeFanStrategy.title}
        if coolingToken != nil {return "等待硬件状态确认"}
        return "外部控制或状态未知"
    }
    func applyFanStrategy(_ strategy:FanStrategy) {
        fanRestorePending=false
        switch strategy {
        case .system:restoreAuto()
        case .custom:applyCustomCurve()
        default:applyFanCurve(strategy.curve!,name:strategy.title,selection:.strategy(strategy))
        }
    }
}
