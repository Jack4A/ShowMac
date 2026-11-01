import Foundation

public struct OptimizationMetric {
    public let date:Date
    public let cpu:Double?
    public let temperature:Double?
    public let dischargeWatts:Double?
    public let source:PowerSource?
    public init(date:Date,cpu:Double?,temperature:Double?,dischargeWatts:Double?,source:PowerSource?) {
        self.date=date;self.cpu=cpu;self.temperature=temperature;self.dischargeWatts=dischargeWatts;self.source=source
    }
}
public struct OptimizationSummary {
    public let cpu:Double?
    public let temperature:Double?
    public let watts:Double?
    public let seconds:Double
    public let count:Int
    public let source:PowerSource?
    public let wattsSamples:Int
    public init(_ samples:[OptimizationMetric]) {
        func average(_ values:[Double?])->Double? {let values=values.compactMap{$0}.filter{$0.isFinite};return values.isEmpty ? nil:values.reduce(0,+)/Double(values.count)}
        let samples=samples.sorted{$0.date<$1.date}
        cpu=average(samples.map(\.cpu));temperature=average(samples.map(\.temperature))
        let sources=Set(samples.compactMap(\.source))
        source=sources.count==1 && !samples.contains(where:{$0.source==nil}) ? sources.first:nil
        // Battery discharge never stands in for wall power, charging, or mixed sources.
        let power=samples.compactMap(\.dischargeWatts).filter{$0.isFinite && $0>0}
        wattsSamples=power.count
        watts=source == .battery && power.count>=2 ? average(power.map{Optional($0)}):nil
        seconds=max(0,(samples.last?.date.timeIntervalSince(samples.first?.date ?? Date())) ?? 0)
        count=samples.count
    }
    public var sufficient:Bool {count>=5 && seconds>=20}
    public func comparableWatts(to other:Self)->Bool {sufficient && other.sufficient && source == .battery && other.source == .battery && watts != nil && other.watts != nil}
    public static func baseline(_ samples:[OptimizationMetric],before date:Date?)->Self {
        guard let date else{return Self([])}
        return Self(samples.filter{$0.date>=date.addingTimeInterval(-60) && $0.date<=date})
    }
    public func assessment(after:Self)->OptimizationAssessment {
        guard sufficient,after.sufficient else{return .insufficient}
        guard let source,let afterSource=after.source,source==afterSource else{return .powerChanged}
        guard let cpu,let nextCPU=after.cpu,abs(cpu-nextCPU)<=max(10,abs(cpu)*0.5) else{return .loadChanged}
        guard let temperature,let next=after.temperature else{return .insufficient}
        if next<=temperature-2 {return .lowerTemperature}
        if next>=temperature+2 {return .higherTemperature}
        return .noClearChange
    }
}
public enum OptimizationAssessment {case insufficient,powerChanged,loadChanged,lowerTemperature,higherTemperature,noClearChange}
