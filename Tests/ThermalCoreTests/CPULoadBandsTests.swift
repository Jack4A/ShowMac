import Foundation
import ThermalCore

struct CPULoadBandsTests {
    func points(_ values:[Double?],times:[Double]?=nil)->[MetricPoint] {
        var h=MetricHistory()
        for (i,n) in values.enumerated(){h.append(n,at:Date(timeIntervalSince1970:1000+(times?[i] ?? Double(i*5))))}
        return h.points
    }
    func testThresholdsAndDuration() {
        let input=points([0,69.9,70,89.9,90,95,100,89,30])
        expectEqual(CPULoadBands.samples(input).map(\.level),[.normal,.normal,.elevated,.elevated,.elevated,.elevated,.critical,.elevated,.normal])
        expectEqual(CPULoadBands.current(30,points:input,at:input.last!.date),.normal)
        expectEqual(CPULoadBands.current(95,points:[],at:Date()),.elevated)
        expectEqual(CPULoadBands.baseLevel(.nan),.unknown);expectEqual(CPULoadBands.baseLevel(101),.unknown)
    }
    func testGapsAndMissingResetSustainedTime() {
        let gaps=points([95,95,95,95,95,95],times:[0,5,10,30,35,40])
        expectEqual(CPULoadBands.samples(gaps).map(\.level),[.elevated,.elevated,.critical,.elevated,.elevated,.critical])
        let missing=points([95,95,nil,95,95,95])
        expectEqual(CPULoadBands.samples(missing).map(\.level),[.elevated,.elevated,.unknown,.elevated,.elevated,.critical])
        let invalid=points([95,95,101,95,95,95])
        expectEqual(CPULoadBands.samples(invalid).map(\.level),[.elevated,.elevated,.unknown,.elevated,.elevated,.critical])
    }
    func testRunsKeepTransitionsAndActualSamples() {
        let input=points([20,30,75,95,95,95,50,nil,95,95,95])
        let runs=CPULoadBands.runs(input,budget:8)
        expectEqual(runs.map(\.level),[.normal,.elevated,.critical,.normal,.elevated,.critical])
        expectTrue(runs.flatMap(\.points).allSatisfy{input.contains($0)})
        expectTrue(runs.allSatisfy{run in Set(run.points.map(\.segment)).count==1})
        expectEqual(runs[2].points.first?.date,input[5].date)
        expectEqual(runs[3].points.first?.date,input[6].date)
        expectEqual(runs[3].points.first?.value,50)
        expectEqual(CPULoadBands.current(nil,points:input,at:input.last!.date),.unknown)
    }
}
