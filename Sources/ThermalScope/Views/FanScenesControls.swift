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
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text(L("场景模式")).font(.system(size:18,weight:.semibold));Spacer()
                Button(L("完成"),action:onClose).keyboardShortcut(.cancelAction)
            }
            Text(L("改名后按回车保存；选中场景后，拖动主界面曲线即可更新曲线和温度来源。"))
                .font(.system(size:12)).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
            List {
                ForEach(model.fanScenes.scenes) {scene in
                    HStack(spacing:12) {
                        FanSceneNameField(model:model,scene:scene)
                        if model.activeFanSceneID==scene.id {Text(L("使用中")).font(.system(size:11)).foregroundColor(Palette.violet)}
                        Button {deletion=scene} label:{Image(systemName:AppSymbols.resolve("minus.circle"))}
                            .buttonStyle(.borderless).help(L("删除场景")).accessibilityLabel(L("删除场景")+" · "+scene.name)
                    }.padding(.vertical,5).listRowBackground(Palette.surface)
                }
            }.listStyle(.inset).appChoiceListSurface()
            if model.messageIsError {Text(L(model.message)).font(.system(size:11)).foregroundColor(.orange).fixedSize(horizontal:false,vertical:true)}
            Divider()
            Text(L("保存当前曲线")).font(.system(size:12,weight:.medium))
            HStack {
                TextField(L("场景名称"),text:$name).textFieldStyle(.roundedBorder).accessibilityIdentifier("newFanSceneName")
                Button(L("保存并使用")) {if model.saveFanScene(name:name,curve:curve) {onClose()}}
                    .buttonStyle(AppChoiceButtonStyle()).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.fanScenes.scenes.count>=FanSceneConfiguration.limit)
                    .accessibilityIdentifier("saveFanScene")
            }
        }.padding(20).frame(width:460,height:440).appBackground{Palette.canvas}.foregroundColor(Palette.primaryText)
            .disabled(model.busy)
            .alert(item:$deletion) {scene in
                Alert(title:Text(String(format:L("删除“%@”场景？"),scene.name)),
                      message:Text(L(model.activeFanSceneID==scene.id ? "当前场景会停止，风扇恢复系统自动。":"其他场景保持不变。")),
                      primaryButton:.destructive(Text(L("删除"))){model.deleteFanScene(scene.id)},secondaryButton:.cancel(Text(L("取消"))))
            }
    }
}

private struct FanSceneNameField:View {
    @ObservedObject var model:AppModel
    let scene:FanScene
    @State private var name:String
    init(model:AppModel,scene:FanScene) {self.model=model;self.scene=scene;_name=State(initialValue:L(scene.name))}
    var body:some View {
        TextField(L("场景名称"),text:$name,onCommit:{
            if name != L(scene.name),!model.renameFanScene(scene.id,name:name) {name=L(scene.name)}
        }).textFieldStyle(.plain).font(.system(size:13))
            .help(L("输入名称后按回车保存"))
            .accessibilityLabel(L("场景名称")+" · "+L(scene.name))
            .onChange(of:scene.name){name=L($0)}
    }
}
