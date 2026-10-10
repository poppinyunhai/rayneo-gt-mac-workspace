import AppKit
import CoreGraphics

private struct OutputOrigin: Codable {
    let uuid: String
    let x: Double
    let y: Double
}

final class DisplayLayoutManager {
    private let snapshotURL: URL
    private var original: OutputOrigin?
    var hasPendingRestore: Bool { original != nil }
    init(snapshotURL: URL) {
        self.snapshotURL=snapshotURL
        if let data=try? Data(contentsOf:snapshotURL) { original=try? JSONDecoder().decode(OutputOrigin.self,from:data) }
    }
    static func uuid(_ id:CGDirectDisplayID) -> String? {
        guard let uuid=CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(kCFAllocatorDefault,uuid) as String
    }
    func arrange(virtualIDs:[CGDirectDisplayID],output:CGDirectDisplayID) throws {
        var online=[CGDirectDisplayID](repeating:0,count:32),count:UInt32=0
        guard CGGetOnlineDisplayList(32,&online,&count) == .success,
              online.prefix(Int(count)).contains(output) else { throw failure("GT 输出屏已断开") }
        let ours=Set(virtualIDs)
        let physical=online.prefix(Int(count)).filter { !ours.contains($0) && $0 != output }
        let rightEdge=physical.map { CGDisplayBounds($0).maxX }.max() ?? 0
        if original == nil {
            guard let uuid=Self.uuid(output) else { throw failure("无法识别 GT 显示器") }
            let origin=CGDisplayBounds(output).origin
            let snapshot=OutputOrigin(uuid:uuid,x:origin.x,y:origin.y)
            try FileManager.default.createDirectory(at:snapshotURL.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(snapshot).write(to:snapshotURL,options:.atomic)
            original=snapshot
        } else if original?.uuid != Self.uuid(output) {
            throw failure("旧输出屏布局尚未恢复；请先连接原设备并恢复布局")
        }
        var config:CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success,let config else { throw failure("无法开始显示器布局配置") }
        var committed=false
        defer { if !committed { CGCancelDisplayConfiguration(config) } }
        guard CGConfigureDisplayOrigin(config,output,Int32(rightEdge)+Int32(virtualIDs.count*1920),0) == .success else { throw failure("GT 输出屏位置配置失败") }
        for (i,id) in virtualIDs.enumerated() {
            if CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay {
                let result = CGConfigureDisplayMirrorOfDisplay(config,id,kCGNullDirectDisplay)
                guard result == .success else { throw failure("取消虚拟屏镜像失败 (\(result.rawValue))") }
            }
            guard CGConfigureDisplayOrigin(config,id,Int32(rightEdge)+Int32(i*1920),0) == .success else { throw failure("虚拟屏位置配置失败") }
        }
        let result=CGCompleteDisplayConfiguration(config,.forSession)
        committed=true // Complete consumes the configuration, including on failure.
        guard result == .success else { throw failure("布局提交失败 (\(result.rawValue))") }
    }
    @discardableResult func restore() -> String? {
        guard let original else { return nil }
        guard let screen=NSScreen.screens.first(where:{ screen in
            guard let number=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return Self.uuid(number.uint32Value) == original.uuid
        }),let number=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return "GT 未连接，布局恢复记录已保留，重连后重试"
        }
        var config:CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success,let config else { return "无法开始恢复 GT 布局，请点击恢复布局重试" }
        guard CGConfigureDisplayOrigin(config,number.uint32Value,Int32(original.x),Int32(original.y)) == .success else {
            CGCancelDisplayConfiguration(config);return "GT 布局恢复失败，请点击恢复布局重试"
        }
        let result=CGCompleteDisplayConfiguration(config,.forSession)
        guard result == .success else { return "GT 布局恢复提交失败 (\(result.rawValue))" }
        do { if FileManager.default.fileExists(atPath:snapshotURL.path) { try FileManager.default.removeItem(at:snapshotURL) } }
        catch { return "布局已恢复，但恢复记录清理失败：\(error.localizedDescription)" }
        self.original=nil;return nil
    }
    private func failure(_ message:String) -> NSError { NSError(domain:"RayNeo.Layout",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
}
