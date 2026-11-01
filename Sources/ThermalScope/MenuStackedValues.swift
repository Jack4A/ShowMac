import AppKit
import SwiftUI

/// Shared by the actual status item and preferences. Template pixels follow macOS contrast.
enum MenuStackedValues {
    static func image(_ values:[(String,String)],appearance:NSAppearance?=nil)->NSImage {
        let labelFont=NSFont.systemFont(ofSize:7.5,weight:.semibold)
        let valueFont=NSFont.monospacedDigitSystemFont(ofSize:10.5,weight:.medium)
        let foreground:NSColor=appearance.map{$0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor.white:NSColor.black} ?? .labelColor
        let labelAttributes:[NSAttributedString.Key:Any]=[.font:labelFont,.foregroundColor:foreground]
        let valueAttributes:[NSAttributedString.Key:Any]=[.font:valueFont,.foregroundColor:foreground]
        let widths=values.map{max(($0.0 as NSString).size(withAttributes:labelAttributes).width,($0.1 as NSString).size(withAttributes:valueAttributes).width).rounded(.up)}
        let width=max(1,widths.reduce(0,+)+Double(max(0,values.count-1))*8)
        let image=NSImage(size:NSSize(width:width,height:22),flipped:false) {_ in
            var x:CGFloat=0
            for (index,value) in values.enumerated() {
                let label=value.0 as NSString,number=value.1 as NSString
                label.draw(at:NSPoint(x:x+(widths[index]-label.size(withAttributes:labelAttributes).width)/2,y:12),withAttributes:labelAttributes)
                number.draw(at:NSPoint(x:x+(widths[index]-number.size(withAttributes:valueAttributes).width)/2,y:0),withAttributes:valueAttributes)
                x+=widths[index]+8
            }
            return true
        }
        image.isTemplate=true
        image.accessibilityDescription=values.map{$0.0+" "+$0.1}.joined(separator:", ")
        return image
    }
}
struct MenuStackedPreview:View {
    @ObservedObject var readings:LiveReadings
    let items:[MenuMetric]
    var body:some View {Image(nsImage:MenuStackedValues.image(items.map{($0.shortTitle,$0.value(readings))}))}
}
