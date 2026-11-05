import AppKit
import SwiftUI
import ThermalCore

struct FanSceneApplicationsPicker:View {
    @ObservedObject var model:AppModel
    let scene:FanScene
    @State private var presented=false
    var body:some View {
        Button {presented.toggle()} label:{Label(L("关联"),systemImage:AppSymbols.resolve("plus.app"))}
            .buttonStyle(.borderless).font(.system(size:11)).foregroundColor(Palette.violet)
            .help(L("关联应用")+" · "+L(scene.name)).accessibilityLabel(L("关联应用")+" · "+L(scene.name))
            .popover(isPresented:$presented) {
                VStack(alignment:.leading,spacing:12) {
                    Text(L("关联应用")).font(.system(size:13,weight:.semibold))
                    Text(String(format:L("打开这些应用时使用“%@”"),L(scene.name)))
                        .font(.system(size:11)).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
                    let apps=model.availableFanApplications
                    if apps.isEmpty {Text(L("选择一个应用，为这个场景建立规则。"))
                        .font(.system(size:12)).foregroundColor(Palette.secondaryText).padding(.vertical,12)}
                    else {
                        ScrollView {
                            VStack(spacing:2) {ForEach(apps) {app in applicationRow(app)}}
                        }.frame(height:min(270,CGFloat(apps.count)*36))
                    }
                    Divider().opacity(0.5)
                    Button(L("选择其他应用…")) {presented=false;model.chooseFanApplications(sceneID:scene.id)}
                        .buttonStyle(.borderless).foregroundColor(Palette.violet).font(.system(size:12))
                    Text(L("每个应用对应一个场景；重新关联会替换原规则。"))
                        .font(.system(size:10)).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
                }.padding(14).frame(width:300).appBackground{Palette.surface}.foregroundColor(Palette.primaryText)
            }
    }
    private func applicationRow(_ app:FanApplication)->some View {
        let assigned=model.fanAutomation.rules.first{$0.id==app.id}?.sceneID
        let selected=assigned==scene.id
        return Button {
            if selected {model.removeFanApplication(app.id)}
            else {model.associateFanApplication(app,sceneID:scene.id)}
        } label:{
            HStack(spacing:8) {
                Image(systemName:selected ? "checkmark.square.fill":"square").foregroundColor(selected ? Palette.violet:Palette.secondaryText)
                if let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:app.id) {
                    Image(nsImage:NSWorkspace.shared.icon(forFile:url.path)).resizable().frame(width:20,height:20)
                }
                Text(app.name).font(.system(size:12)).lineLimit(1)
                Spacer(minLength:0)
                if let assigned,assigned != scene.id,let other=model.fanScenes.scenes.first(where:{$0.id==assigned}) {
                    Text(L(other.name)).font(.system(size:10)).foregroundColor(Palette.secondaryText).lineLimit(1)
                }
            }.foregroundColor(Palette.primaryText).padding(.horizontal,7).frame(height:34)
                .appBackground {RoundedRectangle(cornerRadius:6).fill(selected ? Palette.controlBackground:.clear)}
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(app.name).accessibilityValue(L(selected ? "已关联":"未关联"))
    }
}
