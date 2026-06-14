import SwiftUI

enum WorkTab: String, CaseIterable, Identifiable {
    case incoming
    case outgoing
    case drafts

    var id: String { rawValue }

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

enum ReviewerState {
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

    var id: String { rawValue }

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

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .normal: "Default"
        case .spacious: "Spacious"
        }
    }
}

struct GitHubUser: Identifiable, Hashable {
    let login: String
    let initials: String
    let color: Color

    var id: String { login }
}

struct IncomingReview: Identifiable {
    let id: String
    let repo: String
    let number: Int
    let title: String
    let author: GitHubUser
    let assignedAgoHours: Double
    let additions: Int
    let deletions: Int
    let files: Int
}

struct OutgoingReview: Identifiable {
    let id: String
    let repo: String
    let number: Int
    let title: String
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
    let ci: PullRequestCI
    let ciDetail: String
    let commits: Int
    let updatedAgoHours: Double
}

struct Reviewer: Identifiable {
    let user: GitHubUser
    let state: ReviewerState

    var id: String { user.login }
}

struct MockGitHubData {
    let incoming: [IncomingReview]
    let outgoing: [OutgoingReview]
    let drafts: [DraftReview]

    static let sample = MockGitHubData(
        incoming: [
            IncomingReview(
                id: "pr-9821",
                repo: "acme/payments-api",
                number: 9821,
                title: "Idempotency keys for refund retries",
                author: .marisol,
                assignedAgoHours: 0.4,
                additions: 142,
                deletions: 38,
                files: 7
            ),
            IncomingReview(
                id: "pr-9817",
                repo: "acme/web",
                number: 9817,
                title: "Switch checkout flow to server components",
                author: .tobi,
                assignedAgoHours: 2.3,
                additions: 612,
                deletions: 188,
                files: 24
            ),
            IncomingReview(
                id: "pr-9805",
                repo: "acme/infra",
                number: 9805,
                title: "Bump Postgres to 16.4 + reindex migration",
                author: .kenji,
                assignedAgoHours: 3.7,
                additions: 86,
                deletions: 41,
                files: 4
            ),
            IncomingReview(
                id: "pr-9788",
                repo: "acme/mobile-ios",
                number: 9788,
                title: "Fix biometric prompt race on cold launch",
                author: .priyanka,
                assignedAgoHours: 5.2,
                additions: 54,
                deletions: 29,
                files: 3
            ),
            IncomingReview(
                id: "pr-9776",
                repo: "acme/design-system",
                number: 9776,
                title: "Tokens: replace hex with semantic refs in Button",
                author: .ines,
                assignedAgoHours: 1.1,
                additions: 318,
                deletions: 290,
                files: 12
            )
        ],
        outgoing: [
            OutgoingReview(
                id: "pr-9830",
                repo: "acme/payments-api",
                number: 9830,
                title: "Webhook signature rotation playbook",
                ci: .passing,
                ciDetail: "12/12 checks",
                unresolved: 0,
                approvals: 2,
                requiredApprovals: 2,
                reviewers: [
                    Reviewer(user: .marisol, state: .approved),
                    Reviewer(user: .kenji, state: .approved)
                ],
                updatedAgoHours: 0.3,
                mergeable: true
            ),
            OutgoingReview(
                id: "pr-9826",
                repo: "acme/web",
                number: 9826,
                title: "Search: debounce typeahead + cancel stale fetches",
                ci: .failing,
                ciDetail: "2 failing · 9 passing",
                unresolved: 4,
                approvals: 0,
                requiredApprovals: 2,
                reviewers: [
                    Reviewer(user: .tobi, state: .changesRequested),
                    Reviewer(user: .ines, state: .pending)
                ],
                updatedAgoHours: 1.6,
                mergeable: true
            ),
            OutgoingReview(
                id: "pr-9819",
                repo: "acme/infra",
                number: 9819,
                title: "Terraform: split staging VPC modules",
                ci: .running,
                ciDetail: "8/14 checks · running",
                unresolved: 1,
                approvals: 1,
                requiredApprovals: 2,
                reviewers: [
                    Reviewer(user: .kenji, state: .approved),
                    Reviewer(user: .priyanka, state: .pending)
                ],
                updatedAgoHours: 0.1,
                mergeable: true
            ),
            OutgoingReview(
                id: "pr-9802",
                repo: "acme/cli",
                number: 9802,
                title: "Add acme env diff subcommand",
                ci: .passing,
                ciDetail: "9/9 checks",
                unresolved: 2,
                approvals: 1,
                requiredApprovals: 1,
                reviewers: [
                    Reviewer(user: .marisol, state: .commented)
                ],
                updatedAgoHours: 4.2,
                mergeable: false
            )
        ],
        drafts: [
            DraftReview(
                id: "pr-9835",
                repo: "acme/payments-api",
                number: 9835,
                title: "Spike: ledger double-entry rewrite",
                ci: .running,
                ciDetail: "running · 3/11",
                commits: 6,
                updatedAgoHours: 0.5
            ),
            DraftReview(
                id: "pr-9831",
                repo: "acme/web",
                number: 9831,
                title: "Experiment: streaming cart updates over SSE",
                ci: .passing,
                ciDetail: "11/11 checks",
                commits: 14,
                updatedAgoHours: 8
            ),
            DraftReview(
                id: "pr-9812",
                repo: "acme/design-system",
                number: 9812,
                title: "RFC: motion tokens",
                ci: .failing,
                ciDetail: "1 failing",
                commits: 3,
                updatedAgoHours: 26
            )
        ]
    )
}

extension GitHubUser {
    static let marisol = GitHubUser(login: "marisol", initials: "MR", color: Color(red: 0.49, green: 0.36, blue: 1.00))
    static let tobi = GitHubUser(login: "tobi-l", initials: "TL", color: Color(red: 0.12, green: 0.62, blue: 0.33))
    static let kenji = GitHubUser(login: "kenji", initials: "KS", color: Color(red: 0.84, green: 0.20, blue: 0.42))
    static let priyanka = GitHubUser(login: "priyanka", initials: "PV", color: Color(red: 0.06, green: 0.44, blue: 1.00))
    static let ines = GitHubUser(login: "ines", initials: "IF", color: Color(red: 0.90, green: 0.47, blue: 0.00))
}
