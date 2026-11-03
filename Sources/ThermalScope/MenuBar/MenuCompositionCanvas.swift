import AppKit
import SwiftUI

/// Native drag sessions commit only on a valid drop; hovering or cancelling never edits settings.
struct MenuCompositionCanvas:View {
    @ObservedObject var model:AppModel
    @ObservedObject var readings:LiveReadings
    @ObservedObject var history:MetricHistoryStore
    @Environment(\.colorScheme) private var scheme
    @State private var source:MenuComponentSource = .metric(.cpu)
    @State private var targetedID:String?
    @State private var targetedEnd=false
    @State private var targetedRemoval=false
    let onEdit:(MenuBarComponent)->Void
    init(model:AppModel,onEdit:@escaping(MenuBarComponent)->Void) {
        self.model=model;self.readings=model.readings;self.history=model.metricHistory;self.onEdit=onEdit
    }
    private static let dragType="public.utf8-plain-text"
    private var components:[MenuBarComponent] {model.effectiveMenuComponents}
    private var dark:Bool {scheme == .dark}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text(L("状态栏")).font(AppTypography.section)
                Spacer()
                MenuPresetGallery(model:model)
                Button {model.statusMenuRequested?()} label:{Image(systemName:AppSymbols.resolve("macwindow"))}
                    .help(L("查看状态面板")).accessibilityLabel(L("查看状态面板"))
            }.buttonStyle(.borderless)
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:6) {
                    ForEach(components) {component in activeComponent(component)}
                    Image(systemName:AppSymbols.resolve("plus")).foregroundColor(.secondary).frame(width:64,height:44)
                        .appBackground(targetedEnd ? Palette.selection.opacity(0.5):.clear,in:RoundedRectangle(cornerRadius:6))
                        .contentShape(Rectangle()).accessibilityLabel(L("拖到此处"))
                        .onDrop(of:[Self.dragType],isTargeted:$targetedEnd) {providers in receive(providers){model.applyMenuDrop([$0],before:nil)}}
                }.padding(8)
            }.frame(height:66)
                .appBackground(Palette.inset,in:RoundedRectangle(cornerRadius:8))
            HStack(spacing:8) {
                MenuSensorPicker(model:model,source:$source)
                ForEach([MenuTileStyle.icon,.value,.history]) {style in template(style)}
                Spacer(minLength:0)
                Image(systemName:AppSymbols.resolve("trash")).foregroundColor(targetedRemoval ? Color.red:Color.secondary)
                    .frame(width:32,height:32).contentShape(Rectangle())
                    .appBackground(targetedRemoval ? Color.red.opacity(0.10):.clear,in:RoundedRectangle(cornerRadius:6))
                    .accessibilityLabel(L("拖到这里移除"))
                    .onDrop(of:[Self.dragType],isTargeted:$targetedRemoval) {providers in receive(providers) {token in
                        guard let drag=MenuComponentDrag(token),case .existing(let id)=drag else{return false}
                        return model.removeMenuComponent(id:id)
                    }}
                    .help(L("拖到这里移除"))
            }
            Text(L("拖动添加或排序，点按编辑。")).font(AppTypography.caption).foregroundColor(.secondary)
        }.modifier(MenuGlassGrouping()).subtlePanel(padding:18)
    }
    private func provider(_ token:String)->NSItemProvider {
        NSItemProvider(object:token as NSString)
    }
    private func receive(_ providers:[NSItemProvider],action:@escaping(String)->Bool)->Bool {
        guard providers.count==1,let provider=providers.first,provider.hasItemConformingToTypeIdentifier(Self.dragType) else{return false}
        provider.loadDataRepresentation(forTypeIdentifier:Self.dragType) {data,_ in
            guard let data,data.count<1024,let token=String(data:data,encoding:.utf8),MenuComponentDrag(token) != nil else{return}
            DispatchQueue.main.async {_ = action(token)}
        }
        return true
    }
    private func image(_ component:MenuBarComponent,darkAppearance:Bool?=nil)->NSImage {
        MenuBarAppearanceRenderer.image(tiles:[MenuBarAppearanceRenderer.tile(component:component,model:model)],ending:history.end,spacing:model.menuSpacing,graphWidth:model.menuGraphWidth,background:model.menuGraphBackground,appearance:NSAppearance(named:(darkAppearance ?? dark) ? .darkAqua:.aqua),warningsEnabled:model.menuCPUWarnings,typography:model.menuTypography,dividers:false,innerPadding:model.menuInnerPadding)
    }
    private func activeComponent(_ component:MenuBarComponent)->some View {
        Button {onEdit(component)} label:{
            Image(nsImage:image(component)).fixedSize()
                .frame(minWidth:28,minHeight:22).padding(10)
                .modifier(MenuActionSurface(fallbackOpacity:0.045))
                .contentShape(Rectangle())
                .onDrag {provider(MenuComponentDrag.existing(component.id).token)}
        }.buttonStyle(.plain)
            .accessibilityLabel(component.title(in:model)+" · "+L(component.style.title)+" · "+L("编辑"))
            .help(component.title(in:model)+" · "+L("拖动排序，点按编辑；可重复添加同一指标。"))
            .contextMenu {
                Button(L("编辑")){onEdit(component)}
                if let index=components.firstIndex(where:{$0.id==component.id}) {
                    Button(L("向左移动")){if index>0 {_ = model.moveMenuComponent(id:component.id,before:components[index-1].id)}}.disabled(index==0)
                    Button(L("向右移动")){_ = model.moveMenuComponent(id:component.id,before:index+2<components.count ? components[index+2].id:nil)}.disabled(index==components.count-1)
                }
                Divider()
                Button(L("移除组件")){_ = model.removeMenuComponent(id:component.id)}.disabled(components.count<=1)
            }
            .appOverlay(alignment:.leading) {if targetedID==component.id {Rectangle().fill(Palette.violet).frame(width:2).allowsHitTesting(false)}}
            .onDrop(of:[Self.dragType],isTargeted:Binding(get:{targetedID==component.id},set:{value in
                if value {targetedID=component.id} else if targetedID==component.id {targetedID=nil}
            })) {providers in receive(providers){model.applyMenuDrop([$0],before:component.id)}}
    }
    private func template(_ style:MenuTileStyle)->some View {
        return Button {_ = model.insertMenuComponent(source:source,style:style)} label:{
            HStack(spacing:5) {
                Image(systemName:AppSymbols.resolve(style == .icon ? source.symbol:style == .value ? "textformat.123":"waveform.path"))
                Text(L(style == .icon ? "图标":style == .value ? "数值":"趋势")).font(AppTypography.caption)
            }.frame(height:22).padding(6)
                .modifier(MenuActionSurface(fallbackOpacity:0.035))
                .contentShape(Rectangle())
                .onDrag {provider(drag(style).token)}
        }.buttonStyle(.plain)
            .disabled(components.count>=MenuBarComponent.limit)
            .accessibilityLabel(source.title(in:model)+" · "+L(style.title)+" · "+L("添加组件"))
            .help(L("拖到上方，或点按添加"))
    }
    private func drag(_ style:MenuTileStyle)->MenuComponentDrag {
        switch source {case .metric(let metric):return .template(metric,style);case .sensor(let sensor):return .sensorTemplate(sensor,style)}
    }
}

private struct MenuGlassGrouping:ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if #available(macOS 26,*),!PlatformUI.classic {GlassEffectContainer(spacing:0) {content}}
        else {content}
    }
}

private struct MenuActionSurface:ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let fallbackOpacity:Double
    @ViewBuilder func body(content:Content)->some View {
        if #available(macOS 26,*),!PlatformUI.classic,!reduceTransparency,contrast != .increased {
            content.glassEffect(.regular.interactive(),in:RoundedRectangle(cornerRadius:8,style:.continuous))
        } else if reduceTransparency || contrast == .increased {
            content.appBackground(Palette.surface,in:RoundedRectangle(cornerRadius:6))
                .appOverlay {RoundedRectangle(cornerRadius:6).stroke(Color.primary.opacity(contrast == .increased ? 0.4:0.15),lineWidth:0.75).allowsHitTesting(false)}
        } else {
            content.appBackground(.primary.opacity(fallbackOpacity),in:RoundedRectangle(cornerRadius:6))
        }
    }
}
