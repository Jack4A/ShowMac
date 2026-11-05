import Foundation
import SwiftUI
import ThermalCore

@MainActor final class ElectricityHistoryStore:ObservableObject {
    @Published private(set) var revision=0
    @Published private(set) var storageIssue:String?
    @Published var rate:Double? {didSet{if persistent {defaults.set(rate,forKey:"electricityRate")}}}
    @Published var currency:String {didSet{if persistent {defaults.set(currency,forKey:"electricityCurrency")}}}
    private(set) var history=ElectricityHistory()
    private(set) var watts:[ElectricitySource:Double]=[:]
    private(set) var sampledAt:Date?
    private var manualSource:ElectricitySource?
    private let defaults:UserDefaults
    private let destination:URL?
    private let persistent:Bool
    private let io=DispatchQueue(label:"local.showmac.electricity-history",qos:.utility)
    private var lastPublishedUptime = -Double.infinity
    private var lastSaveUptime = -Double.infinity
    private var dirty=false
    private var suspended=false
    private var loadFailed=false
    var sources:[ElectricitySource] {ElectricitySource.allCases.filter{watts[$0] != nil || history.sources.contains($0) || $0==manualSource}}
    var source:ElectricitySource {manualSource ?? sources.first ?? .system}
    init(persistent:Bool=true,fileURL:URL?=nil,defaults:UserDefaults = .standard) {
        let check=CommandLine.arguments.dropFirst().contains{$0.hasSuffix("-check") || $0=="--ui-check"}
        self.persistent=persistent && (!check || fileURL != nil);self.defaults=defaults
        let saved=defaults.object(forKey:"electricityRate") as? Double
        rate=saved.flatMap{$0.isFinite && (0...10000).contains($0) ? $0:nil}
        let code=defaults.string(forKey:"electricityCurrency") ?? "CNY"
        currency=["CNY","USD","EUR","GBP","JPY","HKD"].contains(code) ? code:"CNY"
        manualSource=defaults.string(forKey:"electricitySource").flatMap(ElectricitySource.init(rawValue:))
        destination=self.persistent ? (fileURL ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("ShowMac",isDirectory:true).appendingPathComponent("electricity-history.json")):nil
        if let destination,FileManager.default.fileExists(atPath:destination.path) {
            do {
                let size=(try destination.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
                guard size<=64*1024*1024 else{throw ScopeError.message("用电历史文件过大")}
                let data=try Data(contentsOf:destination)
                history=try ElectricityHistory(archive:JSONDecoder().decode(ElectricityHistory.Archive.self,from:data))
            } catch {loadFailed=true;storageIssue="历史记录无法读取，原文件已保留；本次数据暂未保存。"}
        }
    }
    func selectSource(_ source:ElectricitySource) {
        manualSource=source
        if persistent {defaults.set(source.rawValue,forKey:"electricitySource")}
        resumeVisualUpdates()
    }
    func record(_ sample:Snapshot,telemetry:SystemTelemetry?,publish:Bool=true) {
        guard !suspended else{return}
        for (source,key) in [(ElectricitySource.system,"PSTR"),(.dcInput,"PDTR")] {
            let value=sample.additionalSensors?.first{$0.key==key && $0.kind == .power}?.value
            recordPower(value,source:source,at:sample.date,publish:false)
        }
        if sample.acPower==false,let telemetry,abs(sample.date.timeIntervalSince(telemetry.date))<=35,
           telemetry.charging != true,let value=telemetry.batteryWatts,value<=0 {
            recordPower(-value,source:.battery,at:telemetry.date,publish:false)
        } else {recordPower(nil,source:.battery,at:sample.date,publish:false)}
        let uptime=ProcessInfo.processInfo.systemUptime
        if publish,uptime-lastPublishedUptime>=10 {resumeVisualUpdates()}
        if uptime-lastSaveUptime>=60 {flush()}
    }
    func recordPower(_ value:Double?,source:ElectricitySource,at date:Date,publish:Bool=true) {
        guard !suspended,date.timeIntervalSince1970.isFinite else{return}
        let valid=value.flatMap{$0.isFinite && (0...10000).contains($0) ? $0:nil}
        watts[source]=valid;sampledAt=max(sampledAt ?? date,date)
        history.record(valid,source:source,at:date,maximumGap:source == .battery ? 35:15)
        dirty=true
        if publish {resumeVisualUpdates()}
    }
    func resumeVisualUpdates(){lastPublishedUptime=ProcessInfo.processInfo.systemUptime;revision &+= 1}
    func suspend() {suspended=true;history.breakContinuity();watts.removeAll();flush()}
    func resume() {history.breakContinuity();suspended=false}
    func shutdown() {suspended=true;history.breakContinuity();flush(wait:true);io.sync{}}
    private func flush(wait:Bool=false) {
        guard dirty,let destination,!loadFailed else{return}
        let archive=history.archive;dirty=false;lastSaveUptime=ProcessInfo.processInfo.systemUptime
        let operation:@Sendable ()->Void={ [weak self] in
            do {
                try Self.write(archive,to:destination)
                DispatchQueue.main.async {if self?.storageIssue != nil {self?.storageIssue=nil}}
            } catch {
                DispatchQueue.main.async {self?.storageIssue="用电历史保存失败，已保留原文件；请检查可用空间和目录权限。";self?.dirty=true}
            }
        }
        if wait {io.sync(execute:operation)} else {io.async(execute:operation)}
    }
    nonisolated private static func write(_ archive:ElectricityHistory.Archive,to url:URL)throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let data=try JSONEncoder().encode(archive)
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
}
