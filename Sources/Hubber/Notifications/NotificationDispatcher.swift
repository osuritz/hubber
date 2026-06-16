import Foundation
import UserNotifications

// MARK: - NotificationDispatching protocol

protocol NotificationDispatching: Sendable {
    /// Requests authorization if not yet determined; returns `true` when authorized.
    /// Result is cached after the first call (lazy authorization, #36).
    func ensureAuthorized() async -> Bool

    /// Posts a notification. No-ops gracefully if not authorized or UN is unavailable.
    func post(_ content: NotificationContent) async
}

// MARK: - UNNotificationDispatcher

/// Production dispatcher backed by `UNUserNotificationCenter`.
/// Authorization is requested lazily the first time it is needed (#36).
/// If the process has no bundle ID (SPM executable mode), UN may be unavailable
/// and will error gracefully — no crash, no-op.
final class UNNotificationDispatcher: NotificationDispatching {
    /// UNUserNotificationCenter is not Sendable in the SDK headers; nonisolated(unsafe)
    /// is safe here because the center is set once at init and used only via its own
    /// async methods which are internally concurrency-safe.
    private nonisolated(unsafe) let center: UNUserNotificationCenter

    // Cache the authorization result after the first request.
    // Two booleans avoid Optional<Bool> (lint: discouraged_optional_boolean).
    @MainActor private var authorizationDetermined = false
    @MainActor private var authorizationGranted = false
    @MainActor private(set) var notificationsDenied = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    nonisolated func ensureAuthorized() async -> Bool {
        // Fast path: already determined
        let (determined, granted) = await MainActor.run { (authorizationDetermined, authorizationGranted) }
        if determined { return granted }

        // Slow path: request authorization for the first time
        do {
            let result = try await center.requestAuthorization(options: [.alert, .sound])
            await MainActor.run {
                authorizationDetermined = true
                authorizationGranted = result
                notificationsDenied = !result
            }
            return result
        } catch {
            // UN may throw if there is no bundle ID (SPM executable pre-M4).
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
