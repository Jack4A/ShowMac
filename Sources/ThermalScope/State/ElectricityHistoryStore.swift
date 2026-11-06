import Foundation
import SwiftUI
import ThermalCore

@MainActor final class ElectricityHistoryStore:ObservableObject {
    @Published private(set) var revision=0
    @Published private(set) var storageIssue:String?
    @Published var rate:Double? {didSet{if persistent {defaults.set(rate,forKey:"electricityRate")}}}
    @Published var currency:String {didSet{if persistent {defaults.set(currency,forKey:"electricityCurrency")}}}
    private(set) var history=ElectricityHistory()
    private(set) var powerHistory=ElectricityPowerHistory()
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
    private var powerLoadFailed=false
    private struct PowerQuery:Hashable {let source:ElectricitySource;let start:Date;let end:Date}
    private var powerCache:[PowerQuery:[MetricPoint]]=[:]
    var sources:[ElectricitySource] {ElectricitySource.allCases.filter{watts[$0] != nil || history.sources.contains($0) || powerHistory.sources.contains($0) || $0==manualSource}}
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
        if let file=destination?.deletingLastPathComponent().appendingPathComponent("electricity-power-history.json"),FileManager.default.fileExists(atPath:file.path) {
            do {
                guard (try file.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0 <= 64*1024*1024 else{throw ScopeError.message("功率历史文件过大")}
                powerHistory=try ElectricityPowerHistory(archive:JSONDecoder().decode(ElectricityPowerHistory.Archive.self,from:Data(contentsOf:file)))
            } catch {powerLoadFailed=true;storageIssue="功率明细无法读取，原文件已保留；用电汇总仍可查看。"}
        }
    }
    func firstDate(for source:ElectricitySource)->Date? {[history.firstDate(for:source),powerHistory.firstDate(for:source)].compactMap{$0}.min()}
    func powerRecords(in range:DateInterval,source:ElectricitySource?=nil)->[MetricPoint] {
        let query=PowerQuery(source:source ?? self.source,start:range.start,end:range.end)
        if let cached=powerCache[query] {return cached}
        let records=powerHistory.records(source:query.source,in:range)
        if powerCache.count>=4 {powerCache.removeAll(keepingCapacity:true)}
        powerCache[query]=records;return records
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
        powerHistory.record(valid,source:source,at:date,maximumGap:source == .battery ? 35:15)
        dirty=true
        if publish {resumeVisualUpdates()}
    }
    func resumeVisualUpdates(){powerCache.removeAll(keepingCapacity:true);lastPublishedUptime=ProcessInfo.processInfo.systemUptime;revision &+= 1}
    func suspend() {suspended=true;history.breakContinuity();powerHistory.breakContinuity();watts.removeAll();flush()}
    func resume() {history.breakContinuity();powerHistory.breakContinuity();suspended=false}
    func shutdown() {suspended=true;history.breakContinuity();powerHistory.breakContinuity();flush(wait:true);io.sync{}}
    private func flush(wait:Bool=false) {
        guard dirty,let destination,!(loadFailed && powerLoadFailed) else{return}
        let archive=loadFailed ? nil:history.archive,powerArchive=powerLoadFailed ? nil:powerHistory.archive
        dirty=false;lastSaveUptime=ProcessInfo.processInfo.systemUptime
        let operation:@Sendable ()->Void={ [weak self] in
            do {
                if let archive {try Self.write(archive,to:destination)}
                if let powerArchive {try Self.write(powerArchive,to:destination.deletingLastPathComponent().appendingPathComponent("electricity-power-history.json"))}
                DispatchQueue.main.async {if self?.storageIssue != nil,self?.loadFailed==false,self?.powerLoadFailed==false {self?.storageIssue=nil}}
            } catch {
                DispatchQueue.main.async {self?.storageIssue="用电历史保存失败，已保留原文件；请检查可用空间和目录权限。";self?.dirty=true}
            }
        }
        if wait {io.sync(execute:operation)} else {io.async(execute:operation)}
    }
    nonisolated private static func write<T:Encodable>(_ archive:T,to url:URL)throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let data=try JSONEncoder().encode(archive)
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
}
