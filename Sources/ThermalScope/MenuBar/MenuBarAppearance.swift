import AppKit
import SwiftUI
import ThermalCore

enum MenuTileStyle:String,CaseIterable,Identifiable {
    case stacked,value,icon,history,bars,ring,historyValue
    var id:String {rawValue}
    var title:String {switch self {case .stacked:return "双行数值";case .value:return "仅数值";case .icon:return "仅图标";case .history:return "面积历史";case .bars:return "柱形历史";case .ring:return "圆环与数值";case .historyValue:return "曲线与数值"}}
}
enum MenuBarTheme:String,CaseIterable,Identifiable {
    case system,accent,multicolor
    var id:String {rawValue}
    var title:String {switch self {case .system:return "系统单色";case .accent:return "统一紫";case .multicolor:return "多彩"}}
}
enum MenuBarPreset:Int,CaseIterable,Identifiable {
    case minimal,graphs,gauges
    var id:Int {rawValue}
    var title:String {["极简","曲线组合","仪表组合"][rawValue]}
    var items:[MenuMetric] {self == .minimal ? [.temperature,.cpu]:[.temperature,.cpu,.fan]}
    var styles:[String:String] {switch self {case .minimal:return ["temperature":"stacked","cpu":"stacked"];case .graphs:return ["temperature":"stacked","cpu":"historyValue","fan":"stacked"];case .gauges:return ["temperature":"stacked","cpu":"ring","fan":"bars"]}}
    var theme:MenuBarTheme {self == .minimal ? .system:(self == .graphs ? .multicolor:.accent)}
    var background:Bool {self == .graphs}
}
extension MenuMetric {
    var historyKind:MetricKind {switch self {case .cpu:return .cpuUsage;case .temperature:return .cpuTemperature;case .gpu:return .gpuTemperature;case .fan:return .fan;case .battery:return .battery}}
    var barLabel:String {switch self {case .cpu:return "CPU";case .temperature:return ["zh","ja","ko"].contains(where:{AppLocalization.shared.resolvedLanguage.hasPrefix($0)}) ? L("温度"):"TEMP";case .gpu:return "GPU";case .fan:return "RPM";case .battery:return L("电池")}}
    var reservedValue:String {switch self {case .cpu,.battery:return "100%";case .temperature,.gpu:return "130°";case .fan:return "30000"}}
    var defaultTileStyle:MenuTileStyle {self == .cpu ? .historyValue:.stacked}
    var defaultBarColor:NSColor {switch self {case .cpu:return .systemBlue;case .temperature:return .systemOrange;case .gpu:return .systemCyan;case .fan:return .systemPurple;case .battery:return .systemTeal}}
    @MainActor func barNumber(_ readings:LiveReadings)->Double? {
        let n:Double?
        switch self {case .cpu:n=readings.snapshot?.cpuUsage;case .temperature:n=readings.snapshot?.cpuTemperature;case .gpu:n=readings.snapshot?.temperature(.gpu);case .fan:n=readings.snapshot?.fans.compactMap(\.rpm).max();case .battery:n=readings.telemetry?.batteryPercent}
        return n.flatMap{$0.isFinite && $0>=0 && (!(self == .cpu || self == .battery) || $0<=100) ? $0:nil}
    }
}
struct MenuBarTile {
    let metric:MenuMetric
    let style:MenuTileStyle
    let label:String
    let value:String
    let number:Double?
    let points:[MetricPoint]
    let upper:Double
    let color:NSColor
}
enum MenuBarAppearanceRenderer {
    static func color(hex:String?,fallback:NSColor)->NSColor {
        guard let hex,hex.count==6,let n=UInt32(hex,radix:16) else{return fallback}
        return NSColor(srgbRed:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255,alpha:1)
    }
    static func hex(_ color:NSColor)->String? {
        guard let c=color.usingColorSpace(.sRGB) else{return nil}
        return String(format:"%02X%02X%02X",Int((min(1,max(0,c.redComponent))*255).rounded()),Int((min(1,max(0,c.greenComponent))*255).rounded()),Int((min(1,max(0,c.blueComponent))*255).rounded()))
    }
    @MainActor static func tiles(model:AppModel,preset:MenuBarPreset?=nil)->[MenuBarTile] {
        (preset?.items ?? model.menuItems).map {metric in
            let n=metric.barNumber(model.readings),points=model.metricHistory.points(metric.historyKind,minutes:2)
            let upper=max(metric.historyKind.fixedUpper,points.compactMap(\.value).max() ?? 0,n ?? 0)
            let value=n.map{String(format:"%.0f",$0)} ?? "—"
            let unit=metric == .cpu || metric == .battery ? "%":(metric == .fan ? "":"°")
            return MenuBarTile(metric:metric,style:MenuTileStyle(rawValue:(preset?.styles ?? model.menuTileStyles)[metric.rawValue] ?? "") ?? metric.defaultTileStyle,label:metric.barLabel,value:value+unit,number:n,points:points,upper:upper,color:color(hex:preset == nil ? model.menuTileColors[metric.rawValue]:nil,fallback:metric.defaultBarColor))
        }
    }
    static func image(tiles:[MenuBarTile],ending:Date,theme:MenuBarTheme,spacing:Double,graphWidth:Double,background:Bool,appearance:NSAppearance?=nil,warningsEnabled:Bool=true)->NSImage {
        let small=NSFont.systemFont(ofSize:7.2,weight:.semibold),large=NSFont.monospacedDigitSystemFont(ofSize:10.5,weight:.medium)
        let gap:CGFloat=spacing==4 ? 4:9,plotWidth:CGFloat=[44.0,66,88].contains(graphWidth) ? graphWidth:44
        func measured(_ s:String,_ font:NSFont)->CGFloat {(s as NSString).size(withAttributes:[.font:font]).width.rounded(.up)}
        let textWidths=tiles.map{max(measured($0.value,large),measured($0.metric.reservedValue,large),measured($0.label,small))+2}
        let widths=tiles.enumerated().map {index,tile -> CGFloat in
            switch tile.style {case .value,.stacked:return textWidths[index];case .icon:return 16;case .history,.bars:return plotWidth+13;case .ring:return 21+textWidths[index];case .historyValue:return plotWidth+5+textWidths[index]}
        }
        let width=max(1,widths.reduce(0,+)+CGFloat(max(0,tiles.count-1))*gap)
        let image=NSImage(size:NSSize(width:width,height:22),flipped:false) {_ in
            func draw() {
                // Resolve against the status button's own appearance, not the main window.
                let dark=(appearance ?? NSAppearance.currentDrawing()).bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
                let foreground=dark ? NSColor.white:NSColor.black
                func text(_ value:String,_ font:NSFont,_ rect:NSRect,_ color:NSColor) {
                    let size=(value as NSString).size(withAttributes:[.font:font])
                    (value as NSString).draw(at:NSPoint(x:rect.midX-size.width/2,y:rect.minY),withAttributes:[.font:font,.foregroundColor:color])
                }
                func stacked(_ tile:MenuBarTile,_ x:CGFloat,_ width:CGFloat) {
                    text(tile.label,small,NSRect(x:x,y:12,width:width,height:10),foreground.withAlphaComponent(0.76))
                    text(tile.value,large,NSRect(x:x,y:0,width:width,height:12),foreground)
                }
                func symbol(_ tile:MenuBarTile,_ x:CGFloat,_ size:CGFloat,_ color:NSColor) {
                    guard let icon=NSImage(systemSymbolName:tile.metric.symbol,accessibilityDescription:nil) else{return}
                    let tinted=NSImage(size:NSSize(width:size,height:size),flipped:false) {r in icon.draw(in:r);color.setFill();r.fill(using:.sourceAtop);return true}
                    tinted.draw(in:NSRect(x:x,y:(22-size)/2,width:size,height:size))
                }
                var x:CGFloat=0
                for (index,tile) in tiles.enumerated() {
                    let baseColor=theme == .system ? foreground:(theme == .accent ? NSColor.systemPurple:tile.color)
                    let cpuWarning=warningsEnabled && tile.metric == .cpu
                    let level=cpuWarning ? CPULoadBands.current(tile.number,points:tile.points,at:ending):CPULoadLevel.normal
                    let accent=level.nativeColor(normal:baseColor)
                    switch tile.style {
                    case .stacked:stacked(tile,x,textWidths[index])
                    case .value:text(tile.value,large,NSRect(x:x,y:5,width:widths[index],height:12),foreground)
                    case .icon:symbol(tile,x,15,accent)
                    case .history,.bars:
                        symbol(tile,x,10,accent)
                        drawHistory(tile.points,ending:ending,rect:NSRect(x:x+13,y:3,width:plotWidth,height:16),upper:tile.upper,color:baseColor,bars:tile.style == .bars,background:background,cpuWarnings:cpuWarning)
                    case .historyValue:
                        drawHistory(tile.points,ending:ending,rect:NSRect(x:x,y:3,width:plotWidth,height:16),upper:tile.upper,color:baseColor,bars:false,background:background,cpuWarnings:cpuWarning)
                        stacked(tile,x+plotWidth+5,textWidths[index])
                    case .ring:
                        let center=NSPoint(x:x+9,y:11),radius:CGFloat=7.5
                        let track=NSBezierPath();track.lineWidth=2.4;track.appendArc(withCenter:center,radius:radius,startAngle:90,endAngle:450)
                        foreground.withAlphaComponent(0.17).setStroke();track.stroke()
                        if let n=tile.number {
                            let arc=NSBezierPath();arc.lineWidth=2.4;arc.lineCapStyle = .round
                            arc.appendArc(withCenter:center,radius:radius,startAngle:90,endAngle:90-min(1,n/max(1,tile.upper))*360,clockwise:true)
                            accent.setStroke();if n>0 {arc.stroke()}
                        } else {text("—",small,NSRect(x:x+3,y:6,width:12,height:10),foreground)}
                        stacked(tile,x+21,textWidths[index])
                    }
                    x+=widths[index]+gap
                }
            }
            if let appearance {appearance.performAsCurrentDrawingAppearance(draw)} else {draw()}
            return true
        }
        let hasWarnings=warningsEnabled && tiles.contains{$0.metric == .cpu && (CPULoadBands.baseLevel($0.number) > .normal || CPULoadBands.samples($0.points).contains{$0.level > .normal})}
        image.isTemplate=theme == .system && !hasWarnings
        image.accessibilityDescription=tiles.map{tile in
            let level=warningsEnabled && tile.metric == .cpu ? CPULoadBands.current(tile.number,points:tile.points,at:ending):.normal
            return tile.metric.title+" "+tile.value+(tile.metric == .fan ? " RPM":"")+(level > .normal ? " · "+L(level.title):"")
        }.joined(separator:", ")
        return image
    }
    static func drawHistory(_ points:[MetricPoint],ending:Date,rect:NSRect,upper:Double,color:NSColor,bars:Bool,background:Bool,cpuWarnings:Bool=false,fillArea:Bool=true) {
        if background {color.withAlphaComponent(0.10).setFill();NSBezierPath(roundedRect:rect,xRadius:2,yRadius:2).fill()}
        let valid=points.filter{$0.date<=ending && $0.date>=ending.addingTimeInterval(-120)}
        if bars {
            let samples=cpuWarnings ? CPULoadBands.samples(valid):valid.map{CPULoadSample(point:$0,level:.normal)}
            var buckets:[Int:(value:Double,level:CPULoadLevel)]=[:]
            for sample in samples {
                guard sample.level != .unknown,let n=sample.point.value,n.isFinite,n>=0 else{continue}
                let bin=Int((sample.point.date.timeIntervalSince(ending.addingTimeInterval(-120))/120)*Double(max(1,Int(rect.width/3)-1)))
                let previous=buckets[bin]
                buckets[bin]=(max(previous?.value ?? 0,n),max(previous?.level ?? .normal,sample.level))
            }
            for (bin,sample) in buckets {
                sample.level.nativeColor(normal:color).setFill()
                NSBezierPath(roundedRect:NSRect(x:rect.minX+CGFloat(bin)*3,y:rect.minY,width:2,height:max(0.7,min(1,sample.value/max(1,upper))*rect.height)),xRadius:0.4,yRadius:0.4).fill()
            }
            return
        }
        let runs=cpuWarnings ? CPULoadBands.runs(valid):[CPULoadRun(id:0,level:.normal,points:valid)]
        for run in runs {
            let stroke=run.level.nativeColor(normal:color)
            var segment:[NSPoint]=[],previous:Int?
            func finish() {
                guard let first=segment.first,let last=segment.last else{return}
                let line=NSBezierPath();line.lineWidth=1.2;line.lineJoinStyle = .round;line.lineCapStyle = .round;line.move(to:first)
                for p in segment.dropFirst(){line.line(to:p)}
                if segment.count==1 {stroke.setFill();NSBezierPath(ovalIn:NSRect(x:first.x-0.7,y:first.y-0.7,width:1.4,height:1.4)).fill()}
                else {
                    if fillArea {let area=line.copy() as! NSBezierPath;area.line(to:NSPoint(x:last.x,y:rect.minY));area.line(to:NSPoint(x:first.x,y:rect.minY));area.close();stroke.withAlphaComponent(0.24).setFill();area.fill()}
                    stroke.setStroke();line.stroke()
                }
                segment=[]
            }
            for p in run.points {
                guard let n=p.value,n.isFinite,n>=0 else{finish();previous=nil;continue}
                if let previous,previous != p.segment {finish()}
                segment.append(NSPoint(x:rect.minX+min(1,max(0,p.date.timeIntervalSince(ending.addingTimeInterval(-120))/120))*rect.width,y:rect.minY+min(1,n/max(1,upper))*(rect.height-1)))
                previous=p.segment
            }
            finish()
        }
    }
}
