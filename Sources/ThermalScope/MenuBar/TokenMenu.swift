import AppKit
import SwiftUI
import ThermalCore

struct TokenMenuConfiguration:Codable,Equatable {
    var provider="all"
    var period:ElectricityPeriod = .day
    var quotaID:String?
    init(provider:String="all",period:ElectricityPeriod = .day,quotaID:String?=nil){self.provider=provider;self.period=period;self.quotaID=quotaID}
    private enum CodingKeys:String,CodingKey {case provider,period,quotaID}
    init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        provider=(try? c.decode(String.self,forKey:.provider)) ?? "all"
        period=(try? c.decode(ElectricityPeriod.self,forKey:.period)) ?? .day
        quotaID=try? c.decode(String.self,forKey:.quotaID)
        self=self.normalized()
    }
    var tool:TokenProvider? {TokenProvider(rawValue:provider)}
    func normalized()->Self {
        var value=self
        if provider != "all",tool==nil {value.provider="all"}
        if let quotaID,quotaID.utf8.count>256 {value.quotaID=nil}
        return value
    }
}
struct TokenMenuReading {
    let title:String
    let text:String
    let number:Double?
    let points:[MetricPoint]
    let range:DateInterval?
    let upper:Double
}
extension MenuMetric {var isToken:Bool {self == .tokens || self == .tokenQuota}}
extension AppModel {
    func tokenMenuReading(metric:MenuMetric,configuration:TokenMenuConfiguration=TokenMenuConfiguration(),at now:Date=Date())->TokenMenuReading {
        let config=configuration.normalized()
        if metric == .tokenQuota {
            let tool=config.tool ?? .codex
            let windows=tokens.quotas.filter{$0.provider==tool}
            let shared=windows.filter{$0.pool=="codex" || $0.pool=="default"}
            let candidates=shared.isEmpty ? windows:shared
            let window:AgentQuotaWindow?
            if let id=config.quotaID {window=windows.first{$0.id==id}}
            else {window=candidates.filter{$0.remaining(at:now) != nil}.min{($0.remaining(at:now) ?? 101)<($1.remaining(at:now) ?? 101)}}
            let value=window?.remaining(at:now)
            let pool=window.flatMap{["codex","default"].contains($0.pool) ? nil:($0.poolName ?? $0.pool)}
            let title=tool.title+(pool.map{" · "+$0} ?? "")+" · "+L("额度余量")+(window.map{" · "+QuotaFormat.window($0)} ?? "")
            return TokenMenuReading(title:title,text:value.map{QuotaFormat.percent($0)} ?? "—",number:value,points:[],range:nil,upper:100)
        }
        let range=config.period.interval(containing:now)
        let report=tokens.report(in:range,provider:config.tool,period:config.period)
        let hasData=tokens.hasScanned && tokens.enabled && (config.tool.map{tokens.state(for:$0)=="ready"} ?? !tokens.snapshot.events.isEmpty)
        let end=min(now,range.end)
        let points=hasData ? report.buckets.filter{$0.interval.start<=end}.map{MetricPoint(date:$0.interval.start,value:Double($0.counts.total),segment:0)}:[]
        let title=(config.tool?.title ?? L("全部工具"))+" · "+L(config.period.currentTitle)+" Token"
        return TokenMenuReading(title:title,text:hasData ? TokenFormat.compact(report.counts.total):"—",number:hasData ? Double(report.counts.total):nil,points:points,range:DateInterval(start:range.start,end:max(range.start.addingTimeInterval(1),end)),upper:max(1,points.compactMap(\.value).max() ?? 0))
    }
    func pinTokenMetric(_ metric:MenuMetric,provider:String="all",period:ElectricityPeriod = .day,quotaID:String?=nil) {
        let configuration=TokenMenuConfiguration(provider:provider,period:period,quotaID:quotaID).normalized()
        guard !effectiveMenuComponents.contains(where:{$0.metric==metric && ($0.token ?? TokenMenuConfiguration())==configuration}) else{return}
        guard insertMenuComponent(metric:metric,style:.iconValue),let id=effectiveMenuComponents.last?.id else{return}
        updateMenuComponent(id:id){$0.token=configuration}
    }
    func hasTokenMetric(_ metric:MenuMetric,provider:String="all",period:ElectricityPeriod = .day,quotaID:String?=nil)->Bool {
        let config=TokenMenuConfiguration(provider:provider,period:period,quotaID:quotaID).normalized()
        return effectiveMenuComponents.contains{$0.metric==metric && ($0.token ?? TokenMenuConfiguration())==config}
    }
}
struct TokenMenuControls:View {
    @ObservedObject var model:AppModel
    @ObservedObject var store:TokenUsageStore
    let id:String
    let metric:MenuMetric
    init(model:AppModel,id:String,metric:MenuMetric){self.model=model;self.store=model.tokens;self.id=id;self.metric=metric}
    private var config:TokenMenuConfiguration {model.effectiveMenuComponents.first{$0.id==id}?.token ?? TokenMenuConfiguration()}
    private func change(_ block:(inout TokenMenuConfiguration)->Void) {model.updateMenuComponent(id:id){component in var value=component.token ?? TokenMenuConfiguration();block(&value);component.token=value.normalized()}}
    var body:some View {
        Section(header:Text(L("统计内容"))) {
            HStack {
                Text(L("AI 工具"));Spacer()
                AppChoicePicker(title:L("AI 工具"),selection:Binding(get:{config.provider},set:{p in change{$0.provider=p;$0.quotaID=nil}}),choices:choices,listWidth:220,maximumListHeight:260)
            }
            if metric == .tokens {
                HStack {
                    Text(L("统计周期"));Spacer()
                    AppChoicePicker(title:L("统计周期"),selection:Binding(get:{config.period},set:{p in change{$0.period=p}}),choices:ElectricityPeriod.allCases.map{AppChoice($0,L($0.currentTitle))})
                }
            } else {
                HStack {
                    Text(L("额度周期"));Spacer()
                    AppChoicePicker(title:L("额度周期"),selection:Binding<String?>(get:{config.quotaID},set:{id in change{$0.quotaID=id}}),choices:[AppChoice<String?>(nil,L("最紧张的额度"))]+store.quotas.filter{$0.provider==(config.tool ?? .codex)}.map{AppChoice(Optional($0.id),QuotaFormat.window($0))})
                }
                Text(L("余量来自工具报告的百分比，未提供或已过期时显示 —。"))
                    .font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            }
        }
    }
    private var choices:[AppChoice<String>] {
        if metric == .tokens {return [AppChoice("all",L("全部工具"))]+TokenProvider.allCases.map{AppChoice($0.rawValue,$0.title)}}
        let tools=Set(store.quotas.map(\.provider)+[.codex,.claude]).sorted{$0.title<$1.title}
        return [AppChoice("all",L("Codex（默认）"))]+tools.map{AppChoice($0.rawValue,$0.title)}
    }
}

struct TokenPinButton:View {
    @ObservedObject var model:AppModel
    let provider:String
    let period:ElectricityPeriod
    private var pinned:Bool {model.hasTokenMetric(.tokens,provider:provider,period:period)}
    var body:some View {
        Button {model.pinTokenMetric(.tokens,provider:provider,period:period)} label:{Image(systemName:pinned ? "checkmark":"pin")}
            .buttonStyle(AppChoiceButtonStyle()).disabled(pinned || model.effectiveMenuComponents.count>=MenuBarComponent.limit)
            .help(L("显示在状态栏")).accessibilityLabel(L("Token 用量加入状态栏")).accessibilityIdentifier("pinTokenUsage")
    }
}
