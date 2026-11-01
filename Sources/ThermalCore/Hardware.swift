import Foundation
import CSMC

public final class SMC {
    private var connection: UInt32=0
    public init() { connection=ts_smc_open() }
    deinit { ts_smc_close(connection) }
    public var available: Bool { connection != 0 }
    public func reopen() { ts_smc_close(connection); connection=ts_smc_open() }
    public func temperatureKeys()->[String] {
        guard let count=number("#KEY"),count>0,count<=10000 else { return [] }
        var result:[String]=[]
        for index in 0..<Int(count) {
            var bytes=[CChar](repeating:0,count:5)
            guard ts_smc_key_at_index(connection,UInt32(index),&bytes)==0,bytes[0]==84 else { continue }
            let key=String(cString:bytes)
            guard let v=try? raw(key),v.type==0x73703738 || v.type==0x666c7420 else { continue }
            if number(key).map({$0>0 && $0<130})==true { result.append(key) }
        }
        return result.sorted()
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
        return (0..<Int(count)).map { id in
            let localMode=number("F\(id)Md")
            let manual: Bool?=SMCVerification.manualState(local:localMode,flags:globalMode,id:id)
            let maxRPM=number("F\(id)Mx")
            return FanReading(id:id,rpm:number("F\(id)Ac"),minimum:number("F\(id)Mn"),maximum:maxRPM,manual:manual,
                controllable:manual != nil && number("F\(id)Tg") != nil && maxRPM.map { $0>0 && $0<=12000 } == true)
        }
    }
    public func setManual(_ id: Int, _ manual: Bool) throws {
        if number("F\(id)Md") != nil { try write("F\(id)Md",number:manual ? 1:0) }
        else if let flags=number("FS! ") {
            let mask=1<<id
            let changed=manual ? Int(flags)|mask : Int(flags)&(~mask)
            try write("FS! ",number:Double(changed))
        } else { throw ScopeError.message("风扇 \(id+1) 没有可识别的模式接口") }
    }
}

/// Used only on the sampler queue. No subprocesses or polling of `top`.
public final class HardwareSampler: @unchecked Sendable {
    private let lock=NSLock()
    private let smc=SMC()
    private var previous: CPUCounters?
    private var knownSensors: [(String,String)]=[]
    private var ticks=0
    private var turbo: TurboState = .unknown
    public init() {}
    public func reset() { lock.lock();defer { lock.unlock() };previous=nil; smc.reopen(); knownSensors=[] }
    public func sample() -> Snapshot {
        lock.lock();defer { lock.unlock() }
        var counters=TSTicks()
        var usage: Double?
        if ts_cpu_ticks(&counters)==0 {
            let now=CPUCounters(user:UInt32(truncatingIfNeeded:counters.user),system:UInt32(truncatingIfNeeded:counters.system),idle:UInt32(truncatingIfNeeded:counters.idle),nice:UInt32(truncatingIfNeeded:counters.nice))
            if let old=previous { usage=now.usage(since:old) }
            previous=now
        }
        if knownSensors.isEmpty {
            var candidates=[("TC0F","CPU die"),("TC0D","CPU diode"),("TC0P","CPU proximity"),("TC0E","CPU PECI"),("TC0H","CPU heatsink"),("TG0D","GPU diode"),("TG0P","GPU proximity")]
            candidates += (0..<10).map { ("TC\($0)C","CPU core sensor \($0)") }
            let named=Set(candidates.map(\.0))
            candidates += smc.temperatureKeys().filter { !named.contains($0) }.map { ($0,SensorCategory.category(for:$0).rawValue+" · "+$0) }
            knownSensors=candidates.filter { smc.number($0.0).map { $0>0 && $0<130 } == true }
        }
        let sensors=knownSensors.compactMap { (key,label) -> SensorReading? in
            guard let value=smc.number(key),value>0,value<130 else { return nil }
            return SensorReading(key:key,label:label,celsius:value)
        }
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
        return Snapshot(date:Date(),cpuUsage:usage,sensors:sensors,fans:smc.fans(),speedLimit:percent(p.speed),schedulerLimit:percent(p.scheduler),availableCPUs:p.available>=0 ? Int(p.available):nil,totalCPUs:ProcessInfo.processInfo.processorCount,thermalState:ProcessInfo.processInfo.thermalState.rawValue,thermalWarning:p.warning>=0 ? Int(p.warning):nil,turbo:turbo,acPower:ac<0 ? nil:ac==1,lowPower:ProcessInfo.processInfo.isLowPowerModeEnabled,smcAvailable:smc.available,memoryPressure:MemoryPressure(rawValue:Int(ts_memory_pressure())))
    }
    public func refreshTurbo() { lock.lock();defer { lock.unlock() };ticks=0 }
}
