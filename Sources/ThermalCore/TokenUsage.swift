import Foundation

/// Generated from the pinned Tokscale client registry; see docs/AGENT-USAGE.md.
public struct TokenProvider:RawRepresentable,Codable,CaseIterable,Identifiable,Hashable,Sendable {
    public let rawValue:String
    public init?(rawValue:String){guard Self.definitions[rawValue] != nil else{return nil};self.rawValue=rawValue}
    private init(_ id:String){rawValue=id}
    public var id:String {rawValue}
    private struct Definition:Sendable {let title:String;let paths:[String];let environment:String?;let relative:String;let custom:Bool;let cached:Bool}
    private var definition:Definition {Self.definitions[rawValue]!}
    public var title:String {definition.title}
    public var supportsCustom:Bool {definition.custom}
    public var requiresCache:Bool {definition.cached}
    public var rootEnvironmentKey:String? {definition.environment}
    public var environmentKey:String {"SHOWMAC_SOURCE_"+rawValue.uppercased().replacingOccurrences(of:"-",with:"_")}
    public static let allCases:[Self]=[
        Self("codex"),Self("claude"),Self("cursor"),Self("gemini"),Self("opencode"),Self("amp"),Self("antigravity"),Self("antigravity-cli"),Self("antigravity-extension"),Self("aside"),Self("augment"),Self("bb"),Self("cherrystudio"),Self("cline"),Self("codebuddy"),Self("codebuff"),Self("commandcode"),Self("copilot"),Self("crush"),Self("dsh"),Self("devin-cli"),Self("devin-desktop"),Self("droid"),Self("freebuff"),Self("fx"),Self("gjc"),Self("goose"),Self("grok"),Self("hermes"),Self("hindsight"),Self("jcode"),Self("junie"),Self("kilo"),Self("kilocode"),Self("kimchi"),Self("kimi"),Self("kiro"),Self("lmstudio"),Self("micode"),Self("mcode"),Self("vibe"),Self("muse"),Self("mux"),Self("omp"),Self("openclaw"),Self("opencodereview"),Self("pi"),Self("prime-agent"),Self("proma"),Self("qwen"),Self("reasonix"),Self("roocode"),Self("senpi"),Self("trae"),Self("unsloth"),Self("warp"),Self("workbuddy"),Self("micode-desktop"),Self("zcode"),Self("zed")
    ]
    public static let codex=Self("codex")
    public static let claude=Self("claude")
    public static let cursor=Self("cursor")
    public static let gemini=Self("gemini")
    public static let opencode=Self("opencode")
    public static let amp=Self("amp")
    public static let antigravity=Self("antigravity")
    public static let antigravityCli=Self("antigravity-cli")
    public static let antigravityExtension=Self("antigravity-extension")
    public static let aside=Self("aside")
    public static let augment=Self("augment")
    public static let bb=Self("bb")
    public static let cherrystudio=Self("cherrystudio")
    public static let cline=Self("cline")
    public static let codebuddy=Self("codebuddy")
    public static let codebuff=Self("codebuff")
    public static let commandcode=Self("commandcode")
    public static let copilot=Self("copilot")
    public static let crush=Self("crush")
    public static let dsh=Self("dsh")
    public static let devinCli=Self("devin-cli")
    public static let devinDesktop=Self("devin-desktop")
    public static let droid=Self("droid")
    public static let freebuff=Self("freebuff")
    public static let fx=Self("fx")
    public static let gjc=Self("gjc")
    public static let goose=Self("goose")
    public static let grok=Self("grok")
    public static let hermes=Self("hermes")
    public static let hindsight=Self("hindsight")
    public static let jcode=Self("jcode")
    public static let junie=Self("junie")
    public static let kilo=Self("kilo")
    public static let kilocode=Self("kilocode")
    public static let kimchi=Self("kimchi")
    public static let kimi=Self("kimi")
    public static let kiro=Self("kiro")
    public static let lmstudio=Self("lmstudio")
    public static let micode=Self("micode")
    public static let mcode=Self("mcode")
    public static let vibe=Self("vibe")
    public static let muse=Self("muse")
    public static let mux=Self("mux")
    public static let omp=Self("omp")
    public static let openclaw=Self("openclaw")
    public static let opencodereview=Self("opencodereview")
    public static let pi=Self("pi")
    public static let primeAgent=Self("prime-agent")
    public static let proma=Self("proma")
    public static let qwen=Self("qwen")
    public static let reasonix=Self("reasonix")
    public static let roocode=Self("roocode")
    public static let senpi=Self("senpi")
    public static let trae=Self("trae")
    public static let unsloth=Self("unsloth")
    public static let warp=Self("warp")
    public static let workbuddy=Self("workbuddy")
    public static let micodeDesktop=Self("micode-desktop")
    public static let zcode=Self("zcode")
    public static let zed=Self("zed")
    private static let definitions:[String:Definition]=[
        "codex":Definition(title:"Codex CLI",paths:["~/.codex/sessions"],environment:"CODEX_HOME",relative:"sessions",custom:true,cached:false),
        "claude":Definition(title:"Claude Code",paths:["~/.claude/projects", "~/.claude/transcripts"],environment:"CLAUDE_CONFIG_DIR",relative:"projects",custom:true,cached:false),
        "cursor":Definition(title:"Cursor IDE",paths:["~/.config/tokscale/cursor-cache"],environment:"TOKSCALE_CONFIG_DIR",relative:"cursor-cache",custom:true,cached:true),
        "gemini":Definition(title:"Gemini CLI",paths:["~/.gemini/tmp"],environment:"GEMINI_CLI_HOME",relative:"tmp",custom:true,cached:false),
        "opencode":Definition(title:"OpenCode",paths:["~/.local/share/opencode/storage/message"],environment:nil,relative:"opencode/storage/message",custom:true,cached:false),
        "amp":Definition(title:"Amp",paths:["~/.config/tokscale/amp-cache/threads", "~/.local/share/amp/threads"],environment:nil,relative:"amp-cache/threads",custom:true,cached:false),
        "antigravity":Definition(title:"Antigravity",paths:["~/.config/tokscale/antigravity-cache/sessions"],environment:nil,relative:"antigravity-cache/sessions",custom:true,cached:false),
        "antigravity-cli":Definition(title:"Antigravity CLI",paths:["~/.gemini/antigravity-cli/conversations"],environment:"GEMINI_CLI_HOME",relative:"antigravity-cli/conversations",custom:true,cached:false),
        "antigravity-extension":Definition(title:"Antigravity IDE Extension",paths:["~/.gemini/antigravity/conversations"],environment:nil,relative:".gemini/antigravity/conversations",custom:true,cached:false),
        "aside":Definition(title:"Aside",paths:["~/.aside/u"],environment:nil,relative:".aside/u",custom:true,cached:false),
        "augment":Definition(title:"Augment Code",paths:["~/.augment/sessions"],environment:nil,relative:".augment/sessions",custom:true,cached:false),
        "bb":Definition(title:"BB",paths:["~/.bb/bb.db"],environment:"BB_DATA_DIR",relative:"bb.db",custom:true,cached:false),
        "cherrystudio":Definition(title:"Cherry Studio",paths:["~/Library/Application Support/CherryStudio/.claude/projects"],environment:nil,relative:"CherryStudio/.claude/projects",custom:true,cached:false),
        "cline":Definition(title:"Cline",paths:["~/.config/Code/User/globalStorage/saoudrizwan.claude-dev/tasks"],environment:nil,relative:".config/Code/User/globalStorage/saoudrizwan.claude-dev/tasks",custom:true,cached:false),
        "codebuddy":Definition(title:"CodeBuddy",paths:["~/.codebuddy/projects"],environment:nil,relative:".codebuddy/projects",custom:true,cached:false),
        "codebuff":Definition(title:"Codebuff",paths:["~/.config/manicode/projects"],environment:"CODEBUFF_DATA_DIR",relative:"projects",custom:true,cached:false),
        "commandcode":Definition(title:"Command Code",paths:["~/.commandcode/projects"],environment:nil,relative:".commandcode/projects",custom:true,cached:false),
        "copilot":Definition(title:"Copilot CLI",paths:["~/.copilot/otel"],environment:nil,relative:".copilot/otel",custom:true,cached:false),
        "crush":Definition(title:"Crush",paths:["~/.local/share/crush/projects.json"],environment:nil,relative:"crush/projects.json",custom:false,cached:false),
        "dsh":Definition(title:"DeepSeek Harness",paths:["~/.dsh/sessions"],environment:"DSH_HOME",relative:"sessions",custom:true,cached:false),
        "devin-cli":Definition(title:"Devin CLI",paths:["~/.local/share/devin/cli/sessions.db"],environment:nil,relative:"devin/cli/sessions.db",custom:true,cached:false),
        "devin-desktop":Definition(title:"Devin Desktop",paths:["~/Library/Application Support/Devin/User/acp-events"],environment:nil,relative:"Library/Application Support/Devin/User/acp-events",custom:true,cached:false),
        "droid":Definition(title:"Droid",paths:["~/.factory/sessions"],environment:nil,relative:".factory/sessions",custom:true,cached:false),
        "freebuff":Definition(title:"Freebuff",paths:["~/.config/manicode/projects"],environment:"FREEBUFF_DATA_DIR",relative:"projects",custom:true,cached:false),
        "fx":Definition(title:"Fx",paths:["~/.fx/sessions"],environment:nil,relative:".fx/sessions",custom:true,cached:false),
        "gjc":Definition(title:"Gajae-Code",paths:["~/.gjc/agent/sessions"],environment:"GJC_CODING_AGENT_DIR",relative:"sessions",custom:true,cached:false),
        "goose":Definition(title:"Goose",paths:["~/.local/share/goose/sessions/sessions.db"],environment:nil,relative:"goose/sessions/sessions.db",custom:false,cached:false),
        "grok":Definition(title:"Grok Build",paths:["~/.grok/sessions"],environment:"GROK_HOME",relative:"sessions",custom:true,cached:false),
        "hermes":Definition(title:"Hermes Agent",paths:["~/.hermes/state.db"],environment:"HERMES_HOME",relative:"state.db",custom:true,cached:false),
        "hindsight":Definition(title:"Hindsight",paths:["~/.hindsight/usage"],environment:"HINDSIGHT_HOME",relative:"usage",custom:true,cached:false),
        "jcode":Definition(title:"Jcode",paths:["~/.jcode/sessions"],environment:"JCODE_HOME",relative:"sessions",custom:true,cached:false),
        "junie":Definition(title:"Junie",paths:["~/.junie/sessions"],environment:nil,relative:".junie/sessions",custom:true,cached:false),
        "kilo":Definition(title:"Kilo CLI",paths:["~/.local/share/kilo/kilo.db"],environment:nil,relative:"kilo/kilo.db",custom:false,cached:false),
        "kilocode":Definition(title:"Kilo Code",paths:["~/.config/Code/User/globalStorage/kilocode.kilo-code/tasks"],environment:nil,relative:".config/Code/User/globalStorage/kilocode.kilo-code/tasks",custom:true,cached:false),
        "kimchi":Definition(title:"Kimchi",paths:["~/.config/kimchi/harness/sessions"],environment:"KIMCHI_CODING_AGENT_DIR",relative:"sessions",custom:true,cached:false),
        "kimi":Definition(title:"Kimi CLI",paths:["~/.kimi/sessions"],environment:nil,relative:".kimi/sessions",custom:true,cached:false),
        "kiro":Definition(title:"Kiro",paths:["~/.kiro/sessions/cli"],environment:nil,relative:".kiro/sessions/cli",custom:true,cached:false),
        "lmstudio":Definition(title:"LM Studio",paths:["~/.lmstudio/server-logs"],environment:"LM_STUDIO_HOME",relative:"server-logs",custom:true,cached:false),
        "micode":Definition(title:"MiMo Code",paths:["~/.local/share/mimocode"],environment:nil,relative:"mimocode",custom:true,cached:false),
        "mcode":Definition(title:"MiniMax Code",paths:["~/.config/tokscale/headless/mcode"],environment:nil,relative:"headless/mcode",custom:true,cached:false),
        "vibe":Definition(title:"Mistral Vibe",paths:["~/.vibe/logs/session"],environment:"VIBE_HOME",relative:"logs/session",custom:true,cached:false),
        "muse":Definition(title:"Muse Code",paths:["~/.local/share/muse/sessions"],environment:nil,relative:"muse/sessions",custom:true,cached:false),
        "mux":Definition(title:"Mux",paths:["~/.mux/sessions"],environment:nil,relative:".mux/sessions",custom:true,cached:false),
        "omp":Definition(title:"Oh My Pi",paths:["~/.omp/agent/sessions"],environment:nil,relative:".omp/agent/sessions",custom:true,cached:false),
        "openclaw":Definition(title:"OpenClaw",paths:["~/.openclaw/agents"],environment:nil,relative:".openclaw/agents",custom:true,cached:false),
        "opencodereview":Definition(title:"OpenCodeReview",paths:["~/.opencodereview/sessions"],environment:nil,relative:".opencodereview/sessions",custom:true,cached:false),
        "pi":Definition(title:"Pi",paths:["~/.pi/agent/sessions"],environment:nil,relative:".pi/agent/sessions",custom:true,cached:false),
        "prime-agent":Definition(title:"Prime Agent",paths:["~/.prime/agent/sessions"],environment:"PRIME_AGENT_CODING_AGENT_DIR",relative:"sessions",custom:true,cached:false),
        "proma":Definition(title:"Proma",paths:["~/.proma"],environment:nil,relative:".proma",custom:true,cached:false),
        "qwen":Definition(title:"Qwen CLI",paths:["~/.qwen/projects"],environment:nil,relative:".qwen/projects",custom:true,cached:false),
        "reasonix":Definition(title:"Reasonix",paths:["~/.reasonix/stats"],environment:nil,relative:"stats",custom:true,cached:false),
        "roocode":Definition(title:"Roo Code",paths:["~/.config/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks"],environment:nil,relative:".config/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks",custom:true,cached:false),
        "senpi":Definition(title:"Senpi (OmO Native)",paths:["~/.omo/agent/sessions", "~/.omo/memory", "~/.omo/senpi-task/children", "~/.senpi/agent/sessions"],environment:"SENPI_CODING_AGENT_DIR",relative:"sessions",custom:true,cached:false),
        "trae":Definition(title:"Trae",paths:["~/.config/tokscale/trae-cache/sessions"],environment:nil,relative:"trae-cache/sessions",custom:true,cached:false),
        "unsloth":Definition(title:"Unsloth",paths:["~/.unsloth/studio/studio.db"],environment:"UNSLOTH_STUDIO_HOME",relative:"studio.db",custom:true,cached:false),
        "warp":Definition(title:"Warp",paths:["~/.config/tokscale/warp-cache"],environment:nil,relative:"warp-cache",custom:true,cached:false),
        "workbuddy":Definition(title:"WorkBuddy",paths:["~/.workbuddy"],environment:nil,relative:".workbuddy",custom:true,cached:false),
        "micode-desktop":Definition(title:"Xiaomi MiMo AI",paths:["~/.local/share/mimocode"],environment:nil,relative:"mimocode",custom:true,cached:false),
        "zcode":Definition(title:"ZCode",paths:["~/.zcode/projects"],environment:nil,relative:".zcode/projects",custom:true,cached:false),
        "zed":Definition(title:"Zed Agent",paths:["~/.local/share/zed/threads/threads.db"],environment:nil,relative:"zed/threads/threads.db",custom:true,cached:false),
    ]
    public func roots(home:URL=FileManager.default.homeDirectoryForCurrentUser,environment:[String:String]=ProcessInfo.processInfo.environment)->[URL] {
        if let custom=environment[environmentKey],!custom.isEmpty {return [URL(fileURLWithPath:custom)]}
        if let key=rootEnvironmentKey,let override=environment[key],!override.trimmingCharacters(in:.whitespaces).isEmpty {
            var roots=[URL(fileURLWithPath:override).appendingPathComponent(definition.relative)]
            if self == .codex {roots.append(URL(fileURLWithPath:override).appendingPathComponent("archived_sessions"))}
            if self == .claude {roots.append(URL(fileURLWithPath:override).appendingPathComponent("transcripts"))}
            return roots
        }
        var paths=definition.paths
        let extra:[String:[String]]=[
            "codex":["~/.codex/archived_sessions"],
            "opencode":["~/.local/share/opencode"],
            "copilot":["~/.copilot/session-state","~/.copilot/session-store.db","~/Library/Application Support/Code/User/workspaceStorage","~/Library/Application Support/Code/User/globalStorage/emptyWindowChatSessions"],
            "roocode":["~/Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks"],
            "kilocode":["~/Library/Application Support/Code/User/globalStorage/kilocode.kilo-code/tasks"],
            "cline":["~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks","~/.cline/data/sessions"],
            "zed":["~/Library/Application Support/Zed/threads/threads.db"],
            "goose":["~/Library/Application Support/goose/sessions/sessions.db","~/Library/Application Support/Block/goose/sessions/sessions.db"],
            "kiro":["~/Library/Application Support/kiro-cli/data.sqlite3","~/Library/Application Support/Kiro/User/globalStorage/kiro.kiroagent","~/Library/Application Support/kiro/User/globalStorage/kiro.kiroagent"],
            "micode":["~/Library/Application Support/orca/mimocode-hooks/shared/data"],
            "micode-desktop":["~/Library/Application Support/orca/mimocode-hooks/shared/data"],
            "workbuddy":["~/.workbuddy-ai/projects","~/.workbuddy-ai/workbuddy.db"],
            "cherrystudio":["~/Library/Application Support/CherryStudio/Data/Agents/.claude/projects"]
        ]
        paths += extra[rawValue] ?? []
        return paths.flatMap {value -> [URL] in
            var path=value.replacingOccurrences(of:"~",with:home.path)
            if let xdg=environment["XDG_DATA_HOME"],!xdg.isEmpty {path=path.replacingOccurrences(of:home.appendingPathComponent(".local/share").path,with:xdg)}
            let url=URL(fileURLWithPath:path)
            if ["db","sqlite3"].contains(url.pathExtension) {return [url,URL(fileURLWithPath:path+"-wal"),URL(fileURLWithPath:path+"-shm")]}
            return [url]
        }
    }
    public init(from decoder:Decoder)throws {
        let c=try decoder.singleValueContainer(),id=try c.decode(String.self)
        guard let value=Self(rawValue:id) else{throw DecodingError.dataCorruptedError(in:c,debugDescription:"Unsupported Agent source")}
        self=value
    }
    public func encode(to encoder:Encoder)throws {var c=encoder.singleValueContainer();try c.encode(rawValue)}
}

/// Input includes cached input; reasoning is a subset of output, never added twice.
public struct TokenCounts:Codable,Equatable,Sendable {
    public var input:Int64
    public var output:Int64
    public var cacheRead:Int64
    public var cacheWrite:Int64
    public var reasoning:Int64
    public var unclassified:Int64
    public var total:Int64 {input+output+unclassified}
    public init(input:Int64=0,output:Int64=0,cacheRead:Int64=0,cacheWrite:Int64=0,reasoning:Int64=0,unclassified:Int64=0) {
        self.input=input;self.output=output;self.cacheRead=cacheRead;self.cacheWrite=cacheWrite;self.reasoning=reasoning;self.unclassified=unclassified
    }
    public var valid:Bool {[input,output,cacheRead,cacheWrite,reasoning,unclassified].allSatisfy{(0...1_000_000_000_000).contains($0)} && cacheRead+cacheWrite<=input && reasoning<=output}
    public func adding(_ other:Self)->Self {Self(input:input+other.input,output:output+other.output,cacheRead:cacheRead+other.cacheRead,cacheWrite:cacheWrite+other.cacheWrite,reasoning:reasoning+other.reasoning,unclassified:unclassified+other.unclassified)}
    public func maximum(_ other:Self)->Self {
        let i=max(input,other.input),o=max(output,other.output),r=max(cacheRead,other.cacheRead)
        return Self(input:i,output:o,cacheRead:min(i,r),cacheWrite:min(i-min(i,r),max(cacheWrite,other.cacheWrite)),reasoning:min(o,max(reasoning,other.reasoning)),unclassified:max(unclassified,other.unclassified))
    }
    public func delta(from previous:Self)->Self? {
        guard input>=previous.input,output>=previous.output else{return nil}
        let i=input-previous.input,o=output-previous.output,r=min(i,max(0,cacheRead-previous.cacheRead))
        return Self(input:i,output:o,cacheRead:r,cacheWrite:min(i-r,max(0,cacheWrite-previous.cacheWrite)),reasoning:min(o,max(0,reasoning-previous.reasoning)))
    }
    private enum CodingKeys:String,CodingKey {case input,output,cacheRead,cacheWrite,reasoning,unclassified}
    public init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        input=try c.decode(Int64.self,forKey:.input);output=try c.decode(Int64.self,forKey:.output)
        cacheRead=try c.decode(Int64.self,forKey:.cacheRead);cacheWrite=try c.decode(Int64.self,forKey:.cacheWrite)
        reasoning=try c.decode(Int64.self,forKey:.reasoning);unclassified=try c.decodeIfPresent(Int64.self,forKey:.unclassified) ?? 0
    }
    var signature:String {"\(input):\(output):\(cacheRead):\(cacheWrite):\(reasoning)"}
}
public struct TokenUsageEvent:Codable,Equatable,Sendable {
    public let id:String
    public let provider:TokenProvider
    public let date:Date
    public let model:String
    public var counts:TokenCounts
    public let cumulative:String?
    public let fallback:Bool
    public init(id:String,provider:TokenProvider,date:Date,model:String,counts:TokenCounts,cumulative:String?=nil,fallback:Bool=false) {
        self.id=id;self.provider=provider;self.date=date;self.model=model;self.counts=counts;self.cumulative=cumulative;self.fallback=fallback
    }
}
public struct TokenUsageBucket:Identifiable {
    public var id:Date {interval.start}
    public let interval:DateInterval
    public var counts:TokenCounts
    public var requests:Int
}
public struct TokenModelUsage:Identifiable {
    public var id:String {provider.rawValue+":"+model}
    public let provider:TokenProvider
    public let model:String
    public var counts:TokenCounts
    public var requests:Int
}
public struct TokenUsageReport {
    public let events:[TokenUsageEvent]
    public let counts:TokenCounts
    public let buckets:[TokenUsageBucket]
    public let models:[TokenModelUsage]
    public init(events:[TokenUsageEvent],in range:DateInterval,provider:TokenProvider?=nil,intervals:[DateInterval]) {
        let selected=events.filter{range.start<=$0.date && $0.date<range.end && (provider==nil || $0.provider==provider)}
        self.events=selected;counts=selected.reduce(TokenCounts()){$0.adding($1.counts)}
        var models:[String:TokenModelUsage]=[:]
        var buckets=intervals.map{TokenUsageBucket(interval:$0,counts:TokenCounts(),requests:0)}
        for event in selected {
            let key=event.provider.rawValue+":"+event.model
            var model=models[key] ?? TokenModelUsage(provider:event.provider,model:event.model,counts:TokenCounts(),requests:0)
            model.counts=model.counts.adding(event.counts);model.requests+=1;models[key]=model
            if let index=buckets.firstIndex(where:{$0.interval.start<=event.date && event.date<$0.interval.end}) {
                buckets[index].counts=buckets[index].counts.adding(event.counts);buckets[index].requests+=1
            }
        }
        self.models=models.values.sorted{$0.counts.total==$1.counts.total ? $0.id<$1.id:$0.counts.total>$1.counts.total};self.buckets=buckets
    }
}
