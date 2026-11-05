import AppKit
import SwiftUI

struct AppChoice<Value:Hashable> {
    let value:Value
    let title:String
    var symbol:String?
    var image:NSImage?
    var help:String?
    init(_ value:Value,_ title:String,symbol:String?=nil,image:NSImage?=nil,help:String?=nil) {
        self.value=value;self.title=title;self.symbol=symbol;self.image=image;self.help=help
    }
}

struct AppChoiceAction {
    let title:String
    let action:()->Void
}

struct AppChoiceButtonStyle:ButtonStyle {
    var expanded=false
    @State private var hovered=false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:12,weight:.medium)).foregroundColor(Palette.violet)
            .padding(.horizontal,10).frame(minHeight:28)
            .appBackground {
                RoundedRectangle(cornerRadius:7,style:.continuous)
                    .fill(expanded || hovered || configuration.isPressed ? Palette.controlHover:Palette.controlBackground)
            }.appOverlay {
                RoundedRectangle(cornerRadius:7,style:.continuous).stroke(Palette.controlBorder,lineWidth:expanded ? 1:0.5)
                    .allowsHitTesting(false)
            }.opacity(enabled ? 1:0.5).onHover{hovered=$0}
    }
}

extension View {
    @ViewBuilder func appChoiceListSurface()->some View {
        if #available(macOS 13,*),!PlatformUI.classic {
            scrollContentBackground(.hidden).background(Palette.surface).accentColor(Palette.violet)
        } else {background(Palette.surface).accentColor(Palette.violet)}
    }
}

/// Palette-matched selection with native buttons, popover dismissal and keyboard input.
struct AppChoicePicker<Value:Hashable>:View {
    let title:String
    @Binding var selection:Value
    let choices:[AppChoice<Value>]
    var minimumWidth:CGFloat=0
    var placeholder:String?=nil
    var actions:[AppChoiceAction]=[]
    @State private var presented=false
    @State private var hovered=false
    @State private var focusedIndex=0
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    private var selectedChoice:AppChoice<Value>? {choices.first{$0.value==selection}}
    private var selectedTitle:String {selectedChoice?.title ?? placeholder ?? "—"}
    var body:some View {
        Button {presented.toggle()} label:{
            HStack(spacing:8) {
                if let choice=selectedChoice {choiceIcon(choice)}
                Text(selectedTitle).lineLimit(1)
                Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold))
                    .foregroundColor(Palette.violet.opacity(0.8))
            }.font(.system(size:12,weight:.medium)).foregroundColor(Palette.violet)
                .padding(.horizontal,10).frame(minWidth:minimumWidth,minHeight:28)
                .appBackground {
                    RoundedRectangle(cornerRadius:7,style:.continuous)
                        .fill(presented || hovered ? Palette.controlHover:Palette.controlBackground)
                }
                .appOverlay {
                    RoundedRectangle(cornerRadius:7,style:.continuous)
                        .stroke(contrast == .increased ? Palette.primaryText:Palette.controlBorder,
                                lineWidth:contrast == .increased || presented ? 1:0.5)
                        .allowsHitTesting(false)
                }.contentShape(RoundedRectangle(cornerRadius:7,style:.continuous))
        }.buttonStyle(.plain).fixedSize().opacity(enabled ? 1:0.5)
            .onHover{hovered=$0}.help(title)
            .accessibilityLabel(title).accessibilityValue(selectedTitle)
            .popover(isPresented:$presented,arrowEdge:.bottom) {options}
    }
    private var options:some View {
        VStack(alignment:.leading,spacing:3) {
            ForEach(choices.indices,id:\.self) {index in
                let choice=choices[index]
                let selected=choice.value==selection
                Button {choose(index)} label:{
                    HStack(spacing:9) {
                        Image(systemName:"checkmark").font(.system(size:11,weight:.semibold))
                            .frame(width:12).opacity(selected ? 1:0)
                        choiceIcon(choice)
                        Text(choice.title).font(.system(size:12,weight:selected ? .medium:.regular))
                        Spacer(minLength:14)
                    }.foregroundColor(selected ? Palette.violet:Palette.primaryText)
                        .padding(.horizontal,10).padding(.vertical,7)
                        .appBackground {
                            RoundedRectangle(cornerRadius:5,style:.continuous)
                                .fill(selected ? Palette.controlHover:(focusedIndex==index ? Palette.controlBackground:.clear))
                        }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .onHover{inside in if inside {focusedIndex=index}}
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(selected ? .isSelected:[])
            }
            if !actions.isEmpty {
                if !choices.isEmpty {Divider().opacity(0.45).padding(.vertical,3)}
                ForEach(actions.indices,id:\.self) {index in
                    Button {choose(choices.count+index)} label:{
                        HStack {Text(actions[index].title);Spacer(minLength:14)}
                            .font(.system(size:12)).foregroundColor(Palette.violet)
                            .padding(.horizontal,10).padding(.vertical,7)
                            .appBackground {
                                RoundedRectangle(cornerRadius:5,style:.continuous)
                                    .fill(focusedIndex==choices.count+index ? Palette.controlBackground:.clear)
                            }.contentShape(Rectangle())
                    }.buttonStyle(.plain).onHover{inside in if inside {focusedIndex=choices.count+index}}
                }
            }
        }.padding(6).frame(minWidth:max(160,minimumWidth),alignment:.leading)
            .background(Palette.surface)
            .appOverlay {
                RoundedRectangle(cornerRadius:8,style:.continuous)
                    .stroke(contrast == .increased ? Palette.primaryText:Palette.controlBorder,
                            lineWidth:contrast == .increased ? 1:0.5).allowsHitTesting(false)
            }
            .accessibilityElement(children:.contain).accessibilityLabel(title)
            .background(ChoiceKeyboardCapture(onMove:{offset in
                let count=choices.count+actions.count
                guard count>0 else{return}
                focusedIndex=(focusedIndex+offset+count)%count
            },onChoose:{choose(focusedIndex)},onDismiss:{presented=false})
                .frame(width:0,height:0).accessibilityHidden(true))
            .onAppear{focusedIndex=choices.firstIndex{$0.value==selection} ?? 0}
    }
    @ViewBuilder private func choiceIcon(_ choice:AppChoice<Value>)->some View {
        if let image=choice.image {Image(nsImage:image).renderingMode(.original).resizable().aspectRatio(contentMode:.fit).frame(width:14,height:14).accessibilityHidden(true)}
        else if let symbol=choice.symbol {Image(systemName:AppSymbols.resolve(symbol)).frame(width:14,height:14).accessibilityHidden(true)}
    }
    private func choose(_ index:Int) {
        presented=false
        if choices.indices.contains(index) {selection=choices[index].value}
        else if actions.indices.contains(index-choices.count) {actions[index-choices.count].action()}
    }
}

/// Small sets stay visible with the same palette, selection and focus states as menus.
struct AppSegmentedPicker<Value:Hashable>:View {
    let title:String
    let selection:Value?
    let choices:[AppChoice<Value>]
    var expands=false
    var compact=false
    var isEnabled:(Value)->Bool={_ in true}
    let onSelect:(Value)->Void
    @State private var hovered:Int?
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    var body:some View {
        HStack(spacing:2) {
            ForEach(choices.indices,id:\.self) {index in
                let choice=choices[index]
                let selected=choice.value==selection
                Button {onSelect(choice.value)} label:{
                    Text(choice.title).font(.system(size:compact ? 11:12,weight:selected ? .semibold:.medium))
                        .lineLimit(1).padding(.horizontal,compact ? 7:11)
                        .frame(maxWidth:expands ? .infinity:nil,minHeight:compact ? 24:28)
                        .foregroundColor(selected ? Palette.violet:Palette.secondaryText)
                        .appBackground {
                            RoundedRectangle(cornerRadius:6,style:.continuous)
                                .fill(selected ? Palette.controlHover:(hovered==index ? Palette.surface.opacity(0.65):.clear))
                        }
                        .appOverlay {
                            if selected {RoundedRectangle(cornerRadius:6,style:.continuous).stroke(Palette.controlBorder,lineWidth:0.5).allowsHitTesting(false)}
                        }.contentShape(RoundedRectangle(cornerRadius:6,style:.continuous))
                }.buttonStyle(.plain).disabled(!isEnabled(choice.value))
                    .opacity(isEnabled(choice.value) ? 1:0.45)
                    .onHover{inside in hovered=inside ? index:nil}
                    .help(choice.help ?? choice.title)
                    .accessibilityLabel(choice.title).accessibilityAddTraits(selected ? .isSelected:[])
            }
        }.padding(3).appBackground(Palette.controlBackground,in:RoundedRectangle(cornerRadius:8,style:.continuous))
            .appOverlay {
                RoundedRectangle(cornerRadius:8,style:.continuous)
                    .stroke(contrast == .increased ? Palette.primaryText:Palette.controlBorder,lineWidth:contrast == .increased ? 1:0.5)
                    .allowsHitTesting(false)
            }.opacity(enabled ? 1:0.5)
            .accessibilityElement(children:.contain).accessibilityLabel(title)
            .onMoveCommand {direction in
                let step=direction == .left || direction == .up ? -1:1
                let options=choices.filter{isEnabled($0.value)}
                guard enabled,!options.isEmpty else{return}
                let index=options.firstIndex{$0.value==selection} ?? (step>0 ? -1:0)
                onSelect(options[(index+step+options.count)%options.count].value)
            }
    }
}

/// Preserve arrow/Return/Escape behavior on macOS 11 without a custom event monitor.
private struct ChoiceKeyboardCapture:NSViewRepresentable {
    let onMove:(Int)->Void
    let onChoose:()->Void
    let onDismiss:()->Void
    func makeNSView(context:Context)->KeyView {KeyView()}
    func updateNSView(_ view:KeyView,context:Context) {
        view.onMove=onMove;view.onChoose=onChoose;view.onDismiss=onDismiss
    }
    final class KeyView:NSView {
        var onMove:((Int)->Void)?
        var onChoose:(()->Void)?
        var onDismiss:(()->Void)?
        override var acceptsFirstResponder:Bool {true}
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async {[weak self] in guard let self,let window=self.window else{return};window.makeFirstResponder(self)}
        }
        override func keyDown(with event:NSEvent) {
            switch event.keyCode {
            case 125:onMove?(1)
            case 126:onMove?(-1)
            case 36,76,49:onChoose?()
            case 53:onDismiss?()
            default:super.keyDown(with:event)
            }
        }
    }
}
