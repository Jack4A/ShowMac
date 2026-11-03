import SwiftUI
import WidgetShared
import WidgetUI

struct WidgetSettings:View {
    @ObservedObject var model:AppModel
    @ObservedObject var publisher:WidgetPublisher
    init(model:AppModel){self.model=model;self.publisher=model.widgetPublisher}
    @State private var showPreview=false
    var body:some View {
        HStack(alignment:.top,spacing:12) {
            Image(systemName:AppSymbols.resolve("square.grid.2x2")).foregroundColor(Palette.violet).font(.system(size:17)).frame(width:24)
            VStack(alignment:.leading,spacing:5) {
                Text(L("系统小组件")).font(.system(size:12,weight:.medium))
                if #available(macOS 14,*) {Text(L("桌面与通知中心 · 小、中、大三种尺寸")).font(.system(size:12)).foregroundColor(Palette.secondaryText)}
                else {Text(L("通知中心 · 小、中、大三种尺寸")).font(.system(size:12)).foregroundColor(Palette.secondaryText)}
                Text(L("刷新由 macOS 调度，卡片显示采样时间。")).font(.system(size:12)).foregroundColor(Palette.secondaryText)
                if publisher.error != nil {Text(L("暂时无法提供组件数据")).font(.system(size:12)).foregroundColor(.orange)}
                else if let date=publisher.lastPublished {HStack(spacing:4){Text(L("采样时间"));Text(date,style:.time).appMonospacedDigit()}.font(.system(size:12)).foregroundColor(Palette.secondaryText)}
            }
            Spacer()
            Button(L("预览与添加")){showPreview=true}.buttonStyle(AppNativeButtonStyle()).appControlSize(.small)
        }.subtlePanel().sheet(isPresented:$showPreview){WidgetPreviewSheet(model:model,onClose:{showPreview=false}).preferredColorScheme(model.colorScheme)}
    }
}
struct WidgetPreviewSheet:View {
    @ObservedObject var model:AppModel
    @ObservedObject var readings:LiveReadings
    @State private var size:WidgetCardSize = .medium
    let onClose:()->Void
    init(model:AppModel,onClose:@escaping()->Void){self.model=model;self.readings=model.readings;self.onClose=onClose}
    var snapshot:WidgetSnapshot? {readings.snapshot.map{WidgetPublisher.snapshot($0,mode:model.coolingStatus,language:AppLocalization.shared.resolvedLanguage,history:model.metricHistory)}}
    var dimensions:CGSize {switch size {case .small:return CGSize(width:170,height:170);case .medium:return CGSize(width:364,height:170);case .large:return CGSize(width:364,height:382)}}
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Text(L("系统小组件")).font(.title2.bold());Spacer();Button(L("完成"),action:onClose).keyboardShortcut(.cancelAction)}
            Picker(L("尺寸"),selection:$size){Text(L("小")).tag(WidgetCardSize.small);Text(L("中")).tag(WidgetCardSize.medium);Text(L("大")).tag(WidgetCardSize.large)}.pickerStyle(.segmented).labelsHidden().frame(maxWidth:.infinity,alignment:.leading)
            ScrollView(showsIndicators:false) {
                VStack(alignment:.leading,spacing:18) {
                    HStack {Spacer();WidgetStatusContent(snapshot:snapshot,size:size,linksEnabled:false).padding(16).frame(width:dimensions.width,height:dimensions.height).appBackground(Palette.surface,in:RoundedRectangle(cornerRadius:24)).overlay(RoundedRectangle(cornerRadius:24).stroke(Palette.border.opacity(0.7),lineWidth:1));Spacer()}
                    Text(L("在桌面空白处右键，选择“编辑小组件”，搜索“showmac”，选择尺寸后添加。")).font(.callout).fixedSize(horizontal:false,vertical:true)
                    Text(L("也可从通知中心底部的“编辑小组件”添加。主程序运行时会提供最近状态；采样时间始终显示。")).font(.system(size:12)).foregroundColor(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
                    Text(L("此处为卡片布局预览；实际更新频率由系统决定。")).font(.system(size:12)).foregroundColor(Palette.secondaryText)
                }
            }
        }.padding(24).frame(width:510,height:620)
    }
}
