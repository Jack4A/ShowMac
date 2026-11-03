import AppKit
import SwiftUI

/// One shared material and tint keep the reference sidebar soft on every supported OS.
struct ConsoleWindowBackdrop:View {
    var body:some View {ConsoleSidebarBackdrop().ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)}
}

struct ConsoleSidebarBackdrop:View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body:some View {
        ZStack {
            if scheme == .dark && !reduceTransparency {ConsoleSidebarMaterial()}
            LinearGradient(gradient:Gradient(colors:[Palette.sidebarTop,Palette.sidebarBottom]),startPoint:.top,endPoint:.bottom)
                .opacity(scheme == .dark && !reduceTransparency ? 0.78:1)
        }
    }
}

private struct ConsoleSidebarMaterial:NSViewRepresentable {
    func makeNSView(context:Context)->NSVisualEffectView {
        let view=NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view:NSVisualEffectView,context:Context) {}
}

struct ConsoleDetailCorners:ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content:Content)->some View {
        content.appBackground {
            LinearGradient(gradient:Gradient(colors:[Palette.detailTop,Palette.canvas]),startPoint:.topLeading,endPoint:.bottomTrailing)
                .clipShape(SidebarFacingShape())
                .ignoresSafeArea(.container,edges:[.top,.bottom])
        }
        .appOverlay {
            SidebarFacingShape().stroke(Palette.sidebarEdge.opacity(contrast == .increased ? 1:(scheme == .dark ? 0.7:0.5)),lineWidth:contrast == .increased ? 1:0.75)
                .appMask(alignment:.leading) {Rectangle().frame(width:24)}
                .ignoresSafeArea(.container,edges:[.top,.bottom])
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
