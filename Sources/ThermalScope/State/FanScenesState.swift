import Foundation
import ThermalCore

extension AppModel {
    var activeFanScene:FanScene? {
        guard activeProfile != nil,let id=activeFanSceneID,let curve=sessionCurve else{return nil}
        return fanScenes.scenes.first{$0.id==id && $0.curve==curve}
    }
    var fanControlSummary:String {
        if systemFansAutomatic {return "系统自动由 macOS 调速，下方曲线尚未启用。"}
        return fanScenes.duration == .continuous ? "持续运行，退出软件时交回 macOS；高温保护始终有效。":"到期交回 macOS；高温保护始终有效。"
    }
    func confirmFanSelection(_ selection:FanModeSelection,curve:FanCurve,automatic:Bool=false) {
        fanRestorePending=false
        var settings=fanScenes;settings.selection=selection
        if selection == .strategy(.custom) {settings.confirmedCustomCurve=curve}
        fanScenes=settings
        if !automatic {fanAutomation.manualSelection=selection}
        if case .scene(let id)=selection {activeFanSceneID=id}
        else {activeFanSceneID=nil;if selection == .strategy(.custom) {customCurve=curve}}
    }
    func applyFanScene(_ id:String) {
        guard !busy,let scene=fanScenes.scenes.first(where:{$0.id==id}) else{return}
        guard isFanControlPreview || ControlAvailability.fansAvailable(snapshot) else {report("传感器或风扇暂不可用，未应用场景。",error:true);return}
        fanRestorePending=false
        applyFanCurve(scene.curve,name:scene.name,selection:.scene(id))
    }
    func applyEditedFanCurve(_ curve:FanCurve) {
        guard !busy,(try? curve.validate()) != nil else{return}
        if let scene=activeFanScene {
            do {
                _=try fanScenes.save(name:scene.name,curve:curve,id:scene.id)
                applyFanCurve(curve,name:scene.name,selection:.scene(scene.id))
            }catch {report(error.localizedDescription,error:true)}
        } else {customCurve=curve;applyCustomCurve()}
    }
    func setFanDuration(_ duration:FanControlDuration) {
        guard !busy,fanScenes.duration != duration else{return}
        fanScenes.duration=duration
        guard let curve=sessionCurve,coolingToken != nil else{return}
        let selection:FanModeSelection=activeFanSceneID.map{.scene($0)} ?? fanScenes.selection
        let previous=fanAutomationApplying
        fanAutomationApplying=fanAutomation.enabled
        defer {fanAutomationApplying=previous}
        applyFanCurve(curve,name:activeFanScene?.name ?? controlName,selection:selection)
    }
    func saveFanScene(name:String,curve:FanCurve)->Bool {
        do {
            let scene=try fanScenes.save(name:name,curve:curve)
            applyFanScene(scene.id);return true
        }catch {report(error.localizedDescription,error:true);return false}
    }
    func renameFanScene(_ id:String,name:String)->Bool {
        guard !busy,let scene=fanScenes.scenes.first(where:{$0.id==id}) else{return false}
        do {_=try fanScenes.save(name:name,curve:scene.curve,id:id);return true}
        catch {report(error.localizedDescription,error:true);return false}
    }
    func deleteFanScene(_ id:String) {
        guard !busy else{return}
        if activeFanSceneID==id {restoreAuto()}
        fanAutomation.removeScene(id)
        fanScenes.remove(id)
        fanAutomationLastAttempt=nil;scheduleFanAutomation()
    }
    func prepareFanRestoration() {
        fanRestorePending = !isFanControlPreview && !fanAutomation.enabled && AppDistribution.hardwareControlAvailable && fanScenes.resumeSelection != nil
        fanRestoreDeadline=Date().addingTimeInterval(30)
    }
    func restoreSavedFanModeIfNeeded() {
        guard fanRestorePending,!fanAutomation.enabled,!isFanControlPreview,!fanSuspending,!busy else{return}
        guard coolingToken==nil else{return}
        guard let snapshot,ControlAvailability.fansAvailable(snapshot),fanScenes.curve(custom:customCurve)?.sensor.temperature(in:snapshot) != nil else {
            if Date()>fanRestoreDeadline {fanRestorePending=false;report("上次的风扇模式未恢复：传感器或风扇暂不可用。",error:true)}
            return
        }
        fanRestorePending=false
        guard snapshot.fans.allSatisfy({$0.manual==false}) else {report("上次的风扇模式未恢复：风扇正由其他程序控制。",error:true);return}
        switch fanScenes.selection {
        case .strategy(.custom):
            if let curve=fanScenes.curve(custom:customCurve) {applyFanCurve(curve,name:"自定义曲线")}
        case .strategy(let strategy):applyFanStrategy(strategy)
        case .scene(let id):applyFanScene(id)
        }
    }
}
