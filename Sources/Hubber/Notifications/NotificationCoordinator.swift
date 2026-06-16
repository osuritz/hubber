import Foundation

// MARK: - NotificationCoordinator

/// Orchestrates the diff → batch → dispatch pipeline.
/// Pure logic; inject `dispatcher` and `snapshotStore` for testing.
@MainActor
final class NotificationCoordinator {
    private let dispatcher: any NotificationDispatching
    private let snapshotStore: SnapshotStore

    init(
        dispatcher: any NotificationDispatching = UNNotificationDispatcher(),
        snapshotStore: SnapshotStore = SnapshotStore()
    ) {
        self.dispatcher = dispatcher
        self.snapshotStore = snapshotStore
    }

    /// Run diff → batch → dispatch for `data` relative to `baseline`.
    /// Returns the new baseline snapshot (already persisted if provided snapshotStore is real).
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
