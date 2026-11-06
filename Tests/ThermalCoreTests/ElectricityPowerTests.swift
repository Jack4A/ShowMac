import Foundation
import ThermalCore

struct ElectricityPowerTests {
    let start=Date(timeIntervalSince1970:1_800_000_000)
    func testRealSamplesSurviveCompaction()throws {
        var history=ElectricityPowerHistory(),original:[Date:Double]=[:]
        for i in 0..<120 {
            let date=start.addingTimeInterval(Double(i)*10),watts=Double(i==40 ? 500:(i==61 ? 1:20+i%10))
            original[date]=watts;history.record(watts,source:.system,at:date)
            history.record(80,source:.dcInput,at:date)
        }
        history.compact(at:start.addingTimeInterval(9*86400))
        expectTrue(history.archive.envelopes.allSatisfy{$0.resolution==3600 && $0.samples.count<=4})
        let restored=try ElectricityPowerHistory(archive:JSONDecoder().decode(ElectricityPowerHistory.Archive.self,from:JSONEncoder().encode(history.archive)))
        let points=restored.records(source:.system,in:DateInterval(start:start,duration:3600))
        expectEqual(points.count,4)
        expectTrue(points.allSatisfy{original[$0.date]==$0.value})
        expectTrue(points.contains{$0.value==500});expectTrue(points.contains{$0.value==1})
        expectEqual(points.first?.date,start)
        expectEqual(points.last?.date,start.addingTimeInterval(1190))
        expectTrue(restored.records(source:.dcInput,in:DateInterval(start:start,duration:3600)).allSatisfy{$0.value==80})
    }
    func testGapsAndRestartStaySeparate()throws {
        var history=ElectricityPowerHistory()
        history.record(10,source:.system,at:start)
        history.record(20,source:.system,at:start.addingTimeInterval(10))
        history.record(nil,source:.system,at:start.addingTimeInterval(15))
        history.record(30,source:.system,at:start.addingTimeInterval(20))
        history.record(40,source:.system,at:start.addingTimeInterval(30))
        history.record(50,source:.system,at:start.addingTimeInterval(3600))
        let range=DateInterval(start:start,duration:7200)
        let records=history.records(source:.system,in:range)
        expectEqual(Set(records.map(\.segment)).count,3)
        let groups=Dictionary(grouping:records,by:\.segment)
        expectNil(ElectricityPowerHistory.nearest(in:groups,at:start.addingTimeInterval(16)))
        let nearest=ElectricityPowerHistory.nearest(in:groups,at:start.addingTimeInterval(8))
        expectEqual(nearest?.date,start.addingTimeInterval(10));expectEqual(nearest?.value,20)
        var restored=try ElectricityPowerHistory(archive:history.archive)
        restored.record(60,source:.system,at:start.addingTimeInterval(3610))
        let after=restored.records(source:.system,in:range)
        expectEqual(Set(after.map(\.segment)).count,4)
        expectNil(ElectricityPowerHistory.nearest(in:Dictionary(grouping:after,by:\.segment),at:start.addingTimeInterval(3605)))
    }
    func testRejectsInvalidAndDoesNotInventLegacyPower()throws {
        var history=ElectricityPowerHistory()
        history.record(10,source:.system,at:start)
        history.record(.nan,source:.system,at:start.addingTimeInterval(1))
        history.record(-1,source:.system,at:start.addingTimeInterval(2))
        history.record(20,source:.system,at:start.addingTimeInterval(3))
        history.record(1000,source:.system,at:start.addingTimeInterval(3))
        history.record(1000,source:.system,at:start.addingTimeInterval(2))
        let points=history.records(source:.system,in:DateInterval(start:start,duration:60))
        expectEqual(points.compactMap(\.value),[10,20])
        expectEqual(Set(points.map(\.segment)).count,2)
        let data=try JSONEncoder().encode(history.archive)
        var object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        object["version"]=999
        expectThrows(try ElectricityPowerHistory(archive:JSONDecoder().decode(ElectricityPowerHistory.Archive.self,from:JSONSerialization.data(withJSONObject:object))))
        expectTrue(ElectricityPowerHistory().records(source:.system,in:DateInterval(start:start,duration:3600)).isEmpty)
    }
}
