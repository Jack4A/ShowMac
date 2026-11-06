import Foundation
import ThermalCore

struct TokenUsageTests {
    func payload(_ events:[[String:Any]]=[])->Data {
        try! JSONSerialization.data(withJSONObject:["version":1,"engine":"tokscale","commit":AgentUsageEngine.commit,"sources":TokenProvider.allCases.map{["provider":$0.rawValue,"state":"ready","records":events.count] as [String:Any]},"events":events])
    }
    func event(_ provider:String="opencode",input:Int64=60,other:Int64=7)->[String:Any] {
        ["id":"request","provider":provider,"timestampMs":1793923200000,"model":"example","input":input,"output":5,"cacheRead":30,"cacheWrite":20,"reasoning":0,"unclassified":other]
    }
    func testAllUpstreamSourcesAreExposed()throws {
        expectEqual(TokenProvider.allCases.count,60)
        expectEqual(Set(TokenProvider.allCases.map(\.rawValue)).count,60)
        let snapshot=try AgentUsageEngine.decode(payload())
        expectEqual(snapshot.sourceStates.count,60)
    }
    func testBridgeCountersAndPrivacy()throws {
        let snapshot=try AgentUsageEngine.decode(payload([event(),event()]))
        expectEqual(snapshot.events.count,1);expectEqual(snapshot.events[0].counts.total,72)
        expectEqual(snapshot.events[0].counts.input,60);expectEqual(snapshot.events[0].counts.unclassified,7)
        let date=snapshot.events[0].date
        expectEqual(date,Date(timeIntervalSince1970:1793923200))
        let encoded=String(decoding:try JSONEncoder().encode(snapshot),as:UTF8.self)
        expectFalse(encoded.contains("content"));expectFalse(encoded.contains("projectPath"))
    }
    func testInvalidProtocolAndCounts()throws {
        var object=try JSONSerialization.jsonObject(with:payload()) as! [String:Any]
        object["commit"]="unexpected"
        expectThrows(try AgentUsageEngine.decode(JSONSerialization.data(withJSONObject:object)))
        var invalid=event();invalid["input"] = -1
        let snapshot=try AgentUsageEngine.decode(payload([invalid]));expectTrue(snapshot.events.isEmpty);expectEqual(snapshot.malformed,1)
        object["commit"]=AgentUsageEngine.commit;object["sources"]=[]
        expectThrows(try AgentUsageEngine.decode(JSONSerialization.data(withJSONObject:object)))
    }
    func testPeriodBoundariesAndUnclassified()throws {
        let snapshot=try AgentUsageEngine.decode(payload([event("gemini")]))
        let start=snapshot.events[0].date,range=DateInterval(start:start,duration:3600)
        let report=TokenUsageReport(events:snapshot.events,in:range,provider:.gemini,intervals:[range])
        expectEqual(report.counts.total,72);expectEqual(report.counts.cacheRead,30)
        expectTrue(TokenUsageReport(events:snapshot.events,in:DateInterval(start:start.addingTimeInterval(3600),duration:3600),intervals:[]).events.isEmpty)
        expectTrue(TokenUsageReport(events:snapshot.events,in:range,provider:.codex,intervals:[range]).events.isEmpty)
    }
    func testCacheHitRateUsesRecordedInputAndWeightedTotals()throws {
        expectEqual(TokenCounts(input:100,output:900,cacheRead:40,cacheWrite:20).cacheHitRate,0.4)
        expectEqual(TokenCounts(input:100,cacheRead:0).cacheHitRate,0)
        expectEqual(TokenCounts(input:100,cacheRead:100).cacheHitRate,1)
        expectEqual(TokenCounts().cacheHitRate,nil)
        expectEqual(TokenCounts(input:0,cacheRead:1).cacheHitRate,nil)
        expectEqual(TokenCounts(input:10,cacheRead:11).cacheHitRate,nil)
        expectEqual(TokenCounts(input:10,cacheRead:-1).cacheHitRate,nil)
        expectEqual(TokenCounts(input:2_000_000_000_000,cacheRead:1_000_000_000_000).cacheHitRate,0.5)
        let date=Date(timeIntervalSince1970:1793923200),range=DateInterval(start:Date(timeIntervalSince1970:1793923200),duration:3600)
        let events=[TokenUsageEvent(id:"a",provider:.codex,date:date,model:"sample",counts:TokenCounts(input:100,cacheRead:90)),TokenUsageEvent(id:"b",provider:.codex,date:date,model:"sample",counts:TokenCounts(input:900,cacheRead:90)),TokenUsageEvent(id:"other",provider:.claude,date:date,model:"sample",counts:TokenCounts(input:1000,cacheRead:1000)),TokenUsageEvent(id:"outside",provider:.codex,date:range.end,model:"sample",counts:TokenCounts(input:1000,cacheRead:1000))]
        let report=TokenUsageReport(events:events,in:range,provider:.codex,intervals:[range])
        expectEqual(report.counts.cacheHitRate,0.18)
        expectEqual(report.counts.input,1000);expectEqual(report.counts.cacheRead,180)
    }
    func testAgentStatisticsFilterAggregateAndSort()throws {
        let date=Date(timeIntervalSince1970:1793923200),range=DateInterval(start:Date(timeIntervalSince1970:1793923200),duration:3600)
        let events=[
            TokenUsageEvent(id:"a",provider:.codex,date:date,model:"one",counts:TokenCounts(input:100,output:10,cacheRead:90)),
            TokenUsageEvent(id:"b",provider:.codex,date:date,model:"two",counts:TokenCounts(input:900,output:10,cacheRead:90)),
            TokenUsageEvent(id:"c",provider:.claude,date:date,model:"sample",counts:TokenCounts(input:300,output:50,cacheRead:240)),
            TokenUsageEvent(id:"d",provider:.gemini,date:date,model:"sample",counts:TokenCounts(output:5)),
            TokenUsageEvent(id:"outside",provider:.claude,date:range.end,model:"sample",counts:TokenCounts(input:9000))]
        let report=TokenUsageReport(events:events,in:range,intervals:[range])
        expectEqual(report.agents.count,3)
        let codex=report.agents.first{$0.provider == .codex}!
        expectEqual(codex.counts.input,1000);expectEqual(codex.counts.cacheHitRate,0.18);expectEqual(codex.requests,2)
        expectEqual(report.sortedAgents().map(\.provider),[.codex,.claude,.gemini])
        expectEqual(report.sortedAgents(by:.input,ascending:true).map(\.provider),[.gemini,.claude,.codex])
        expectEqual(report.sortedAgents(by:.output).map(\.provider),[.claude,.codex,.gemini])
        expectEqual(report.sortedAgents(by:.cacheHitRate).map(\.provider),[.claude,.codex,.gemini])
        expectEqual(report.sortedAgents(by:.cacheHitRate,ascending:true).map(\.provider),[.codex,.claude,.gemini])
        expectEqual(report.sortedAgents(by:.name,ascending:true).map(\.provider),[.claude,.codex,.gemini])
        let selected=TokenUsageReport(events:events,in:range,provider:.claude,intervals:[range])
        expectEqual(selected.agents.map(\.provider),[.claude]);expectEqual(selected.counts.total,350)
        expectEqual(selected.buckets.first?.counts.total,350);expectEqual(selected.models.count,1)
        let empty=TokenUsageReport(events:events,in:DateInterval(start:range.end,duration:1),provider:.codex,intervals:[])
        expectTrue(empty.sortedAgents().isEmpty)
        let ties=TokenUsageReport(events:[TokenUsageEvent(id:"tie-b",provider:.gemini,date:date,model:"",counts:TokenCounts(output:10)),TokenUsageEvent(id:"tie-a",provider:.claude,date:date,model:"",counts:TokenCounts(output:10))],in:range,intervals:[])
        expectEqual(ties.sortedAgents(by:.cacheHitRate).map(\.id),["claude","gemini"])
        expectEqual(ties.sortedAgents(by:.total,ascending:true).map(\.id),["claude","gemini"])
    }
    func testCacheAndRuntimeFailure()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("showmac-engine-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let fixture=root.appendingPathComponent("fixture.json"),script=root.appendingPathComponent("engine"),cache=root.appendingPathComponent("cache.json")
        try payload([event()]).write(to:fixture)
        try "#!/bin/sh\n/bin/cat '\(fixture.path)'\n".write(to:script,atomically:true,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:script.path)
        var environment:[String:String]=["PATH":"/usr/bin:/bin"]
        for provider in TokenProvider.allCases {environment[provider.environmentKey]=root.appendingPathComponent(provider.rawValue).path}
        let reader=AgentUsageEngine(executable:script,cacheURL:cache)
        let first=reader.scan(environment:environment);expectEqual(first.events.count,1);expectEqual(first.unreadable,0)
        let restored=AgentUsageEngine(executable:script,cacheURL:cache)
        expectEqual(restored.scan(environment:environment).events,first.events)
        try FileManager.default.removeItem(at:script)
        let failed=restored.scan(environment:environment);expectEqual(failed.events.count,1);expectTrue(failed.unreadable>0)
    }
    func testLegacyCountsDecodeAndSourceLocations()throws {
        let data=Data("{\"input\":60,\"output\":5,\"cacheRead\":30,\"cacheWrite\":20,\"reasoning\":0}".utf8)
        let counts=try JSONDecoder().decode(TokenCounts.self,from:data);expectEqual(counts.total,65);expectEqual(counts.unclassified,0)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("showmac-source-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root.appendingPathComponent("sessions"),withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        expectTrue(TokenProvider.codex.roots(environment:["CODEX_HOME":root.path]).contains(root.appendingPathComponent("sessions")))
        expectTrue(TokenProvider.cursor.requiresCache)
    }
}
