import Foundation
import CryptoKit
import Darwin

public struct TokenScanSnapshot:Codable,Sendable {
    public var events:[TokenUsageEvent]=[]
    public var fileCount=0
    public var unreadable=0
    public var malformed=0
    public var unresolvedForks=0
    public var bytesRead:UInt64=0
    public var reparsedFiles=0
    public var appendedFiles=0
    public var unchangedFiles=0
    public var scannedAt=Date()
    public var sourceStates:[String:String]=[:]
    public init(){}
}


/// Uses bundled Tokscale parsers, never an executable found through PATH or a downloaded script.
public final class AgentUsageEngine {
    public static let commit="82613d2f5e96654ce3729892afbb0025979f1c75"
    public struct Output:Decodable {
        struct Source:Decodable {let provider:TokenProvider;let state:String;let records:Int}
        struct Event:Decodable {
            let id:String;let provider:TokenProvider;let timestampMs:Int64;let model:String
            let input:Int64;let output:Int64;let cacheRead:Int64;let cacheWrite:Int64;let reasoning:Int64;let unclassified:Int64
        }
        let version:Int;let engine:String;let commit:String;let sources:[Source];let events:[Event]
    }
    private struct Cache:Codable {let version:Int;let fingerprint:String;let snapshot:TokenScanSnapshot}
    private let executable:URL
    private let cacheURL:URL?
    private var cached:Cache?
    public init(executable:URL,cacheURL:URL?=nil) {
        self.executable=executable;self.cacheURL=cacheURL
        if let cacheURL,let size=try? cacheURL.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<64*1024*1024,
           let data=try? Data(contentsOf:cacheURL),let cache=try? JSONDecoder().decode(Cache.self,from:data),cache.version==1,
           cache.snapshot.events.count<=500000,cache.snapshot.events.allSatisfy({$0.counts.valid && $0.date.timeIntervalSince1970.isFinite}) {cached=cache}
    }
    public static func decode(_ data:Data)throws->TokenScanSnapshot {
        guard data.count<64*1024*1024 else{throw ScopeError.message("Agent usage output is too large")}
        let output=try JSONDecoder().decode(Output.self,from:data)
        guard output.version==1,output.engine=="tokscale",output.commit==commit,Set(output.sources.map(\.provider))==Set(TokenProvider.allCases),output.events.count<=500000 else{throw ScopeError.message("Agent usage engine protocol mismatch")}
        var snapshot=TokenScanSnapshot(),seen=Set<String>()
        for event in output.events {
            let counts=TokenCounts(input:event.input,output:event.output,cacheRead:event.cacheRead,cacheWrite:event.cacheWrite,reasoning:event.reasoning,unclassified:event.unclassified)
            let date=Date(timeIntervalSince1970:Double(event.timestampMs)/1000)
            guard counts.valid,counts.total>0,event.id.utf8.count<=512,event.model.utf8.count<=256,abs(date.timeIntervalSince1970)<10_000_000_000 else{snapshot.malformed+=1;continue}
            guard seen.insert(event.id).inserted else{continue}
            snapshot.events.append(TokenUsageEvent(id:event.id,provider:event.provider,date:date,model:event.model,counts:counts))
        }
        snapshot.events.sort{$0.date<$1.date}
        for source in output.sources {snapshot.sourceStates[source.provider.rawValue]=source.state}
        return snapshot
    }
    public func scan(custom:[String:String]=[:],environment:[String:String]=ProcessInfo.processInfo.environment)->TokenScanSnapshot {
        var safeEnvironment=environment.filter{["HOME","USER","PATH","TMPDIR","LANG","LC_ALL","TZ","XDG_CONFIG_HOME","XDG_DATA_HOME"].contains($0.key) || TokenProvider.allCases.flatMap{[$0.environmentKey,$0.rootEnvironmentKey ?? ""]}.contains($0.key)}
        for provider in TokenProvider.allCases {if let path=custom[provider.rawValue] {safeEnvironment[provider.environmentKey]=path}}
        let paths=Dictionary(uniqueKeysWithValues:TokenProvider.allCases.compactMap {provider -> (String,[String])? in
            guard provider.supportsCustom,let path=safeEnvironment[provider.environmentKey],!path.isEmpty else{return nil}
            return (provider.rawValue,[path])
        })
        if let encoded=try? JSONEncoder().encode(paths){safeEnvironment["SHOWMAC_AGENT_PATHS"]=String(decoding:encoded,as:UTF8.self)}
        let metadata=fingerprint(environment:safeEnvironment)
        if let cached,cached.fingerprint==metadata.hash,Date().timeIntervalSince(cached.snapshot.scannedAt)<300 {var snapshot=cached.snapshot;snapshot.scannedAt=Date();snapshot.bytesRead=0;snapshot.unchangedFiles=metadata.files;return snapshot}
        do {
            let result=try run(environment:safeEnvironment)
            var snapshot=try Self.decode(result.data)
            if result.partial {snapshot.malformed+=1}
            snapshot.fileCount=metadata.files
            for provider in TokenProvider.allCases {
                let state=snapshot.sourceStates[provider.rawValue]
                if state=="error" {
                    let exists=provider.roots(environment:safeEnvironment).contains{FileManager.default.fileExists(atPath:$0.path)}
                    if exists {
                        snapshot.unreadable+=1
                        snapshot.events.append(contentsOf:cached?.snapshot.events.filter{$0.provider==provider} ?? [])
                    } else {snapshot.sourceStates[provider.rawValue]="missing"}
                } else if state=="empty" {snapshot.sourceStates[provider.rawValue]="missing"}
            }
            snapshot.events.sort{$0.date<$1.date};snapshot.unreadable+=metadata.issues
            let cache=Cache(version:1,fingerprint:metadata.hash,snapshot:snapshot);cached=cache
            if let cacheURL,snapshot.unreadable==0 {
                try FileManager.default.createDirectory(at:cacheURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                try JSONEncoder().encode(cache).write(to:cacheURL,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:cacheURL.path)
            }
            return snapshot
        } catch {
            var snapshot=cached?.snapshot ?? TokenScanSnapshot();snapshot.unreadable=max(1,snapshot.unreadable);snapshot.scannedAt=Date();return snapshot
        }
    }
    private func run(environment:[String:String])throws->(data:Data,partial:Bool) {
        guard FileManager.default.isExecutableFile(atPath:executable.path) else{throw ScopeError.message("Bundled Tokscale engine is missing")}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("showmac-agent-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer{try? FileManager.default.removeItem(at:directory)}
        let output=directory.appendingPathComponent("usage.json")
        FileManager.default.createFile(atPath:output.path,contents:Data(),attributes:[.posixPermissions:0o600])
        let handle=try FileHandle(forWritingTo:output);defer{try? handle.close()}
        let errorURL=directory.appendingPathComponent("errors.txt")
        FileManager.default.createFile(atPath:errorURL.path,contents:Data(),attributes:[.posixPermissions:0o600])
        let errorHandle=try FileHandle(forWritingTo:errorURL);defer{try? errorHandle.close()}
        let process=Process(),done=DispatchSemaphore(value:0)
        process.executableURL=executable;process.environment=environment;process.standardOutput=handle;process.standardError=errorHandle
        process.terminationHandler={_ in done.signal()};try process.run()
        if done.wait(timeout:.now()+45) == .timedOut {
            process.terminate()
            if done.wait(timeout:.now()+2) == .timedOut {kill(process.processIdentifier,SIGKILL);_ = done.wait(timeout:.now()+2)}
            throw ScopeError.message("Agent usage scan timed out")
        }
        guard process.terminationStatus==0,let size=try output.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<64*1024*1024 else{throw ScopeError.message("Agent usage scan failed")}
        let errors=try FileHandle(forReadingFrom:errorURL);defer{try? errors.close()}
        let text=String(decoding:(try? errors.read(upToCount:256*1024)) ?? Data(),as:UTF8.self)
        return (try Data(contentsOf:output),text.contains("Warning:") || text.contains("unreadable source"))
    }
    private func fingerprint(environment:[String:String])->(hash:String,files:Int,issues:Int) {
        var hasher=SHA256(),files=0,issues=0,seen=Set<String>()
        func add(_ text:String){hasher.update(data:Data((text+"\n").utf8))}
        add(Self.commit)
        if let a=try? FileManager.default.attributesOfItem(atPath:executable.path) {add("\(a[.size] ?? 0):\(a[.modificationDate] ?? Date.distantPast)")}
        for provider in TokenProvider.allCases {
            for root in provider.roots(environment:environment) {
                add(provider.rawValue+":"+root.path)
                guard FileManager.default.fileExists(atPath:root.path) else{continue}
                if let values=try? root.resourceValues(forKeys:[.isRegularFileKey]),values.isRegularFile==true,let a=try? FileManager.default.attributesOfItem(atPath:root.path) {
                    add(root.path+":\(a[.size] ?? 0):\((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)");files+=1;continue
                }
                guard let enumerator=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[],errorHandler:{_,_ in issues+=1;return true}) else{continue}
                var rows:[String]=[]
                for case let file as URL in enumerator {
                    guard files<100000 else{issues+=1;break}
                    guard seen.insert(file.path).inserted else{continue}
                    if let values=try? file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey]),values.isRegularFile==true,values.isSymbolicLink != true,let a=try? FileManager.default.attributesOfItem(atPath:file.path) {
                        rows.append(file.path+":\(a[.size] ?? 0):\(a[.systemFileNumber] ?? 0):\((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)");files+=1
                    }
                }
                for row in rows.sorted(){add(row)}
            }
        }
        return (hasher.finalize().map{String(format:"%02x",$0)}.joined(),files,issues)
    }
}
