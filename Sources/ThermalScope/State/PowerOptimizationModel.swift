import Foundation
import SwiftUI
import ThermalCore

@MainActor final class PowerOptimizationModel:ObservableObject {
    @Published private(set) var configuration=PowerConfiguration()
    @Published private(set) var blockers:[SleepBlocker]=[]
    @Published private(set) var sleepKnown=false
    @Published private(set) var source:PowerSource?
    @Published private(set) var turboDisabled:Bool?
    @Published private(set) var reading=false
    @Published private(set) var busy=false
    @Published private(set) var status=""
    @Published private(set) var failed=false
    @Published private(set) var environmentError=""
    @Published private(set) var backup:PowerBackup?
    @Published var lowPower=false
    @Published var scope:PowerScope = .current
    @Published var displaySleep=false
    @Published var idleSleep=false
    @Published var disableTurbo=false
    @Published private(set) var before:OptimizationSummary?
    @Published private(set) var after:OptimizationSummary?
    @Published private(set) var observationSeconds=0
    @Published private(set) var collecting=false
    var perform:((ControlRequest,@escaping(Result<ControlReply,Error>)->Void)->Void)?
    private var metrics:[OptimizationMetric]=[]
    private var appliedAt:Date?
    private var lastEffectUpdate=Date.distantPast
    private var lastBatterySample:Date?
    private let queue=DispatchQueue(label:"local.thermalscope.power-observation",qos:.utility)
    private var timer:DispatchSourceTimer?
    init() {
        if let data=UserDefaults.standard.data(forKey:"powerOptimizationBackup"),let saved=try? JSONDecoder().decode(PowerBackup.self,from:data),(try? saved.validate()) != nil {backup=saved}
        let timer=DispatchSource.makeTimerSource(queue:.main)
        timer.schedule(deadline:.now(),repeating:30,leeway:.seconds(2))
        timer.setEventHandler { [weak self] in self?.refresh() }
        self.timer=timer;timer.resume()
    }
    var plan:PowerOptimizationPlan? {
        source.map {PowerOptimizationPlan(source:$0,scope:scope,lowPower:lowPower,displayMinutes:displaySleep ? 5:nil,idleMinutes:idleSleep ? 15:nil,disableTurbo:disableTurbo,expected:configuration)}
    }
    var edits:[PowerEdit] {plan?.edits(in:configuration) ?? []}
    var hasSelection:Bool {lowPower || displaySleep || idleSleep || disableTurbo}
    var hasChanges:Bool {!edits.isEmpty || (disableTurbo && turboDisabled==false)}
    var planIssue:String? {
        guard !reading,let plan else{return nil}
        do {try plan.requireReadable(configuration);return nil}
        catch {return error.localizedDescription}
    }
    var canApply:Bool {
        guard !busy,!reading,backup==nil,let plan,(try? plan.requireReadable(configuration)) != nil,hasChanges else{return false}
        if disableTurbo && turboDisabled==nil {return false}
        return !idleSleep || (sleepKnown && blockers.isEmpty)
    }
    func refresh() {
        guard !reading else{return};reading=true
        queue.async { [weak self] in
            let config=Result {try NativePowerSettings.read()}
            let assertions=Result {try SleepBlocker.read()}
            DispatchQueue.main.async {
                guard let self else{return};self.reading=false
                switch config {
                case .success(let next):if self.configuration != next {self.configuration=next};self.environmentError=""
                case .failure(let error):self.configuration=PowerConfiguration();self.environmentError=error.localizedDescription
                }
                switch assertions {
                case .success(let next):if self.blockers != next {self.blockers=next};self.sleepKnown=true
                case .failure:self.blockers=[];self.sleepKnown=false
                }
            }
        }
    }
    func record(_ sample:Snapshot,telemetry:SystemTelemetry?) {
        let nextSource=sample.acPower.map{$0 ? PowerSource.ac:.battery}
        if source != nextSource {source=nextSource;refresh()}
        let nextTurbo:Bool?=sample.turbo == .disabledDriverLoaded ? true:(sample.turbo == .driverNotLoaded ? false:nil)
        if turboDisabled != nextTurbo {turboDisabled=nextTurbo}
        var watts:Double?
        if nextSource == .battery,let telemetry,telemetry.charging==false,telemetry.date != lastBatterySample,
           abs(sample.date.timeIntervalSince(telemetry.date))<10,let value=telemetry.batteryWatts,value<0 {
            watts = -value;lastBatterySample=telemetry.date
        }
        metrics.append(OptimizationMetric(date:sample.date,cpu:sample.cpuUsage,temperature:sample.cpuTemperature,dischargeWatts:watts,source:nextSource))
        metrics.removeAll{$0.date<sample.date.addingTimeInterval(-180)}
        guard let appliedAt,collecting,sample.date.timeIntervalSince(lastEffectUpdate)>=5 else{return}
        lastEffectUpdate=sample.date
        let from=appliedAt.addingTimeInterval(10),until=appliedAt.addingTimeInterval(70)
        observationSeconds=max(0,min(60,Int(sample.date.timeIntervalSince(from))))
        after=OptimizationSummary(metrics.filter{$0.date>=from && $0.date<=until})
        if sample.date>=until {collecting=false}
    }
    func apply() {
        guard canApply,let plan,let perform else{return}
        busy=true;failed=false;status="正在应用所选措施…"
        perform(ControlRequest("power-optimize",powerPlan:plan)) { [weak self] result in
            guard let self else{return};self.busy=false
            switch result {
            case .success(let reply):
                guard reply.ok,let outcome=reply.power else{self.failed=true;self.status=reply.message;self.refresh();return}
                self.backup=outcome.backup;self.saveBackup();self.status=reply.message
                if outcome.changed {self.before=OptimizationSummary.baseline(self.metrics,before:outcome.startedAt);self.after=nil;self.appliedAt=Date();self.observationSeconds=0;self.collecting=true}
            case .failure(let error):self.failed=true;self.status=error.localizedDescription
            }
            self.refresh()
        }
    }
    func restore() {
        guard !busy,let backup,let perform else{return}
        busy=true;failed=false;status="正在恢复原设置…";collecting=false;appliedAt=nil
        perform(ControlRequest("power-restore",powerBackup:backup)) { [weak self] result in
            guard let self else{return};self.busy=false
            switch result {
            case .success(let reply):
                guard reply.ok,reply.power != nil else{self.failed=true;self.status=reply.message;self.refresh();return}
                self.backup=nil;self.saveBackup();self.status=reply.message
            case .failure(let error):self.failed=true;self.status=error.localizedDescription
            }
            self.refresh()
        }
    }
    private func saveBackup() {
        if let backup,let data=try? JSONEncoder().encode(backup) {UserDefaults.standard.set(data,forKey:"powerOptimizationBackup")}
        else {UserDefaults.standard.removeObject(forKey:"powerOptimizationBackup")}
    }
    func shutdown(){timer?.cancel()}
}
