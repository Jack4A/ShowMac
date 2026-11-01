import AppKit
import SwiftUI
import ThermalCore

extension CPULoadLevel {
    func nativeColor(normal:NSColor)->NSColor {switch self {case .critical:return .systemRed;case .elevated:return .systemOrange;default:return normal}}
    func plotColor(normal:Color = Palette.violet)->Color {switch self {case .critical:return .red;case .elevated:return .orange;default:return normal}}
    var title:String {switch self {case .critical:return "持续高负载";case .elevated:return "负载偏高";case .normal:return "正常负载";case .unknown:return "未知"}}
}
