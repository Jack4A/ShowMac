import SwiftUI

struct LoginItemSettings:View {
    @ObservedObject var login:LoginItemController
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:16) {
                Text(L("登录时启动")).font(AppTypography.body)
                    .help(L("登录 Mac 后在状态栏运行，不打开主窗口。"))
                Spacer(minLength:12)
                Toggle(L("登录时启动"),isOn:Binding(get:{login.enabled},set:{login.setEnabled($0)}))
                    .labelsHidden().toggleStyle(.switch).accentColor(Palette.violet)
                    .accessibilityIdentifier("launchAtLogin")
            }.frame(minHeight:38)
            if login.state == .requiresApproval || login.error != nil {
                HStack(alignment:.top,spacing:10) {
                    Text(login.error ?? L("请在系统设置中允许 ShowMac 登录时启动。"))
                        .font(AppTypography.caption).foregroundColor(.orange).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:4)
                    Button(L("系统设置")){login.openSettings()}.buttonStyle(AppNativeButtonStyle()).appControlSize(.small)
                }
            }
        }.padding(.horizontal,16).padding(.bottom,login.state == .requiresApproval || login.error != nil ? 10:0).onAppear{login.refresh()}
    }
}
