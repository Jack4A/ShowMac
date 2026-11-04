import Foundation

public struct CurvePoint:Codable,Equatable,Identifiable {
    public var temperature:Double
    public var percent:Double
    public var id:Double { temperature }
    public init(_ temperature:Double,_ percent:Double) { self.temperature=temperature;self.percent=percent }
}
public enum CurveSensor:String,Codable,CaseIterable,Identifiable {
    case cpu="CPU",gpu="GPU",hottest="CPU / GPU 较高温"
    public var id:String { rawValue }
    public func temperature(in sample:Snapshot)->Double? {
        switch self { case .cpu:return sample.cpuTemperature;case .gpu:return sample.temperature(.gpu);case .hottest:return [sample.cpuTemperature,sample.temperature(.gpu)].compactMap{$0}.max() }
    }
}
public struct FanCurve:Codable,Equatable {
    public var points:[CurvePoint]
    public var sensor:CurveSensor
    public init(points:[CurvePoint],sensor:CurveSensor = .hottest) { self.points=points;self.sensor=sensor }
    public func validate() throws {
        guard (2...8).contains(points.count) else { throw ScopeError.message("曲线需要 2 至 8 个控制点") }
        for (index,p) in points.enumerated() {
            guard p.temperature.isFinite,p.percent.isFinite,(30...100).contains(p.temperature),(0...100).contains(p.percent) else { throw ScopeError.message("曲线温度范围为 30–100°C，转速范围为 0–100%") }
            if index>0 {
                guard p.temperature-points[index-1].temperature>=2-1e-9,p.percent>=points[index-1].percent else { throw ScopeError.message("温度控制点至少间隔 2°C，转速必须随温度升高而不降低") }
            }
        }
        guard let last=points.last,last.temperature<=90 else { throw ScopeError.message("最后一个控制点的温度不能超过 90°C") }
    }
    /// Drag continuously within neighboring temperatures. The last point sets the
    /// curve ceiling; lowering it caps earlier points without reversing the curve.
    /// CurveLease still overrides the curve with rated maximum RPM when hot.
    public mutating func movePoint(_ index:Int,temperature:Double,percent:Double) {
        guard points.indices.contains(index),temperature.isFinite,percent.isFinite else{return}
        let last=index==points.count-1
        let lowT=index>0 ? points[index-1].temperature+2:30
        let highT=last ? 90:points[index+1].temperature-2
        let lowP=index>0 && !last ? points[index-1].percent:0
        let highP=last ? 100:points[index+1].percent
        let target=min(highP,max(lowP,percent))
        points[index]=CurvePoint(min(highT,max(lowT,temperature)),target)
        if last {
            for prior in points.indices where prior<index {
                points[prior].percent=min(points[prior].percent,target)
            }
        }
    }
    public func percent(at temperature:Double)->Double {
        guard let first=points.first,let last=points.last else { return 100 }
        if !temperature.isFinite { return 100 }
        if temperature<=first.temperature { return first.percent }
        if temperature>=last.temperature { return last.percent }
        for index in 1..<points.count {
            let a=points[index-1],b=points[index]
            if temperature<=b.temperature {
                let fraction=(temperature-a.temperature)/(b.temperature-a.temperature)
                return a.percent+(b.percent-a.percent)*fraction
            }
        }
        return 100
    }
    /// Fixed relative RPM below 80°C; ramp to maximum by 90°C. Thermal overrides still apply.
    public static func manual(percent:Double)->FanCurve {
        let safe=percent.isFinite ? min(100,max(0,percent)):100
        return FanCurve(points:[.init(30,safe),.init(80,safe),.init(90,100)])
    }
    public static let balanced=FanCurve(points:[.init(40,10),.init(55,25),.init(70,55),.init(80,80),.init(90,100)])
    public static let performance=FanCurve(points:[.init(40,30),.init(55,50),.init(65,75),.init(75,95),.init(85,100)])
    public static let quiet=FanCurve(points:[.init(40,0),.init(55,8),.init(70,25),.init(80,60),.init(90,100)])
}
public enum ThermalProfile:String,CaseIterable,Identifiable {
    case automatic="系统自动",eco="节能",performance="性能",balanced="均衡",quiet="静音",custom="自定义"
    public var id:String { rawValue }
    public var command:String {
        switch self {case .eco:return "eco";case .automatic:return "automatic";case .performance:return "performance";case .balanced:return "balanced";case .quiet:return "quiet";case .custom:return "custom"}
    }
    public var disablesTurbo:Bool { self == .quiet || self == .eco }
    public static var energyModes:[ThermalProfile] { [.eco,.performance,.quiet] }
    public var curve:FanCurve {
        switch self {case .performance:return .performance;case .quiet:return .quiet;default:return .balanced}
    }
    public var explanation:String {
        switch self {
        case .eco:return "限制性能峰值 · 均衡散热"
        case .automatic:return "系统控制风扇 · 保留睿频设置"
        case .performance:return "开启睿频 · 积极散热"
        case .balanced:return "开启睿频 · 平衡温度与噪声"
        case .quiet:return "关闭睿频 · 温和散热"
        case .custom:return "按你的曲线运行 · 保留睿频设置"
        }
    }
}
public enum CurvePolicy {
    /// Observation only: never take control away from macOS in response to a label.
    /// All fan ranges/readings must be known before describing cooling as low.
    public static func highTemperatureWithLowFanSpeed(_ sample:Snapshot)->Bool {
        guard requiresMaximum(sample),!sample.fans.isEmpty else{return false}
        return sample.fans.allSatisfy {fan in
            guard let rpm=fan.rpm,let low=fan.minimum,let high=fan.maximum,
                  rpm.isFinite,low.isFinite,high.isFinite,rpm>=0,low>=0,high>low else{return false}
            return rpm<=low+(high-low)*0.1
        }
    }
    public static func percent(rpm:Double,minimum:Double,maximum:Double)->Double {
        guard rpm.isFinite,minimum.isFinite,maximum.isFinite,maximum>minimum else{return 0}
        return min(100,max(0,(rpm-minimum)/(maximum-minimum)*100))
    }
    public static func requiresMaximum(_ sample:Snapshot)->Bool {
        (sample.cpuTemperature ?? 0)>=92 || (sample.temperature(.gpu) ?? 0)>=88 ||
        (sample.temperature(.storage) ?? 0)>=75 || (2...3).contains(sample.thermalState)
    }
    public static func rpm(percent:Double,minimum:Double,maximum:Double)->Double {
        minimum+(maximum-minimum)*min(100,max(0,percent))/100
    }
    public static func smooth(desired:Double,previous:Double?)->Double {
        // Raise promptly, lower by at most 4 percentage points per 2-second sample.
        guard let previous else { return desired }
        return desired>=previous ? desired:max(desired,previous-4)
    }
}
public struct FanControlProgress {
    public let deadline:Double
    public let targets:[FanTarget]
    public let protectionActive:Bool
}
public enum CurveLease {
    public static func run(hardware:CoolingHardware,curve:FanCurve,duration:Double=1800,
                           sample:()->Snapshot,now:()->Double,isCancelled:()->Bool,wait:()->Void,onUpdate:(FanControlProgress)->Void = {_ in},onApplied:()->Void = {}) throws {
        try curve.validate()
        guard duration>0,duration<=1800 else { throw ScopeError.message("曲线会话最长 30 分钟") }
        if isCancelled() { return }
        let fans=hardware.fans()
        guard !fans.isEmpty,fans.allSatisfy({$0.controllable && $0.manual==false && $0.minimum != nil && $0.maximum != nil}) else {
            throw ScopeError.message("请先恢复系统自动风扇并退出其他控制程序")
        }
        for fan in fans {
            guard let low=fan.minimum,let high=fan.maximum,low.isFinite,high.isFinite,low>0,high>=low,high<=12000 else { throw ScopeError.message("无法验证风扇额定范围") }
        }
        for fan in fans { try CoolingLease.validateInheritedTarget(hardware,fan:fan) }
        let deadline=now()+duration
        var active=false,previous:Double?
        var lastTargets:[Int:Double]=[:]
        do {
            while now()<deadline && !isCancelled() {
                let reading=sample()
                guard reading.cpuTemperature != nil,let temperature=curve.sensor.temperature(in:reading),temperature.isFinite else {
                    throw ScopeError.message("控制温度传感器不可用，已停止曲线并恢复系统自动")
                }
                if active {
                    let current=hardware.fans()
                    for fan in fans {
                        guard current.first(where:{$0.id==fan.id})?.manual==true,
                              let target=hardware.target(fan.id),let expected=lastTargets[fan.id],abs(target-expected)<3 else {
                            throw ScopeError.message("风扇控制被改变或无法读取，已停止曲线")
                        }
                    }
                }
                let protection=CurvePolicy.requiresMaximum(reading)
                let wanted=protection ? 100:curve.percent(at:temperature)
                let percent=CurvePolicy.smooth(desired:wanted,previous:previous)
                for fan in fans {
                    if !active { try hardware.setManual(fan.id,true) }
                    let rpm=CurvePolicy.rpm(percent:percent,minimum:fan.minimum!,maximum:fan.maximum!)
                    if !active || abs((lastTargets[fan.id] ?? 0)-rpm)>=30 {
                        try hardware.setTarget(fan.id,rpm:rpm);lastTargets[fan.id]=rpm
                    }
                }
                onUpdate(FanControlProgress(deadline:deadline,targets:fanTargets(lastTargets),protectionActive:protection))
                if !active { onApplied() }
                active=true;previous=percent;wait()
            }
        } catch {
            let original=error
            do { try CoolingLease.restoreAuto(hardware,ids:fans.map(\.id)) }
            catch { throw ScopeError.message("\(original.localizedDescription)；\(error.localizedDescription)") }
            throw original
        }
        if active { try CoolingLease.restoreAuto(hardware,ids:fans.map(\.id)) }
    }
    private static func fanTargets(_ targets:[Int:Double])->[FanTarget] {
        targets.keys.sorted().map{FanTarget(id:$0,rpm:targets[$0]!)}
    }
}
