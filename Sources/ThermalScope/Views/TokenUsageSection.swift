import SwiftUI
import ThermalCore

struct TokenUsageSection:View {
    @ObservedObject var store:TokenUsageStore
    let range:DateInterval
    let period:ElectricityPeriod
    @State private var provider="all"
    @State private var selected:Date?
    @State private var sources=false
    @State private var models=false
    private var report:TokenUsageReport {store.report(in:range,provider:TokenProvider(rawValue:provider),period:period)}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Label(L("Token 用量"),systemImage:"number.circle").font(AppTypography.section)
                Spacer()
                AppChoicePicker(title:L("AI 工具"),selection:$provider,choices:[AppChoice("all",L("全部工具"))]+TokenProvider.allCases.map{AppChoice($0.rawValue,$0.title)})
                    .accessibilityIdentifier("tokenProvider")
                Button{store.refresh()}label:{Image(systemName:"arrow.clockwise")}.buttonStyle(AppChoiceButtonStyle()).disabled(store.isScanning || !store.enabled).help(L("刷新 Token 统计"))
            }
            if !store.hasScanned || store.snapshot.fileCount==0 || store.snapshot.events.isEmpty {
                VStack(alignment:.leading,spacing:10) {
                    Text(L(store.isScanning ? "正在读取本机用量日志…":(store.enabled ? "未找到可统计的 Token 日志":"Token 统计已暂停"))).font(AppTypography.body)
                    Text(L("支持 Codex 与 Claude Code 的本机 JSONL 会话日志；没有日志的工具无法统计。"))
                        .font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                }.frame(maxWidth:.infinity,minHeight:90,alignment:.leading)
            } else {
                HStack(alignment:.firstTextBaseline,spacing:10) {
                    Text(TokenFormat.compact(report.counts.total)).font(AppTypography.number(30,weight:.semibold))
                    Text("tokens").font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                    Spacer()
                    Text(L("已记录请求")+" · "+TokenFormat.number(Int64(report.events.count))).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                }.accessibilityElement(children:.combine)
                HStack(spacing:24) {
                    tokenLabel("输入",report.counts.input)
                    tokenLabel("输出",report.counts.output)
                    tokenLabel("其中缓存读取",report.counts.cacheRead)
                }
                chart
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
                Text(L("本机日志统计，非账户额度或实际账单")).font(AppTypography.caption).foregroundColor(Palette.secondaryText)
                Spacer()
                if store.hasScanned {Text(ElectricityFormat.powerDate(store.snapshot.scannedAt)).font(.system(size:10)).foregroundColor(Palette.secondaryText)}
            }
            AppDisclosureGroup(L("数据来源与统计口径"),isExpanded:$sources) {
                VStack(alignment:.leading,spacing:12) {
                    Toggle(L("本机 Token 统计"),isOn:$store.enabled).toggleStyle(.checkbox)
                    ForEach(TokenProvider.allCases) {provider in
                        HStack(alignment:.top,spacing:12) {
                            VStack(alignment:.leading,spacing:4) {
                                Text(provider.title).font(AppTypography.body)
                                Text(store.location(for:provider)).font(AppTypography.caption).foregroundColor(Palette.secondaryText).appTextSelection()
                            }
                            Spacer(minLength:4)
                            Button(L("选择文件夹…")){store.chooseDirectory(for:provider)}.buttonStyle(.borderless)
                        }
                    }
                    Button(L("恢复默认日志位置")){store.resetDirectories()}.buttonStyle(.borderless)
                    Text(L("每分钟在后台增量扫描一次，可手动刷新。只保存用量、时间、模型和去重标识，不保存对话内容或读取登录密钥。"))
                    Text(L("总量 = 输入 + 输出；缓存包含在输入内，推理包含在输出内，不重复相加。Claude 缓存写入与读取也计入输入。"))
                    Text(L("重复请求、流式修订及可识别的分叉历史会去重；无法确认的分叉计数会排除。删除本机日志会改变统计范围。"))
                    Text(L("仅支持日志中实际记录的用量；其他设备、网页聊天和未记录的请求不会自动计入。"))
                }.font(AppTypography.caption).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true).padding(.top,12)
            }
        }.subtlePanel(padding:18).onChange(of:range.start){_ in selected=nil}.onChange(of:provider){_ in selected=nil}
            .accessibilityElement(children:.contain).accessibilityIdentifier("tokenUsageSection")
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
    static func compact(_ value:Int64)->String {
        if value<10000 {return number(value)}
        let divisor:Double=value>=1_000_000_000 ? 1_000_000_000:(value>=1_000_000 ? 1_000_000:1000)
        return ElectricityFormat.number(Double(value)/divisor,maximum:2)+(divisor==1_000_000_000 ? "B":(divisor==1_000_000 ? "M":"K"))
    }
}
