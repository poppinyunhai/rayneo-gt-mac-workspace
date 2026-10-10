import Foundation

// A single pending delivery retains only the newest frame, independent of UI speed.
final class LatestFrameMailbox<Value> {
    private let lock = NSLock()
    private var value: Value?
    private var scheduled = false
    private var enabled = true
    private var overwritten = 0
    func offer(_ value: Value) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return false }
        if self.value != nil { overwritten += 1 }
        self.value = value
        guard !scheduled else { return false }
        scheduled = true; return true
    }
    func take() -> Value? {
        lock.lock(); defer { lock.unlock() }
        let result = value; value = nil; scheduled = false
        return enabled ? result : nil
    }
    func disable() { lock.lock(); enabled = false; value = nil; lock.unlock() }
    var dropped: Int { lock.lock(); defer { lock.unlock() }; return overwritten }
}
