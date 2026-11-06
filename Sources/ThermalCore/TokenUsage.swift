import Foundation

public enum TokenProvider:String,Codable,CaseIterable,Identifiable,Sendable {
    case codex,claude
    public var id:String {rawValue}
    public var title:String {self == .codex ? "Codex":"Claude Code"}
}

/// Input includes cached input; reasoning is a subset of output, never added twice.
public struct TokenCounts:Codable,Equatable,Sendable {
    public var input:Int64
    public var output:Int64
    public var cacheRead:Int64
    public var cacheWrite:Int64
    public var reasoning:Int64
    public var total:Int64 {input+output}
    public init(input:Int64=0,output:Int64=0,cacheRead:Int64=0,cacheWrite:Int64=0,reasoning:Int64=0) {
        self.input=input;self.output=output;self.cacheRead=cacheRead;self.cacheWrite=cacheWrite;self.reasoning=reasoning
    }
    public var valid:Bool {[input,output,cacheRead,cacheWrite,reasoning].allSatisfy{(0...1_000_000_000_000).contains($0)} && cacheRead+cacheWrite<=input && reasoning<=output}
    public func adding(_ other:Self)->Self {Self(input:input+other.input,output:output+other.output,cacheRead:cacheRead+other.cacheRead,cacheWrite:cacheWrite+other.cacheWrite,reasoning:reasoning+other.reasoning)}
    public func maximum(_ other:Self)->Self {
        let i=max(input,other.input),o=max(output,other.output),r=max(cacheRead,other.cacheRead)
        return Self(input:i,output:o,cacheRead:min(i,r),cacheWrite:min(i-min(i,r),max(cacheWrite,other.cacheWrite)),reasoning:min(o,max(reasoning,other.reasoning)))
    }
    public func delta(from previous:Self)->Self? {
        guard input>=previous.input,output>=previous.output else{return nil}
        let i=input-previous.input,o=output-previous.output,r=min(i,max(0,cacheRead-previous.cacheRead))
        return Self(input:i,output:o,cacheRead:r,cacheWrite:min(i-r,max(0,cacheWrite-previous.cacheWrite)),reasoning:min(o,max(0,reasoning-previous.reasoning)))
    }
    var signature:String {"\(input):\(output):\(cacheRead):\(cacheWrite):\(reasoning)"}
}
public struct TokenUsageEvent:Codable,Equatable,Sendable {
    public let id:String
    public let provider:TokenProvider
    public let date:Date
    public let model:String
    public var counts:TokenCounts
    public let cumulative:String?
    public let fallback:Bool
    public init(id:String,provider:TokenProvider,date:Date,model:String,counts:TokenCounts,cumulative:String?=nil,fallback:Bool=false) {
        self.id=id;self.provider=provider;self.date=date;self.model=model;self.counts=counts;self.cumulative=cumulative;self.fallback=fallback
    }
}
public struct TokenUsageBucket:Identifiable {
    public var id:Date {interval.start}
    public let interval:DateInterval
    public var counts:TokenCounts
    public var requests:Int
}
public struct TokenModelUsage:Identifiable {
    public var id:String {provider.rawValue+":"+model}
    public let provider:TokenProvider
    public let model:String
    public var counts:TokenCounts
    public var requests:Int
}
public struct TokenUsageReport {
    public let events:[TokenUsageEvent]
    public let counts:TokenCounts
    public let buckets:[TokenUsageBucket]
    public let models:[TokenModelUsage]
    public init(events:[TokenUsageEvent],in range:DateInterval,provider:TokenProvider?=nil,intervals:[DateInterval]) {
        let selected=events.filter{range.start<=$0.date && $0.date<range.end && (provider==nil || $0.provider==provider)}
        self.events=selected;counts=selected.reduce(TokenCounts()){$0.adding($1.counts)}
        var models:[String:TokenModelUsage]=[:]
        var buckets=intervals.map{TokenUsageBucket(interval:$0,counts:TokenCounts(),requests:0)}
        for event in selected {
            let key=event.provider.rawValue+":"+event.model
            var model=models[key] ?? TokenModelUsage(provider:event.provider,model:event.model,counts:TokenCounts(),requests:0)
            model.counts=model.counts.adding(event.counts);model.requests+=1;models[key]=model
            if let index=buckets.firstIndex(where:{$0.interval.start<=event.date && event.date<$0.interval.end}) {
                buckets[index].counts=buckets[index].counts.adding(event.counts);buckets[index].requests+=1
            }
        }
        self.models=models.values.sorted{$0.counts.total==$1.counts.total ? $0.id<$1.id:$0.counts.total>$1.counts.total};self.buckets=buckets
    }
}
