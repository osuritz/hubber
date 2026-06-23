import Foundation
import HubberKit
import WidgetKit

// MARK: - Widget snapshot write-path

/// Holds the write-path logic that keeps the widget's App Group snapshot in sync with
/// `HubberStore`'s aggregated state.
///
/// ## Partial-failure preservation
/// `HubberData` already preserves last-known rows for failed connections.
/// `Connection.fetchAllTabsIndependently` (HubberStoreTabs.swift) calls `resolveTab`, which
/// returns the *existing* data for any tab whose fetch fails with a non-global error. So
/// `Connection.data` is never collapsed to empty on a partial failure — failed tabs keep their
/// last-known rows and successful tabs update normally. Because `recomputeAggregate` aggregates
/// each connection's current `data`, writing the snapshot after every recompute is sufficient
/// to satisfy the spec's "never silently collapsed to empty" requirement without extra code.
extension HubberStore {

    // MARK: - Write-path

    /// Builds a `WidgetSnapshot` from the current per-connection state and writes it to the
    /// App Group container via `store`, then asks WidgetKit to reload the PR-list widget's
    /// timeline.
    ///
    /// - Parameters:
    ///   - store: The `WidgetSnapshotStore` to write to. Pass `nil` (the default) to use the
    ///     live App Group store (`HubberStore.appGroupWidgetStore`). Pass a temp-dir store in
    ///     tests for deterministic, container-free verification.
    ///   - now: The timestamp recorded as `meta.lastUpdated`. Injected for testability;
    ///     defaults to `Date()` at the call site.
    ///
    /// Silently no-ops when the effective store is `nil` (App Group container unavailable —
    /// unsigned / ad-hoc builds without entitlements).
    func writeWidgetSnapshot(to store: WidgetSnapshotStore? = nil, now: Date = Date()) {
        guard let store = store ?? Self.appGroupWidgetStore else { return }

        // A user is "signed in" if at least one connection is in the .signedIn state.
        // canRefreshPullRequests on Connection checks exactly this condition.
        let isSignedIn = connections.contains(where: \.canRefreshPullRequests)

        let perConnectionData = connections.map { conn in
            (id: conn.id, data: conn.data)
        }

        let snapshot = WidgetSnapshot.from(
            perConnectionData: perConnectionData,
            isSignedIn: isSignedIn,
            lastUpdated: now
        )

        writeSnapshot(snapshot, to: store)
    }

    /// Writes an explicit signed-out snapshot (empty lists, `isSignedIn = false`) and reloads
    /// the widget timeline. Called after all connections are signed out.
    ///
    /// - Parameters:
    ///   - store: The `WidgetSnapshotStore` to write to. `nil` uses the live App Group store.
    ///   - now: The timestamp recorded as `meta.lastUpdated`. Injected for testability.
    func writeSignedOutWidgetSnapshot(to store: WidgetSnapshotStore? = nil, now: Date = Date()) {
        guard let store = store ?? Self.appGroupWidgetStore else { return }

        let snapshot = WidgetSnapshot(
            meta: SnapshotMeta(lastUpdated: now, isSignedIn: false),
            connections: [],
            incoming: [],
            outgoing: [],
            drafts: []
        )

        writeSnapshot(snapshot, to: store)
    }

    // MARK: - Shared write + reload

    /// Atomically writes `snapshot` and reloads the widget timeline.
    /// Write failures are swallowed — the widget shows the last successfully-written snapshot.
    private func writeSnapshot(_ snapshot: WidgetSnapshot, to store: WidgetSnapshotStore) {
        do {
            try store.write(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: HubberWidgetKind.prList)
        } catch {
            // Non-fatal: disk full / permissions. The widget will show the previous snapshot.
        }
    }

    // MARK: - Live App Group store (lazy singleton; nil = container unavailable)

    /// The live widget snapshot store backed by the real App Group container.
    /// `nil` when the container is unavailable (unsigned / ad-hoc builds without entitlements).
    /// Created lazily once; all production write calls fall back to this when no injected
    /// store is passed.
    static let appGroupWidgetStore: WidgetSnapshotStore? = WidgetSnapshotStore()
}
