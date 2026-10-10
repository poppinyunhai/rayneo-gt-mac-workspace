import Foundation

struct OperationTimeout: Error, LocalizedError {
    let label: String
    var errorDescription: String? { "\(label)超时，已执行本地清理" }
}

// Unstructured work is intentional: a task group would wait forever for a system call
// that ignores cancellation. Late completion cannot resume the caller twice.
private final class DeadlineRace<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var tasks: [Task<Void, Never>] = []
    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func store(_ tasks: [Task<Void, Never>]) {
        lock.lock()
        if result != nil { lock.unlock(); tasks.forEach { $0.cancel() } }
        else { self.tasks = tasks; lock.unlock() }
    }
    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation; self.continuation = nil
        let tasks = self.tasks; self.tasks = []
        lock.unlock()
        continuation?.resume(with: result)
        tasks.forEach { $0.cancel() }
    }
}

enum AsyncDeadline {
    @MainActor static func run<Value>(seconds: Double, label: String,
        operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        let race = DeadlineRace<Value>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                if Task.isCancelled { race.resolve(.failure(CancellationError())); return }
                let worker = Task { @MainActor in
                    do { race.resolve(.success(try await operation())) }
                    catch { race.resolve(.failure(error)) }
                }
                let deadline = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }
                    catch { return }
                    race.resolve(.failure(OperationTimeout(label: label)))
                }
                race.store([worker, deadline])
            }
        }, onCancel: { race.resolve(.failure(CancellationError())) })
    }
}
