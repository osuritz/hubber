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

struct GitHubUser: Identifiable, Hashable {
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
    let author: GitHubUser
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

    var updatedAgoHours: Double {
        max(0, Date().timeIntervalSince(updatedAt) / 3600)
    }
}

struct Reviewer: Identifiable {
    let user: GitHubUser
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

extension GitHubUser {
    static let marisol = GitHubUser(login: "marisol", initials: "MR", color: Color(red: 0.49, green: 0.36, blue: 1.00))
    static let tobi = GitHubUser(login: "tobi-l", initials: "TL", color: Color(red: 0.12, green: 0.62, blue: 0.33))
    static let kenji = GitHubUser(login: "kenji", initials: "KS", color: Color(red: 0.84, green: 0.20, blue: 0.42))
    static let priyanka = GitHubUser(
        login: "priyanka", initials: "PV", color: Color(red: 0.06, green: 0.44, blue: 1.00)
    )
    static let ines = GitHubUser(login: "ines", initials: "IF", color: Color(red: 0.90, green: 0.47, blue: 0.00))
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
