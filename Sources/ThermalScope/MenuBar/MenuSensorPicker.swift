import SwiftUI
import ThermalCore

/// Search stays inside one native popover instead of adding another settings page.
struct MenuSensorPicker:View {
    @ObservedObject var model:AppModel
    @ObservedObject var readings:LiveReadings
    @Binding var source:MenuComponentSource
    @State private var showing=false
    @State private var search=""
    init(model:AppModel,source:Binding<MenuComponentSource>) {
        self.model=model;self.readings=model.readings;self._source=source
    }
    private var query:String {search.trimmingCharacters(in:.whitespacesAndNewlines)}
    private func matches(_ option:MenuSensorOption)->Bool {
        query.isEmpty || [option.title,option.detail,L(option.reference.kind.title),option.reference.kind.unit].contains{$0.localizedCaseInsensitiveContains(query)}
    }
    var body:some View {
        Button {search="";showing.toggle()} label:{
            HStack(spacing:6) {
                Text(source.title(in:model)).lineLimit(1)
                Spacer(minLength:2)
                Image(systemName:AppSymbols.resolve("chevron.down")).font(.system(size:9,weight:.semibold))
            }.frame(width:175)
        }.buttonStyle(AppChoiceButtonStyle(expanded:showing))
            .accessibilityLabel(L("选择状态栏读数")+" · "+source.title(in:model))
            .popover(isPresented:$showing,arrowEdge:.bottom) {
                VStack(spacing:0) {
                    NativeSearchField(title:L("搜索传感器名称或编号"),text:$search).frame(height:24).padding(12)
                    Divider()
                    List(selection:Binding<MenuComponentSource?>(get:{source},set:{item in
                        if let item {source=item;showing=false}
                    })) {
                        let metrics=[MenuMetric.cpu,.battery].filter{query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)}
                        let common=model.menuCommonSensorOptions.filter(matches)
                        let hardware=model.menuHardwareSensorOptions.filter(matches)
                        if !metrics.isEmpty || !common.isEmpty {
                            Section(header:Text(L("常用读数"))) {
                                ForEach(metrics) {metric in
                                    choice(.metric(metric),title:metric.title,detail:nil,value:metric.value(readings))
                                }
                                ForEach(common) {option in optionRow(option)}
                            }
                        }
                        ForEach(HardwareSensorKind.allCases) {kind in
                            let rows=hardware.filter{$0.reference.kind==kind}
                            if !rows.isEmpty {Section(header:Text(L(kind.title))) {ForEach(rows){optionRow($0)}}}
                        }
                        if metrics.isEmpty && common.isEmpty && hardware.isEmpty {Text(L("没有匹配的传感器")).foregroundColor(.secondary)}
                    }.listStyle(.inset).appChoiceListSurface().appHideScrollIndicators()
                }.frame(width:390,height:440).appBackground{Palette.surface}.preferredColorScheme(model.colorScheme)
            }
    }
    private func optionRow(_ option:MenuSensorOption)->some View {
        choice(.sensor(option.reference),title:option.title,detail:option.detail,value:sensorValueText(option.value,kind:option.reference.kind))
    }
    private func choice(_ item:MenuComponentSource,title:String,detail:String?,value:String)->some View {
        HStack(spacing:8) {
                Image(systemName:AppSymbols.resolve(item.symbol)).frame(width:16).foregroundColor(.secondary)
                VStack(alignment:.leading,spacing:2) {
                    Text(title).lineLimit(2)
                    if let detail {Text(detail).font(AppTypography.caption).foregroundColor(.secondary).lineLimit(1)}
                }
                Spacer(minLength:6)
                Text(value).font(AppTypography.caption).appMonospacedDigit().foregroundColor(.secondary)
                Image(systemName:AppSymbols.resolve("checkmark")).font(.system(size:10)).opacity(source==item ? 1:0).frame(width:10)
        }.padding(.vertical,3).contentShape(Rectangle()).tag(item)
            .foregroundColor(source==item ? Palette.violet:Palette.primaryText)
            .listRowBackground(source==item ? Palette.controlHover:Palette.surface)
            .accessibilityElement(children:.combine)
            .accessibilityLabel(title+" · "+(detail.map{$0+" · "} ?? "")+value)
    }
}
