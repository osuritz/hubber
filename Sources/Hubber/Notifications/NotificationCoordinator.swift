import Foundation

// MARK: - NotificationCoordinator

/// Orchestrates the diff → batch → dispatch pipeline.
/// Pure logic; inject `dispatcher` for testing.
@MainActor
final class NotificationCoordinator {
    private let dispatcher: any NotificationDispatching

    init(dispatcher: any NotificationDispatching = UNNotificationDispatcher()) {
        self.dispatcher = dispatcher
    }

    /// True when the user has explicitly denied notification authorization.
    var notificationsDenied: Bool {
        dispatcher.notificationsDenied
    }

    /// Run diff → batch → dispatch for `data` relative to `baseline`.
    /// Returns the new baseline snapshot.
    @discardableResult
    func processRefresh(
        data: HubberData,
        baseline: ReviewSnapshot?,
        enabledTypes: Set<NotificationEventType>
    ) async -> ReviewSnapshot {
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: enabledTypes)
        if !events.isEmpty {
            let authorized = await dispatcher.ensureAuthorized()
            if authorized {
                let contents = NotificationBatcher.contents(from: events)
                for content in contents {
                    await dispatcher.post(content)
                }
            }
        }
        return NotificationDiffer.snapshot(from: data)
    }
}
