import Foundation

struct IMUSample {
    let gyro: [Double]
    let acceleration: [Double]
    let temperature: Double
    static func decode(_ report: [UInt8]) -> Self? {
        let bytes = report.count == 65 && report.first == 0 ? Array(report.dropFirst()) : report
        guard bytes.count == 64, bytes[0] == 0x99, bytes[1] == 0x65 else { return nil }
        func float(_ offset: Int) -> Double {
            let bits = UInt32(bytes[offset]) | UInt32(bytes[offset+1]) << 8 | UInt32(bytes[offset+2]) << 16 | UInt32(bytes[offset+3]) << 24
            return Double(Float(bitPattern: bits))
        }
        let gyro = [float(16), float(20), float(24)]
        guard gyro.allSatisfy({ $0.isFinite && abs($0) < 4000 }) else { return nil }
        let acc = [float(4),float(8),float(12)]
        return Self(gyro: gyro, acceleration: acc, temperature: float(28))
    }
}

struct GyroIntegrator {
    var adaptiveBias = true
    private(set) var angles = [0.0,0,0]
    private(set) var bias = [0.0,0,0]
    private(set) var calibrated = false
    private(set) var samples = 0
    private(set) var stationarySeconds = 0.0
    private(set) var rejectedGaps = 0
    private(set) var temperature = 0.0
    private(set) var lastGyroDPS = [0.0,0,0]
    private(set) var calibrationVariance = [0.0,0,0]
    private var previousTime: Double?
    private var previousSpeed = [0.0,0,0]
    private var calibrationStart: Double?
    private var sums = [0.0,0,0]
    private var squares = [0.0,0,0]
    private var count = 0
    private var previousAccelerationNorm: Double?

    mutating func reset() {
        let adaptive = adaptiveBias; self = Self(); adaptiveBias = adaptive
    }
    mutating func recenter() { angles = [0,0,0] }
    mutating func recalibrate() {
        calibrated = false; count = 0; sums = [0,0,0]; squares = [0,0,0]
        calibrationStart = nil; previousTime = nil; stationarySeconds = 0; recenter()
    }
    mutating func receive(_ sample: IMUSample, at now: Double) {
        guard now.isFinite, sample.gyro.count == 3,
              sample.gyro.allSatisfy({ $0.isFinite && abs($0) < 4000 }) else { return }
        samples += 1
        lastGyroDPS = sample.gyro
        if sample.temperature.isFinite { temperature = sample.temperature }
        let elapsed = previousTime.map { now - $0 } ?? 0
        previousTime = now
        let dt = elapsed > 0 && elapsed <= 0.1 ? elapsed : 0
        if elapsed > 0.1 || elapsed < 0 { rejectedGaps += 1; stationarySeconds = 0; previousSpeed = [0,0,0] }
        if !calibrated {
            if sample.gyro.contains(where: { abs($0) > 3 }) {
                count = 0; sums = [0,0,0]; squares = [0,0,0]; calibrationStart = nil
                return
            }
            if calibrationStart == nil { calibrationStart = now }
            count += 1
            for i in 0..<3 { sums[i] += sample.gyro[i]; squares[i] += sample.gyro[i] * sample.gyro[i] }
            if now - (calibrationStart ?? now) >= 2 && count >= 200 {
                let mean = sums.map { $0 / Double(count) }
                let variance = (0..<3).map { max(0, squares[$0] / Double(count) - mean[$0] * mean[$0]) }
                calibrationVariance = variance
                // GT noise exceeded the experimental variance gate on real hardware,
                // permanently preventing calibration. Preserve v0.8's motion gate;
                // report variance for measurement instead of blocking head tracking.
                bias = mean; calibrated = true; previousSpeed = [0,0,0]
            }
            return
        }
        let accelerationNorm = sqrt(sample.acceleration.reduce(0) { $0 + $1 * $1 })
        let stableAcceleration = accelerationNorm.isFinite && accelerationNorm > 0.01 &&
            previousAccelerationNorm.map { abs(accelerationNorm - $0) / max($0, 0.01) < 0.02 } == true
        previousAccelerationNorm = accelerationNorm.isFinite ? accelerationNorm : nil
        var speed = (0..<3).map { sample.gyro[$0] - bias[$0] }
        // Only adapt after sustained stillness; no magnetometer/absolute-yaw correction is claimed.
        if dt > 0 && stableAcceleration && speed.allSatisfy({ abs($0) < 0.25 }) {
            stationarySeconds += dt
            if adaptiveBias && stationarySeconds >= 3 {
                let alpha = 1 - exp(-dt / 20)
                for i in 0..<3 { bias[i] += speed[i] * alpha; speed[i] = sample.gyro[i] - bias[i] }
            }
        } else { stationarySeconds = 0 }
        for i in 0..<3 {
            let current = abs(speed[i]) > 0.10 ? speed[i] : 0
            if dt > 0 { angles[i] += (current + previousSpeed[i]) * 0.5 * dt * .pi / 180 }
            previousSpeed[i] = current
        }
    }
}
