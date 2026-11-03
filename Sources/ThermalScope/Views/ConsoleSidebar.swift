import SwiftUI

/// A roomy native source list with a fixed utility destination and a glass selection.
struct ConsoleSidebar:View {
    @ObservedObject var model:AppModel
    @ObservedObject var navigation:DiagnosticNavigation
    @Environment(\.colorScheme) private var scheme
    init(model:AppModel){self.model=model;self.navigation=model.navigation}

    var body:some View {
        SidebarNavigationTable(items:items,selection:selection,dark:scheme == .dark)
            .accessibilityLabel(L("主导航"))
            .modifier(ConsoleToolbarPresentation())
            .padding(.bottom,12)
            .frame(minWidth:210,idealWidth:220,maxWidth:280)
            .appBackground {
                if scheme == .light {
                    LinearGradient(gradient:Gradient(colors:[Palette.sidebarTop,Palette.sidebarBottom]),startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
                }
            }
    }
    private var items:[SidebarNavigationTable.Item] {
        let symbols:[ConsolePage:String]=[.metrics:"waveform.path.ecg.rectangle.fill",.sensors:"sensor.fill",.thermal:"thermometer.sun.fill",.optimization:"stethoscope",.processes:"square.stack.3d.up.fill",.history:"clock.arrow.circlepath"]
        let pages:[ConsolePage]=[.metrics,.sensors,.thermal,.optimization,.processes,.history]
        return pages.map {page in
            SidebarNavigationTable.Item(id:page.rawValue,title:L(page.title),symbol:symbols[page] ?? page.symbol,help:L(page.subtitle))
        }+[SidebarNavigationTable.Item(id:"preferences",title:L("设置"),symbol:"gearshape.fill",help:L("设置"))]
    }
    private var selection:Binding<String?> {
        Binding(get:{model.tab==1 ? "preferences":navigation.page.rawValue},set:{value in
            guard let value else{return}
            if navigation.metric != nil {navigation.metric=nil}
            if navigation.section != nil {navigation.section=nil}
            if value=="preferences" {if model.tab != 1 {model.tab=1}}
            else if let page=ConsolePage(rawValue:value) {
                if model.tab != 0 {model.tab=0}
                if navigation.page != page {navigation.page=page}
            }
        })
    }
}
