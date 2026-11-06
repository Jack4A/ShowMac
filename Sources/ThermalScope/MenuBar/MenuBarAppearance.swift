import AppKit
import SwiftUI
import ThermalCore
import CoreText

enum MenuTileStyle:String,CaseIterable,Identifiable,Codable {
    case stacked,value,icon,history,bars,ring,historyValue,iconValue
    var id:String {rawValue}
    var title:String {switch self {case .stacked:return "双行数值";case .value:return "单行数值";case .icon:return "仅图标";case .history:return "面积历史";case .bars:return "柱形历史";case .ring:return "圆环与数值";case .historyValue:return "曲线与数值";case .iconValue:return "图标与数值"}}
}
enum MenuBarPreset:Int,CaseIterable,Identifiable {
    case minimal,graphs,gauges
    var id:Int {rawValue}
    var title:String {["极简","曲线组合","仪表组合"][rawValue]}
    var items:[MenuMetric] {self == .minimal ? [.temperature,.cpu]:[.temperature,.cpu,.fan]}
    var styles:[String:String] {switch self {case .minimal:return ["temperature":"iconValue","cpu":"iconValue"];case .graphs:return ["temperature":"iconValue","cpu":"historyValue","fan":"iconValue"];case .gauges:return ["temperature":"iconValue","cpu":"ring","fan":"bars"]}}
    var background:Bool {self == .graphs}
}
extension MenuMetric {
    var historyKind:MetricKind {switch self {case .cpu:return .cpuUsage;case .temperature:return .cpuTemperature;case .gpu:return .gpuTemperature;case .fan:return .fan;case .battery:return .battery;case .tokens,.tokenQuota:return .cpuUsage}}
    var barLabel:String {switch self {case .cpu:return "CPU";case .temperature:return ["zh","ja","ko"].contains(where:{AppLocalization.shared.resolvedLanguage.hasPrefix($0)}) ? L("温度"):"TEMP";case .gpu:return "GPU";case .fan:return "RPM";case .battery:return L("电池");case .tokens:return "Token";case .tokenQuota:return L("余量")}}
    var reservedValue:String {switch self {case .cpu,.battery:return "100%";case .temperature,.gpu:return "130°";case .fan:return "30000";case .tokens:return "999.9M";case .tokenQuota:return "100%"}}
    var defaultTileStyle:MenuTileStyle {self == .cpu ? .historyValue:.iconValue}
    @MainActor func barNumber(_ readings:LiveReadings)->Double? {
        let n:Double?
        switch self {case .cpu:n=readings.snapshot?.cpuUsage;case .temperature:n=readings.snapshot?.cpuTemperature;case .gpu:n=readings.snapshot?.temperature(.gpu);case .fan:n=readings.snapshot?.fans.compactMap(\.rpm).max();case .battery:n=readings.telemetry?.batteryPercent;case .tokens,.tokenQuota:n=nil}
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
    var color:NSColor?=nil
    var icon:MenuBarIcon = .automatic
    var sensor:MenuSensorReference?
    var displayTitle:String?
    var lower:Double=0
    var historyRange:DateInterval?
    var warningKind:MetricKind? {
        if let sensor {return MetricWarningBands.kind(sensor:sensor)}
        return metric.isToken ? nil:metric.historyKind
    }
}
enum MenuBarLayout {
    // Matches the visible spacing of adjacent native status items at the default font.
    static let defaultSpacing=18.0
    static let spacingRange=0.0...24.0
    static func spacing(_ value:Double?)->Double {
        guard let value,value.isFinite else{return defaultSpacing}
        return min(spacingRange.upperBound,max(spacingRange.lowerBound,value))
    }
}
enum MenuBarAppearanceRenderer {
    static func color(hex:String?)->NSColor? {
        guard let hex,hex.count==6,let n=UInt32(hex,radix:16) else{return nil}
        return NSColor(srgbRed:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255,alpha:1)
    }
    static func hex(_ color:NSColor)->String? {
        guard let c=color.usingColorSpace(.sRGB) else{return nil}
        return String(format:"%02X%02X%02X",Int((min(1,max(0,c.redComponent))*255).rounded()),Int((min(1,max(0,c.greenComponent))*255).rounded()),Int((min(1,max(0,c.blueComponent))*255).rounded()))
    }
    @MainActor static func tiles(model:AppModel,preset:MenuBarPreset?=nil)->[MenuBarTile] {
        if preset==nil {
            let sensors=Dictionary(grouping:model.menuSensorOptions,by:\.id).mapValues{$0[0]}
            return model.effectiveMenuComponents.map{tile(component:$0,model:model,sensors:sensors)}
        }
        return (preset?.items ?? model.menuItems).map {metric in
            let n=metric.barNumber(model.readings),points=model.metricHistory.points(metric.historyKind,minutes:2)
            let upper=max(metric.historyKind.fixedUpper,points.compactMap(\.value).max() ?? 0,n ?? 0)
            let value=n.map{String(format:"%.0f",$0)} ?? "—"
            let unit=metric == .cpu || metric == .battery ? "%":(metric == .fan ? "":"°")
            return MenuBarTile(metric:metric,style:MenuTileStyle(rawValue:(preset?.styles ?? model.menuTileStyles)[metric.rawValue] ?? "") ?? metric.defaultTileStyle,label:MenuIconStore.label(preset == nil ? model.menuTileLabels[metric.rawValue]:nil,fallback:metric.barLabel),value:value+unit,number:n,points:points,upper:upper,color:color(hex:preset == nil ? model.menuTileColors[metric.rawValue]:nil),icon:preset == nil ? MenuIconStore.icon(model.menuTileIcons[metric.rawValue],metric:metric,preview:model.isFanControlPreview):.automatic)
        }
    }
    @MainActor static func tile(component:MenuBarComponent,model:AppModel,sensors:[String:MenuSensorOption]?=nil)->MenuBarTile {
        if let sensor=component.sensor {
            let option=sensors?[sensor.id] ?? (sensors==nil ? model.menuSensorOptions.first{$0.reference==sensor}:nil)
            let n=option?.value,points=model.sensorHistory.menuPoints(for:sensor)
            let values=points.compactMap(\.value)+(n.map{[$0]} ?? [])
            let title=option.map{$0.title+(sensor.isCommon ? "":" · "+sensor.key)} ?? sensor.fallbackTitle
            return MenuBarTile(metric:component.metric,style:component.style,label:"",value:sensorValueText(n,kind:sensor.kind),number:n,points:points,upper:max(sensor.upper,values.max() ?? 0),color:color(hex:component.colorHex),icon:MenuIconStore.icon(component.icon,metric:component.metric,preview:model.isFanControlPreview,options:MenuIconOption.options(component)),sensor:sensor,displayTitle:title,lower:min(0,values.min() ?? 0))
        }
        if component.metric.isToken {
            let value=model.tokenMenuReading(metric:component.metric,configuration:component.token ?? TokenMenuConfiguration())
            var icon=MenuIconStore.icon(component.icon,metric:component.metric,preview:model.isFanControlPreview)
            let provider=component.token?.tool ?? (component.metric == .tokenQuota ? TokenProvider.codex:nil)
            if component.icon==nil || component.icon=="auto",let provider,let artwork=AgentProviderArtwork.image(provider) {icon = .image(artwork)}
            return MenuBarTile(metric:component.metric,style:component.style,label:MenuIconStore.label(component.label,fallback:component.metric.barLabel),value:value.text,number:value.number,points:value.points,upper:value.upper,color:color(hex:component.colorHex),icon:icon,displayTitle:value.title,historyRange:value.range)
        }
        let metric=component.metric,n=metric.barNumber(model.readings)
        let points=model.metricHistory.points(metric.historyKind,minutes:2)
        let upper=max(metric.historyKind.fixedUpper,points.compactMap(\.value).max() ?? 0,n ?? 0)
        let value=n.map{String(format:"%.0f",$0)} ?? "—"
        let unit=metric == .cpu || metric == .battery ? "%":(metric == .fan ? "":"°")
        return MenuBarTile(metric:metric,style:component.style,label:MenuIconStore.label(component.label,fallback:metric.barLabel),value:value+unit,number:n,points:points,upper:upper,color:color(hex:component.colorHex),icon:MenuIconStore.icon(component.icon,metric:metric,preview:model.isFanControlPreview))
    }
    static func image(tiles:[MenuBarTile],ending:Date,spacing:Double,graphWidth:Double,background:Bool,appearance:NSAppearance?=nil,warningsEnabled:Bool=true,typography:MenuTypography = .standard,dividers:Bool=false,outerPadding:Double=0,innerPadding:Double=0)->NSImage {
        let small=typography.labelFont,large=typography.numberFont
        let gap:CGFloat=MenuBarLayout.spacing(spacing)
        let inset:CGFloat=outerPadding.isFinite ? min(20,max(0,outerPadding)):0
        let inner:CGFloat=innerPadding.isFinite ? min(20,max(0,innerPadding)):0
        // Breathing room between an icon, sparkline or gauge and its value digits.
        let iconGap:CGFloat=4
        let plotWidth:CGFloat=graphWidth.isFinite ? min(100,max(28,graphWidth)):44
        func measured(_ s:String,_ font:NSFont)->CGFloat {(s as NSString).size(withAttributes:[.font:font]).width.rounded(.up)}
        let textWidths=tiles.map {measured($0.value,large)}
        let icons=tiles.map {tile -> NSImage? in
            let fallback=NSImage(systemSymbolName:AppSymbols.resolve(tile.sensor?.symbol ?? tile.metric.symbol),accessibilityDescription:nil)
            switch tile.icon {
            case .automatic:return [.icon,.iconValue,.history,.bars].contains(tile.style) ? fallback:nil
            case .hidden:return tile.style == .icon ? fallback:nil
            case .symbol(let name):return NSImage(systemSymbolName:AppSymbols.resolve(name),accessibilityDescription:nil) ?? fallback
            case .image(let image):return image
            }
        }
        let prefixWidths=tiles.enumerated().map {index,tile -> CGFloat in
            guard icons[index] != nil,tile.style != .icon else{return 0}
            return ([.history,.bars].contains(tile.style) ? 11:14)+iconGap
        }
        let widths=tiles.enumerated().map {index,tile -> CGFloat in
            let core:CGFloat
            switch tile.style {
            case .value,.stacked,.iconValue:core=textWidths[index]
            case .icon:core=15
            case .history,.bars:core=plotWidth
            case .ring:core=18+iconGap+textWidths[index]
            case .historyValue:core=plotWidth+iconGap+textWidths[index]
            }
            return core+prefixWidths[index]+inner*2
        }
        let width=max(1,widths.reduce(0,+)+CGFloat(max(0,tiles.count-1))*gap+inset*2)
        let image=NSImage(size:NSSize(width:width,height:22),flipped:false) {_ in
            func draw() {
                let dark=(appearance ?? NSAppearance.currentDrawing()).bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
                let foreground=dark ? NSColor.white:NSColor.black
                func text(_ value:String,_ font:NSFont,_ x:CGFloat,_ width:CGFloat,_ baseline:CGFloat,_ color:NSColor) {
                    guard let context=NSGraphicsContext.current?.cgContext else{return}
                    let line=CTLineCreateWithAttributedString(NSAttributedString(string:value,attributes:[.font:font,.foregroundColor:color]))
                    let lineWidth=CGFloat(CTLineGetTypographicBounds(line,nil,nil,nil))
                    context.saveGState();context.textMatrix = .identity
                    context.textPosition=CGPoint(x:x+(width-lineWidth)/2,y:baseline)
                    CTLineDraw(line,context);context.restoreGState()
                }
                func alignedValue(_ tile:MenuBarTile,_ x:CGFloat,_ width:CGFloat,_ color:NSColor) {
                    text(tile.value,large,x,width,(22-large.capHeight)/2,color)
                }
                func symbol(_ icon:NSImage,_ x:CGFloat,_ size:CGFloat,_ color:NSColor) {
                    let tinted=NSImage(size:NSSize(width:size,height:size),flipped:false) {rect in
                        icon.draw(in:rect);color.setFill();rect.fill(using:.sourceAtop);return true
                    }
                    tinted.draw(in:NSRect(x:x,y:(22-size)/2,width:size,height:size))
                }
                var x:CGFloat=inset
                for (index,tile) in tiles.enumerated() {
                    let baseColor=tile.color ?? foreground
                    let warningKind=warningsEnabled ? tile.warningKind:nil
                    let level=MetricWarningBands.current(tile.number,points:tile.points,at:ending,kind:warningKind)
                    let accent=level.nativeColor(normal:baseColor)
                    let valueColor=tile.color != nil ? accent:foreground
                    let start=x+inner+prefixWidths[index]
                    let plotEnd=tile.historyRange?.end ?? ending
                    let plotDuration=tile.historyRange?.duration ?? 120
                    if let icon=icons[index] {
                        symbol(icon,x+inner,tile.style == .icon ? 15:([.history,.bars].contains(tile.style) ? 11:14),accent)
                    }
                    switch tile.style {
                    case .stacked:alignedValue(tile,start,textWidths[index],valueColor)
                    case .value,.iconValue:text(tile.value,large,start,textWidths[index],(22-large.capHeight)/2,valueColor)
                    case .icon:break
                    case .history,.bars:
                        drawHistory(tile.points,ending:plotEnd,rect:NSRect(x:start,y:3,width:plotWidth,height:16),upper:tile.upper,color:baseColor,bars:tile.style == .bars,background:false,fillArea:background,lower:tile.lower,warningKind:warningKind,duration:plotDuration)
                        if !tile.points.contains(where:{$0.value != nil && $0.date<=plotEnd && $0.date>=plotEnd.addingTimeInterval(-plotDuration)}) {
                            text("—",small,start,plotWidth,7,foreground)
                        }
                    case .historyValue:
                        drawHistory(tile.points,ending:plotEnd,rect:NSRect(x:start,y:3,width:plotWidth,height:16),upper:tile.upper,color:baseColor,bars:false,background:false,fillArea:background,lower:tile.lower,warningKind:warningKind,duration:plotDuration)
                        alignedValue(tile,start+plotWidth+iconGap,textWidths[index],valueColor)
                    case .ring:
                        let center=NSPoint(x:start+9,y:11),radius:CGFloat=7.5
                        let track=NSBezierPath();track.lineWidth=2.4;track.appendArc(withCenter:center,radius:radius,startAngle:90,endAngle:450)
                        foreground.withAlphaComponent(0.17).setStroke();track.stroke()
                        if let n=tile.number {
                            let arc=NSBezierPath();arc.lineWidth=2.4;arc.lineCapStyle = .round
                            arc.appendArc(withCenter:center,radius:radius,startAngle:90,endAngle:90-min(1,n/max(1,tile.upper))*360,clockwise:true)
                            accent.setStroke();if n>0 {arc.stroke()}
                        } else {text("—",small,start+3,12,7,foreground)}
                        alignedValue(tile,start+18+iconGap,textWidths[index],valueColor)
                    }
                    if dividers,index<tiles.count-1 {
                        let line=NSBezierPath();line.lineWidth=0.5
                        let dividerX=x+widths[index]+gap/2
                        line.move(to:NSPoint(x:dividerX,y:5));line.line(to:NSPoint(x:dividerX,y:17))
                        foreground.withAlphaComponent(0.25).setStroke();line.stroke()
                    }
                    x+=widths[index]+gap
                }
            }
            if let appearance {appearance.performAsCurrentDrawingAppearance(draw)} else {draw()}
            return true
        }
        let hasWarnings=warningsEnabled && tiles.contains{MetricWarningBands.level($0.number,kind:$0.warningKind) > .normal || MetricWarningBands.samples($0.points,kind:$0.warningKind).contains{$0.level > .normal}}
        image.isTemplate=tiles.allSatisfy{$0.color==nil} && !hasWarnings
        image.accessibilityDescription=tiles.map{tile in
            let level=MetricWarningBands.current(tile.number,points:tile.points,at:ending,kind:tile.warningKind,enabled:warningsEnabled)
            return (tile.displayTitle ?? tile.metric.title)+" "+tile.value+(tile.sensor==nil && tile.metric == .fan ? " RPM":"")+(level > .normal ? " · "+L(MetricWarningBands.title(level,kind:tile.warningKind)):"")
        }.joined(separator:", ")
        return image
    }
    static func drawHistory(_ points:[MetricPoint],ending:Date,rect:NSRect,upper:Double,color:NSColor,bars:Bool,background:Bool,fillArea:Bool=true,lower:Double=0,warningKind:MetricKind?=nil,duration:Double=120) {
        func fraction(_ value:Double)->CGFloat {min(1,max(0,(value-lower)/max(1,upper-lower)))}
        let baseline=rect.minY+fraction(0)*rect.height
        if background {color.withAlphaComponent(0.10).setFill();NSBezierPath(roundedRect:rect,xRadius:2,yRadius:2).fill()}
        let valid=points.filter{$0.date<=ending && $0.date>=ending.addingTimeInterval(-duration)}
        if bars {
            let samples=MetricWarningBands.samples(valid,kind:warningKind)
            var buckets:[Int:(value:Double,level:CPULoadLevel)]=[:]
            for sample in samples {
                guard sample.level != .unknown,let n=sample.point.value,n.isFinite,n>=lower else{continue}
                let bin=Int((sample.point.date.timeIntervalSince(ending.addingTimeInterval(-duration))/max(1,duration))*Double(max(1,Int(rect.width/3)-1)))
                let previous=buckets[bin]
                buckets[bin]=(previous.map{abs($0.value)>abs(n) ? $0.value:n} ?? n,max(previous?.level ?? .normal,sample.level))
            }
            for (bin,sample) in buckets {
                sample.level.nativeColor(normal:color).setFill()
                let y=rect.minY+fraction(sample.value)*rect.height
                NSBezierPath(roundedRect:NSRect(x:rect.minX+CGFloat(bin)*3,y:min(baseline,y),width:2,height:max(0.7,abs(y-baseline))),xRadius:0.4,yRadius:0.4).fill()
            }
            return
        }
        let runs=MetricWarningBands.runs(valid,kind:warningKind)
        for run in runs {
            let stroke=run.level.nativeColor(normal:color)
            var segment:[NSPoint]=[],previous:Int?
            func finish() {
                guard let first=segment.first,let last=segment.last else{return}
                let line=NSBezierPath();line.lineWidth=1.2;line.lineJoinStyle = .round;line.lineCapStyle = .round;line.move(to:first)
                for p in segment.dropFirst(){line.line(to:p)}
                if segment.count==1 {stroke.setFill();NSBezierPath(ovalIn:NSRect(x:first.x-0.7,y:first.y-0.7,width:1.4,height:1.4)).fill()}
                else {
                    if fillArea {
                        let area=line.copy() as! NSBezierPath
                        area.line(to:NSPoint(x:last.x,y:baseline));area.line(to:NSPoint(x:first.x,y:baseline));area.close()
                        NSGradient(starting:stroke.withAlphaComponent(0.02),ending:stroke.withAlphaComponent(0.24))?.draw(in:area,angle:first.y>=baseline ? 90:270)
                    }
                    stroke.setStroke();line.stroke()
                }
                segment=[]
            }
            for p in run.points {
                guard let n=p.value,n.isFinite,n>=lower else{finish();previous=nil;continue}
                if let previous,previous != p.segment {finish()}
                segment.append(NSPoint(x:rect.minX+min(1,max(0,p.date.timeIntervalSince(ending.addingTimeInterval(-duration))/max(1,duration)))*rect.width,y:rect.minY+fraction(n)*(rect.height-1)))
                previous=p.segment
            }
            finish()
        }
    }
}
