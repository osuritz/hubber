import Foundation

// MARK: - Widget kind constant

/// Shared widget kind identifier. Used by both the host (WidgetCenter reload calls) and the
/// widget extension target (as `WidgetConfiguration.kind`). Lives in HubberKit so both sides
/// agree without string duplication.
public enum HubberWidgetKind {
    public static let prList = "com.osuritz.hubber.widget"
}

// MARK: - Schema version

public let currentSchemaVersion = 1

// MARK: - SnapshotMeta

public struct SnapshotMeta: Codable, Sendable, Equatable {
    public let lastUpdated: Date
    public let isSignedIn: Bool

    public init(lastUpdated: Date, isSignedIn: Bool) {
        self.lastUpdated = lastUpdated
        self.isSignedIn = isSignedIn
    }
}

// MARK: - ConnectionSummary

public struct ConnectionSummary: Codable, Sendable, Equatable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

// MARK: - CIState

/// Maps `PullRequestCI` from the live app to a Codable DTO.
/// `.passing` → CI checks all green.
/// `.failing` → at least one check failed.
/// `.running` → checks in progress.
/// `.pending` → checks have not started yet.
/// `.noChecks` → PR has no CI checks configured.
public enum CIState: String, Codable, Sendable, Equatable {
    case passing
    case failing
    case running
    case pending
    case noChecks
}

// MARK: - ReviewSummary

/// Aggregate review verdict for a PR row, distilled to Codable DTO.
/// `.approved` → required approvals met.
/// `.changesRequested` → at least one reviewer blocked the PR.
/// `.commented` → reviewers engaged but no decision.
/// `.pending` → awaiting first reviewer action.
/// `.none` → no reviewers assigned.
public enum ReviewSummary: String, Codable, Sendable, Equatable {
    case approved
    case changesRequested
    case commented
    case pending
    case none
}

// MARK: - PRRowSnapshot

public struct PRRowSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let connectionID: String
    public let repo: String
    public let number: Int
    public let title: String
    public let url: URL?
    public let ci: CIState
    public let review: ReviewSummary
    public let ageHours: Double
    public let additions: Int
    public let deletions: Int
    public let files: Int
    public let needsAttention: Bool

    public init(
        id: String,
        connectionID: String,
        repo: String,
        number: Int,
        title: String,
        url: URL?,
        ci: CIState,
        review: ReviewSummary,
        ageHours: Double,
        additions: Int,
        deletions: Int,
        files: Int,
        needsAttention: Bool
    ) {
        self.id = id
        self.connectionID = connectionID
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.ci = ci
        self.review = review
        self.ageHours = ageHours
        self.additions = additions
        self.deletions = deletions
        self.files = files
        self.needsAttention = needsAttention
    }
}

// MARK: - WidgetSnapshot

public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let meta: SnapshotMeta
    public let connections: [ConnectionSummary]
    public let incoming: [PRRowSnapshot]
    public let outgoing: [PRRowSnapshot]
    public let drafts: [PRRowSnapshot]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        meta: SnapshotMeta,
        connections: [ConnectionSummary],
        incoming: [PRRowSnapshot],
        outgoing: [PRRowSnapshot],
        drafts: [PRRowSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.meta = meta
        self.connections = connections
        self.incoming = incoming
        self.outgoing = outgoing
        self.drafts = drafts
    }
}
