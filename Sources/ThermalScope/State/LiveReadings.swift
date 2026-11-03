import SwiftUI
import ThermalCore

@MainActor final class LiveReadings:ObservableObject {
    private(set) var snapshot:Snapshot?
    private(set) var telemetry:SystemTelemetry?
    func update(_ value:Snapshot,publish:Bool) {
        if publish {objectWillChange.send()};snapshot=value
    }
    func update(_ value:SystemTelemetry,publish:Bool) {
        if publish {objectWillChange.send()};telemetry=value
    }
    func resumeVisualUpdates(){objectWillChange.send()}
}
struct LiveAuxiliary:View {
    @ObservedObject var readings:LiveReadings
    var body:some View {
        HStack(spacing:16) {
            Label("GPU "+valueText(readings.snapshot?.temperature(.gpu))+"°C",systemImage:AppSymbols.resolve("display"))
            Label(L("存储 ")+valueText(readings.snapshot?.temperature(.storage))+"°C",systemImage:AppSymbols.resolve("internaldrive"))
            Spacer();Label(valueText(readings.telemetry?.batteryPercent)+"%",systemImage:AppSymbols.resolve("battery.75percent"))
        }.font(.system(size:11)).foregroundColor(.secondary).padding(.horizontal,4)
    }
}
struct LiveThermalDetails:View {
    @ObservedObject var readings:LiveReadings
    var body:some View {if let sample=readings.snapshot {ThermalStatusCard(sample:sample)}}
}
struct MenuLivePreview:View {
    @ObservedObject var readings:LiveReadings
    let items:[MenuMetric]
    let style:String
    var body:some View {
        ScrollView(.horizontal,showsIndicators:false) {
        HStack(spacing:14) {
            ForEach(items) {metric in
                HStack(spacing:4) {
                    if style != "values" {Image(systemName:AppSymbols.resolve(metric.symbol))}
                    if style != "icons" {Text(value(metric)).appMonospacedDigit()}
                }.help(metric.title)
            }
        }.font(.system(size:12,weight:.medium)).fixedSize(horizontal:true,vertical:false).padding(.horizontal,10).frame(minHeight:32)
        }.frame(height:32).appBackground(.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:8))
    }
    func value(_ metric:MenuMetric)->String {
        switch metric {
        case .cpu:return valueText(readings.snapshot?.cpuUsage)+"%"
        case .temperature:return valueText(readings.snapshot?.cpuTemperature)+"°"
        case .gpu:return valueText(readings.snapshot?.temperature(.gpu))+"°"
        case .battery:return valueText(readings.telemetry?.batteryPercent)+"%"
        case .fan:return valueText(readings.snapshot?.fans.compactMap(\.rpm).max())+" rpm"
        }
    }
}
