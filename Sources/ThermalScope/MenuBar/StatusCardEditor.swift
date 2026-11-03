import SwiftUI
import ThermalCore

/// Both entry points edit the same saved configuration and share their row actions/picker.
struct StatusCardEditor:View {
    @ObservedObject var model:AppModel
    var embedded=false
    @State private var choosing=false
    @State private var search=""
    private var query:String {search.trimmingCharacters(in:.whitespacesAndNewlines)}
    var body:some View {
        Group {
            if embedded {settingsContents}
            else {popoverContents}
        }.font(AppTypography.body)
    }
    private var settingsContents:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:8) {
                Text(L("弹窗卡片")).font(AppTypography.section)
                count
                Spacer()
                addButton.popover(isPresented:$choosing,arrowEdge:.bottom) {
                    sourcePicker.padding(12).frame(width:390,height:440)
                        .preferredColorScheme(model.colorScheme)
                }
            }
            cardRows
            HStack(spacing:20) {
                visibilityControls
                Spacer(minLength:0)
            }
        }
    }
    private var popoverContents:some View {
        VStack(alignment:.leading,spacing:10) {
            if choosing {sourcePicker}
            else {
                HStack {
                    Text(L("显示内容")).font(.system(size:12,weight:.medium))
                    Spacer()
                    count
                }
                ScrollView(showsIndicators:false) {
                    cardRows
                    addButton.padding(.top,10)
                        .frame(maxWidth:.infinity,alignment:.leading)
                }
                Divider()
                visibilityControls
            }
        }.padding(.vertical,6)
    }
    private var count:some View {
        Text("\(model.statusPanel.cards.count)/\(StatusPanelConfiguration.limit)").font(.system(size:11)).foregroundStyle(.secondary)
    }
    private var addButton:some View {
        Button {search="";choosing=true} label:{Label(L("添加卡片"),systemImage:"plus")}
            .disabled(model.statusPanel.cards.count>=StatusPanelConfiguration.limit).controlSize(.small)
    }
    @ViewBuilder private var visibilityControls:some View {
        Toggle(L("显示风扇控制"),isOn:$model.statusPanel.showFanControls)
        Toggle(L("显示 CPU 占用排行"),isOn:$model.statusPanel.showProcesses)
    }
    private var cardRows:some View {
        VStack(spacing:0) {
            ForEach(Array(model.statusPanel.cards.enumerated()),id:\.element.id) {index,source in
                HStack(spacing:8) {
                    Image(systemName:source.symbol).frame(width:16).foregroundStyle(Palette.violet)
                    Text(source.title(model)).lineLimit(1).help(source.title(model))
                    Spacer(minLength:2)
                    Button {model.moveStatusCard(source,by:-1)} label:{Image(systemName:"chevron.up")}
                        .disabled(index==0).help(L("上移")).accessibilityLabel(L("上移")+" · "+source.title(model))
                    Button {model.moveStatusCard(source,by:1)} label:{Image(systemName:"chevron.down")}
                        .disabled(index==model.statusPanel.cards.count-1).help(L("下移")).accessibilityLabel(L("下移")+" · "+source.title(model))
                    Button {model.removeStatusCard(source)} label:{Image(systemName:"minus.circle")}
                        .disabled(model.statusPanel.cards.count<=1).help(L("移除")).accessibilityLabel(L("移除")+" · "+source.title(model))
                }.font(.system(size:12)).buttonStyle(.borderless).controlSize(.small).padding(.vertical,10)
                if index<model.statusPanel.cards.count-1 {Divider().opacity(0.5)}
            }
        }.padding(.horizontal,10).background(Palette.surface,in:RoundedRectangle(cornerRadius:12,style:.continuous))
    }
    private var sourcePicker:some View {
        VStack(spacing:10) {
            HStack {
                Button {choosing=false} label:{Label(L("返回"),systemImage:"chevron.left")}.controlSize(.small)
                Spacer()
                Text(L("添加卡片")).font(.system(size:12,weight:.medium))
            }
            NativeSearchField(title:L("搜索传感器名称或编号"),text:$search).frame(height:24)
            List(selection:Binding<StatusCardSource?>(get:{nil},set:{source in
                if let source,model.addStatusCard(source) {choosing=false}
            })) {
                let metrics=MetricKind.allCases.filter{query.isEmpty || L($0.title).localizedCaseInsensitiveContains(query)}
                let common=model.menuCommonSensorOptions.filter{matches($0) && $0.reference.isCommon && $0.reference.key=="memory"}
                let hardware=model.menuHardwareSensorOptions.filter(matches)
                if !metrics.isEmpty || !common.isEmpty {
                    Section(L("常用读数")) {
                        ForEach(metrics) {kind in choice(.metric(kind),title:L(kind.title),detail:nil,value:StatusCardSource.metric(kind).value(model.readings))}
                        ForEach(common) {option in choice(.sensor(option.reference),title:option.title,detail:option.detail,value:option.value)}
                    }
                }
                ForEach(HardwareSensorKind.allCases) {kind in
                    let options=hardware.filter{$0.reference.kind==kind}
                    if !options.isEmpty {
                        Section(L(kind.title)) {ForEach(options) {option in choice(.sensor(option.reference),title:option.title,detail:option.detail,value:option.value)}}
                    }
                }
                if metrics.isEmpty && common.isEmpty && hardware.isEmpty {Text(L("没有匹配的传感器")).foregroundStyle(.secondary)}
            }.listStyle(.inset).scrollIndicators(.hidden)
        }
    }
    private func matches(_ option:MenuSensorOption)->Bool {
        query.isEmpty || [option.title,option.detail,L(option.reference.kind.title),option.reference.kind.unit].contains{$0.localizedCaseInsensitiveContains(query)}
    }
    private func choice(_ source:StatusCardSource,title:String,detail:String?,value:Double?)->some View {
        let selected=model.statusPanel.cards.contains(source)
        return HStack(spacing:7) {
                Image(systemName:source.symbol).frame(width:16).foregroundStyle(Palette.violet)
                VStack(alignment:.leading,spacing:2) {
                    Text(title).lineLimit(2)
                    if let detail {Text(detail).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)}
                }
                Spacer(minLength:2)
                Text(source.valueText(value)+" "+source.unit).font(.system(size:11)).monospacedDigit().foregroundStyle(.secondary)
                if selected {Image(systemName:"checkmark").font(.system(size:10))}
            }.font(.system(size:12)).padding(.vertical,4).contentShape(Rectangle()).tag(source)
            .foregroundStyle(selected ? Color.secondary:Color.primary)
            .accessibilityLabel(title+(detail.map{" · "+$0} ?? "")+(selected ? " · "+L("已添加"):""))
    }
}
