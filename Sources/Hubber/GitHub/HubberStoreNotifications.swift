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
    /// Coordinator-owned union diff.
    ///
    /// Called by the per-connection `onRefreshSucceeded` callback, wired in `wireCallbacks(on:)`.
    /// Diffs the UNION of all connection data against the MERGED union of all per-connection baselines,
    /// fires ONE batch of notifications, then advances ONLY the refreshed connection's baseline.
    ///
    /// Respects per-tab partial failures: only the tabs that succeeded advance `refreshed`'s baseline,
    /// so a failed outgoing fetch never permanently drops the outgoing snapshot and never fires false
    /// "merged" events across refreshes.
    func handleRefreshSucceeded(_ refreshed: Connection?, _ tabSuccesses: TabSuccesses) async {
        let current = ConnectionAggregator.aggregate(connections.map(\.data))
        let perConnectionBaselines = connections.compactMap(\.notificationBaseline)
        // Pass nil only if NO connection has a baseline yet (initial-load-no-fire rule).
        // An empty-but-non-nil baseline means "first refresh is done; any new PR is genuinely new."
        let previous: ReviewSnapshot? = perConnectionBaselines.isEmpty
            ? nil
            : ConnectionAggregator.mergedBaseline(perConnectionBaselines)

        await notificationCoordinator.processRefresh(
            data: current,
            baseline: previous,
            enabledTypes: settings.enabledNotificationTypes
        )

        // Advance ONLY the refreshed connection's baseline (per-connection baseline write-back).
        // Stale connections are untouched — they contribute to the union diff but their baselines
        // stay frozen until they refresh themselves, preventing false events for stale data.
        if let refreshed {
            advanceBaseline(for: refreshed, tabSuccesses: tabSuccesses)
        }

        notificationsDenied = notificationCoordinator.notificationsDenied
    }

    // MARK: - Private helpers

    /// Advances `connection`'s baseline using the succeeded-tabs-only logic.
    /// Only the portions for succeeded tabs are updated to avoid false "merged" events
    /// when a tab fetch failed transiently.
    private func advanceBaseline(for connection: Connection, tabSuccesses: TabSuccesses) {
        let existing = connection.notificationBaseline
        let freshSnapshot = NotificationDiffer.snapshot(from: connection.data)
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
        connection.notificationBaseline = newBaseline
        try? connection.snapshotStore.save(newBaseline)
    }
}
