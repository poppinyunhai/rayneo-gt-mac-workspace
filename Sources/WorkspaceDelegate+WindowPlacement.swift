import AppKit

extension WorkspaceDelegate {
    func moveFocusedWindow(_ index: Int) {
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
}
