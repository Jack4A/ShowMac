import SwiftUI

/// One stationary backdrop joins navigation and content; data cards keep their own surfaces.
struct ConsoleWindowBackdrop:View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body:some View {
        GeometryReader {geometry in
            ZStack {
                Palette.canvas
                if scheme == .dark && !reduceTransparency {
                    LinearGradient(gradient:Gradient(colors:[Palette.sidebarTop.opacity(0.72),.clear]),startPoint:.leading,endPoint:UnitPoint(x:0.7,y:0.5))
                    RadialGradient(gradient:Gradient(colors:[Palette.violet.opacity(0.12),.clear]),center:UnitPoint(x:0.08,y:0.1),startRadius:0,endRadius:max(400,geometry.size.width*0.65))
                }
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Only the two sidebar-facing corners are covered; the content canvas stays intact.
struct ConsoleDetailCorners:ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content:Content)->some View {
        content.appOverlay {
            GeometryReader { _ in
                sidebarFill.appMask {
                    Rectangle().appOverlay {
                        SidebarFacingShape().fill(.black).blendMode(.destinationOut)
                    }.compositingGroup()
                }
                if !reduceTransparency && contrast != .increased {
                    SidebarFacingShape()
                        .stroke(LinearGradient(gradient:Gradient(colors:[.white.opacity(scheme == .dark ? 0.22:0.85),.white.opacity(0.025),Palette.violet.opacity(scheme == .dark ? 0.20:0.12)]),startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.75)
                        .appMask(alignment:.leading) {Rectangle().frame(width:24)}
                }
            }
            .ignoresSafeArea(.container,edges:[.top,.bottom])
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
    @ViewBuilder private var sidebarFill:some View {
        if scheme == .dark {
            // Match the neutral sidebar instead of sampling colors from the desktop.
            LinearGradient(gradient:Gradient(colors:[Color(red:0.165,green:0.157,blue:0.180),Color(red:0.145,green:0.137,blue:0.165)]),startPoint:.top,endPoint:.bottom)
        }
        else {LinearGradient(gradient:Gradient(colors:[Palette.sidebarTop,Palette.sidebarBottom]),startPoint:.topLeading,endPoint:.bottomTrailing)}
    }
}

private struct SidebarFacingShape:Shape {
    func path(in rect:CGRect)->Path {
        // Native continuous curves, with square trailing corners, also work on macOS 13.
        var path=RoundedRectangle(cornerRadius:18,style:.continuous).path(in:rect)
        path.addRect(CGRect(x:rect.midX,y:rect.minY,width:rect.width/2,height:rect.height))
        return path
    }
}

/// Keep the main destinations visible, as in the supplied reference.
struct ConsoleToolbarPresentation:ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if #available(macOS 14,*) {content.toolbar(removing:.sidebarToggle)}
        else {content}
    }
}
