import AppKit
import SceneKit
import IOKit.hid
import ScreenCaptureKit
import CoreImage
import CoreMedia
import Carbon

// Optional window-placement shortcuts only. Mouse input stays entirely native.
final class WindowShortcuts {
    var requestMove: ((Int) -> Void)?
    private var hotkeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    func install() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        guard InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x47544D53, id.id < 4 else { return OSStatus(eventNotHandledErr) }
            Unmanaged<WindowShortcuts>.fromOpaque(context).takeUnretainedValue().requestMove?(Int(id.id))
            return noErr
        }, 1, &type, context, &handler) == noErr else { return }
        for (index, key) in [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_0].enumerated() {
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(UInt32(key), UInt32(cmdKey | optionKey), EventHotKeyID(signature: 0x47544D53, id: UInt32(index)), GetApplicationEventTarget(), 0, &ref) == noErr, let ref { hotkeys.append(ref) }
        }
    }
    deinit {
        hotkeys.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((CGImage) -> Void)?
    var onError: ((String) -> Void)?
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "local.rayneo.capture", qos: .userInteractive)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private(set) var frames = 0
    func start(_ display: SCDisplay) async throws {
        let config = SCStreamConfiguration()
        config.width = 1920; config.height = 1080
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.showsCursor = true
        config.capturesAudio = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
    }
    func stop() async { try? await stream?.stopCapture(); stream = nil }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.onError?(error.localizedDescription) }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid, let pixel = CMSampleBufferGetImageBuffer(sample) else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int, raw != SCFrameStatus.complete.rawValue { return }
        let image = CIImage(cvPixelBuffer: pixel)
        guard let cg = context.createCGImage(image, from: image.extent) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frames += 1; self.onFrame?(cg)
        }
    }
}

final class GTTracker {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    private var device: IOHIDDevice?
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    private var bias = [Double](repeating: 0, count: 3)
    private var sums = [Double](repeating: 0, count: 3)
    private var calibrationCount = 0
    private var previousTime = 0.0
    private var startedAt = 0.0
    private(set) var angles = [Double](repeating: 0, count: 3)
    private(set) var samples = 0
    private(set) var status = "连接中"
    private(set) var calibrated = false

    func start() {
        let match: [String: Any] = [kIOHIDVendorIDKey: 0x3941, kIOHIDProductIDKey: 0xAF50,
                                   kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: 1]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let rc = IOHIDManagerOpen(manager, 0)
        guard rc == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, devices.count == 1,
              let selected = devices.first else {
            status = String(format: "GT HID 不可用 (%08x)", rc); return
        }
        device = selected
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(selected, buffer, 1024, { ctx, result, _, _, _, bytes, length in
            guard let ctx, result == kIOReturnSuccess else { return }
            Unmanaged<GTTracker>.fromOpaque(ctx).takeUnretainedValue().receive(bytes, length)
        }, context)
        IOHIDDeviceScheduleWithRunLoop(selected, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        startedAt = ProcessInfo.processInfo.systemUptime
        let result = setStreaming(true)
        status = result == kIOReturnSuccess ? "请保持眼镜静止 2 秒，估计零偏" : "IMU 开启失败"
    }
    // Strict whitelist: runtime IMU ON/OFF only.
    private func setStreaming(_ enabled: Bool) -> IOReturn {
        guard let device else { return kIOReturnNoDevice }
        var packet = [UInt8](repeating: 0, count: 64)
        packet[0] = 0x66; packet[1] = enabled ? 1 : 2
        return packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, 64) }
    }
    private func receive(_ pointer: UnsafeMutablePointer<UInt8>, _ length: Int) {
        var bytes = Array(UnsafeBufferPointer(start: pointer, count: length))
        if bytes.count == 65 && bytes[0] == 0 { bytes.removeFirst() }
        guard bytes.count == 64, bytes[0] == 0x99, bytes[1] == 0x65 else { return }
        let gyro: [Double] = (0..<3).map { axis in
            let i = 16 + axis * 4
            let value = UInt32(bytes[i]) | UInt32(bytes[i+1]) << 8 | UInt32(bytes[i+2]) << 16 | UInt32(bytes[i+3]) << 24
            return Double(Float(bitPattern: value))
        }
        guard gyro.allSatisfy({ $0.isFinite && abs($0) < 4000 }) else { return }
        samples += 1
        let now = ProcessInfo.processInfo.systemUptime
        let dt = previousTime > 0 ? min(max(now - previousTime, 0), 0.02) : 0
        previousTime = now
        if !calibrated {
            // Restart the calibration window when the headset is clearly moving.
            if gyro.contains(where: { abs($0) > 3 }) {
                startedAt = now; calibrationCount = 0; sums = [0, 0, 0]
                status = "请保持眼镜静止 2 秒，估计零偏"
                return
            }
            calibrationCount += 1
            for i in 0..<3 { sums[i] += gyro[i] }
            if now - startedAt >= 2 && calibrationCount >= 200 {
                bias = sums.map { $0 / Double(calibrationCount) }
                calibrated = true; status = "GT 已连接 · 软件姿态追踪"
            }
            return
        }
        for i in 0..<3 {
            let speed = gyro[i] - bias[i]
            if abs(speed) > 0.15 { angles[i] += speed * dt * .pi / 180 }
        }
    }
    func recenter() { angles = [0, 0, 0] }
    func recalibrate() {
        calibrated = false; calibrationCount = 0; sums = [0, 0, 0]
        startedAt = ProcessInfo.processInfo.systemUptime; recenter()
    }
    func stop() {
        if let device {
            _ = setStreaming(false)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        device = nil
        IOHIDManagerClose(manager, 0)
    }
    deinit { buffer.deallocate() }
}

final class DemoView: SCNView {
    var handleKey: ((String) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil); return }
        handleKey?(event.charactersIgnoringModifiers?.lowercased() ?? "")
    }
}

final class DemoDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var view: DemoView!
    private var hud: NSTextField!
    private let tracker = GTTracker()
    private let camera = SCNNode()
    private var timer: Timer?
    private var yawAxis = 1
    private var direction = 1.0
    private var paused = false
    private var controlWindow: NSWindow!
    private var controlStatus: NSTextField!
    private var statusItem: NSStatusItem!
    private var panels: [SCNNode] = []
    private var virtualDisplays: [CGVirtualDisplay] = []
    private var captures: [DesktopCapture] = []
    private var generation = 0
    private var desktopStatus = "尚未启动独立虚拟屏"
    private var starting = false
    private var testWindows: [NSWindow] = []
    private var lastTelemetry = 0.0
    private var panelScale: Float = 1.0
    private let shortcuts = WindowShortcuts()
    private var originalGTOrigin: CGPoint?
    private var outputDisplayID: CGDirectDisplayID = 0
    private var lastExternalPID: pid_t?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.localizedName.lowercased().contains("smartglasses") }) else {
            let alert = NSAlert()
            alert.messageText = "未找到 SmartGlasses 显示器"
            alert.informativeText = "请将 GT 直连 Mac，并断开占用原生外屏输出的显示器。"
            alert.runModal(); NSApp.terminate(nil); return
        }
        outputDisplayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        NotificationCenter.default.addObserver(self, selector: #selector(updateOutputScreen), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.setFrame(screen.frame, display: true)
        // Cover the physical GT menu bar without hiding the Mac's own menu bar.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.ignoresMouseEvents = true
        window.title = "RayNeo Workspace — 三屏姿态原型"
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.contentView = container
        view = DemoView(frame: container.bounds)
        view.autoresizingMask = [.width, .height]
        view.backgroundColor = NSColor(calibratedRed: 0.012, green: 0.018, blue: 0.028, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        container.addSubview(view)
        let scene = SCNScene()
        view.scene = scene
        camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .horizontal
        camera.camera?.fieldOfView = 46
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 50
        scene.rootNode.addChildNode(camera)
        view.pointOfView = camera
        addPanel(scene, angle: -48, title: "DOCS / 文档", lines: ["项目文档", "运行手册 · 网络拓扑", "参考资料与待办", "", "左侧空间面板"], color: .systemTeal)
        addPanel(scene, angle: 0, title: "CODE / 主工作区", lines: ["RayNeo Workspace", "M2 Air + GT · USB-C 直连", "", "这一版验证头部追踪与空间排布", "真实应用窗口尚未接入"], color: .systemBlue)
        addPanel(scene, angle: 48, title: "OPS / 终端与监控", lines: ["$ ssh server", "服务状态 · 日志 · 指标", "", "右侧空间面板", "下一步：捕获真实工作窗口"], color: .systemOrange)
        panels.forEach { $0.isHidden = true }
        hud = NSTextField(labelWithString: "初始化")
        hud.frame = NSRect(x: 24, y: 18, width: container.bounds.width - 48, height: 54)
        hud.autoresizingMask = [.width]
        hud.textColor = .white
        hud.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        hud.maximumNumberOfLines = 3
        container.addSubview(hud)
        shortcuts.requestMove = { [weak self] index in self?.moveFocusedWindow(index) }
        shortcuts.install()
        view.handleKey = { [weak self] key in
            guard let self else { return }
            switch key {
            case "r": self.tracker.recenter()
            case "c": self.tracker.recalibrate()
            case " ": self.paused.toggle()
            case "f": self.direction *= -1
            case "x": self.yawAxis = 0; self.tracker.recenter()
            case "y": self.yawAxis = 1; self.tracker.recenter()
            case "z": self.yawAxis = 2; self.tracker.recenter()
            case "+", "=": self.changeScale(1)
            case "-": self.changeScale(-1)
            case "h": self.hud.isHidden.toggle()
            default: break
            }
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        createControls()
        NSApp.activate(ignoringOtherApps: true)
        tracker.start()
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func addPanel(_ scene: SCNScene, angle: Double, title: String, lines: [String], color: NSColor) {
        let texture = NSImage(size: NSSize(width: 1600, height: 900))
        texture.lockFocus()
        NSColor(calibratedRed: 0.035, green: 0.05, blue: 0.08, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1600, height: 900).fill()
        color.setFill(); NSRect(x: 0, y: 880, width: 1600, height: 20).fill()
        let titleStyle: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 68, weight: .bold), .foregroundColor: color]
        (title as NSString).draw(at: NSPoint(x: 80, y: 720), withAttributes: titleStyle)
        let bodyStyle: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 44, weight: .regular), .foregroundColor: NSColor.white]
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 80, y: 580 - index * 80), withAttributes: bodyStyle)
        }
        texture.unlockFocus()
        // At distance 3, 2*tan(46/2)*3 ~= 2.547 fills the horizontal view.
        // Leave 2% margin to keep the desktop edges visible.
        let panelWidth = 2.50
        let plane = SCNPlane(width: panelWidth, height: panelWidth * 9 / 16)
        plane.firstMaterial?.diffuse.contents = texture
        plane.firstMaterial?.lightingModel = .constant
        plane.firstMaterial?.isDoubleSided = true
        let node = SCNNode(geometry: plane)
        let radians = angle * .pi / 180
        node.position = SCNVector3(3 * sin(radians), 0, -3 * cos(radians))
        node.eulerAngles.y = CGFloat(-radians)
        scene.rootNode.addChildNode(node)
        panels.append(node)
    }
    private func createControls() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 RayNeo Workspace", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem(); item.submenu = appMenu; menu.addItem(item)
        NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "GT 三屏"
        let statusMenu = NSMenu()
        let show = NSMenuItem(title: "显示控制面板", action: #selector(showControls), keyEquivalent: "")
        show.target = self; statusMenu.addItem(show)
        let stop = NSMenuItem(title: "停止三屏", action: #selector(stopDesktops), keyEquivalent: "")
        stop.target = self; statusMenu.addItem(stop)
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = statusMenu
        controlWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
                                 styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        controlWindow.isReleasedWhenClosed = false
        controlWindow.title = "RayNeo Workspace · 独立桌面"
        let content = controlWindow.contentView!
        let title = NSTextField(labelWithString: "把三个独立 Mac 桌面放进 GT")
        title.font = .systemFont(ofSize: 23, weight: .bold)
        title.frame = NSRect(x: 24, y: 360, width: 630, height: 35); content.addSubview(title)
        let help = NSTextField(wrappingLabelWithString: "眼镜使用跟随模式。启动后，系统会出现 RayNeo Left / Center / Right 三个扩展屏，可把应用窗口拖过去。屏幕捕获只在本机显示，不保存视频、不上传。")
        help.stringValue = "鼠标无需切换模式：从 Mac 右边缘依次进入左 / 中 / 右屏，正常点击、拖拽和输入。下方移动窗口按钮与 ⌘⌥1 / 2 / 3 / 0 都是可选功能。眼镜保持跟随模式。"
        help.frame = NSRect(x: 24, y: 275, width: 630, height: 68); content.addSubview(help)
        for (index, name) in ["移到左屏 ⌘⌥1", "移到中屏 ⌘⌥2", "移到右屏 ⌘⌥3", "移回 Mac ⌘⌥0"].enumerated() {
            let button = NSButton(title: name, target: self, action: #selector(moveWindowButton(_:)))
            button.tag = index; button.frame = NSRect(x: 24 + index * 160, y: 225, width: 150, height: 34)
            content.addSubview(button)
        }
        controlStatus = NSTextField(wrappingLabelWithString: desktopStatus)
        controlStatus.frame = NSRect(x: 24, y: 78, width: 630, height: 85); content.addSubview(controlStatus)
        let specifications: [(String, Selector, CGFloat, CGFloat)] = [
            ("启动三屏", #selector(startDesktops), 24, 110),
            ("回中", #selector(recenter), 145, 85),
            ("停止三屏", #selector(stopDesktops), 240, 110),
            ("退出", #selector(quit), 360, 85)]
        for (title, action, x, width) in specifications {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.frame = NSRect(x: x, y: 24, width: width, height: 34); content.addSubview(button)
        }
        let smaller = NSButton(title: "屏幕缩小", target: self, action: #selector(smallerPanel))
        smaller.frame = NSRect(x: 24, y: 172, width: 105, height: 32); content.addSubview(smaller)
        let larger = NSButton(title: "屏幕放大", target: self, action: #selector(largerPanel))
        larger.frame = NSRect(x: 145, y: 172, width: 105, height: 32); content.addSubview(larger)
        let toggleHUD = NSButton(title: "显示/隐藏状态文字", target: self, action: #selector(toggleStatus))
        toggleHUD.frame = NSRect(x: 270, y: 172, width: 180, height: 32); content.addSubview(toggleHUD)
        if let builtIn = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false }) {
            controlWindow.setFrameOrigin(NSPoint(x: builtIn.visibleFrame.midX - 340, y: builtIn.visibleFrame.midY - 165))
        } else { controlWindow.center() }
        showControls()
    }
    @objc private func showControls() { controlWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func recenter() { tracker.recenter() }
    @objc private func smallerPanel() { changeScale(-1) }
    @objc private func largerPanel() { changeScale(1) }
    @objc private func toggleStatus() { hud.isHidden.toggle() }
    private func changeScale(_ direction: Float) {
        panelScale = min(max(panelScale + direction * 0.05, 0.65), 1.25)
        panels.forEach { $0.scale = SCNVector3(panelScale, panelScale, 1) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func moveWindowButton(_ sender: NSButton) { moveFocusedWindow(sender.tag) }
    private func moveFocusedWindow(_ index: Int) {
        guard AXIsProcessTrusted() else {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            desktopStatus = "移动窗口需要辅助功能权限：请允许 RayNeo Workspace 后重试"; return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let pid = (frontPID != ownPID ? frontPID : lastExternalPID) else {
            desktopStatus = "请先选中要移动的应用窗口，再按 ⌘⌥1 / 2 / 3"; return
        }
        let displayID: CGDirectDisplayID
        if index == 3 {
            guard let screen = NSScreen.screens.first(where: { screen in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                return CGDisplayIsBuiltin(id.uint32Value) != 0
            }), let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
            displayID = id.uint32Value
        } else {
            guard virtualDisplays.indices.contains(index) else { desktopStatus = "请先启动三屏"; return }
            displayID = virtualDisplays[index].displayID
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            desktopStatus = "该应用没有可移动的普通窗口；请先选中窗口"; return
        }
        let focused = unsafeBitCast(value, to: AXUIElement.self)
        var fullScreen: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, "AXFullScreen" as CFString, &fullScreen) == .success,
           (fullScreen as? Bool) == true {
            desktopStatus = "请先退出应用全屏，再移动窗口"; return
        }
        let bounds = CGDisplayBounds(displayID)
        var size = CGSize(width: min(1280, bounds.width - 80), height: min(850, bounds.height - 100))
        var existingSize: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXSizeAttribute as CFString, &existingSize) == .success,
           let existingSize, CFGetTypeID(existingSize) == AXValueGetTypeID() {
            var original = CGSize.zero
            if AXValueGetValue(unsafeBitCast(existingSize, to: AXValue.self), .cgSize, &original) {
                size.width = min(original.width, bounds.width - 80)
                size.height = min(original.height, bounds.height - 100)
            }
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) { _ = AXUIElementSetAttributeValue(focused, kAXSizeAttribute as CFString, sizeValue) }
        var position = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        guard let positionValue = AXValueCreate(.cgPoint, &position) else { return }
        let result = AXUIElementSetAttributeValue(focused, kAXPositionAttribute as CFString, positionValue)
        desktopStatus = result == .success ? "已移动窗口到 \(["左屏", "中屏", "右屏", "Mac"][index])" : "窗口移动失败 (\(result.rawValue))；该应用可能限制窗口位置"
    }
    @objc private func updateOutputScreen() {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == outputDisplayID
        }), let window else { return }
        window.setFrame(screen.frame, display: true)
    }
    @objc private func startDesktops() {
        guard !starting, virtualDisplays.isEmpty else { return }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            desktopStatus = "请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 RayNeo Workspace。若系统要求，请退出并重新打开，再点击启动三屏。"
            controlStatus.stringValue = desktopStatus
            return
        }
        guard NSClassFromString("CGVirtualDisplay") != nil else {
            desktopStatus = "当前系统没有可用的虚拟显示器接口"; return
        }
        starting = true; generation += 1
        let ticket = generation
        desktopStatus = "正在创建三个独立桌面…"
        Task { @MainActor [self] in
            do {
                for (i, name) in ["RayNeo Left", "RayNeo Center", "RayNeo Right"].enumerated() {
                    let descriptor = CGVirtualDisplayDescriptor()
                    descriptor.name = name; descriptor.maxPixelsWide = 1920; descriptor.maxPixelsHigh = 1080
                    descriptor.sizeInMillimeters = CGSize(width: 530, height: 298)
                    descriptor.vendorID = 0xC0D3; descriptor.productID = 0x4754; descriptor.serialNum = UInt32(1001+i)
                    descriptor.setDispatchQueue(.main)
                    guard let display = CGVirtualDisplay(descriptor: descriptor) else { throw NSError(domain: "RayNeo", code: 1, userInfo: [NSLocalizedDescriptionKey: "创建 \(name) 失败"]) }
                    let settings = CGVirtualDisplaySettings(); settings.hiDPI = 0
                    settings.modes = [CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60)]
                    guard display.apply(settings) else { throw NSError(domain: "RayNeo", code: 2, userInfo: [NSLocalizedDescriptionKey: "虚拟屏模式设置失败"]) }
                    virtualDisplays.append(display)
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard generation == ticket else { return }
                // WindowServer needs a run-loop turn to register the new displays.
                try arrangeDesktops()
                try await Task.sleep(nanoseconds: 600_000_000)
                guard generation == ticket else { return }
                createTestWindows()
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                for (index, virtual) in virtualDisplays.enumerated() {
                    guard generation == ticket else { return }
                    guard let display = content.displays.first(where: { $0.displayID == virtual.displayID }) else {
                        throw NSError(domain: "RayNeo", code: 3, userInfo: [NSLocalizedDescriptionKey: "屏幕捕获未识别到虚拟屏"])
                    }
                    let capture = DesktopCapture()
                    capture.onFrame = { [weak self] image in
                        guard let self, self.generation == ticket else { return }
                        self.panels[index].geometry?.firstMaterial?.diffuse.contents = image
                    }
                    capture.onError = { [weak self] error in self?.desktopStatus = "捕获停止：\(error)" }
                    captures.append(capture)
                    try await capture.start(display)
                }
                desktopStatus = "三屏已启动，使用原生鼠标。Mac → 左屏 → 中屏 → 右屏，可直接跨屏拖动窗口。"
                panels.forEach { $0.isHidden = false }
                hud.isHidden = true
                starting = false
            } catch {
                guard generation == ticket else { return }
                let message = error.localizedDescription
                stopDesktops()
                desktopStatus = "启动失败：\(message)"
            }
        }
    }
    private func arrangeDesktops() throws {
        var online = [CGDirectDisplayID](repeating: 0, count: 32), count: UInt32 = 0
        _ = CGGetOnlineDisplayList(32, &online, &count)
        let ours = Set(virtualDisplays.map { $0.displayID })
        let physical = online.prefix(Int(count)).filter { !ours.contains($0) && $0 != outputDisplayID }
        let rightEdge = physical.map { CGDisplayBounds($0).maxX }.max() ?? 0
        if originalGTOrigin == nil { originalGTOrigin = CGDisplayBounds(outputDisplayID).origin }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            throw NSError(domain: "RayNeo", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法配置虚拟屏布局"])
        }
        // Keep the compositor output after the three working desktops, never between them and the Mac.
        guard CGConfigureDisplayOrigin(config, outputDisplayID, Int32(rightEdge) + 3 * 1920, 0) == .success else {
            CGCancelDisplayConfiguration(config)
            throw NSError(domain: "RayNeo", code: 7, userInfo: [NSLocalizedDescriptionKey: "GT 输出屏位置配置失败"])
        }
        for (i, display) in virtualDisplays.enumerated() {
            if CGDisplayMirrorsDisplay(display.displayID) != kCGNullDirectDisplay {
                let mirror = CGConfigureDisplayMirrorOfDisplay(config, display.displayID, kCGNullDirectDisplay)
                guard mirror == .success else {
                    CGCancelDisplayConfiguration(config)
                    throw NSError(domain: "RayNeo", code: 5, userInfo: [NSLocalizedDescriptionKey: "取消虚拟屏镜像失败 (\(mirror.rawValue))"])
                }
            }
            let origin = CGConfigureDisplayOrigin(config, display.displayID, Int32(rightEdge) + Int32(i * 1920), 0)
            guard origin == .success else {
                CGCancelDisplayConfiguration(config)
                throw NSError(domain: "RayNeo", code: 5, userInfo: [NSLocalizedDescriptionKey: "虚拟屏 \(i+1) 位置设置失败 (\(origin.rawValue))"])
            }
        }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            throw NSError(domain: "RayNeo", code: 6, userInfo: [NSLocalizedDescriptionKey: "虚拟屏布局提交失败"])
        }
    }
    private func restoreOutputOrigin() {
        guard let origin = originalGTOrigin else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        guard CGConfigureDisplayOrigin(config, outputDisplayID, Int32(origin.x), Int32(origin.y)) == .success else {
            CGCancelDisplayConfiguration(config); return
        }
        if CGCompleteDisplayConfiguration(config, .forSession) == .success { originalGTOrigin = nil }
    }
    @objc private func stopDesktops() {
        restoreOutputOrigin()
        generation += 1; starting = false
        let old = captures; captures = []
        old.forEach { $0.onFrame = nil; $0.onError = nil }
        Task { for capture in old { await capture.stop() } }
        testWindows.forEach { $0.close() }; testWindows.removeAll()
        virtualDisplays.removeAll()
        panels.forEach { $0.isHidden = true }
        hud?.isHidden = false
        desktopStatus = "三个虚拟屏已移除；可以重新启动"
    }
    private func createTestWindows() {
        for (index, display) in virtualDisplays.enumerated() {
            guard let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
            }) else { continue }
            let name = ["Left / 文档", "Center / 代码", "Right / 终端"][index]
            let test = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false, screen: screen)
            test.isReleasedWhenClosed = false
            test.title = "RayNeo \(name) · 独立桌面测试"
            test.setFrameOrigin(NSPoint(x: screen.frame.midX - 600, y: screen.frame.midY - 380))
            let scroll = NSScrollView(frame: test.contentView!.bounds)
            scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
            let editor = NSTextView(frame: scroll.bounds)
            editor.isEditable = true; editor.isRichText = false
            editor.font = .monospacedSystemFont(ofSize: 28, weight: .regular)
            editor.textContainerInset = NSSize(width: 24, height: 24)
            editor.autoresizingMask = [.width, .height]
            editor.string = "RayNeo \(name)\n\n这是独立 macOS 虚拟显示器上的真实窗口。\n\n你可以点击并编辑这里的文字，验证实时捕获。\n也可以将浏览器、编辑器或终端拖到这个桌面。\n\n本窗口只是测试内容，可以关闭。\n\nGT 保持跟随模式；在 Mac 控制面板里回中或停止三屏。"
            scroll.documentView = editor; test.contentView?.addSubview(scroll)
            test.orderFront(nil); testWindows.append(test)
        }
    }
    private func update() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier { lastExternalPID = front.processIdentifier }
        if !paused {
            // GT's yaw axis and sign are intentionally user-selectable until movement is verified.
            camera.eulerAngles.y = CGFloat(direction * tracker.angles[yawAxis])
        }
        let axis = ["X", "Y", "Z"][yawAxis]
        hud.stringValue = "\(tracker.status) · 样本 \(tracker.samples) · Yaw \(axis)\(direction > 0 ? "+" : "−")\(paused ? " · 已暂停" : "")\n\(desktopStatus)"
        controlStatus?.stringValue = desktopStatus + "\n捕获帧数：" + captures.map { String($0.frames) }.joined(separator: " / ")
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastTelemetry >= 1 {
            lastTelemetry = now
            let status: [String: Any] = ["status": desktopStatus, "imuSamples": tracker.samples,
                                       "virtualIDs": virtualDisplays.map { $0.displayID },
                                       "captureFrames": captures.map { $0.frames }, "inputMode": "native", "displayBounds": virtualDisplays.map { NSStringFromRect(CGDisplayBounds($0.displayID)) }]
            if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
                let path = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("runtime-status.json")
                try? data.write(to: path, options: .atomic)
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); stopDesktops(); tracker.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = DemoDelegate()
app.delegate = delegate
app.run()
