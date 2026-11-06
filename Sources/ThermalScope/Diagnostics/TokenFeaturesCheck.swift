import AppKit
import ThermalCore

@MainActor enum TokenFeaturesCheck {
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else{exit(2)}
        _=NSApplication.shared
        let key=Bundle.main.bundleIdentifier!,before=NSDictionary(dictionary:UserDefaults.standard.persistentDomain(forName:key) ?? [:])
        let model=AppModel();model.shutdown()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("showmac-token-features-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        do {
            let localized:[(Int64,String)]=[(9999,"9,999"),(10_000,"1万"),(75_750,"7.58万"),(1_500_000,"1.5百万"),(25_000_000,"2.5千万"),(559_710_000,"5.6亿"),(1_200_000_000_000,"1.2万亿")]
            for (value,expected) in localized {guard TokenFormat.compact(value,language:"zh-Hans")==expected else{throw ScopeError.message("Chinese token magnitude: "+String(value))}}
            guard TokenFormat.compact(1_500_000,language:"en")=="1.5M",TokenFormat.compact(75_750,language:"en")=="75.75K",TokenFormat.compact(559_710_000,language:"zh-Hant")=="5.6億",!TokenFormat.compact(Int64.max,language:"zh-Hans").isEmpty else{throw ScopeError.message("Token magnitude locale or overflow")}
            let now=Date(),range=ElectricityPeriod.day.interval(containing:now)
            model.tokens.setPreview([TokenUsageEvent(id:"fixture",provider:.codex,date:now,model:"sample",counts:TokenCounts(input:100,output:20,cacheRead:40))])
            model.menuComposition=[MenuBarComponent(metric:.cpu,style:.iconValue)]
            model.pinTokenMetric(.tokens,provider:"codex")
            model.pinTokenMetric(.tokens,provider:"codex")
            guard model.effectiveMenuComponents.count==2 else{throw ScopeError.message("Duplicate token pin")}
            let token=model.effectiveMenuComponents.last!,reading=model.tokenMenuReading(metric:.tokens,configuration:token.token!)
            guard reading.number==120,reading.range?.start==range.start,reading.points.reduce(0,{($1.value ?? 0)+$0})==120 else{throw ScopeError.message("Token menu totals or real time scale")}
            guard let decoded=MenuBarComponent.decode(try JSONEncoder().encode(model.effectiveMenuComponents)),decoded==model.effectiveMenuComponents else{throw ScopeError.message("Token menu configuration round trip")}
            let malformed=Data("{\"provider\":\"unknown-tool\",\"period\":\"future-period\"}".utf8)
            guard let normalized=try? JSONDecoder().decode(TokenMenuConfiguration.self,from:malformed),normalized.provider=="all",normalized.period == .day else{throw ScopeError.message("Malformed token settings fallback")}
            let quota=model.tokenMenuReading(metric:.tokenQuota)
            guard quota.number==42 else{throw ScopeError.message("Most constrained quota selection")}
            let shared=AgentQuotaWindow(provider:.codex,pool:"codex",window:"primary",minutes:300,usedPercent:30,resetsAt:now.addingTimeInterval(3000),observedAt:now)
            let separate=AgentQuotaWindow(provider:.codex,pool:"model-specific",window:"primary",minutes:300,usedPercent:95,resetsAt:now.addingTimeInterval(3000),observedAt:now)
            model.tokens.setPreviewQuotas([shared,separate])
            guard model.tokenMenuReading(metric:.tokenQuota).number==70,model.tokenMenuReading(metric:.tokenQuota,configuration:TokenMenuConfiguration(provider:"codex",quotaID:separate.id)).number==5 else{throw ScopeError.message("Independent model quota mixed with shared account allowance")}
            guard model.tokenMenuReading(metric:.tokenQuota,configuration:TokenMenuConfiguration(provider:"codex",quotaID:"codex:missing:primary")).number==nil else{throw ScopeError.message("Missing explicit quota silently fell back to another pool")}
            model.tokens.setPreviewQuotas([AgentQuotaWindow(provider:.codex,pool:"codex",window:"primary",minutes:300,usedPercent:42,resetsAt:now.addingTimeInterval(-1),observedAt:now.addingTimeInterval(-2))])
            guard model.tokenMenuReading(metric:.tokenQuota).number==nil else{throw ScopeError.message("Expired quota shown as fresh")}
            guard MenuBarComponent.template(metric:.tokenQuota,style:.history).style == .ring else{throw ScopeError.message("Quota is not a token history graph")}
            for dark in [false,true] {
                let tile=MenuBarAppearanceRenderer.tile(component:token,model:model)
                let image=MenuBarAppearanceRenderer.image(tiles:[tile],ending:now,spacing:18,graphWidth:44,background:false,appearance:NSAppearance(named:dark ? .darkAqua:.aqua))
                guard image.isTemplate,image.size.width>10,tile.warningKind==nil else{throw ScopeError.message("Token menu monochrome rendering")}
            }
            let settings=root.appendingPathComponent("settings.json"),directory=root.appendingPathComponent("integration"),executable=URL(fileURLWithPath:"/Applications/showmac.app/Contents/MacOS/ThermalScope")
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let original:[String:Any]=["statusLine":["type":"command","command":"printf original-output","padding":3],"env":["KEEP":"UNCHANGED"],"theme":"dark"]
            try JSONSerialization.data(withJSONObject:original).write(to:settings)
            try ClaudeQuotaIntegration.enable(settings:settings,directory:directory,executable:executable)
            let enabled=try JSONSerialization.jsonObject(with:Data(contentsOf:settings)) as! [String:Any]
            guard enabled["env"] as? [String:String]==["KEEP":"UNCHANGED"],enabled["theme"] as? String=="dark",ClaudeQuotaIntegration.isInstalled(settings:settings,executable:executable) else{throw ScopeError.message("Status-line opt-in touched unrelated settings")}
            try ClaudeQuotaIntegration.disable(settings:settings,directory:directory,executable:executable)
            let restored=try JSONSerialization.jsonObject(with:Data(contentsOf:settings)) as! NSDictionary
            guard restored==original as NSDictionary else{throw ScopeError.message("Original status-line restoration")}
            let payload=try JSONSerialization.data(withJSONObject:["rate_limits":["five_hour":["used_percentage":23,"resets_at":Date().addingTimeInterval(3600).timeIntervalSince1970]],"prompt":"PRIVATE_PAYLOAD","api_key":"PRIVATE_KEY"])
            guard ClaudeQuotaIntegration.capture(input:payload,directory:directory,chain:false)==0 else{throw ScopeError.message("Claude quota capture")}
            let cached=try String(contentsOf:directory.appendingPathComponent("quota.json"),encoding:.utf8)
            guard !cached.contains("PRIVATE"),cached.contains("usedPercent") else{throw ScopeError.message("Capture retained non-quota data")}
            guard before.isEqual(NSDictionary(dictionary:UserDefaults.standard.persistentDomain(forName:key) ?? [:])) else{throw ScopeError.message("Token fixtures changed preferences")}
            print("PASS: Chinese/English/Traditional token magnitudes, token menu pinning/dedup, period and provider totals, real graph scale, monochrome rendering, quota expiration, configuration round trip, opt-in Claude status-line preservation/restoration and metadata-only capture. Isolated fixtures; no hardware or real CLI settings changed.")
        }catch{fputs("Token feature check failed: \(error)\n",stderr);exit(1)}
    }
}
