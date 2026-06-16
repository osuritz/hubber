import Foundation

// MARK: - NotificationContent

struct NotificationContent: Equatable {
    /// Stable identifier for deduplication (type + prID or type + "batched").
    let id: String
    let title: String
    let body: String
    /// The PR to open on tap. Nil for batched multi-PR notifications.
    let url: URL?
}

// MARK: - NotificationBatcher

enum NotificationBatcher {

    /// Groups `events` by type; returns one `NotificationContent` per type.
    /// Single event → specific copy. Multiple events of same type → batched copy with count.
    static func contents(from events: [NotificationEvent]) -> [NotificationContent] {
        let grouped = Dictionary(grouping: events, by: \.type)
        // Preserve a stable ordering (CaseIterable order)
        return NotificationEventType.allCases.compactMap { type in
            guard let group = grouped[type], !group.isEmpty else { return nil }
            return group.count == 1 ? specificContent(for: group[0]) : batchedContent(type: type, events: group)
        }
    }

    // MARK: - Private helpers

    private static func specificContent(for event: NotificationEvent) -> NotificationContent {
        let (title, body) = specificCopy(for: event)
        return NotificationContent(
            id: "\(event.type.rawValue)-\(event.prID)",
            title: title,
            body: body,
            url: event.url
        )
    }

    private static func batchedContent(
        type: NotificationEventType,
        events: [NotificationEvent]
    ) -> NotificationContent {
        let count = events.count
        let (title, body) = batchedCopy(type: type, count: count)
        return NotificationContent(
            id: "\(type.rawValue)-batched",
            title: title,
            body: body,
            url: nil
        )
    }

    private static func specificCopy(for event: NotificationEvent) -> (title: String, body: String) {
        switch event.type {
        case .newReview:
            ("New review requested", "New review · \(event.repo) #\(event.number)")
        case .reviewApproved:
            ("Review approved", "\(event.repo) #\(event.number) was approved")
        case .changesRequested:
            ("Changes requested", "\(event.repo) #\(event.number) — changes requested")
        case .ciFailed:
            ("CI failed", "\(event.repo) #\(event.number) — CI is failing")
        case .prMerged:
            ("PR merged", "\(event.repo) #\(event.number) was merged")
        }
    }

    private static func batchedCopy(type: NotificationEventType, count: Int) -> (title: String, body: String) {
        switch type {
        case .newReview:
            ("New review requests", "\(count) new review requests")
        case .reviewApproved:
            ("Reviews approved", "\(count) reviews approved")
        case .changesRequested:
            ("Changes requested", "\(count) PRs — changes requested")
        case .ciFailed:
            ("CI failures", "\(count) PRs have CI failures")
        case .prMerged:
            ("PRs merged", "\(count) PRs were merged")
        }
    }
}
