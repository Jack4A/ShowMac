import SwiftUI

/// App-owned opaque surfaces prevent wallpaper and OS material changes altering the theme.
struct ConsoleWindowBackdrop:View {
    var body:some View {ConsoleSidebarBackdrop().ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)}
}

struct ConsoleSidebarBackdrop:View {
    var body:some View {
        LinearGradient(gradient:Gradient(colors:[Palette.sidebarTop,Palette.sidebarBottom]),startPoint:.top,endPoint:.bottom)
    }
}

struct ConsoleDetailCorners:ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content:Content)->some View {
        content.appBackground {
            LinearGradient(gradient:Gradient(colors:[Palette.detailTop,Palette.canvas]),startPoint:.topLeading,endPoint:.bottomTrailing)
        }
        .clipShape(SidebarFacingShape())
        .appOverlay {
            SidebarFacingShape().stroke(Palette.sidebarEdge.opacity(contrast == .increased ? 1:(scheme == .dark ? 0.7:0.5)),lineWidth:contrast == .increased ? 1:0.75)
                .appMask(alignment:.leading) {Rectangle().frame(width:24)}
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

private struct SidebarFacingShape:Shape {
    func path(in rect:CGRect)->Path {
        var path=RoundedRectangle(cornerRadius:18,style:.continuous).path(in:rect)
        path.addRect(CGRect(x:rect.midX,y:rect.minY,width:rect.width/2,height:rect.height))
        return path
    }
}
