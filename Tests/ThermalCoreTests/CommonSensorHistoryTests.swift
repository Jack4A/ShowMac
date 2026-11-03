import Foundation
import ThermalCore

struct CommonSensorHistoryTests {
    private let base=Date(timeIntervalSince1970:10_000)
    private func sample(_ seconds:Double,temperatures:[Double]=[50,60],power:Double?=12,fan:Double?=1000)->Snapshot {
        Snapshot(date:base.addingTimeInterval(seconds),cpuUsage:nil,sensors:temperatures.enumerated().map{SensorReading(key:$0.offset==0 ? "TC0P":"TC1P",label:"CPU",celsius:$0.element)},fans:[FanReading(id:0,rpm:fan,minimum:0,maximum:6000,manual:false,controllable:true)],speedLimit:100,schedulerLimit:100,availableCPUs:4,totalCPUs:4,thermalState:0,thermalWarning:nil,turbo:.unsupported,acPower:true,lowPower:false,smcAvailable:true,additionalSensors:[HardwareSensorReading(key:"PSTR",label:"PSTR",kind:.power,value:power)])
    }
    func testMatchesCardsAndPreservesSignedPower() {
        var history=CommonSensorHistory()
        history.record(sample(0,power:-2,fan:0),platform:.generic)
        history.record(sample(5,temperatures:[70,55],power:0,fan:1200),platform:.generic)
        expectEqual(history.points(for:"cpu",minutes:10).compactMap(\.value),[60,70])
        expectEqual(history.points(for:"power:PSTR",minutes:10).compactMap(\.value),[-2,0])
        expectEqual(history.points(for:"fan:F0Ac",minutes:10).compactMap(\.value),[0,1200])
        expectEqual(history.readings.first{$0.id=="cpu"}?.value,70)
        expectEqual(history.end,base.addingTimeInterval(5))
        expectEqual(Set(history.readings.first{$0.id=="cpu"}?.sources ?? []),Set(["TC0P","TC1P"]))
    }
    func testOutagesAndSleepBreakLinesWithoutLosingCards() {
        var history=CommonSensorHistory()
        history.record(sample(0),platform:.generic)
        history.record(sample(5,temperatures:[],power:nil,fan:nil),platform:.generic)
        expectNil(history.readings.first{$0.id=="cpu"}?.value)
        expectEqual(history.readings.count,3)
        history.record(sample(10),platform:.generic)
        history.record(sample(40),platform:.generic)
        let points=history.points(for:"cpu",minutes:10)
        expectEqual(points.count,4)
        expectNil(points[1].value)
        expectNotEqual(points[0].segment,points[2].segment)
        expectNotEqual(points[2].segment,points[3].segment)
        expectEqual(MetricPlot.decimated(points).count,3)
    }
    func testTimeWindowsRetentionAndOutOfOrderSamples() {
        var history=CommonSensorHistory()
        for i in 0...1200 {history.record(sample(Double(i*2)),platform:.generic)}
        let thirty=history.points(for:"cpu",minutes:30)
        expectEqual(thirty.count,901)
        expectEqual(thirty.first?.date,base.addingTimeInterval(600))
        expectEqual(history.points(for:"cpu",minutes:5).count,151)
        expectEqual(history.points(for:"cpu",minutes:10).count,301)
        history.record(sample(2400,temperatures:[99]),platform:.generic)
        history.record(sample(2300,temperatures:[99]),platform:.generic)
        expectEqual(history.points(for:"cpu",minutes:30),thirty)
        history.record(sample(4201,temperatures:[]),platform:.generic)
        expectFalse(history.readings.contains{$0.id=="cpu"})
        expectTrue(history.points(for:"cpu",minutes:30).isEmpty)
    }
}
