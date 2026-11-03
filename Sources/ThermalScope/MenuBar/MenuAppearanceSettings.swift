import SwiftUI
import AppKit

struct MenuFontControls:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
            Text(L("数值字体"));Spacer()
            Picker(L("数值字体"),selection:$model.menuTypography.family) {
                ForEach(MenuFontFamily.allCases) {Text(L($0.title)).tag($0)}
            }.labelsHidden().frame(width:200,alignment:.trailing)
            }
            HStack {
            Text(L("字号"));Spacer()
            Picker(L("字号"),selection:$model.menuTypography.size) {
                ForEach([10.0,11,11.5,12,13],id:\.self) {Text(String(format:"%g pt",$0)).tag($0)}
            }.labelsHidden().frame(width:200,alignment:.trailing)
            }
            HStack {
            Text(L("字重"));Spacer()
            Picker(L("字重"),selection:$model.menuTypography.weight) {
                ForEach(MenuFontWeight.allCases) {Text(L($0.title)).tag($0)}
            }.labelsHidden().frame(width:200,alignment:.trailing)
            }
        }.font(AppTypography.body)
    }
}

struct MenuAppearanceControls:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:12) {
                Text(L("整体外边距")).frame(width:70,alignment:.leading)
                Slider(value:$model.menuOuterPadding,in:0...20,step:1).frame(maxWidth:210)
                    .accessibilityLabel(L("整体外边距"))
                Text(String(format:L("左右各 %.0f pt"),model.menuOuterPadding)).appMonospacedDigit().fixedSize()
            }.help(L("调整整组组件左右两端的留白。"))
            HStack(spacing:12) {
                Text(L("组件内边距")).frame(width:70,alignment:.leading)
                Slider(value:$model.menuInnerPadding,in:0...20,step:1).frame(maxWidth:210)
                    .accessibilityLabel(L("组件内边距"))
                Text(String(format:L("左右各 %.0f pt"),model.menuInnerPadding)).appMonospacedDigit().fixedSize()
            }.help(L("调整每个组件内部左右两侧的留白。"))
            HStack(spacing:12) {
                Text(L("项目间距")).frame(width:70,alignment:.leading)
                Slider(value:$model.menuSpacing,in:MenuBarLayout.spacingRange,step:1).frame(maxWidth:210)
                    .accessibilityLabel(L("项目间距"))
                Text(String(format:"%.0f pt",model.menuSpacing)).appMonospacedDigit().frame(width:40)
            }
            Toggle(L("项目分隔线"),isOn:$model.menuDividers).toggleStyle(.checkbox)
            HStack(spacing:12) {
                Text(L("曲线宽度")).frame(width:70,alignment:.leading)
                Slider(value:$model.menuGraphWidth,in:28...100,step:4).frame(maxWidth:210)
                Text(String(format:"%.0f pt",model.menuGraphWidth)).appMonospacedDigit().frame(width:40)
            }
            Toggle(L("图形底色"),isOn:$model.menuGraphBackground).toggleStyle(.checkbox)
            Toggle(L("曲线告警色"),isOn:$model.menuCPUWarnings).toggleStyle(.checkbox)
            Text(L("CPU ≥70% 橙色，持续 ≥90% 10 秒红色；CPU 温度 ≥80/90°C、GPU ≥75/85°C 分级变色。"))
                .foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
        }.font(AppTypography.caption)
    }
}

struct MenuPresetGallery:View {
    @ObservedObject var model:AppModel
    var body:some View {
        Menu {
            ForEach(MenuBarPreset.allCases) {preset in
                Button(L(preset.title)) {model.applyMenuPreset(preset.rawValue)}
                    .help(L(preset.title))
            }
        } label:{Image(systemName:AppSymbols.resolve("sparkles"))}
            .menuStyle(.borderlessButton).help(L("快速样式")).accessibilityLabel(L("快速样式"))
    }
}

struct MenuTileEditor:View {
    @ObservedObject var model:AppModel
    @Environment(\.colorScheme) private var scheme
    @StateObject private var customColorPanel=MenuComponentColorPanel()
    let componentID:String
    let metric:MenuMetric
    let onClose:()->Void
    private var component:MenuBarComponent {model.effectiveMenuComponents.first{$0.id==componentID} ?? MenuBarComponent(id:componentID,metric:metric,style:metric.defaultTileStyle)}
    private var styles:[MenuTileStyle] {
        let values:[MenuTileStyle]=[.icon,.value,.history,.iconValue]
        return values.contains(component.style) ? values:values+[component.style]
    }
    var style:Binding<MenuTileStyle> {Binding(get:{component.style},set:{newValue in model.updateMenuComponent(id:componentID){$0.style=newValue}})}
    private var selectedColor:String? {component.colorHex?.uppercased()}
    private var colorTitle:String {selectedColor.map{MenuComponentColorPreset(rawValue:$0)?.title ?? "自定义"} ?? "黑白（默认）"}
    private func chooseColor(_ hex:String?) {
        customColorPanel.close()
        model.updateMenuComponent(id:componentID){$0.colorHex=hex}
    }
    var body:some View {
        VStack(spacing:0) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text(component.title(in:model)).font(AppTypography.section)
                    Text(L("状态栏")).font(AppTypography.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(L("完成"),action:onClose).keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            Form {
                Section(header:Text(L("显示方式"))) {
                    Picker(L("项目样式"),selection:style) {ForEach(styles){Text(L($0.title)).tag($0)}}
                        .accessibilityLabel(component.title(in:model)+" · "+L("项目样式"))
                    HStack {Text(L("图标"));Spacer();iconMenu}
                }
                Section {
                    HStack {Text(L("项目颜色"));Spacer();colorMenu}
                }
            }.appGroupedForm()
            HStack {
                Button(L("移除组件")) {if model.removeMenuComponent(id:componentID){onClose()}}
                    .foregroundColor(.red)
                    .disabled(model.effectiveMenuComponents.count<=1)
                Spacer()
                Text(L("更改会立即保存。")).font(AppTypography.caption).foregroundColor(.secondary)
            }
                .padding(.horizontal,20).padding(.bottom,16)
        }.font(AppTypography.body).frame(width:420,height:330)
            .onDisappear{customColorPanel.close()}
    }
    private var colorMenu:some View {
        Menu {
            Picker(L("项目颜色"),selection:Binding<String?>(get:{selectedColor},set:{chooseColor($0)})) {
                Label {Text(L("黑白（默认）"))} icon:{Image(nsImage:MenuComponentColorPreset.swatch(hex:nil,dark:scheme == .dark))}.tag(String?.none)
                ForEach(MenuComponentColorPreset.allCases) {preset in
                    Label {Text(L(preset.title))} icon:{Image(nsImage:MenuComponentColorPreset.swatch(hex:preset.rawValue,dark:scheme == .dark))}.tag(Optional(preset.rawValue))
                }
                if let selectedColor,MenuComponentColorPreset(rawValue:selectedColor)==nil {
                    Label {Text(L("自定义"))} icon:{Image(nsImage:MenuComponentColorPreset.swatch(hex:selectedColor,dark:scheme == .dark))}.tag(Optional(selectedColor))
                }
            }.pickerStyle(.inline).labelsHidden()
            Divider()
            Button(L("自定义…")) {
                customColorPanel.show(color:MenuBarAppearanceRenderer.color(hex:selectedColor) ?? (scheme == .dark ? .white:.black)) {hex in
                    model.updateMenuComponent(id:componentID){$0.colorHex=hex}
                }
            }
        } label:{
            Label {Text(L(colorTitle))} icon:{Image(nsImage:MenuComponentColorPreset.swatch(hex:selectedColor,dark:scheme == .dark))}
        }.menuStyle(.borderlessButton).accessibilityLabel(component.title(in:model)+" · "+L("项目颜色"))
    }
    var iconMenu:some View {
        Menu {
            Button(L("跟随样式")){model.setMenuComponentIcon("auto",id:componentID)}
            Button(L("无图标")){model.setMenuComponentIcon("none",id:componentID)}
            Divider()
            ForEach(MenuIconOption.options(component)) {option in
                Button {model.setMenuComponentIcon("sf:"+option.symbol,id:componentID)} label:{Label(L(option.title),systemImage:AppSymbols.resolve(option.symbol))}
            }
            Divider()
            Button(L("选择图片…")){model.chooseMenuIcon(metric,componentID:componentID)}
        } label:{
            HStack(spacing:5) {
                iconPreview.frame(width:14,height:14)
                Text(L(iconTitle))
            }
        }.menuStyle(.borderlessButton).accessibilityLabel(component.title(in:model)+" · "+L("图标"))
    }
    @ViewBuilder var iconPreview:some View {
        switch MenuIconStore.icon(component.icon,metric:metric,preview:model.isFanControlPreview,options:MenuIconOption.options(component)) {
        case .automatic:Image(systemName:AppSymbols.resolve(component.source.symbol))
        case .hidden:Image(systemName:AppSymbols.resolve("minus.circle"))
        case .symbol(let name):Image(systemName:AppSymbols.resolve(name))
        case .image(let image):Image(nsImage:MenuIconStore.thumbnail(image))
        }
    }
    private var iconTitle:String {
        switch MenuIconStore.icon(component.icon,metric:metric,preview:model.isFanControlPreview,options:MenuIconOption.options(component)) {
        case .automatic:return "跟随样式"
        case .hidden:return "无图标"
        case .symbol(let name):return MenuIconOption.options(component).first{$0.symbol==name}?.title ?? "自定义图标"
        case .image:return "自定义图片"
        }
    }
}
