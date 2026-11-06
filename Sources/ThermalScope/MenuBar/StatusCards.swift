import SwiftUI
import ThermalCore

/// Popover contents are independent of the narrow components in the menu bar.
enum StatusCardSource:Codable,Hashable,Identifiable {
    case metric(MetricKind)
    case sensor(MenuSensorReference)
    var id:String {switch self {case .metric(let kind):return "metric:"+kind.rawValue;case .sensor(let ref):return ref.id}}
    var isValid:Bool {if case .sensor(let ref)=self {return ref.isValid};return true}
    var sensor:MenuSensorReference? {if case .sensor(let ref)=self {return ref};return nil}
    var warningKind:MetricKind? {switch self {case .metric(let kind):return kind;case .sensor(let ref):return MetricWarningBands.kind(sensor:ref)}}
    var symbol:String {
        switch self {
        case .sensor(let ref):return ref.symbol
        case .metric(let kind):
            switch kind {
            case .cpuTemperature:return "thermometer.medium"
            case .gpuTemperature:return "display"
            case .storageTemperature:return "internaldrive"
            case .cpuUsage:return "cpu"
            case .memory:return "memorychip"
            case .fan:return "fanblades"
            case .battery:return "battery.75percent"
            }
        }
    }
    var unit:String {switch self {case .metric(let kind):return kind.unit.trimmingCharacters(in:.whitespaces);case .sensor(let ref):return ref.kind.unit}}
    var upper:Double {switch self {case .metric(let kind):return kind.fixedUpper;case .sensor(let ref):return ref.upper}}
    @MainActor func title(_ model:AppModel)->String {
        switch self {case .metric(let kind):return L(kind.title);case .sensor(let ref):return MenuComponentSource.sensor(ref).title(in:model)}
    }
    @MainActor func value(_ readings:LiveReadings)->Double? {
        let value:Double?
        switch self {
        case .metric(let kind):
            if let category=kind.sensor {value=readings.snapshot?.temperature(category)}
            else {switch kind {
                case .cpuUsage:value=readings.snapshot?.cpuUsage.flatMap{$0<=100 ? $0:nil}
                case .memory:value=readings.telemetry?.memoryPercent.flatMap{$0<=100 ? $0:nil}
                case .battery:value=readings.telemetry?.batteryPercent.flatMap{$0<=100 ? $0:nil}
                case .fan:value=readings.snapshot?.fans.compactMap(\.rpm).max()
                default:value=nil
            }}
        case .sensor(let ref):
            if ref.isCommon {
                value=readings.snapshot.flatMap {sample in SensorCatalog.common(SensorInventory.readings(sample),platform:.current).first{$0.id==ref.key}?.value}
            } else {
                value=readings.snapshot.flatMap {SensorInventory.readings($0).first{$0.key==ref.key && $0.kind==ref.kind}?.value}
            }
        }
        return value.flatMap{$0.isFinite ? $0:nil}
    }
    func valueText(_ value:Double?)->String {
        guard let value else{return "—"}
        if case .sensor(let ref)=self {
            switch ref.kind {
            case .power:return String(format:"%.2f",value)
            case .voltage,.current:return String(format:"%.3f",value)
            default:break
            }
        }
        return String(format:"%.0f",value)
    }
    @MainActor func points(_ model:AppModel,minutes:Int)->[MetricPoint] {
        switch self {case .metric(let kind):return model.metricHistory.points(kind,minutes:minutes);case .sensor(let ref):return model.sensorHistory.points(for:ref,minutes:minutes)}
    }
    var destination:String {switch self {case .metric(let kind):return kind.rawValue;case .sensor:return "sensors"}}
}

struct StatusPanelConfiguration:Codable,Equatable {
    static let limit=8
    var cards:[StatusCardSource]=[.metric(.cpuTemperature),.metric(.cpuUsage),.metric(.fan),.metric(.memory)]
    var showFanControls=true
    var showProcesses=true
    var showTokenSummary:Bool?=nil
    static func decode(_ data:Data?)->Self {
        guard let data,let saved=try? JSONDecoder().decode(Self.self,from:data) else{return Self()}
        var result=saved,seen=Set<String>()
        result.cards=Array(saved.cards.filter{$0.isValid && seen.insert($0.id).inserted}.prefix(limit))
        if result.cards.isEmpty {result.cards=Self().cards}
        return result
    }
}

extension AppModel {
    var showsStatusTokenSummary:Bool {statusPanel.showTokenSummary ?? effectiveMenuComponents.contains{$0.metric.isToken}}
    @discardableResult func moveStatusCard(id:String,before target:String)->Bool {
        guard id != target,let index=statusPanel.cards.firstIndex(where:{$0.id==id}),statusPanel.cards.contains(where:{$0.id==target}) else{return false}
        var cards=statusPanel.cards
        let item=cards.remove(at:index)
        let destination=cards.firstIndex(where:{$0.id==target})!
        cards.insert(item,at:destination);statusPanel.cards=cards;return true
    }
    var retainedSensorReferences:[MenuSensorReference] {Array(Set(effectiveMenuComponents.compactMap(\.sensor)+statusPanel.cards.compactMap(\.sensor)))}
    @discardableResult func addStatusCard(_ source:StatusCardSource)->Bool {
        guard source.isValid,statusPanel.cards.count<StatusPanelConfiguration.limit,!statusPanel.cards.contains(source) else{return false}
        if let ref=source.sensor,!menuSensorOptions.contains(where:{$0.reference==ref}) {return false}
        statusPanel.cards.append(source);return true
    }
    func removeStatusCard(_ source:StatusCardSource) {
        guard statusPanel.cards.count>1 else{return}
        statusPanel.cards.removeAll{$0==source}
    }
    func moveStatusCard(_ source:StatusCardSource,by offset:Int) {
        guard let index=statusPanel.cards.firstIndex(of:source),statusPanel.cards.indices.contains(index+offset) else{return}
        statusPanel.cards.swapAt(index,index+offset)
    }
}

enum StatusCardLayout {
    static let tileHeight:CGFloat=78
    static let wideHeight:CGFloat=58
    static let spacing:CGFloat=8
    static func height(count:Int)->CGFloat {
        let rows=(count+1)/2
        return CGFloat(count/2)*tileHeight+(count.isMultiple(of:2) ? 0:wideHeight)+CGFloat(max(0,rows-1))*spacing
    }
}

/// Quiet surfaces keep the trend and current reading above the background.
struct StatusCardSurface:ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var hovered=false
    func body(content:Content)->some View {
        content.appBackground {
            RoundedRectangle(cornerRadius:12,style:.continuous).fill(Palette.surface)
                .appOverlay {
                    if scheme == .dark {
                        RoundedRectangle(cornerRadius:12,style:.continuous)
                            .fill(LinearGradient(gradient:Gradient(colors:[Palette.highlight.opacity(0.07),.clear]),startPoint:.topLeading,endPoint:.bottomTrailing))
                    }
                }
                .shadow(color:.black.opacity(contrast == .increased ? 0:(scheme == .dark ? 0.10:0.018)),radius:5,x:0,y:2)
        }.appOverlay {
            RoundedRectangle(cornerRadius:12,style:.continuous)
                .stroke(border,lineWidth:contrast == .increased ? CGFloat(1):CGFloat(0.6)).allowsHitTesting(false)
        }
    }
    private var border:Color {
        if contrast == .increased {return Color.primary.opacity(0.45)}
        return hovered ? Palette.violet.opacity(scheme == .dark ? 0.65:0.45):Palette.border.opacity(scheme == .dark ? 0.6:0.7)
    }
}

struct StatusMetricCard:View {
    let model:AppModel
    @ObservedObject var readings:LiveReadings
    @ObservedObject var metrics:MetricHistoryStore
    @ObservedObject var sensors:SensorHistoryStore
    let source:StatusCardSource
    let wide:Bool
    let onOpen:()->Void
    @State private var hovered=false
    init(model:AppModel,source:StatusCardSource,wide:Bool=false,onOpen:@escaping()->Void) {
        self.model=model;readings=model.readings;metrics=model.metricHistory;sensors=model.sensorHistory;self.source=source;self.wide=wide;self.onOpen=onOpen
    }
    private var full:[MetricPoint] {source.points(model,minutes:model.statusMinutes)}
    private var end:Date {source.sensor == nil ? metrics.end:sensors.end}
    private var runs:[CPULoadRun] {MetricWarningBands.runs(full,kind:source.warningKind,enabled:model.menuCPUWarnings,budget:80)}
    private var level:CPULoadLevel {MetricWarningBands.current(source.value(readings),points:full,at:end,kind:source.warningKind,enabled:model.menuCPUWarnings)}
    private var scale:ClosedRange<Double> {
        let values=full.compactMap(\.value)+[source.value(readings)].compactMap{$0}
        return min(0,values.min() ?? 0)...max(source.upper,values.max() ?? 0)
    }
    private var cardDescription:String {
        let value=source.valueText(source.value(readings))+" "+source.unit
        let warning=level > .normal ? " · "+L(MetricWarningBands.title(level,kind:source.warningKind)):""
        return source.title(model)+" · "+value+warning+" · "+L(source.sensor == nil ? "指标详情":"查看完整读数")
    }
    var body:some View {
        Button(action:onOpen) {
            Group {
                if wide {
                    HStack(spacing:18) {
                        reading
                        graph.frame(width:106,height:26)
                    }
                } else {
                    VStack(alignment:.leading,spacing:8) {
                        reading
                        graph.frame(height:24)
                    }
                }
            }.padding(.horizontal,12).padding(.vertical,10)
                .frame(maxWidth:.infinity,alignment:.leading).frame(height:wide ? StatusCardLayout.wideHeight:StatusCardLayout.tileHeight)
                .modifier(StatusCardSurface(hovered:hovered))
                .contentShape(RoundedRectangle(cornerRadius:12,style:.continuous))
        }.buttonStyle(.plain).onHover{hovered=$0}
            .help(cardDescription)
            .accessibilityElement(children:.ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(cardDescription)
    }
    private var reading:some View {
        HStack(alignment:.firstTextBaseline,spacing:5) {
            Image(systemName:AppSymbols.resolve(source.symbol)).font(.system(size:11,weight:.medium)).foregroundColor(Palette.violet.opacity(0.85)).frame(width:12)
            Text(source.title(model)).font(.system(size:11,weight:.medium)).foregroundColor(Palette.secondaryText).lineLimit(1).minimumScaleFactor(0.9)
            Spacer(minLength:2)
            MetricValue(value:source.valueText(source.value(readings)),unit:source.unit,size:21,unitSize:10,foreground:level > .normal ? level.plotColor():.primary)
                .fixedSize(horizontal:true,vertical:false)
        }
    }
    @ViewBuilder private var graph:some View {
        MetricPlotView(series:MetricPlotView.metricSeries(runs,filled:true),xRange:end.addingTimeInterval(-Double(model.statusMinutes*60)).timeIntervalSince1970...end.timeIntervalSince1970,yRange:scale)
            .allowsHitTesting(false).accessibilityHidden(true)

    }

}
