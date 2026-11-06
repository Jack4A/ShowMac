import Foundation
import CoreFoundation

/// Only usage metadata leaves this parser. Transcript text and credentials are never retained.
public struct TokenLogState:Codable {
    public var session:String
    public var parent:String?
    public var model=""
    public var previous:TokenCounts?
    public var counterEpoch=0
    public var events:[TokenUsageEvent]=[]
    public var malformed=0
    public init(session:String){self.session=session}
    public mutating func consume(_ line:Data,provider:TokenProvider,ordinal:UInt64) {
        let needles=provider == .codex ? ["\"session_meta\"","\"turn_context\"","\"thread_settings_applied\"","\"token_count\"","\"token_usage_record\""]:["\"usage\""]
        guard needles.contains(where:{line.range(of:Data($0.utf8)) != nil}) else{return}
        guard let row=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any] else{malformed+=1;return}
        let type=row["type"] as? String ?? ""
        if provider == .codex {
            guard let payload=row["payload"] as? [String:Any] else{return}
            if type=="session_meta" {
                if let id=Self.string(payload["id"]) ?? Self.string(payload["session_id"]) {session=id}
                parent=Self.string(payload["forked_from_id"]);return
            }
            if type=="turn_context" {if let value=Self.string(payload["model"]) {model=value};return}
            if type=="event_msg",payload["type"] as? String == "thread_settings_applied",let settings=payload["thread_settings"] as? [String:Any],let value=Self.string(settings["model"]) {model=value;return}
            guard let date=Self.date(row["timestamp"]) else{malformed+=1;return}
            if type=="token_usage_record",let id=Self.string(payload["response_id"]),let usage=Self.counts(payload["usage"],claude:false),usage.total>0 {
                events.append(TokenUsageEvent(id:"codex:request:"+id,provider:.codex,date:date,model:Self.string(payload["model"]) ?? model,counts:usage,cumulative:Self.counts(payload["thread_token_usage"],claude:false)?.signature));return
            }
            guard type=="event_msg",payload["type"] as? String == "token_count",let info=payload["info"] as? [String:Any] else{return}
            let total=Self.counts(info["total_token_usage"],claude:false),last=Self.counts(info["last_token_usage"],claude:false)
            let delta:TokenCounts?
            if let total {
                if let previous {
                    if let difference=total.delta(from:previous) {delta=difference}
                    else {counterEpoch+=1;delta=last}
                } else {delta=last ?? total}
                previous=total
            } else {delta=last}
            guard let delta,delta.valid,delta.total>0 else{return}
            let identity=total?.signature ?? "\(date.timeIntervalSince1970):\(delta.signature)"
            events.append(TokenUsageEvent(id:"codex:counter:"+session+":\(counterEpoch):"+identity,provider:.codex,date:date,model:Self.string(payload["model"]) ?? Self.string(info["model"]) ?? model,counts:delta,cumulative:total?.signature,fallback:true))
        } else {
            guard type=="assistant",let message=row["message"] as? [String:Any],let usage=message["usage"] as? [String:Any],let counts=Self.counts(usage,claude:true),counts.total>0 else{return}
            // Explicitly unfinished proxy records are not confirmed usage.
            if message["stop_reason"] is NSNull,counts.output==0,counts.cacheRead==0,counts.cacheWrite==0 {return}
            guard let date=Self.date(row["timestamp"]) else{malformed+=1;return}
            let messageID=Self.string(message["id"]) ?? Self.string(row["uuid"])
            let request=Self.string(row["requestId"]) ?? Self.string(row["request_id"]) ?? ""
            let identity=messageID.map{request+":"+$0} ?? session+":\(ordinal)"
            events.append(TokenUsageEvent(id:"claude:message:"+identity,provider:.claude,date:date,model:Self.string(message["model"]) ?? "",counts:counts))
        }
    }
    static func string(_ value:Any?)->String? {
        guard let s=value as? String,!s.isEmpty,s.utf8.count<=256 else{return nil};return s
    }
    static func counts(_ value:Any?,claude:Bool)->TokenCounts? {
        guard let d=value as? [String:Any],d["input_tokens"] != nil || d["output_tokens"] != nil else{return nil}
        func number(_ key:String)->Int64? {
            guard let value=d[key] else{return 0}
            guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID() else{return nil}
            let v=n.doubleValue;guard v.isFinite,v>=0,v<=1_000_000_000_000,v.rounded()==v else{return nil};return Int64(v)
        }
        guard let input=number("input_tokens"),let output=number("output_tokens"),let read=number(claude ? "cache_read_input_tokens":"cached_input_tokens"),let write=number(claude ? "cache_creation_input_tokens":"cache_write_input_tokens"),let reasoning=number("reasoning_output_tokens") else{return nil}
        let counts=TokenCounts(input:claude ? input+read+write:input,output:output,cacheRead:read,cacheWrite:write,reasoning:reasoning)
        return counts.valid ? counts:nil
    }
    static func date(_ value:Any?)->Date? {
        guard let text=value as? String,text.utf8.count<=80 else{return nil}
        if let result=fractional.date(from:text) ?? plain.date(from:text),abs(result.timeIntervalSince1970)<10_000_000_000 {return result};return nil
    }
    private static let fractional:ISO8601DateFormatter={let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f}()
    private static let plain=ISO8601DateFormatter()
}

public enum TokenLogReconciliation {
    public static func events(from files:[TokenLogState])->(events:[TokenUsageEvent],unresolvedForks:Int) {
        let codex=files.filter{$0.events.first?.provider == .codex}
        let sessions=Dictionary(grouping:codex,by:\.session).mapValues{states in states.max{$0.events.count<$1.events.count}!}
        var result:[String:TokenUsageEvent]=[:],unresolved=0
        func insert(_ event:TokenUsageEvent) {
            if var existing=result[event.id] {existing.counts=existing.counts.maximum(event.counts);result[event.id]=existing}
            else {result[event.id]=event}
        }
        for file in files {
            let requests=file.events.filter{!$0.fallback}
            let covered=Set(requests.compactMap(\.cumulative))
            let fallback=file.events.filter(\.fallback)
            var copied=Set<String>()
            if let parent=file.parent {
                if let source=sessions[parent] {
                    let originals=source.events.filter(\.fallback)
                    for (child,original) in zip(fallback,originals) {
                        guard child.cumulative != nil,child.cumulative==original.cumulative else{break}
                        copied.insert(child.id)
                    }
                } else {unresolved+=1;copied.formUnion(fallback.map(\.id))}
            }
            for event in requests {insert(event)}
            for event in fallback where !copied.contains(event.id) {
                if let signature=event.cumulative,covered.contains(signature) {continue}
                if requests.contains(where:{$0.counts==event.counts && abs($0.date.timeIntervalSince(event.date))<=2}) {continue}
                insert(event)
            }
        }
        return (result.values.sorted{$0.date==$1.date ? $0.id<$1.id:$0.date<$1.date},unresolved)
    }
}
