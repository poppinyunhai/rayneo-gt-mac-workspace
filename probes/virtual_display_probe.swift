import AppKit
import CoreGraphics

func listDisplays(_ label: String) {
    print(label)
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    _ = CGGetOnlineDisplayList(32, &ids, &count)
    for id in ids.prefix(Int(count)) {
        print("  id=\(id) vendor=\(CGDisplayVendorNumber(id)) size=\(CGDisplayPixelsWide(id))x\(CGDisplayPixelsHigh(id)) mirrorOf=\(CGDisplayMirrorsDisplay(id))")
    }
}
listDisplays("Before")
guard NSClassFromString("CGVirtualDisplay") != nil else { print("Virtual display API missing"); exit(2) }
var displays: [CGVirtualDisplay] = []
for (i, name) in ["RayNeo Left", "RayNeo Center", "RayNeo Right"].enumerated() {
    let descriptor = CGVirtualDisplayDescriptor()
    descriptor.name = name
    descriptor.maxPixelsWide = 1920; descriptor.maxPixelsHigh = 1080
    descriptor.sizeInMillimeters = CGSize(width: 530, height: 298)
    descriptor.vendorID = 0xC0D3; descriptor.productID = 0x4754
    descriptor.serialNum = UInt32(1001 + i)
    descriptor.setDispatchQueue(DispatchQueue.main)
    guard let display = CGVirtualDisplay(descriptor: descriptor) else { print("Creation failed: \(name)"); break }
    let settings = CGVirtualDisplaySettings()
    settings.hiDPI = 0
    settings.modes = [CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60)]
    guard display.apply(settings) else { print("Mode failed: \(name)"); break }
    displays.append(display)
    print("Created \(name) id=\(display.displayID)")
}
CFRunLoopRunInMode(.defaultMode, 3, false)
listDisplays("Three virtual displays alive")
var config: CGDisplayConfigRef?
let begin = CGBeginDisplayConfiguration(&config)
print("Layout begin: \(begin.rawValue)")
if let config {
    var failed = false
    for (i, display) in displays.enumerated() {
        let rc = CGConfigureDisplayOrigin(config, display.displayID, Int32(3390 + i * 1920), 0)
        print("Origin \(display.displayID) active=\(CGDisplayIsActive(display.displayID)) result=\(rc.rawValue)")
        if rc != .success { failed = true }
    }
    if failed { CGCancelDisplayConfiguration(config) }
    else { print("Layout commit: \(CGCompleteDisplayConfiguration(config, .forSession).rawValue)") }
}
print("Removing test displays")
displays.removeAll()
CFRunLoopRunInMode(.defaultMode, 3, false)
listDisplays("After cleanup")
