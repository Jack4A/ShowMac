import SwiftUI
import ThermalCore

struct ElectricityUsagePage:View {
    @ObservedObject var store:ElectricityHistoryStore
    @State private var period:ElectricityPeriod = .day
    @State private var date=Date()
    @State private var followsCurrent=true
    @State private var selected:Date?
    @State private var showRate=false
    @State private var showMethod=false
    private var range:DateInterval {period.interval(containing:followsCurrent ? Date():date)}
    private var total:ElectricityTotals {store.history.totals(source:store.source,in:range)}
    private var bars:[ElectricityBar] {period.chartIntervals(containing:range.start).map{ElectricityBar(interval:$0,total:store.history.totals(source:store.source,in:$0))}}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:12) {
                AppSegmentedPicker(title:L("统计周期"),selection:period,choices:ElectricityPeriod.allCases.map{AppChoice($0,L($0.title))},onSelect:{period=$0;selected=nil})
                    .accessibilityIdentifier("electricityPeriod")
                Spacer(minLength:8)
                AppChoicePicker(title:L("统计来源"),selection:Binding(get:{store.source},set:{store.selectSource($0)}),
                                choices:(store.sources.isEmpty ? [.system]:store.sources).map{AppChoice($0,L($0.title))})
                    .accessibilityIdentifier("electricitySource")
            }
            dateNavigation
            HStack(alignment:.top,spacing:14) {
                consumptionCard.frame(maxWidth:.infinity,alignment:.leading)
                costCard.frame(maxWidth:.infinity,alignment:.leading)
            }
            chart
            if let issue=store.storageIssue {Label(L(issue),systemImage:"exclamationmark.triangle").font(AppTypography.caption).foregroundColor(.orange)}
            AppDisclosureGroup(L("统计说明"),isExpanded:$showMethod,inset:18) {
                VStack(alignment:.leading,spacing:9) {
                    Text(L(store.source.detail))
                    Text(L("功率随时间累计为用电量，1 度电 = 1 kWh。不同来源分别记录，不相加。"))
                    Text(L("仅统计 ShowMac 运行且连续采样的时段；睡眠、退出和读取中断不补算，历史保存在本机。"))
                    Text(L("电费按当前统一单价估算；修改电价会重新估算历史费用，不含阶梯电价、峰谷电价或适配器损耗。"))
                    Text(L("按当前系统时区显示；跨时区的小时边界采用近似分摊。"))
                    Text(L("开始记录")+" · "+ElectricityFormat.date(store.history.firstDate(for:store.source) ?? store.history.createdAt))
                }.font(AppTypography.caption).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true).padding(.top,8)
            }.subtlePanel(padding:0)
        }.onChange(of:store.source){_ in selected=nil}
            .accessibilityElement(children:.contain)
            .accessibilityIdentifier("electricityUsagePage")
    }
    private var dateNavigation:some View {
        HStack(spacing:12) {
            Button {move(-1)} label:{Image(systemName:"chevron.left")}
                .buttonStyle(AppChoiceButtonStyle()).help(L("上一周期")).accessibilityLabel(L("上一周期"))
                .disabled(store.history.firstDate(for:store.source).map{range.start<=$0} ?? true)
            Text(ElectricityFormat.period(range,period:period)).font(.system(size:13,weight:.medium)).appMonospacedDigit()
            Button {move(1)} label:{Image(systemName:"chevron.right")}
                .buttonStyle(AppChoiceButtonStyle()).help(L("下一周期")).accessibilityLabel(L("下一周期")).disabled(range.end>Date())
            Spacer(minLength:0)
            Button(L(period.currentTitle)){followsCurrent=true;date=Date();selected=nil}.buttonStyle(AppChoiceButtonStyle())
        }
    }
    private var consumptionCard:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L("已记录用电")).font(AppTypography.body).foregroundColor(Palette.secondaryText)
            MetricValue(value:total.observedSeconds>0 ? ElectricityFormat.number(total.kilowattHours,maximum:total.kilowattHours<0.001 ? 6:3):"—",unit:L("度"),size:28,unitSize:12)
            Text(L("已记录")+" · "+ElectricityFormat.duration(total.observedSeconds)).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            HStack(spacing:5) {
                Text(L("当前功率"))
                Text(store.watts[store.source].map{ElectricityFormat.number($0,maximum:1)+" W"} ?? L("暂无读数")).appMonospacedDigit()
            }.font(AppTypography.caption).foregroundColor(Palette.secondaryText)
        }.frame(maxWidth:.infinity,minHeight:118,alignment:.leading).subtlePanel(padding:18)
    }
    private var costCard:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(L("估算电费")).font(AppTypography.body).foregroundColor(Palette.secondaryText)
                Spacer(minLength:4)
                Button(L(store.rate==nil ? "设置电价":"修改电价")){showRate=true}.buttonStyle(.borderless).font(AppTypography.caption)
                    .accessibilityIdentifier("electricityRateButton")
                    .popover(isPresented:$showRate) {ElectricityRateEditor(store:store,onClose:{showRate=false})}
            }
            Text(total.cost(rate:store.rate).map{ElectricityFormat.money($0,currency:store.currency)} ?? "—")
                .font(AppTypography.number(28,weight:.medium)).appMonospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(store.rate.map{ElectricityFormat.money($0,currency:store.currency)+L(" / 度")} ?? L("填写每度电价格后显示估算费用。"))
                .font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            Text(L("采样估算，非实际账单")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
        }.frame(maxWidth:.infinity,minHeight:118,alignment:.leading).subtlePanel(padding:18)
    }
    private var chart:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text(L("用电趋势")).font(AppTypography.section)
                Spacer()
                Text(L("度 / kWh")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            }
            ElectricityBarChart(bars:bars,period:period,selected:$selected)
            if let selected,let bar=bars.first(where:{$0.interval.start==selected}) {
                HStack(spacing:10) {
                    Text(ElectricityFormat.barDate(selected,period:period))
                    Text(bar.total.observedSeconds>0 ? ElectricityFormat.number(bar.total.kilowattHours,maximum:6)+" "+L("度"):L("未采样"))
                    Spacer()
                    Text(L("已记录")+" · "+ElectricityFormat.duration(bar.total.observedSeconds))
                }.font(AppTypography.caption).foregroundColor(Palette.secondaryText).appMonospacedDigit()
            } else {
                Text(L(total.observedSeconds>0 ? "悬停或点击查看分时用电；空白时段未采样。":"尚无可累计的采样，连续运行片刻后显示。"))
                    .font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            }
            if store.watts[store.source]==nil {
                Text(L("当前来源暂无可读功率，已有历史仍会保留。"))
                    .font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            }
        }.subtlePanel(padding:18)
    }
    private func move(_ offset:Int) {
        if let next=Calendar.current.date(byAdding:period.component,value:offset,to:range.start) {followsCurrent=false;date=next;selected=nil}
    }
}

private struct ElectricityBar:Identifiable {
    let interval:DateInterval
    let total:ElectricityTotals
    var id:Date {interval.start}
}
private struct ElectricityBarChart:View {
    let bars:[ElectricityBar]
    let period:ElectricityPeriod
    @Binding var selected:Date?
    private var upper:Double {max(0.000001,bars.map{$0.total.kilowattHours}.max() ?? 0)}
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(ElectricityFormat.number(upper,maximum:upper<0.001 ? 6:3)).font(.system(size:10)).foregroundColor(Palette.secondaryText)
            HStack(alignment:.bottom,spacing:period == .month ? 4:6) {
                ForEach(Array(bars.enumerated()),id:\.element.id) {index,bar in
                    Button {selected=bar.id} label:{
                        VStack(spacing:8) {
                            ZStack(alignment:.bottom) {
                                Rectangle().fill(Palette.border.opacity(0.25)).frame(height:1)
                                RoundedRectangle(cornerRadius:3,style:.continuous)
                                    .fill(Palette.violet.opacity(selected==bar.id ? 1:0.7))
                                    .frame(height:bar.total.observedSeconds>0 ? max(2,CGFloat(bar.total.kilowattHours/upper)*138):0)
                            }.frame(height:140,alignment:.bottom)
                            Text(tick(index,bar)).font(.system(size:9)).foregroundColor(Palette.secondaryText).lineLimit(1).frame(height:14)
                        }.frame(maxWidth:.infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain).onHover{if $0 {selected=bar.id}}
                        .accessibilityLabel(ElectricityFormat.barDate(bar.id,period:period))
                        .accessibilityValue(bar.total.observedSeconds>0 ? ElectricityFormat.number(bar.total.kilowattHours,maximum:6)+" kWh":L("未采样"))
                }
            }
        }
    }
    private func tick(_ index:Int,_ bar:ElectricityBar)->String {
        if period == .day {return index%4==0 ? String(Calendar.current.component(.hour,from:bar.id)):""}
        if period == .month {return index==0 || (index+1)%5==0 ? String(index+1):""}
        return ElectricityFormat.shortDate(bar.id,period:period)
    }
}

private struct ElectricityRateEditor:View {
    @ObservedObject var store:ElectricityHistoryStore
    let onClose:()->Void
    @State private var text:String
    @State private var currency:String
    init(store:ElectricityHistoryStore,onClose:@escaping ()->Void) {
        self.store=store;self.onClose=onClose
        _text=State(initialValue:store.rate.map{ElectricityFormat.number($0,maximum:4)} ?? "")
        _currency=State(initialValue:store.currency)
    }
    private var rate:Double? {
        let separator=Locale(identifier:AppLocalization.shared.resolvedLanguage).decimalSeparator ?? "."
        let clean=text.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:separator,with:".")
        guard !clean.isEmpty,clean.allSatisfy({"0123456789.".contains($0)}),clean.filter({$0=="."}).count<=1,
              let value=Double(clean),value.isFinite,(0...10000).contains(value) else{return nil}
        return value
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text(L("设置电价")).font(AppTypography.section)
            HStack(spacing:8) {
                AppChoicePicker(title:L("币种"),selection:$currency,choices:["CNY","USD","EUR","GBP","JPY","HKD"].map{AppChoice($0,$0)})
                TextField(L("例如 0.60"),text:$text).textFieldStyle(.roundedBorder).frame(width:100)
                    .accessibilityLabel(L("每度电单价")).accessibilityIdentifier("electricityRateInput")
                Text(L(" / 度")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            }
            Text(L("按统一单价估算；历史费用也会随单价更新。"))
                .font(AppTypography.caption).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
            HStack {
                Button(L("取消"),action:onClose).buttonStyle(AppNativeButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("保存")){if let rate {store.rate=rate;store.currency=currency;onClose()}}
                    .buttonStyle(AppChoiceButtonStyle()).disabled(rate==nil).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("saveElectricityRate")
            }
        }.padding(18).frame(width:300).background(Palette.surface)
    }
}

private enum ElectricityFormat {
    static var locale:Locale {Locale(identifier:AppLocalization.shared.resolvedLanguage)}
    static func number(_ value:Double,maximum:Int)->String {
        let formatter=NumberFormatter();formatter.locale=locale;formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator=false;formatter.maximumFractionDigits=maximum
        return formatter.string(from:NSNumber(value:value)) ?? "—"
    }
    static func money(_ value:Double,currency:String)->String {
        let formatter=NumberFormatter();formatter.locale=locale;formatter.numberStyle = .currency
        formatter.currencyCode=currency;formatter.minimumFractionDigits=2;formatter.maximumFractionDigits=value<0.01 ? 6:4
        return formatter.string(from:NSNumber(value:value)) ?? "—"
    }
    static func duration(_ seconds:Double)->String {
        let value=max(0,Int(seconds.rounded(.down)))
        if value<60 {return String(format:L("%d 秒"),value)}
        if value<3600 {return String(format:L("%d 分钟"),value/60)}
        return String(format:L("%d 小时 %d 分钟"),value/3600,value%3600/60)
    }
    static func date(_ date:Date)->String {
        let formatter=DateFormatter();formatter.locale=locale;formatter.dateStyle = .medium;formatter.timeStyle = .none;return formatter.string(from:date)
    }
    static func period(_ range:DateInterval,period:ElectricityPeriod)->String {
        if period == .day {return date(range.start)}
        if period == .week {return date(range.start)+" – "+date(range.end.addingTimeInterval(-1))}
        return formatted(range.start,template:period == .month ? "yMMMM":"y")
    }
    static func shortDate(_ date:Date,period:ElectricityPeriod)->String {formatted(date,template:period == .year ? "MMM":"EEE")}
    static func barDate(_ date:Date,period:ElectricityPeriod)->String {formatted(date,template:period == .day ? "MMMdhm":(period == .year ? "yMMMM":"MMM d EEE"))}
    private static func formatted(_ date:Date,template:String)->String {
        let formatter=DateFormatter();formatter.locale=locale;formatter.setLocalizedDateFormatFromTemplate(template);return formatter.string(from:date)
    }
}
