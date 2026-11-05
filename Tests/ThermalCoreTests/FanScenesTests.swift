import Foundation
import ThermalCore

final class FanScenesTests {
    func testSceneStorageAndRestoration() throws {
        var settings=FanSceneConfiguration()
        expectEqual(settings.scenes.map(\.name),["剪辑","游戏","办公","影音","编程"])
        expectEqual(settings.duration,.continuous);expectNil(settings.resumeSelection)
        let original=settings.scenes[0]
        var curve=original.curve;curve.sensor = .gpu;curve.movePoint(2,temperature:63.75,percent:70.125)
        let scene=try settings.save(name:"  我的剪辑  ",curve:curve)
        settings.selection = .scene(scene.id)
        let data=try JSONEncoder().encode(settings)
        let restored=FanSceneConfiguration.decode(data)
        expectEqual(restored,settings);expectEqual(restored.curve(custom:.quiet),curve)
        expectEqual(restored.resumeSelection,.scene(scene.id))
        _=try settings.save(name:"GPU 剪辑",curve:curve,id:scene.id)
        expectEqual(settings.scenes.count,6);expectEqual(settings.scenes.last?.id,scene.id)
        settings.restoreOnLaunch=false;expectNil(settings.resumeSelection)
        settings.restoreOnLaunch=true;settings.remove(scene.id)
        expectTrue(settings.selection.isAutomatic);expectNil(settings.resumeSelection)
        settings.selection = .strategy(.custom)
        expectEqual(settings.curve(custom:curve),curve);expectNil(settings.resumeSelection)
        settings.confirmedCustomCurve=curve
        expectEqual(settings.resumeSelection,.strategy(.custom))
        expectEqual(settings.curve(custom:.quiet),curve)
        settings.selection = .strategy(.quiet);expectEqual(settings.curve(custom:curve),.quiet)
    }
    func testInvalidScenesCannotRestoreOrOverwrite() throws {
        var settings=FanSceneConfiguration()
        expectThrows(try settings.save(name:" ",curve:.balanced))
        expectThrows(try settings.save(name:"游戏",curve:.quiet))
        expectThrows(try settings.save(name:"name\nline",curve:.quiet))
        expectThrows(try settings.save(name:String(repeating:"x",count:81),curve:.quiet))
        var invalid=FanScene(name:"invalid",curve:.balanced);invalid.curve.points[0].percent=Double.nan
        expectThrows(try invalid.validate())
        let id=settings.scenes[0].id
        settings.scenes.append(settings.scenes[0]);settings.scenes.append(.init(name:"different ID",curve:.quiet));settings.scenes[settings.scenes.count-1].id="invalid"
        settings.selection = .scene("deleted")
        let restored=FanSceneConfiguration.decode(try JSONEncoder().encode(settings))
        expectEqual(restored.scenes.count,5);expectEqual(restored.scenes[0].id,id)
        expectTrue(restored.selection.isAutomatic)
        expectEqual(FanSceneConfiguration.decode(Data("not json".utf8)),FanSceneConfiguration())
        var many=FanSceneConfiguration(scenes:[])
        for i in 0..<FanSceneConfiguration.limit {_=try many.save(name:"Scene \(i)",curve:.balanced)}
        expectThrows(try many.save(name:"overflow",curve:.balanced))
        expectEqual(many.scenes.count,FanSceneConfiguration.limit)
    }
    func testContinuousControlOutlivesThirtyMinutesAndStops() throws {
        let fans=FakeFans();var clock=0.0;var targets:[FanControlProgress]=[]
        try CurveLease.run(hardware:fans,curve:.balanced,continuous:true,sample:{CurveTests().snapshot(clock>=3600 ? 95:60)},now:{clock},isCancelled:{clock>=7200},wait:{clock+=1800},onUpdate:{targets.append($0)})
        expectEqual(clock,7200);expectEqual(targets.count,4)
        expectTrue(targets.allSatisfy{$0.deadline.isInfinite})
        expectEqual(targets.last?.targets.map(\.rpm),[5500,5500]);expectEqual(fans.modes,[false,false])
        let missing=FakeFans();clock=0
        expectThrows(try CurveLease.run(hardware:missing,curve:.balanced,continuous:true,sample:{CurveTests().snapshot(clock<3600 ? 60:nil)},now:{clock},isCancelled:{false},wait:{clock+=1800}))
        expectEqual(missing.modes,[false,false]);expectEqual(clock,3600)
        let cancelled=FakeFans()
        try CurveLease.run(hardware:cancelled,curve:.balanced,continuous:true,sample:{CurveTests().snapshot()},now:{0},isCancelled:{true},wait:{})
        expectTrue(cancelled.writes.isEmpty)
    }
    func testTimedControlAndProtocolBoundaries() throws {
        let fans=FakeFans();var clock=0.0
        try CurveLease.run(hardware:fans,curve:.balanced,duration:3600,sample:{CurveTests().snapshot()},now:{clock},isCancelled:{false},wait:{clock+=1800})
        expectEqual(clock,3600);expectEqual(fans.modes,[false,false])
        try ControlRequest("profile",profile:"custom",curve:.balanced,continuous:true).validate()
        try ControlRequest("profile",profile:"custom",curve:.quiet,duration:7200).validate()
        expectThrows(try ControlRequest("test-fans",continuous:true).validate())
        expectThrows(try ControlRequest("auto",continuous:true).validate())
        expectThrows(try ControlRequest("profile",profile:"custom",curve:.quiet,duration:1800,continuous:true).validate())
        for invalid in [Double.nan,.infinity,-1,0,86401] {expectThrows(try ControlRequest("profile",profile:"custom",curve:.quiet,duration:invalid).validate())}
        let old=try JSONDecoder().decode(FanSessionStatus.self,from:Data(#"{"remainingSeconds":100,"targets":[],"protectionActive":false}"#.utf8))
        expectNil(old.continuous)
        let continuous=FanSessionStatus(remainingSeconds:0,targets:[],protectionActive:false,continuous:true)
        expectEqual(try JSONDecoder().decode(FanSessionStatus.self,from:JSONEncoder().encode(continuous)),continuous)
        expectNil(FanControlDuration.continuous.seconds);expectEqual(FanControlDuration.hours2.seconds,7200)
    }
}
