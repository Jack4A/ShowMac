import AppKit
import ThermalCore

/// Synthetic display fixtures only; never applied to live readings or fan controls.
@MainActor enum CurveWarningCheck {
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else{print("Use --curve-warning-check --ui-check.");exit(2)}
        _=NSApplication.shared
        do {
            func require(_ value:Bool,_ message:String)throws {if !value {throw ScopeError.message(message)}}
            let origin=Date(timeIntervalSince1970:1000)
            func points(_ values:[Double?])->[MetricPoint] {values.enumerated().map{MetricPoint(date:origin.addingTimeInterval(Double($0.offset*5)),value:$0.element,segment:0)}}
            let cpu=points([60,70,92,94,95,40])
            try require(MetricWarningBands.samples(cpu,kind:.cpuUsage).map(\.level)==[.normal,.elevated,.elevated,.elevated,.critical,.normal],"CPU thresholds or sustained timing changed")
            for kind in [MetricKind.cpuTemperature,.gpuTemperature] {
                let values:[Double?]=kind == .cpuTemperature ? [60,80,90,85,60]:[60,75,85,80,60]
                let history=points(values),ending=history.last!.date
                try require(MetricWarningBands.samples(history,kind:kind).map(\.level)==[.normal,.elevated,.critical,.elevated,.normal],"Temperature color boundaries failed")
                let runs=MetricWarningBands.runs(history,kind:kind)
                try require(Set(runs.flatMap(\.points).map(\.date))==Set(history.map(\.date)),"Warning runs lost actual samples")
                for dark in [false,true] {for style in [MenuTileStyle.history,.historyValue,.bars] {
                    let tile=MenuBarTile(metric:kind == .cpuTemperature ? .temperature:.gpu,style:style,label:"TEMP",value:"60°",number:60,points:history,upper:130)
                    let image=MenuBarAppearanceRenderer.image(tiles:[tile],ending:ending,spacing:0,graphWidth:100,background:false,appearance:NSAppearance(named:dark ? .darkAqua:.aqua))
                    guard !image.isTemplate,let data=image.tiffRepresentation,let pixels=NSBitmapImageRep(data:data) else{throw ScopeError.message("Temperature warning image remained monochrome")}
                    var orange=0,red=0
                    for y in 0..<pixels.pixelsHigh {for x in 0..<pixels.pixelsWide {
                        guard let c=pixels.colorAt(x:x,y:y)?.usingColorSpace(.sRGB),c.alphaComponent>0.5 else{continue}
                        if c.redComponent>0.7 && c.greenComponent<0.5 && c.blueComponent<0.6 {red+=1}
                        if c.redComponent>0.7 && c.greenComponent>0.5 && c.greenComponent<0.85 && c.blueComponent<0.4 {orange+=1}
                    }}
                    try require(red>0 && orange>0,"Temperature curve warning pixels missing")
                    let disabled=MenuBarAppearanceRenderer.image(tiles:[tile],ending:ending,spacing:0,graphWidth:100,background:false,warningsEnabled:false)
                    try require(disabled.isTemplate,"Disabling curve warnings did not restore automatic monochrome")
                }}
            }
            let broken=[MetricPoint(date:origin,value:80,segment:0),MetricPoint(date:origin.addingTimeInterval(5),value:nil,segment:1),MetricPoint(date:origin.addingTimeInterval(25),value:95,segment:2)]
            let runs=MetricWarningBands.runs(broken,kind:.cpuTemperature)
            try require(runs.count==2 && runs.allSatisfy{$0.points.count==1},"Temperature warnings bridged missing samples")
            try require(MetricWarningBands.kind(sensor:MenuSensorReference(key:"PSTR",kind:.power))==nil,"Power was given an invented temperature threshold")
            try require(MetricWarningBands.kind(sensor:MenuSensorReference(key:"TC0P",kind:.temperature)) == .cpuTemperature,"CPU probe warning category lost")
            try require(MetricWarningBands.runs(cpu,kind:.cpuUsage,enabled:false).allSatisfy{$0.level == .normal},"Disabled chart warnings retained alert segments")
            let reference=points([20,12,30,14,22,18,28,20,25,17,15,18,16,15,18,80,76,78,80,93,95,94,95,97])
            let tile=MenuBarTile(metric:.cpu,style:.history,label:"CPU",value:"97%",number:97,points:reference,upper:100,icon:.hidden)
            let end=reference.last!.date
            let filled=MenuBarAppearanceRenderer.image(tiles:[tile],ending:end,spacing:18,graphWidth:100,background:true,appearance:NSAppearance(named:.darkAqua))
            guard let filledData=filled.tiffRepresentation,let filledPixels=NSBitmapImageRep(data:filledData) else{throw ScopeError.message("Reference curve pixels unavailable")}
            let scale=CGFloat(filledPixels.pixelsWide)/filled.size.width
            let column=Int(12*scale)
            let lowerAlpha=filledPixels.colorAt(x:column,y:filledPixels.pixelsHigh-1-Int(3*scale))?.alphaComponent ?? 0
            let upperAlpha=filledPixels.colorAt(x:column,y:Int(3*scale))?.alphaComponent ?? 1
            try require(lowerAlpha>0 && lowerAlpha<0.1 && upperAlpha<0.01,"Curve fill did not fade down or retained a rectangular backdrop")
            if let path=ProcessInfo.processInfo.environment["THERMALSCOPE_CURVE_PREVIEW_DIRECTORY"] {
                let folder=URL(fileURLWithPath:path,isDirectory:true)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                for dark in [true,false] {
                    let appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
                    let curve=MenuBarAppearanceRenderer.image(tiles:[tile],ending:end,spacing:18,graphWidth:100,background:true,appearance:appearance)
                    let preview=NSImage(size:NSSize(width:124,height:34),flipped:false) {rect in
                        (dark ? NSColor(srgbRed:0.15,green:0.46,blue:0.65,alpha:1):NSColor(srgbRed:0.94,green:0.95,blue:0.97,alpha:1)).setFill();rect.fill()
                        curve.draw(in:NSRect(x:12,y:6,width:100,height:22));return true
                    }
                    guard let data=preview.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data),let png=bitmap.representation(using:.png,properties:[:]) else{throw ScopeError.message("Reference preview export failed")}
                    try png.write(to:folder.appendingPathComponent(dark ? "menu-curve-dark.png":"menu-curve-light.png"))
                }
            }
            print("PASS: CPU sustained thresholds, CPU/GPU temperature thresholds, actual-sample/gap preservation, light/dark line/area/bar warning pixels, fading area with transparent backdrop, zero spacing and disabled-warning behavior. No preferences or hardware writes.")
        } catch {print("FAIL: "+error.localizedDescription);exit(1)}
    }
}
