import AppKit
import SwiftUI

/// A native table owns selection, keyboard navigation and accessibility.
/// Only the row material and symbol rendering differ from a stock source list.
struct SidebarNavigationTable:NSViewRepresentable {
    struct Item {
        let id:String
        let title:String
        let symbol:String
        let help:String
    }
    let items:[Item]
    @Binding var selection:String?
    let dark:Bool

    func makeCoordinator()->Coordinator {Coordinator(selection:$selection)}
    func makeNSView(context:Context)->SidebarScrollView {
        let scroll=SidebarScrollView(),table=NSTableView()
        scroll.drawsBackground=false;scroll.borderType = .noBorder
        // No scroller at all: overlay scrollers follow the system scroll-bar preference and
        // stay visible whenever a traditional mouse (or USB receiver) is attached. Scrolling
        // still works without scroller UI.
        scroll.hasVerticalScroller=false
        scroll.horizontalScrollElasticity = .none;scroll.verticalScrollElasticity = .none
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("destination"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column);table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView=nil;table.backgroundColor = .clear;table.intercellSpacing = .zero
        table.style = .plain;table.autoresizingMask = [.width]
        table.allowsMultipleSelection=false;table.allowsEmptySelection=false
        table.selectionHighlightStyle = .none;table.focusRingType = .none
        table.dataSource=context.coordinator;table.delegate=context.coordinator
        table.target=context.coordinator;table.action=#selector(Coordinator.activate(_:))
        table.setAccessibilityLabel(L("主导航"))
        scroll.documentView=table
        context.coordinator.table=table;context.coordinator.scroll=scroll
        scroll.onHeightChange={ [weak coordinator=context.coordinator] in coordinator?.resizeSpacer() }
        return scroll
    }
    func updateNSView(_ scroll:SidebarScrollView,context:Context) {
        let coordinator=context.coordinator
        coordinator.selection=$selection
        coordinator.update(items:items,dark:dark)
    }

    final class Coordinator:NSObject,NSTableViewDataSource,NSTableViewDelegate {
        var selection:Binding<String?>
        weak var table:NSTableView?
        weak var scroll:SidebarScrollView?
        private var items:[Item]=[]
        private var dark=false
        private var syncing=false
        init(selection:Binding<String?>){self.selection=selection}
        // A top inset and a flexible spacer keep Settings at the bottom of the same native table.
        private var spacer:Int {items.count}
        private func item(_ row:Int)->Item? {
            if row>0 && row<spacer {return items[row-1]}
            if row==spacer+1 {return items.last}
            return nil
        }
        func update(items:[Item],dark:Bool) {
            guard let table else{return}
            let changed=self.items.map(\.title) != items.map(\.title) || self.items.map(\.id) != items.map(\.id) || self.dark != dark
            self.items=items;self.dark=dark;syncing=true
            if changed {table.reloadData();resizeSpacer()}
            let selected=(0..<numberOfRows(in:table)).first{item($0)?.id==selection.wrappedValue}
            if let selected,table.selectedRow != selected {table.selectRowIndexes(IndexSet(integer:selected),byExtendingSelection:false)}
            syncing=false
        }
        func resizeSpacer() {
            guard let table,!items.isEmpty else{return}
            table.noteHeightOfRows(withIndexesChanged:IndexSet([0,spacer]))
        }
        func numberOfRows(in tableView:NSTableView)->Int {items.isEmpty ? 0:items.count+2}
        func tableView(_ tableView:NSTableView,heightOfRow row:Int)->CGFloat {
            let height=scroll?.contentView.bounds.height ?? 600
            let top=min(44,max(24,height*0.06))
            if row==0 {return top}
            if row==spacer {return max(24,height-top-CGFloat(items.count)*52)}
            return 52
        }
        func tableView(_ tableView:NSTableView,shouldSelectRow row:Int)->Bool {item(row) != nil}
        func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView? {SidebarMaterialRow()}
        func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
            guard let item=item(row) else{return NSView()}
            let cell=SidebarNavigationCell()
            let icon=NSImageView(),label=NSTextField(wrappingLabelWithString:item.title)
            label.isEditable=false;label.isSelectable=false;label.refusesFirstResponder=true
            icon.imageScaling = .scaleProportionallyDown
            icon.setAccessibilityElement(false)
            label.font = .systemFont(ofSize:13,weight:.medium)
            label.maximumNumberOfLines=2;label.lineBreakMode = .byWordWrapping
            cell.imageView=icon;cell.textField=label;cell.toolTip=item.help
            cell.addSubview(icon);cell.addSubview(label)
            cell.symbolName=item.symbol;cell.dark=dark
            cell.applyStyle(selected:tableView.selectedRow==row)
            return cell
        }
        func tableViewSelectionDidChange(_ notification:Notification) {
            guard !syncing,let table,let item=item(table.selectedRow) else{return}
            selection.wrappedValue=item.id
        }
        @objc func activate(_ sender:NSTableView) {
            guard let item=item(sender.clickedRow) else{return}
            // Clicking the current destination also returns from an open metric detail.
            selection.wrappedValue=item.id
        }
    }
}

private final class SidebarNavigationCell:NSTableCellView {
    var symbolName=""
    var dark=false
    func applyStyle(selected:Bool) {
        imageView?.image=SidebarSymbol.image(symbolName,dark:dark,selected:selected)
        textField?.textColor=Palette.navigationText(dark:dark,selected:selected)
    }
    override func layout() {
        super.layout()
        imageView?.frame=NSRect(x:27,y:(bounds.height-24)/2,width:24,height:24)
        guard let label=textField else{return}
        let width=max(1,bounds.width-78)
        label.preferredMaxLayoutWidth=width
        let measured=(label.stringValue as NSString).boundingRect(with:NSSize(width:width,height:40),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:label.font ?? NSFont.systemFont(ofSize:13)])
        let height=min(38,max(18,ceil(measured.height)))
        label.frame=NSRect(x:64,y:(bounds.height-height)/2,width:width,height:height)
    }
}

final class SidebarScrollView:NSScrollView {
    var onHeightChange:(()->Void)?
    private var lastHeight:CGFloat=0
    override func layout() {
        super.layout()
        if abs(contentView.bounds.height-lastHeight)>0.5 {
            lastHeight=contentView.bounds.height;onHeightChange?()
        }
    }
}

private final class SidebarMaterialRow:NSTableRowView {
    private let glass:NSView={
        if #available(macOS 26,*),!PlatformUI.classic {
            let view=NSGlassEffectView()
            view.style = .regular;view.cornerRadius=14
            view.contentView=NSView()
            // Use the public property dynamically so the macOS 26 SDK can build
            // the macOS 11 package while newer systems retain the interaction.
            if #available(macOS 27,*),view.responds(to:NSSelectorFromString("setEffectIsInteractive:")) {
                view.setValue(true,forKey:"effectIsInteractive")
            }
            return view
        }
        let view=NSVisualEffectView()
        view.material = .popover;view.blendingMode = .withinWindow;view.state = .active
        view.wantsLayer=true;view.layer?.cornerRadius=14;view.layer?.masksToBounds=true
        view.layer?.borderWidth=0.7
        return view
    }()
    private let sheen=CAGradientLayer()
    override init(frame:NSRect) {
        super.init(frame:frame)
        if glass is NSVisualEffectView {glass.layer?.addSublayer(sheen)}
        glass.setAccessibilityElement(false)
        addSubview(glass,positioned:.below,relativeTo:nil);glass.isHidden=true
        updateMaterial()
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override var interiorBackgroundStyle:NSView.BackgroundStyle {.normal}
    override var isSelected:Bool {didSet {
        glass.isHidden = !isSelected
        if numberOfColumns>0 {(view(atColumn:0) as? SidebarNavigationCell)?.applyStyle(selected:isSelected)}
        needsDisplay=true
    }}
    override func drawSelection(in dirtyRect:NSRect) {}
    override func drawBackground(in dirtyRect:NSRect) {}
    override func viewDidChangeEffectiveAppearance(){super.viewDidChangeEffectiveAppearance();updateMaterial()}
    private func updateMaterial() {
        // Native Liquid Glass supplies its own highlights and accessibility adaptation.
        if #available(macOS 26,*),glass is NSGlassEffectView {return}
        let dark=effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let tone=Palette.navigationSelection(dark:dark)
        sheen.colors=[tone.withAlphaComponent(dark ? 0.75:1).cgColor,tone.withAlphaComponent(dark ? 0.45:0.96).cgColor]
        sheen.startPoint=CGPoint(x:0,y:1);sheen.endPoint=CGPoint(x:1,y:0)
        glass.layer?.borderColor=Palette.navigationIcon(dark:dark,selected:true).withAlphaComponent(dark ? 0.22:0.10).cgColor
    }
    override func layout() {
        super.layout()
        glass.frame=bounds.insetBy(dx:12,dy:4)
        CATransaction.begin();CATransaction.setDisableActions(true);sheen.frame=glass.bounds;CATransaction.commit()
    }
}

private enum SidebarSymbol {
    static func image(_ name:String,dark:Bool,selected:Bool)->NSImage? {
        guard var symbol=NSImage(systemSymbolName:AppSymbols.resolve(name),accessibilityDescription:nil)?
            .withSymbolConfiguration(.init(pointSize:22,weight:.medium)) else{return nil}
        if #available(macOS 12,*),let palette=symbol.withSymbolConfiguration(.init(paletteColors:[.black,.black,.black])) {symbol=palette}
        let mask=NSImage(size:NSSize(width:24,height:24),flipped:false) {rect in
            let scale=min(22/symbol.size.width,22/symbol.size.height)
            let size=NSSize(width:symbol.size.width*scale,height:symbol.size.height*scale)
            symbol.draw(in:NSRect(x:(24-size.width)/2,y:(24-size.height)/2,width:size.width,height:size.height));return true
        }
        let color=Palette.navigationIcon(dark:dark,selected:selected)
        return NSImage(size:mask.size,flipped:false) {rect in
            color.setFill();rect.fill()
            mask.draw(in:rect,from:.zero,operation:.destinationIn,fraction:1)
            return true
        }
    }
}
