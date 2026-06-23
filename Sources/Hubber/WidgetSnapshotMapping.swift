import Foundation
import HubberKit

// MARK: - Live model → DTO mapping

// swiftlint:disable:next type_contents_order
extension WidgetSnapshot {
    /// Maps per-connection `HubberData` to a `WidgetSnapshot` DTO, tagging each row with its
    /// owning `connectionID`. This is the preferred production path because the aggregated
    /// `HubberData` in `HubberStore.data` loses per-connection attribution.
    ///
    /// `needsAttention` is computed with the same rule used by
    /// `AttentionState.attentionItems(data:)` and `TabBadgePresentation.counts(data:mode:.needsAttention)`:
    ///   - Incoming: every review needs attention (it is a pending request on the viewer).
    ///   - Outgoing: failing CI (`ci == .failing`) or unresolved threads (`unresolved > 0`).
    ///   - Draft:    failing CI only (`ci == .failing`).
    static func from(
        perConnectionData: [(id: ConnectionID, data: HubberData)],
        isSignedIn: Bool,
        lastUpdated: Date
    ) -> WidgetSnapshot {
        var incoming: [PRRowSnapshot] = []
        var outgoing: [PRRowSnapshot] = []
        var drafts: [PRRowSnapshot] = []
        var seenIncomingIDs = Set<String>()
        var seenOutgoingIDs = Set<String>()
        var seenDraftIDs = Set<String>()

        // Mirrors ConnectionAggregator.aggregate: first-write-wins for outgoing/drafts,
        // earliest sloClockStart wins for incoming (both flatten to DTO rows here, so we
        // just de-duplicate by id after the fact using the same first-wins rule).
        for (connID, data) in perConnectionData {
            let connIDStr = connID.description
            for r in data.incoming where seenIncomingIDs.insert(r.id).inserted {
                incoming.append(mapIncoming(r, connectionID: connIDStr))
            }
            for r in data.outgoing where seenOutgoingIDs.insert(r.id).inserted {
                outgoing.append(mapOutgoing(r, connectionID: connIDStr))
            }
            for r in data.drafts where seenDraftIDs.insert(r.id).inserted {
                drafts.append(mapDraft(r, connectionID: connIDStr))
            }
        }

        let connections = perConnectionData.map { item in
            ConnectionSummary(
                id: item.id.description,
                displayName: "\(item.id.providerDisplayName) · @\(item.id.login)"
            )
        }

        return WidgetSnapshot(
            meta: SnapshotMeta(lastUpdated: lastUpdated, isSignedIn: isSignedIn),
            connections: connections,
            incoming: incoming,
            outgoing: outgoing,
            drafts: drafts
        )
    }

    /// Maps the app's live `HubberData` flat arrays to a `WidgetSnapshot` DTO.
    ///
    /// Prefer `from(perConnectionData:isSignedIn:lastUpdated:)` for the production write-path;
    /// this overload exists for callers that have already aggregated data (tests, back-compat).
    ///
    /// `needsAttention` is computed with the same rule used by
    /// `AttentionState.attentionItems(data:)` and `TabBadgePresentation.counts(data:mode:.needsAttention)`:
    ///   - Incoming: every review needs attention (it is a pending request on the viewer).
    ///   - Outgoing: failing CI (`ci == .failing`) or unresolved threads (`unresolved > 0`).
    ///   - Draft:    failing CI only (`ci == .failing`).
    static func from( // swiftlint:disable:this function_parameter_count
        incoming: [IncomingReview],
        outgoing: [OutgoingReview],
        drafts: [DraftReview],
        connections: [(id: ConnectionID, displayName: String)],
        isSignedIn: Bool,
        lastUpdated: Date
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            meta: SnapshotMeta(lastUpdated: lastUpdated, isSignedIn: isSignedIn),
            connections: connections.map {
                ConnectionSummary(id: $0.id.description, displayName: $0.displayName)
            },
            incoming: incoming.map { mapIncoming($0, connectionID: "") },
            outgoing: outgoing.map { mapOutgoing($0, connectionID: "") },
            drafts: drafts.map { mapDraft($0, connectionID: "") }
        )
    }
}

// MARK: - Per-row mappers

private func mapIncoming(_ r: IncomingReview, connectionID: String) -> PRRowSnapshot {
    PRRowSnapshot(
        id: r.id,
        connectionID: connectionID,
        repo: r.repo,
        number: r.number,
        title: r.title,
        url: r.url,
        ci: .noChecks,
        review: .none,
        ageHours: r.assignedAgoHours,
        additions: r.additions,
        deletions: r.deletions,
        files: r.files,
        // Every incoming review needs attention — the viewer has been asked to review it.
        // Source: AttentionState.attentionItems iterates data.incoming unconditionally.
        needsAttention: true
    )
}

private func mapOutgoing(_ r: OutgoingReview, connectionID: String) -> PRRowSnapshot {
    PRRowSnapshot(
        id: r.id,
        connectionID: connectionID,
        repo: r.repo,
        number: r.number,
        title: r.title,
        url: r.url,
        ci: ciState(from: r.ci),
        review: reviewSummary(from: r.reviewVerdict),
        ageHours: r.updatedAgoHours,
        additions: r.additions,
        deletions: r.deletions,
        files: r.files,
        // Source: AttentionState.attentionItems: `if pr.ci == .failing || pr.unresolved > 0`
        // TabBadgePresentation.counts mode .needsAttention: same condition for .outgoing.
        needsAttention: r.ci == .failing || r.unresolved > 0
    )
}

private func mapDraft(_ r: DraftReview, connectionID: String) -> PRRowSnapshot {
    PRRowSnapshot(
        id: r.id,
        connectionID: connectionID,
        repo: r.repo,
        number: r.number,
        title: r.title,
        url: r.url,
        ci: ciState(from: r.ci),
        review: .none,
        ageHours: r.updatedAgoHours,
        additions: r.additions,
        deletions: r.deletions,
        files: r.files,
        // Source: TabBadgePresentation.counts mode .needsAttention for .drafts:
        // `data.drafts.count(where: { $0.ci == .failing })` — only failing CI triggers attention.
        needsAttention: r.ci == .failing
    )
}

// MARK: - Enum bridges

private func ciState(from ci: PullRequestCI) -> CIState {
    switch ci {
    case .passing: .passing
    case .failing: .failing
    case .running: .running
    case .pending: .pending
    case .noChecks: .noChecks
    }
}

private func reviewSummary(from verdict: ReviewVerdict) -> ReviewSummary {
    switch verdict {
    case .approved: .approved
    case .changesRequested: .changesRequested
    case .inReview: .commented
    case .awaitingReview: .pending
    }
}
