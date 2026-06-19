import Foundation
import ServiceManagement

/// Registers/unregisters Hubber as a macOS login item. Injectable so the logic that drives it
/// is testable without touching the real SMAppService (which requires a real .app bundle). (#106)
protocol LaunchAtLoginManaging: Sendable {
    /// True when Hubber is currently registered as a login item.
    var isEnabled: Bool { get }
    /// Registers (enabled) or unregisters (disabled) the login item.
    func setEnabled(_ enabled: Bool) throws
}

/// Production implementation backed by `SMAppService.mainApp` (macOS 13+).
///
/// Guarded on a real `.app` bundle: `SMAppService` register/unregister throw or no-op outside one
/// (e.g. `swift run` / xctest), so we never call it there — mirrors the notification bundle guard.
struct SMAppServiceLaunchAtLogin: LaunchAtLoginManaging {
    private var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var isEnabled: Bool {
        guard isBundledApp else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard isBundledApp else { return }
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        }
    }
}
