import Foundation
import ThermalCore

struct TokenUsageTests {
    func line(_ type:String,_ payload:[String:Any],at:String="2026-11-06T00:00:00Z")->Data {
        try! JSONSerialization.data(withJSONObject:["type":type,"timestamp":at,"payload":payload],options:[.sortedKeys])
    }
    func codex(_ input:Int,_ output:Int,_ cache:Int=0)->[String:Any] {["input_tokens":input,"output_tokens":output,"cached_input_tokens":cache]}
    func testCodexCountersAndRequests()throws {
        var state=TokenLogState(session:"session")
        state.consume(line("turn_context",["model":"test-model"]),provider:.codex,ordinal:0)
        state.consume(line("token_usage_record",["response_id":"r1","usage":codex(100,20,80),"thread_token_usage":codex(100,20,80)]),provider:.codex,ordinal:1)
        let count=line("event_msg",["type":"token_count","info":["total_token_usage":codex(100,20,80),"last_token_usage":codex(100,20,80)]])
        state.consume(count,provider:.codex,ordinal:2);state.consume(count,provider:.codex,ordinal:3)
        state.consume(line("event_msg",["type":"token_count","info":["total_token_usage":codex(250,50,180),"last_token_usage":codex(150,30,100)]],at:"2026-11-06T01:00:00Z"),provider:.codex,ordinal:4)
        let result=TokenLogReconciliation.events(from:[state,state])
        expectEqual(result.events.count,2)
        let total=result.events.reduce(TokenCounts()){$0.adding($1.counts)}
        expectEqual(total.input,250);expectEqual(total.output,50);expectEqual(total.total,300);expectEqual(total.cacheRead,180)
        expectTrue(result.events.allSatisfy{$0.model=="test-model"})
    }
    func testClaudeStreamRevisionsAndCaches()throws {
        var state=TokenLogState(session:"claude")
        func row(_ output:Int,_ id:String="m1",_ stop:Any="end_turn")->Data {
            try! JSONSerialization.data(withJSONObject:["type":"assistant","timestamp":"2026-11-06T00:00:00Z","requestId":"request","message":["id":id,"model":"claude-test","content":[["type":"text","text":"PRIVATE PROMPT MUST NOT BE RETAINED"]],"stop_reason":stop,"usage":["input_tokens":10,"output_tokens":output,"cache_read_input_tokens":80,"cache_creation_input_tokens":20]]])
        }
        state.consume(row(5),provider:.claude,ordinal:0);state.consume(row(20),provider:.claude,ordinal:1)
        let result=TokenLogReconciliation.events(from:[state])
        expectEqual(result.events.count,1);expectEqual(result.events[0].counts.total,130)
        expectEqual(result.events[0].counts.input,110);expectEqual(result.events[0].counts.cacheRead,80)
        let encoded=try JSONEncoder().encode(state)
        expectFalse(String(decoding:encoded,as:UTF8.self).contains("PRIVATE PROMPT"))
        let invalid=try JSONSerialization.data(withJSONObject:["type":"assistant","timestamp":"2026-11-06T00:00:00Z","message":["id":"bad","stop_reason":NSNull(),"usage":["input_tokens":9,"output_tokens":0]]])
        state.consume(invalid,provider:.claude,ordinal:2);expectEqual(state.events.count,2)
    }
    func testForkReplayAndMissingParent()throws {
        var parent=TokenLogState(session:"parent"),child=TokenLogState(session:"child")
        for i in 1...2 {
            let row=line("event_msg",["type":"token_count","info":["total_token_usage":codex(i*100,i*10),"last_token_usage":codex(100,10)]])
            parent.consume(row,provider:.codex,ordinal:UInt64(i));child.consume(row,provider:.codex,ordinal:UInt64(i))
        }
        child.parent="parent"
        child.consume(line("event_msg",["type":"token_count","info":["total_token_usage":codex(350,40),"last_token_usage":codex(150,20)]]),provider:.codex,ordinal:3)
        let result=TokenLogReconciliation.events(from:[parent,child]);expectEqual(result.events.count,3)
        expectEqual(result.events.reduce(Int64(0)){$0+$1.counts.total},390)
        let missing=TokenLogReconciliation.events(from:[child]);expectTrue(missing.events.isEmpty);expectEqual(missing.unresolvedForks,1)
    }
    func testInvalidCountsAndReportBoundaries()throws {
        var state=TokenLogState(session:"bad")
        for value:Any in [-1,0.5,true,"100"] {
            state.consume(line("event_msg",["type":"token_count","info":["total_token_usage":["input_tokens":value,"output_tokens":1]]]),provider:.codex,ordinal:0)
        }
        expectTrue(state.events.isEmpty)
        let start=Date(timeIntervalSince1970:1_800_000_000),end=start.addingTimeInterval(3600)
        let events=[TokenUsageEvent(id:"first",provider:.codex,date:start,model:"m",counts:TokenCounts(input:100,output:20,cacheRead:80,reasoning:5)),TokenUsageEvent(id:"end",provider:.claude,date:end,model:"m",counts:TokenCounts(input:500))]
        let interval=DateInterval(start:start,end:end),report=TokenUsageReport(events:events,in:interval,intervals:[interval])
        expectEqual(report.counts.total,120);expectEqual(report.models.count,1);expectEqual(report.buckets[0].requests,1)
    }
    func testLargeNonUsageLinesAndCounterReset()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("showmac-large-token-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("session.jsonl")
        var data=Data("{\"type\":\"response_item\",\"text\":\"".utf8)
        data.append(Data(repeating:120,count:5*1024*1024));data.append(Data("\"}\n".utf8))
        let first=line("event_msg",["type":"token_count","info":["total_token_usage":codex(100,20),"last_token_usage":codex(100,20)]])
        let reset=line("event_msg",["type":"token_count","info":["total_token_usage":codex(10,2),"last_token_usage":codex(10,2)]])
        for row in [first,reset,first] {data.append(row);data.append(10)}
        try data.write(to:file)
        let snapshot=TokenLogScanner().scan(roots:[TokenLogRoot(provider:.codex,url:root)])
        expectEqual(snapshot.malformed,0);expectEqual(snapshot.events.count,3)
        expectEqual(snapshot.events.reduce(Int64(0)){$0+$1.counts.total},240)
    }
    func testIncrementalPartialLinesTruncationAndCache()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("showmac-tokens-"+UUID().uuidString),file=root.appendingPathComponent("session.jsonl"),cache=root.appendingPathComponent("cache.json")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let first=line("event_msg",["type":"token_count","info":["total_token_usage":codex(100,20)]])+Data([10])
        let second=line("event_msg",["type":"token_count","info":["total_token_usage":codex(200,40)]])+Data([10])
        try (first+second.prefix(20)).write(to:file)
        let scanner=TokenLogScanner(cacheURL:cache),roots=[TokenLogRoot(provider:.codex,url:root)]
        expectEqual(scanner.scan(roots:roots).events.count,1)
        let handle=try FileHandle(forWritingTo:file);try handle.seekToEnd();try handle.write(contentsOf:second.dropFirst(20));try handle.close()
        let appended=scanner.scan(roots:roots);expectEqual(appended.events.count,2)
        expectEqual(scanner.scan(roots:roots).bytesRead,0)
        let restored=TokenLogScanner(cacheURL:cache);expectEqual(restored.scan(roots:roots).events,appended.events)
        try first.write(to:file,options:.atomic);expectEqual(scanner.scan(roots:roots).events.count,1)
        try FileManager.default.removeItem(at:file);expectTrue(scanner.scan(roots:roots).events.isEmpty)
        let broken=Data("broken cache".utf8);try broken.write(to:cache);try first.write(to:file)
        expectEqual(TokenLogScanner(cacheURL:cache).scan(roots:roots).events.count,1)
        expectEqual(try Data(contentsOf:cache),broken)
    }
}
