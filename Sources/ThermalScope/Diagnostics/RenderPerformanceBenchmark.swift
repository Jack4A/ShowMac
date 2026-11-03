import AppKit
import Foundation
import ThermalCore

enum RenderPerformanceBenchmark {
    @MainActor static func run() {
        _=NSApplication.shared
        var history=MetricHistory()
        for i in 0..<900 {history.append(i%80<20 ? 95:Double(i%65),at:Date(timeIntervalSince1970:1000+Double(i*2)))}
        let end=history.points.last!.date
        let tiles=[MenuBarTile(metric:.cpu,style:.historyValue,label:"CPU",value:"35%",number:35,points:history.points,upper:100,color:.systemBlue),MenuBarTile(metric:.temperature,style:.stacked,label:"TEMP",value:"65°",number:65,points:[],upper:130,color:.systemOrange)]
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1200,pixelsHigh:44,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap) else{exit(2)}
        var drawing:[Double]=[],historyCost:[Double]=[]
        for i in 0..<220 {
            let start=ProcessInfo.processInfo.systemUptime
            let image=MenuBarAppearanceRenderer.image(tiles:tiles,ending:end,spacing:4,graphWidth:88,background:true,appearance:NSAppearance(named:.darkAqua))
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
            image.draw(in:NSRect(x:0,y:0,width:image.size.width*2,height:44))
            context.flushGraphics();NSGraphicsContext.restoreGraphicsState()
            let elapsed=(ProcessInfo.processInfo.systemUptime-start)*1000
            let classificationStart=ProcessInfo.processInfo.systemUptime
            _=CPULoadBands.runs(history.points,budget:240)
            if i>=20 {drawing.append(elapsed);historyCost.append((ProcessInfo.processInfo.systemUptime-classificationStart)*1000)}
        }
        func stats(_ v:[Double])->[String:Double] {let v=v.sorted();return ["p50_ms":v[v.count/2],"p95_ms":v[Int(ceil(Double(v.count)*0.95))-1],"max_ms":v.last!]}
        let result:[String:Any]=["schema":1,"iterations":drawing.count,"warmup_iterations":20,"menu_image_cpu_render":stats(drawing),"cpu_history_classification_900_samples":stats(historyCost),"fixture_data":true,"scope":"CPU-side native image generation and bitmap draw; excludes WindowServer/compositor/GPU and is not FPS","actual_fps":NSNull(),"animation_hitches":NSNull()]
        if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]){FileHandle.standardOutput.write(data);print()}
    }
}
