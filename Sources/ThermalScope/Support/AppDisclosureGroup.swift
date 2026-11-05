import SwiftUI

/// A native button owns the whole header, including the trailing empty space.
/// Keep the body outside its hit area so sliders, fields and nested rows stay independent.
struct AppDisclosureGroup<Label:View,Content:View>:View {
    private let selection:Binding<Bool>?
    private let label:Label
    private let content:Content
    private let inset:CGFloat
    @State private var localExpanded=false
    @State private var hovered=false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    private var expanded:Bool {selection?.wrappedValue ?? localExpanded}

    init(isExpanded:Binding<Bool>?=nil,inset:CGFloat=0,@ViewBuilder content:()->Content,@ViewBuilder label:()->Label) {
        self.selection=isExpanded;self.inset=inset;self.label=label();self.content=content()
    }
    init(_ title:String,isExpanded:Binding<Bool>?=nil,inset:CGFloat=0,@ViewBuilder content:()->Content) where Label==Text {
        self.init(isExpanded:isExpanded,inset:inset,content:content,label:{Text(verbatim:title)})
    }
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            Button {
                if let selection {selection.wrappedValue.toggle()}
                else {localExpanded.toggle()}
            } label:{
                HStack(spacing:8) {
                    Image(systemName:AppSymbols.resolve(expanded ? "chevron.down":"chevron.right"))
                        .font(.system(size:10,weight:.semibold)).foregroundColor(Palette.secondaryText)
                        .frame(width:12).accessibilityHidden(true)
                    label.frame(maxWidth:.infinity,alignment:.leading)
                }.frame(maxWidth:.infinity,minHeight:28,alignment:.leading).padding(inset)
                    .contentShape(Rectangle())
                    .appBackground {
                        RoundedRectangle(cornerRadius:inset>0 ? 14:5,style:.continuous)
                            .fill(hovered && enabled ? Palette.controlBackground:Color.clear)
                    }
                    .appOverlay {
                        if hovered && enabled && contrast == .increased {
                            RoundedRectangle(cornerRadius:inset>0 ? 14:5,style:.continuous)
                                .stroke(Palette.secondaryText,lineWidth:1).allowsHitTesting(false)
                        }
                    }
            }.buttonStyle(.plain).onHover{hovered=$0}
                .accessibilityValue(L(expanded ? "已展开":"已收起"))
                .accessibilityHint(L(expanded ? "点击收起":"点击展开"))
            if expanded {content.padding(.horizontal,inset).padding(.bottom,inset)}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
