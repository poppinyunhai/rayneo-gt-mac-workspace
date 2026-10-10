import Foundation

enum StartupReadiness {
    @MainActor static func wait(seconds: Double, label: String, stableSeconds: Double = 0,
                                ready: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        var readySince: Double?
        while true {
            try Task.checkCancellation()
            let now = ProcessInfo.processInfo.systemUptime
            if ready() {
                if readySince == nil { readySince = now }
                if now - readySince! >= stableSeconds { return }
            } else { readySince = nil }
            guard now < deadline else {
                throw NSError(domain: "RayNeo.Startup", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "等待\(label)超时"])
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
