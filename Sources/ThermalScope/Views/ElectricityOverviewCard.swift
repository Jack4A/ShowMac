import SwiftUI
import ThermalCore

struct ElectricityOverviewCard:View {
    @ObservedObject var store:ElectricityHistoryStore
    let onOpen:()->Void
    private var today:ElectricityTotals {store.history.totals(source:store.source,in:ElectricityPeriod.day.interval(containing:Date()))}
    private var range:DateInterval {DateInterval(start:(store.sampledAt ?? Date()).addingTimeInterval(-120),duration:120)}
    var body:some View {
        Button(action:onOpen) {
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Label(L("今日用电"),systemImage:"bolt.fill").font(.system(size:13,weight:.medium)).foregroundColor(Palette.secondaryText)
                    Spacer()
                    Image(systemName:"chevron.right").font(.system(size:12,weight:.medium)).foregroundColor(Palette.secondaryText)
                }
                HStack(alignment:.center,spacing:22) {
                    VStack(alignment:.leading,spacing:7) {
                        MetricValue(value:today.observedSeconds>0 ? ElectricityFormat.number(today.kilowattHours,maximum:today.kilowattHours<0.001 ? 6:3):"—",unit:L("度"),size:26,unitSize:12)
                        Text(today.cost(rate:store.rate).map{L("估算电费")+" · "+ElectricityFormat.money($0,currency:store.currency)} ?? L(store.rate==nil ? "设置电价，查看费用估算":"等待用电采样"))
                            .font(AppTypography.caption).foregroundColor(Palette.secondaryText).lineLimit(1)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    VStack(alignment:.trailing,spacing:5) {
                        Text(store.watts[store.source].map{ElectricityFormat.number($0,maximum:1)+" W"} ?? "— W")
                            .font(AppTypography.number(16,weight:.medium)).appMonospacedDigit()
                        ElectricityPowerCurve(records:store.powerRecords(in:range),range:range,compact:true).frame(height:38)
                        Text(L("近 2 分钟实测功率")).font(.system(size:10)).foregroundColor(Palette.secondaryText)
                    }.frame(maxWidth:250)
                }
            }.frame(maxWidth:.infinity,alignment:.leading).subtlePanel(padding:18).contentShape(Rectangle())
        }.buttonStyle(.plain).help(L("查看用电量、电费和历史功率"))
            .accessibilityLabel(L("今日用电")+" · "+ElectricityFormat.number(today.kilowattHours,maximum:6)+" kWh")
            .accessibilityIdentifier("electricityOverviewCard")
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
