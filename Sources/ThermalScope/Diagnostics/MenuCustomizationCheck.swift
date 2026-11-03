import AppKit
import ThermalCore

@MainActor enum MenuCustomizationCheck {
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else {print("Use --menu-customization-check --ui-check for isolated preferences.");exit(2)}
        _=NSApplication.shared
        do {
            var font=MenuTypography();font.size = .nan
            guard font.safeSize==11.5 else{throw ScopeError.message("Invalid font size was not bounded")}
            font.size=40;guard font.safeSize==13 else{throw ScopeError.message("Large font was not bounded")}
            font.size=11.5;font.family = .monospaced;font.weight = .semibold
            guard try JSONDecoder().decode(MenuTypography.self,from:JSONEncoder().encode(font))==font else{throw ScopeError.message("Typography roundtrip failed")}
            guard MenuIconStore.label(" A\nB ",fallback:"CPU")=="AB",MenuIconStore.label("",fallback:"CPU")=="CPU",MenuIconStore.label("123456789",fallback:"CPU")=="12345678" else{throw ScopeError.message("Label normalization failed")}
            for metric in MenuMetric.allCases {for option in MenuIconOption.options(metric) {
                guard NSImage(systemSymbolName:option.symbol,accessibilityDescription:nil) != nil else{throw ScopeError.message("Unavailable built-in symbol: "+option.symbol)}
            }}
            let fixtureFolder=FileManager.default.temporaryDirectory.appendingPathComponent("ThermalScope-Icon-Check-"+UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:fixtureFolder,withIntermediateDirectories:true)
            let glyph=NSImage(size:NSSize(width:32,height:32),flipped:false) {_ in
                NSColor.white.setStroke();let path=NSBezierPath(ovalIn:NSRect(x:4,y:4,width:24,height:24));path.lineWidth=3;path.stroke();return true
            }
            guard let data=glyph.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data),let png=bitmap.representation(using:.png,properties:[:]) else{throw ScopeError.message("Fixture creation failed")}
            let url=fixtureFolder.appendingPathComponent("glyph.png");try png.write(to:url)
            try url.path.write(toFile:"/tmp/thermalscope-menu-icon-fixture-path.txt",atomically:true,encoding:.utf8)
            let token=try MenuIconStore.importImage(url,preview:true)
            guard case .image(let imported)=MenuIconStore.icon(token,metric:.cpu,preview:true),imported.isValid else{throw ScopeError.message("Imported icon was not resolved")}
            let thumbnail=MenuIconStore.thumbnail(imported)
            guard thumbnail.size==NSSize(width:14,height:14),thumbnail.isTemplate else{throw ScopeError.message("Native menu thumbnail size was not bounded")}
            guard case .automatic=MenuIconStore.icon("image:../../private",metric:.cpu,preview:true) else{throw ScopeError.message("Invalid image token accepted")}
            guard case .automatic=MenuIconStore.icon("sf:not-a-real-symbol",metric:.cpu,preview:true) else{throw ScopeError.message("Unknown symbol token accepted")}
            var count=0
            for dark in [false,true] {for family in MenuFontFamily.allCases {for size in [10.0,11.5,13] {for style in MenuTileStyle.allCases {
                var typography=MenuTypography();typography.family=family;typography.size=size
                var tile=MenuBarTile(metric:.cpu,style:style,label:"CPU",value:"0%",number:0,points:[],upper:100,color:nil,icon:.image(imported))
                func render(_ tile:MenuBarTile)->NSImage {MenuBarAppearanceRenderer.image(tiles:[tile],ending:Date(),spacing:0,graphWidth:100,background:false,appearance:NSAppearance(named:dark ? .darkAqua:.aqua),warningsEnabled:false,typography:typography)}
                let zero=render(tile);tile=MenuBarTile(metric:.cpu,style:style,label:"CPU",value:"100%",number:100,points:[],upper:100,color:nil,icon:.image(imported))
                let full=render(tile)
                let compactWidth=[MenuTileStyle.icon,.history,.bars].contains(style) ? zero.size.width==full.size.width:zero.size.width<full.size.width
                guard compactWidth,zero.size.height==22,full.size.height==22,let data=zero.tiffRepresentation,let pixels=NSBitmapImageRep(data:data) else{throw ScopeError.message("Values still reserve unused digits or failed to render")}
                var alpha:CGFloat=0
                for y in 0..<pixels.pixelsHigh {for x in 0..<pixels.pixelsWide {alpha+=pixels.colorAt(x:x,y:y)?.alphaComponent ?? 0}}
                guard alpha>1 else{throw ScopeError.message("Customized menu item became invisible")}
                count+=1
            }}}}
            let paddingFixtures:[ [MenuBarTile] ]=[
                [MenuBarTile(metric:.cpu,style:.value,label:"CPU",value:"26%",number:26,points:[],upper:100),
                 MenuBarTile(metric:.temperature,style:.value,label:"",value:"23.92 W",number:23.92,points:[],upper:100,sensor:MenuSensorReference(key:"PSTR",kind:.power))],
                MenuTileStyle.allCases.map{MenuBarTile(metric:.cpu,style:$0,label:"CPU",value:"26%",number:26,points:[],upper:100,color:$0 == .ring ? .systemBlue:nil,icon:.symbol("cpu"))}
            ]
            guard MenuBarLayout.spacing(nil)==18,MenuBarLayout.spacing(.nan)==18,MenuBarLayout.spacing(0)==0 else{throw ScopeError.message("Native-aligned default or zero spacing override failed")}
            for tiles in paddingFixtures {
                let ending=Date()
                let compact=MenuBarAppearanceRenderer.image(tiles:tiles,ending:ending,spacing:0,graphWidth:44,background:false)
                let aligned=MenuBarAppearanceRenderer.image(tiles:tiles,ending:ending,spacing:MenuBarLayout.defaultSpacing,graphWidth:44,background:false)
                guard aligned.size.width==compact.size.width+CGFloat(tiles.count-1)*18 else{throw ScopeError.message("Native-aligned component spacing was clipped")}
            }
            for dark in [false,true] {for tiles in paddingFixtures {
                let ending=Date(),appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
                func image(_ padding:Double)->NSImage {MenuBarAppearanceRenderer.image(tiles:tiles,ending:ending,spacing:2,graphWidth:44,background:true,appearance:appearance,warningsEnabled:false,outerPadding:padding)}
                let plain=image(0),padded=image(12)
                guard padded.size.width==plain.size.width+24,padded.size.height==plain.size.height,padded.isTemplate==plain.isTemplate,
                      let plainData=plain.tiffRepresentation,let paddedData=padded.tiffRepresentation,
                      let a=NSBitmapImageRep(data:plainData),let b=NSBitmapImageRep(data:paddedData),a.pixelsHigh==b.pixelsHigh else{throw ScopeError.message("Outer padding changed the content size or color mode")}
                let inset=Int((12*CGFloat(a.pixelsWide)/plain.size.width).rounded())
                guard b.pixelsWide==a.pixelsWide+inset*2 else{throw ScopeError.message("Outer padding was not symmetric")}
                for y in 0..<b.pixelsHigh {for x in 0..<b.pixelsWide {
                    guard let c=b.colorAt(x:x,y:y)?.usingColorSpace(.sRGB) else{throw ScopeError.message("Padded menu pixels unavailable")}
                    if x<inset || x>=b.pixelsWide-inset {
                        guard c.alphaComponent<0.01 else{throw ScopeError.message("Outer padding did not stay transparent")}
                    } else {
                        guard let p=a.colorAt(x:x-inset,y:y)?.usingColorSpace(.sRGB),
                              abs(p.alphaComponent-c.alphaComponent)<0.02,
                              abs(p.redComponent*p.alphaComponent-c.redComponent*c.alphaComponent)<0.02,
                              abs(p.greenComponent*p.alphaComponent-c.greenComponent*c.alphaComponent)<0.02,
                              abs(p.blueComponent*p.alphaComponent-c.blueComponent*c.alphaComponent)<0.02 else{throw ScopeError.message("Outer padding moved or changed an individual component")}
                    }
                }}
            }}
            for tile in paddingFixtures[0] {
                let plain=MenuBarAppearanceRenderer.image(tiles:[tile],ending:Date(),spacing:0,graphWidth:44,background:false)
                let padded=MenuBarAppearanceRenderer.image(tiles:[tile],ending:Date(),spacing:0,graphWidth:44,background:false,innerPadding:8)
                guard padded.size.width==plain.size.width+16,padded.size.height==plain.size.height else{throw ScopeError.message("Component inner padding was not independently applied")}
            }
            func preferences()->NSDictionary {NSDictionary(dictionary:UserDefaults.standard.dictionaryRepresentation().filter{$0.key.hasPrefix("menu")})}
            let before=preferences(),model=AppModel()
            model.menuComposition=nil;model.menuItems=[.cpu,.temperature];model.menuStyle="custom"
            model.menuTileStyles["cpu"]=MenuTileStyle.icon.rawValue
            model.setMenuIcon("none",for:.cpu)
            guard model.menuTileStyles["cpu"]==MenuTileStyle.value.rawValue else{throw ScopeError.message("Removing the sole icon did not preserve a readable value")}
            model.setMenuIcon(token,for:.cpu);model.menuTileLabels["cpu"]="CORE"
            model.menuTypography=font;model.menuSpacing=12;model.menuOuterPadding=12;model.menuInnerPadding=6;model.menuGraphWidth=100;model.menuDividers=true
            model.applyMenuPreset(1)
            guard model.menuOuterPadding==12,model.menuInnerPadding==6,model.menuSpacing==18 else{throw ScopeError.message("Preset spacing defaults or independent padding were not preserved")}
            guard before.isEqual(preferences()) else{throw ScopeError.message("UI check changed saved appearance preferences")}
            print("PASS: \(count) light/dark font/style/icon combinations retain visible pixels and natural value widths; whole-group outer padding adds symmetric transparent edges without changing component pixels or gaps; native-aligned 18 pt default spacing, zero override, independent inner padding and isolated UI preferences verified. No hardware writes.")
        } catch {print("FAIL: "+error.localizedDescription);exit(1)}
    }
}
