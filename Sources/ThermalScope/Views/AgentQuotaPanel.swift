import SwiftUI
import ThermalCore

@MainActor enum QuotaFormat {
    static func percent(_ value:Double)->String {
        if value>0,value<0.1 {return "<0.1%"}
        return ElectricityFormat.number(value,maximum:value>0 && value<1 ? 1:0)+"%"
    }
    static func window(_ row:AgentQuotaWindow)->String {
        guard let minutes=row.minutes else{return row.window=="secondary" ? L("长周期额度"):L("当前额度")}
        if minutes.isMultiple(of:1440) {return String(format:L("%d 天额度"),minutes/1440)}
        if minutes.isMultiple(of:60) {return String(format:L("%d 小时额度"),minutes/60)}
        return String(format:L("%d 分钟额度"),minutes)
    }
    static func reset(_ row:AgentQuotaWindow,at now:Date=Date())->String {
        guard let date=row.resetsAt else{return L("未提供重置时间")}
        let seconds=date.timeIntervalSince(now)
        if seconds<=0 {return L("周期已结束，等待新读数")}
        if seconds>=86400 {return String(format:L("%d 天后重置"),Int(ceil(seconds/86400)))}
        return ElectricityFormat.duration(seconds)+" "+L("后重置")
    }
    static func updated(_ row:AgentQuotaWindow)->String {
        let minutes=max(0,Int(Date().timeIntervalSince(row.observedAt)/60))
        if minutes<1 {return L("刚刚")}
        if minutes<60 {return String(format:L("%d 分钟前"),minutes)}
        return ElectricityFormat.powerDate(row.observedAt)
    }
    static func color(_ remaining:Double?)->Color {
        guard let remaining else{return Palette.secondaryText}
        return remaining<=5 ? .red:(remaining<=20 ? .orange:Palette.violet)
    }
}
struct AgentQuotaPanel:View {
    @ObservedObject var model:AppModel
    @ObservedObject var store:TokenUsageStore
    @State private var connecting=false
    init(model:AppModel){self.model=model;self.store=model.tokens}
    private struct Group:Identifiable {
        let provider:TokenProvider
        let pool:String
        let rows:[AgentQuotaWindow]
        var id:String {provider.rawValue+":"+pool}
    }
    private var groups:[Group] {
        Dictionary(grouping:store.quotas,by:{$0.provider.rawValue+":"+$0.pool}).values.compactMap {rows in
            guard let first=rows.first else{return nil}
            return Group(provider:first.provider,pool:first.pool,rows:rows.sorted{($0.minutes ?? 0)<($1.minutes ?? 0)})
        }.sorted{$0.id<$1.id}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text(L("账户额度")).font(AppTypography.section)
                Spacer()
                Button {connecting=true} label:{HStack(spacing:5) {AgentProviderBadge(provider:.claude,size:17,background:false);Text(L("Claude Code 同步"))}}.buttonStyle(AppChoiceButtonStyle()).font(AppTypography.caption)
                    .accessibilityIdentifier("claudeQuotaConnection")
            }
            if groups.isEmpty {
                HStack(spacing:12) {
                    AgentProviderBadge(provider:.codex,size:36)
                    VStack(alignment:.leading,spacing:6) {
                        Text(L("等待工具报告额度")).font(AppTypography.body)
                        Text(L("Codex 自动读取最近的额度记录；Claude Code 可启用本机同步。"))
                            .font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                    }
                    Spacer(minLength:0)
                }.padding(.vertical,6)
            } else {
                ForEach(groups) {group in providerCard(group)}
            }
            HStack(spacing:5) {
                Image(systemName:"info.circle")
                Text(L("工具报告的额度，与 Token 累计分开统计。"))
            }.font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                .help(L("余量来自工具报告，与本机 Token 累计独立；超过 15 分钟未更新或已重置的读数不作为当前余量。"))
        }.subtlePanel(padding:18).sheet(isPresented:$connecting){ClaudeQuotaConnectionSheet(store:store,preview:model.isFanControlPreview)}
    }
    private func providerCard(_ group:Group)->some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:10) {
                AgentProviderBadge(provider:group.provider,size:32)
                VStack(alignment:.leading,spacing:3) {
                    Text(AgentProviderArtwork.title(group.provider)).font(AppTypography.body).fontWeight(.semibold)
                    if !["codex","default"].contains(group.pool) {Text(group.rows.first?.poolName ?? group.pool).font(AppTypography.caption).foregroundColor(Palette.secondaryText)}
                }
                Spacer(minLength:4)
                if let latest=group.rows.max(by:{$0.observedAt<$1.observedAt}) {
                    Text(L("最近报告")+" · "+QuotaFormat.updated(latest)).font(.system(size:10)).foregroundColor(Palette.secondaryText)
                        .help(ElectricityFormat.powerDate(latest.observedAt))
                }
            }
            if group.rows.count==1,let row=group.rows.first {quotaWindow(row,compact:true)}
            else {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:14) {
                    ForEach(group.rows) {row in quotaWindow(row)}
                }
            }
        }.padding(14).appBackground(AgentProviderArtwork.color(group.provider).opacity(0.04),in:RoundedRectangle(cornerRadius:14,style:.continuous))
    }
    private func quotaWindow(_ row:AgentQuotaWindow,compact:Bool=false)->some View {
        let remaining=row.remaining(),pinned=model.hasTokenMetric(.tokenQuota,provider:row.provider.rawValue,quotaID:row.id)
        return VStack(alignment:.leading,spacing:9) {
            HStack(alignment:.firstTextBaseline,spacing:6) {
                if compact {
                    VStack(alignment:.leading,spacing:5) {
                        Text(QuotaFormat.window(row)).font(AppTypography.body)
                        resetLabel(row)
                    }
                    Spacer(minLength:4)
                } else {Text(QuotaFormat.window(row)).font(AppTypography.caption).foregroundColor(Palette.secondaryText);Spacer(minLength:4)}
                if compact {percent(remaining)}
                Button {model.pinTokenMetric(.tokenQuota,provider:row.provider.rawValue,quotaID:row.id)} label:{Image(systemName:pinned ? "checkmark":"pin")}
                    .buttonStyle(.borderless).disabled(pinned || model.effectiveMenuComponents.count>=MenuBarComponent.limit).help(L("显示在状态栏")).accessibilityLabel(AgentProviderArtwork.title(row.provider)+" · "+QuotaFormat.window(row)+" · "+L("显示在状态栏"))
            }
            if !compact {percent(remaining)}
            GeometryReader {proxy in
                ZStack(alignment:.leading) {
                    Capsule().fill(Palette.violet.opacity(0.09))
                    if let remaining {Capsule().fill(QuotaFormat.color(remaining)).frame(width:max(0,proxy.size.width*remaining/100))}
                }
            }.frame(height:5).accessibilityLabel(L("额度余量")).accessibilityValue(remaining.map{QuotaFormat.percent($0)} ?? L("未提供"))
            if !compact {resetLabel(row)}
        }.padding(compact ? 0:12).appBackground(compact ? Color.clear:Palette.surface.opacity(0.65),in:RoundedRectangle(cornerRadius:10))
    }
    private func percent(_ remaining:Double?)->some View {
        HStack(alignment:.firstTextBaseline,spacing:5) {
            Text(remaining.map{QuotaFormat.percent($0)} ?? "—").font(AppTypography.number(29,weight:.semibold)).foregroundColor(QuotaFormat.color(remaining)).appMonospacedDigit()
            Text(L(remaining==nil ? "等待更新":"剩余")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
        }.fixedSize(horizontal:true,vertical:false)
    }
    private func resetLabel(_ row:AgentQuotaWindow)->some View {
        Label(QuotaFormat.reset(row),systemImage:"clock").font(.system(size:10)).foregroundColor(Palette.secondaryText).lineLimit(1)
    }
}

struct ClaudeQuotaConnectionSheet:View {
    @ObservedObject var store:TokenUsageStore
    let preview:Bool
    @Environment(\.presentationMode) private var presentation
    @State private var installed:Bool
    init(store:TokenUsageStore,preview:Bool) {self.store=store;self.preview=preview;_installed=State(initialValue:preview ? false:ClaudeQuotaIntegration.installed)}
    @State private var issue:String?
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Label(L("Claude Code 本机额度同步"),systemImage:"link").font(AppTypography.section)
            Text(L("Claude Code 每次更新状态行时，将官方提供的额度百分比与重置时间写入 ShowMac 的本机缓存。无需 API 密钥，也不会读取钥匙串。"))
            Text(L("启用会修改 ~/.claude/settings.json 的 statusLine，并串联保留原命令的输出。原状态行会私密保存，可在这里恢复；其余设置保持原值。"))
                .foregroundColor(Palette.secondaryText)
            if let issue {Text(L(issue)).foregroundColor(.orange)}
            HStack {
                Link(L("查看官方状态行说明"),destination:URL(string:"https://code.claude.com/docs/en/statusline#rate-limit-usage")!)
                Spacer()
                Button(L("关闭")){presentation.wrappedValue.dismiss()}.buttonStyle(AppNativeButtonStyle()).keyboardShortcut(.cancelAction)
                Button(L(installed ? "恢复原状态行":"启用同步")) {
                    do {
                        if installed {try ClaudeQuotaIntegration.disable()}else{try ClaudeQuotaIntegration.enable()}
                        installed=ClaudeQuotaIntegration.installed;issue=nil;store.refresh()
                    }catch{installed=ClaudeQuotaIntegration.installed;issue=error.localizedDescription}
                }.buttonStyle(AppChoiceButtonStyle()).disabled(preview)
            }
        }.font(AppTypography.body).padding(24).frame(width:520).fixedSize(horizontal:false,vertical:true).appBackground{Palette.canvas}
    }
}
struct StatusTokenSummary:View {
    @ObservedObject var store:TokenUsageStore
    let model:AppModel
    let onOpen:()->Void
    init(model:AppModel,onOpen:@escaping()->Void){self.model=model;self.store=model.tokens;self.onOpen=onOpen}
    var body:some View {
        let usage=model.effectiveMenuComponents.first{$0.metric == .tokens},quota=model.effectiveMenuComponents.first{$0.metric == .tokenQuota}
        let count=model.tokenMenuReading(metric:.tokens,configuration:usage?.token ?? TokenMenuConfiguration())
        let quotaConfig=quota?.token ?? TokenMenuConfiguration(provider:usage?.token?.tool?.rawValue ?? "codex")
        let provider=quotaConfig.tool ?? .codex
        let remaining=model.tokenMenuReading(metric:.tokenQuota,configuration:quotaConfig)
        return Button(action:onOpen) {
            HStack(spacing:12) {
                Image(systemName:"number.circle").foregroundColor(Palette.violet)
                VStack(alignment:.leading,spacing:4) {Text(L((usage?.token?.period ?? .day).currentTitle)+" Token").font(AppTypography.caption).foregroundColor(Palette.secondaryText);Text(count.text).font(AppTypography.number(18,weight:.semibold))}
                Spacer(minLength:4)
                VStack(alignment:.trailing,spacing:4) {HStack(spacing:4) {AgentProviderBadge(provider:provider,size:15,background:false);Text(AgentProviderArtwork.title(provider)+" · "+L("余量"))}.font(AppTypography.caption).foregroundColor(Palette.secondaryText);Text(remaining.text).font(AppTypography.number(18,weight:.semibold))}
                Image(systemName:"chevron.right").font(.system(size:10)).foregroundColor(Palette.secondaryText)
            }.padding(12).contentShape(Rectangle()).modifier(StatusCardSurface())
        }.buttonStyle(.plain).help(count.title+" · "+remaining.title).accessibilityLabel("Token · "+count.text+" · "+L("账户余量")+" "+remaining.text)
    }
}
