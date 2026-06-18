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
    /// The connection ids whose data participates in the notification pass. When `notifyHidden`
    /// is false, hidden connections are excluded.
    static func notificationConnectionIDs(
        _ items: [(id: ConnectionID, data: HubberData)],
        visibility: ConnectionVisibility,
        notifyHidden: Bool
    ) -> [ConnectionID] {
        items
            .filter { notifyHidden || visibility.isVisible($0.id) }
            .map(\.id)
    }

    /// Coordinator-owned union diff.
    ///
    /// Called by the per-connection `onRefreshSucceeded` callback, wired in `wireCallbacks(on:)`.
    /// Diffs the UNION of all connection data against the MERGED union of all per-connection baselines,
    /// using current data as the baseline contribution for newly added connections that have not yet
    /// established their own notification baseline.
    /// fires ONE batch of notifications, then advances ONLY the refreshed connection's baseline.
    ///
    /// Respects per-tab partial failures: only the tabs that succeeded advance `refreshed`'s baseline,
    /// so a failed outgoing fetch never permanently drops the outgoing snapshot and never fires false
    /// "merged" events across refreshes.
    func handleRefreshSucceeded(_ refreshed: Connection?, _ tabSuccesses: TabSuccesses) async {
        let prior = notificationTail
        let pass = Task { @MainActor in
            _ = await prior.value
            await self.performNotificationPass(refreshed, tabSuccesses)
        }
        notificationTail = pass
        await pass.value
    }

    private func performNotificationPass(_ refreshed: Connection?, _ tabSuccesses: TabSuccesses) async {
        let participatingIDs = Set(Self.notificationConnectionIDs(
            connections.map { (id: $0.id, data: $0.data) },
            visibility: settings.connectionVisibility,
            notifyHidden: settings.notifyHiddenAccounts
        ))
        let participating = connections.filter { participatingIDs.contains($0.id) }
        let current = ConnectionAggregator.aggregate(participating.map(\.data))
        let baselinesForDiff = participating.map { connection in
            connection.notificationBaseline ?? NotificationDiffer.snapshot(from: connection.data)
        }
        let allBaselinesNil = participating.allSatisfy { $0.notificationBaseline == nil }
        // Pass nil only if ALL connections have nil baselines (initial-load-no-fire rule).
        // Nil-baseline connections in a mixed set contribute their current data as already known.
        let previous: ReviewSnapshot? = allBaselinesNil
            ? nil
            : ConnectionAggregator.mergedBaseline(baselinesForDiff)

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
