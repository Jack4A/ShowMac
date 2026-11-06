import Foundation
import ThermalCore
import Darwin

/// An explicit, reversible status-line integration. No OAuth or Keychain access.
enum ClaudeQuotaIntegration {
    static var folder:URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ShowMac/ClaudeQuota",isDirectory:true)}
    static var cache:URL {folder.appendingPathComponent("quota.json")}
    static var configuration:URL {FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")}
    static func read()->[AgentQuotaWindow] {
        guard let a=try? cache.resourceValues(forKeys:[.fileSizeKey]),let size=a.fileSize,size<65536,let data=try? Data(contentsOf:cache),let rows=try? JSONDecoder().decode([AgentQuotaWindow].self,from:data) else{return []}
        return rows.filter{$0.provider == .claude && $0.valid}
    }
    static var installed:Bool {isInstalled(settings:configuration,executable:Bundle.main.executableURL!)}
    static func isInstalled(settings:URL,executable:URL)->Bool {
        guard let data=try? Data(contentsOf:settings),let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let line=object["statusLine"] as? [String:Any] else{return false}
        return line["command"] as? String==command(executable)
    }
    private static func command(_ executable:URL)->String {"'"+executable.path.replacingOccurrences(of:"'",with:"'\\''")+"' --claude-quota-statusline"}
    static func enable(settings:URL=configuration,directory:URL=folder,executable:URL=Bundle.main.executableURL!)throws {
        if isInstalled(settings:settings,executable:executable){return}
        if (try? settings.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink)==true {throw ScopeError.message("Claude Code 设置是符号链接，请手动配置同步。") }
        var original:Data?
        var object:[String:Any]=[:]
        if FileManager.default.fileExists(atPath:settings.path) {
            let data=try Data(contentsOf:settings);original=data;guard data.count<4*1024*1024,let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else{throw ScopeError.message("Claude Code 设置无法读取，未做修改。")};object=value
        }
        if let old=object["statusLine"],!(old is [String:Any]) {throw ScopeError.message("Claude Code 状态行格式不受支持，未做修改。")}
        if let old=object["statusLine"] as? [String:Any],(old["type"] as? String != nil && old["type"] as? String != "command" || old["command"] != nil && !(old["command"] is String)) {throw ScopeError.message("Claude Code 状态行格式不受支持，未做修改。")}
        let backup=directory.appendingPathComponent("original-statusline.json")
        guard !FileManager.default.fileExists(atPath:backup.path) else{throw ScopeError.message("已有状态行恢复记录，请先恢复原配置。")}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let saved:[String:Any]=["existed":object["statusLine"] != nil,"value":object["statusLine"] ?? NSNull()]
        try privateWrite(JSONSerialization.data(withJSONObject:saved,options:[.sortedKeys]),to:backup)
        var line=(object["statusLine"] as? [String:Any]) ?? [:];line["type"]="command";line["command"]=command(executable);object["statusLine"]=line
        do {
            guard (try? Data(contentsOf:settings))==original else{throw ScopeError.message("Claude Code 设置刚被修改，请重试。") }
            try FileManager.default.createDirectory(at:settings.deletingLastPathComponent(),withIntermediateDirectories:true)
            try privateWrite(JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]),to:settings)
        } catch {if !isInstalled(settings:settings,executable:executable) {try? FileManager.default.removeItem(at:backup)};throw error}
    }
    static func disable(settings:URL=configuration,directory:URL=folder,executable:URL=Bundle.main.executableURL!)throws {
        guard isInstalled(settings:settings,executable:executable) else{throw ScopeError.message("状态行已被其他工具修改，未覆盖当前配置。")}
        let backup=directory.appendingPathComponent("original-statusline.json"),current=try Data(contentsOf:settings)
        guard let saved=(try JSONSerialization.jsonObject(with:Data(contentsOf:backup))) as? [String:Any],let existed=saved["existed"] as? Bool,var object=(try JSONSerialization.jsonObject(with:current)) as? [String:Any] else{throw ScopeError.message("原状态行记录无法读取。")}
        if existed {object["statusLine"]=saved["value"]}else{object.removeValue(forKey:"statusLine")}
        guard try Data(contentsOf:settings)==current else{throw ScopeError.message("Claude Code 设置刚被修改，请重试。") }
        try privateWrite(JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]),to:settings)
        try FileManager.default.removeItem(at:backup)
        try? FileManager.default.removeItem(at:directory.appendingPathComponent("quota.json"))
    }
    static func capture()->Int32 {
        var input=Data()
        while let chunk=try? FileHandle.standardInput.read(upToCount:16384),!chunk.isEmpty {
            input.append(chunk);if input.count>512*1024 {return 1}
        }
        return capture(input:input)
    }
    static func capture(input:Data,directory:URL=folder,chain:Bool=true)->Int32 {
        guard input.count<=512*1024 else{return 1}
        let rows=AgentQuotaParser.claude(input)
        if !rows.isEmpty {
            do {try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);try privateWrite(JSONEncoder().encode(rows),to:directory.appendingPathComponent("quota.json"))}catch{}
        }
        let backup=directory.appendingPathComponent("original-statusline.json")
        if chain,let data=try? Data(contentsOf:backup),let saved=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let value=saved["value"] as? [String:Any],let previous=value["command"] as? String,!previous.isEmpty,!previous.contains("--claude-quota-statusline") {
            let inputPipe=Pipe(),process=Process();process.executableURL=URL(fileURLWithPath:"/bin/sh");process.arguments=["-c",previous];process.standardInput=inputPipe;process.standardOutput=FileHandle.standardOutput;process.standardError=FileHandle.standardError
            let done=DispatchSemaphore(value:0);process.terminationHandler={_ in done.signal()}
            do {
                signal(SIGPIPE,SIG_IGN)
                try process.run();inputPipe.fileHandleForReading.closeFile()
                DispatchQueue.global(qos:.utility).async {try? inputPipe.fileHandleForWriting.write(contentsOf:input);try? inputPipe.fileHandleForWriting.close()}
                if done.wait(timeout:.now()+5) == .timedOut {process.terminate();if done.wait(timeout:.now()+1) == .timedOut {kill(process.processIdentifier,SIGKILL)};return 1}
                return process.terminationStatus
            }catch{return 1}
        }
        let summary=rows.compactMap{row in row.remaining().map{String(row.minutes ?? 0)+"m "+String(format:"%.0f%%",$0)}}.joined(separator:" · ")
        print(summary.isEmpty ? "Claude Code":"Claude · "+summary);return 0
    }
    private static func privateWrite(_ data:Data,to url:URL)throws {try data.write(to:url,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)}
}
