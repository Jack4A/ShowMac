import Foundation
import ThermalCore
import CSMC

final class SensorInventoryTests {
    private func decode(_ type:UInt32,_ bytes:[UInt8],size:UInt32=2)->Double {
        var value=TSValue();value.type=type;value.size=size
        withUnsafeMutableBytes(of:&value.bytes) {buffer in
            for (index,byte) in bytes.enumerated() {buffer[index]=byte}
        }
        return ts_decode(&value)
    }
    func testPhysicalFormatsAndMissingValues() {
        expectEqual(decode(0x66703838,[0x0c,0x80]),12.5) // fp88: voltage
        expectEqual(decode(0x73703561,[0xfa,0x00]),-1.5) // sp5a: signed current
        expectEqual(decode(0x73703738,[0x2a,0x80]),42.5)
        expectEqual(decode(0x66706532,[0x0f,0xa0]),1000)
        expectTrue(decode(0x66703939,[0,1]).isNaN)
        expectTrue(decode(0x66703838,[0,1],size:1).isNaN)
        expectNil(HardwareSensorKind.smcKind(key:"PSTR",type:0x75693820,size:1))
        expectNil(HardwareSensorKind.smcKind(key:"F0Tg",type:0x666c7420,size:4))
        expectEqual(HardwareSensorKind.smcKind(key:"VC0C",type:0x66703838,size:2),.voltage)
        expectEqual(HardwareSensorKind.current.valid(-1.5),-1.5)
        expectEqual(HardwareSensorKind.power.valid(0),0)
        expectNil(HardwareSensorKind.voltage.valid(-1))
        expectNil(HardwareSensorKind.temperature.valid(0))
        expectNil(HardwareSensorKind.power.valid(.infinity))
    }
    func testCompleteInventoryAndBackwardCompatibility() throws {
        let base=CurveTests().snapshot(55)
        let sensors=(0..<160).map {SensorReading(key:String(format:"T%03d",$0),label:"探头",celsius:40+Double($0%20))}
        let extra=[HardwareSensorReading(key:"PC0C",label:"PC0C",kind:.power,value:0),HardwareSensorReading(key:"IC0C",label:"IC0C",kind:.current,value:-1.5),HardwareSensorReading(key:"VC0C",label:"VC0C",kind:.voltage,value:nil),HardwareSensorReading(key:"T999",label:"T999",kind:.temperature,value:nil)]
        let sample=Snapshot(date:base.date,cpuUsage:base.cpuUsage,sensors:sensors,fans:base.fans,speedLimit:100,schedulerLimit:100,availableCPUs:10,totalCPUs:10,thermalState:0,thermalWarning:nil,turbo:.unsupported,acPower:true,lowPower:false,smcAvailable:true,additionalSensors:extra)
        let rows=SensorInventory.readings(sample)
        expectEqual(rows.count,164+base.fans.count)
        expectEqual(rows.filter{$0.kind == .temperature}.count,161)
        expectEqual(rows.first{$0.key=="PC0C"}?.value,0)
        expectNil(rows.first{$0.key=="VC0C"}?.value)
        let data=try JSONEncoder().encode(sample)
        let restored=try JSONDecoder().decode(Snapshot.self,from:data)
        expectEqual(SensorInventory.readings(restored).count,rows.count)
        var legacy=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        legacy.removeValue(forKey:"additionalSensors")
        let old=try JSONDecoder().decode(Snapshot.self,from:JSONSerialization.data(withJSONObject:legacy))
        expectNil(old.additionalSensors)
        expectEqual(old.sensors.count,160)
        expectEqual(old.cpuTemperature,sample.cpuTemperature)
    }
}
