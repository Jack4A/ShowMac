import Foundation

public struct ActivitySource {
    public let id:String
    public let name:String
    public let cpu:Double
    public let diskRate:Double?
    public init(id:String,name:String,cpu:Double,diskRate:Double?=nil) {self.id=id;self.name=name;self.cpu=cpu;self.diskRate=diskRate}
}
public struct SustainedActivity:Identifiable {
    public let id:String
    public let name:String
    public let averageCPU:Double
    public let currentCPU:Double
    /// Share of CPU time among readable processes, never a share of energy.
    public let cpuShare:Double
    public let averageDiskRate:Double?
    public let currentDiskRate:Double?
    public let diskSeconds:Double
}
/// Integrates sampled CPU percentages over time. Missing/long sample gaps are not
/// extrapolated; exited sources stop appearing, and old intervals expire.
public struct CPUActivityWindow {
    private struct Frame {let start:Double;let end:Double;let sources:[String:ActivitySource]}
    private var frames:[Frame]=[]
    private var last:Double?
    public private(set) var seconds:Double=0
    public private(set) var rows:[SustainedActivity]=[]
    private let window:Double
    public init(seconds:Double=60) {window=max(1,seconds)}
    public mutating func record(_ sources:[ActivitySource],at now:Double) {
        guard now.isFinite else{return}
        var current:[String:ActivitySource]=[:]
        for source in sources where source.cpu.isFinite && source.cpu>=0 {
            let sum=(current[source.id]?.cpu ?? 0)+source.cpu
            guard sum.isFinite else{continue}
            let previous=current[source.id]
            let disk:Double?
            if let rate=source.diskRate,rate.isFinite,rate>=0 {
                disk=previous == nil ? rate:previous?.diskRate.map{$0+rate}
            } else {disk=nil}
            current[source.id]=ActivitySource(id:source.id,name:source.name,cpu:sum,diskRate:disk)
        }
        guard !current.isEmpty else{frames=[];last=nil;seconds=0;rows=[];return}
        defer{last=now}
        guard let previous=last,now>previous,now-previous<=15 else {
            frames=[];seconds=0;rows=[];return
        }
        frames.append(Frame(start:previous,end:now,sources:current))
        let cutoff=now-window
        frames.removeAll{$0.end<=cutoff}
        var integrals:[String:Double]=[:],diskIntegrals:[String:Double]=[:],diskDurations:[String:Double]=[:]
        seconds=0
        for frame in frames {
            let duration=frame.end-max(cutoff,frame.start)
            seconds+=duration
            for source in frame.sources.values {
                integrals[source.id,default:0]+=source.cpu*duration
                if let rate=source.diskRate,rate.isFinite {diskIntegrals[source.id,default:0]+=rate*duration;diskDurations[source.id,default:0]+=duration}
            }
        }
        let total=integrals.values.reduce(0,+)
        rows=current.values.map{source in
            let integral=integrals[source.id] ?? 0
            let duration=diskDurations[source.id] ?? 0
            return SustainedActivity(id:source.id,name:source.name,averageCPU:seconds>0 ? integral/seconds:0,currentCPU:source.cpu,cpuShare:total>0 ? integral/total*100:0,averageDiskRate:duration>0 ? (diskIntegrals[source.id] ?? 0)/duration:nil,currentDiskRate:source.diskRate,diskSeconds:duration)
        }.sorted{$0.averageCPU == $1.averageCPU ? $0.id<$1.id:$0.averageCPU>$1.averageCPU}
    }
}
