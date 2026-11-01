import Foundation
import SwiftUI
import WidgetShared

public enum WidgetCardSize:String,CaseIterable {case small,medium,large}
public enum WidgetStrings {
    private static let table:[String:[String:String]]={guard let u=Bundle.main.url(forResource:"Localization",withExtension:"json"),let d=try? Data(contentsOf:u),let t=try? JSONDecoder().decode([String:[String:String]].self,from:d) else{return [:]};return t}()
    public static func text(_ key:String,language:String)->String {
        let language=language=="system" ? (Locale.preferredLanguages.first ?? "en"):language
        if language.hasPrefix("zh") {return language.contains("Hant") || language.contains("TW") || language.contains("HK") ? (key.applyingTransform(StringTransform("Hans-Hant"),reverse:false) ?? key):key}
        let code=["en","ja","ko","de","fr","es"].first(where:{language.hasPrefix($0)}) ?? "en"
        if let value=table[key]?[code]{return value}
        if key.contains(" · "){return key.components(separatedBy:" · ").map{text($0,language:language)}.joined(separator:" · ")}
        return table[key]?["en"] ?? key
    }
}
public struct WidgetStatusContent:View {
    public let snapshot:WidgetSnapshot?
    public let date:Date
    public let size:WidgetCardSize
    public var linksEnabled:Bool
    public init(snapshot:WidgetSnapshot?,date:Date=Date(),size:WidgetCardSize,linksEnabled:Bool=true){self.snapshot=snapshot;self.date=date;self.size=size;self.linksEnabled=linksEnabled}
    var state:WidgetFreshness {snapshot?.freshness(at:date) ?? .unavailable}
    var data:WidgetSnapshot? {state == .unavailable ? nil:snapshot}
    var language:String {snapshot?.language ?? "system"}
    var accent:Color {Color(red:0.53,green:0.43,blue:0.82)}
    func t(_ key:String)->String {WidgetStrings.text(key,language:language)}
    var badge:String {switch state {case .recent:return "最近状态";case .previous:return "上次状态";case .paused:return "监测已暂停";case .unavailable:return "等待状态数据"}}
    public var body:some View {
        VStack(alignment:.leading,spacing:size == .small ? 5:10) {
            HStack {Label(t("温控台"),systemImage:"thermometer.medium").font(.system(size:11,weight:.semibold));Spacer(minLength:0);if size != .small {Text(t(badge)).font(.system(size:9)).foregroundStyle(state == .recent ? Color.secondary:Color.orange)}}
            if size == .small {small}
            else if size == .medium {medium}
            else {large}
            Spacer(minLength:0)
            footer
        }.foregroundStyle(.primary)
    }
    var small:some View {
        VStack(alignment:.leading,spacing:4) {
            metricLink(.cpuTemperature) {Text(number(.cpuTemperature)+"°").font(.system(size:32,weight:.medium,design:.rounded)).monospacedDigit()}
            HStack {Text("CPU "+number(.cpuUsage)+"%");Spacer(minLength:0);Text(number(.fan)+" RPM")}.font(.system(size:10,weight:.medium)).monospacedDigit()
            WidgetTrend(points:data?.trends[WidgetMetric.cpuUsage.rawValue] ?? [],end:data?.date ?? date,upper:100,color:accent).frame(height:16)
            Text(t(data?.mode ?? "打开温控台开始监测")).font(.system(size:9)).lineLimit(1)
        }
    }
    var medium:some View {
        HStack(alignment:.top,spacing:12) {
            tile(.cpuTemperature,title:"CPU 温度",symbol:"thermometer.medium")
            tile(.cpuUsage,title:"CPU 使用率",symbol:"cpu")
            tile(.fan,title:"风扇转速",symbol:"fanblades")
        }
    }
    var large:some View {
        VStack(spacing:10) {
            ForEach([WidgetMetric.cpuTemperature,.cpuUsage,.fan],id:\.rawValue) {kind in
                VStack(alignment:.leading,spacing:4) {
                    HStack {Text(t(title(kind))).font(.system(size:11));Spacer();metricLink(kind){Text(number(kind)+unit(kind)).font(.system(size:21,weight:.medium,design:.rounded)).monospacedDigit()}}
                    WidgetTrend(points:data?.trends[kind.rawValue] ?? [],end:data?.date ?? date,upper:kind == .fan ? max(6000,data?.value(kind) ?? 0):(kind == .cpuUsage ? 100:130),color:accent).frame(height:29)
                }
            }
            if let data {
                HStack {ForEach(data.fans,id:\.id) {fan in Text(fanText(fan)).font(.system(size:9)).lineLimit(1)}}
                HStack {Text("GPU "+temperature(data.gpuTemperature));Spacer();Text(t("存储温度")+" "+temperature(data.storageTemperature))}.font(.system(size:9)).foregroundStyle(.secondary)
            }
        }
    }
    func temperature(_ value:Double?)->String {(value.map{String(format:"%.0f",$0)} ?? "—")+"°C"}
    func fanText(_ fan:WidgetFan)->String {
        let value=fan.rpm.map{String(format:"%.0f",$0)} ?? "—"
        let state=t(fan.manual.map{$0 ? "手动":"自动"} ?? "未知")
        return t("风扇")+" \(fan.id+1) · "+value+" · "+state
    }
    func tile(_ kind:WidgetMetric,title:String,symbol:String)->some View {
        metricLink(kind) {
            VStack(alignment:.leading,spacing:5) {
                Label(t(title),systemImage:symbol).font(.system(size:10)).lineLimit(1).minimumScaleFactor(0.75)
                Text(number(kind)+unit(kind)).font(.system(size:kind == .fan ? 19:23,weight:.medium,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                WidgetTrend(points:data?.trends[kind.rawValue] ?? [],end:data?.date ?? date,upper:kind == .fan ? max(6000,data?.value(kind) ?? 0):(kind == .cpuUsage ? 100:130),color:accent).frame(height:27)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    var footer:some View {
        VStack(alignment:.leading,spacing:3) {
            if size != .small,let data {HStack {Text(t(data.mode)).lineLimit(1);Spacer(minLength:0);Text(t("睿频")+" · "+t(data.turbo)).lineLimit(1)}.font(.system(size:9))}
            HStack(spacing:3) {
                Text(t(size == .small ? badge:"采样时间"))
                if let snapshot {Text(snapshot.date,style:.relative).monospacedDigit()}
            }.font(.system(size:8)).foregroundStyle(.secondary).lineLimit(1)
            if state == .unavailable {Text(t("打开温控台开始监测")).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(2)}
        }
    }
    @ViewBuilder func metricLink<Content:View>(_ kind:WidgetMetric,@ViewBuilder content:()->Content)->some View {if linksEnabled && size != .small {Link(destination:WidgetRoute.metric(kind).url, label:content)} else {content()}}
    func title(_ kind:WidgetMetric)->String {kind == .fan ? "风扇转速":(kind == .cpuUsage ? "CPU 使用率":"CPU 温度")}
    func unit(_ kind:WidgetMetric)->String {kind == .fan ? "":(kind == .cpuUsage ? "%":"°")}
    func number(_ kind:WidgetMetric)->String {data?.value(kind).map{String(format:"%.0f",$0)} ?? "—"}
}
private struct WidgetTrend:View {
    let points:[WidgetPoint]
    let end:Date
    let upper:Double
    let color:Color
    var body:some View {
        GeometryReader {geometry in
            let paths=paths(size:geometry.size)
            ZStack(alignment:.topLeading) {
                paths.1.fill(LinearGradient(colors:[color.opacity(0.22),color.opacity(0.015)],startPoint:.top,endPoint:.bottom))
                paths.0.stroke(color,style:StrokeStyle(lineWidth:1.5,lineCap:.round,lineJoin:.round))
            }
        }.accessibilityHidden(true)
    }
    func paths(size:CGSize)->(Path,Path) {
        var line=Path(),area=Path(),previous:Int?,first:CGPoint?,last:CGPoint?
        func close(){guard let first,let last else{return};area.addLine(to:CGPoint(x:last.x,y:size.height));area.addLine(to:CGPoint(x:first.x,y:size.height));area.closeSubpath()}
        for point in points {
            guard let value=point.value else{close();previous=nil;first=nil;continue}
            let p=CGPoint(x:min(1,max(0,point.date.timeIntervalSince(end.addingTimeInterval(-300))/300))*size.width,y:size.height-min(1,max(0,value/max(1,upper)))*size.height)
            if previous==point.segment {line.addLine(to:p);area.addLine(to:p)} else {close();line.move(to:p);area.move(to:p);first=p}
            previous=point.segment;last=p
        }
        close();return(line,area)
    }
}
