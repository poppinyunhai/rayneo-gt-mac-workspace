import SceneKit

enum SpatialLayout {
    static func apply(panels:[SCNNode],settings:WorkspaceSettings) {
        for (index,node) in panels.enumerated() {
            let angle=Double(index-1)*settings.spacingDegrees * .pi/180
            node.position=SCNVector3(settings.distance*sin(angle),0,-settings.distance*cos(angle))
            node.eulerAngles.y=CGFloat(-angle)
            node.scale=SCNVector3(settings.scale,settings.scale,1)
        }
    }
}
