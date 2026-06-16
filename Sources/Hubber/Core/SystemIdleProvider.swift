import Foundation
import IOKit

protocol MachineIdleProviding: Sendable {
    var isIdle: Bool { get }
}

/// Queries the system HID idle time via IOKit.
/// Returns true when the machine has been idle for at least 5 minutes.
struct SystemIdleProvider: MachineIdleProviding {
    static let idleThresholdSeconds: TimeInterval = 5 * 60

    var isIdle: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }

        guard
            let prop = IORegistryEntryCreateCFProperty(
                service,
                "HIDIdleTime" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() else { return false }

        let idleNs = (prop as? NSNumber)?.uint64Value ?? 0
        let idleSeconds = TimeInterval(idleNs) / 1_000_000_000
        return idleSeconds >= Self.idleThresholdSeconds
    }
}
