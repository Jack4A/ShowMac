import Foundation
import ThermalCore

final class FanTelemetryTests {
    func testProgressFollowsVerifiedTargetsAndProtection() throws {
        let fans=FakeFans();var clock=0.0;var updates:[FanControlProgress]=[]
        try CurveLease.run(hardware:fans,curve:.balanced,duration:4,sample:{CurveTests().snapshot(clock<2 ? 60:95)},now:{clock},isCancelled:{false},wait:{clock+=2},onUpdate:{progress in
            expectEqual(progress.targets.map(\.id),[0,1])
            expectEqual(progress.targets.map(\.rpm),fans.targets)
            expectTrue(fans.modes.allSatisfy{$0})
            updates.append(progress)
        })
        expectEqual(updates.count,2)
        expectEqual(updates.map(\.deadline),[4,4])
        expectEqual(updates.map(\.protectionActive),[false,true])
        expectEqual(updates.last?.targets.map(\.rpm),[5500,5500])
        expectEqual(fans.modes,[false,false])
        fans.failTarget=1;var reported=false
        expectThrows(try CurveLease.run(hardware:fans,curve:.balanced,sample:{CurveTests().snapshot()},now:{0},isCancelled:{false},wait:{},onUpdate:{_ in reported=true}))
        expectFalse(reported)
        expectEqual(fans.modes,[false,false])
    }
    func testReplyMetadataCompatibility() throws {
        let old=Data("{\"ok\":true,\"message\":\"automatic\"}".utf8)
        expectNil(try JSONDecoder().decode(ControlReply.self,from:old).fanStatus)
        let status=FanSessionStatus(remainingSeconds:1200,targets:[FanTarget(id:0,rpm:2500),FanTarget(id:1,rpm:3200)],protectionActive:true)
        let reply=ControlReply(ok:true,message:"confirmed",session:"session",profile:"custom",fanStatus:status)
        let decoded=try JSONDecoder().decode(ControlReply.self,from:JSONEncoder().encode(reply))
        expectEqual(decoded.fanStatus,status)
    }
    func testRPMInputUsesRatedRangeAndThermalRamp() {
        expectEqual(CurvePolicy.percent(rpm:2950,minimum:1000,maximum:4900),50)
        expectEqual(CurvePolicy.percent(rpm:0,minimum:1000,maximum:4900),0)
        expectEqual(CurvePolicy.percent(rpm:9999,minimum:1000,maximum:4900),100)
        expectEqual(CurvePolicy.percent(rpm:.nan,minimum:1000,maximum:4900),0)
        expectEqual(CurvePolicy.percent(rpm:2000,minimum:2000,maximum:2000),0)
        let manual=FanCurve.manual(percent:50)
        expectEqual(manual.percent(at:70),50)
        expectEqual(manual.percent(at:85),75)
        expectEqual(manual.percent(at:90),100)
    }
}
