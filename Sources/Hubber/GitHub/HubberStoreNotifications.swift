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
    /// avoids false "merged" events.
    func dispatchNotifications(tabSuccesses: TabSuccesses) async {
        var baseline = notificationBaseline

        // When a previous baseline exists, merge only the portions for succeeded tabs.
        if let existing = baseline {
            var mergedIncoming = existing.incomingIDs
            var mergedOutgoing = existing.outgoing
            if tabSuccesses.incoming {
                mergedIncoming = Set(data.incoming.map(\.id))
            }
            if tabSuccesses.outgoing {
                mergedOutgoing = NotificationDiffer.snapshot(from: data).outgoing
            }
            baseline = ReviewSnapshot(incomingIDs: mergedIncoming, outgoing: mergedOutgoing)
        }

        let newSnapshot = await notificationCoordinator.processRefresh(
            data: data,
            baseline: baseline,
            enabledTypes: settings.enabledNotificationTypes
        )

        notificationBaseline = newSnapshot
        try? snapshotStore.save(newSnapshot)
    }
}
