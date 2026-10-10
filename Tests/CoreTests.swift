import Foundation

@MainActor final class TestGate {
    var continuation: CheckedContinuation<Void,Never>?
    var open = false
    func wait() async { if open { return };await withCheckedContinuation { continuation=$0 } }
    func release() { open=true;continuation?.resume();continuation=nil }
}
@main struct CoreTests {
    @MainActor static func main() async throws {
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:temp) }
        let store=SettingsStore(url:temp.appendingPathComponent("settings.json"))
        var settings=WorkspaceSettings();settings.scale=100;settings.distance=Double.nan;settings.spacingDegrees=2;settings.yawAxis=9;settings.direction=0;settings.captureFPS=70
        try store.save(settings)
        let restored=store.load()
        precondition(restored.scale==1.25 && restored.distance==3 && restored.spacingDegrees==35 && restored.yawAxis==1 && restored.captureFPS==30)
        try Data("broken json".utf8).write(to:store.url)
        precondition(store.load()==WorkspaceSettings())
        var recovery=RecoveryPolicy();recovery.requestStart()
        precondition(recovery.shouldResume(now:0,ready:true,idle:true))
        recovery.sleeping=true;precondition(!recovery.shouldResume(now:0,ready:true,idle:true))
        recovery.sleeping=false;recovery.startFailed(now:0)
        precondition(!recovery.shouldResume(now:1,ready:true,idle:true) && recovery.shouldResume(now:2,ready:true,idle:true))
        recovery.startFailed(now:3);recovery.startFailed(now:8)
        precondition(!recovery.shouldResume(now:100,ready:true,idle:true))
        recovery.interrupted();precondition(recovery.shouldResume(now:100,ready:true,idle:true))
        recovery.requestStop();recovery.interrupted();precondition(!recovery.shouldResume(now:100,ready:true,idle:true))
        let mailbox=LatestFrameMailbox<Int>()
        precondition(mailbox.offer(1));precondition(!mailbox.offer(2));precondition(!mailbox.offer(3))
        precondition(mailbox.dropped==2 && mailbox.take()==3)
        precondition(mailbox.offer(4));mailbox.disable();precondition(mailbox.take()==nil && !mailbox.offer(5))
        var packet=[UInt8](repeating:0,count:64);packet[0]=0x99;packet[1]=0x65
        func setFloat(_ value:Float,_ offset:Int) {
            let bits=value.bitPattern
            for i in 0..<4 { packet[offset+i]=UInt8(truncatingIfNeeded:bits >> (i*8)) }
        }
        setFloat(12.5,16);setFloat(-3.5,20);setFloat(0.5,24);setFloat(1,12)
        precondition(IMUSample.decode(packet)?.gyro==[12.5,-3.5,0.5])
        precondition(IMUSample.decode([0]+packet)?.gyro==[12.5,-3.5,0.5])
        precondition(IMUSample.decode(Array(packet.dropLast()))==nil)
        setFloat(Float.nan,16);precondition(IMUSample.decode(packet)==nil)
        var gyro=GyroIntegrator()
        let stationary=IMUSample(gyro:[0.2,-0.1,0],acceleration:[0,0,1],temperature:25)
        for i in 0...220 { gyro.receive(stationary,at:Double(i)/100) }
        precondition(gyro.calibrated && abs(gyro.bias[0]-0.2)<1e-8)
        let turning=IMUSample(gyro:[0.2,89.9,0],acceleration:[0,0,1],temperature:25)
        for i in 221...320 { gyro.receive(turning,at:Double(i)/100) }
        precondition(abs(gyro.angles[1]*180 / .pi-89.55)<0.01)
        let before=gyro.angles[1];gyro.receive(turning,at:30)
        precondition(gyro.angles[1]==before && gyro.rejectedGaps==1)
        gyro.recenter();precondition(gyro.angles==[0,0,0])
        gyro.recalibrate();precondition(!gyro.calibrated)
        for i in 0...220 { gyro.receive(stationary,at:40+Double(i)/100) }
        let offset=IMUSample(gyro:[0.4,-0.1,0],acceleration:[0,0,1],temperature:25)
        for i in 221...3220 { gyro.receive(offset,at:40+Double(i)/100) }
        precondition(gyro.bias[0]>0.3 && gyro.bias[0]<0.4)
        // Hung, cancellation-ignoring work must not block timeout and late completion must be safe.
        let gate=TestGate()
        let time=ProcessInfo.processInfo.systemUptime
        do {
            _ = try await AsyncDeadline.run(seconds:0.03,label:"test") { await gate.wait();return 5 }
            preconditionFailure("expected timeout")
        } catch is OperationTimeout {}
        precondition(ProcessInfo.processInfo.systemUptime-time<1)
        gate.release();await Task.yield()
        let value=try await AsyncDeadline.run(seconds:1,label:"fast") { 7 }
        precondition(value==7)
        let cancelGate=TestGate()
        let task=Task { try await AsyncDeadline.run(seconds:10,label:"cancel") { await cancelGate.wait();return 4 } }
        await Task.yield();task.cancel()
        do { _ = try await task.value;preconditionFailure("expected cancellation") } catch is CancellationError {}
        cancelGate.release()
        print("PASS: settings, recovery/backoff/manual stop, latest-frame bounds, packet parsing, yaw integration/gaps/bias, timeout/cancellation/late completion")
    }
}
