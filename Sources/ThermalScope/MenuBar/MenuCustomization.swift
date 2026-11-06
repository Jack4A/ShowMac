import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ThermalCore

enum MenuFontFamily:String,Codable,CaseIterable,Identifiable {
    case system,rounded,monospaced
    var id:String {rawValue}
    var title:String {switch self {case .system:return "系统字体";case .rounded:return "圆角字体";case .monospaced:return "等宽字体"}}
}
enum MenuFontWeight:String,Codable,CaseIterable,Identifiable {
    case regular,medium,semibold
    var id:String {rawValue}
    var title:String {switch self {case .regular:return "常规";case .medium:return "中等";case .semibold:return "半粗"}}
    var native:NSFont.Weight {switch self {case .regular:return .regular;case .medium:return .medium;case .semibold:return .semibold}}
}
struct MenuTypography:Codable,Equatable {
    var family:MenuFontFamily = .system
    var weight:MenuFontWeight = .medium
    var size:Double=11.5
    static let standard=Self()
    var safeSize:CGFloat {size.isFinite ? min(13,max(10,size)):11.5}
    var numberFont:NSFont {
        if family == .monospaced {return .monospacedSystemFont(ofSize:safeSize,weight:weight.native)}
        let base=NSFont.monospacedDigitSystemFont(ofSize:safeSize,weight:weight.native)
        if family == .rounded,let descriptor=base.fontDescriptor.withDesign(.rounded),let font=NSFont(descriptor:descriptor,size:safeSize) {return font}
        return base
    }
    var labelFont:NSFont {.systemFont(ofSize:min(8.5,max(7.5,safeSize*0.69)),weight:.medium)}
}

struct MenuIconOption:Identifiable {
    let symbol:String
    let title:String
    var id:String {symbol}
    static func options(_ metric:MenuMetric)->[Self] {
        switch metric {
        case .tokens:return [.init(symbol:"number.circle",title:"Token"),.init(symbol:"sparkles",title:"AI"),.init(symbol:"chart.bar",title:"柱状图")]
        case .tokenQuota:return [.init(symbol:"chart.pie",title:"额度"),.init(symbol:"gauge",title:"余量"),.init(symbol:"hourglass",title:"重置时间")]
        case .cpu:return [.init(symbol:"cpu",title:"处理器"),.init(symbol:"chart.bar",title:"柱状图"),.init(symbol:"waveform.path",title:"波形")]
        case .temperature:return [.init(symbol:"thermometer.medium",title:"温度计"),.init(symbol:"thermometer.sun",title:"温度与太阳"),.init(symbol:"flame",title:"火焰")]
        case .gpu:return [.init(symbol:"display",title:"显示器"),.init(symbol:"cpu",title:"芯片"),.init(symbol:"square.stack.3d.up",title:"图层")]
        case .fan:return [.init(symbol:"fanblades",title:"风扇"),.init(symbol:"wind",title:"风"),.init(symbol:"leaf",title:"叶片")]
        case .battery:return [.init(symbol:"battery.75percent",title:"电池"),.init(symbol:"bolt",title:"闪电"),.init(symbol:"bolt.batteryblock",title:"电池与闪电")]
        }
    }
    static func options(_ component:MenuBarComponent)->[Self] {
        guard let sensor=component.sensor else{return options(component.metric)}
        return [.init(symbol:sensor.symbol,title:sensor.kind.title),.init(symbol:"waveform.path",title:"波形"),.init(symbol:"chart.bar",title:"柱状图")]
    }
}
enum MenuBarIcon {
    case automatic,hidden,symbol(String),image(NSImage)
}

@MainActor enum MenuIconStore {
    private static let cache=NSCache<NSString,NSImage>()
    static func directory(preview:Bool)->URL {
        let base=preview ? FileManager.default.temporaryDirectory.appendingPathComponent("ThermalScope-UI-Icons",isDirectory:true):
            (FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("ThermalScope/MenuIcons",isDirectory:true)
        return base
    }
    static func icon(_ token:String?,metric:MenuMetric,preview:Bool,options:[MenuIconOption]?=nil)->MenuBarIcon {
        guard let token else{return .automatic}
        if token=="none" {return .hidden}
        if token.hasPrefix("sf:") {
            let name=String(token.dropFirst(3))
            return (options ?? MenuIconOption.options(metric)).contains{$0.symbol==name} ? .symbol(name):.automatic
        }
        guard token.hasPrefix("image:"),let id=UUID(uuidString:String(token.dropFirst(6))) else{return .automatic}
        let url=directory(preview:preview).appendingPathComponent(id.uuidString+".png")
        let key=url.path as NSString
        if let image=cache.object(forKey:key) {return .image(image)}
        guard let image=NSImage(contentsOf:url),image.isValid else{return .automatic}
        cache.setObject(image,forKey:key)
        return .image(image)
    }
    static func importImage(_ url:URL,preview:Bool)throws->String {
        let data=try Data(contentsOf:url,options:.mappedIfSafe)
        guard data.count<=5*1024*1024,let source=NSImage(data:data),source.isValid,
              source.size.width.isFinite,source.size.height.isFinite,
              source.size.width>0,source.size.height>0,max(source.size.width,source.size.height)<=10000 else {
            throw ScopeError.message("图标图片无法读取，请选择 5 MB 以内的 PNG、JPEG、TIFF 或 PDF。")
        }
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:64,pixelsHigh:64,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
              let context=NSGraphicsContext(bitmapImageRep:bitmap) else {throw ScopeError.message("无法准备图标图片。")}
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
        context.cgContext.clear(CGRect(x:0,y:0,width:64,height:64))
        let scale=min(60/source.size.width,60/source.size.height)
        let size=NSSize(width:source.size.width*scale,height:source.size.height*scale)
        source.draw(in:NSRect(x:(64-size.width)/2,y:(64-size.height)/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png=bitmap.representation(using:.png,properties:[:]) else{throw ScopeError.message("无法准备图标图片。")}
        let folder=directory(preview:preview)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let id=UUID().uuidString
        try png.write(to:folder.appendingPathComponent(id+".png"),options:.atomic)
        return "image:"+id
    }
    static func label(_ raw:String?,fallback:String)->String {
        let cleaned=(raw ?? "").components(separatedBy:.controlCharacters).joined().trimmingCharacters(in:.whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback:String(cleaned.prefix(8))
    }
    static func thumbnail(_ image:NSImage)->NSImage {
        // Native Menu buttons extract the NSImage and ignore SwiftUI resizing.
        let thumbnail=NSImage(size:NSSize(width:14,height:14),flipped:false) {rect in image.draw(in:rect);return true}
        thumbnail.isTemplate=true
        return thumbnail
    }
}

extension AppModel {
    func setMenuIcon(_ token:String,for metric:MenuMetric) {
        menuTileIcons[metric.rawValue]=token
        let style=MenuTileStyle(rawValue:menuTileStyles[metric.rawValue] ?? "") ?? metric.defaultTileStyle
        if token=="none",style == .icon {menuTileStyles[metric.rawValue]=MenuTileStyle.value.rawValue}
        else if token != "auto",token != "none",style == .value {menuTileStyles[metric.rawValue]=MenuTileStyle.iconValue.rawValue}
    }
    func chooseMenuIcon(_ metric:MenuMetric,componentID:String?=nil) {
        let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        panel.allowedContentTypes=[.png,.jpeg,.tiff,.pdf]
        panel.message=L("选择透明背景的图标，状态栏会使用单色轮廓显示。")
        panel.begin { [weak self] response in
            guard response == .OK,let self,let url=panel.url else{return}
            do {
                let token=try MenuIconStore.importImage(url,preview:self.isFanControlPreview)
                if let componentID {self.setMenuComponentIcon(token,id:componentID)}
                else {self.setMenuIcon(token,for:metric)}
            }
            catch {self.report(error.localizedDescription,error:true)}
        }
    }
}
