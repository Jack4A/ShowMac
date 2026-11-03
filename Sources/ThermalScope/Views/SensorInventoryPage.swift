import SwiftUI
import ThermalCore

struct SensorInventoryPage:View {
    let model:AppModel
    @ObservedObject var readings:LiveReadings
    @ObservedObject var history:SensorHistoryStore
    @State private var search=""
    @State private var filter:HardwareSensorKind?
    @State private var showAll=false
    @State private var showOther=false
    @State private var minutes=10
    @State private var selected:CommonSensorReading?
    private let platform=SensorNamingPlatform.current
    var all:[HardwareSensorReading] {readings.snapshot.map{SensorInventory.readings($0)} ?? []}
    private var named:[NamedSensor] {NamedSensor.rows(all,platform:platform)}
    private var query:String {search.trimmingCharacters(in:.whitespacesAndNewlines)}
    private var filtered:[NamedSensor] {named.filter{(filter==nil || $0.reading.kind==filter) && $0.matches(query)}}
    private var common:[CommonSensorReading] {history.readings}
    var countText:String {
        if !showAll {return String(format:L("常用 %d 项 · 全部 %d 项"),common.count,all.count)}
        if !query.isEmpty || filter != nil {return String(format:L("找到 %d / %d 项"),filtered.count,all.count)}
        return String(format:L("全部 %d 项 · 已识别 %d 项"),all.count,named.filter{$0.meaning != nil}.count)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            toolbar
            HStack {
                Text(countText)
                Spacer()
                if let date=readings.snapshot?.date {Text(date,format:.dateTime.hour().minute().second()).monospacedDigit()}
            }.font(.system(size:12)).foregroundStyle(Palette.secondaryText)
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    if all.isEmpty && (showAll || common.isEmpty) {empty("暂无可读传感器","设备暂未提供可读取的传感器信息，可稍后刷新。")}
                    else if showAll {completeList}
                    else {commonList}
                }.frame(maxWidth:.infinity,alignment:.leading).padding(1)
            }.id((showAll ? "all":"common")+(filter?.rawValue ?? "all")+search)
        }
        .onChange(of:search) {value in if !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {showAll=true}}
        .onChange(of:filter) {value in if value != nil {showAll=true}}
        .onChange(of:showAll) {value in if !value {search="";filter=nil}}
        .sheet(item:$selected) {reading in
            SensorTrendSheet(history:history,initial:reading,minutes:$minutes)
        }
    }
    var toolbar:some View {
        HStack(spacing:12) {
            Picker(L("显示范围"),selection:$showAll) {
                Text(L("常用读数")).tag(false)
                Text(L("全部传感器")).tag(true)
            }.pickerStyle(.segmented).labelsHidden().fixedSize(horizontal:true,vertical:false)
            NativeSearchField(title:L("搜索传感器名称或编号"),text:$search).frame(height:24)
            Picker(L("传感器类型"),selection:$filter) {
                Text(L("全部")).tag(Optional<HardwareSensorKind>.none)
                ForEach(HardwareSensorKind.allCases) {Text(L($0.title)).tag(Optional($0))}
            }.labelsHidden().frame(width:90).help(L("传感器类型"))
        }
    }
    var commonList:some View {
        VStack(alignment:.leading,spacing:14) {
            if common.isEmpty {
                empty("暂无可识别的常用读数","完整读数仍可在“全部传感器”查看。")
            } else {
                HStack {
                    Text(L("近期趋势")).font(AppTypography.section)
                    Spacer()
                    SensorTrendRangePicker(minutes:$minutes)
                }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:240),spacing:12)],spacing:12) {
                    ForEach(common) {reading in
                        CommonSensorCell(reading:reading,points:history.points(for:reading.id,minutes:minutes),end:history.end,minutes:minutes,onTrend:{selected=reading})
                            .contextMenu {Button(L("在状态栏显示")){_ = model.insertMenuComponent(source:.sensor(.common(reading)),style:.value)}.disabled(model.effectiveMenuComponents.count>=MenuBarComponent.limit)}
                    }
                }
                Text(L("仅保留本次运行最近 30 分钟；退出后清空。"))
                    .font(AppTypography.caption).foregroundStyle(Palette.secondaryText)
            }
            Button {showAll=true} label:{Label(L("查看完整读数"),systemImage:"list.bullet")}
                .buttonStyle(.borderless).font(.system(size:12))
        }
    }
    var completeList:some View {
        VStack(alignment:.leading,spacing:20) {
            if filtered.isEmpty {empty("没有匹配的传感器","尝试传感器编号、名称，或选择其他类型。")}
            else {
                ForEach(SensorComponent.allCases.filter{$0 != .unknown}) {component in
                    let rows=filtered.filter{$0.component==component}
                    if !rows.isEmpty {section(component.title,rows:rows)}
                }
                let other=filtered.filter{$0.component == .unknown}
                if !other.isEmpty {
                    if !query.isEmpty || filter != nil {section("用途未识别",rows:other)}
                    else {
                        DisclosureGroup(isExpanded:$showOther) {
                            grid(other).padding(.top,10)
                        } label:{Text(String(format:L("其他探头 · %d 项用途尚未公开"),other.count)).font(.system(size:13))}
                    }
                }
                Text(L("已识别的名称用于帮助理解读数；未识别探头保留完整原始数据。"))
                    .font(.system(size:12)).foregroundStyle(Palette.secondaryText)
            }
        }
    }
    private func section(_ title:String,rows:[NamedSensor])->some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:6) {
                Text(L(title)).font(.system(size:14,weight:.semibold))
                Text("\(rows.count)").font(.system(size:12)).foregroundStyle(Palette.secondaryText)
            }
            grid(rows)
        }
    }
    private func grid(_ rows:[NamedSensor])->some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:260),spacing:10)],spacing:10) {
            ForEach(rows) {row in
                SensorInventoryCell(sensor:row,fan:readings.snapshot?.fans.first{"F\($0.id)Ac"==row.reading.key})
                    .contextMenu {Button(L("在状态栏显示")){_ = model.insertMenuComponent(source:.sensor(.hardware(row.reading)),style:.value)}.disabled(model.effectiveMenuComponents.count>=MenuBarComponent.limit)}
            }
        }
    }
    func empty(_ title:String,_ detail:String)->some View {
        VStack(spacing:10) {
            Image(systemName:"sensor").font(.system(size:24)).foregroundStyle(Palette.secondaryText)
            Text(L(title)).font(AppTypography.section)
            Text(L(detail)).font(.system(size:12)).foregroundStyle(Palette.secondaryText)
        }.frame(maxWidth:.infinity,minHeight:160)
    }
}

private struct CommonSensorCell:View {
    let reading:CommonSensorReading
    let points:[MetricPoint]
    let end:Date
    let minutes:Int
    let onTrend:()->Void
    @State private var explanationVisible=false
    var title:String {commonSensorTitle(reading)}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text(title).font(.system(size:13,weight:.semibold))
                Spacer(minLength:6)
                Button {explanationVisible.toggle()} label:{Image(systemName:"info.circle").foregroundStyle(Palette.secondaryText)}
                    .buttonStyle(.borderless).accessibilityLabel(L("读数说明")+" · "+title)
                    .popover(isPresented:$explanationVisible) {
                        VStack(alignment:.leading,spacing:12) {
                            Text(title).font(AppTypography.section)
                            Text(L(reading.explanation)).font(.system(size:13))
                            if reading.kind == .temperature {Text(L("温度取已识别的相关探头最高值；探头编号不代表核心编号。")).font(.system(size:12))}
                            Text(L("原始编号")).font(.system(size:12)).foregroundStyle(Palette.secondaryText)
                            Text(reading.sources.joined(separator:" · ")).font(.system(size:11,design:.monospaced)).textSelection(.enabled)
                        }.padding(18).frame(width:300,alignment:.leading)
                    }
            }
            Button(action:onTrend) {
                VStack(alignment:.leading,spacing:10) {
                    Text(sensorValueText(reading.value,kind:reading.kind)).font(AppTypography.number(26,weight:.medium)).monospacedDigit().foregroundStyle(.primary)
                    SensorSparkline(points:points,end:end,minutes:minutes,kind:reading.kind,warningKind:MetricWarningBands.kind(commonID:reading.id)).frame(height:44)
                    HStack {
                        Text(sensorTrendPeriodText(points,end:end,minutes:minutes)).foregroundStyle(Palette.secondaryText).lineLimit(1).minimumScaleFactor(0.85)
                        Spacer()
                        Text(L("查看趋势")).foregroundStyle(Palette.violet).fixedSize()
                        Image(systemName:"chevron.right").font(.system(size:10,weight:.semibold)).foregroundStyle(Palette.violet)
                    }.font(AppTypography.caption)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(title+" · "+sensorValueText(reading.value,kind:reading.kind)+" · "+L("查看趋势"))
                .help(L("查看趋势"))
        }.frame(maxWidth:.infinity,alignment:.leading).subtlePanel()
    }
}

private struct SensorInventoryCell:View {
    let sensor:NamedSensor
    let fan:FanReading?
    var body:some View {
        HStack(spacing:10) {
            VStack(alignment:.leading,spacing:5) {
                Text(sensor.title).font(.system(size:13,weight:.medium)).lineLimit(2)
                Text(sensor.reading.key+(sensor.meaning==nil ? " · "+L("用途未公开"):""))
                    .font(.system(size:11,design:.monospaced)).foregroundStyle(Palette.secondaryText)
                if let fan {
                    Text(L(fan.manual.map{$0 ? "手动":"自动"} ?? "未知")+" · "+valueText(fan.minimum)+"–"+valueText(fan.maximum)+" RPM")
                        .font(.system(size:11)).foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer(minLength:4)
            Text(sensorValueText(sensor.reading.value,kind:sensor.reading.kind))
                .font(AppTypography.number(14,weight:.medium)).monospacedDigit().fixedSize()
        }.frame(maxWidth:.infinity,alignment:.leading).subtlePanel()
            .textSelection(.enabled).accessibilityElement(children:.combine)
            .help(L(sensor.meaning?.explanation ?? "该探头的具体位置和用途尚无可靠映射。"))
    }
}

func commonSensorTitle(_ reading:CommonSensorReading)->String {
    reading.kind == .fan ? localizedFanTitle(reading.sources.first ?? ""):L(reading.title)
}
func localizedFanTitle(_ key:String)->String {
    let id=Int(key.dropFirst().dropLast(2)) ?? 0
    return String(format:L("风扇 %d"),id+1)
}
func sensorValueText(_ value:Double?,kind:HardwareSensorKind)->String {
    guard let value else{return "—"}
    let format:String
    switch kind {case .fan:format="%.0f";case .temperature:format="%.1f";case .power:format="%.2f";case .voltage,.current:format="%.3f"}
    return String(format:format,value)+" "+kind.unit
}
