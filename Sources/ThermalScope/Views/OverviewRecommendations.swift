import SwiftUI
import ThermalCore

struct OverviewRecommendations:View {
    @ObservedObject var store:DiagnosisStore
    let onAction:(DiagnosticAction)->Void
    let onReview:()->Void
    var priority:DiagnosticFinding? {store.report.findings.first{$0.severity != .information}}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(L(priority == nil ? "建议摘要":"优先建议")).font(.system(size:13,weight:.semibold))
                Spacer()
                Button(L("查看全部建议"),action:onReview).buttonStyle(.borderless).font(.system(size:12))
            }
            if let finding=priority {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:5) {
                        Text(L(finding.title)).font(.system(size:12,weight:.medium))
                        if let subject=finding.subject {Text(subject).font(.system(size:12)).foregroundColor(Palette.secondaryText).lineLimit(1)}
                        if let evidence=finding.evidence {Text(evidence).font(.system(size:12)).foregroundColor(Palette.secondaryText).lineLimit(2)}
                    }
                    Spacer()
                    Button(L(finding.actionTitle)){onAction(finding.action)}.buttonStyle(AppNativeButtonStyle())
                }
            } else {
                Text(L(store.report.state == .sampling ? "正在观察，建议会随持续读数更新。":"暂无需要立即处理的建议，详细依据可在性能诊断中查看。")).font(.system(size:12)).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
            }
        }.subtlePanel()
    }
}
