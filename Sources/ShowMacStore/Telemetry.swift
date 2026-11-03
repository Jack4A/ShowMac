import Foundation
import Darwin
import IOKit.ps

// This target has no dependency on ThermalCore, CSMC or the desktop helper.
struct CPUTicks {
    let user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
    func utilization(since old: CPUTicks) -> Double? {
        let busy = UInt64(user &- old.user) + UInt64(system &- old.system) + UInt64(nice &- old.nice)
        let total = busy + UInt64(idle &- old.idle)
        guard total > 0 else { return nil }
        return Double(busy) / Double(total) * 100
    }
}
struct StoreSample: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double?, memoryBytes: Double?, battery: Double?
    let thermal: ProcessInfo.ThermalState
    let powerSource: String?
    let charging: Bool?
    let lowPower: Bool?
}
final class StoreSampler {
    private var previousCPU: CPUTicks?
    private func cpuTicks() -> CPUTicks? {
        var data = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let status = withUnsafeMutablePointer(to: &data) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return nil }
        return CPUTicks(user: data.cpu_ticks.0, system: data.cpu_ticks.1, idle: data.cpu_ticks.2, nice: data.cpu_ticks.3)
    }
    func sample() -> StoreSample {
        let info = ProcessInfo.processInfo
        let ticks = cpuTicks()
        let cpu = ticks.flatMap { value in previousCPU.flatMap { value.utilization(since: $0) } }
        previousCPU = ticks
        var vm = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let status = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        mach_port_deallocate(mach_task_self_, host)
        let estimate = Double(UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * Double(vm_kernel_page_size)
        let memory = status == KERN_SUCCESS ? min(Double(info.physicalMemory), estimate) : nil
        var battery: Double?, charging: Bool?, powerSource: String?
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            powerSource = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
            if let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
                for source in sources {
                    guard let data = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                          data[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                          data[kIOPSIsPresentKey] as? Bool != false else { continue }
                    if let current = data[kIOPSCurrentCapacityKey] as? Double, let maximum = data[kIOPSMaxCapacityKey] as? Double, maximum > 0 {
                        battery = min(100, max(0, current / maximum * 100))
                    }
                    charging = data[kIOPSIsChargingKey] as? Bool
                    break
                }
            }
        }
        var lowPower: Bool?
        if #available(macOS 12.0, *) { lowPower = info.isLowPowerModeEnabled }
        return StoreSample(date: Date(), cpu: cpu, memoryBytes: memory, battery: battery, thermal: info.thermalState, powerSource: powerSource, charging: charging, lowPower: lowPower)
    }
}
