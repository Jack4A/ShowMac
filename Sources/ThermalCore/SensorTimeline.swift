import Foundation

public struct TimelineSample {
    public let snapshot:Snapshot
    public let mode:String?
    public init(_ snapshot:Snapshot,mode:String?) {self.snapshot=snapshot;self.mode=mode}
}
public enum SensorTimeline {
    public static func records(_ samples:[TimelineSample],sensor:SensorCategory,start:Date)->[ModeRecord] {
        var result:[ModeRecord]=[],segment=0
        var previous:Date?,mode:String?,origin=start
        for item in samples where item.snapshot.date>=start {
            let s=item.snapshot
            guard let value=s.temperature(sensor),value.isFinite else {previous=nil;mode=nil;continue}
            let turboLabel=s.turbo == .disabledDriverLoaded ? "睿频关闭":(s.turbo == .driverNotLoaded ? "允许睿频":"睿频未知")
            let next=(item.mode ?? "未确认模式")+" · "+turboLabel
            if mode != next || previous.map({s.date.timeIntervalSince($0)>15 || s.date <= $0}) != false {
                segment+=1;origin=s.date
            }
            var record=ModeRecord(date:s.date,mode:next,temperature:value,load:s.cpuUsage,segment:segment,elapsed:s.date.timeIntervalSince(origin))
            record.turboDisabled=s.turbo == .disabledDriverLoaded ? true:(s.turbo == .driverNotLoaded ? false:nil)
            result.append(record)
            previous=s.date;mode=next
        }
        return result
    }
    /// Plot fewer actual samples, preserving endpoints, peaks, troughs and segment gaps.
    /// Full-resolution samples remain available for averages and export.
    public static func decimated(_ points:[ModeRecord],budget:Int=300)->[ModeRecord] {
        guard points.count>budget,budget>=4 else{return points}
        let chunk=max(2,Int(ceil(Double(points.count)*2/Double(budget))))
        var output:[ModeRecord]=[],index=0
        while index<points.count {
            let segment=points[index].segment
            var end=index
            while end<points.count && points[end].segment==segment {end+=1}
            output.append(points[index])
            var offset=index+1
            while offset<end-1 {
                let upper=min(end-1,offset+chunk)
                let bucket=points[offset..<upper]
                if let low=bucket.min(by:{$0.temperature<$1.temperature}),let high=bucket.max(by:{$0.temperature<$1.temperature}) {
                    if low.date==high.date {output.append(low)}
                    else {output.append(contentsOf:[low,high].sorted{$0.date<$1.date})}
                }
                offset=upper
            }
            if end-index>1 {output.append(points[end-1])}
            index=end
        }
        return output
    }
}
