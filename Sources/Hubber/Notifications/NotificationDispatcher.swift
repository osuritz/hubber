import Foundation
import UserNotifications

// MARK: - NotificationDispatching protocol

protocol NotificationDispatching: Sendable {
    /// Requests authorization if not yet determined; returns `true` when authorized.
    /// Result is cached after the first call (lazy authorization, #36).
    func ensureAuthorized() async -> Bool

    /// Posts a notification. No-ops gracefully if not authorized or UN is unavailable.
    func post(_ content: NotificationContent) async

    /// True when the user has explicitly denied notification authorization.
    @MainActor var notificationsDenied: Bool { get }
}

// MARK: - UNNotificationDispatcher

/// Production dispatcher backed by `UNUserNotificationCenter`.
/// Authorization is requested lazily the first time it is needed (#36).
/// If the process has no bundle ID (SPM executable mode), UN may be unavailable
/// and will error gracefully — no crash, no-op.
final class UNNotificationDispatcher: NotificationDispatching {
    // Cache the authorization result after the first request.
    // Two booleans avoid Optional<Bool> (lint: discouraged_optional_boolean).
    @MainActor private var authorizationDetermined = false
    @MainActor private var authorizationGranted = false
    @MainActor private(set) var notificationsDenied = false

    init() {}

    /// True only inside a real `.app` bundle. `UNUserNotificationCenter.current()` raises an
    /// uncatchable Objective-C `NSException` ("bundleProxyForCurrentProcess is nil") when there
    /// is no app bundle — e.g. under `xctest` or `swift run` — so we must never touch it there.
    private nonisolated var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    nonisolated func ensureAuthorized() async -> Bool {
        // Fast path: already determined
        let (determined, granted) = await MainActor.run { (authorizationDetermined, authorizationGranted) }
        if determined {
            return granted
        }

        // No app bundle (xctest / `swift run`): treat UN as unavailable rather than crashing.
        // notificationsDenied stays false — this is an environment limitation, not a user denial.
        guard isBundledApp else {
            await MainActor.run {
                authorizationDetermined = true
                authorizationGranted = false
                notificationsDenied = false
            }
            return false
        }

        // Slow path: request authorization for the first time.
        let center = UNUserNotificationCenter.current()
        do {
            let result = try await center.requestAuthorization(options: [.alert, .sound])
            await MainActor.run {
                authorizationDetermined = true
                authorizationGranted = result
                notificationsDenied = !result
            }
            return result
        } catch {
            // UN throws when there is no bundle ID (SPM executable pre-M4).
            await MainActor.run {
                authorizationDetermined = true
                authorizationGranted = false
                notificationsDenied = true
            }
            return false
        }
    }

    nonisolated func post(_ content: NotificationContent) async {
        guard await ensureAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        let unContent = UNMutableNotificationContent()
        unContent.title = content.title
        unContent.body = content.body
        unContent.sound = .default
        if let url = content.url {
            unContent.userInfo = ["prURL": url.absoluteString]
        }
        let request = UNNotificationRequest(
            identifier: content.id,
            content: unContent,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            // Delivery failure is non-fatal (no bundle ID in SPM mode).
        }
    }
}
