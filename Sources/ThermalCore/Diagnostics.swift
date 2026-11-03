import Foundation

public enum DiagnosticSeverity:Int,Equatable {case information=0,warning=1,critical=2}
public enum DiagnosticConfidence:Equatable {case confirmed,possible,unavailable}
public enum DiagnosticKind:Equatable {case thermalPressure,thermalLimit,performanceLimit,temperature,temperatureObservation,sustainedCPU,memoryPressure,diskActivity,wakeRequests,batteryPolicy,unavailable}
public enum DiagnosticAction:Equatable {
    case reviewApplication(String),memoryProcesses,diskProcesses,temperatureTimeline,wakeRequests,lowPowerPlan,refresh
}
public struct DiagnosticSource:Equatable {
    public let id:String
    public let name:String
    public let averageCPU:Double
    public let currentCPU:Double
    public let averageDiskRate:Double?
    public let currentDiskRate:Double?
    public let diskSeconds:Double
    public init(id:String,name:String,averageCPU:Double,currentCPU:Double,averageDiskRate:Double?=nil,currentDiskRate:Double?=nil,diskSeconds:Double=0) {
        self.id=id;self.name=name;self.averageCPU=averageCPU;self.currentCPU=currentCPU;self.averageDiskRate=averageDiskRate;self.currentDiskRate=currentDiskRate;self.diskSeconds=diskSeconds
    }
}
public struct DiagnosticFinding:Identifiable,Equatable {
    public let id:String
    public let kind:DiagnosticKind
    public let severity:DiagnosticSeverity
    public let confidence:DiagnosticConfidence
    public let subject:String?
    public let value:Double?
    public let seconds:Double?
    public let action:DiagnosticAction
    public init(id:String,kind:DiagnosticKind,severity:DiagnosticSeverity,confidence:DiagnosticConfidence,subject:String?=nil,value:Double?=nil,seconds:Double?=nil,action:DiagnosticAction) {
        self.id=id;self.kind=kind;self.severity=severity;self.confidence=confidence;self.subject=subject;self.value=value;self.seconds=seconds;self.action=action
    }
}
public enum DiagnosticState:Equatable {case sampling,attention,observing,stable,partial}
/// A read-only capture of the metrics available to this exact rule evaluation.
/// Stale process sources and invalid values remain unavailable in the UI.
public struct DiagnosticMetrics:Equatable {
    public let cpuUsage:Double?
    public let cpuTemperature:Double?
    public let gpuTemperature:Double?
    public let memoryPressure:MemoryPressure?
    public let thermalTitle:String
    public let performanceLimited:Bool?
    public let processFresh:Bool
    public let wakeRequestsKnown:Bool
    public let processSeconds:Double
    public let cpuSource:DiagnosticSource?
    public let diskSource:DiagnosticSource?
    public init(_ input:DiagnosticInput) {
        func valid(_ value:Double?)->Double? {value.flatMap{$0.isFinite && $0>=0 ? $0:nil}}
        let sample=input.snapshot
        cpuUsage=valid(sample.cpuUsage).flatMap{$0<=100 ? $0:nil}
        cpuTemperature=valid(sample.cpuTemperature);gpuTemperature=valid(sample.temperature(.gpu))
        memoryPressure=sample.memoryPressure;thermalTitle=sample.thermalTitle
        performanceLimited=sample.limitKnown ? sample.limited:nil
        let fresh=input.processDate.map{let age=sample.date.timeIntervalSince($0);return age>=(-1) && age<=12} ?? false
        processFresh=fresh;wakeRequestsKnown=input.blockers != nil
        let seconds=fresh && input.processSeconds.isFinite && input.processSeconds>0 ? min(60,input.processSeconds):0
        processSeconds=seconds
        cpuSource=seconds>0 ? input.sources.filter{$0.averageCPU.isFinite && $0.averageCPU>=0 && $0.currentCPU.isFinite && $0.currentCPU>=0}.max(by:{$0.averageCPU<$1.averageCPU}):nil
        diskSource=seconds>0 ? input.sources.filter{$0.diskSeconds.isFinite && $0.diskSeconds>0 && valid($0.averageDiskRate) != nil && valid($0.currentDiskRate) != nil}.max(by:{($0.averageDiskRate ?? 0)<($1.averageDiskRate ?? 0)}):nil
    }
}
public struct DiagnosticReport:Equatable {
    public let state:DiagnosticState
    public let findings:[DiagnosticFinding]
    public let attentionCount:Int
    public let observedSeconds:Double
    public let date:Date?
    public let metrics:DiagnosticMetrics?
    public init(state:DiagnosticState = .sampling,findings:[DiagnosticFinding]=[],attentionCount:Int=0,observedSeconds:Double=0,date:Date?=nil,metrics:DiagnosticMetrics?=nil) {self.state=state;self.findings=findings;self.attentionCount=attentionCount;self.observedSeconds=observedSeconds;self.date=date;self.metrics=metrics}
}
public struct DiagnosticInput {
    public let snapshot:Snapshot
    public let sources:[DiagnosticSource]
    public let processSeconds:Double
    public let processDate:Date?
    public let blockers:Int?
    public let batteryPercent:Double?
    public let supportsLowPowerMode:Bool
    public init(snapshot:Snapshot,sources:[DiagnosticSource]=[],processSeconds:Double=0,processDate:Date?=nil,blockers:Int?=nil,batteryPercent:Double?=nil,supportsLowPowerMode:Bool=SystemCapabilities.lowPowerMode) {
        self.snapshot=snapshot;self.sources=sources;self.processSeconds=processSeconds;self.processDate=processDate;self.blockers=blockers;self.batteryPercent=batteryPercent
        self.supportsLowPowerMode=supportsLowPowerMode
    }
}
/// Rules only produce evidence and review actions. They never execute controls.
public struct DiagnosticEngine {
    private var last:Date?
    private var observed:Double=0
    private var hotSeconds:Double=0
    private var hotSource:SensorCategory?
    public init(){}
    public mutating func evaluate(_ input:DiagnosticInput)->DiagnosticReport {
        let sample=input.snapshot,now=sample.date
        let interval=last.map{now.timeIntervalSince($0)} ?? 0
        if interval<=0 || interval>15 {observed=0;hotSeconds=0;hotSource=nil}
        else {observed=min(60,observed+interval)}
        last=now
        let cpuHot=sample.cpuTemperature.map{$0.isFinite && $0>=90} ?? false
        let gpuHot=sample.temperature(.gpu).map{$0.isFinite && $0>=85} ?? false
        let nextHotSource:SensorCategory?=cpuHot ? .cpu:(gpuHot ? .gpu:nil)
        let cpuWarm=sample.cpuTemperature.map{$0.isFinite && $0>=80} ?? false
        let gpuWarm=sample.temperature(.gpu).map{$0.isFinite && $0>=75} ?? false
        let warm=cpuWarm || gpuWarm
        hotSeconds=nextHotSource != nil && hotSource==nextHotSource && interval>0 && interval<=15 ? hotSeconds+interval:0
        hotSource=nextHotSource
        var items:[DiagnosticFinding]=[]
        if (2...3).contains(sample.thermalState) {
            items.append(DiagnosticFinding(id:"thermal-pressure",kind:sample.limited ? .thermalLimit:.thermalPressure,severity:sample.thermalState==3 ? .critical:.warning,confidence:.confirmed,value:Double(sample.thermalState),action:.temperatureTimeline))
        } else if sample.limited {
            items.append(DiagnosticFinding(id:"system-limit",kind:.performanceLimit,severity:sample.lowPower ? .information:.warning,confidence:.confirmed,value:sample.speedLimit.map(Double.init),action:.temperatureTimeline))
        } else if hotSeconds>=30 {
            items.append(DiagnosticFinding(id:"temperature",kind:.temperature,severity:.warning,confidence:.possible,subject:cpuHot ? "CPU":"GPU",value:cpuHot ? sample.cpuTemperature:sample.temperature(.gpu),seconds:hotSeconds,action:.temperatureTimeline))
        } else if warm {
            items.append(DiagnosticFinding(id:"temperature-observation",kind:.temperatureObservation,severity:.information,confidence:.confirmed,subject:cpuWarm ? "CPU":"GPU",value:cpuWarm ? sample.cpuTemperature:sample.temperature(.gpu),action:.temperatureTimeline))
        }
        if let pressure=sample.memoryPressure,pressure != .normal {
            items.append(DiagnosticFinding(id:"memory-pressure",kind:.memoryPressure,severity:pressure == .critical ? .critical:.warning,confidence:.confirmed,value:Double(pressure.rawValue),action:.memoryProcesses))
        }
        let metrics=DiagnosticMetrics(input),processFresh=metrics.processFresh
        if processFresh,metrics.processSeconds>=45 {
            for source in input.sources.filter({$0.averageCPU.isFinite && $0.averageCPU>=100 && $0.currentCPU.isFinite && $0.currentCPU>=50}).sorted(by:{$0.averageCPU>$1.averageCPU}).prefix(2) {
                items.append(DiagnosticFinding(id:"cpu:"+source.id,kind:.sustainedCPU,severity:.warning,confidence:.possible,subject:source.name,value:source.averageCPU,seconds:metrics.processSeconds,action:.reviewApplication(source.id)))
            }
        }
        if processFresh,let source=input.sources.filter({$0.diskSeconds>=30 && ($0.averageDiskRate?.isFinite ?? false) && ($0.currentDiskRate?.isFinite ?? false) && ($0.averageDiskRate ?? 0)>=20*1024*1024 && ($0.currentDiskRate ?? 0)>=5*1024*1024}).max(by:{($0.averageDiskRate ?? 0)<($1.averageDiskRate ?? 0)}) {
            items.append(DiagnosticFinding(id:"disk:"+source.id,kind:.diskActivity,severity:.information,confidence:.confirmed,subject:source.name,value:source.averageDiskRate,seconds:min(60,source.diskSeconds),action:.reviewApplication(source.id)))
        }
        if input.supportsLowPowerMode,sample.acPower==false,!sample.lowPower,let battery=input.batteryPercent,battery.isFinite,battery>=0,battery<=30 {
            items.append(DiagnosticFinding(id:"battery-policy",kind:.batteryPolicy,severity:.information,confidence:.confirmed,value:battery,action:.lowPowerPlan))
        }
        if let count=input.blockers,count>0 {
            items.append(DiagnosticFinding(id:"wake-requests",kind:.wakeRequests,severity:.information,confidence:.confirmed,value:Double(count),action:.wakeRequests))
        }
        let partial=sample.cpuTemperature==nil || sample.cpuUsage==nil || !sample.limitKnown || sample.memoryPressure==nil || !processFresh || input.blockers==nil
        if partial,observed>=30 {
            items.append(DiagnosticFinding(id:"data-unavailable",kind:.unavailable,severity:.information,confidence:.unavailable,action:.refresh))
        }
        items.sort {a,b in
            if a.severity != b.severity {return a.severity.rawValue>b.severity.rawValue}
            func rank(_ kind:DiagnosticKind)->Int {switch kind {case .thermalPressure,.thermalLimit:return 0;case .memoryPressure:return 1;case .performanceLimit:return 2;case .sustainedCPU:return 3;case .temperature,.temperatureObservation:return 4;case .batteryPolicy:return 5;case .diskActivity:return 6;case .wakeRequests:return 7;case .unavailable:return 8}}
            if rank(a.kind) != rank(b.kind) {return rank(a.kind)<rank(b.kind)}
            return a.id<b.id
        }
        let count=items.filter{$0.severity != .information}.count
        let state:DiagnosticState
        if count>0 {state = .attention}
        else if observed<45 || (processFresh && metrics.processSeconds<45) {state = .sampling}
        else if partial {state = .partial}
        else if warm || items.contains(where:{$0.kind == .diskActivity}) {state = .observing}
        else {state = .stable}
        return DiagnosticReport(state:state,findings:items,attentionCount:count,observedSeconds:processFresh ? min(observed,metrics.processSeconds):observed,date:now,metrics:metrics)
    }
}
