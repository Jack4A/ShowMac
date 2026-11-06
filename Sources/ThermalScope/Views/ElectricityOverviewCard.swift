import SwiftUI
import ThermalCore

struct ElectricityOverviewCard:View {
    @ObservedObject var store:ElectricityHistoryStore
    @ObservedObject var tokens:TokenUsageStore
    let onOpen:()->Void
    var onTokens:(()->Void)?=nil
    private var range:DateInterval {ElectricityPeriod.day.interval(containing:Date())}
    private var today:ElectricityTotals {store.history.totals(source:store.source,in:range)}
    private var energyValue:String {
        today.observedSeconds>0 ? ElectricityFormat.number(today.kilowattHours,maximum:3)+" "+L("度"):"—"
    }
    private var tokenCount:Int64 {tokens.report(in:range).counts.total}
    private var tokenValue:String {tokens.hasScanned && !tokens.snapshot.events.isEmpty ? TokenFormat.compact(tokenCount):"—"}
    private var accessibilitySummary:String {
        let energy=ElectricityFormat.number(today.kilowattHours,maximum:3)
        let count=TokenFormat.number(tokenCount)
        return L("用量统计")+" · "+energy+" kWh · "+count+" tokens"
    }
    var body:some View {
        HStack(spacing:16) {
            Button(action:onOpen) {
                HStack(spacing:14) {
                    Image(systemName:"bolt.fill").foregroundColor(Palette.violet).font(.system(size:16))
                    energySummary
                    Spacer(minLength:0)
                    Image(systemName:"chevron.right").font(.system(size:10)).foregroundColor(Palette.secondaryText)
                }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(L("今日用电")+" · "+energyValue)
            Divider().frame(height:32)
            Button(action:onTokens ?? onOpen) {
                HStack(spacing:14) {
                    Image(systemName:"number.circle").foregroundColor(Palette.violet).font(.system(size:17))
                    tokenSummary
                    Spacer(minLength:0)
                    Image(systemName:"chevron.right").font(.system(size:10)).foregroundColor(Palette.secondaryText)
                }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(L("今日 Token")+" · "+tokenValue)
        }.subtlePanel(padding:16).accessibilityElement(children:.contain).accessibilityIdentifier("electricityOverviewCard")
    }
    private var energySummary:some View {
        VStack(alignment:.leading,spacing:5) {
            Text(L("今日用电")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            HStack(spacing:8) {
                Text(energyValue).font(AppTypography.number(17,weight:.semibold))
                if let cost=today.cost(rate:store.rate) {
                    Text(ElectricityFormat.money(cost,currency:store.currency)).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                }
            }
        }
    }
    private var tokenSummary:some View {
        VStack(alignment:.leading,spacing:5) {
            Text(L("今日 Token")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            Text(tokenValue).font(AppTypography.number(17,weight:.semibold)).appMonospacedDigit()
        }
    }

}

struct ElectricityPowerCurve:View {
    let records:[MetricPoint]
    let range:DateInterval
    var compact=false
    private let groups:[Int:[MetricPoint]]
    private let series:[MetricPlotView.Series]
    @State private var inspected:MetricPoint?
    init(records:[MetricPoint],range:DateInterval,compact:Bool=false) {
        self.records=records;self.range=range;self.compact=compact
        groups=Dictionary(grouping:records,by:\.segment)
        let visible=MetricPlot.decimated(records,budget:compact ? 50:500)
        let grouped=Dictionary(grouping:visible,by:\.segment)
        series=grouped.keys.sorted().map {segment in
            let points=grouped[segment]!
            return MetricPlotView.Series(id:"power:\(segment)",points:points.compactMap{point in point.value.map{.init(x:point.date.timeIntervalSince1970,y:$0,segment:segment)}},color:Palette.violet,filled:true,markers:points.count==1)
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            MetricPlotView(series:series,xRange:range.start.timeIntervalSince1970...range.end.timeIntervalSince1970,
                           yRange:MetricPlot.scale(records.compactMap(\.value),automatic:true,upper:100),axes:!compact,
                           xTicks:compact ? nil:(0...4).map{range.start.timeIntervalSince1970+range.duration*Double($0)/4},
                           xLabel:{ElectricityFormat.powerAxis(Date(timeIntervalSince1970:$0),duration:range.duration)},
                           selection:inspected.flatMap{point in point.value.map{.init(x:point.date.timeIntervalSince1970,y:$0)}},
                           placeholder:compact ? nil:L("尚无实测功率明细"),onInspect:compact ? nil:inspect)
                .accessibilityLabel(L("实测功率曲线"))
            if !compact {
                HStack(spacing:10) {
                    if let inspected,let watts=inspected.value {
                        Text(ElectricityFormat.number(watts,maximum:2)+" W").font(AppTypography.number(17,weight:.semibold))
                        Text(ElectricityFormat.powerDate(inspected.date)).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                    } else {Text(L("悬停或点击查看实测时间与功率")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)}
                    Spacer(minLength:0)
                }.appMonospacedDigit().frame(minHeight:24)
            }
        }
    }
    private func inspect(_ value:Double?) {
        guard let value else{inspected=nil;return}
        inspected=ElectricityPowerHistory.nearest(in:groups,at:Date(timeIntervalSince1970:value),pointTolerance:range.duration/600)
    }
}
