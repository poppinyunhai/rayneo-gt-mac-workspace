import Foundation

struct WorkspaceSettings: Codable, Equatable {
    var scale = 1.0
    var distance = 3.0
    var spacingDegrees = 48.0
    var yawAxis = 1
    var direction = 1.0
    var captureFPS = 30
    var renderFPS = 60
    var useGPUTextures = true
    var adaptiveBias = true
    var automaticRecovery = true
    var showTestWindows = true

    func validated() -> Self {
        var value = self
        value.scale = scale.isFinite ? min(max(scale, 0.65), 1.25) : 1
        value.distance = distance.isFinite ? min(max(distance, 2.0), 5.0) : 3
        value.spacingDegrees = spacingDegrees.isFinite ? min(max(spacingDegrees, 35), 65) : 48
        value.yawAxis = (0...2).contains(yawAxis) ? yawAxis : 1
        value.direction = direction < 0 ? -1 : 1
        value.captureFPS = [15,30,60].contains(captureFPS) ? captureFPS : 30
        value.renderFPS = [30,60].contains(renderFPS) ? renderFPS : 60
        return value
    }
}

final class SettingsStore {
    let url: URL
    init(url: URL) { self.url = url }
    func load() -> WorkspaceSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(WorkspaceSettings.self, from: data) else { return WorkspaceSettings() }
        return settings.validated()
    }
    func save(_ settings: WorkspaceSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings.validated()).write(to: url, options: .atomic)
    }
}

struct RecoveryPolicy {
    var wantsSession = false
    var sleeping = false
    var attempts = 0
    var retryAt = 0.0
    var failed = false
    var automaticallyRecover = true
    mutating func requestStart() { wantsSession = true; attempts = 0; retryAt = 0; failed = false }
    mutating func requestStop() { wantsSession = false; attempts = 0; retryAt = 0; failed = false }
    mutating func interrupted() { attempts = 0; retryAt = 0; failed = false }
    mutating func succeeded() { attempts = 0; retryAt = 0; failed = false }
    mutating func startFailed(now: Double) {
        attempts += 1; retryAt = now + Double(attempts * 2)
        failed = attempts >= 3
    }
    func shouldResume(now: Double, ready: Bool, idle: Bool) -> Bool {
        automaticallyRecover && wantsSession && !sleeping && !failed && ready && idle && now >= retryAt
    }
}
