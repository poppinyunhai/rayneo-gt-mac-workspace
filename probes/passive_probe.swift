import Foundation
import AppKit
import CoreGraphics
import IOKit.hid

// Device discovery and passive input only. No SetReport, USB control requests,
// firmware updates, configuration changes, or exclusive device ownership.
print("Displays:")
for screen in NSScreen.screens {
    let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    print("  \(screen.localizedName) id=\(id) frame=\(screen.frame) pixels=\(CGDisplayPixelsWide(id))x\(CGDisplayPixelsHigh(id))")
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let match: [String: Any] = [kIOHIDVendorIDKey: 0x3941, kIOHIDProductIDKey: 0xAF50]
IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
print(String(format: "HID manager open: 0x%08x", status))
guard status == kIOReturnSuccess else { exit(2) }
defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
    print("No matching GT HID devices accessible.")
    exit(3)
}
var count = 0
let callback: IOHIDReportCallback = { _, result, _, type, reportID, report, length in
    count += 1
    if count <= 5 {
        let prefix = (0..<min(length, 24)).map { String(format: "%02x", report[$0]) }.joined(separator: " ")
        print("Input #\(count) result=\(result) type=\(type.rawValue) id=\(reportID) length=\(length) prefix=\(prefix)")
    }
}
var buffers: [UnsafeMutablePointer<UInt8>] = []
for device in devices {
    for key in [kIOHIDProductKey, kIOHIDPrimaryUsagePageKey, kIOHIDPrimaryUsageKey, kIOHIDMaxInputReportSizeKey] {
        print("  \(key): \(String(describing: IOHIDDeviceGetProperty(device, key as CFString)))")
    }
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    buffers.append(buffer)
    IOHIDDeviceRegisterInputReportCallback(device, buffer, 1024, callback, nil)
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
}
print("Listening passively for 10 seconds...")
CFRunLoopRunInMode(.defaultMode, 10, false)
print("Total passive input reports: \(count)")
for device in devices {
    IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
}
buffers.forEach { $0.deallocate() }
