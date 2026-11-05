import Foundation
import ThermalCore

final class FanAutomationTests {
    let editor=FanApplication(bundleID:"com.example.editor",name:"Editor")
    let game=FanApplication(bundleID:"com.example.game",name:"Game")
    func testForegroundPriorityAndWorkloadLifetime() throws {
        let scenes=FanScene.defaults
        var rules=FanSceneAutomation(enabled:true,manualSelection:.strategy(.quiet))
        try rules.associate(editor,with:scenes[0].id);try rules.associate(game,with:scenes[1].id)
        let both=[editor,game]
        let gaming=rules.decision(running:both,frontmost:game.id,current:editor.id,scenes:scenes)
        expectEqual(gaming?.selection,.scene(scenes[1].id));expectEqual(gaming?.application,game)
        // Looking at ShowMac or an unrelated app must not bounce out of a running game.
        expectEqual(rules.decision(running:both,frontmost:"com.example.other",current:game.id,scenes:scenes),gaming)
        expectEqual(rules.decision(running:[editor],frontmost:nil,current:game.id,scenes:scenes)?.selection,.scene(scenes[0].id))
        expectEqual(rules.decision(running:[],frontmost:nil,current:editor.id,scenes:scenes)?.selection,.strategy(.quiet))
        rules.enabled=false;expectNil(rules.decision(running:both,frontmost:game.id,current:nil,scenes:scenes))
    }
    func testMappingsMoveAndSurviveRelaunch() throws {
        let scenes=FanScene.defaults
        var rules=FanSceneAutomation(enabled:true)
        try rules.associate(editor,with:scenes[0].id);try rules.associate(game,with:scenes[1].id)
        try rules.associate(editor,with:scenes[4].id)
        expectEqual(rules.rules.count,2);expectEqual(rules.rules[0].sceneID,scenes[4].id)
        rules.manualSelection = .scene(scenes[2].id)
        expectEqual(FanSceneAutomation.decode(try JSONEncoder().encode(rules),scenes:scenes),rules)
        var renamed=scenes;renamed[4].name="My code"
        expectEqual(rules.decision(running:[editor],frontmost:editor.id,current:nil,scenes:renamed)?.selection,.scene(scenes[4].id))
        rules.removeScene(scenes[2].id);expectTrue(rules.manualSelection.isAutomatic)
        rules.removeApplication(editor.id);expectEqual(rules.rules.count,1)
        rules.removeScene(scenes[1].id);expectTrue(rules.rules.isEmpty)
    }
    func testUntrustedRulesAreBoundedAndDeletedScenesDoNotRun() throws {
        let scenes=FanScene.defaults
        var rules=FanSceneAutomation(enabled:true,manualSelection:.scene("deleted"))
        expectThrows(try rules.associate(.init(bundleID:"/Applications/App.app",name:"Invalid"),with:scenes[0].id))
        expectThrows(try rules.associate(.init(bundleID:"com.example.bad",name:"name\ncontrol"),with:scenes[0].id))
        try rules.associate(editor,with:scenes[0].id)
        rules.rules.append(rules.rules[0]);rules.rules.append(.init(application:game,sceneID:"deleted"))
        let decoded=FanSceneAutomation.decode(try JSONEncoder().encode(rules),scenes:scenes)
        expectEqual(decoded.rules.count,1);expectTrue(decoded.manualSelection.isAutomatic)
        expectEqual(decoded.decision(running:[editor],frontmost:editor.id,current:nil,scenes:Array(scenes.dropFirst()))?.selection,.strategy(.system))
        expectEqual(FanSceneAutomation.decode(Data("invalid".utf8),scenes:scenes),FanSceneAutomation())
        var many=FanSceneAutomation()
        for i in 0..<FanSceneAutomation.limit {try many.associate(.init(bundleID:"com.example.app\(i)",name:"App \(i)"),with:scenes[0].id)}
        expectThrows(try many.associate(editor,with:scenes[0].id))
    }
}
