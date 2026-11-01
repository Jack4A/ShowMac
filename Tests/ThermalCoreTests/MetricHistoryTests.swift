import Foundation
import ThermalCore

struct MetricHistoryTests {
    func testMissingAndSampleGaps() {
        var history=MetricHistory()
        let base=Date(timeIntervalSince1970:1000)
        history.append(0,at:base);history.append(50,at:base.addingTimeInterval(5))
        expectEqual(history.points[0].value,0);expectEqual(history.points[0].segment,history.points[1].segment)
        history.append(.nan,at:base.addingTimeInterval(10));history.append(25,at:base.addingTimeInterval(15))
        expectTrue(history.points[2].value==nil);expectTrue(history.points[3].segment != history.points[1].segment)
        history.append(30,at:base.addingTimeInterval(40))
        expectTrue(history.points[4].segment != history.points[3].segment)
        var memory=MetricHistory(maximumGap:35)
        memory.append(60,at:base);memory.append(65,at:base.addingTimeInterval(25))
        expectEqual(memory.points[0].segment,memory.points[1].segment)
    }
    func testBoundedHistoryAndActualTimestamps() {
        var history=MetricHistory()
        let base=Date(timeIntervalSince1970:1000)
        history.append(10,at:base);history.append(99,at:base);history.append(99,at:base.addingTimeInterval(-1))
        expectEqual(history.points.count,1);expectEqual(history.points[0].value,10)
        for n in 1...1200 {history.append(Double(n%100),at:base.addingTimeInterval(Double(n*2)))}
        expectTrue(history.points.count<=901)
        let end=base.addingTimeInterval(2400),window=history.window(ending:end,seconds:120)
        expectTrue(window.allSatisfy{$0.date>=end.addingTimeInterval(-120) && $0.date<=end})
        expectEqual(window.last?.date,end);expectEqual(window.count,61)
    }
    func testPlotPreservesPeaksAndSegments() {
        var h=MetricHistory();let base=Date(timeIntervalSince1970:1000)
        for n in 0..<900 {h.append(n==450 ? nil:(n==222 ? 99:(n==668 ? 1:50)),at:base.addingTimeInterval(Double(n*2)))}
        let plotted=MetricPlot.decimated(h.points)
        expectTrue(plotted.count<300)
        expectEqual(plotted.first?.date,h.points.first?.date);expectEqual(plotted.last?.date,h.points.last?.date)
        expectTrue(plotted.contains{$0.value==99});expectTrue(plotted.contains{$0.value==1})
        expectTrue(plotted.contains{$0.date==base.addingTimeInterval(898)})
        expectTrue(plotted.contains{$0.date==base.addingTimeInterval(902)})
        expectTrue(plotted.allSatisfy{h.points.contains($0)})
        expectEqual(Set(plotted.map(\.segment)).count,2)
    }
    func testPlotInspectionRejectsGaps() {
        var h=MetricHistory();let base=Date(timeIntervalSince1970:1000)
        h.append(10,at:base);h.append(nil,at:base.addingTimeInterval(10));h.append(30,at:base.addingTimeInterval(20))
        expectNil(MetricPlot.nearest(h.points,to:base.addingTimeInterval(10),maximumDistance:3))
        expectEqual(MetricPlot.nearest(h.points,to:base.addingTimeInterval(19),maximumDistance:3)?.value,30)
        expectNil(MetricPlot.nearest(h.points,to:base,maximumDistance:.nan))
    }
    func testPlotScalesRemainReadable() {
        let flat=MetricPlot.scale([70,70],automatic:true)
        expectTrue(flat.contains(70));expectTrue(flat.upperBound-flat.lowerBound>=10)
        let fixed=MetricPlot.scale([500,7000],automatic:false,upper:6000)
        expectEqual(fixed.lowerBound,0);expectEqual(fixed.upperBound,7000)
        expectEqual(MetricPlot.scale([],automatic:true),0...100)
        let filtered=MetricPlot.scale([.nan,.infinity,-10,42],automatic:true)
        expectTrue(filtered.contains(42));expectTrue(filtered.lowerBound>=0);expectTrue(filtered.upperBound.isFinite)
    }
}
