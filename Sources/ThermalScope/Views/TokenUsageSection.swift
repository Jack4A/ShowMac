import SwiftUI
import ThermalCore

struct TokenUsageSection:View {
    @ObservedObject var store:TokenUsageStore
    let range:DateInterval
    let period:ElectricityPeriod
    var model:AppModel?=nil
    @State private var provider="all"
    @State private var selected:Date?
    @State private var sources=false
    @State private var models=false
    @State private var sourceSearch=""
    @State private var showAllSources=false
    private var visibleSources:[TokenProvider] {
        TokenProvider.allCases.filter {provider in
            let matches=sourceSearch.isEmpty || provider.title.localizedCaseInsensitiveContains(sourceSearch) || provider.rawValue.localizedCaseInsensitiveContains(sourceSearch)
            return matches && (showAllSources || !sourceSearch.isEmpty || store.state(for:provider)=="ready")
        }
    }
    private var selectedSourceUnavailable:Bool {
        guard let source=TokenProvider(rawValue:provider) else{return false}
        return store.state(for:source) != "ready"
    }
    private var emptyTitle:String {
        if store.isScanning {return "正在读取本机用量日志…"}
        if store.snapshot.unreadable>0 {return "暂时无法读取 Agent 用量，请重试"}
        if store.enabled,selectedSourceUnavailable {return "未检测到该工具的本机用量"}
        return store.enabled ? "未找到可统计的 Token 日志":"Token 统计已暂停"
    }
    private var report:TokenUsageReport {store.report(in:range,provider:TokenProvider(rawValue:provider),period:period)}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Label(L("Token 用量"),systemImage:"number.circle").font(AppTypography.section)
                Spacer()
                AppChoicePicker(title:L("AI 工具"),selection:$provider,choices:[AppChoice("all",L("全部工具"))]+TokenProvider.allCases.map{AppChoice($0.rawValue,$0.title)},listWidth:230,maximumListHeight:280)
                    .accessibilityIdentifier("tokenProvider")
                if let model {
                    TokenPinButton(model:model,provider:provider,period:period)
                }
                Button{store.refresh()}label:{Image(systemName:"arrow.clockwise")}.buttonStyle(AppChoiceButtonStyle()).disabled(store.isScanning || !store.enabled).help(L("刷新 Token 统计"))
            }
            if !store.hasScanned || store.snapshot.events.isEmpty || selectedSourceUnavailable {
                VStack(alignment:.leading,spacing:10) {
                    Text(L(emptyTitle)).font(AppTypography.body)
                    Text(L("通过 Tokscale 支持 60 类工具的本机用量；部分来源需要导出文件或已有同步缓存。没有数据时会明确提示。"))
                        .font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                }.frame(maxWidth:.infinity,minHeight:90,alignment:.leading)
            } else {
                HStack(alignment:.firstTextBaseline,spacing:10) {
                    Text(TokenFormat.compact(report.counts.total)).font(AppTypography.number(30,weight:.semibold))
                    Text("tokens").font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                    Spacer()
                    Text(L("用量记录")+" · "+TokenFormat.number(Int64(report.events.count))).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                }.accessibilityElement(children:.combine)
                HStack(spacing:12) {
                    tokenStat("输入",report.counts.input,symbol:"arrow.down.left",tint:Palette.violet)
                    tokenStat("输出",report.counts.output,symbol:"arrow.up.right",tint:Color(red:0.39,green:0.43,blue:0.76))
                    tokenStat("其中缓存读取",report.counts.cacheRead,symbol:"arrow.triangle.2.circlepath",tint:Color(red:0.20,green:0.57,blue:0.58))
                }
                chart
                if provider=="all",toolDistribution.count>1 {distribution}
                if let bucket=report.buckets.first(where:{$0.id==selected}) {
                    HStack(spacing:10) {
                        Text(ElectricityFormat.powerDate(bucket.id)).foregroundColor(Palette.secondaryText)
                        Text(TokenFormat.number(bucket.counts.total)+" tokens")
                        Spacer(minLength:0)
                    }.font(AppTypography.caption).appMonospacedDigit()
                } else {Text(L("悬停或点击查看分时 Token 用量")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)}
                AppDisclosureGroup(L("按模型查看"),isExpanded:$models) {
                    VStack(spacing:10) {
                        ForEach(report.models) {model in
                            HStack(spacing:12) {
                                VStack(alignment:.leading,spacing:3) {
                                    Text(model.model.isEmpty ? L("未记录模型"):model.model).font(AppTypography.body)
                                    Text(model.provider.title).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                                }
                                Spacer(minLength:8)
                                Text(TokenFormat.number(model.counts.total)).font(AppTypography.number(13,weight:.medium)).appMonospacedDigit()
                            }
                        }
                        if report.counts.cacheWrite>0 {tokenLabel("其中缓存写入",report.counts.cacheWrite)}
                        if report.counts.reasoning>0 {tokenLabel("其中推理输出",report.counts.reasoning)}
                    }.padding(.top,12)
                }
            }
            if store.snapshot.unreadable+store.snapshot.malformed+store.snapshot.unresolvedForks>0 {
                Label(L("部分日志无法读取或不完整，当前结果可能不完整。"),systemImage:"exclamationmark.triangle").font(AppTypography.caption).foregroundColor(.orange)
            }
            HStack {
                Text(L("本机记录与上游估算，非账户额度或实际账单")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                Spacer()
                if store.hasScanned {Text(ElectricityFormat.powerDate(store.snapshot.scannedAt)).font(.system(size:10)).foregroundColor(Palette.secondaryText)}
            }
            AppDisclosureGroup(L("数据来源与统计口径"),isExpanded:$sources) {
                VStack(alignment:.leading,spacing:12) {
                    Toggle(L("本机 Token 统计"),isOn:$store.enabled).toggleStyle(.checkbox)
                    HStack {
                        TextField(L("搜索 Agent…"),text:$sourceSearch).textFieldStyle(.roundedBorder).frame(maxWidth:260)
                        Spacer()
                        Toggle(L("显示全部支持的工具"),isOn:$showAllSources).toggleStyle(.checkbox)
                    }
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:14) {
                            ForEach(visibleSources) {provider in sourceRow(provider)}
                        }.padding(.trailing,6)
                    }.frame(height:min(300,CGFloat(max(1,visibleSources.count))*66))
                    Text(L("Cursor 读取本机 Tokscale 已同步的用量缓存；ShowMac 不会登录或自动同步账户。部分工具由上游根据文本估算 Token，并非精确账单。"))
                    Link("Tokscale · MIT",destination:URL(string:"https://github.com/junhoyeo/tokscale")!).font(AppTypography.caption)
                    Button(L("恢复默认日志位置")){store.resetDirectories()}.buttonStyle(.borderless)
                    Text(L("随包原生引擎每分钟检查日志变化，后台更新并复用缓存；只保存用量元数据，不保存对话内容或读取登录密钥。"))
                    Text(L("总量 = 输入 + 输出 + 未细分 Token（若有）；缓存与推理已包含在对应分类内，不重复相加。未提供分类的数据会单独标明。"))
                    Text(L("解析和去重直接复用 Tokscale。部分来源包含上游估算值；删除本机日志会改变覆盖范围。统计不代表账户额度或实际账单。"))
                    Text(L("仅支持日志中实际记录的用量；其他设备、网页聊天和未记录的请求不会自动计入。"))
                }.font(AppTypography.caption).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true).padding(.top,12)
            }
        }.subtlePanel(padding:18).onChange(of:range.start){_ in selected=nil}.onChange(of:provider){_ in selected=nil}
            .accessibilityElement(children:.contain).accessibilityIdentifier("tokenUsageSection")
    }
    private func sourceStateTitle(_ provider:TokenProvider)->String {
        switch store.state(for:provider) {
        case "ready":return "已检测到"
        case "error":return "读取失败"
        case "pending":return "等待扫描"
        default:return "未检测到用量"
        }
    }
    private func sourceRow(_ provider:TokenProvider)->some View {
        HStack(alignment:.top,spacing:12) {
            VStack(alignment:.leading,spacing:4) {
                HStack(spacing:8) {
                    Text(provider.title).font(AppTypography.body)
                    Text(L(sourceStateTitle(provider))).font(AppTypography.caption)
                }
                Text(store.location(for:provider)).font(AppTypography.caption).appTextSelection().lineLimit(2)
            }
            Spacer(minLength:4)
            if provider.supportsCustom {Button(L("选择文件夹…")){store.chooseDirectory(for:provider)}.buttonStyle(.borderless)}
        }.foregroundColor(Palette.secondaryText)
    }
    private var toolDistribution:[(TokenProvider,Int64)] {
        var values:[TokenProvider:Int64]=[:]
        for event in report.events {values[event.provider,default:0]+=event.counts.total}
        return values.sorted{$0.value>$1.value}.map{($0.key,$0.value)}
    }
    private var distribution:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L("工具分布")).font(AppTypography.body)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:12) {
                ForEach(Array(toolDistribution.prefix(6).enumerated()),id:\.element.0.rawValue) {index,item in
                    VStack(alignment:.leading,spacing:6) {
                        HStack {Text(item.0.title).lineLimit(1);Spacer();Text(TokenFormat.compact(item.1)).appMonospacedDigit().foregroundColor(Palette.secondaryText)}
                        GeometryReader {proxy in
                            ZStack(alignment:.leading) {Capsule().fill(Palette.violet.opacity(0.06));Capsule().fill(Palette.violet.opacity(index==0 ? 0.9:0.45)).frame(width:max(1,proxy.size.width*Double(item.1)/Double(max(1,report.counts.total))))}
                        }.frame(height:4)
                    }.font(AppTypography.caption)
                }
            }
        }.padding(.vertical,6)
    }
    private func tokenStat(_ title:String,_ count:Int64,symbol:String,tint:Color)->some View {
        VStack(alignment:.leading,spacing:9) {
            Label(L(title),systemImage:symbol).foregroundColor(Palette.secondaryText).font(AppTypography.caption)
            Text(TokenFormat.compact(count)).font(AppTypography.number(19,weight:.semibold)).appMonospacedDigit().foregroundColor(tint)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(13).appBackground(tint.opacity(0.045),in:RoundedRectangle(cornerRadius:11,style:.continuous))
    }
    private func tokenLabel(_ title:String,_ count:Int64)->some View {
        VStack(alignment:.leading,spacing:4) {Text(L(title)).foregroundColor(Palette.secondaryText);Text(TokenFormat.compact(count)).appMonospacedDigit()}.font(AppTypography.caption)
    }
    private var chart:some View {
        let values=report.buckets,maximum=max(1,Double(values.map(\.counts.total).max() ?? 1))
        return HStack(alignment:.bottom,spacing:period == .month ? 4:7) {
            ForEach(Array(values.enumerated()),id:\.element.id) {index,bucket in
                Button {selected=bucket.id} label:{
                    VStack(spacing:7) {
                        ZStack(alignment:.bottom) {
                            RoundedRectangle(cornerRadius:3).fill(Palette.violet.opacity(0.045))
                            RoundedRectangle(cornerRadius:3).fill(Palette.violet.opacity(selected==bucket.id ? 1:0.65))
                                .frame(height:bucket.counts.total==0 ? 0:max(2,Double(bucket.counts.total)/maximum*108))
                        }.frame(height:108)
                        Text(tick(index,bucket)).font(.system(size:9)).foregroundColor(Palette.secondaryText).lineLimit(1).frame(height:14)
                    }.frame(maxWidth:.infinity).contentShape(Rectangle())
                }.buttonStyle(.plain).onHover{if $0 {selected=bucket.id}}
                    .accessibilityLabel(ElectricityFormat.powerDate(bucket.id)).accessibilityValue(TokenFormat.number(bucket.counts.total)+" tokens")
            }
        }.frame(height:132)
    }
    private func tick(_ index:Int,_ bucket:TokenUsageBucket)->String {
        if period == .day {return index%4==0 ? String(Calendar.current.component(.hour,from:bucket.id)):""}
        if period == .month {return index==0 || (index+1)%5==0 ? String(index+1):""}
        let formatter=DateFormatter();formatter.locale=ElectricityFormat.locale;formatter.setLocalizedDateFormatFromTemplate(period == .year ? "MMM":"EEE");return formatter.string(from:bucket.id)
    }
}
enum TokenFormat {
    static func number(_ value:Int64)->String {let f=NumberFormatter();f.locale=ElectricityFormat.locale;f.numberStyle = .decimal;return f.string(from:NSNumber(value:value)) ?? String(value)}
    static func compact(_ value:Int64,language:String?=nil)->String {
        let language=language ?? AppLocalization.shared.resolvedLanguage
        let formatter=NumberFormatter();formatter.locale=Locale(identifier:language);formatter.numberStyle = .decimal;formatter.usesGroupingSeparator=value<10000;formatter.maximumFractionDigits=2
        guard value>=10000 else{return formatter.string(from:NSNumber(value:value)) ?? String(value)}
        let divisor:Double,unit:String
        if language.hasPrefix("zh") {
            let traditional=language.hasPrefix("zh-Hant") || language.hasPrefix("zh-TW") || language.hasPrefix("zh-HK") || language.hasPrefix("zh-MO")
            let units:[(Int64,String)]=[(1_000_000_000_000,traditional ? "萬億":"万亿"),(100_000_000,traditional ? "億":"亿"),(10_000_000,traditional ? "千萬":"千万"),(1_000_000,traditional ? "百萬":"百万"),(10_000,traditional ? "萬":"万")]
            let scale=units.first{value >= $0.0}!
            divisor=Double(scale.0);unit=scale.1
        } else {
            divisor=value>=1_000_000_000 ? 1_000_000_000:(value>=1_000_000 ? 1_000_000:1000)
            unit=divisor==1_000_000_000 ? "B":(divisor==1_000_000 ? "M":"K")
        }
        return (formatter.string(from:NSNumber(value:Double(value)/divisor)) ?? "—")+unit
    }
}
