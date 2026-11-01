import SwiftUI
import AppKit

struct MenuAppearancePreview:View {
    @ObservedObject var model:AppModel
    @ObservedObject var readings:LiveReadings
    @ObservedObject var history:MetricHistoryStore
    init(model:AppModel){self.model=model;self.readings=model.readings;self.history=model.metricHistory}
    var body:some View {
        VStack(spacing:8) {
            preview(dark:false)
            preview(dark:true)
        }
    }
    func preview(dark:Bool)->some View {
        let image=MenuBarAppearanceRenderer.image(tiles:MenuBarAppearanceRenderer.tiles(model:model),ending:history.end,theme:model.menuBarTheme,spacing:model.menuSpacing,graphWidth:model.menuGraphWidth,background:model.menuGraphBackground,appearance:NSAppearance(named:dark ? .darkAqua:.aqua),warningsEnabled:model.menuCPUWarnings)
        return HStack(spacing:14) {
            Text(L(dark ? "深色菜单栏":"浅色菜单栏")).font(.system(size:10)).foregroundStyle(dark ? Color.white.opacity(0.7):Color.black.opacity(0.6)).frame(width:76,alignment:.leading)
            Spacer(minLength:0)
            GeometryReader {proxy in ScrollView(.horizontal,showsIndicators:false) {HStack {Spacer(minLength:0);Image(nsImage:image).fixedSize()}.frame(minWidth:proxy.size.width).frame(height:26)}}.frame(height:26)
        }.padding(.horizontal,12).frame(height:42)
            .background(dark ? Color(white:0.12):Color(white:0.94),in:RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).stroke(dark ? .white.opacity(0.09):.black.opacity(0.07),lineWidth:0.5))
            .environment(\.colorScheme,dark ? .dark:.light)
    }
}
struct MenuAppearanceControls:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L("一键搭配")).font(.caption).foregroundStyle(.secondary)
            MenuPresetGallery(model:model)
            HStack(spacing:16) {
                Picker(L("配色"),selection:$model.menuBarTheme){ForEach(MenuBarTheme.allCases){theme in Text(L(theme.title)).tag(theme)}}.frame(maxWidth:220)
                Picker(L("间距"),selection:$model.menuSpacing){Text(L("紧凑")).tag(4.0);Text(L("标准")).tag(9.0)}.pickerStyle(.segmented).frame(maxWidth:190)
                Spacer(minLength:0)
            }
            HStack(spacing:16) {
                Picker(L("曲线宽度"),selection:$model.menuGraphWidth){Text(L("紧凑")).tag(44.0);Text(L("标准")).tag(66.0);Text(L("宽")).tag(88.0)}.frame(maxWidth:220)
                Toggle(L("图形底色"),isOn:$model.menuGraphBackground).toggleStyle(.checkbox)
                Spacer(minLength:0)
            }.font(.system(size:11))
            Text(L("曲线取最近 2 分钟真实采样；圆环表示读数在刻度范围内的位置。")).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text(L("上方按实际尺寸预览；颜色只影响图形，读数跟随系统文字颜色。")).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}
struct MenuPresetGallery:View {
    @ObservedObject var model:AppModel
    @ObservedObject var readings:LiveReadings
    @ObservedObject var history:MetricHistoryStore
    init(model:AppModel){self.model=model;self.readings=model.readings;self.history=model.metricHistory}
    var body:some View {
        HStack(spacing:8) {
            ForEach(MenuBarPreset.allCases) {preset in
                Button{model.applyMenuPreset(preset.rawValue)}label:{
                    VStack(alignment:.leading,spacing:7) {
                        Text(L(preset.title)).font(.system(size:10,weight:.medium))
                        Image(nsImage:MenuBarAppearanceRenderer.image(tiles:MenuBarAppearanceRenderer.tiles(model:model,preset:preset),ending:history.end,theme:preset.theme,spacing:4,graphWidth:44,background:preset.background,appearance:NSAppearance(named:.darkAqua),warningsEnabled:model.menuCPUWarnings)).fixedSize().frame(height:22)
                    }.padding(10).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(.white).background(Color(white:0.12),in:RoundedRectangle(cornerRadius:8))
                }.buttonStyle(.plain).help(L(preset.title))
            }
        }
    }
}
struct MenuTileEditor:View {
    @ObservedObject var model:AppModel
    let metric:MenuMetric
    var enabled:Bool {model.menuItems.contains(metric)}
    var style:Binding<MenuTileStyle> {Binding(get:{MenuTileStyle(rawValue:model.menuTileStyles[metric.rawValue] ?? "") ?? metric.defaultTileStyle},set:{model.menuTileStyles[metric.rawValue]=$0.rawValue})}
    var color:Binding<Color> {Binding(get:{Color(nsColor:MenuBarAppearanceRenderer.color(hex:model.menuTileColors[metric.rawValue],fallback:metric.defaultBarColor))},set:{if let hex=MenuBarAppearanceRenderer.hex(NSColor($0)){model.menuTileColors[metric.rawValue]=hex}})}
    var body:some View {
        HStack(spacing:10) {
            Toggle(isOn:Binding(get:{enabled},set:{model.toggleMenu(metric,$0)})){Label(metric.title,systemImage:metric.symbol)}.toggleStyle(.checkbox).disabled(enabled && model.menuItems.count==1)
            Spacer(minLength:0)
            if enabled {
                Picker(L("项目样式"),selection:style){ForEach(MenuTileStyle.allCases){s in Text(L(s.title)).tag(s)}}.labelsHidden().frame(width:132).controlSize(.small).accessibilityLabel(metric.title+" · "+L("项目样式"))
                ColorPicker(metric.title+" · "+L("颜色"),selection:color,supportsOpacity:false).labelsHidden().frame(width:24).disabled(model.menuBarTheme != .multicolor)
                if let index=model.menuItems.firstIndex(of:metric) {
                    Button{model.moveMenu(metric,-1)}label:{Image(systemName:"chevron.left").frame(width:18,height:22)}.disabled(index==0).help(L("向左移动"))
                    Button{model.moveMenu(metric,1)}label:{Image(systemName:"chevron.right").frame(width:18,height:22)}.disabled(index==model.menuItems.count-1).help(L("向右移动"))
                }
            }
        }.font(.system(size:12)).buttonStyle(.borderless).padding(.vertical,5)
    }
}
