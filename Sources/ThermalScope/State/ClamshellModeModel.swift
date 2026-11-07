import Foundation
import ThermalCore

enum ClamshellActivation:String,CaseIterable {
    case manual,whenPowered
    var title:String {self == .manual ? "仅本次开启":"接通电源时自动开启"}
}

@MainActor final class ClamshellModeModel:ObservableObject {
    @Published private(set) var environment:ClamshellEnvironment?
    @Published private(set) var status=ClamshellStatus()
    @Published private(set) var changing=false
    @Published private(set) var activation:ClamshellActivation
    @Published private(set) var enabled=false
    @Published private(set) var automaticIssue:String?
    private let defaults:UserDefaults?
    private let readEnvironment:()throws->ClamshellEnvironment
    private var attempted=false
    private var stopAttempted=false
    private var shuttingDown=false
    private var powerObservation:ClamshellPowerObservation?
    /// Other hardware controls share one authorization channel; defer until it is free.
    var canPerform:()->Bool = {true}
    var perform:((ControlRequest,@escaping(Result<ControlReply,Error>)->Void)->Void)?
    init(defaults:UserDefaults?=nil,readEnvironment:@escaping()throws->ClamshellEnvironment = NativeClamshellPower.readEnvironment) {
        self.defaults=defaults;self.readEnvironment=readEnvironment
        // The single switch defaults to AC automation. Keep a different mode
        // only when it was explicitly chosen from the new secondary menu.
        activation=ClamshellActivation(rawValue:defaults?.string(forKey:"clamshellActivationChoice") ?? "") ?? .whenPowered
        // Only an explicitly enabled automatic rule survives relaunch. Manual
        // sessions still start off, and preferences never imply an active lease.
        enabled=activation == .whenPowered && defaults?.bool(forKey:"clamshellAutomaticEnabled")==true
        refresh()
    }
    var isEnabled:Bool {enabled || status.active}
    var canRetryAutomatic:Bool {enabled && activation == .whenPowered && attempted && !status.active && canEnable}
    var canSetEnabled:Bool {isEnabled || (activation == .whenPowered ? canArmAutomatic:canEnable)}
    var canArmAutomatic:Bool {AppDistribution.hardwareControlAvailable && environment?.portable==true}
    var canEnable:Bool {
        AppDistribution.hardwareControlAvailable && environment?.unavailableReason==nil && environment?.sleepDisabled==false && environment != nil
    }
    var detail:String {
        if changing {return "正在确认合盖运行状态…"}
        if let automaticIssue,enabled,activation == .whenPowered {return automaticIssue}
        if status.active || status.failed {return status.message}
        if enabled,activation == .whenPowered,environment==nil {return "无法确认电源状态，自动开启已暂停"}
        if enabled,activation == .whenPowered,environment?.portable==true,environment?.acPower != true {return "自动规则已开启，等待接通电源"}
        if let reason=environment?.unavailableReason {return reason}
        if environment?.sleepDisabled==true {return "其他程序已禁止系统休眠，请先关闭其防休眠功能"}
        if enabled,activation == .whenPowered {return "自动开启已暂停，可重试或重新接通电源"}
        return status.message
    }
    var explanation:String {
        activation == .whenPowered ? "自动规则会保留；ShowMac 运行时满足条件便开启，拔电或退出后恢复休眠。":"仅接电时生效；拔电、关闭开关或退出 ShowMac 后恢复休眠。请保持通风，放入包前关闭。"
    }
    var summary:String {
        if changing || status.failed || automaticIssue != nil || !canArmAutomatic {return detail}
        if activation == .manual {return status.active ? detail:"仅本次手动运行，退出后关闭"}
        if enabled {return status.active ? "接电运行中，拔电自动停止":detail}
        return "开启后接电运行，拔电自动停止"
    }
    private func persist() {
        defaults?.set(activation.rawValue,forKey:"clamshellActivationChoice")
        defaults?.set(activation == .whenPowered && enabled,forKey:"clamshellAutomaticEnabled")
    }
    func setActivation(_ value:ClamshellActivation) {
        guard value != activation,!changing,!shuttingDown else{return}
        activation=value;attempted=false;stopAttempted=false;automaticIssue=nil
        if value == .manual {enabled=status.active}
        persist();refresh()
    }
    func refresh() {
        let next=try? readEnvironment()
        if environment != next {environment=next}
        // Even if the helper disconnected, never keep a stale On state after
        // the watchdog has restored normal sleep.
        if status.active,next?.sleepDisabled==false {
            status=ClamshellStatus()
            if activation == .manual {enabled=false}
            else if enabled,!changing,next?.acPower==true,next?.thermalCritical==false {
                automaticIssue="合盖运行已中断，可重试或重新接通电源"
            }
        }
        reconcile()
    }
    func receive(_ value:ClamshellStatus?) {
        if let value {
            if status.active,!value.active,enabled,activation == .whenPowered,!changing {
                automaticIssue="合盖运行已中断，可重试或重新接通电源"
            }
            if status != value {status=value}
            if !value.active {stopAttempted=false}
            if activation == .manual,!changing {enabled=value.active}
            if value.failed,activation == .whenPowered,enabled {automaticIssue=value.message}
        }
        refresh()
    }
    func setEnabled(_ value:Bool) {
        guard !shuttingDown,(!value || canSetEnabled) else{return}
        if value==enabled,value || !status.active {return}
        enabled=value;attempted=false;stopAttempted=false;automaticIssue=nil
        if !value,!status.active,!changing {status=ClamshellStatus()}
        persist();refresh()
    }
    func retryAutomatic() {
        guard enabled,activation == .whenPowered,!changing,!shuttingDown else{return}
        attempted=false;automaticIssue=nil;refresh()
    }
    func startObservingPower() {
        guard !shuttingDown,powerObservation==nil else{return}
        powerObservation=ClamshellPowerObservation { [weak self] in self?.refresh() }
    }
    func shutdown(){shuttingDown=true;powerObservation?.invalidate();powerObservation=nil}
    private func reconcile() {
        guard !shuttingDown else{return}
        let conditionMatches=environment?.portable==true && environment?.acPower==true && environment?.thermalCritical==false
        // A new power/eligibility interval permits one new attempt. A refused
        // authorization or interrupted helper never retries every sampling tick.
        if activation == .whenPowered,(environment?.acPower==false || environment?.thermalCritical==true) {
            attempted=false;automaticIssue=nil
            if !status.active,!changing,status.failed {status=ClamshellStatus()}
        }
        guard !changing,canPerform(),perform != nil else{return}
        if !enabled {
            if status.active,!stopAttempted {stopAttempted=true;request(false)}
            return
        }
        if activation == .whenPowered,!conditionMatches {
            if status.active,!stopAttempted {stopAttempted=true;request(false)}
            return
        }
        guard !status.active,canEnable else{return}
        if activation == .whenPowered {
            guard !attempted else{return}
            attempted=true
        }
        request(true)
    }
    private func request(_ enabled:Bool) {
        guard let perform else{return}
        if enabled {stopAttempted=false}
        changing=true
        perform(ControlRequest(enabled ? "clamshell-start":"clamshell-stop")) { [weak self] result in
            guard let self else{return}
            switch result {
            case .success(let reply):
                if let value=reply.clamshell {self.receive(value)}
                if !reply.ok || reply.clamshell?.active != enabled {
                    self.status=ClamshellStatus(active:self.status.active,message:reply.message,failed:true)
                }
            case .failure(let error):self.status=ClamshellStatus(active:self.status.active,message:error.localizedDescription,failed:true)
            }
            if self.status.failed {
                if self.activation == .whenPowered,self.enabled {self.automaticIssue=self.status.message}
                else if enabled {self.enabled=false}
            }
            self.changing=false
            self.refresh()
        }
    }
}
