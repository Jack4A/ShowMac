import SwiftUI
import ThermalCore

struct FanSceneControls:View {
    @ObservedObject var model:AppModel
    var compact=false
    let onManage:()->Void
    var body:some View {
        HStack(spacing:8) {
            if !compact {Text(L("场景")).font(.system(size:12)).foregroundColor(Palette.secondaryText)}
            AppChoicePicker(title:L("场景模式"),selection:Binding<String?>(get:{model.activeFanScene?.id},set:{if let id=$0 {model.applyFanScene(id)}}),
                            choices:model.fanScenes.scenes.map{AppChoice(Optional($0.id),L($0.name))},placeholder:L("选择场景"),
                            actions:[AppChoiceAction(title:L("新建或管理场景…"),action:onManage)],labelWidth:compact ? 90:110,listWidth:240,maximumListHeight:320)
                .accessibilityIdentifier("fanScenePicker")
            Spacer(minLength:0)
            if !compact {
                Button(action:onManage) {Image(systemName:AppSymbols.resolve("arrow.triangle.branch"))}
                    .buttonStyle(AppChoiceButtonStyle(expanded:model.fanAutomation.enabled))
                    .help(L("场景与应用")).accessibilityLabel(L("场景与应用"))
            }
            AppChoicePicker(title:L("控制时长"),selection:Binding(get:{model.fanScenes.duration},set:{model.setFanDuration($0)}),
                            choices:FanControlDuration.allCases.map{AppChoice($0,L($0.title))})
                .accessibilityIdentifier("fanDurationPicker")
            if !compact {
                Toggle(L("启动时恢复"),isOn:Binding(get:{model.fanScenes.restoreOnLaunch},set:{value in
                    model.fanScenes.restoreOnLaunch=value
                    if !value {model.fanRestorePending=false}
                })).toggleStyle(.checkbox).font(.system(size:11))
                    .help(L("重新启动或唤醒后恢复上次确认的风扇模式；首次控制仍需系统授权。"))
                    .accessibilityIdentifier("restoreFanModeOnLaunch")
            }
        }.disabled(model.busy || !AppDistribution.hardwareControlAvailable)
    }
}

struct FanSceneManager:View {
    @ObservedObject var model:AppModel
    let curve:FanCurve
    let onClose:()->Void
    @State private var name=""
    @State private var deletion:FanScene?
    @State private var adding=false
    @State private var renaming:String?
    @State private var renameText=""
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text(L("场景与应用")).font(.system(size:18,weight:.semibold));Spacer()
                Button(L("完成"),action:onClose).keyboardShortcut(.cancelAction)
            }
            VStack(alignment:.leading,spacing:7) {
                HStack {
                    Text(L("按应用切换")).font(.system(size:13,weight:.medium))
                    Spacer()
                    Toggle(L("按应用切换"),isOn:Binding(get:{model.fanAutomation.enabled},set:{model.setFanAutomationEnabled($0)}))
                        .labelsHidden().toggleStyle(.switch).accentColor(Palette.violet)
                        .accessibilityIdentifier("fanApplicationAutomation")
                        .disabled(model.busy || (model.fanAutomation.rules.isEmpty && !model.fanAutomation.enabled))
                }
                Text(L("前台应用优先；关联应用全部退出后恢复原模式。手动选档会暂停自动切换。"))
                    .font(.system(size:11)).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
            }.padding(12).background(Palette.surface).cornerRadius(12)
            HStack {
                Text(L("我的场景")).font(.system(size:12,weight:.semibold))
                Spacer()
                Button {adding.toggle()} label:{Label(L("新建场景"),systemImage:"plus")}
                    .buttonStyle(.borderless).font(.system(size:12)).disabled(model.busy || model.fanScenes.scenes.count>=FanSceneConfiguration.limit)
            }
            ScrollView {
                VStack(spacing:8) {ForEach(model.fanScenes.scenes) {scene in sceneRow(scene)}}
                    .padding(1)
            }
            if adding {
                HStack {
                    TextField(L("场景名称"),text:$name).textFieldStyle(.roundedBorder).accessibilityIdentifier("newFanSceneName")
                    Button(L("保存并使用")) {if model.saveFanScene(name:name,curve:curve) {onClose()}}
                        .buttonStyle(AppChoiceButtonStyle()).disabled(model.busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveFanScene")
                }
                Text(L("以当前曲线创建；使用场景后可在主界面拖动曲线修改。"))
                    .font(.system(size:11)).foregroundColor(Palette.secondaryText)
            }
            if model.messageIsError {Text(L(model.message)).font(.system(size:11)).foregroundColor(.orange).fixedSize(horizontal:false,vertical:true)}
            Divider().opacity(0.6)
            HStack(spacing:12) {
                AppChoicePicker(title:L("控制时长"),selection:Binding(get:{model.fanScenes.duration},set:{model.setFanDuration($0)}),choices:FanControlDuration.allCases.map{AppChoice($0,L($0.title))})
                Spacer()
                Toggle(L("启动时恢复"),isOn:Binding(get:{model.fanScenes.restoreOnLaunch},set:{model.fanScenes.restoreOnLaunch=$0;if !$0 {model.fanRestorePending=false}}))
                    .toggleStyle(.checkbox).font(.system(size:12))
            }.disabled(model.busy)
        }.padding(20).frame(width:520,height:580).appBackground{Palette.canvas}.foregroundColor(Palette.primaryText)
            .alert(item:$deletion) {scene in
                Alert(title:Text(String(format:L("删除“%@”场景？"),scene.name)),
                      message:Text(L(model.activeFanSceneID==scene.id ? "当前场景会停止，风扇恢复系统自动。":"其他场景保持不变。")),
                      primaryButton:.destructive(Text(L("删除"))){model.deleteFanScene(scene.id)},secondaryButton:.cancel(Text(L("取消"))))
            }
    }
    private func sceneRow(_ scene:FanScene)->some View {
        let apps=model.fanAutomation.rules.filter{$0.sceneID==scene.id}.map(\.application)
        return HStack(spacing:10) {
            Image(systemName:AppSymbols.resolve(FanSceneArtwork.symbol(scene))).font(.system(size:17)).foregroundColor(Palette.violet)
                .frame(width:34,height:34).background(Palette.controlBackground).cornerRadius(9)
            VStack(alignment:.leading,spacing:4) {
                if renaming==scene.id {
                    TextField(L("场景名称"),text:$renameText,onCommit:{saveRename(scene)}).textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L("场景名称")+" · "+L(scene.name))
                } else {
                    HStack(spacing:6) {
                        Text(L(scene.name)).font(.system(size:13,weight:.semibold)).lineLimit(1)
                        if model.activeFanSceneID==scene.id {Image(systemName:"checkmark.circle.fill").font(.system(size:11)).foregroundColor(Palette.violet).help(L("使用中"))}
                    }
                    Text(apps.isEmpty ? L("未关联应用"):apps.map(\.name).joined(separator:" · "))
                        .font(.system(size:11)).foregroundColor(Palette.secondaryText).lineLimit(1)
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            if renaming==scene.id {
                Button {saveRename(scene)} label:{Image(systemName:"checkmark")}.buttonStyle(.borderless).accessibilityLabel(L("保存名称"))
                Button {renaming=nil} label:{Image(systemName:"xmark")}.buttonStyle(.borderless).accessibilityLabel(L("取消"))
            } else {
                FanSceneApplicationsPicker(model:model,scene:scene)
                Button(L("使用")){model.applyFanScene(scene.id);onClose()}.buttonStyle(AppChoiceButtonStyle())
                Menu {
                    Button(L("编辑曲线")){model.applyFanScene(scene.id);onClose()}
                    Button(L("重命名")){renameText=L(scene.name);renaming=scene.id}
                    Divider()
                    Button(L("删除场景")){deletion=scene}
                } label:{Image(systemName:"ellipsis").frame(width:16)}.menuStyle(.borderlessButton).fixedSize()
                    .help(L("更多操作")).accessibilityLabel(L("更多操作")+" · "+L(scene.name))
            }
        }.padding(10).background(Palette.surface).cornerRadius(11)
            .appOverlay {RoundedRectangle(cornerRadius:11).stroke(model.activeFanSceneID==scene.id ? Palette.controlBorder:Palette.border.opacity(0.5),lineWidth:0.5)}
            .disabled(model.busy)
    }
    private func saveRename(_ scene:FanScene) {
        if model.renameFanScene(scene.id,name:renameText) {renaming=nil}
    }
}

enum FanSceneArtwork {
    static func symbol(_ scene:FanScene)->String {
        switch scene.id {
        case FanScene.defaults[0].id:return "scissors"
        case FanScene.defaults[1].id:return "gamecontroller"
        case FanScene.defaults[2].id:return "briefcase"
        case FanScene.defaults[3].id:return "play.rectangle"
        case FanScene.defaults[4].id:return "chevron.left.forwardslash.chevron.right"
        default:return "slider.horizontal.3"
        }
    }
}
