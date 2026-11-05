import Foundation
import ThermalCore

extension AppModel {
    @discardableResult func startFanStopTimer(minutes:Int)->Bool {
        guard !busy,(coolingToken != nil && sessionCurve != nil || fanStopTimer != nil) else{return false}
        do {
            fanStopTimer=try FanStopTimer(minutes:minutes)
            scheduleFanStopTimer()
            reapplyTimedFanCurve()
            return true
        }catch {report(error.localizedDescription,error:true);return false}
    }
    func clearFanStopTimer() {
        fanStopWork?.cancel();fanStopWork=nil;fanStopTimer=nil
    }
    func cancelFanStopTimer() {
        guard !busy,fanStopTimer != nil else{return}
        clearFanStopTimer();reapplyTimedFanCurve()
    }
    private func reapplyTimedFanCurve() {
        guard let curve=sessionCurve,coolingToken != nil else{return}
        let selection:FanModeSelection=activeFanSceneID.map{.scene($0)} ?? fanScenes.selection
        let previous=fanAutomationApplying
        fanAutomationApplying=fanAutomation.enabled
        defer {fanAutomationApplying=previous}
        applyFanCurve(curve,name:activeFanScene?.name ?? controlName,selection:selection)
    }
    func scheduleFanStopTimer() {
        fanStopWork?.cancel()
        guard let timer=fanStopTimer else{return}
        let work=DispatchWorkItem { [weak self] in MainActor.assumeIsolated {self?.expireFanStopTimerIfNeeded()} }
        fanStopWork=work
        DispatchQueue.main.asyncAfter(deadline:.now()+max(0.1,timer.remaining()),execute:work)
    }
    func expireFanStopTimerIfNeeded() {
        guard let timer=fanStopTimer,!fanSuspending else{return}
        guard timer.remaining()<=0 else {scheduleFanStopTimer();return}
        guard !busy else {
            let work=DispatchWorkItem { [weak self] in MainActor.assumeIsolated {self?.expireFanStopTimerIfNeeded()} }
            fanStopWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.25,execute:work);return
        }
        let previous=fanAutomationApplying
        fanAutomationApplying=false
        defer {fanAutomationApplying=previous}
        clearFanStopTimer();restoreAuto()
    }
    func resumeFanStopTimerAfterWake() {
        if let timer=fanStopTimer,timer.remaining()<=0 {
            clearFanStopTimer();pauseFanAutomationForManualSelection()
            fanScenes.selection = .strategy(.system)
            fanAutomation.manualSelection = .strategy(.system)
        } else {scheduleFanStopTimer()}
    }
}
