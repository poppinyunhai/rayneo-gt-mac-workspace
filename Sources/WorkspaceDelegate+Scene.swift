import AppKit
import SceneKit

extension WorkspaceDelegate {
    func addPanel(_ scene: SCNScene, angle: Double, title: String, lines: [String], color: NSColor) {
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
}
