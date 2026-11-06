import Foundation
import ThermalCore

struct AgentQuotaTests {
    private let date=Date(timeIntervalSince1970:1793952000)
    private func codex(_ limits:[String:Any],stamp:String="2026-11-06T08:00:00Z")->Data {
        try! JSONSerialization.data(withJSONObject:["timestamp":stamp,"type":"event_msg","payload":["type":"token_count","rate_limits":limits]])
    }
    func testProviderWindowsAndExpiration()throws {
        let data=codex(["limit_id":"codex","primary":["used_percent":32.5,"window_minutes":10080,"resets_at":1794556800]])
        let rows=AgentQuotaParser.codex(data);expectEqual(rows.count,1);expectEqual(rows[0].minutes,10080);expectEqual(rows[0].remaining(at:date),67.5)
        expectEqual(rows[0].remaining(at:date.addingTimeInterval(901)),nil)
        let expires=AgentQuotaWindow(provider:.codex,window:"primary",minutes:300,usedPercent:100,resetsAt:date.addingTimeInterval(10),observedAt:date)
        expectEqual(expires.remaining(at:date),0);expectEqual(expires.remaining(at:date.addingTimeInterval(10)),nil)
        let over=AgentQuotaWindow(provider:.codex,window:"primary",minutes:300,usedPercent:110,resetsAt:nil,observedAt:date);expectEqual(over.remaining(at:date),0)
    }
    func testInvalidAndContextValuesAreNotQuota()throws {
        expectTrue(AgentQuotaParser.codex(codex(["primary":["used_percent":true]])).isEmpty)
        expectTrue(AgentQuotaParser.codex(codex(["primary":["used_percent":-1]])).isEmpty)
        let context=try JSONSerialization.data(withJSONObject:["context_window":["remaining_percentage":98]])
        expectTrue(AgentQuotaParser.claude(context,at:date).isEmpty)
        let invalid=AgentQuotaWindow(provider:.codex,window:"primary",minutes:300,usedPercent:.nan,resetsAt:nil,observedAt:date);expectFalse(invalid.valid)
    }
    func testClaudeStatusLineMetadataOnly()throws {
        let payload:[String:Any]=["rate_limits":["five_hour":["used_percentage":10.25,"resets_at":1793955600],"seven_day":["used_percentage":42,"resets_at":1794556800]],"context_window":["remaining_percentage":1],"content":"PRIVATE_TRANSCRIPT","api_key":"PRIVATE_CREDENTIAL"]
        let rows=AgentQuotaParser.claude(try JSONSerialization.data(withJSONObject:payload),at:date)
        expectEqual(rows.count,2);expectEqual(rows.first?.remaining(at:date),89.75)
        let cache=String(decoding:try JSONEncoder().encode(rows),as:UTF8.self);expectFalse(cache.contains("PRIVATE"));expectFalse(cache.contains("api_key"));expectFalse(cache.contains("context_window"))
    }
    func testRecentRolloutsDedupAndSparseResponses()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("showmac-quota-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let older=codex(["primary":["used_percent":10,"window_minutes":300],"secondary":["used_percent":20,"window_minutes":10080]],stamp:"2026-11-06T07:59:00Z")
        let latest=codex(["primary":["used_percent":30,"window_minutes":10080]])
        var lines=Data();lines.append(older);lines.append(10);lines.append(latest);lines.append(10);lines.append(Data("{\"partial\":".utf8))
        let path=root.appendingPathComponent("rollout.jsonl");try lines.write(to:path)
        let reader=AgentQuotaReader(),first=reader.readCodex(roots:[root]);expectEqual(first.count,1);expectEqual(first[0].usedPercent,30);expectEqual(first[0].minutes,10080)
        expectEqual(reader.readCodex(roots:[root]),first)
        try lines.write(to:root.appendingPathComponent("mirror.jsonl"));expectEqual(reader.readCodex(roots:[root]).count,1)
        try FileManager.default.removeItem(at:path);try FileManager.default.removeItem(at:root.appendingPathComponent("mirror.jsonl"));expectTrue(reader.readCodex(roots:[root]).isEmpty)
    }
}
