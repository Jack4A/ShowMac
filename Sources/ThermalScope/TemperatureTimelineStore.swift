import Foundation
import SwiftUI
import ThermalCore

@MainActor final class TemperatureTimelineStore:ObservableObject {
    @Published var sensor:SensorCategory = .cpu {didSet{rebuild()}}
    @Published var minutes:Int=10 {didSet{rebuild()}}
    @Published private(set) var points:[ModeRecord]=[]
    private(set) var fullPoints:[ModeRecord]=[]
    private var samples:[TimelineSample]=[]
    private var lastBuild=Date.distantPast
    private(set) var end=Date()
    private(set) var start=Date().addingTimeInterval(-600)
    private(set) var modes:[String]=[]
    private(set) var average:Double?
    private(set) var latest:Double?
    func append(_ sample:Snapshot,mode:String?,publish:Bool=true) {
        guard sample.date.timeIntervalSince1970.isFinite,
              samples.last.map({sample.date>$0.snapshot.date}) ?? true else{return}
        samples.append(TimelineSample(sample,mode:mode))
        samples.removeAll{$0.snapshot.date<sample.date.addingTimeInterval(-1800)}
        if samples.count>1000 {samples.removeFirst(samples.count-1000)}
        if publish && sample.date.timeIntervalSince(lastBuild)>=4 {rebuild()}
    }
    func resumeVisualUpdates(){rebuild()}
    private func rebuild() {
        end=samples.last?.snapshot.date ?? Date();start=end.addingTimeInterval(-Double(minutes*60))
        let full=SensorTimeline.records(samples,sensor:sensor,start:start)
        average=full.isEmpty ? nil:full.map(\.temperature).reduce(0,+)/Double(full.count)
        latest=full.last?.temperature;modes=Array(Set(full.map(\.mode))).sorted()
        lastBuild=end;fullPoints=full;points=SensorTimeline.decimated(full)
    }
}
