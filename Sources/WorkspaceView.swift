import AppKit
import SceneKit
import IOKit.hid
import ScreenCaptureKit
import CoreImage
import CoreMedia
import Carbon

final class WorkspaceView: SCNView {
    var handleKey: ((String) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil); return }
        handleKey?(event.charactersIgnoringModifiers?.lowercased() ?? "")
    }
}

