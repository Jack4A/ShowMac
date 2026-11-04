import SwiftUI
import WidgetKit
import WidgetShared
import WidgetUI

struct StatusEntry:TimelineEntry {let date:Date;let snapshot:WidgetSnapshot?}
struct StatusProvider:TimelineProvider {
    func placeholder(in context:Context)->StatusEntry {StatusEntry(date:Date(),snapshot:nil)}
    func getSnapshot(in context:Context,completion:@escaping(StatusEntry)->Void){completion(StatusEntry(date:Date(),snapshot:WidgetStorage.read()))}
    func getTimeline(in context:Context,completion:@escaping(Timeline<StatusEntry>)->Void) {
        let now=Date(),snapshot=WidgetStorage.read()
        let dates=[now,now.addingTimeInterval(300),now.addingTimeInterval(1800)]
        completion(Timeline(entries:dates.map{StatusEntry(date:$0,snapshot:snapshot)},policy:.after(now.addingTimeInterval(1800))))
    }
}
struct StatusWidgetView:View {
    @Environment(\.widgetFamily) private var family
    let entry:StatusEntry
    var size:WidgetCardSize {family == .systemSmall ? .small:(family == .systemMedium ? .medium:.large)}
    var content:some View {WidgetStatusContent(snapshot:entry.snapshot,date:entry.date,size:size).widgetURL(WidgetRoute.overview.url)}
    @ViewBuilder var body:some View {
        if #available(macOS 14.0,*) {content.containerBackground(for:.widget){Color(.windowBackgroundColor)}}
        else {content.padding().background(Color(.windowBackgroundColor))}
    }
}
@main struct ThermalStatusWidget:Widget {
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:WidgetStorage.kind,provider:StatusProvider()){StatusWidgetView(entry:$0)}
            .configurationDisplayName("ShowMac")
            .description(LocalizedStringKey(WidgetStrings.text("查看温度、CPU、风扇与最近模式。",language:"system")))
            .supportedFamilies([.systemSmall,.systemMedium,.systemLarge])
    }
}
