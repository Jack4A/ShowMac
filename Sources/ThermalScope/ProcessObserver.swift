import AppKit
import SwiftUI
import ThermalCore
import CSMC

struct ObservedProcess:Identifiable {
    let reading:ProcessReading
    let name:String
    let application:NSRunningApplication?
    let canQuit:Bool
    var id:Int32 {reading.pid}
    var groupID:String {
        if let application,application.activationPolicy == .regular {return "app:\(application.processIdentifier):\(application.launchDate?.timeIntervalSince1970 ?? 0)"}
        return "process:\(reading.pid):\(reading.started)"
    }
}
enum ProcessSort:String,CaseIterable,Identifiable {case cpu,memory,disk
    var id:String {rawValue}
    var title:String {switch self {case .cpu:return "CPU";case .memory:return L("内存");case .disk:return L("磁盘活动")}}
}
@MainActor final class ProcessObserver:ObservableObject {
    @Published private(set) var rows:[ObservedProcess]=[]
    @Published private(set) var unavailable=0
    @Published private(set) var activity:[SustainedActivity]=[]
    @Published private(set) var observedSeconds:Double=0
    private var activityWindow=CPUActivityWindow()
    @Published var sort:ProcessSort = .cpu {didSet{sortRows()}}
    private(set) var allRows:[ObservedProcess]=[]
    private(set) var diagnosticActivity:[DiagnosticSource]=[]
    private(set) var sampledAt:Date?
    @Published var actionMessage=""
    private let sampler=NativeProcessSampler()
    private let queue=DispatchQueue(label:"local.thermalscope.processes",qos:.utility)
    private var timer:DispatchSourceTimer?
    init() {
        let timer=DispatchSource.makeTimerSource(queue:queue)
        timer.schedule(deadline:.now(),repeating:5,leeway:.seconds(1))
        let sampler=self.sampler
        timer.setEventHandler { [weak self] in
            let now=ProcessInfo.processInfo.systemUptime,date=Date()
            let values=sampler.sample(now:now),skipped=sampler.inaccessible
            DispatchQueue.main.async {self?.receive(values,skipped:skipped,now:now,date:date)}
        }
        self.timer=timer;timer.resume()
    }
    private func receive(_ values:[ProcessReading],skipped:Int,now:Double,date:Date) {
        let protected=["com.apple.finder","com.apple.dock","com.apple.loginwindow","com.apple.systemuiserver","com.apple.WindowManager"]
        let parents=Dictionary(uniqueKeysWithValues:values.map{($0.pid,$0.parentPID)})
        let applications=Dictionary(uniqueKeysWithValues:NSWorkspace.shared.runningApplications.map{($0.processIdentifier,$0)})
        let observed=values.map { row in
            let direct=applications[row.pid]
            var target=direct,ancestor=row.pid,visited=Set<Int32>()
            for _ in 0..<10 {
                guard visited.insert(ancestor).inserted else {break}
                if let app=applications[ancestor],app.activationPolicy == .regular {target=app;break}
                guard let parent=parents[ancestor],parent>1 else {break};ancestor=parent
            }
            let eligible=row.uid==getuid() && target?.processIdentifier != getpid() && target?.activationPolicy == .regular && !protected.contains(target?.bundleIdentifier ?? "")
            return ObservedProcess(reading:row,name:direct?.localizedName ?? row.name,application:target,canQuit:eligible)
        }
        allRows=observed;sampledAt=values.isEmpty ? nil:date;sortRows()
        // All readable processes participate, including children outside the top 12.
        // Group an application's helpers with its owner before integrating activity.
        let sources=observed.map { row -> ActivitySource in
            if let app=row.application,app.activationPolicy == .regular {
                return ActivitySource(id:row.groupID,name:app.localizedName ?? row.name,cpu:row.reading.cpu,diskRate:row.reading.diskRate)
            }
            return ActivitySource(id:row.groupID,name:row.name,cpu:row.reading.cpu,diskRate:row.reading.diskRate)
        }
        activityWindow.record(sources,at:now)
        activity=Array(activityWindow.rows.prefix(4));observedSeconds=activityWindow.seconds
        let candidates=Array(activityWindow.rows.prefix(4))+Array(activityWindow.rows.sorted{($0.averageDiskRate ?? 0)>($1.averageDiskRate ?? 0)}.prefix(2))
        var seen=Set<String>()
        diagnosticActivity=candidates.filter{seen.insert($0.id).inserted}.map{DiagnosticSource(id:$0.id,name:$0.name,averageCPU:$0.averageCPU,currentCPU:$0.currentCPU,averageDiskRate:$0.averageDiskRate,currentDiskRate:$0.currentDiskRate,diskSeconds:$0.diskSeconds)}
        unavailable=skipped
    }
    private func sortRows() {
        let sorted=allRows.sorted {a,b in
            switch sort {
            case .cpu:return a.reading.cpu>b.reading.cpu
            case .memory:return a.reading.memory>b.reading.memory
            case .disk:return (a.reading.diskRate ?? -1)>(b.reading.diskRate ?? -1)
            }
        }
        rows=Array(sorted.prefix(12))
    }
    func quit(_ row:ObservedProcess) {
        guard row.canQuit,ts_process_identity(row.reading.pid,getuid(),row.reading.started)==1,
              let app=row.application,!app.isTerminated else {actionMessage="进程已变化，请刷新后重试。";return}
        actionMessage=app.terminate() ? "已请求应用正常退出；有未保存内容时请在应用中处理。":"该应用没有接受退出请求，请在活动监视器中检查。"
    }
    func openActivityMonitor() {
        if let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.ActivityMonitor") {NSWorkspace.shared.open(url)}
    }
    func shutdown(){timer?.cancel()}
}
struct ProcessObserverPanel:View {
    @ObservedObject var observer:ProcessObserver
    var onInspect:((String)->Void)?
    @State private var expanded=false
    @State private var candidate:ObservedProcess?
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Label(L("进程详情"),systemImage:"waveform.path.ecg").font(.system(size:15,weight:.semibold))
                Spacer()
                Picker(L("进程排序"),selection:$observer.sort) {ForEach(ProcessSort.allCases){Text($0.title).tag($0)}}.labelsHidden().frame(width:110)
                Button(L("活动监视器")) {observer.openActivityMonitor()}.buttonStyle(.borderless).font(.caption)
                Button(expanded ? L("收起"):L("更多")) {expanded.toggle()}.buttonStyle(.borderless).font(.caption)
            }
            HStack {Text(L("应用 / 进程"));Spacer();Text("CPU").frame(width:60,alignment:.trailing);Text(L("内存")).frame(width:65,alignment:.trailing);Text(L("磁盘读写")).frame(width:85,alignment:.trailing);Color.clear.frame(width:72,height:1)}.font(.system(size:10)).foregroundStyle(.secondary)
            if observer.rows.isEmpty {Text(L("正在采样进程，约 5 秒后显示排行…")).font(.caption).foregroundStyle(.secondary)}
            ForEach(Array(observer.rows.prefix(expanded ? 12:5))) {row in
                HStack(spacing:10) {
                    VStack(alignment:.leading,spacing:3) {
                        Button(row.name){onInspect?(row.groupID)}.buttonStyle(.plain).font(.system(size:12,weight:.medium)).lineLimit(1).help(L("查看相关应用")).disabled(onInspect==nil)
                        Text(verbatim:"PID \(row.reading.pid)"+(row.application?.processIdentifier != row.reading.pid ? " · "+(row.application?.localizedName ?? ""):"")).font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength:8)
                    Text(String(format:"%.1f%%",row.reading.cpu)).font(.system(size:12,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(row.reading.cpu>70 ? Color.primary:Color.secondary).frame(width:60,alignment:.trailing)
                    Text(ByteCountFormatter.string(fromByteCount:Int64(min(row.reading.memory,UInt64(Int64.max))),countStyle:.memory)).font(.system(size:10)).foregroundStyle(.secondary).frame(width:65,alignment:.trailing)
                    Text(diskRateText(row.reading.diskRate)).font(.system(size:10)).monospacedDigit().foregroundStyle(.secondary).frame(width:85,alignment:.trailing)
                    Button(L("退出应用")) {candidate=row}.buttonStyle(.bordered).controlSize(.small).disabled(!row.canQuit).frame(width:72)
                }.padding(.vertical,3)
            }
            Text(L("每 5 秒更新；进程 CPU 以单个核心 100% 计，多线程应用可能超过 100%。")).font(.system(size:9)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if observer.unavailable>0 {Text(L("部分系统进程受 macOS 权限限制，不会当作零占用。")).font(.system(size:9)).foregroundStyle(.secondary)}
            if !observer.actionMessage.isEmpty {Text(L(observer.actionMessage)).font(.caption).foregroundStyle(.secondary)}
        }.padding(22).subtlePanel()
        .confirmationDialog(L("请求应用正常退出？"),isPresented:Binding(get:{candidate != nil},set:{if !$0{candidate=nil}}),titleVisibility:.visible) {
            if let row=candidate {Button(L("退出应用"),role:.destructive) {observer.quit(row);candidate=nil}}
            Button(L("取消"),role:.cancel){candidate=nil}
        } message:{Text(L("将退出所属应用：")+(candidate?.application?.localizedName ?? candidate?.name ?? "")+"\n"+L("有未保存内容时，应用可能要求你先保存。系统进程和其他用户的进程不会在这里结束。"))}
    }
}
