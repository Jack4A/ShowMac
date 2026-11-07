import Foundation
import Darwin
import CSMC
import ThermalCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message+"\n").utf8)); exit(1)
}
func cooling(_ args: [String],duration:Double=300) throws {
    guard args.count==5, let pid=Int32(args[2]),pid>1,let uid=UInt32(args[3]),uid>0,
          let token=UUID(uuidString:args[4]),ts_owner_alive(pid,uid)==1 else {
        throw ScopeError.message("无效的散热会话参数或发起程序已经退出")
    }
    let stopPath="/tmp/thermalscope-stop-"+token.uuidString
    ts_install_stop_handlers()
    try CoolingLease.run(hardware:SMC(),duration:duration,now:{ts_continuous_seconds()},
        isCancelled:{ts_should_stop() != 0 || ts_owner_alive(pid,uid) != 1 || access(stopPath,F_OK)==0},
        wait:{usleep(1_000_000)})
    print("散热会话结束，已确认风扇恢复系统自动。")
}
func setTurbo(disable:Bool) throws {
    #if arch(arm64)
    throw ScopeError.message("Intel 睿频不适用于 Apple Silicon")
    #else
    if ts_turbo_driver_state()==(disable ? 1:0) { return }
    var result=try ProcessRunner.run("/usr/bin/kmutil",[disable ? "load":"unload","-b","com.rugarciap.DisableTurboBoost"],timeout:90)
    if disable && result.status != 0 {
        // Fixed vendor locations only; retain all macOS approval and signature checks.
        let candidates=["/Applications/Turbo Boost Switcher Pro.app/Contents/Resources/DisableTurboBoost.64bits.kext","/Applications/Turbo Boost Switcher.app/Contents/Resources/DisableTurboBoost.64bits.kext"]
        if let path=candidates.first(where:{Bundle(path:$0)?.bundleIdentifier=="com.rugarciap.DisableTurboBoost"}) {
            result=try ProcessRunner.run("/usr/bin/kmutil",["load","-p",path],timeout:90)
        }
    }
    guard result.status==0,ts_turbo_driver_state()==(disable ? 1:0) else {
        throw ScopeError.message("睿频操作未确认。需要已安装且获得系统批准的驱动。\n"+result.output)
    }
    #endif
}
func profile(_ args:[String]) throws {
    guard args.count==7,let pid=Int32(args[3]),pid>1,let uid=UInt32(args[4]),uid>0,
          let token=UUID(uuidString:args[5]),ts_owner_alive(pid,uid)==1,
          let mode=ThermalProfile.allCases.first(where:{$0.command==args[2]}),mode != .automatic else {
        throw ScopeError.message("无效的模式会话参数")
    }
    let curve:FanCurve
    if mode == .custom {
        guard args[6].utf8.count<=4096,let data=Data(base64Encoded:args[6]) else { throw ScopeError.message("曲线数据无效") }
        curve=try JSONDecoder().decode(FanCurve.self,from:data)
    } else { curve=mode.curve }
    try curve.validate()
    let stopPath="/tmp/thermalscope-stop-"+token.uuidString
    ts_install_stop_handlers()
    let cancelled={ts_should_stop() != 0 || ts_owner_alive(pid,uid) != 1 || access(stopPath,F_OK)==0}
    if cancelled() { return }
    let hardware=SMC(),sampler=HardwareSampler()
    let fans=hardware.fans(),initial=sampler.sample()
    guard !fans.isEmpty,fans.allSatisfy({$0.controllable && $0.manual==false}),initial.cpuTemperature != nil,curve.sensor.temperature(in:initial) != nil else {
        throw ScopeError.message("风扇必须处于系统自动，且控制温度传感器可读取；请先退出其他调控软件。")
    }
    let previousTurbo=ts_turbo_driver_state()
    if mode != .custom { try setTurbo(disable:mode.disablesTurbo) }
    if cancelled() {
        if mode != .custom && previousTurbo>=0 { try setTurbo(disable:previousTurbo==1) }
        return
    }
    do {
        try CurveLease.run(hardware:hardware,curve:curve,sample:{sampler.sample()},now:{ts_continuous_seconds()},isCancelled:cancelled,wait:{usleep(2_000_000)})
    } catch {
        if mode != .custom && previousTurbo>=0 {
            do { try setTurbo(disable:previousTurbo==1) }
            catch let restoreError { throw ScopeError.message("\(error.localizedDescription)；睿频回退失败：\(restoreError.localizedDescription)") }
        }
        throw error
    }
    print("模式会话结束，风扇已恢复系统自动；保留睿频选择。")
}

let args=CommandLine.arguments
#if arch(arm64)
let command=args.dropFirst().first ?? ""
let fanCommands=["probe","fan-probe","serve","cooling","test-fans","auto","clamshell-guard"]
if !fanCommands.contains(command) && !(command=="profile" && args.count>2 && args[2]=="custom") {
    fail("Apple Silicon 当前仅支持独立风扇控制")
}
#endif
if args.count==2 && args[1]=="fan-probe" {
    let smc=SMC()
    let keys=["FNum","F0Md","F0md","F0Tg","F0Ac","F0Mn","F0Mx","Ftst","FS! "]
    let values=Dictionary(uniqueKeysWithValues:keys.compactMap {key in smc.number(key).map {(key,$0)}})
    do {let data=try JSONEncoder().encode(values);FileHandle.standardOutput.write(data);print()} catch {fail(error.localizedDescription)}
    exit(0)
}
if args.count==5 && args[1]=="clamshell-guard" {
    do {try runClamshellGuard(args)} catch {
        var reply=ControlReply(ok:false,message:error.localizedDescription)
        reply.clamshell=ClamshellStatus(message:error.localizedDescription,failed:true)
        try? ControlChannel(fd:STDOUT_FILENO).send(reply)
    }
    exit(0)
}
if args.count==4 && args[1]=="serve" {
    do { try runControlSession(args) } catch { fail(error.localizedDescription) }
    exit(0)
}
if args.count==2 && args[1]=="probe" {
    let sampler=HardwareSampler()
    _=sampler.sample(); usleep(250_000)
    let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
    do { FileHandle.standardOutput.write(try encoder.encode(sampler.sample())); print() }
    catch { fail(error.localizedDescription) }
    exit(0)
}
guard geteuid()==0 else { fail("硬件控制需要管理员授权；监测不需要管理员权限。") }
do {
    switch args.dropFirst().first {
    case "cooling": try cooling(args)
    case "test-fans": try cooling(args,duration:5)
    case "profile": try profile(args)
    case "auto":
        guard args.count==2 else { throw ScopeError.message("无效参数") }
        let smc=SMC(),fans=smc.fans()
        guard !fans.isEmpty else { throw ScopeError.message("没有可读取的风扇") }
        try CoolingLease.restoreAuto(smc,ids:fans.map(\.id)); print("风扇已恢复系统自动。")
    case "turbo-disable", "turbo-enable":
        guard args.count==2 else { throw ScopeError.message("无效参数") }
        let disable=args[1]=="turbo-disable"
        try setTurbo(disable:disable)
        print(disable ? "已确认禁用睿频驱动加载。":"已确认禁用睿频驱动卸载。")
    default: throw ScopeError.message("允许的命令：probe、cooling、profile、auto、turbo-disable、turbo-enable")
    }
} catch { fail(error.localizedDescription) }
