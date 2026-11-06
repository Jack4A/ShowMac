import AppKit
import SwiftUI
import ThermalCore

@MainActor final class TokenUsageStore:ObservableObject {
    @Published private(set) var snapshot=TokenScanSnapshot()
    @Published private(set) var hasScanned=false
    @Published private(set) var isScanning=false
    @Published var enabled:Bool {didSet{guard persistent else{return};defaults.set(enabled,forKey:"tokenUsageEnabled");generation+=1;if enabled {refresh()}}}
    private let defaults:UserDefaults
    private let persistent:Bool
    private let queue=DispatchQueue(label:"local.showmac.token-usage",qos:.utility)
    private let worker=Worker()
    private var timer:DispatchSourceTimer?
    private var generation=0
    private var stopped=false
    private var custom:[String:String]
    private struct Query:Hashable {let start:Date;let end:Date;let provider:TokenProvider?;let period:ElectricityPeriod}
    private var reports:[Query:TokenUsageReport]=[:]
    private final class Worker:@unchecked Sendable {
        var scanner:TokenLogScanner?
        func scan(roots:[TokenLogRoot],cache:URL?)->TokenScanSnapshot {
            if scanner==nil {scanner=TokenLogScanner(cacheURL:cache)}
            return scanner!.scan(roots:roots)
        }
    }
    init(persistent:Bool=true,defaults:UserDefaults = .standard) {
        self.defaults=defaults
        self.persistent=persistent && !CommandLine.arguments.contains{$0.hasSuffix("-check") || $0=="--ui-check"}
        enabled=(defaults.object(forKey:"tokenUsageEnabled") as? Bool) ?? true
        custom=(defaults.dictionary(forKey:"tokenUsageLocations") as? [String:String]) ?? [:]
        if self.persistent {
            let timer=DispatchSource.makeTimerSource(queue:.main)
            timer.schedule(deadline:.now()+1,repeating:60)
            timer.setEventHandler{[weak self] in MainActor.assumeIsolated{self?.refresh()}}
            self.timer=timer;timer.resume()
        }
    }
    func report(in range:DateInterval,provider:TokenProvider?=nil,period:ElectricityPeriod = .day)->TokenUsageReport {
        let query=Query(start:range.start,end:range.end,provider:provider,period:period)
        if let report=reports[query] {return report}
        let result=TokenUsageReport(events:snapshot.events,in:range,provider:provider,intervals:period.chartIntervals(containing:range.start))
        if reports.count>=8 {reports.removeAll(keepingCapacity:true)};reports[query]=result;return result
    }
    var firstDate:Date? {snapshot.events.first?.date}
    var roots:[TokenLogRoot] {
        TokenProvider.allCases.flatMap{provider->[TokenLogRoot] in
            if let path=custom[provider.rawValue] {return [TokenLogRoot(provider:provider,url:URL(fileURLWithPath:path,isDirectory:true))]}
            return TokenLogScanner.defaultRoots().filter{$0.provider==provider}
        }
    }
    func location(for provider:TokenProvider)->String {
        if let value=custom[provider.rawValue] {return value.replacingOccurrences(of:FileManager.default.homeDirectoryForCurrentUser.path,with:"~")}
        return provider == .codex ? "~/.codex/sessions + archived_sessions":"~/.claude/projects + ~/.config/claude/projects"
    }
    func chooseDirectory(for provider:TokenProvider) {
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.allowsMultipleSelection=false
        panel.message=L("选择保存该工具 JSONL 会话日志的文件夹。")
        panel.directoryURL=roots.first{$0.provider==provider}?.url
        guard panel.runModal() == .OK,let url=panel.url else{return}
        custom[provider.rawValue]=url.path;saveLocations()
    }
    func resetDirectories(){custom=[:];saveLocations()}
    private func saveLocations(){if persistent {defaults.set(custom,forKey:"tokenUsageLocations")};generation+=1;refresh()}
    func refresh() {
        guard persistent,enabled,!stopped,!isScanning else{return}
        isScanning=true
        let current=generation,roots=self.roots
        let cache=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("ShowMac/token-usage-cache.json")
        queue.async{[weak self,worker] in
            let result=worker.scan(roots:roots,cache:cache)
            DispatchQueue.main.async {
                guard let self,!self.stopped else{return}
                self.isScanning=false
                guard self.enabled,self.generation==current else{self.refresh();return}
                self.reports.removeAll(keepingCapacity:true);self.snapshot=result;self.hasScanned=true
            }
        }
    }
    func setPreview(_ events:[TokenUsageEvent]){guard !persistent else{return};reports.removeAll();snapshot.events=events;snapshot.fileCount=2;hasScanned=true}
    func shutdown(){stopped=true;timer?.cancel();timer=nil}
}
