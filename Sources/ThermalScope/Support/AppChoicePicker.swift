import AppKit
import SwiftUI

struct AppChoice<Value:Hashable> {
    let value:Value
    let title:String
    init(_ value:Value,_ title:String) {self.value=value;self.title=title}
}

/// Palette-matched selection with native buttons, popover dismissal and keyboard input.
struct AppChoicePicker<Value:Hashable>:View {
    let title:String
    @Binding var selection:Value
    let choices:[AppChoice<Value>]
    var minimumWidth:CGFloat=0
    @State private var presented=false
    @State private var hovered=false
    @State private var focusedIndex=0
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    private var selectedTitle:String {choices.first{$0.value==selection}?.title ?? "—"}
    var body:some View {
        Button {presented.toggle()} label:{
            HStack(spacing:8) {
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
        }.padding(6).frame(minWidth:max(160,minimumWidth),alignment:.leading)
            .background(Palette.surface)
            .appOverlay {
                RoundedRectangle(cornerRadius:8,style:.continuous)
                    .stroke(contrast == .increased ? Palette.primaryText:Palette.controlBorder,
                            lineWidth:contrast == .increased ? 1:0.5).allowsHitTesting(false)
            }
            .accessibilityElement(children:.contain).accessibilityLabel(title)
            .background(ChoiceKeyboardCapture(onMove:{offset in
                guard !choices.isEmpty else{return}
                focusedIndex=(focusedIndex+offset+choices.count)%choices.count
            },onChoose:{choose(focusedIndex)},onDismiss:{presented=false})
                .frame(width:0,height:0).accessibilityHidden(true))
            .onAppear{focusedIndex=choices.firstIndex{$0.value==selection} ?? 0}
    }
    private func choose(_ index:Int) {
        guard choices.indices.contains(index) else{return}
        presented=false
        selection=choices[index].value
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
