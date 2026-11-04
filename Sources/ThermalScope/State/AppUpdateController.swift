import AppKit
import Combine
import ThermalCore

enum AppUpdateState:Equatable {case idle,checking,current,available,failed}

@MainActor final class AppUpdateController:ObservableObject {
    @Published private(set) var state:AppUpdateState = .idle
    @Published private(set) var latestVersion:ReleaseVersion?
    @Published private(set) var lastCheckedAt:Date?
    @Published var automaticChecks:Bool {
        didSet {
            defaults?.set(automaticChecks,forKey:"automaticUpdateChecks")
            if automaticChecks {checkIfDue()}
            else if state == .checking {cancelCheck()}
        }
    }
    let installedVersion:ReleaseVersion?
    private let defaults:UserDefaults?
    private let fetcher:AppUpdateFetching
    private let now:()->Date
    private var lastAttemptAt:Date?
    private var timer:Timer?
    private var generation:UUID?
    private var pending=0
    private var candidates:[ReleaseVersion]=[]
    private var presentWhenFinished=false

    init(installedVersion:ReleaseVersion?=ReleaseVersion(AppInfo.version),
         defaults:UserDefaults?=CommandLine.arguments.contains("--ui-check") ? nil:UserDefaults.standard,
         fetcher:AppUpdateFetching?=nil,now:@escaping()->Date=Date.init) {
        self.installedVersion=installedVersion
        self.defaults=defaults
        self.fetcher=fetcher ?? AppUpdateFetcher();self.now=now
        automaticChecks=(self.defaults?.object(forKey:"automaticUpdateChecks") as? Bool) ?? true
        lastAttemptAt=self.defaults?.object(forKey:"updateLastAttempt") as? Date
        lastCheckedAt=self.defaults?.object(forKey:"updateLastSuccess") as? Date
        if let saved=self.defaults?.string(forKey:"updateLatestVersion"),let version=ReleaseVersion(saved) {
            latestVersion=version
            state=availableVersion == nil ? .current:.available
        }
    }
    var availableVersion:ReleaseVersion? {
        guard let installedVersion,let latestVersion,latestVersion>installedVersion else{return nil}
        return latestVersion
    }
    var statusText:String {
        if state == .checking {return L("正在检查更新…")}
        if let version=availableVersion {return String(format:L("发现新版本 %@"),version.description)}
        switch state {
        case .idle:return L("尚未检查更新")
        case .current:return L("未发现新版本")
        case .failed:return L("暂时无法检查更新，请稍后重试。")
        case .checking,.available:return L("正在检查更新…")
        }
    }
    func start() {
        guard timer==nil else{return}
        checkIfDue()
        timer=Timer.scheduledTimer(withTimeInterval:3600,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated{self?.checkIfDue()}
        }
    }
    func checkIfDue() {
        guard automaticChecks else{return}
        if let lastAttemptAt,now().timeIntervalSince(lastAttemptAt)<86400,now()>=lastAttemptAt{return}
        checkNow()
    }
    func checkNow(presentResult:Bool=false) {
        presentWhenFinished = presentWhenFinished || presentResult
        guard state != .checking else{return}
        guard installedVersion != nil else{
            state = .failed;presentWhenFinished=false
            if presentResult {showResult()};return
        }
        lastAttemptAt=now();defaults?.set(lastAttemptAt,forKey:"updateLastAttempt")
        state = .checking;candidates=[];pending=ReleaseMetadataSource.allCases.count
        let token=UUID();generation=token
        for source in ReleaseMetadataSource.allCases {
            fetcher.fetch(source) { [weak self] result in self?.receive(result,generation:token) }
        }
    }
    private func receive(_ result:Result<ReleaseVersion,Error>,generation token:UUID) {
        guard generation==token else{return}
        if case .success(let version)=result {candidates.append(version)}
        pending-=1
        guard pending==0 else{return}
        generation=nil
        if let newest=candidates.max() {
            latestVersion=newest;lastCheckedAt=now()
            defaults?.set(lastCheckedAt,forKey:"updateLastSuccess")
            defaults?.set(newest.description,forKey:"updateLatestVersion")
            state=availableVersion == nil ? .current:.available
        }else{state = .failed}
        let present=presentWhenFinished;presentWhenFinished=false
        if present {showResult()}
    }
    func showResult() {
        let alert=NSAlert();alert.alertStyle = .informational
        alert.messageText=statusText
        if let version=availableVersion {
            alert.informativeText=String(format:L("当前版本 %@，最新版本 %@。请选择下载来源，下载后替换应用即可。"),AppInfo.version,version.description)
            alert.addButton(withTitle:L("前往官网下载"))
            alert.addButton(withTitle:L("前往 GitHub 下载"))
            alert.addButton(withTitle:L("稍后"))
        }else {
            alert.informativeText=L("当前版本")+" "+AppInfo.versionLabel
            alert.addButton(withTitle:L("好"))
            if state == .failed {
                alert.addButton(withTitle:L("前往官网下载"))
                alert.addButton(withTitle:L("前往 GitHub 下载"))
            }
        }
        NSApp.activate(ignoringOtherApps:true)
        let response=alert.runModal()
        if availableVersion != nil {
            if response == .alertFirstButtonReturn {openWebsite()}
            else if response == .alertSecondButtonReturn {openGitHub()}
        }else if state == .failed {
            if response == .alertSecondButtonReturn {openWebsite()}
            else if response == .alertThirdButtonReturn {openGitHub()}
        }
    }
    func openWebsite() {NSWorkspace.shared.open(AppInfo.downloadURL)}
    func openGitHub() {NSWorkspace.shared.open(AppInfo.releasesURL)}
    private func cancelCheck() {
        if state == .checking {lastAttemptAt=nil;defaults?.removeObject(forKey:"updateLastAttempt")}
        generation=nil;pending=0;presentWhenFinished=false;fetcher.cancel()
        state=availableVersion == nil ? (latestVersion == nil ? .idle:.current):.available
    }
    func shutdown() {timer?.invalidate();timer=nil;cancelCheck()}
}
