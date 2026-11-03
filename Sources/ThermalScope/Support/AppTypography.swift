import SwiftUI

enum AppTypography {
    static let title=Font.system(size:25,weight:.bold)
    static let section=Font.system(size:14,weight:.semibold)
    static let body=Font.system(size:13)
    static let caption=Font.system(size:12)
    static let sidebar=Font.system(size:13,weight:.medium)
    static func number(_ size:CGFloat,weight:Font.Weight = .medium)->Font {
        .system(size:size,weight:weight)
    }
}
