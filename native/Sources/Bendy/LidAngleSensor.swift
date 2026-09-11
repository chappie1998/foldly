import Foundation
import IOKit.hid

struct LidSensorReading {
    let angle: Double?
    let detail: String
}

final class LidAngleSensor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.bendy.lid-sensor", qos: .userInteractive)
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private var callback: ((LidSensorReading) -> Void)?

    func start(callback: @escaping (LidSensorReading) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.callback = callback
            let initial = self.connectAndRead()
            callback(initial)
            guard self.device != nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + .milliseconds(34), repeating: .milliseconds(34), leeway: .milliseconds(5))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                callback(self.readCurrent())
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            if let device = self.device {
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            if let manager = self.manager {
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            self.device = nil
            self.manager = nil
            self.callback = nil
        }
    }

    func diagnose() -> LidSensorReading {
        queue.sync {
            let reading = connectAndRead()
            if let device {
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            if let manager {
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            device = nil
            manager = nil
            return reading
        }
    }

    private func connectAndRead() -> LidSensorReading {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDPrimaryUsagePageKey as String: 0x20,
            kIOHIDPrimaryUsageKey as String: 0x8A
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            return LidSensorReading(angle: nil, detail: "Lid sensor could not be opened (IOKit \(openResult)).")
        }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let candidate = devices.first(where: Self.isExpectedDevice) else {
            return LidSensorReading(angle: nil, detail: "No compatible Apple lid-angle sensor found. Manual angle remains available.")
        }
        let deviceOpen = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceOpen == kIOReturnSuccess else {
            return LidSensorReading(angle: nil, detail: "Apple lid sensor is present but access failed (IOKit \(deviceOpen)).")
        }
        device = candidate
        return readCurrent()
    }

    private static func propertyInt(_ device: IOHIDDevice, _ key: CFString) -> Int? {
        (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.intValue
    }

    private static func isExpectedDevice(_ device: IOHIDDevice) -> Bool {
        propertyInt(device, kIOHIDVendorIDKey as CFString) == 0x05AC &&
        propertyInt(device, kIOHIDPrimaryUsagePageKey as CFString) == 0x20 &&
        propertyInt(device, kIOHIDPrimaryUsageKey as CFString) == 0x8A
    }

    private func readCurrent() -> LidSensorReading {
        guard let device else {
            return LidSensorReading(angle: nil, detail: "No compatible Apple lid-angle sensor found. Manual angle remains available.")
        }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(1), &report, &length)
        guard result == kIOReturnSuccess, length >= 3 else {
            return LidSensorReading(angle: nil, detail: "Sensor report unavailable (IOKit \(result)).")
        }
        let raw = Int(report[2]) << 8 | Int(report[1])
        guard (0...180).contains(raw) else {
            return LidSensorReading(angle: nil, detail: "Sensor returned an out-of-range value (\(raw)°).")
        }
        return LidSensorReading(angle: Double(raw), detail: "Hardware sensor active · \(raw)°")
    }
}
