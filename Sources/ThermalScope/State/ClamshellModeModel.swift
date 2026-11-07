import Foundation
import ThermalCore

@MainActor final class ClamshellModeModel:ObservableObject {
    @Published private(set) var environment:ClamshellEnvironment?
    @Published private(set) var status=ClamshellStatus()
    @Published private(set) var changing=false
    private let readEnvironment:()throws->ClamshellEnvironment
    var perform:((ControlRequest,@escaping(Result<ControlReply,Error>)->Void)->Void)?
    init(readEnvironment:@escaping()throws->ClamshellEnvironment = NativeClamshellPower.readEnvironment) {self.readEnvironment=readEnvironment;refresh()}
    var canEnable:Bool {
        AppDistribution.hardwareControlAvailable && environment?.unavailableReason==nil && environment?.sleepDisabled==false && environment != nil
    }
    var detail:String {
        if changing {return "正在确认合盖运行状态…"}
        if status.active || status.failed {return status.message}
        if let reason=environment?.unavailableReason {return reason}
        if environment?.sleepDisabled==true {return "其他程序已禁止系统休眠，请先关闭其防休眠功能"}
        return status.message
    }
    func refresh() {
        let next=try? readEnvironment()
        if environment != next {environment=next}
        // Even if the helper disconnected, never keep a stale On state after
        // the watchdog has restored normal sleep.
        if status.active,next?.sleepDisabled==false {status=ClamshellStatus()}
    }
    func receive(_ value:ClamshellStatus?) {
        if let value,status != value {status=value}
        refresh()
    }
    func setEnabled(_ enabled:Bool) {
        guard !changing,enabled != status.active,(!enabled || canEnable),let perform else{return}
        changing=true
        perform(ControlRequest(enabled ? "clamshell-start":"clamshell-stop")) { [weak self] result in
            guard let self else{return}
            self.changing=false
            switch result {
            case .success(let reply):
                if reply.ok,let value=reply.clamshell {self.receive(value)}
                else {self.status=ClamshellStatus(active:self.status.active,message:reply.message,failed:true)}
            case .failure(let error):self.status=ClamshellStatus(active:self.status.active,message:error.localizedDescription,failed:true)
            }
            self.refresh()
        }
    }
}
