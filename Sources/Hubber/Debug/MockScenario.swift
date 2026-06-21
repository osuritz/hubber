#if DEBUG
    import Foundation

    enum MockScenario: String, CaseIterable, Identifiable {
        case off
        case empty
        case small
        case large
        case error
        case loading
        case multiConnection

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .off: "Off"
            case .empty: "Empty"
            case .small: "Small"
            case .large: "Large"
            case .error: "Error"
            case .loading: "Loading"
            case .multiConnection: "Multi-connection"
            }
        }

        init?(env value: String?) {
            let normalized = value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard let normalized, !normalized.isEmpty else {
                self = .off
                return
            }
            switch normalized {
            case "empty": self = .empty
            case "small": self = .small
            case "large": self = .large
            case "error": self = .error
            case "loading": self = .loading
            case "multi", "multi-connection", "multiconnection": self = .multiConnection
            case "off": self = .off
            default: self = .off
            }
        }

        var connectionPlan: [MockConnectionPlan] {
            switch self {
            case .off:
                []
            case .empty:
                [Self.plan(login: "hubber-mock-empty", behavior: .data(Self.emptyData))]
            case .small:
                [Self.plan(login: "hubber-mock-small", behavior: .data(Self.smallData(prefix: "small")))]
            case .large:
                [Self.plan(login: "hubber-mock-large", behavior: .data(Self.largeData))]
            case .error:
                [Self.plan(login: "hubber-mock-error", behavior: .error)]
            case .loading:
                [Self.plan(login: "hubber-mock-loading", behavior: .loading)]
            case .multiConnection:
                [
                    MockConnectionPlan(
                        id: ConnectionID(provider: "github", host: "github.com", login: "hubber-mock-github"),
                        login: "hubber-mock-github",
                        behavior: .data(Self.multiConnectionGitHubData)
                    ),
                    MockConnectionPlan(
                        id: ConnectionID(provider: "gitlab", host: "gitlab.com", login: "hubber-mock-gitlab"),
                        login: "hubber-mock-gitlab",
                        behavior: .data(Self.multiConnectionGitLabData)
                    ),
                ]
            }
        }

        static var allMockConnectionIDs: [ConnectionID] {
            allCases.flatMap(\.connectionPlan).map(\.id)
        }

        private static func plan(login: String, behavior: MockBehavior) -> MockConnectionPlan {
            MockConnectionPlan(id: .gitHubDotCom(login: login), login: login, behavior: behavior)
        }

        private static let emptyData = HubberData(incoming: [], outgoing: [], drafts: [])

        private static let largeData = HubberData(
            incoming: incoming(count: 25, prefix: "large"),
            outgoing: outgoing(count: 25, prefix: "large"),
            drafts: drafts(count: 12, prefix: "large")
        )

        private static let multiConnectionGitHubData = HubberData(
            incoming: incoming(count: 4, prefix: "github"),
            outgoing: [
                outgoingReview(index: 0, prefix: "shared", id: Self.overlappingPullRequestID),
                outgoingReview(index: 1, prefix: "github"),
                outgoingReview(index: 2, prefix: "github"),
            ],
            drafts: drafts(count: 2, prefix: "github")
        )

        private static let multiConnectionGitLabData = HubberData(
            incoming: incoming(count: 3, prefix: "gitlab"),
            outgoing: [
                outgoingReview(index: 0, prefix: "shared", id: Self.overlappingPullRequestID),
                outgoingReview(index: 1, prefix: "gitlab"),
                outgoingReview(index: 2, prefix: "gitlab"),
            ],
            drafts: drafts(count: 2, prefix: "gitlab")
        )

        static let overlappingPullRequestID = "mock-overlap-pr-1042"

        private static func smallData(prefix: String) -> HubberData {
            HubberData(
                incoming: incoming(count: 3, prefix: prefix),
                outgoing: outgoing(count: 2, prefix: prefix),
                drafts: drafts(count: 1, prefix: prefix)
            )
        }

        private static func incoming(count: Int, prefix: String) -> [IncomingReview] {
            (0..<count).map { index in
                IncomingReview(
                    id: "\(prefix)-incoming-\(index)",
                    repo: repo(index: index),
                    number: 3000 + index,
                    title: title(index: index, kind: "Review"),
                    url: url(repo: repo(index: index), number: 3000 + index),
                    author: user(index: index),
                    sloClockStart: .hoursAgo(sloHours(index: index)),
                    additions: 24 + (index * 37) % 900,
                    deletions: 3 + (index * 19) % 300,
                    files: 1 + index % 18
                )
            }
        }

        private static func outgoing(count: Int, prefix: String) -> [OutgoingReview] {
            (0..<count).map { outgoingReview(index: $0, prefix: prefix) }
        }

        private static func outgoingReview(index: Int, prefix: String, id: String? = nil) -> OutgoingReview {
            let number = 4100 + index
            let ci = ci(index: index)
            return OutgoingReview(
                id: id ?? "\(prefix)-outgoing-\(index)",
                repo: repo(index: index + 2),
                number: number,
                title: title(index: index, kind: "Ship"),
                url: url(repo: repo(index: index + 2), number: number),
                ci: ci,
                ciDetail: ciDetail(ci: ci, index: index),
                unresolved: index % 6,
                approvals: index % 3,
                requiredApprovals: 2,
                reviewers: reviewers(index: index),
                updatedAgoHours: Double((index * 3) % 36) + 0.5,
                mergeable: index % 4 != 0
            )
        }

        private static func drafts(count: Int, prefix: String) -> [DraftReview] {
            (0..<count).map { index in
                let number = 5200 + index
                let ci = ci(index: index + 1)
                return DraftReview(
                    id: "\(prefix)-draft-\(index)",
                    repo: repo(index: index + 4),
                    number: number,
                    title: title(index: index, kind: "Draft"),
                    url: url(repo: repo(index: index + 4), number: number),
                    ci: ci,
                    ciDetail: ciDetail(ci: ci, index: index),
                    commits: 1 + index % 9,
                    updatedAt: .hoursAgo(Double(index + 1) * 1.75)
                )
            }
        }

        private static func title(index: Int, kind: String) -> String {
            let variants = [
                "\(kind): tighten refresh state handoff",
                "\(kind): handle reviewer changes after force-push",
                "\(kind): compact row layout for extremely long repository names and branch labels",
                "\(kind): fix São Paulo billing import",
                "\(kind): add 日本語 repository owner fallback",
                "\(kind): surface 🚦 CI transition in account menu",
                "\(kind): resolve flaky CI retry badge",
                "\(kind): untangle comments, approvals, and mergeability signals",
            ]
            return variants[index % variants.count]
        }

        private static func repo(index: Int) -> String {
            let repos = [
                "acme/payments-api",
                "acme/review-router",
                "northstar/mobile-release",
                "octo/data-sync",
                "platform/very-long-repository-name-for-layout-checks",
            ]
            return repos[index % repos.count]
        }

        private static func url(repo: String, number: Int) -> URL? {
            URL(string: "https://github.com/\(repo)/pull/\(number)")
        }

        private static func user(index: Int) -> CodeHostUser {
            [.marisol, .tobi, .kenji, .priyanka, .ines][index % 5]
        }

        private static func reviewers(index: Int) -> [Reviewer] {
            [
                Reviewer(user: user(index: index), state: reviewerState(index: index)),
                Reviewer(user: user(index: index + 2), state: reviewerState(index: index + 1)),
            ]
        }

        private static func reviewerState(index: Int) -> ReviewerState {
            [.approved, .changesRequested, .commented, .pending][index % 4]
        }

        private static func ci(index: Int) -> PullRequestCI {
            [.passing, .failing, .running, .pending, .noChecks][index % 5]
        }

        private static func ciDetail(ci: PullRequestCI, index: Int) -> String {
            switch ci {
            case .passing: "passing · \(8 + index % 4)/\(8 + index % 4)"
            case .failing: "failing · \(1 + index % 3) failed"
            case .running: "running · \(2 + index % 5)/11"
            case .pending: "pending · queued"
            case .noChecks: "no checks"
            }
        }

        private static func sloHours(index: Int) -> Double {
            switch index % 3 {
            case 0: Double(index % 4) + 1
            case 1: Double(index % 6) + 18
            default: Double(index % 10) + 31
            }
        }
    }

    enum MockBehavior {
        case data(HubberData)
        case error
        case loading
    }

    struct MockConnectionPlan {
        let id: ConnectionID
        let login: String
        let behavior: MockBehavior
    }
#endif
