import SwiftUI
import ThermalCore

/// Continuous is the default. Timing is a temporary action rather than a saved mode.
struct FanStopTimerButton:View {
    @ObservedObject var model:AppModel
    @State private var presented=false
    @State private var minutesText="30"
    private var minutes:Int? {Int(minutesText.trimmingCharacters(in:.whitespacesAndNewlines)).flatMap{FanStopTimer.minuteRange.contains($0) ? $0:nil}}
    private var available:Bool {model.coolingToken != nil && model.sessionCurve != nil || model.fanStopTimer != nil}
    var body:some View {
        Button {presented.toggle()} label:{
            if model.fanStopTimer != nil {
                AppTimelineView(interval:1) {_ in Label(title,systemImage:AppSymbols.resolve("timer")).lineLimit(1)}
            } else {Label(L("定时关闭…"),systemImage:AppSymbols.resolve("timer")).lineLimit(1)}
        }.buttonStyle(AppChoiceButtonStyle(expanded:model.fanStopTimer != nil))
            .disabled(model.busy || !available || !AppDistribution.hardwareControlAvailable)
            .help(L(available ? "默认持续运行，需要时再设置定时关闭。":"启用风扇控制后，可定时恢复系统自动。"))
            .accessibilityLabel(L("定时关闭"))
            .accessibilityValue(title)
            .accessibilityIdentifier("fanStopTimerButton")
            .popover(isPresented:$presented,arrowEdge:.bottom) {timerOptions}
            .onChange(of:presented){if $0 {minutesText=String(model.fanStopTimer?.minutes ?? 30)}}
            .onChange(of:available){if !$0 {presented=false}}
    }
    private var title:String {
        guard let timer=model.fanStopTimer else{return L("定时关闭…")}
        let remaining=timer.remaining()
        return remaining>0 ? String(format:L("%d 分钟后关闭"),max(1,Int(ceil(remaining/60)))):L("正在恢复自动…")
    }
    var timerOptions:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L("定时关闭")).font(.system(size:13,weight:.semibold))
            Text(L("到时恢复系统自动，监控继续。"))
                .font(.system(size:11)).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
            HStack(spacing:6) {
                ForEach([15,30,60,120],id:\.self) {value in
                    Button(String(value)){start(value)}.buttonStyle(AppChoiceButtonStyle())
                        .accessibilityLabel(String(format:L("%d 分钟后关闭"),value))
                }
            }
            HStack(spacing:8) {
                TextField(L("分钟数"),text:$minutesText,onCommit:{if let minutes {start(minutes)}})
                    .textFieldStyle(.roundedBorder).frame(width:64).accessibilityLabel(L("分钟数")).accessibilityIdentifier("fanStopTimerMinutes")
                Text(L("分钟后")).font(.system(size:12)).foregroundColor(Palette.secondaryText)
                Spacer(minLength:0)
                Button(L("开始")){if let minutes {start(minutes)}}.buttonStyle(AppChoiceButtonStyle())
                    .disabled(minutes==nil).accessibilityIdentifier("startFanStopTimer")
            }
            Text(L("1–1440 分钟，仅本次有效。"))
                .font(.system(size:10)).foregroundColor(Palette.secondaryText)
            if let timer=model.fanStopTimer {
                Divider().opacity(0.5)
                HStack {
                    AppTimelineView(interval:1) {_ in
                        let seconds=max(0,Int(ceil(timer.remaining())))
                        Text(String(format:L("剩余 %02d:%02d"),seconds/60,seconds%60)).appMonospacedDigit()
                    }.font(.system(size:11)).foregroundColor(Palette.secondaryText)
                    Spacer()
                    Button(L("取消定时")){model.cancelFanStopTimer();presented=false}
                        .buttonStyle(.borderless).font(.system(size:12)).foregroundColor(Palette.violet)
                        .accessibilityIdentifier("cancelFanStopTimer")
                }
            }
        }.padding(14).frame(width:260).appBackground{Palette.surface}.foregroundColor(Palette.primaryText)
            .disabled(model.busy || !available)
    }
    private func start(_ minutes:Int) {
        if model.startFanStopTimer(minutes:minutes) {presented=false}
    }
}
