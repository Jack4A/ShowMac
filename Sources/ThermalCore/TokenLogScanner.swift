import Foundation
import CryptoKit

public struct TokenLogRoot:Sendable {
    public let provider:TokenProvider
    public let url:URL
    public init(provider:TokenProvider,url:URL){self.provider=provider;self.url=url}
}
public struct TokenScanSnapshot:Sendable {
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
    public init(){}
}

/// Serial, append-only scans on a utility queue. Cache contains counters/identities, not chat text.
public final class TokenLogScanner {
    private struct Entry:Codable {
        var provider:TokenProvider
        var inode:UInt64
        var size:UInt64
        var modified:Date
        var prefix:String
        var offset:UInt64
        var state:TokenLogState
    }
    private struct Cache:Codable {let version:Int;var entries:[String:Entry]}
    private var entries:[String:Entry]=[:]
    private let cacheURL:URL?
    private var cacheWritable=true
    public init(cacheURL:URL?=nil) {
        self.cacheURL=cacheURL
        if let cacheURL,FileManager.default.fileExists(atPath:cacheURL.path) {
            do {
                guard (try cacheURL.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0 < 64*1024*1024 else{throw ScopeError.message("Token cache too large")}
                let cache=try JSONDecoder().decode(Cache.self,from:Data(contentsOf:cacheURL))
                guard cache.version==1,cache.entries.count<=10000,cache.entries.values.allSatisfy({$0.offset<=$0.size && $0.state.events.count<=250000 && $0.state.events.allSatisfy{$0.counts.valid && $0.date.timeIntervalSince1970.isFinite}}) else{throw ScopeError.message("Invalid Token cache")}
                entries=cache.entries
            } catch {cacheWritable=false}
        }
    }
    public static func defaultRoots(home:URL=FileManager.default.homeDirectoryForCurrentUser,environment:[String:String]=ProcessInfo.processInfo.environment)->[TokenLogRoot] {
        let codex=environment["CODEX_HOME"].map{URL(fileURLWithPath:$0,isDirectory:true)} ?? home.appendingPathComponent(".codex",isDirectory:true)
        let claude=environment["CLAUDE_CONFIG_DIR"].map{URL(fileURLWithPath:$0,isDirectory:true)} ?? home.appendingPathComponent(".claude",isDirectory:true)
        return [TokenLogRoot(provider:.codex,url:codex.appendingPathComponent("sessions")),TokenLogRoot(provider:.codex,url:codex.appendingPathComponent("archived_sessions")),TokenLogRoot(provider:.claude,url:claude.appendingPathComponent("projects")),TokenLogRoot(provider:.claude,url:home.appendingPathComponent(".config/claude/projects"))]
    }
    public func scan(roots:[TokenLogRoot])->TokenScanSnapshot {
        var snapshot=TokenScanSnapshot(),active=Set<String>(),states:[TokenLogState]=[],seenFiles=Set<String>()
        var changed=false
        for root in roots {
            var directory:ObjCBool=false
            guard FileManager.default.fileExists(atPath:root.url.path,isDirectory:&directory) else{continue}
            guard directory.boolValue,let enumerator=FileManager.default.enumerator(at:root.url,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles],errorHandler:{_,_ in snapshot.unreadable+=1;return true}) else {snapshot.unreadable+=1;continue}
            for case let file as URL in enumerator where file.pathExtension=="jsonl" {
                guard snapshot.fileCount<10000 else{snapshot.unreadable+=1;break}
                let canonical=file.standardizedFileURL.path
                guard seenFiles.insert(canonical).inserted else{continue}
                do {
                    let values=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
                    guard values.isRegularFile==true,values.isSymbolicLink != true else{continue}
                    let attributes=try FileManager.default.attributesOfItem(atPath:file.path)
                    let size=(attributes[.size] as? NSNumber)?.uint64Value ?? 0,inode=(attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,modified=attributes[.modificationDate] as? Date ?? .distantPast
                    let key=root.provider.rawValue+":"+Self.digest(Data(canonical.utf8));active.insert(key);snapshot.fileCount+=1
                    if let entry=entries[key],entry.inode==inode,entry.size==size,entry.modified==modified {snapshot.unchangedFiles+=1;states.append(entry.state);snapshot.malformed+=entry.state.malformed;continue}
                    let handle=try FileHandle(forReadingFrom:file);defer{try? handle.close()}
                    let header=try handle.read(upToCount:Int(min(size,4096))) ?? Data(),prefix=Self.digest(header)
                    var entry=entries[key]
                    if entry==nil || entry!.inode != inode || entry!.offset>size || entry!.prefix != prefix || size<=entry!.size {
                        snapshot.reparsedFiles+=1
                        entry=Entry(provider:root.provider,inode:inode,size:0,modified:.distantPast,prefix:prefix,offset:0,state:TokenLogState(session:key))
                    }
                    if entry!.offset>0 {snapshot.appendedFiles+=1}
                    var value=entry!,buffer=Data(),discarding=false,position=value.offset
                    try handle.seek(toOffset:value.offset)
                    while let chunk=try handle.read(upToCount:1024*1024),!chunk.isEmpty {
                        snapshot.bytesRead+=UInt64(chunk.count)
                        var start=chunk.startIndex
                        for index in chunk.indices where chunk[index]==10 {
                            let part=chunk[start..<index]
                            if !discarding {
                                if buffer.count+part.count<=4*1024*1024 {buffer.append(part);value.state.consume(buffer,provider:root.provider,ordinal:position)}
                                else if Self.usageHeader(buffer,provider:root.provider) {value.state.malformed+=1}
                            }
                            position+=UInt64(buffer.count+part.count+1)
                            // Position is reset from the actual reader offset below for long discarded lines.
                            buffer.removeAll(keepingCapacity:true);discarding=false;start=chunk.index(after:index)
                            value.offset=try handle.offset()-UInt64(chunk.count-chunk.distance(from:chunk.startIndex,to:start))
                            position=value.offset
                        }
                        let tail=chunk[start..<chunk.endIndex]
                        if !discarding {
                            if buffer.count+tail.count<=4*1024*1024 {buffer.append(tail)}
                            else {if Self.usageHeader(buffer,provider:root.provider) {value.state.malformed+=1};buffer.removeAll(keepingCapacity:true);discarding=true}
                        }
                        if value.state.events.count>250000 {snapshot.unreadable+=1;break}
                    }
                    value.size=max(size,try handle.offset());value.modified=((try? FileManager.default.attributesOfItem(atPath:file.path)[.modificationDate]) as? Date) ?? modified;value.prefix=prefix;entries[key]=value;changed=true
                    states.append(value.state);snapshot.malformed+=value.state.malformed
                } catch {snapshot.unreadable+=1}
            }
        }
        if entries.keys.contains(where:{!active.contains($0)}) {entries=entries.filter{active.contains($0.key)};changed=true}
        let reconciled=TokenLogReconciliation.events(from:states);snapshot.events=reconciled.events;snapshot.unresolvedForks=reconciled.unresolvedForks
        if changed,let cacheURL,cacheWritable {
            do {
                try FileManager.default.createDirectory(at:cacheURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                try JSONEncoder().encode(Cache(version:1,entries:entries)).write(to:cacheURL,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:cacheURL.path)
            } catch {snapshot.unreadable+=1}
        }
        if !cacheWritable {snapshot.unreadable+=1}
        snapshot.scannedAt=Date();return snapshot
    }
    private static func usageHeader(_ data:Data,provider:TokenProvider)->Bool {
        let prefix=data.prefix(512)
        let types=provider == .codex ? ["session_meta","turn_context","event_msg","token_usage_record"]:["assistant"]
        return types.contains{prefix.range(of:Data(("\""+$0+"\"").utf8)) != nil}
    }
    private static func digest(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
}
