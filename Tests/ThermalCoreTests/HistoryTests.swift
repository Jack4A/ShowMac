import Foundation
import ThermalCore

final class HistoryTests {
    func sample(_ time:Double,_ mode:TurboState,_ temperature:Double?=60)->Snapshot {
        Snapshot(date:Date(timeIntervalSince1970:time),cpuUsage:20,sensors:temperature.map { [SensorReading(key:"TC0F",label:"CPU",celsius:$0)] } ?? [],fans:[],speedLimit:100,schedulerLimit:100,availableCPUs:12,totalCPUs:12,thermalState:0,thermalWarning:nil,turbo:mode,acPower:true,lowPower:false,smcAvailable:true)
    }
    func testSwitchCreatesIndependentSegmentsAndAlignedTime() {
        let data=[sample(0,.disabledDriverLoaded),sample(2,.disabledDriverLoaded),sample(4,.driverNotLoaded,70),sample(6,.driverNotLoaded,72),sample(8,.disabledDriverLoaded,65)]
        let points=TurboHistory.points(data)
        expectEqual(points.map(\.segment),[1,1,2,2,3])
        expectEqual(points.map(\.elapsed),[0,2,0,2,0])
        expectEqual(TurboHistory.transitions(data).map(\.date),[Date(timeIntervalSince1970:4),Date(timeIntervalSince1970:8)])
    }
    func testUnknownMissingAndGapBreakCurves() {
        let data=[sample(0,.disabledDriverLoaded),sample(2,.unknown),sample(4,.disabledDriverLoaded),sample(6,.disabledDriverLoaded,nil),sample(8,.disabledDriverLoaded),sample(60,.disabledDriverLoaded)]
        let points=TurboHistory.points(data)
        expectEqual(points.count,4)
        expectEqual(points.map(\.segment),[1,2,3,4])
        expectEqual(points.map(\.elapsed),[0,0,0,0])
    }
    func testMissingComparisonNotInvented() {
        let points=TurboHistory.points([sample(0,.disabledDriverLoaded,60),sample(2,.disabledDriverLoaded,70)])
        let absent=TurboHistory.summary(points,mode:.on)
        expectEqual(absent.count,0);expectNil(absent.average);expectNil(absent.maximum)
        let off=TurboHistory.summary(points,mode:.off)
        expectEqual(off.average!,65);expectEqual(off.maximum!,70);expectEqual(off.averageLoad!,20)
    }
}
