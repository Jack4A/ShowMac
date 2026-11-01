import AppKit
let destination=CommandLine.arguments[1]
let iconset=URL(fileURLWithPath:destination,isDirectory:true)
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=size*scale
        let image=NSImage(size:NSSize(width:pixels,height:pixels))
        image.lockFocus()
        let factor=Double(pixels)/1024
        let transform=NSAffineTransform();transform.scale(by:factor);transform.concat()
        NSColor(calibratedRed:0.02,green:0.48,blue:0.45,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:72,y:72,width:880,height:880),xRadius:200,yRadius:200).fill()
        let path=NSBezierPath()
        path.move(to:NSPoint(x:210,y:490));path.line(to:NSPoint(x:370,y:490))
        path.line(to:NSPoint(x:432,y:730));path.line(to:NSPoint(x:510,y:300))
        path.line(to:NSPoint(x:580,y:610));path.line(to:NSPoint(x:640,y:490));path.line(to:NSPoint(x:814,y:490))
        path.lineWidth=48;path.lineCapStyle = .round;path.lineJoinStyle = .round
        NSColor.white.setStroke();path.stroke();image.unlockFocus()
        guard let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]) else { fatalError("icon render failed") }
        let suffix=scale==2 ? "@2x":""
        try png.write(to:iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
