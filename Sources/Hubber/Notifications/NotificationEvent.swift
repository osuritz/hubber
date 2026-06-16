import Foundation

// MARK: - NotificationEventType

enum NotificationEventType: String, CaseIterable {
    case newReview
    case reviewApproved
    case changesRequested
    case ciFailed
    case prMerged
}

// MARK: - NotificationEvent

struct NotificationEvent: Equatable {
    let type: NotificationEventType
    let prID: String
    let repo: String
    let number: Int
    let title: String
    let url: URL?
}

// MARK: - ReviewSnapshot

struct ReviewSnapshot: Codable, Equatable {
    var incomingIDs: Set<String>
    var outgoing: [String: OutgoingSnapshot]
}

// MARK: - OutgoingSnapshot

struct OutgoingSnapshot: Codable, Equatable {
    /// login → ReviewerState.rawValue
    var reviewerStates: [String: String]
    /// PullRequestCI.rawValue
    var ci: String
    var mergeable: Bool
    /// approvals >= requiredApprovals (or any reviewer approved)
    var approved: Bool
}
