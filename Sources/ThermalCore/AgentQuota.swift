import Foundation
import CoreFoundation

/// A provider-reported rolling allowance. Token totals never manufacture quota.
public struct AgentQuotaWindow:Codable,Equatable,Identifiable,Sendable {
    public let provider:TokenProvider
    public let pool:String
    public let poolName:String?
    public let window:String
    public let minutes:Int?
    public let usedPercent:Double
    public let resetsAt:Date?
    public let observedAt:Date
    public var id:String {provider.rawValue+":"+pool+":"+window}
    public init(provider:TokenProvider,pool:String="default",poolName:String?=nil,window:String,minutes:Int?,usedPercent:Double,resetsAt:Date?,observedAt:Date) {
        self.provider=provider;self.pool=pool;self.poolName=poolName;self.window=window;self.minutes=minutes;self.usedPercent=usedPercent;self.resetsAt=resetsAt;self.observedAt=observedAt
    }
    public var valid:Bool {usedPercent.isFinite && (0...10000).contains(usedPercent) && (minutes.map{(1...525600).contains($0)} ?? true) && observedAt.timeIntervalSince1970.isFinite && observedAt.timeIntervalSince1970>0 && pool.utf8.count<=100 && (poolName.map{$0.utf8.count<=100 && !$0.unicodeScalars.contains{CharacterSet.controlCharacters.contains($0)}} ?? true) && !pool.unicodeScalars.contains{CharacterSet.controlCharacters.contains($0)} && (resetsAt.map{$0.timeIntervalSince1970.isFinite && $0>observedAt.addingTimeInterval(-60)} ?? true)}
    public func remaining(at date:Date=Date())->Double? {
        guard valid,date.timeIntervalSince(observedAt) >= -60,date.timeIntervalSince(observedAt)<=900,resetsAt.map({$0>date}) ?? true else{return nil}
        return max(0,100-usedPercent)
    }
}
public enum AgentQuotaParser {
    public static func codex(_ data:Data)->[AgentQuotaWindow] {
        guard data.count<=2*1024*1024,let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],object["type"] as? String=="event_msg",let payload=object["payload"] as? [String:Any],payload["type"] as? String=="token_count",let limits=payload["rate_limits"] as? [String:Any],let stamp=object["timestamp"] as? String,let date=timestamp(stamp) else{return []}
        let pool=(limits["limit_id"] as? String) ?? "codex"
        return ["primary","secondary"].compactMap {name in
            guard let row=limits[name] as? [String:Any],let percent=number(row["used_percent"]) else{return nil}
            let value=AgentQuotaWindow(provider:.codex,pool:pool,poolName:limits["limit_name"] as? String,window:name,minutes:number(row["window_minutes"]).map{Int($0)},usedPercent:percent,resetsAt:number(row["resets_at"]).map{Date(timeIntervalSince1970:$0)},observedAt:date)
            return value.valid ? value:nil
        }
    }
    public static func claude(_ data:Data,at date:Date=Date())->[AgentQuotaWindow] {
        guard data.count<=512*1024,let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let limits=object["rate_limits"] as? [String:Any] else{return []}
        return [("five_hour",300),("seven_day",10080)].compactMap {name,minutes in
            guard let row=limits[name] as? [String:Any],let percent=number(row["used_percentage"]) else{return nil}
            let value=AgentQuotaWindow(provider:.claude,window:name,minutes:minutes,usedPercent:percent,resetsAt:number(row["resets_at"]).map{Date(timeIntervalSince1970:$0)},observedAt:date)
            return value.valid ? value:nil
        }
    }
    private static func number(_ value:Any?)->Double? {
        guard let number=value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID() else{return nil}
        let value=number.doubleValue;return value.isFinite && abs(value)<10_000_000_000 ? value:nil
    }
    private static func timestamp(_ text:String)->Date? {
        let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        return f.date(from:text) ?? ISO8601DateFormatter().date(from:text)
    }
}

/// Bounded tails from the newest rollouts, never auth.json or a credential store.
public final class AgentQuotaReader {
    private var files:[String:(Int64,Date,[AgentQuotaWindow])]=[:]
    public init(){}
    public func readCodex(roots:[URL])->[AgentQuotaWindow] {
        var candidates:[(URL,Date)]=[]
        for root in roots {
            guard let enumerator=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.contentModificationDateKey],options:[.skipsHiddenFiles]) else{continue}
            for case let url as URL in enumerator {
                guard url.pathExtension=="jsonl",let values=try? url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.contentModificationDateKey]),values.isRegularFile==true,values.isSymbolicLink != true else{continue}
                candidates.append((url,values.contentModificationDate ?? .distantPast))
                if candidates.count>=20000 {break}
            }
        }
        candidates.sort{$0.1>$1.1}
        var rows:[AgentQuotaWindow]=[],retained=Set<String>()
        for (url,date) in candidates.prefix(32) {
            guard let size=(try? FileManager.default.attributesOfItem(atPath:url.path)[.size]) as? NSNumber else{continue}
            retained.insert(url.path)
            if let entry=files[url.path],entry.0==size.int64Value,entry.1==date {rows+=entry.2;continue}
            guard let file=try? FileHandle(forReadingFrom:url) else{continue};defer{try? file.close()}
            let offset=max(0,size.int64Value-1024*1024);try? file.seek(toOffset:UInt64(offset))
            guard let data=try? file.read(upToCount:1024*1024) else{continue}
            var lines=data.split(separator:10,omittingEmptySubsequences:false)
            if offset>0,!lines.isEmpty {lines.removeFirst()}
            if data.last != 10,!lines.isEmpty {lines.removeLast()}
            var found:[String:[AgentQuotaWindow]]=[:]
            for line in lines.reversed() {
                guard !line.isEmpty,Data(line).range(of:Data("\"rate_limits\"".utf8)) != nil else{continue}
                let parsed=AgentQuotaParser.codex(Data(line))
                if let first=parsed.first,found[first.pool]==nil {found[first.pool]=parsed}
            }
            let parsed=found.values.flatMap{$0};files[url.path]=(size.int64Value,date,parsed);rows+=parsed
        }
        files=files.filter{retained.contains($0.key)}
        // A single newest response owns each pool. Do not merge sparse windows
        // from potentially different signed-in accounts or expired periods.
        var pools:[String:[AgentQuotaWindow]]=[:]
        for row in rows {
            let stamp=pools[row.pool]?.first?.observedAt
            if stamp==nil || row.observedAt>stamp! {pools[row.pool]=rows.filter{$0.pool==row.pool && $0.observedAt==row.observedAt}}
        }
        var unique:[String:AgentQuotaWindow]=[:]
        for row in pools.values.flatMap({$0}) {unique[row.id]=row}
        return unique.values.sorted{$0.id<$1.id}
    }
}
