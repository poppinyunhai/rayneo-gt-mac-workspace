"""Run actual cleanup/termination methods with controllable capture and startup doubles."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/WorkspaceDelegate.swift').read_text()
cleanup = source[source.index('    @objc func stopDesktops()'):source.index('    func createTestWindows()')].replace('@objc ', '').replace('private func', 'func')
termination = source[source.index('    func applicationShouldTerminate('):source.index('    func applicationWillTerminate(')]
harness = r'''
import Foundation
@MainActor final class Gate {
    var waiter: CheckedContinuation<Void, Never>?
    var opened = false
    func wait() async { if opened { return }; await withCheckedContinuation { waiter = $0 } }
    func open() { opened = true; waiter?.resume(); waiter = nil }
}
@MainActor final class Capture {
    var onFrame: (() -> Void)? = {}
    var onError: (() -> Void)? = {}
    var stopCalls = 0
    let gate: Gate
    init(_ gate: Gate) { self.gate = gate }
    func invalidate() { onFrame=nil;onError=nil }
    func stop() async -> String? { stopCalls += 1; await gate.wait(); return nil }
}
final class Material { var diffuse = Diffuse() }
final class Diffuse { var contents: Int? }
final class Geometry { var firstMaterial: Material? = Material() }
final class Panel { var isHidden = false; var geometry: Geometry? = Geometry() }
final class HUD { var isHidden = true }
final class Window { func close() {} }
final class Tracker { var stops = 0; func stop() { stops += 1 } }
final class TestTimer { func invalidate() {} }
final class FakeView { var isPlaying=true }
final class Benchmark { func stop() {} }
final class Layout {
    var restores=0
    var error:String?
    func restore() -> String? { restores += 1;return error }
}
enum NSColor { static let black = 0 }
@MainActor final class NSApplication {
    enum TerminateReply { case terminateLater }
    var replies = 0
    func reply(toApplicationShouldTerminate: Bool) { replies += 1 }
}
@MainActor final class Harness {
    var stopTask: Task<Void, Never>?
    var startupTask: Task<Void, Never>?
    var terminating = false
    var generation = 0
    var starting = true
    var captures: [Capture] = []
    var desktopStatus = ""
    var testWindows: [Window] = []
    var virtualDisplays = [1,2,3]
    var panels = [Panel()]
    var hud: HUD? = HUD()
    var tracker = Tracker()
    var timer: TestTimer?
    var recovery=RecoveryPolicy()
    var layoutManager=Layout()
    var retainedFrames:[Int?]=[nil,nil,nil]
    var benchmark=Benchmark()
    var view:FakeView?=FakeView()
''' + cleanup + termination + r'''
}
@main struct Tests {
    @MainActor static func settle() async { for _ in 0..<40 { await Task.yield() } }
    @MainActor static func main() async {
        // Stop during startup: retain displays until the in-flight start and capture stop finish.
        let start = Gate(), captureStop = Gate(), h = Harness()
        let capture = Capture(captureStop); h.captures = [capture]
        h.startupTask = Task { await start.wait() }
        await settle()
        h.stopDesktops(); h.stopDesktops()
        await settle()
        precondition(h.generation == 1 && capture.stopCalls == 0)
        precondition(h.virtualDisplays.count == 3 && capture.onFrame == nil && capture.onError == nil)
        start.open(); await settle()
        precondition(capture.stopCalls == 1 && h.layoutManager.restores == 0 && h.virtualDisplays.count == 3)
        captureStop.open(); await h.stopTask?.value
        precondition(h.virtualDisplays.isEmpty && h.captures.isEmpty && h.layoutManager.restores == 1 && h.stopTask == nil)
        // Quit while cleanup is already active: one cleanup, reply only after completion.
        let stop = Gate(), q = Harness(), app = NSApplication()
        q.captures = [Capture(stop)]
        q.stopDesktops()
        _ = q.applicationShouldTerminate(app)
        _ = q.applicationShouldTerminate(app)
        await settle()
        precondition(q.generation == 1 && app.replies == 0 && q.tracker.stops == 0)
        stop.open(); await settle()
        precondition(app.replies == 1 && q.tracker.stops == 1 && q.virtualDisplays.isEmpty)
        // Quit without initialized output/UI is safe.
        let empty = Harness(), emptyApp = NSApplication()
        empty.virtualDisplays = []; empty.panels = []; empty.hud = nil
        _ = empty.applicationShouldTerminate(emptyApp); await settle()
        precondition(emptyApp.replies == 1)
        // A startup operation that ignores cancellation must not hold cleanup indefinitely.
        let stuck=Gate(), timeoutHarness=Harness()
        timeoutHarness.startupTask=Task { await stuck.wait() }
        await settle();timeoutHarness.beginStopping(message:"stopped")
        await timeoutHarness.stopTask?.value
        precondition(timeoutHarness.virtualDisplays.isEmpty && timeoutHarness.desktopStatus.contains("超时"))
        stuck.open()
        let failedLayout=Harness();failedLayout.layoutManager.error="布局恢复失败"
        failedLayout.stopDesktops();await failedLayout.stopTask?.value
        precondition(failedLayout.desktopStatus.contains("布局恢复失败"))
        print("PASS: startup cancellation, duplicate stop, resource ordering, quit during cleanup, uninitialized quit, hung startup timeout, layout errors")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='rayneo-lifecycle-') as temp:
    path = Path(temp) / 'LifecycleTests.swift'
    path.write_text(harness)
    binary = Path(temp) / 'tests'
    subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path','/private/tmp/rayneo-swift-cache',str(root/'Sources/WorkspaceSettings.swift'),str(root/'Sources/AsyncDeadline.swift'),str(path),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=20)
