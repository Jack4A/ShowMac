import Foundation
import IOKit.pwr_mgt

public enum PowerSource:String,Codable,CaseIterable {case ac,battery
    public var argument:String {self == .ac ? "-c":"-b"}
    public var title:String {self == .ac ? "插电":"电池"}
}
public enum PowerSetting:String,Codable,CaseIterable {case lowpowermode,displaysleep,sleep
    public var title:String {switch self {case .lowpowermode:return "系统低电量模式";case .displaysleep:return "显示器休眠";case .sleep:return "系统闲置休眠"}}
    public func valid(_ value:Int)->Bool {self == .lowpowermode ? (0...1).contains(value):(0...240).contains(value)}
}
public struct PowerConfiguration:Codable,Equatable {
    public var profiles:[PowerSource:[PowerSetting:Int]]
    public init(_ profiles:[PowerSource:[PowerSetting:Int]]=[:]) {self.profiles=profiles}
    public func value(_ key:PowerSetting,on source:PowerSource)->Int? {profiles[source]?[key]}
    public static func parse(_ output:String)->Self {
        var profiles:[PowerSource:[PowerSetting:Int]]=[:],source:PowerSource?,seen=Set<String>()
        for line in output.components(separatedBy:.newlines) {
            let text=line.trimmingCharacters(in:.whitespaces)
            if text=="AC Power:" {source = .ac;profiles[.ac]=[:];continue}
            if text=="Battery Power:" {source = .battery;profiles[.battery]=[:];continue}
            let parts=text.split(whereSeparator:{$0.isWhitespace})
            guard let source,parts.count==2,let key=PowerSetting(rawValue:String(parts[0])),let value=Int(parts[1]),key.valid(value) else {continue}
            // Ambiguous duplicate fields are unavailable rather than guessed.
            guard seen.insert(source.rawValue+":"+key.rawValue).inserted else{profiles[source]?.removeValue(forKey:key);continue}
            profiles[source]?[key]=value
        }
        return Self(profiles)
    }
}
public enum PowerScope:String,Codable {case current,batteryAutomatic}
public struct PowerOptimizationPlan:Codable {
    public var source:PowerSource
    public var scope:PowerScope
    public var lowPower:Bool
    public var displayMinutes:Int?
    public var idleMinutes:Int?
    public var disableTurbo:Bool
    public var expected:PowerConfiguration?
    public init(source:PowerSource,scope:PowerScope = .current,lowPower:Bool=true,displayMinutes:Int?=nil,idleMinutes:Int?=nil,disableTurbo:Bool=false,expected:PowerConfiguration?=nil) {
        self.source=source;self.scope=scope;self.lowPower=lowPower;self.displayMinutes=displayMinutes;self.idleMinutes=idleMinutes;self.disableTurbo=disableTurbo;self.expected=expected
    }
    public func validate() throws {
        if let displayMinutes {guard [2,5,10].contains(displayMinutes) else{throw ScopeError.message("无效的显示器休眠时间")}}
        if let idleMinutes {guard [5,10,15].contains(idleMinutes) else{throw ScopeError.message("无效的系统休眠时间")}}
    }
    private var targets:[(PowerSource,PowerSetting,Int)] {
        var targets:[(PowerSource,PowerSetting,Int)]=[]
        if lowPower {
            if scope == .batteryAutomatic {targets += [(.battery,.lowpowermode,1),(.ac,.lowpowermode,0)]}
            else {targets.append((source,.lowpowermode,1))}
        }
        if let displayMinutes {targets.append((source,.displaysleep,displayMinutes))}
        if let idleMinutes {targets.append((source,.sleep,idleMinutes))}
        return targets
    }
    public func edits(in configuration:PowerConfiguration)->[PowerEdit] {
        targets.compactMap {source,key,after in
            guard let before=configuration.value(key,on:source),before != after else{return nil}
            return PowerEdit(source:source,key:key,before:before,after:after)
        }
    }
    public func requireReadable(_ configuration:PowerConfiguration) throws {
        try validate()
        if let expected {
            guard targets.allSatisfy({source,key,_ in expected.value(key,on:source)==configuration.value(key,on:source)}) else{throw ScopeError.message("电源设置已变化，请刷新后重新选择措施")}
        }
        if lowPower {
            let sources: [PowerSource] = scope == .batteryAutomatic ? [.battery,.ac]:[source]
            guard sources.allSatisfy({configuration.value(.lowpowermode,on:$0) != nil}) else{throw ScopeError.message("此设备的系统低电量设置不可读取")}
        }
        if displayMinutes != nil,configuration.value(.displaysleep,on:source)==nil {throw ScopeError.message("显示器休眠设置不可读取")}
        if idleMinutes != nil,configuration.value(.sleep,on:source)==nil {throw ScopeError.message("系统休眠设置不可读取")}
    }
}
public struct PowerEdit:Codable,Equatable,Identifiable {
    public let source:PowerSource
    public let key:PowerSetting
    public let before:Int
    public let after:Int
    public var id:String {source.rawValue+":"+key.rawValue}
    public init(source:PowerSource,key:PowerSetting,before:Int,after:Int) {self.source=source;self.key=key;self.before=before;self.after=after}
}
public struct PowerBackup:Codable,Identifiable {
    public let id:UUID
    public let date:Date
    public let edits:[PowerEdit]
    public let turboBefore:Int?
    public init(edits:[PowerEdit],turboBefore:Int?) {id=UUID();date=Date();self.edits=edits;self.turboBefore=turboBefore}
    public func validate() throws {
        guard edits.count<=6,Set(edits.map(\.id)).count==edits.count,edits.allSatisfy({$0.key.valid($0.before) && $0.key.valid($0.after)}),turboBefore==nil || turboBefore==0 || turboBefore==1 else {throw ScopeError.message("恢复记录无效")}
    }
}
public struct PowerOutcome:Codable {
    public let backup:PowerBackup?
    public let changed:Bool
    public let skipped:Int
    public let startedAt:Date?
    public init(backup:PowerBackup?,changed:Bool,skipped:Int=0,startedAt:Date?=nil) {self.backup=backup;self.changed=changed;self.skipped=skipped;self.startedAt=startedAt}
}
public protocol PowerSettingsAccess {
    func configuration() throws ->PowerConfiguration
    func set(_ key:PowerSetting,on source:PowerSource,to value:Int) throws
    func currentSource()->PowerSource?
    func hasSleepBlockers() throws ->Bool
    func turboState()->Int?
    func setTurbo(disabled:Bool) throws
}
public enum PowerTransaction {
    public static func apply(_ plan:PowerOptimizationPlan,using hardware:PowerSettingsAccess) throws ->PowerOutcome {
        let configuration=try hardware.configuration()
        try plan.requireReadable(configuration)
        guard hardware.currentSource()==plan.source else{throw ScopeError.message("供电状态已变化，请刷新优化方案")}
        if plan.idleMinutes != nil,try hardware.hasSleepBlockers() {throw ScopeError.message("存在阻止休眠的任务，未修改休眠设置")}
        let edits=plan.edits(in:configuration)
        var turboBefore:Int?
        if plan.disableTurbo {
            guard let state=hardware.turboState(),state==0 || state==1 else{throw ScopeError.message("睿频状态不可确认")}
            if state==0 {turboBefore=state}
        }
        let startedAt=Date()
        var attempted:[PowerEdit]=[],turboAttempted=false
        do {
            for edit in edits {attempted.append(edit);try hardware.set(edit.key,on:edit.source,to:edit.after)}
            if turboBefore != nil {turboAttempted=true;try hardware.setTurbo(disabled:true)}
        } catch {
            var failures:[String]=[]
            if turboAttempted,let turboBefore {do{try hardware.setTurbo(disabled:turboBefore==1)}catch{failures.append(error.localizedDescription)}}
            for edit in attempted.reversed() {do{try hardware.set(edit.key,on:edit.source,to:edit.before)}catch{failures.append(error.localizedDescription)}}
            if !failures.isEmpty {throw ScopeError.message(error.localizedDescription+"；部分原设置未确认恢复："+failures.joined(separator:"；"))}
            throw error
        }
        let changed = !edits.isEmpty || turboBefore != nil
        return PowerOutcome(backup:changed ? PowerBackup(edits:edits,turboBefore:turboBefore):nil,changed:changed,startedAt:startedAt)
    }
    public static func restore(_ backup:PowerBackup,using hardware:PowerSettingsAccess) throws ->PowerOutcome {
        try backup.validate()
        let current=try hardware.configuration()
        var skipped=0,changed=false
        for edit in backup.edits.reversed() {
            let actual=current.value(edit.key,on:edit.source)
            if actual==edit.before {continue}
            guard actual==edit.after else{skipped+=1;continue}
            try hardware.set(edit.key,on:edit.source,to:edit.before);changed=true
        }
        if let before=backup.turboBefore {
            let actual=hardware.turboState()
            if actual==1 {try hardware.setTurbo(disabled:before==1);changed=true}
            else if actual != before {skipped+=1}
        }
        return PowerOutcome(backup:nil,changed:changed,skipped:skipped)
    }
}
public struct SleepBlocker:Identifiable,Equatable,Codable {
    public let pid:Int32
    public let name:String
    public let reason:String
    public let type:String
    public let since:Date?
    public var id:String {"\(pid):\(type):\(reason)"}
    public static func read() throws ->[SleepBlocker] {
        var raw:Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw)==0,let values=raw?.takeRetainedValue() as NSDictionary? else{throw ScopeError.message("休眠阻止状态不可读取")}
        var blockers:[SleepBlocker]=[]
        let types=["PreventUserIdleSystemSleep","PreventSystemSleep","PreventUserIdleDisplaySleep"]
        for (pid,items) in values {
            guard let pid=pid as? NSNumber,let items=items as? [[String:Any]] else{continue}
            for item in items {
                guard let type=item["AssertType"] as? String,types.contains(type),(item["AssertLevel"] as? NSNumber)?.intValue ?? 0 > 0 else{continue}
                blockers.append(SleepBlocker(pid:pid.int32Value,name:item["Process Name"] as? String ?? "PID \(pid)",reason:item["AssertName"] as? String ?? type,type:type,since:item["AssertStartWhen"] as? Date))
            }
        }
        return blockers.sorted{$0.id<$1.id}
    }
}
/// Read-only polling uses fixed OS commands; writes run only in the authorized
/// compiled helper, with typed keys/values and verified readback, never a shell.
public enum NativePowerSettings {
    public static func read() throws ->PowerConfiguration {
        let output=try ProcessRunner.run("/usr/bin/pmset",["-g","custom"],timeout:8)
        guard output.status==0 else{throw ScopeError.message("电源设置读取失败")}
        let configuration=PowerConfiguration.parse(output.output)
        guard !configuration.profiles.isEmpty else{throw ScopeError.message("电源设置读取失败")}
        return configuration
    }
    public static func write(_ key:PowerSetting,on source:PowerSource,value:Int) throws {
        guard key.valid(value) else{throw ScopeError.message("电源参数不在允许范围")}
        let output=try ProcessRunner.run("/usr/bin/pmset",[source.argument,key.rawValue,String(value)],timeout:12)
        guard output.status==0 else{throw ScopeError.message("系统电源设置未完成："+output.output)}
        guard try read().value(key,on:source)==value else{throw ScopeError.message("系统电源设置读回不一致")}
    }
}
