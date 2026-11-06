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
    private var rows:[AgentQuotaWindow] {
        store.quotas.sorted {a,b in
            let left=a.provider.rawValue+(a.pool=="codex" || a.pool=="default" ? "0":"1")
            let right=b.provider.rawValue+(b.pool=="codex" || b.pool=="default" ? "0":"1")
            return left==right ? (a.minutes ?? 0)<(b.minutes ?? 0):left<right
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Label(L("账户额度"),systemImage:"chart.pie").font(AppTypography.section)
                Text(L("最近报告")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                Spacer()
                Button {connecting=true} label:{Label(L("Claude Code 同步"),systemImage:"link")}.buttonStyle(AppChoiceButtonStyle()).font(AppTypography.caption)
                    .accessibilityIdentifier("claudeQuotaConnection")
            }
            if rows.isEmpty {
                HStack(spacing:12) {
                    Image(systemName:"hourglass").font(.system(size:24)).foregroundColor(Palette.violet)
                    VStack(alignment:.leading,spacing:6) {
                        Text(L("等待工具报告额度")).font(AppTypography.body)
                        Text(L("Codex 自动读取最近的额度记录；Claude Code 可启用本机同步。"))
                            .font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                    }
                    Spacer(minLength:0)
                }.padding(.vertical,6)
            } else {
                LazyVGrid(columns:rows.count==1 ? [GridItem(.flexible())]:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:12) {
                    ForEach(rows) {row in quotaCard(row)}
                }
            }
            Text(L("余量来自工具报告，与本机 Token 累计独立；超过 15 分钟未更新或已重置的读数不作为当前余量。"))
                .font(AppTypography.caption).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
        }.subtlePanel(padding:18).sheet(isPresented:$connecting){ClaudeQuotaConnectionSheet(store:store,preview:model.isFanControlPreview)}
    }
    private func quotaCard(_ row:AgentQuotaWindow)->some View {
        let remaining=row.remaining(),pinned=model.hasTokenMetric(.tokenQuota,provider:row.provider.rawValue,quotaID:row.id)
        return VStack(alignment:.leading,spacing:10) {
            HStack {
                Text(row.provider.title).font(AppTypography.body)
                Spacer(minLength:6)
                Button {model.pinTokenMetric(.tokenQuota,provider:row.provider.rawValue,quotaID:row.id)} label:{Image(systemName:pinned ? "checkmark":"pin")}
                    .buttonStyle(.borderless).disabled(pinned || model.effectiveMenuComponents.count>=MenuBarComponent.limit).help(L("显示在状态栏")).accessibilityLabel(row.provider.title+" · "+QuotaFormat.window(row)+" · "+L("显示在状态栏"))
            }
            HStack(alignment:.firstTextBaseline,spacing:6) {
                Text(remaining.map{QuotaFormat.percent($0)} ?? "—").font(AppTypography.number(27,weight:.semibold)).foregroundColor(QuotaFormat.color(remaining)).appMonospacedDigit()
                Text(L(remaining==nil ? "等待更新":"剩余")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                Spacer(minLength:0)
                Text(QuotaFormat.window(row)).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            }
            GeometryReader {proxy in
                ZStack(alignment:.leading) {
                    Capsule().fill(Palette.violet.opacity(0.09))
                    if let remaining {Capsule().fill(QuotaFormat.color(remaining)).frame(width:max(0,proxy.size.width*remaining/100))}
                }
            }.frame(height:5).accessibilityLabel(L("额度余量")).accessibilityValue(remaining.map{QuotaFormat.percent($0)} ?? L("未提供"))
            HStack {
                Text(QuotaFormat.reset(row)).lineLimit(1)
                Spacer(minLength:3)
                Text(QuotaFormat.updated(row)).lineLimit(1).font(.system(size:9))
            }.font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            if !["codex","default"].contains(row.pool) {Text(row.poolName ?? row.pool).font(.system(size:10)).foregroundColor(Palette.secondaryText).lineLimit(1)}
        }.padding(14).appBackground(Palette.violet.opacity(0.045),in:RoundedRectangle(cornerRadius:12,style:.continuous))
            .help(L("工具最近报告")+" · "+ElectricityFormat.powerDate(row.observedAt))
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
        let remaining=model.tokenMenuReading(metric:.tokenQuota,configuration:quota?.token ?? TokenMenuConfiguration())
        return Button(action:onOpen) {
            HStack(spacing:12) {
                Image(systemName:"number.circle").foregroundColor(Palette.violet)
                VStack(alignment:.leading,spacing:4) {Text(L((usage?.token?.period ?? .day).currentTitle)+" Token").font(AppTypography.caption).foregroundColor(Palette.secondaryText);Text(count.text).font(AppTypography.number(18,weight:.semibold))}
                Spacer(minLength:4)
                VStack(alignment:.trailing,spacing:4) {Text(L("账户余量")).font(AppTypography.caption).foregroundColor(Palette.secondaryText);Text(remaining.text).font(AppTypography.number(18,weight:.semibold))}
                Image(systemName:"chevron.right").font(.system(size:10)).foregroundColor(Palette.secondaryText)
            }.padding(12).contentShape(Rectangle()).modifier(StatusCardSurface())
        }.buttonStyle(.plain).help(count.title+" · "+remaining.title).accessibilityLabel("Token · "+count.text+" · "+L("账户余量")+" "+remaining.text)
    }
}
