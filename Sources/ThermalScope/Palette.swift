import AppKit
import SwiftUI

enum Palette {
    // One set of surfaces and one accent, resolved for the app's appearance.
    private static func adaptive(_ light:(CGFloat,CGFloat,CGFloat),_ dark:(CGFloat,CGFloat,CGFloat))->Color {
        Color(nsColor:NSColor(name:nil,dynamicProvider:{appearance in
            let rgb=appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark:light
            return NSColor(srgbRed:rgb.0,green:rgb.1,blue:rgb.2,alpha:1)
        }))
    }
    static let violet=adaptive((0.43,0.33,0.77),(0.66,0.58,0.96))
    static let action=adaptive((0.43,0.33,0.77),(0.46,0.35,0.77))
    static let canvas=adaptive((0.955,0.953,0.968),(0.092,0.092,0.115))
    static let surface=adaptive((0.992,0.990,0.997),(0.123,0.123,0.149))
    static let sidebarTop=adaptive((0.916,0.907,0.950),(0.133,0.123,0.180))
    static let sidebarBottom=adaptive((0.937,0.930,0.960),(0.100,0.098,0.135))
    static let selection=adaptive((0.844,0.815,0.943),(0.240,0.212,0.345))
    static let border=adaptive((0.865,0.858,0.898),(0.205,0.202,0.248))
    static let highlight=adaptive((1,1,1),(0.24,0.23,0.32))
    static let cool=adaptive((0.22,0.47,0.59),(0.40,0.74,0.86))
    static let base=Color(nsColor:.windowBackgroundColor)
    // Mode series keep distinct, related colors and their existing text labels.
    static func mode(_ name:String)->Color {
        switch name.components(separatedBy:" · ").first ?? name {
        case "系统自动":return violet
        case "性能":return adaptive((0.35,0.37,0.70),(0.48,0.56,0.87))
        case "节能":return adaptive((0.30,0.48,0.60),(0.44,0.69,0.75))
        case "静音":return adaptive((0.59,0.38,0.58),(0.77,0.59,0.74))
        case "手动转速":return adaptive((0.39,0.43,0.54),(0.64,0.69,0.80))
        case "自定义曲线","自定义":return adaptive((0.58,0.37,0.77),(0.78,0.60,0.93))
        case "独立风扇策略":return cool
        default:return .secondary
        }
    }
}
