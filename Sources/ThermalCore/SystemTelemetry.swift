import Foundation
import IOKit
import IOKit.ps
import Darwin

public struct SystemTelemetry:Identifiable,Codable {
    public let date:Date
    public var id:Date { date }
    public let batteryPercent:Double?
    public let batteryWatts:Double?
    public let charging:Bool?
    public let cycles:Int?
    public let memoryUsed:Double?
    public let memoryTotal:Double
    public var memoryPercent:Double? { memoryUsed.map { $0 / memoryTotal * 100 } }
    public static func watts(millivolts:Double?,milliamps:Double?)->Double? {
        guard let v=millivolts,let a=milliamps,v.isFinite,a.isFinite,(1000...30000).contains(v),abs(a)<30000 else { return nil }
        return v*a/1_000_000
    }
    public static func read()->SystemTelemetry {
        var percent:Double?,watts:Double?,charging:Bool?,cycles:Int?
        if let info=IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),let sources=IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let d=IOPSGetPowerSourceDescription(info,source)?.takeUnretainedValue() as? [String:Any],d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                if let c=d[kIOPSCurrentCapacityKey] as? Double,let m=d[kIOPSMaxCapacityKey] as? Double,m>0 { percent=min(100,max(0,c/m*100)) }
                charging=d[kIOPSIsChargingKey] as? Bool
            }
        }
        let battery=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSmartBattery"))
        if battery != 0 {
            defer { IOObjectRelease(battery) }
            func number(_ key:String)->Double? { (IORegistryEntryCreateCFProperty(battery,key as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? NSNumber)?.doubleValue }
            watts=Self.watts(millivolts:number("Voltage"),milliamps:number("Amperage"))
            cycles=number("CycleCount").flatMap { $0>=0 && $0<100000 ? Int($0):nil }
        }
        var vm=vm_statistics64_data_t()
        var count=mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size/MemoryLayout<integer_t>.size)
        let host=mach_host_self()
        defer {mach_port_deallocate(mach_task_self_,host)}
        let result=withUnsafeMutablePointer(to:&vm) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { host_statistics64(host,HOST_VM_INFO64,$0,&count) }
        }
        let total=Double(ProcessInfo.processInfo.physicalMemory)
        let used:Double?=result==KERN_SUCCESS ? min(total,Double(UInt64(vm.active_count)+UInt64(vm.wire_count)+UInt64(vm.compressor_page_count))*Double(vm_kernel_page_size)):nil
        return SystemTelemetry(date:Date(),batteryPercent:percent,batteryWatts:watts,charging:charging,cycles:cycles,memoryUsed:used,memoryTotal:total)
    }
}
