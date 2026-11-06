import SwiftUI
import ThermalCore

/// Exists only while the system popover is open. Sampling stays in the shared stores.
struct StatusOverview:View {
    @ObservedObject var model:AppModel
    @ObservedObject var readings:LiveReadings
    @ObservedObject var control:FanControlReadings
    @State private var editing=false
    @StateObject private var drag:StatusCardDragController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    let height:CGFloat
    let onNavigate:(String)->Void
    let onSettings:()->Void
    let onActions:()->Void
    let onResize:(CGFloat)->Void
    init(model:AppModel,height:CGFloat,onNavigate:@escaping(String)->Void,onSettings:@escaping()->Void,onActions:@escaping()->Void,onResize:@escaping(CGFloat)->Void,dragController:StatusCardDragController?=nil) {
        self._drag=StateObject(wrappedValue:dragController ?? StatusCardDragController(model:model))
        self.model=model;self.readings=model.readings;self.control=model.fanControl;self.height=height
        self.onNavigate=onNavigate;self.onSettings=onSettings;self.onActions=onActions;self.onResize=onResize
    }
    private var panelHeight:CGFloat {
        if editing {return height}
        let fanHeight=model.statusPanel.showFanControls ? 122+(model.systemFanHeatWarning || control.status?.protectionActive==true ? 18:0):0
        let tokenHeight=model.showsStatusTokenSummary ? 78:0
        let contents=122+CGFloat(tokenHeight)+StatusCardLayout.height(count:model.statusPanel.cards.count)+CGFloat(fanHeight)+(model.statusPanel.showProcesses ? 110:0)+(model.messageIsError ? 32:0)
        return min(height,max(240,contents))
    }
    var turbo:String {
        guard let state=readings.snapshot?.turbo else{return "未知"}
        return state == .disabledDriverLoaded ? "已关闭":(state == .driverNotLoaded ? "允许开启":"状态不可用")
    }
    var body:some View {
        VStack(spacing:0) {
            header.padding(.bottom,10)
            if editing {
                StatusCardEditor(model:model)
            } else {
                ScrollView(showsIndicators:false) {
                    VStack(spacing:10) {
                        LazyVStack(spacing:StatusCardLayout.spacing) {
                            ForEach(Array(stride(from:0,to:model.statusPanel.cards.count,by:2)),id:\.self) {index in
                                HStack(spacing:StatusCardLayout.spacing) {
                                    let source=model.statusPanel.cards[index]
                                    draggableCard(source,wide:index+1==model.statusPanel.cards.count)
                                    if index+1<model.statusPanel.cards.count {
                                        let next=model.statusPanel.cards[index+1]
                                        draggableCard(next)
                                    }
                                }
                            }
                        }.padding(.top,2).padding(.horizontal,1)
                        if model.showsStatusTokenSummary {
                            StatusTokenSummary(model:model,onOpen:{onNavigate("tokens")})
                                .opacity(drag.sourceID==StatusCardDragController.tokenSummary ? 0.45:1)
                                .appOverlay {StatusCardDragSurface(controller:drag,id:StatusCardDragController.tokenSummary,title:L("Token 用量与余量"),onOpen:{onNavigate("tokens")})}
                        }
                        if model.statusPanel.showFanControls {
                            StatusFanControl(model:model,onManage:{model.navigation.showFanSceneManager=true;onNavigate("thermal")})
                        }
                        if model.statusPanel.showProcesses {StatusCPUContributor(observer:model.processes,onOpen:{onNavigate(MetricKind.cpuUsage.rawValue)})}
                        if model.messageIsError {
                            Button {onNavigate("thermal")} label:{Label(L(model.operationIssue.title),systemImage:AppSymbols.resolve("exclamationmark.circle.fill")).font(.callout).foregroundColor(.orange).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).padding(.vertical,8)
                        }
                    }
                    .padding(.bottom,10)
                }
            }
            Divider().opacity(0.6)
            Group {
                if drag.active {
                    Label(L(drag.sourceID.map{drag.canRemove($0)} == true ? "拖到这里移除":"至少保留一个指标卡片"),systemImage:"trash")
                        .font(AppTypography.caption).foregroundColor(drag.removalTarget ? .white:.red)
                        .frame(maxWidth:.infinity,minHeight:32)
                        .appBackground(drag.removalTarget ? Color.red:Color.red.opacity(0.07),in:RoundedRectangle(cornerRadius:8))
                        .appOverlay {StatusCardDragSurface(controller:drag,trash:true)}
                        .accessibilityIdentifier("statusCardRemovalZone")
                } else {footer}
            }.padding(.top,8)
        }.foregroundColor(Palette.primaryText).font(AppTypography.body).padding(.horizontal,16).padding(.vertical,12).frame(width:390,height:panelHeight)
            .appBackground {Palette.canvas}
            .id(model.language).environment(\.locale,Locale(identifier:AppLocalization.shared.resolvedLanguage)).preferredColorScheme(model.colorScheme)
            .transaction{$0.animation=nil;$0.disablesAnimations=true}
            .onDisappear{drag.end()}
            .onAppear{onResize(panelHeight)}.onChange(of:panelHeight){onResize($0)}
    }
    private func draggableCard(_ source:StatusCardSource,wide:Bool=false)->some View {
        StatusMetricCard(model:model,source:source,wide:wide,onOpen:{onNavigate(source.destination)})
            .opacity(drag.sourceID==source.id ? 0.45:1)
            .appOverlay {
                RoundedRectangle(cornerRadius:12).stroke(drag.targetID==source.id ? Palette.violet:Color.clear,lineWidth:2).allowsHitTesting(false)
            }
            .appOverlay {StatusCardDragSurface(controller:drag,id:source.id,title:source.title(model),detail:source.valueText(source.value(readings))+" "+source.unit,onOpen:{onNavigate(source.destination)})}
    }
    var header:some View {
        VStack(spacing:5) {
            HStack {
                Button(L(editing ? "完成":"编辑")){editing.toggle()}.buttonStyle(AppChoiceButtonStyle(expanded:editing))
                Spacer()
                AppChoicePicker(title:L("趋势时间范围"),selection:$model.statusMinutes,
                                choices:[AppChoice(2,L("2 分钟")),AppChoice(5,L("5 分钟")),AppChoice(10,L("10 分钟"))])
                    .accessibilityIdentifier("statusTimeRange")
            }
            HStack(spacing:5) {
                Button {onNavigate("thermal")} label:{
                    HStack(spacing:5) {
                        Text(L(model.fanStrategyTitle))
                        Image(systemName:AppSymbols.resolve("chevron.right")).font(.system(size:8,weight:.semibold))
                    }.lineLimit(1).contentShape(Rectangle())
                }.buttonStyle(.plain).help(L("温度控制"))
                Spacer(minLength:4)
                if ControlAvailability.isAppleSilicon {
                    Text(L("热压力")+" · "+L(readings.snapshot?.thermalTitle ?? "未知")).lineLimit(1)
                        .foregroundColor((readings.snapshot?.thermalState ?? 0)>0 ? Color.orange:Color.secondary)
                } else {Text(L("睿频")+" · "+L(turbo)).lineLimit(1)}
            }.font(.system(size:11)).foregroundColor(.secondary)
        }
    }
    var footer:some View {
        HStack(spacing:12) {
            Button {onNavigate("metrics")} label:{Text(L("打开主窗口"))}
                .font(.system(size:12,weight:.medium)).buttonStyle(.plain)
            Spacer(minLength:4)
            AppUpdateBadge(updates:model.updates)
            freshness
            Button(action:onSettings) {Image(systemName:AppSymbols.resolve("gearshape"))}.help(L("设置")).accessibilityLabel(L("设置"))
            Button(action:onActions) {Image(systemName:AppSymbols.resolve("ellipsis"))}.help(L("更多操作")).accessibilityLabel(L("更多操作"))
        }.buttonStyle(.borderless).appControlSize(.small).frame(minHeight:24)
    }
    var freshness:some View {
        AppTimelineView(interval:5) {context in
            let date=readings.snapshot?.date
            let stale=date.map{context.date.timeIntervalSince($0)>max(15,model.interval*3)} ?? false
            let description=date.map{L(stale ? "读数未更新":"采样时间")+" · "+DateFormatter.localizedString(from:$0,dateStyle:.none,timeStyle:.medium)} ?? L("正在读取…")
            HStack(spacing:4) {
                if let date {
                    if stale {Image(systemName:AppSymbols.resolve("exclamationmark.circle")).foregroundColor(.orange)}
                    Text(date,style:.time).appMonospacedDigit()
                        .foregroundColor(stale ? Color.orange:Color.secondary)
                } else {Text(L("正在读取…"))}
            }.font(.system(size:10)).foregroundColor(.secondary)
                .accessibilityElement(children:.ignore).accessibilityLabel(description).help(description)
        }
    }
}

struct StatusCPUContributor:View {
    @ObservedObject var observer:ProcessObserver
    let onOpen:()->Void
    var rows:[ObservedProcess] {guard let date=observer.sampledAt,Date().timeIntervalSince(date)<20 else{return []};return Array(observer.allRows.sorted{$0.reading.cpu>$1.reading.cpu}.prefix(3))}
    var body:some View {
        let currentRows=rows
        if !currentRows.isEmpty {
            VStack(alignment:.leading,spacing:6) {
                HStack {Text(L("CPU 占用排行"));Spacer();Text(L("单核 100%"))}.font(.system(size:10)).foregroundColor(.secondary)
                ForEach(currentRows) {row in
                    Button(action:onOpen) {
                        HStack(spacing:6) {
                            if let icon=row.application?.icon {Image(nsImage:icon).resizable().frame(width:14,height:14)} else {Image(systemName:AppSymbols.resolve("app")).frame(width:14,height:14).foregroundColor(.secondary)}
                            Text(row.name).lineLimit(1);Spacer(minLength:2)
                            MetricValue(value:String(format:"%.1f",row.reading.cpu),unit:"%",size:12,unitSize:10,weight:.regular).fixedSize(horizontal:true,vertical:false)
                        }.font(.system(size:12)).foregroundColor(.primary).frame(minHeight:18).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(L("每 5 秒更新；进程 CPU 以单个核心 100% 计，多线程应用可能超过 100%。"))
                }
            }.padding(.vertical,8)
        }
    }
}
