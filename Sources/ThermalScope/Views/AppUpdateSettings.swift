import SwiftUI

struct AppUpdateSettings:View {
    @ObservedObject var updates:AppUpdateController
    var body:some View {
        VStack(alignment:.leading,spacing:9) {
            HStack(spacing:10) {
                if updates.state == .checking {ProgressView().appControlSize(.mini)}
                Text(updates.statusText).font(.system(size:12))
                    .foregroundColor(updates.availableVersion == nil ? Palette.secondaryText:Palette.violet)
                    .fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:8)
                Button(L("检查更新")){updates.checkNow()}
                    .buttonStyle(AppNativeButtonStyle()).appControlSize(.small)
                    .disabled(updates.state == .checking).accessibilityIdentifier("checkForUpdates")
                    .help(updates.lastCheckedAt.map{L("上次检查")+" · "+DateFormatter.localizedString(from:$0,dateStyle:.short,timeStyle:.short)} ?? L("检查更新"))
                if updates.availableVersion != nil {
                    Menu(L("下载…")) {
                        Button(L("前往官网下载")){updates.openWebsite()}
                        Button(L("前往 GitHub 下载")){updates.openGitHub()}
                    }.menuStyle(.borderlessButton).fixedSize().appControlSize(.small)
                }
            }
            HStack(spacing:12) {
                Toggle(L("自动检查更新"),isOn:$updates.automaticChecks)
                    .help(L("每天检查一次，仅获取公开版本信息。"))
                    .accessibilityIdentifier("automaticUpdateChecks")
                Spacer(minLength:8)
            }.font(.caption)
        }.accessibilityElement(children:.contain).accessibilityIdentifier("appUpdateSettings")
    }
}

/// Quiet discovery in the existing popover footer; no startup alerts or permissions.
struct AppUpdateBadge:View {
    @ObservedObject var updates:AppUpdateController
    var body:some View {
        if updates.availableVersion != nil {
            Button(L("发现新版本")){updates.showResult()}
                .font(.system(size:11)).foregroundColor(Palette.violet).buttonStyle(.plain)
                .help(updates.statusText)
        }
    }
}
