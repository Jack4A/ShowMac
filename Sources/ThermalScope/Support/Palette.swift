import AppKit
import SwiftUI

enum Palette {
    // Silver surfaces in light mode reserve plum for selection, controls and data.
    private static func adaptive(_ light:(CGFloat,CGFloat,CGFloat),_ dark:(CGFloat,CGFloat,CGFloat))->Color {
        Color(NSColor(name:nil,dynamicProvider:{appearance in
            let rgb=appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark:light
            return NSColor(srgbRed:rgb.0,green:rgb.1,blue:rgb.2,alpha:1)
        }))
    }
    // Readable strokes and links need a lighter plum than selected control fills in dark mode.
    static let violet=adaptive((0.463,0.314,0.659),(0.716,0.640,0.824))
    static let action=Color.accentColor
    static let canvas=adaptive((0.957,0.961,0.969),(0.098,0.094,0.118))
    static let surface=adaptive((1,1,1),(0.145,0.137,0.173))
    static let inset=adaptive((0.925,0.937,0.953),(0.110,0.104,0.130))
    static let sidebarTop=adaptive((0.925,0.933,0.957),(0.129,0.122,0.161))
    static let sidebarBottom=adaptive((0.953,0.957,0.973),(0.129,0.122,0.161))
    static let selection=adaptive((0.933,0.906,0.969),(0.231,0.200,0.294))
    static let border=adaptive((0.851,0.871,0.906),(0.231,0.212,0.271))
    static let highlight=adaptive((1,1,1),(0.24,0.23,0.32))
    static let cool=adaptive((0.337,0.471,0.569),(0.600,0.741,0.831))
    static let secondaryText=Color(NSColor(name:nil,dynamicProvider:{appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? .secondaryLabelColor:native(0x5D6470)
    }))
    static let base=Color(.windowBackgroundColor)
    // Mode series keep distinct, related colors and their existing text labels.
    static func mode(_ name:String)->Color {
        switch name.components(separatedBy:" · ").first ?? name {
        case "系统自动":return violet
        case "均衡":return adaptive((0.365,0.388,0.569),(0.654,0.686,0.839))
        case "性能","散热优先":return cool
        case "节能":return adaptive((0.384,0.502,0.451),(0.635,0.769,0.686))
        case "静音","安静优先":return adaptive((0.337,0.494,0.486),(0.600,0.769,0.729))
        case "手动转速","指定转速":return adaptive((0.39,0.43,0.54),(0.64,0.69,0.80))
        case "自定义曲线","自定义":return adaptive((0.529,0.384,0.616),(0.772,0.659,0.851))
        case "独立风扇策略":return cool
        default:return .secondary
        }
    }
    private static func native(_ hex:UInt32)->NSColor {
        NSColor(srgbRed:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255,alpha:1)
    }
    static func navigationIcon(dark:Bool,selected:Bool)->NSColor {
        native(selected ? (dark ? 0xB7A3D2:0x7650A8):(dark ? 0xAAA4B5:0x8C91A0))
    }
    static func navigationText(dark:Bool,selected:Bool)->NSColor {
        native(selected ? (dark ? 0xF0EDF7:0x503172):(dark ? 0xCAC5D1:0x56606E))
    }
    static func navigationSelection(dark:Bool)->NSColor {native(dark ? 0x3B334B:0xFFFFFF)}
}
