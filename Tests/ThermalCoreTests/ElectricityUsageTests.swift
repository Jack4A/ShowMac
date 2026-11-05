import Foundation
import ThermalCore

struct ElectricityUsageTests {
    private let start=Date(timeIntervalSince1970:1_800_000_000)
    func testIntegrationAndSources() {
        var history=ElectricityHistory(createdAt:start)
        for i in 0...360 {
            let date=start.addingTimeInterval(Double(i)*10)
            history.record(100,source:.system,at:date)
            history.record(120,source:.dcInput,at:date)
        }
        let range=DateInterval(start:start,duration:3600)
        let total=history.totals(source:.system,in:range)
        expectEqual(total.wattHours,100,accuracy:0.000001)
        expectEqual(total.observedSeconds,3600,accuracy:0.000001)
        expectEqual(total.averageWatts!,100,accuracy:0.000001)
        expectEqual(total.kilowattHours,0.1,accuracy:0.000001)
        expectEqual(total.cost(rate:0.6)!,0.06,accuracy:0.000001)
        expectEqual(history.totals(source:.dcInput,in:range).wattHours,120,accuracy:0.000001)
        expectNil(total.cost(rate:nil));expectNil(total.cost(rate:-1));expectNil(total.cost(rate:.infinity))
        expectEqual(total.cost(rate:0),0)
        var ramp=ElectricityHistory(createdAt:start)
        ramp.record(0,source:.system,at:start);ramp.record(100,source:.system,at:start.addingTimeInterval(10))
        expectEqual(ramp.totals(source:.system,in:range).wattHours,50*10/3600,accuracy:0.000001)
    }
    func testOutagesSleepAndRestart()throws {
        var history=ElectricityHistory(createdAt:start)
        history.record(100,source:.system,at:start)
        history.record(100,source:.system,at:start.addingTimeInterval(10))
        history.record(nil,source:.system,at:start.addingTimeInterval(15))
        history.record(100,source:.system,at:start.addingTimeInterval(20))
        history.record(100,source:.system,at:start.addingTimeInterval(30))
        history.record(100,source:.system,at:start.addingTimeInterval(3600))
        history.record(100,source:.system,at:start.addingTimeInterval(3610))
        history.breakContinuity()
        history.record(100,source:.system,at:start.addingTimeInterval(3615))
        history.record(100,source:.system,at:start.addingTimeInterval(3625))
        let range=DateInterval(start:start,duration:7200)
        expectEqual(history.totals(source:.system,in:range).observedSeconds,40,accuracy:0.000001)
        let data=try JSONEncoder().encode(history.archive)
        var restarted=try ElectricityHistory(archive:JSONDecoder().decode(ElectricityHistory.Archive.self,from:data))
        restarted.record(100,source:.system,at:start.addingTimeInterval(3630))
        expectEqual(restarted.totals(source:.system,in:range).observedSeconds,40,accuracy:0.000001)
        restarted.record(100,source:.system,at:start.addingTimeInterval(3640))
        expectEqual(restarted.totals(source:.system,in:range).observedSeconds,50,accuracy:0.000001)
    }
    func testInvalidReadingsAndClockJumps() {
        var history=ElectricityHistory(createdAt:start)
        history.record(100,source:.system,at:start)
        history.record(100,source:.system,at:start.addingTimeInterval(10))
        history.record(1000,source:.system,at:start.addingTimeInterval(10))
        history.record(1000,source:.system,at:start.addingTimeInterval(5))
        history.record(100,source:.system,at:start.addingTimeInterval(20))
        history.record(-100,source:.system,at:start.addingTimeInterval(25))
        history.record(.nan,source:.system,at:start.addingTimeInterval(30))
        history.record(10001,source:.system,at:start.addingTimeInterval(35))
        history.record(100,source:.system,at:start.addingTimeInterval(40))
        history.record(100,source:.system,at:start.addingTimeInterval(50))
        let total=history.totals(source:.system,in:DateInterval(start:start,duration:3600))
        expectEqual(total.observedSeconds,30,accuracy:0.000001)
        expectEqual(total.wattHours,100*30/3600,accuracy:0.000001)
    }
    func testCalendarBoundariesAndDST() {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
        let midnight=calendar.startOfDay(for:start)
        var history=ElectricityHistory(createdAt:midnight.addingTimeInterval(-10))
        history.record(360,source:.system,at:midnight.addingTimeInterval(-10))
        history.record(360,source:.system,at:midnight.addingTimeInterval(10),maximumGap:30)
        expectEqual(history.totals(source:.system,in:ElectricityPeriod.day.interval(containing:midnight,calendar:calendar)).wattHours,1,accuracy:0.000001)
        expectEqual(history.totals(source:.system,in:ElectricityPeriod.day.interval(containing:midnight.addingTimeInterval(-1),calendar:calendar)).wattHours,1,accuracy:0.000001)
        calendar.timeZone=TimeZone(identifier:"America/Los_Angeles")!
        let spring=calendar.date(from:DateComponents(year:2026,month:3,day:8,hour:12))!
        let fall=calendar.date(from:DateComponents(year:2026,month:11,day:1,hour:12))!
        expectEqual(ElectricityPeriod.day.interval(containing:spring,calendar:calendar).duration,23*3600)
        expectEqual(ElectricityPeriod.day.chartIntervals(containing:spring,calendar:calendar).count,23)
        expectEqual(ElectricityPeriod.day.chartIntervals(containing:fall,calendar:calendar).count,25)
        expectEqual(ElectricityPeriod.year.chartIntervals(containing:fall,calendar:calendar).count,12)
        expectEqual(ElectricityPeriod.week.chartIntervals(containing:fall,calendar:calendar).count,7)
    }
    func testArchiveValidation()throws {
        let malformed="{\"version\":2,\"createdAt\":0,\"buckets\":[]}".data(using:.utf8)!
        expectThrows(try ElectricityHistory(archive:JSONDecoder().decode(ElectricityHistory.Archive.self,from:malformed)))
        var history=ElectricityHistory(createdAt:start)
        history.record(100,source:.system,at:start);history.record(100,source:.system,at:start.addingTimeInterval(10))
        let data=try JSONEncoder().encode(history.archive)
        var object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        var buckets=object["buckets"] as! [[String:Any]]
        buckets[0]["wattHours"] = -1;object["buckets"]=buckets
        let bad=try JSONSerialization.data(withJSONObject:object)
        expectThrows(try ElectricityHistory(archive:JSONDecoder().decode(ElectricityHistory.Archive.self,from:bad)))
        object["buckets"]=Array(repeating:(try JSONSerialization.jsonObject(with:data) as! [String:Any])["buckets"] as! [[String:Any]],count:2).flatMap{$0}
        expectThrows(try ElectricityHistory(archive:JSONDecoder().decode(ElectricityHistory.Archive.self,from:JSONSerialization.data(withJSONObject:object))))
    }
}
