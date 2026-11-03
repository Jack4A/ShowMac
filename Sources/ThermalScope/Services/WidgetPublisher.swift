import Foundation
import WidgetKit
import ThermalCore
import WidgetShared

@MainActor final class WidgetPublisher:ObservableObject {
    @Published private(set) var lastPublished:Date?
    @Published private(set) var error:String?
    private let queue=DispatchQueue(label:"local.thermalscope.widget-snapshot",qos:.utility)
    private let enabled=["local.jack.ThermalScope","com.jackjohn.showmac"].contains(Bundle.main.bundleIdentifier ?? "")
    private var schedule=WidgetPublishSchedule()
    private var last:WidgetSnapshot?
    static func snapshot(_ sample:Snapshot,mode:String,language:String,history:MetricHistoryStore?=nil)->WidgetSnapshot {
        var trends:[String:[WidgetPoint]]=[:]
        if let history {
            for kind in WidgetMetric.allCases {
                guard let source=MetricKind(rawValue:kind.rawValue) else{continue}
                trends[kind.rawValue]=MetricPlot.decimated(history.points(source,minutes:5),budget:48).map{WidgetPoint(date:$0.date,value:$0.value,segment:$0.segment)}
            }
        }
        let turbo=sample.turbo == .disabledDriverLoaded ? "已关闭":(sample.turbo == .driverNotLoaded ? "允许开启":"未知")
        return WidgetSnapshot(date:sample.date,cpuTemperature:sample.temperature(.cpu),gpuTemperature:sample.temperature(.gpu),storageTemperature:sample.temperature(.storage),cpuUsage:sample.cpuUsage,fans:sample.fans.map{WidgetFan(id:$0.id,rpm:$0.rpm,maximum:$0.maximum,manual:$0.manual)},mode:mode,turbo:turbo,language:language,trends:trends)
    }
    func record(_ sample:Snapshot,mode:String,language:String,history:MetricHistoryStore) {
        guard enabled else{return}
        let state=mode+"|"+sample.turbo.rawValue+"|"+language
        let decision=schedule.receive(date:sample.date,state:state)
        guard decision.write else{return}
        let snapshot=Self.snapshot(sample,mode:mode,language:language,history:history)
        last=snapshot
        let reload=decision.reload
        queue.async {[weak self] in
            do {
                try WidgetStorage.write(snapshot)
                if reload {WidgetCenter.shared.reloadTimelines(ofKind:WidgetStorage.kind)}
                DispatchQueue.main.async {self?.lastPublished=snapshot.date;self?.error=nil}
            } catch {let text=error.localizedDescription;DispatchQueue.main.async {self?.error=text}}
        }
    }
    func shutdown() {
        guard enabled,var snapshot=last else{return}
        snapshot.running=false
        queue.sync {try? WidgetStorage.write(snapshot);WidgetCenter.shared.reloadTimelines(ofKind:WidgetStorage.kind)}
    }
}
