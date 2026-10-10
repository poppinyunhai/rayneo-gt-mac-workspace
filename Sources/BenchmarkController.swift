import AppKit

private final class BenchmarkView:NSView {
    var tick=0
    override var isFlipped:Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        NSColor(calibratedRed:0.03,green:0.05,blue:0.09,alpha:1).setFill();bounds.fill()
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedSystemFont(ofSize:22,weight:.medium),.foregroundColor:NSColor.white]
        for line in 0..<22 {
            let text=String(format:"%04d  func render(frame: %06d) → Workspace  // RayNeo",line+tick/3,tick)
            (text as NSString).draw(at:NSPoint(x:24,y:CGFloat(line*30)-CGFloat(tick%30)),withAttributes:attributes)
        }
        NSColor.systemTeal.setFill()
        NSBezierPath(roundedRect:NSRect(x:CGFloat((tick*6)%max(1,Int(bounds.width)-80)),y:bounds.height-60,width:70,height:30),xRadius:8,yRadius:8).fill()
    }
}

final class BenchmarkController {
    private var windows:[NSWindow]=[]
    private var timer:Timer?
    var running:Bool { timer != nil }
    func start(displayIDs:[CGDirectDisplayID]) {
        stop()
        for id in displayIDs {
            guard let screen=NSScreen.screens.first(where:{ ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value==id }) else { continue }
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:700),styleMask:[.titled,.closable],backing:.buffered,defer:false,screen:screen)
            window.isReleasedWhenClosed=false;window.title="RayNeo · 可重复动态负载（非端到端延迟测量）"
            window.contentView=BenchmarkView(frame:NSRect(x:0,y:0,width:1000,height:700))
            window.setFrameOrigin(NSPoint(x:screen.frame.midX-500,y:screen.frame.midY-350));window.orderFront(nil);windows.append(window)
        }
        timer=Timer(timeInterval:1.0/60,repeats:true) { [weak self] _ in
            self?.windows.forEach { window in
                if let view=window.contentView as? BenchmarkView { view.tick += 1;view.needsDisplay=true }
            }
        }
        RunLoop.main.add(timer!,forMode:.common)
    }
    func stop() { timer?.invalidate();timer=nil;windows.forEach { $0.close() };windows=[] }
}
