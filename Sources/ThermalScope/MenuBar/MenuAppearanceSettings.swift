import SwiftUI
import AppKit

struct MenuFontControls:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
            Text(L("数值字体"));Spacer()
            AppChoicePicker(title:L("数值字体"),selection:$model.menuTypography.family,
                            choices:MenuFontFamily.allCases.map{AppChoice($0,L($0.title))}).frame(width:200,alignment:.trailing)
            }
            HStack {
            Text(L("字号"));Spacer()
            AppChoicePicker(title:L("字号"),selection:$model.menuTypography.size,
                            choices:[10.0,11,11.5,12,13].map{AppChoice($0,String(format:"%g pt",$0))}).frame(width:200,alignment:.trailing)
            }
            HStack {
            Text(L("字重"));Spacer()
            AppChoicePicker(title:L("字重"),selection:$model.menuTypography.weight,
                            choices:MenuFontWeight.allCases.map{AppChoice($0,L($0.title))}).frame(width:200,alignment:.trailing)
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
        AppChoicePicker(title:L("快速样式"),selection:Binding<Int>(get:{-1},set:{model.applyMenuPreset($0)}),
                        choices:MenuBarPreset.allCases.map{AppChoice($0.rawValue,L($0.title))},placeholder:L("快速样式"))
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
        let values:[MenuTileStyle]=metric == .tokenQuota ? [.icon,.value,.ring,.iconValue]:[.icon,.value,.history,.historyValue,.bars,.iconValue]
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
                if metric.isToken {TokenMenuControls(model:model,id:componentID,metric:metric)}
                Section(header:Text(L("显示方式"))) {
                    HStack {
                        Text(L("项目样式"));Spacer()
                        AppChoicePicker(title:L("项目样式"),selection:style,choices:styles.map{AppChoice($0,L($0.title))})
                            .accessibilityLabel(component.title(in:model)+" · "+L("项目样式"))
                    }
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
        }.font(AppTypography.body).frame(width:420,height:metric.isToken ? 470:330).appBackground{Palette.canvas}
            .onDisappear{customColorPanel.close()}
    }
    private var colorMenu:some View {
        AppChoicePicker(title:L("项目颜色"),selection:Binding<String?>(get:{selectedColor},set:{chooseColor($0)}),choices:colorChoices,
                        actions:[AppChoiceAction(title:L("自定义…"),action:{
                customColorPanel.show(color:MenuBarAppearanceRenderer.color(hex:selectedColor) ?? (scheme == .dark ? .white:.black)) {hex in
                    model.updateMenuComponent(id:componentID){$0.colorHex=hex}
                }
            })]).accessibilityLabel(component.title(in:model)+" · "+L("项目颜色"))
    }
    private var colorChoices:[AppChoice<String?>] {
        var choices=[AppChoice<String?>(nil,L("黑白（默认）"),image:MenuComponentColorPreset.swatch(hex:nil,dark:scheme == .dark))]
        choices += MenuComponentColorPreset.allCases.map{AppChoice(Optional($0.rawValue),L($0.title),image:MenuComponentColorPreset.swatch(hex:$0.rawValue,dark:scheme == .dark))}
        if let selectedColor,MenuComponentColorPreset(rawValue:selectedColor)==nil {
            choices.append(AppChoice(Optional(selectedColor),L("自定义"),image:MenuComponentColorPreset.swatch(hex:selectedColor,dark:scheme == .dark)))
        }
        return choices
    }
    var iconMenu:some View {
        AppChoicePicker(title:L("图标"),selection:Binding<String>(get:{component.icon ?? "auto"},set:{model.setMenuComponentIcon($0,id:componentID)}),choices:iconChoices,
                        actions:[AppChoiceAction(title:L("选择图片…"),action:{model.chooseMenuIcon(metric,componentID:componentID)})])
            .accessibilityLabel(component.title(in:model)+" · "+L("图标"))
    }
    private var iconChoices:[AppChoice<String>] {
        var choices=[AppChoice("auto",L("跟随样式"),symbol:component.source.symbol),AppChoice("none",L("无图标"),symbol:"minus.circle")]
        choices += MenuIconOption.options(component).map{AppChoice("sf:"+$0.symbol,L($0.title),symbol:$0.symbol)}
        if let token=component.icon,!choices.contains(where:{$0.value==token}) {
            switch MenuIconStore.icon(token,metric:metric,preview:model.isFanControlPreview,options:MenuIconOption.options(component)) {
            case .image(let image):choices.append(AppChoice(token,L("自定义图片"),image:MenuIconStore.thumbnail(image)))
            case .symbol(let name):choices.append(AppChoice(token,L("自定义图标"),symbol:name))
            default:break
            }
        }
        return choices
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
