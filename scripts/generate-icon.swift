import AppKit

// Original vector artwork: three workspace panels on a dark rounded tile.
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let sizes = [("icon_16x16",16), ("icon_16x16@2x",32), ("icon_32x32",32),
             ("icon_32x32@2x",64), ("icon_128x128",128), ("icon_128x128@2x",256),
             ("icon_256x256",256), ("icon_256x256@2x",512), ("icon_512x512",512),
             ("icon_512x512@2x",1024)]
let iconset = output + "/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
func polygon(_ points: [NSPoint], color: NSColor) {
    let path = NSBezierPath(); path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.close(); color.setFill(); path.fill()
}
func render(_ size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: CGFloat(size) / 1024)
    (transform as NSAffineTransform).concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 194, yRadius: 194)
    NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.16, blue: 0.25, alpha: 1),
               ending: NSColor(srgbRed: 0.02, green: 0.04, blue: 0.10, alpha: 1))!.draw(in: tile, angle: -90)
    // Side panels taper outward to suggest a curved workspace.
    polygon([NSPoint(x:166,y:350),NSPoint(x:166,y:700),NSPoint(x:342,y:656),NSPoint(x:342,y:394)],
            color: NSColor(srgbRed: 0.15, green: 0.78, blue: 0.76, alpha: 1))
    polygon([NSPoint(x:682,y:394),NSPoint(x:682,y:656),NSPoint(x:858,y:700),NSPoint(x:858,y:350)],
            color: NSColor(srgbRed: 0.38, green: 0.48, blue: 1, alpha: 1))
    let center = NSBezierPath(roundedRect: NSRect(x:366,y:352,width:292,height:348),xRadius:25,yRadius:25)
    NSColor(srgbRed:0.77,green:0.93,blue:1,alpha:1).setFill(); center.fill()
    let inner = NSBezierPath(roundedRect:NSRect(x:388,y:374,width:248,height:304),xRadius:10,yRadius:10)
    NSColor(srgbRed:0.06,green:0.17,blue:0.27,alpha:1).setFill(); inner.fill()
    let code = NSBezierPath()
    code.move(to:NSPoint(x:464,y:578));code.line(to:NSPoint(x:424,y:530));code.line(to:NSPoint(x:464,y:482))
    code.move(to:NSPoint(x:560,y:578));code.line(to:NSPoint(x:600,y:530));code.line(to:NSPoint(x:560,y:482))
    code.move(to:NSPoint(x:533,y:598));code.line(to:NSPoint(x:491,y:462))
    code.lineWidth=16;code.lineCapStyle = .round;code.lineJoinStyle = .round
    NSColor(srgbRed:0.67,green:0.9,blue:1,alpha:1).setStroke();code.stroke()
    let orbit = NSBezierPath()
    orbit.move(to:NSPoint(x:238,y:285))
    orbit.curve(to:NSPoint(x:786,y:285),controlPoint1:NSPoint(x:370,y:193),controlPoint2:NSPoint(x:654,y:193))
    orbit.lineWidth=14;orbit.lineCapStyle = .round
    NSColor(srgbRed:0.36,green:0.71,blue:0.94,alpha:1).setStroke();orbit.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using:.png,properties:[:])!
}
for (name,size) in sizes {
    let data=render(size)
    try data.write(to:URL(fileURLWithPath:iconset + "/" + name + ".png"))
    if size==1024 { try data.write(to:URL(fileURLWithPath:output + "/AppIcon.png")) }
}
