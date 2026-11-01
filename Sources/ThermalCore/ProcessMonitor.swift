import Foundation
import CSMC

public struct ProcessReading:Identifiable {
    public let pid:Int32
    public let parentPID:Int32
    public let uid:UInt32
    public let started:UInt64
    public let name:String
    public let cpu:Double
    public let memory:UInt64
    public let diskReadRate:Double?
    public let diskWriteRate:Double?
    public var diskRate:Double? {guard let diskReadRate,let diskWriteRate else{return nil};return diskReadRate+diskWriteRate}
    public var id:Int32 {pid}
}
public enum ProcessCPU {
    public static func rate(previous:UInt64,current:UInt64,elapsed:Double,sameIdentity:Bool)->Double? {
        guard sameIdentity,elapsed>0,elapsed.isFinite,current>=previous else{return nil}
        let value=Double(current-previous)/elapsed
        return value.isFinite ? value:nil
    }
    public static func percent(previous:UInt64,current:UInt64,elapsed:Double,sameIdentity:Bool)->Double? {
        guard sameIdentity,elapsed>0,elapsed.isFinite,current>=previous else{return nil}
        let value=Double(current-previous)/1_000_000_000/elapsed*100
        return value.isFinite ? max(0,value):nil
    }
}
public final class NativeProcessSampler {
    private var previous:[Int32:(UInt64,UInt64,UInt64,UInt64)]=[:]
    private var previousTime:Double?
    public private(set) var inaccessible=0
    public init(){}
    public func sample(now:Double=ProcessInfo.processInfo.systemUptime)->[ProcessReading] {
        var raw=[TSProcessSnapshot](repeating:TSProcessSnapshot(),count:4096),skipped:Int32=0
        let count=ts_process_snapshot(&raw,Int32(raw.count),&skipped)
        inaccessible=Int(skipped)
        guard count>=0 else{return []}
        var next:[Int32:(UInt64,UInt64,UInt64,UInt64)]=[:],readings:[ProcessReading]=[]
        for item in raw.prefix(Int(count)) {
            next[item.pid]=(item.started,item.cpu_ns,item.disk_read_bytes,item.disk_write_bytes)
            guard let old=previous[item.pid],let time=previousTime,
                  let cpu=ProcessCPU.percent(previous:old.1,current:item.cpu_ns,elapsed:now-time,sameIdentity:old.0==item.started) else {continue}
            let name=withUnsafePointer(to:item.name) {$0.withMemoryRebound(to:CChar.self,capacity:96) {String(cString:$0)}}
            readings.append(ProcessReading(pid:item.pid,parentPID:item.parent_pid,uid:item.uid,started:item.started,name:name,cpu:cpu,memory:item.memory_bytes,diskReadRate:ProcessCPU.rate(previous:old.2,current:item.disk_read_bytes,elapsed:now-time,sameIdentity:true),diskWriteRate:ProcessCPU.rate(previous:old.3,current:item.disk_write_bytes,elapsed:now-time,sameIdentity:true)))
        }
        previous=next;previousTime=now
        return readings.sorted{$0.cpu>$1.cpu}
    }
}
