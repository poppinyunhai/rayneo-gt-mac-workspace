import AppKit

MainActor.assumeIsolated {
    let app=NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate=WorkspaceDelegate()
    if CommandLine.arguments.contains("--render-controls"),let index=CommandLine.arguments.firstIndex(of:"--render-controls"),CommandLine.arguments.count>index+1 {
        delegate.createControls()
        delegate.controlWindow.appearance=NSAppearance(named:.aqua)
        let content=delegate.controlWindow.contentView!
        content.wantsLayer=true
        content.layer?.backgroundColor=NSColor(srgbRed:0.95,green:0.95,blue:0.96,alpha:1).cgColor
        RunLoop.current.run(until:Date().addingTimeInterval(0.2))
        content.layoutSubtreeIfNeeded()
        if let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) {
            content.cacheDisplay(in:content.bounds,to:bitmap)
            if let data=bitmap.representation(using:.png,properties:[:]) {
                try? data.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]))
            }
        }
    } else {
        app.delegate=delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
