import SwiftUI
import ThermalCore

struct ElectricityUsagePage:View {
    @ObservedObject var store:ElectricityHistoryStore
    @ObservedObject var tokens:TokenUsageStore
    @State private var period:ElectricityPeriod = .day
    @State private var date=Date()
    @State private var followsCurrent=true
    @State private var powerHour = -1
    @State private var showRate=false
    @State private var showMethod=false
    private var range:DateInterval {period.interval(containing:followsCurrent ? Date():date)}
    private var total:ElectricityTotals {store.history.totals(source:store.source,in:range)}
    private var hours:[DateInterval] {ElectricityPeriod.day.chartIntervals(containing:range.start)}
    private var powerRange:DateInterval {period == .day && hours.indices.contains(powerHour) ? hours[powerHour]:range}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:12) {
                AppSegmentedPicker(title:L("统计周期"),selection:period,choices:ElectricityPeriod.allCases.map{AppChoice($0,L($0.title))},onSelect:{period=$0;powerHour = -1})
                    .accessibilityIdentifier("electricityPeriod")
                Spacer(minLength:8)
                AppChoicePicker(title:L("统计来源"),selection:Binding(get:{store.source},set:{store.selectSource($0)}),
                                choices:(store.sources.isEmpty ? [.system]:store.sources).map{AppChoice($0,L($0.title))})
                    .accessibilityIdentifier("electricitySource")
            }
            dateNavigation
            HStack(alignment:.top,spacing:14) {
                consumptionCard.frame(maxWidth:.infinity,alignment:.leading)
                tokenCard.frame(maxWidth:.infinity,alignment:.leading)
            }
            chart
            TokenUsageSection(store:tokens,range:range,period:period)
            if let issue=store.storageIssue {Label(L(issue),systemImage:"exclamationmark.triangle").font(AppTypography.caption).foregroundColor(.orange)}
            AppDisclosureGroup(L("统计说明"),isExpanded:$showMethod,inset:18) {
                VStack(alignment:.leading,spacing:9) {
                    Text(L(store.source.detail))
                    Text(L("功率随时间累计为用电量，1 度电 = 1 kWh。不同来源分别记录，不相加。"))
                    Text(L("仅统计 ShowMac 运行且连续采样的时段；睡眠、退出和读取中断不补算，历史保存在本机。"))
                    Text(L("电费按当前统一单价估算；修改电价会重新估算历史费用，不含阶梯电价、峰谷电价或适配器损耗。"))
                    Text(L("功率曲线保留带时间戳的实测峰谷点，较长周期会抽稀；采样断点不连接。"))
                    Text(L("按当前系统时区显示；跨时区的小时边界采用近似分摊。"))
                    Text(L("开始记录")+" · "+ElectricityFormat.date(store.firstDate(for:store.source) ?? store.history.createdAt))
                }.font(AppTypography.caption).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true).padding(.top,8)
            }.subtlePanel(padding:0)
        }.onChange(of:store.source){_ in powerHour = -1}
            .accessibilityElement(children:.contain)
            .accessibilityIdentifier("electricityUsagePage")
    }
    private var dateNavigation:some View {
        HStack(spacing:12) {
            Button {move(-1)} label:{Image(systemName:"chevron.left")}
                .buttonStyle(AppChoiceButtonStyle()).help(L("上一周期")).accessibilityLabel(L("上一周期"))
                .disabled([store.firstDate(for:store.source),tokens.firstDate].compactMap{$0}.min().map{range.start<=$0} ?? true)
            Text(ElectricityFormat.period(range,period:period)).font(.system(size:13,weight:.medium)).appMonospacedDigit()
            Button {move(1)} label:{Image(systemName:"chevron.right")}
                .buttonStyle(AppChoiceButtonStyle()).help(L("下一周期")).accessibilityLabel(L("下一周期")).disabled(range.end>Date())
            Spacer(minLength:0)
            Button(L(period.currentTitle)){followsCurrent=true;date=Date();powerHour = -1}.buttonStyle(AppChoiceButtonStyle())
        }
    }
    private var consumptionCard:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L("已记录用电")).font(AppTypography.body).foregroundColor(Palette.secondaryText)
            MetricValue(value:total.observedSeconds>0 ? ElectricityFormat.number(total.kilowattHours,maximum:total.kilowattHours<0.001 ? 6:3):"—",unit:L("度"),size:28,unitSize:12)
            Text(L("已记录")+" · "+ElectricityFormat.duration(total.observedSeconds)).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            HStack(spacing:8) {
                Text(total.cost(rate:store.rate).map{L("估算电费")+" "+ElectricityFormat.money($0,currency:store.currency)} ?? L("尚未设置电价")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                Spacer(minLength:0)
                Button(L(store.rate==nil ? "设置电价":"修改电价")){showRate=true}.buttonStyle(.borderless).font(AppTypography.caption)
                    .accessibilityIdentifier("electricityRateButton")
                    .popover(isPresented:$showRate) {ElectricityRateEditor(store:store,onClose:{showRate=false})}
            }
        }.frame(maxWidth:.infinity,minHeight:118,alignment:.leading).subtlePanel(padding:18)
    }
    private var tokenCard:some View {
        let report=tokens.report(in:range,period:period)
        return VStack(alignment:.leading,spacing:12) {
            Text(L("Token 用量")+" · "+L("全部工具")).font(AppTypography.body).foregroundColor(Palette.secondaryText)
            Text(tokens.hasScanned && !tokens.snapshot.events.isEmpty ? TokenFormat.compact(report.counts.total):"—").font(AppTypography.number(28,weight:.semibold)).appMonospacedDigit()
            Text(L("输入")+" "+TokenFormat.compact(report.counts.input)+" · "+L("输出")+" "+TokenFormat.compact(report.counts.output)).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            Text(L("其中缓存读取")+" "+TokenFormat.compact(report.counts.cacheRead)).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
        }.frame(maxWidth:.infinity,minHeight:118,alignment:.leading).subtlePanel(padding:18)
    }
    private var chart:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text(L("实测功率")).font(AppTypography.section)
                Text("W").font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                Spacer()
                if period == .day {
                    AppChoicePicker(title:L("功率时段"),selection:$powerHour,
                                    choices:[AppChoice(-1,L("全天"))]+hours.indices.map{AppChoice($0,ElectricityFormat.hourRange(hours[$0]))},
                                    listWidth:190,maximumListHeight:280)
                        .accessibilityIdentifier("electricityPowerHour")
                }
            }
            ElectricityPowerCurve(records:store.powerRecords(in:powerRange),range:powerRange)
                .frame(height:235).id("\(store.source.rawValue):\(powerRange.start.timeIntervalSince1970):\(powerRange.end.timeIntervalSince1970)")
            if store.powerRecords(in:powerRange).isEmpty,total.observedSeconds>0 {
                Text(L("此时段只有电量汇总，尚无实测功率明细。"))
                    .font(AppTypography.caption).foregroundColor(Palette.secondaryText)
            }
        }.subtlePanel(padding:18)
    }
    private func move(_ offset:Int) {
        if let next=Calendar.current.date(byAdding:period.component,value:offset,to:range.start) {followsCurrent=false;date=next;powerHour = -1}
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

enum ElectricityFormat {
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
    static func powerDate(_ date:Date)->String {
        let formatter=DateFormatter();formatter.locale=locale;formatter.dateStyle = .short;formatter.timeStyle = .medium;return formatter.string(from:date)
    }
    static func powerAxis(_ date:Date,duration:Double)->String {formatted(date,template:duration<=90000 ? "Hm":(duration<=32*86400 ? "MMM d":"MMM"))}
    static func hourRange(_ range:DateInterval)->String {
        let formatter=DateFormatter();formatter.locale=locale;formatter.dateFormat="HH:mm"
        return formatter.string(from:range.start)+"–"+formatter.string(from:range.end)
    }
    private static func formatted(_ date:Date,template:String)->String {
        let formatter=DateFormatter();formatter.locale=locale;formatter.setLocalizedDateFormatFromTemplate(template);return formatter.string(from:date)
    }
}
