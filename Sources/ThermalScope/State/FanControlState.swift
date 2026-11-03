import Foundation
import SwiftUI
import ThermalCore

enum FanStrategy:String,CaseIterable,Identifiable {
    case system,quiet,balanced,cooling,custom
    var id:String {rawValue}
    static let presets:[Self]=[.system,.quiet,.balanced,.cooling]
    var title:String {
        switch self {
        case .system:return "系统自动"
        case .quiet:return "安静优先"
        case .balanced:return "均衡"
        case .cooling:return "散热优先"
        case .custom:return "自定义曲线"
        }
    }
    var shortTitle:String {
        switch self {case .system:return "自动";case .quiet:return "安静";case .balanced:return "均衡";case .cooling:return "强劲";case .custom:return "自定义"}
    }
    var curve:FanCurve? {
        switch self {case .quiet:return .quiet;case .balanced:return .balanced;case .cooling:return .performance;default:return nil}
    }
    var explanation:String {
        switch self {
        case .system:return "由 macOS 决定转速，不使用应用曲线"
        case .quiet:return "优先降低风扇噪声"
        case .balanced:return "兼顾温度与噪声"
        case .cooling:return "提前提高风扇转速"
        case .custom:return "使用已保存的温度曲线"
        }
    }
}

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
        if controlName=="指定转速" || controlName=="手动转速" {return .custom}
        if controlName=="自定义曲线" {return .custom}
        if let preset=FanStrategy.presets.first(where:{$0.curve==curve}) {return preset}
        return .custom
    }
    var fanStrategyTitle:String {
        if let activeFanStrategy {return activeFanStrategy.title}
        if coolingToken != nil {return "等待硬件状态确认"}
        return "外部控制或状态未知"
    }
    func applyFanStrategy(_ strategy:FanStrategy) {
        switch strategy {
        case .system:restoreAuto()
        case .custom:applyCustomCurve()
        default:applyFanCurve(strategy.curve!,name:strategy.title)
        }
    }
}
