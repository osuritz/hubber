import Foundation

// MARK: - TabSuccesses

/// Tracks which tabs fetched successfully in a given refresh cycle.
/// Used by the notification pipeline to avoid false "merged" events when a tab fails.
struct TabSuccesses {
    let incoming: Bool
    let outgoing: Bool
}

// MARK: - HubberStore notification pipeline extension

@MainActor
extension HubberStore {
    /// Diff + batch + dispatch notifications, then persist the updated snapshot.
    /// Respects per-tab partial failures: only updates snapshot portions for tabs that
    /// succeeded — so a failed outgoing fetch doesn't drop the outgoing snapshot and
    /// avoids false "merged" events across refreshes.
    func dispatchNotifications(tabSuccesses: TabSuccesses) async {
        let existing = notificationBaseline
        var diffBaseline = existing

        // When a previous baseline exists, merge only the portions for succeeded tabs.
        if let existing {
            var mergedIncoming = existing.incomingIDs
            var mergedOutgoing = existing.outgoing
            if tabSuccesses.incoming {
                mergedIncoming = Set(data.incoming.map(\.id))
            }
            if tabSuccesses.outgoing {
                mergedOutgoing = NotificationDiffer.snapshot(from: data).outgoing
            }
            diffBaseline = ReviewSnapshot(incomingIDs: mergedIncoming, outgoing: mergedOutgoing)
        }

        await notificationCoordinator.processRefresh(
            data: data,
            baseline: diffBaseline,
            enabledTypes: settings.enabledNotificationTypes
        )

        // Build the stored baseline by advancing only the tabs that succeeded.
        // This ensures a transient failure never permanently drops the outgoing portion.
        let freshSnapshot = NotificationDiffer.snapshot(from: data)
        let newBaseline: ReviewSnapshot
        if let existing {
            var newIncoming = existing.incomingIDs
            var newOutgoing = existing.outgoing
            if tabSuccesses.incoming { newIncoming = freshSnapshot.incomingIDs }
            if tabSuccesses.outgoing { newOutgoing = freshSnapshot.outgoing }
            newBaseline = ReviewSnapshot(incomingIDs: newIncoming, outgoing: newOutgoing)
        } else {
            newBaseline = freshSnapshot
        }
        notificationBaseline = newBaseline
        try? snapshotStore.save(newBaseline)
        notificationsDenied = notificationCoordinator.notificationsDenied
    }
}
