import AppKit
import SwiftUI

/// These choices belong to one menu component; an unset color follows the system.
enum MenuComponentColorPreset:String,CaseIterable,Identifiable {
    case purple="9876C8",blue="4B83C3",teal="3D9390",graphite="8792A7",rose="C7769E",gold="B88943"
    var id:String {rawValue}
    var title:String {
        switch self {case .purple:return "雾紫";case .blue:return "海蓝";case .teal:return "青绿";case .graphite:return "石墨";case .rose:return "玫瑰";case .gold:return "暖金"}
    }
    static func swatch(hex:String?,dark:Bool)->NSImage {
        let symbol=NSImage(systemSymbolName:AppSymbols.resolve(hex==nil ? "circle.lefthalf.filled":"circle.fill"),accessibilityDescription:nil)
        let color=MenuBarAppearanceRenderer.color(hex:hex) ?? (dark ? NSColor.white:.black)
        let image=NSImage(size:NSSize(width:14,height:14),flipped:false) {rect in
            symbol?.draw(in:rect);color.setFill();rect.fill(using:.sourceAtop);return true
        }
        image.isTemplate=hex==nil
        return image
    }
}

/// The native custom picker remains attached to the component that opened it.
@MainActor final class MenuComponentColorPanel:NSObject,ObservableObject {
    private var panel:NSColorPanel?
    private var onChange:((String)->Void)?

    func show(color:NSColor,onChange:@escaping(String)->Void) {
        close()
        let panel=NSColorPanel.shared
        panel.setTarget(nil);panel.setAction(nil)
        panel.showsAlpha=false;panel.isContinuous=true;panel.color=color
        self.panel=panel;self.onChange=onChange
        panel.setTarget(self);panel.setAction(#selector(changed(_:)))
        NotificationCenter.default.addObserver(self,selector:#selector(didClose(_:)),name:NSWindow.willCloseNotification,object:panel)
        panel.makeKeyAndOrderFront(nil)
    }
    func close() {
        panel?.orderOut(nil)
        detach()
    }
    private func detach() {
        guard let panel else{return}
        panel.setTarget(nil);panel.setAction(nil)
        NotificationCenter.default.removeObserver(self,name:NSWindow.willCloseNotification,object:panel)
        self.panel=nil;onChange=nil
    }
    @objc private func changed(_ sender:NSColorPanel) {
        guard sender===panel,let hex=MenuBarAppearanceRenderer.hex(sender.color) else{return}
        onChange?(hex)
    }
    @objc private func didClose(_ notification:Notification) {detach()}
}
