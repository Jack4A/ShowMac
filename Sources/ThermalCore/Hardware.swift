import Foundation
import CSMC

public final class SMC {
    private var connection: UInt32=0
    private lazy var armFans=AppleSiliconFanControl(read:{[unowned self] in self.number($0)},write:{[unowned self] in try self.write($0,number:$1)},wait:{Thread.sleep(forTimeInterval:0.1)})
    public init() { connection=ts_smc_open() }
    deinit { ts_smc_close(connection) }
    public var available: Bool { connection != 0 }
    public func reopen() { ts_smc_close(connection); connection=ts_smc_open() }
    public func temperatureKeys()->[String] {
        sensorKeys().filter{$0.kind == .temperature}.map(\.key)
    }
    public func sensorKeys()->[(key:String,kind:HardwareSensorKind)] {
        guard let count=number("#KEY"),count>0,count<=10000 else { return [] }
        var result:[(key:String,kind:HardwareSensorKind)]=[]
        for index in 0..<Int(count) {
            var bytes=[CChar](repeating:0,count:5)
            guard ts_smc_key_at_index(connection,UInt32(index),&bytes)==0,[84,80,86,73].contains(bytes[0]) else { continue }
            let key=String(cString:bytes)
            guard var value=try? raw(key),let kind=HardwareSensorKind.smcKind(key:key,type:value.type,size:value.size),
                  kind.valid(ts_decode(&value)) != nil else {continue}
            result.append((key,kind))
        }
        return result.sorted{$0.key<$1.key}
    }
    public func raw(_ key: String) throws -> TSValue {
        var value=TSValue()
        let code=key.withCString { ts_smc_read(connection,$0,&value) }
        guard code==0 else { throw ScopeError.message("SMC \(key) 读取失败（\(code)）") }
        return value
    }
    public func number(_ key: String) -> Double? {
        guard var value=try? raw(key) else { return nil }
        let number=ts_decode(&value)
        return number.isFinite ? number : nil
    }
    public func write(_ key: String, number: Double) throws {
        var value=try raw(key)
        guard ts_encode(number,&value)==0 else { throw ScopeError.message("SMC \(key) 不支持写入这个数值") }
        let result=key.withCString { ts_smc_write(connection,$0,&value) }
        guard result==0 else { throw ScopeError.message("SMC \(key) 写入失败（\(result)）；此机型可能不支持控制") }
        var actual:Double?
        let verified=SMCVerification.waitFor(number,now:{ProcessInfo.processInfo.systemUptime},read:{
            actual=self.number(key);return actual
        },wait:{Thread.sleep(forTimeInterval:0.05)})
        guard verified else {
            let observed=actual.map { String(format:"%.2f",$0) } ?? "无法读取"
            throw ScopeError.message("SMC \(key) 回读不一致，操作未确认（目标 \(String(format:"%.2f",number))，读回 \(observed)；已等待最多 2 秒）")
        }
    }

    public func fans() -> [FanReading] {
        guard let count=number("FNum"), count>=0, count<=10 else { return [] }
        let globalMode=number("FS! ")
        #if arch(arm64)
        let handoff=number("Ftst")
        #else
        let handoff:Double?=nil
        #endif
        return (0..<Int(count)).map { id in
            #if arch(arm64)
            let localMode=armFans.modeKey(id).flatMap {number($0)}
            #else
            let localMode=number("F\(id)Md")
            #endif
            let manual: Bool?=SMCVerification.manualState(local:localMode,flags:globalMode,id:id,handoff:handoff)
            let maxRPM=number("F\(id)Mx")
            return FanReading(id:id,rpm:number("F\(id)Ac"),minimum:number("F\(id)Mn"),maximum:maxRPM,manual:manual,
                controllable:manual != nil && number("F\(id)Tg") != nil && maxRPM.map { $0>0 && $0<=12000 } == true)
        }
    }
    public func setManual(_ id: Int, _ manual: Bool) throws {
        guard (0..<10).contains(id) else {throw ScopeError.message("无效风扇编号")}
        #if arch(arm64)
        try armFans.setManual(id,manual)
        #else
        if number("F\(id)Md") != nil { try write("F\(id)Md",number:manual ? 1:0) }
        else if let flags=number("FS! ") {
            let mask=1<<id
            let changed=manual ? Int(flags)|mask : Int(flags)&(~mask)
            try write("FS! ",number:Double(changed))
        } else { throw ScopeError.message("风扇 \(id+1) 没有可识别的模式接口") }
        #endif
    }
}

/// Used only on the sampler queue. No subprocesses or polling of `top`.
public enum SystemCapabilities {
    public static var lowPowerMode:Bool {
        if #available(macOS 12,*) {return true}
        return false
    }
}
public final class HardwareSampler: @unchecked Sendable {
    private static var lowPowerModeEnabled:Bool {
        if #available(macOS 12,*) {return ProcessInfo.processInfo.isLowPowerModeEnabled}
        return false // Low Power Mode was introduced in macOS 12.
    }
    private let lock=NSLock()
    private let smc=SMC()
    private var previous: CPUCounters?
    private var knownSensors: [(key:String,label:String,kind:HardwareSensorKind)]=[]
    private var needsDiscovery=true
    private var ticks=0
    private var turbo: TurboState = .unknown
    public init() {}
    public func reset() { lock.lock();defer { lock.unlock() };previous=nil; smc.reopen();knownSensors=[];needsDiscovery=true }
    public func sample() -> Snapshot {
        lock.lock();defer { lock.unlock() }
        var counters=TSTicks()
        var usage: Double?
        if ts_cpu_ticks(&counters)==0 {
            let now=CPUCounters(user:UInt32(truncatingIfNeeded:counters.user),system:UInt32(truncatingIfNeeded:counters.system),idle:UInt32(truncatingIfNeeded:counters.idle),nice:UInt32(truncatingIfNeeded:counters.nice))
            if let old=previous { usage=now.usage(since:old) }
            previous=now
        }
        if needsDiscovery || ticks % 60 == 0 {
            var candidates=[("TC0F","CPU die"),("TC0D","CPU diode"),("TC0P","CPU proximity"),("TC0E","CPU PECI"),("TC0H","CPU heatsink"),("TG0D","GPU diode"),("TG0P","GPU proximity")]
            candidates += (0..<10).map { ("TC\($0)C","CPU core sensor \($0)") }
            let names=Dictionary(uniqueKeysWithValues:candidates)
            var discovered=smc.sensorKeys().map {item in
                (key:item.key,label:names[item.key] ?? (item.kind == .temperature ? SensorCategory.category(for:item.key).rawValue+" · "+item.key:item.key),kind:item.kind)
            }
            let keys=Set(discovered.map(\.key))
            discovered += candidates.filter{!keys.contains($0.0) && HardwareSensorKind.temperature.valid(smc.number($0.0)) != nil}.map{(key:$0.0,label:$0.1,kind:.temperature)}
            // Retain discovered metadata through a temporary read failure.
            let found=Set(discovered.map(\.key))
            knownSensors=discovered+knownSensors.filter{!found.contains($0.key)}
            needsDiscovery=false
        }
        let hardwareReadings=knownSensors.map {sensor in
            HardwareSensorReading(key:sensor.key,label:sensor.label,kind:sensor.kind,value:smc.number(sensor.key))
        }
        let sensors=hardwareReadings.compactMap {reading -> SensorReading? in
            guard reading.kind == .temperature,let value=reading.value else{return nil}
            return SensorReading(key:reading.key,label:reading.label,celsius:value)
        }
        let additional=hardwareReadings.filter{$0.kind != .temperature || $0.value == nil}
        if ticks % 5 == 0 {
            #if arch(x86_64)
            let state=ts_turbo_driver_state()
            turbo = state==1 ? .disabledDriverLoaded : (state==0 ? .driverNotLoaded : .unknown)
            #else
            turbo = .unsupported
            #endif
        }
        ticks+=1
        let p=ts_power_status(), ac=ts_ac_power()
        func percent(_ x:Int32)->Int? { (0...100).contains(x) ? Int(x):nil }
        return Snapshot(date:Date(),cpuUsage:usage,sensors:sensors,fans:smc.fans(),speedLimit:percent(p.speed),schedulerLimit:percent(p.scheduler),availableCPUs:p.available>=0 ? Int(p.available):nil,totalCPUs:ProcessInfo.processInfo.processorCount,thermalState:ProcessInfo.processInfo.thermalState.rawValue,thermalWarning:p.warning>=0 ? Int(p.warning):nil,turbo:turbo,acPower:ac<0 ? nil:ac==1,lowPower:Self.lowPowerModeEnabled,smcAvailable:smc.available,memoryPressure:MemoryPressure(rawValue:Int(ts_memory_pressure())),additionalSensors:additional)
    }
    public func refreshTurbo() { lock.lock();defer { lock.unlock() };ticks=0 }
}
