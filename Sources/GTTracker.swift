import Foundation
import IOKit.hid

final class GTTracker {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    private var device: IOHIDDevice?
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    private var running = false
    var integrator = GyroIntegrator()
    var onConnectionChanged: ((Bool) -> Void)?
    private(set) var status = "等待 GT 连接"
    var connected: Bool { device != nil }
    var calibrated: Bool { integrator.calibrated }
    var angles: [Double] { integrator.angles }
    var samples: Int { integrator.samples }

    func start() {
        guard !running else { return }
        let match: [String: Any] = [kIOHIDVendorIDKey:0x3941, kIOHIDProductIDKey:0xAF50,
            kIOHIDPrimaryUsagePageKey:0xFF00, kIOHIDPrimaryUsageKey:1]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, result, _, device in
            guard let ctx, result == kIOReturnSuccess else { return }
            let tracker = Unmanaged<GTTracker>.fromOpaque(ctx).takeUnretainedValue()
            tracker.attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            let tracker = Unmanaged<GTTracker>.fromOpaque(ctx).takeUnretainedValue()
            tracker.detach(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            status = String(format:"GT HID 打开失败 (%08x)", result); return
        }
        running = true
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let selected = devices.first { attach(selected) }
    }
    func retryConnection() {
        if !running { start(); return }
        guard device == nil else { return }
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let selected = devices.first { attach(selected) }
    }
    private func attach(_ selected: IOHIDDevice) {
        guard running, device == nil else { return }
        device = selected; integrator.reset()
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(selected, buffer, 1024, { ctx, result, _, _, _, bytes, length in
            guard let ctx, result == kIOReturnSuccess else { return }
            let tracker = Unmanaged<GTTracker>.fromOpaque(ctx).takeUnretainedValue()
            guard tracker.connected, let sample = IMUSample.decode(Array(UnsafeBufferPointer(start:bytes,count:length))) else { return }
            tracker.integrator.receive(sample, at: ProcessInfo.processInfo.systemUptime)
            tracker.status = tracker.calibrated ? "GT 已连接 · 姿态追踪" : "请保持眼镜静止 2 秒，估计零偏"
        }, context)
        IOHIDDeviceScheduleWithRunLoop(selected, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = setStreaming(true)
        if result != kIOReturnSuccess {
            IOHIDDeviceUnscheduleFromRunLoop(selected, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceRegisterInputReportCallback(selected, buffer, 1024, nil, nil)
            device = nil
            status = String(format:"IMU 开启失败 (%08x)",result)
            onConnectionChanged?(false); return
        }
        status = "请保持眼镜静止 2 秒，估计零偏"
        onConnectionChanged?(true)
    }
    private func detach(_ removed: IOHIDDevice) {
        guard let device, CFEqual(device, removed) else { return }
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 1024, nil, nil)
        self.device = nil; integrator.reset(); status = "GT 已断开，等待重新连接"
        onConnectionChanged?(false)
    }
    private func setStreaming(_ enabled: Bool) -> IOReturn {
        guard let device else { return kIOReturnNoDevice }
        var bytes = [UInt8](repeating:0,count:64); bytes[0]=0x66; bytes[1]=enabled ? 1 : 2
        return bytes.withUnsafeBufferPointer { IOHIDDeviceSetReport(device,kIOHIDReportTypeOutput,0,$0.baseAddress!,64) }
    }
    func recenter() { integrator.recenter() }
    func recalibrate() { integrator.recalibrate() }
    func stop() {
        if let device {
            _ = setStreaming(false)
            IOHIDDeviceUnscheduleFromRunLoop(device,CFRunLoopGetMain(),CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceRegisterInputReportCallback(device,buffer,1024,nil,nil)
        }
        device = nil
        if running {
            IOHIDManagerUnscheduleFromRunLoop(manager,CFRunLoopGetMain(),CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager,0)
        }
        running = false; integrator.reset(); status = "IMU 已停止"
    }
    deinit { buffer.deallocate() }
}
