import Foundation
import ThermalCore

final class SensorCatalogTests {
    func reading(_ key:String,_ kind:HardwareSensorKind = .temperature,_ value:Double?=50)->HardwareSensorReading {
        HardwareSensorReading(key:key,label:key,kind:kind,value:value)
    }
    func testPlatformAndCaseSensitiveNames() {
        expectEqual(SensorNamingPlatform.detect(cpuBrand:"Apple M4"),.appleM4)
        expectEqual(SensorNamingPlatform.detect(cpuBrand:"Apple M4 Pro"),.appleM4ProMax)
        expectEqual(SensorNamingPlatform.detect(cpuBrand:"Apple M40"),.generic)
        expectEqual(SensorNamingPlatform.detect(cpuBrand:"Apple M5"),.generic)
        expectEqual(SensorCatalog.meaning(reading("Te05"),platform:.appleM4)?.component,.cpu)
        expectNil(SensorCatalog.meaning(reading("Te05"),platform:.generic))
        expectEqual(SensorCatalog.meaning(reading("Tg0d"),platform:.appleM4)?.component,.gpu)
        expectNil(SensorCatalog.meaning(reading("Tg0D"),platform:.appleM4))
        expectNil(SensorCatalog.meaning(reading("Tg0G"),platform:.appleM4ProMax))
        expectEqual(SensorCatalog.meaning(reading("Tg1U"),platform:.appleM4ProMax)?.component,.gpu)
        expectEqual(SensorCatalog.meaning(reading("Tm1p"),platform:.appleM4)?.component,.memory)
        expectNil(SensorCatalog.meaning(reading("Tm1P"),platform:.appleM4))
        expectNil(SensorCatalog.meaning(reading("Tp01",.voltage),platform:.appleM4))
        expectNil(SensorCatalog.meaning(reading("Ta0L"),platform:.appleM4))
    }
    func testCommonReadingsUseRecognizedSources() {
        let rows=[reading("TCMb",.temperature,55),reading("Te05",.temperature,60),reading("Tunknown",.temperature,129),reading("Tg0d",.temperature,45),reading("PSTR",.power,0),reading("PDTR",.power,20)]
        let summaries=SensorCatalog.common(rows,platform:.appleM4)
        let cpu=summaries.first{$0.id=="cpu"}
        expectEqual(cpu?.value,60)
        expectEqual(Set(cpu?.sources ?? []),Set(["TCMb","Te05"]))
        expectEqual(summaries.first{$0.title=="整机功耗"}?.value,0)
        expectFalse(summaries.contains{$0.title=="直流输入功耗"})
        expectEqual(summaries.first{$0.id=="gpu"}?.value,45)
        expectFalse(summaries.contains{$0.sources.contains("Tunknown")})
        let missing=SensorCatalog.common([reading("PSTR",.power,nil),reading("PDTR",.power,20)],platform:.generic)
        expectEqual(missing.first?.title,"直流输入功耗")
        expectEqual(missing.first?.value,20)
        expectTrue(SensorCatalog.common([reading("Tunknown")],platform:.generic).isEmpty)
    }
    func testTemperatureSourcesMatchKnownPlatformProbes() {
        let sample=Snapshot(date:Date(),cpuUsage:10,sensors:[
            SensorReading(key:"TCMb",label:"CPU",celsius:55),
            SensorReading(key:"Te05",label:"CPU probe",celsius:62),
            SensorReading(key:"Tg0d",label:"GPU probe",celsius:82),
            SensorReading(key:"Tg0D",label:"Unverified probe",celsius:115),
            SensorReading(key:"Tunknown",label:"Unknown probe",celsius:120),
            SensorReading(key:"TG0P",label:"Invalid GPU",celsius:.infinity)
        ],fans:[],speedLimit:100,schedulerLimit:100,availableCPUs:8,totalCPUs:8,thermalState:0,thermalWarning:nil,turbo:.unsupported,acPower:true,lowPower:false,smcAvailable:true)
        expectEqual(sample.temperature(.cpu,platform:.appleM4),62)
        expectEqual(sample.temperature(.gpu,platform:.appleM4),82)
        expectEqual(sample.temperature(.cpu,platform:.generic),55)
        expectNil(sample.temperature(.gpu,platform:.generic))
        expectEqual(SensorCategory.category(for:"Tg0d",platform:.appleM4),.gpu)
        expectEqual(SensorCategory.category(for:"Tg0D",platform:.appleM4),.other)
        expectEqual(SensorCategory.category(for:"Tg0G",platform:.appleM4ProMax),.other)
    }
}
