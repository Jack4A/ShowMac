import Foundation
import Darwin
import CSMC
import ThermalCore

final class SessionControl {
    private let condition=NSCondition()
    private var running=false
    private var cancelled=false
    private var applied=false
    private var failure:String?
    private var session:String?
    private var profile:String?
    private var label:String?
    private var progress:FanControlProgress?
    // Keep handoff ownership after a failed restore so explicit Auto can retry it.
    private let fanHardware=SMC()
    private let owner:Int32
    private let uid:UInt32
    init(owner:Int32,uid:UInt32) {self.owner=owner;self.uid=uid}
    func shouldStop()->Bool {
        condition.lock();let stop=cancelled;condition.unlock()
        return stop || ts_should_stop() != 0 || ts_owner_alive(owner,uid) != 1
    }
    func status()->ControlReply {
        condition.lock();defer{condition.unlock()}
        let status:FanSessionStatus?
        if running,applied,let progress {
            status=FanSessionStatus(remainingSeconds:max(0,progress.deadline-ts_continuous_seconds()),targets:progress.targets,protectionActive:progress.protectionActive)
        } else {status=nil}
        return ControlReply(ok:failure==nil,message:failure ?? (running ? "控制已确认生效":"风扇由系统管理"),session:session,profile:profile,label:label,fanStatus:status)
    }
    func stop(ignorePreviousFailure:Bool=false) throws {
        condition.lock();defer{condition.unlock()}
        cancelled=true
        let limit=Date().addingTimeInterval(12)
        while running {
            guard condition.wait(until:limit) else {throw ScopeError.message("等待风扇恢复自动超时，未开始下一操作")}
        }
        if !ignorePreviousFailure,let failure, failure.contains("恢复自动风扇失败") {throw ScopeError.message(failure)}
    }
    func start(curve:FanCurve,mode:String,name:String,duration:Double) throws {
        try curve.validate();try stop()
        condition.lock()
        cancelled=false;running=true;applied=false;failure=nil;progress=nil
        session=UUID().uuidString;profile=mode;label=name
        condition.unlock()
        DispatchQueue.global(qos:.utility).async { [self] in
            var errorText:String?
            do {
                let hardware=self.fanHardware,sampler=HardwareSampler()
                try CurveLease.run(hardware:hardware,curve:curve,duration:duration,
                    sample:{sampler.sample()},now:{ts_continuous_seconds()},isCancelled:{self.shouldStop()},
                    wait:{for _ in 0..<20 {if self.shouldStop(){break};usleep(100000)}},onUpdate:{progress in
                        self.condition.lock();self.progress=progress;self.condition.unlock()
                    },onApplied:{
                        self.condition.lock();self.applied=true;self.condition.broadcast();self.condition.unlock()
                    })
            } catch {errorText=error.localizedDescription}
            condition.lock();failure=errorText;running=false;session=nil;profile=nil;label=nil;progress=nil
            condition.broadcast();condition.unlock()
        }
        condition.lock();defer{condition.unlock()}
        let limit=Date().addingTimeInterval(12)
        while running && !applied {
            guard condition.wait(until:limit) else {cancelled=true;throw ScopeError.message("控制确认超时，已请求恢复系统自动")}
        }
        guard applied,failure==nil else {throw ScopeError.message(failure ?? "控制未生效")}
    }
    func handle(_ request:ControlRequest) throws ->ControlReply {
        #if arch(arm64)
        try FanControlPolicy.validate(request,appleSilicon:true)
        #else
        try FanControlPolicy.validate(request,appleSilicon:false)
        #endif
        switch request.command {
        case "hello","status":return status()
        case "power-optimize","power-restore":
            let hardware=SystemPowerAccess()
            let outcome:PowerOutcome
            if request.command=="power-optimize" {outcome=try PowerTransaction.apply(request.powerPlan!,using:hardware)}
            else {outcome=try PowerTransaction.restore(request.powerBackup!,using:hardware)}
            if request.powerPlan?.disableTurbo == true || request.powerBackup?.turboBefore != nil {
                condition.lock();if running {profile="custom";label="独立风扇策略"};condition.unlock()
            }
            var reply=status();reply.ok=true;reply.power=outcome
            reply.message=request.command=="power-optimize" ? (outcome.changed ? "优化设置已确认生效":"所选设置已满足"):(outcome.skipped>0 ? "恢复已结束；外部更改保留":"原设置已恢复")
            return reply
        case "shutdown":try stop();return status()
        case "auto":
            try stop(ignorePreviousFailure:true)
            let hardware=fanHardware,fans=hardware.fans()
            guard !fans.isEmpty else {throw ScopeError.message("没有可读取的风扇")}
            try CoolingLease.restoreAuto(hardware,ids:fans.map(\.id))
            condition.lock();failure=nil;condition.unlock();return status()
        case "turbo-disable","turbo-enable":
            try setTurbo(disable:request.command=="turbo-disable")
            // Independent Turbo adjustments keep the fan curve running, but stop
            // presenting the original combined policy as an unchanged preset.
            condition.lock()
            if running {profile="custom";label="独立风扇策略"}
            condition.unlock();return status()
        case "test-fans":
            try start(curve:.manual(percent:100),mode:"custom",name:"风扇验证",duration:5)
            return status()
        case "profile":
            guard let mode=ThermalProfile.allCases.first(where:{$0.command==request.profile}) else {throw ScopeError.message("无效模式")}
            try stop()
            let previous=ts_turbo_driver_state()
            if mode != .custom {try setTurbo(disable:mode.disablesTurbo)}
            do {
                try start(curve:mode == .custom ? request.curve!:mode.curve,
                          mode:mode.command,name:request.label ?? mode.rawValue,duration:request.duration ?? 1800)
            } catch {
                // A mode change is a transaction: do not leave half the preset applied.
                if mode != .custom,previous>=0 {
                    do {try setTurbo(disable:previous==1)}
                    catch let rollback {throw ScopeError.message("\(error.localizedDescription)；睿频回退失败：\(rollback.localizedDescription)")}
                }
                throw error
            }
            return status()
        default:throw ScopeError.message("未知控制命令")
        }
    }
}
func runControlSession(_ args:[String]) throws {
    guard geteuid()==0,args.count==4,let owner=Int32(args[2]),let uid=UInt32(args[3]),
          uid>0,getuid()==uid,ts_owner_alive(owner,uid)==1 else {throw ScopeError.message("原生授权会话身份验证失败")}
    signal(SIGPIPE,SIG_IGN);ts_install_stop_handlers()
    let controller=SessionControl(owner:owner,uid:uid)
    let input=ControlChannel(fd:STDIN_FILENO),output=ControlChannel(fd:STDOUT_FILENO)
    DispatchQueue.global(qos:.utility).async {
        while ts_owner_alive(owner,uid)==1 && ts_should_stop()==0 {usleep(200000)}
        try? controller.stop();exit(0)
    }
    defer{try? controller.stop()}
    while let data=try input.readLine(timeout:86400) {
        guard ts_owner_alive(owner,uid)==1 else {break}
        let reply:ControlReply
        var shutdown=false
        do {
            let request=try JSONDecoder().decode(ControlRequest.self,from:data)
            reply=try controller.handle(request);shutdown=request.command=="shutdown"
        } catch {reply=ControlReply(ok:false,message:error.localizedDescription)}
        try output.send(reply)
        if shutdown {break}
    }
}
