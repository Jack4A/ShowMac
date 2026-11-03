import AppKit
import SwiftUI
import ThermalCore

extension AppModel {
    var operationIssue:OperationIssue { OperationIssue(message) }
}
struct OperationNotice:View {
    @ObservedObject var model:AppModel
    @State private var expanded=false
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top,spacing:12) {
                if model.busy {ProgressView().appControlSize(.small).frame(width:20,height:24)}
                else {Image(systemName:AppSymbols.resolve(model.messageIsError ? "exclamationmark.circle.fill":"checkmark.circle.fill")).font(.system(size:20)).foregroundColor(model.messageIsError ? Color.orange:Palette.violet)}
                VStack(alignment:.leading,spacing:5) {
                    Text(L(model.busy ? "正在应用…":(model.messageIsError ? model.operationIssue.title:"操作已完成"))).font(.system(size:13,weight:.semibold))
                    Text(L(model.messageIsError ? model.operationIssue.guidance:model.message)).font(.system(size:12)).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
                }
                Spacer(minLength:8)
                if !model.busy {Button { model.dismissNotice() } label:{Image(systemName:AppSymbols.resolve("xmark"))}.buttonStyle(.borderless).help(L("收起提示（不改变硬件状态）")).accessibilityLabel(L("收起提示（不改变硬件状态）"))}
            }
            if model.messageIsError {
            HStack(spacing:14) {
                Button(expanded ? L("收起技术详情"):L("查看技术详情")) { expanded.toggle() }
                Button(L("复制详情")) { NSPasteboard.general.clearContents();NSPasteboard.general.setString(model.message,forType:.string) }
            }.font(.system(size:12)).buttonStyle(.borderless)
            if expanded {
                ScrollView(showsIndicators:false) {
                    Text(model.message).font(.system(size:12,design:.monospaced)).foregroundColor(Palette.secondaryText).appTextSelection().fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                }.frame(maxHeight:110).subtlePanel()
            }
            }
        }.frame(maxWidth:.infinity,alignment:.leading).subtlePanel()
            .onChange(of:model.message){_ in expanded=false}
    }
}
struct ThermalStatusCard:View {
    let sample:Snapshot
    var thermalColor:Color { switch sample.thermalState { case 0:return Palette.violet;case 1:return .orange;case 2,3:return .red;default:return .secondary } }
    var explanation:String {
        if sample.limited { return L("系统正在限制性能，可能与温度或供电有关。") }
        if !sample.limitKnown { return L("限速数据不完整，状态未知。") }
        if (1...3).contains(sample.thermalState) { return L("系统未限速，但热压力升高。") }
        if sample.thermalState != 0 { return L("系统未限速，热压力未知。") }
        return L("系统未限速，热压力正常。")
    }
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { Label(L("性能与热状态"),systemImage:AppSymbols.resolve("gauge.with.dots.needle.50percent")).font(.system(size:14,weight:.semibold));Spacer();Text(L("系统实时报告")).font(.system(size:12)).foregroundColor(Palette.secondaryText) }
            HStack(alignment:.top,spacing:24) {
                status(L("可用性能"),sample.limited ? L("受到限制"):(sample.limitKnown ? L("未检测到限速"):L("数据不完整")),sample.limited ? .orange:(sample.limitKnown ? Palette.violet:.secondary))
                Rectangle().fill(Color.primary.opacity(0.08)).frame(width:1,height:52)
                status(L("热压力"),L(sample.thermalTitle),thermalColor)
                Spacer(minLength:0)
                VStack(alignment:.trailing,spacing:8) { Text(L("可用逻辑处理器")).font(.system(size:12)).foregroundColor(Palette.secondaryText);Text("\(sample.availableCPUs.map(String.init) ?? "—") / \(sample.totalCPUs)").font(AppTypography.number(23,weight:.medium)).appMonospacedDigit() }
            }
            Text(explanation).font(.system(size:12)).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
        }.subtlePanel()
    }
    func status(_ title:String,_ value:String,_ color:Color)->some View {
        VStack(alignment:.leading,spacing:10) { Text(title).font(.system(size:12)).foregroundColor(Palette.secondaryText);HStack(spacing:7) { Circle().fill(color).frame(width:7,height:7);Text(value).font(.system(size:16,weight:.semibold)).foregroundColor(color) } }
    }
}
