import Foundation
import WidgetShared

struct WidgetTests {
    func sample(at date:Date)->WidgetSnapshot {WidgetSnapshot(date:date,cpuTemperature:70,gpuTemperature:nil,storageTemperature:35,cpuUsage:20,fans:[WidgetFan(id:0,rpm:2000,maximum:5000,manual:false)],mode:"系统自动",turbo:"已关闭",language:"zh-Hans")}
    func testFreshnessAndMissingValues() {
        let date=Date(timeIntervalSince1970:1000);var s=sample(at:date)
        expectEqual(s.freshness(at:date),.recent);expectEqual(s.freshness(at:date.addingTimeInterval(301)),.previous)
        expectEqual(s.freshness(at:date.addingTimeInterval(86401)),.unavailable);expectEqual(s.freshness(at:date.addingTimeInterval(-121)),.unavailable)
        s.running=false;expectEqual(s.freshness(at:date),.paused);expectNil(s.gpuTemperature)
        let invalid=WidgetSnapshot(date:date,cpuTemperature:.nan,gpuTemperature:160,storageTemperature:-1,cpuUsage:101,fans:[WidgetFan(id:0,rpm:-1,maximum:.infinity,manual:nil),WidgetFan(id:0,rpm:3000,maximum:5000,manual:true)],mode:"",turbo:"",language:"")
        expectNil(invalid.cpuTemperature);expectNil(invalid.gpuTemperature);expectNil(invalid.cpuUsage);expectNil(invalid.fans.first?.rpm);expectNil(invalid.fans.first?.manual);expectEqual(invalid.fans.count,1)
    }
    func testBoundedRoundtripAndAtomicStorage() throws {
        let now=Date(timeIntervalSince1970:2000)
        let points=(0..<250).reversed().map{WidgetPoint(date:now.addingTimeInterval(Double($0-200)),value:Double($0),segment:0)}
        var s=sample(at:now)
        s=WidgetSnapshot(date:now,cpuTemperature:s.cpuTemperature,gpuTemperature:nil,storageTemperature:nil,cpuUsage:s.cpuUsage,fans:s.fans,mode:s.mode,turbo:s.turbo,language:s.language,trends:["cpuUsage":points])
        expectTrue((s.trends["cpuUsage"]?.count ?? 0)<=120);expectTrue(s.trends["cpuUsage"]!.allSatisfy{$0.date<=now})
        let encoded=try JSONEncoder().encode(s),decoded=try WidgetSnapshot.decode(encoded)
        expectEqual(decoded,s)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("ThermalScope-widget-check-"+UUID().uuidString),url=folder.appendingPathComponent("status.json")
        defer {try? FileManager.default.removeItem(at:folder)}
        try WidgetStorage.write(s,to:url);expectEqual(WidgetStorage.read(from:url),s)
        var unknown=s;unknown.schema=999;expectThrows(try WidgetSnapshot.decode(JSONEncoder().encode(unknown)))
        expectThrows(try WidgetSnapshot.decode(Data(repeating:0,count:262145)))
    }
    func testNavigationOnlyURLs() {
        for metric in WidgetMetric.allCases {expectEqual(WidgetRoute(WidgetRoute.metric(metric).url),.metric(metric))}
        expectEqual(WidgetRoute(WidgetRoute.overview.url),.overview);expectEqual(WidgetRoute(WidgetRoute.thermal.url),.thermal)
        for value in ["thermalscope://turbo-disable","thermalscope://metric/cpuUsage?command=auto","thermalscope://metric/../../thermal","https://metric/cpuUsage","thermalscope://metric/cpuUsage#run","thermalscope://user:pass@metric/cpuUsage","thermalscope://metric:55/fan"] {expectNil(WidgetRoute(URL(string:value)!))}
    }
    func testReloadCoalescingKeepsConfirmedState() {
        var schedule=WidgetPublishSchedule();let base=Date(timeIntervalSince1970:1000)
        let first=schedule.receive(date:base,state:"automatic")
        expectTrue(first.write);expectTrue(first.reload)
        let pending=schedule.receive(date:base.addingTimeInterval(5),state:"waiting")
        expectTrue(pending.write);expectFalse(pending.reload)
        let confirmed=schedule.receive(date:base.addingTimeInterval(10),state:"performance")
        expectTrue(confirmed.write);expectFalse(confirmed.reload)
        expectFalse(schedule.receive(date:base.addingTimeInterval(20),state:"performance").write)
        let final=schedule.receive(date:base.addingTimeInterval(70),state:"performance")
        expectTrue(final.write);expectTrue(final.reload)
        expectFalse(schedule.receive(date:base.addingTimeInterval(130),state:"performance").reload)
        expectTrue(schedule.receive(date:base.addingTimeInterval(1870),state:"performance").reload)
    }
}
