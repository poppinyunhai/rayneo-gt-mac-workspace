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

