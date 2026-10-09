import Foundation
import IOKit.hid

// Runtime-only IMU start/stop, using the reviewed RayNeo SDK framing.
// This program cannot send arbitrary commands. No firmware/calibration/config writes.
// Reference: verncat/RayNeo-Air-3S-Pro-OpenVR, src/RayneoApi.cpp
let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x3941, kIOHIDProductIDKey: 0xAF50,
                                      kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: 1] as CFDictionary)
let opened = IOHIDManagerOpen(manager, 0)
guard opened == kIOReturnSuccess else {
    print(String(format: "HID open failed: 0x%08x", opened)); exit(2)
}
defer { IOHIDManagerClose(manager, 0) }
guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, devices.count == 1,
      let device = devices.first else {
    print("Expected exactly one GT HID collection."); exit(3)
}
var reports = 0, samples = 0
var firstTime: Double = 0, lastTime: Double = 0
var minGyro = [Float](repeating: .infinity, count: 3)
var maxGyro = [Float](repeating: -.infinity, count: 3)
func floatLE(_ bytes: [UInt8], _ offset: Int) -> Float {
    let bits = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
               UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    return Float(bitPattern: bits)
}
let callback: IOHIDReportCallback = { _, result, _, _, _, data, length in
    guard result == kIOReturnSuccess else { return }
    reports += 1
    var bytes = Array(UnsafeBufferPointer(start: data, count: length))
    if bytes.count == 65 && bytes[0] == 0 { bytes.removeFirst() }
    guard bytes.count == 64, bytes[0] == 0x99 else { return }
    if bytes[1] != 0x65 {
        if reports <= 5 { print("Non-IMU frame type: \(bytes[1])") }
        return
    }
    let gyro = (0..<3).map { floatLE(bytes, 16 + $0 * 4) }
    let accel = (0..<3).map { floatLE(bytes, 4 + $0 * 4) }
    guard (gyro + accel).allSatisfy({ $0.isFinite }) else { return }
    samples += 1
    let now = ProcessInfo.processInfo.systemUptime
    if samples == 1 { firstTime = now }
    lastTime = now
    for axis in 0..<3 {
        minGyro[axis] = min(minGyro[axis], gyro[axis])
        maxGyro[axis] = max(maxGyro[axis], gyro[axis])
    }
    if samples <= 3 || samples % 500 == 0 {
        print("IMU #\(samples) gyro(deg/s)=\(gyro) accel=\(accel)")
    }
}
let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
defer { buffer.deallocate() }
IOHIDDeviceRegisterInputReportCallback(device, buffer, 1024, callback, nil)
IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
defer { IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue) }
func setStreaming(_ enabled: Bool) -> IOReturn {
    var packet = [UInt8](repeating: 0, count: 64)
    packet[0] = 0x66
    packet[1] = enabled ? 0x01 : 0x02
    return packet.withUnsafeBufferPointer { ptr in
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, ptr.baseAddress!, ptr.count)
    }
}
if CommandLine.arguments.contains("--stream") {
    let start = setStreaming(true)
    print(String(format: "Runtime IMU ON result: 0x%08x", start))
    defer {
        let stop = setStreaming(false)
        print(String(format: "Runtime IMU OFF result: 0x%08x", stop))
    }
    if start == kIOReturnSuccess {
        print("Reading IMU for 12 seconds. Small head movements may help verify axes.")
        CFRunLoopRunInMode(.defaultMode, 12, false)
    }
} else {
    print("Passive mode; use --stream to enable runtime IMU start/stop.")
    CFRunLoopRunInMode(.defaultMode, 12, false)
}
print("Reports: \(reports), finite decoded IMU samples: \(samples)")
if samples > 1 {
    print(String(format: "Observed sample rate: %.1f Hz", Double(samples - 1) / (lastTime - firstTime)))
    print("Gyro ranges: \(zip(minGyro, maxGyro).map { [$0.0, $0.1] })")
}
