import SwiftUI

enum WorkTab: String, CaseIterable, Identifiable {
    case incoming
    case outgoing
    case drafts

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .incoming: "Reviews"
        case .outgoing: "Outgoing"
        case .drafts: "Drafts"
        }
    }
}

enum PullRequestCI: String {
    case passing
    case failing
    case running
    case pending
    case noChecks
}

enum ReviewerState: String {
    case approved
    case changesRequested
    case commented
    case pending
}

enum SLOStatus {
    case green
    case amber
    case red
}

enum SLODisplay: String, CaseIterable, Identifiable {
    case remaining
    case elapsed
    case traffic

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .remaining: "Remaining"
        case .elapsed: "Elapsed"
        case .traffic: "Light only"
        }
    }
}

enum RowDensity: Int, CaseIterable, Identifiable {
    case compact = 1
    case normal = 2
    case spacious = 3

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .normal: "Default"
        case .spacious: "Spacious"
        }
    }
}

/// Menu-bar panel width preset. The panel height is automatic (a fraction of the screen),
/// so width is the only user-set dimension. `points` is the rendered width in points.
enum PanelWidth: Int, CaseIterable, Identifiable {
    case narrow = 1
    case normal = 2
    case wide = 3

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .narrow: "Narrow"
        case .normal: "Normal"
        case .wide: "Wide"
        }
    }

    var points: Double {
        switch self {
        case .narrow: 400
        case .normal: 460
        case .wide: 520
        }
    }
}

enum IncomingReviewMode: String, CaseIterable, Identifiable {
    case explicit
    case team

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .explicit: "Explicit requests"
        case .team: "Include team requests"
        }
    }
}

enum BadgeMode: String, CaseIterable, Identifiable {
    case incomingCount
    case attentionNeeded
    case off

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .incomingCount: "Incoming"
        case .attentionNeeded: "Attention"
        case .off: "Off"
        }
    }
}

/// Controls what the in-popover per-tab count badges represent. Independent of the
/// menubar `BadgeMode`, which governs the single status-item badge.
enum TabBadgeMode: String, CaseIterable, Identifiable {
    case needsAttention
    case totalCount

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .needsAttention: "Attention"
        case .totalCount: "Total"
        }
    }
}

enum UnresolvedThreadMode: String, CaseIterable, Identifiable {
    case allOpen
    case reviewOnly
    case changesRequested

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .allOpen: "All threads"
        case .reviewOnly: "Review threads"
        case .changesRequested: "Changes requested"
        }
    }
}

struct CodeHostUser: Identifiable, Hashable {
    let login: String
    let initials: String
    let color: Color
    let avatarURL: URL?

    var id: String {
        login
    }

    init(login: String, initials: String, color: Color, avatarURL: URL? = nil) {
        self.login = login
        self.initials = initials
        self.color = color
        self.avatarURL = avatarURL
    }
}

struct IncomingReview: Identifiable {
    let id: String
    let repo: String
    let number: Int
    let title: String
    let url: URL?
    let author: CodeHostUser
    let sloClockStart: Date // max(reviewRequestedAt, readyForReviewAt)
    let additions: Int
    let deletions: Int
    let files: Int

    var assignedAgoHours: Double {
        max(0, Date().timeIntervalSince(sloClockStart) / 3600)
    }
}

struct OutgoingReview: Identifiable {
    let id: String
    let repo: String
    let number: Int
    let title: String
    let url: URL?
    let ci: PullRequestCI
    let ciDetail: String
    let unresolved: Int
    let approvals: Int
    let requiredApprovals: Int
    let reviewers: [Reviewer]
    let updatedAgoHours: Double
    let mergeable: Bool
    let additions: Int
    let deletions: Int
    let files: Int

    /// `additions`/`deletions`/`files` default to 0 ("size unknown") so call sites
    /// that don't carry diff stats stay terse; providers fill in real values.
    init(
        id: String,
        repo: String,
        number: Int,
        title: String,
        url: URL?,
        ci: PullRequestCI,
        ciDetail: String,
        unresolved: Int,
        approvals: Int,
        requiredApprovals: Int,
        reviewers: [Reviewer],
        updatedAgoHours: Double,
        mergeable: Bool,
        additions: Int = 0,
        deletions: Int = 0,
        files: Int = 0
    ) {
        self.id = id
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.ci = ci
        self.ciDetail = ciDetail
        self.unresolved = unresolved
        self.approvals = approvals
        self.requiredApprovals = requiredApprovals
        self.reviewers = reviewers
        self.updatedAgoHours = updatedAgoHours
        self.mergeable = mergeable
        self.additions = additions
        self.deletions = deletions
        self.files = files
    }
}

struct DraftReview: Identifiable {
    let id: String
    let repo: String
    let number: Int
    let title: String
    let url: URL?
    let ci: PullRequestCI
    let ciDetail: String
    let commits: Int
    let updatedAt: Date
    let additions: Int
    let deletions: Int
    let files: Int

    var updatedAgoHours: Double {
        max(0, Date().timeIntervalSince(updatedAt) / 3600)
    }

    /// `additions`/`deletions`/`files` default to 0 ("size unknown") so call sites
    /// that don't carry diff stats stay terse; providers fill in real values.
    init(
        id: String,
        repo: String,
        number: Int,
        title: String,
        url: URL?,
        ci: PullRequestCI,
        ciDetail: String,
        commits: Int,
        updatedAt: Date,
        additions: Int = 0,
        deletions: Int = 0,
        files: Int = 0
    ) {
        self.id = id
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.ci = ci
        self.ciDetail = ciDetail
        self.commits = commits
        self.updatedAt = updatedAt
        self.additions = additions
        self.deletions = deletions
        self.files = files
    }
}

struct Reviewer: Identifiable {
    let user: CodeHostUser
    let state: ReviewerState

    var id: String {
        user.login
    }
}

struct DeveloperLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

struct HubberData {
    let incoming: [IncomingReview]
    let outgoing: [OutgoingReview]
    let drafts: [DraftReview]

    static let sample = HubberData(
        incoming: [],
        outgoing: [],
        drafts: [
            DraftReview(
                id: "pr-9835",
                repo: "acme/payments-api",
                number: 9835,
                title: "Spike: ledger double-entry rewrite",
                url: nil,
                ci: .running,
                ciDetail: "running · 3/11",
                commits: 6,
                updatedAt: .hoursAgo(0.5)
            ),
        ]
    )
}

extension Date {
    static func hoursAgo(_ hours: Double) -> Date {
        Date().addingTimeInterval(-hours * 3600)
    }
}

extension CodeHostUser {
    static let marisol = CodeHostUser(
        login: "marisol", initials: "MR", color: Color(red: 0.49, green: 0.36, blue: 1.00)
    )
    static let tobi = CodeHostUser(login: "tobi-l", initials: "TL", color: Color(red: 0.12, green: 0.62, blue: 0.33))
    static let kenji = CodeHostUser(login: "kenji", initials: "KS", color: Color(red: 0.84, green: 0.20, blue: 0.42))
    static let priyanka = CodeHostUser(
        login: "priyanka", initials: "PV", color: Color(red: 0.06, green: 0.44, blue: 1.00)
    )
    static let ines = CodeHostUser(login: "ines", initials: "IF", color: Color(red: 0.90, green: 0.47, blue: 0.00))
}

// MARK: - Auth state

enum HubberAuthState: Equatable {
    case restoring
    case signedOut
    case waitingForUser(GitHubDeviceAuthorization)
    case signedIn(login: String)
    case sessionExpired(login: String)
    case error(String)
}

// MARK: - Async result helpers

func catchingResult<T: Sendable>(_ body: @Sendable () async throws -> T) async -> Result<T, Error> {
    do { return try await .success(body()) } catch { return .failure(error) }
}

extension Result {
    var failureError: Failure? {
        if case let .failure(e) = self { e } else { nil }
    }
}
