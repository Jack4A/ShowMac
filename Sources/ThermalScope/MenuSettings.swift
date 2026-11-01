import SwiftUI
import AppKit
import ThermalCore

enum MenuMetric:String,CaseIterable,Identifiable,Codable {
    case cpu,temperature,gpu,battery,fan
    var id:String { rawValue }
    var title:String { switch self { case .cpu:return L("CPU 使用率");case .temperature:return L("CPU 温度");case .gpu:return L("GPU 温度");case .battery:return L("电池电量");case .fan:return L("风扇转速") } }
    var symbol:String { switch self {case .cpu:return "cpu";case .temperature:return "thermometer.medium";case .gpu:return "display";case .battery:return "battery.75percent";case .fan:return "fanblades"} }
    var shortTitle:String {switch self {case .cpu:return "CPU";case .temperature:return L("温度");case .gpu:return "GPU";case .battery:return L("电池");case .fan:return L("风扇")}}
    @MainActor func value(_ readings:LiveReadings)->String {
        switch self {
        case .cpu:return valueText(readings.snapshot?.cpuUsage)+"%"
        case .temperature:return valueText(readings.snapshot?.cpuTemperature)+"°"
        case .gpu:return valueText(readings.snapshot?.temperature(.gpu))+"°"
        case .battery:return valueText(readings.telemetry?.batteryPercent)+"%"
        case .fan:return valueText(readings.snapshot?.fans.compactMap(\.rpm).max())
        }
    }
    @MainActor func value(_ model:AppModel)->String {
        switch self {
        case .cpu:return valueText(model.snapshot?.cpuUsage)+"%"
        case .temperature:return valueText(model.snapshot?.cpuTemperature)+"°"
        case .gpu:return valueText(model.snapshot?.temperature(.gpu))+"°"
        case .battery:return valueText(model.telemetry?.batteryPercent)+"%"
        case .fan:return valueText(model.snapshot?.fans.compactMap(\.rpm).max())+" rpm"
        }
    }
}
struct MenuSettings:View {
    @ObservedObject var model:AppModel
    var orderedItems:[MenuMetric] {model.menuItems+MenuMetric.allCases.filter{!model.menuItems.contains($0)}}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label(L("状态栏"),systemImage:"menubar.rectangle").font(.system(size:15,weight:.semibold))
                Spacer()
                Button(L("查看状态面板")) {model.statusMenuRequested?()}.buttonStyle(.borderless).font(.caption)
            }
            if model.menuStyle == "custom" {
                MenuAppearancePreview(model:model)
                MenuAppearanceControls(model:model)
            }
            HStack(alignment:.top,spacing:18) {
                if model.menuStyle != "custom" {VStack(alignment:.leading,spacing:7) {
                    Text(L("实时预览")).font(.system(size:10)).foregroundStyle(.secondary)
                    HStack(spacing:8) {
                        if model.menuGraph {MenuCPUPreview(history:model.metricHistory,kind:model.menuGraphKind,style:model.menuGraphStyle,width:model.menuGraphWidth,warningsEnabled:model.menuCPUWarnings)}
                        if model.menuStyle == "stacked" {MenuStackedPreview(readings:model.readings,items:model.menuItems)}
                        else {MenuLivePreview(readings:model.readings,items:model.menuItems,style:model.menuStyle)}
                    }.frame(height:32)
                }.frame(minWidth:160,maxWidth:.infinity,alignment:.leading)}
                VStack(alignment:.leading,spacing:7) {
                    Text(L("显示样式")).font(.system(size:10)).foregroundStyle(.secondary)
                    Picker(L("显示样式"),selection:$model.menuStyle) {
                        Text(L("自定义组合")).tag("custom");Text(L("双行数值")).tag("stacked");Text(L("图标与数值")).tag("both");Text(L("仅数值")).tag("values");Text(L("仅图标")).tag("icons")
                    }.pickerStyle(.menu).labelsHidden().frame(width:160).frame(minHeight:26)
                }.fixedSize(horizontal:true,vertical:false)
            }
            if model.menuStyle != "custom" {
            Toggle(L("显示菜单栏曲线"),isOn:$model.menuGraph).toggleStyle(.checkbox).font(.system(size:12))
            if model.menuGraph {
                DisclosureGroup(L("曲线设置")) {
                    HStack(spacing:16) {
                        Picker(L("曲线来源"),selection:$model.menuGraphKind) {ForEach(MetricKind.allCases){kind in Text(L(kind.title)).tag(kind)}}
                        Picker(L("图形样式"),selection:$model.menuGraphStyle) {ForEach(MenuGraphStyle.allCases){style in Text(L(style.title)).tag(style)}}
                        Picker(L("曲线宽度"),selection:$model.menuGraphWidth) {Text(L("紧凑")).tag(44.0);Text(L("标准")).tag(66.0);Text(L("宽")).tag(88.0)}
                    }.padding(.top,10)
                }.font(.caption)
                Text(L("最近 2 分钟的真实采样；百分比固定 0–100%，温度 0–130°C，风扇至少 0–6000 RPM。")).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            }
            Toggle(L("CPU 高负载警示色"),isOn:$model.menuCPUWarnings).toggleStyle(.checkbox).font(.system(size:12))
            Text(L("全机 CPU ≥70% 显示橙色；≥90% 连续采样满 10 秒显示红色。缺失或断档重新计时。")).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Divider().opacity(0.45)
            VStack(spacing:0) {
                ForEach(orderedItems) { metric in
                    if model.menuStyle == "custom" {MenuTileEditor(model:model,metric:metric)} else {HStack(spacing:10) {
                        Toggle(isOn:Binding(get:{model.menuItems.contains(metric)},set:{model.toggleMenu(metric,$0)})) { Label(metric.title,systemImage:metric.symbol) }.toggleStyle(.checkbox).disabled(model.menuItems.contains(metric) && model.menuItems.count==1)
                        Spacer()
                        if let index=model.menuItems.firstIndex(of:metric) {
                            Text("\(index+1)").font(.system(size:10,weight:.medium,design:.rounded)).monospacedDigit().foregroundStyle(.secondary).frame(width:20,height:20).background(.primary.opacity(0.045),in:Circle())
                            Button { model.moveMenu(metric,-1) } label:{Image(systemName:"chevron.left").frame(width:22,height:22)}.disabled(index==0).help(L("向左移动"))
                            Button { model.moveMenu(metric,1) } label:{Image(systemName:"chevron.right").frame(width:22,height:22)}.disabled(index==model.menuItems.count-1).help(L("向右移动"))
                        }
                    }.font(.system(size:12)).padding(.vertical,6).buttonStyle(.borderless)}
                }
            }
            if model.menuStyle != "custom" {Button(L("使用自定义组合")){model.menuStyle="custom"}.buttonStyle(.bordered).controlSize(.small)}
            Text(L("至少保留一项。上方为实时预览；箭头调整菜单栏中的顺序。")).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(18).subtlePanel()
    }
}
