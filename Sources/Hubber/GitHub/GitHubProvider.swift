import Foundation
import SwiftUI

final class GitHubProvider: CodeHostProvider {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Incoming Reviews

    func fetchIncomingReviews(
        accessToken: String,
        viewerLogin: String,
        mode: IncomingReviewMode
    ) async throws
        -> [IncomingReview]
    {
        var searchQuery = "is:pr is:open review-requested:@me"
        if mode == .team {
            searchQuery += " team-review-requested:@me"
        }

        let payload = try await graphQL(
            query: Self.incomingReviewsQuery,
            variables: ["searchQuery": searchQuery, "first": 100],
            accessToken: accessToken
        )

        guard
            let search = payload["search"] as? [String: Any],
            let nodes = search["nodes"] as? [[String: Any]]
        else { throw GitHubAuthError.invalidResponse }

        return nodes.compactMap { node in
            Self.parseIncomingReview(node: node, viewerLogin: viewerLogin)
        }
    }

    private static func parseIncomingReview(node: [String: Any], viewerLogin: String) -> IncomingReview? {
        guard
            node["__typename"] as? String == "PullRequest",
            node["isDraft"] as? Bool == false,
            let id = node["id"] as? String,
            let number = node["number"] as? Int,
            let title = node["title"] as? String,
            let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String,
            let authorNode = node["author"] as? [String: Any],
            let authorLogin = authorNode["login"] as? String
        else { return nil }

        let url = (node["url"] as? String).flatMap(URL.init(string:))
        let avatarURL = (authorNode["avatarUrl"] as? String).flatMap(URL.init(string:))
        let additions = node["additions"] as? Int ?? 0
        let deletions = node["deletions"] as? Int ?? 0
        let files = node["changedFiles"] as? Int ?? 0

        let sloStart = parseSLOClockStart(
            timelineNodes: (node["timelineItems"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [],
            viewerLogin: viewerLogin
        )

        let author = GitHubUser(
            login: authorLogin,
            initials: String(authorLogin.prefix(2)).uppercased(),
            color: colorForLogin(authorLogin),
            avatarURL: avatarURL
        )

        return IncomingReview(
            id: id,
            repo: repo,
            number: number,
            title: title,
            url: url,
            author: author,
            sloClockStart: sloStart,
            additions: additions,
            deletions: deletions,
            files: files
        )
    }

    /// SLO clock = max(earliest ReviewRequestedEvent for viewer, latest ReadyForReviewEvent).
    private static func parseSLOClockStart(
        timelineNodes: [[String: Any]],
        viewerLogin: String
    )
        -> Date
    {
        let iso = ISO8601DateFormatter()
        var reviewRequestedAt: Date?
        var readyForReviewAt: Date?

        for item in timelineNodes {
            switch item["__typename"] as? String {
            case "ReviewRequestedEvent":
                guard
                    let dateStr = item["createdAt"] as? String,
                    let date = iso.date(from: dateStr)
                else { continue }
                let reviewer = item["requestedReviewer"] as? [String: Any]
                let login = reviewer?["login"] as? String
                // Accept explicit user request or team request (no login field on Team).
                if login == viewerLogin || login == nil {
                    if let prev = reviewRequestedAt {
                        if date < prev { reviewRequestedAt = date }
                    } else {
                        reviewRequestedAt = date
                    }
                }
            case "ReadyForReviewEvent":
                guard
                    let dateStr = item["createdAt"] as? String,
                    let date = iso.date(from: dateStr)
                else { continue }
                if let prev = readyForReviewAt {
                    if date > prev { readyForReviewAt = date }
                } else {
                    readyForReviewAt = date
                }
            default:
                break
            }
        }

        let base = reviewRequestedAt ?? Date()
        if let ready = readyForReviewAt {
            return max(base, ready)
        }
        return base
    }

    // MARK: - Outgoing PRs

    func fetchOutgoingPullRequests(
        accessToken: String,
        viewerLogin: String,
        unresolvedMode: UnresolvedThreadMode
    ) async throws
        -> [OutgoingReview]
    {
        let payload = try await graphQL(
            query: Self.outgoingPRsQuery,
            variables: ["first": 100],
            accessToken: accessToken
        )

        guard
            let viewer = payload["viewer"] as? [String: Any],
            let prs = viewer["pullRequests"] as? [String: Any],
            let nodes = prs["nodes"] as? [[String: Any]]
        else { throw GitHubAuthError.invalidResponse }

        return nodes.compactMap { Self.parseOutgoingPR($0, unresolvedMode: unresolvedMode) }
    }

    private static func parseOutgoingPR(
        _ node: [String: Any],
        unresolvedMode: UnresolvedThreadMode
    )
        -> OutgoingReview?
    {
        guard
            node["isDraft"] as? Bool == false,
            let id = node["id"] as? String,
            let number = node["number"] as? Int,
            let title = node["title"] as? String,
            let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String
        else { return nil }

        let url = (node["url"] as? String).flatMap(URL.init(string:))
        let updatedAt = (node["updatedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)) ?? Date()
        let mergeable = (node["mergeable"] as? String) == "MERGEABLE"

        let (ci, ciDetail) = parseCIStatus(node)
        let reviewers = parseReviewers(node)
        let approvals = reviewers.count(where: { $0.state == .approved })
        let unresolved = countUnresolved(node, mode: unresolvedMode)

        return OutgoingReview(
            id: id,
            repo: repo,
            number: number,
            title: title,
            url: url,
            ci: ci,
            ciDetail: ciDetail,
            unresolved: unresolved,
            approvals: approvals,
            // GitHub API doesn't expose branch-protection required count without admin scope; default 1
            requiredApprovals: 1,
            reviewers: reviewers,
            updatedAgoHours: max(0, Date().timeIntervalSince(updatedAt) / 3600),
            mergeable: mergeable
        )
    }

    private static func parseCIStatus(_ node: [String: Any]) -> (PullRequestCI, String) {
        guard
            let commits = node["commits"] as? [String: Any],
            let commitNodes = commits["nodes"] as? [[String: Any]],
            let rollup = commitNodes.first?["commit"] as? [String: Any],
            let statusNode = rollup["statusCheckRollup"] as? [String: Any]
        else { return (.pending, "No checks") }

        let state = statusNode["state"] as? String ?? ""
        let contexts = statusNode["contexts"] as? [String: Any]
        let total = contexts?["totalCount"] as? Int ?? 0
        let contextNodes = contexts?["nodes"] as? [[String: Any]] ?? []

        let failing = contextNodes.count(where: {
            let conclusion = $0["conclusion"] as? String
            let checkState = $0["state"] as? String
            return conclusion == "FAILURE" || conclusion == "ERROR"
                || checkState == "FAILURE" || checkState == "ERROR"
        })
        let running = contextNodes.count(where: {
            let status = $0["status"] as? String
            let checkState = $0["state"] as? String
            return status == "IN_PROGRESS" || status == "QUEUED"
                || checkState == "PENDING"
        })

        switch state {
        case "SUCCESS":
            return (.passing, "\(total)/\(total) checks")
        case "FAILURE", "ERROR":
            let passing = total - failing
            return (.failing, "\(failing) failing · \(passing) passing")
        case "PENDING":
            if running > 0 {
                let done = total - running
                return (.running, "\(done)/\(total) checks · running")
            }
            return (.pending, "Pending")
        default:
            return (.pending, "No checks")
        }
    }

    private static func parseReviewers(_ node: [String: Any]) -> [Reviewer] {
        guard
            let reviews = node["latestReviews"] as? [String: Any],
            let reviewNodes = reviews["nodes"] as? [[String: Any]]
        else { return [] }

        return reviewNodes.compactMap { review -> Reviewer? in
            guard
                let author = review["author"] as? [String: Any],
                let login = author["login"] as? String,
                let stateStr = review["state"] as? String
            else { return nil }

            let state: ReviewerState = switch stateStr {
            case "APPROVED": .approved
            case "CHANGES_REQUESTED": .changesRequested
            case "COMMENTED", "DISMISSED": .commented
            default: .pending
            }

            let avatarURL = (author["avatarUrl"] as? String).flatMap(URL.init(string:))
            let user = GitHubUser(
                login: login,
                initials: String(login.prefix(2)).uppercased(),
                color: colorForLogin(login),
                avatarURL: avatarURL
            )

            return Reviewer(user: user, state: state)
        }
    }

    private static func countUnresolved(_ node: [String: Any], mode: UnresolvedThreadMode) -> Int {
        guard
            let threads = node["reviewThreads"] as? [String: Any],
            let threadNodes = threads["nodes"] as? [[String: Any]]
        else { return 0 }

        return threadNodes.count(where: { thread in
            guard
                thread["isResolved"] as? Bool == false,
                thread["isOutdated"] as? Bool == false
            else { return false }

            switch mode {
            case .allOpen:
                return true
            case .reviewOnly:
                let comment = (thread["comments"] as? [String: Any])?["nodes"] as? [[String: Any]]
                return comment?.first?["pullRequestReview"] as? [String: Any] != nil
            case .changesRequested:
                let comment = (thread["comments"] as? [String: Any])?["nodes"] as? [[String: Any]]
                let review = comment?.first?["pullRequestReview"] as? [String: Any]
                return review?["state"] as? String == "CHANGES_REQUESTED"
            }
        })
    }

    // MARK: - Drafts

    func fetchDraftPullRequests(accessToken: String, limit: Int = 100) async throws -> [DraftReview] {
        let payload = try await graphQL(
            query: Self.draftPullRequestsQuery,
            variables: ["first": limit],
            accessToken: accessToken
        )

        guard
            let viewer = payload["viewer"] as? [String: Any],
            let prs = viewer["pullRequests"] as? [String: Any],
            let nodes = prs["nodes"] as? [[String: Any]]
        else { throw GitHubAuthError.invalidResponse }

        let iso = ISO8601DateFormatter()
        return nodes.compactMap { node -> DraftReview? in
            guard
                node["isDraft"] as? Bool == true,
                let id = node["id"] as? String,
                let number = node["number"] as? Int,
                let title = node["title"] as? String,
                let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String,
                let updatedStr = node["updatedAt"] as? String,
                let updatedAt = iso.date(from: updatedStr)
            else { return nil }

            let url = (node["url"] as? String).flatMap(URL.init(string:))
            let commits = (node["commits"] as? [String: Any])?["totalCount"] as? Int ?? 0

            return DraftReview(
                id: id,
                repo: repo,
                number: number,
                title: title,
                url: url,
                ci: .pending,
                ciDetail: "not checked",
                commits: commits,
                updatedAt: updatedAt
            )
        }
    }

    // MARK: - GraphQL transport

    func graphQL(query: String, variables: [String: Any], accessToken: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubAuthError.invalidResponse }
        if http.statusCode == 401 { throw GitHubAuthError.badCredentials }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubAuthError.github("GitHub returned HTTP \(http.statusCode).")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if
            let errors = json["errors"] as? [[String: Any]],
            let message = errors.first?["message"] as? String
        {
            throw GitHubAuthError.github(message)
        }
        guard let payload = json["data"] as? [String: Any] else { throw GitHubAuthError.invalidResponse }
        return payload
    }

    // MARK: - Queries

    private static let incomingReviewsQuery = """
    query IncomingReviews($searchQuery: String!, $first: Int!) {
      search(query: $searchQuery, type: ISSUE, first: $first) {
        nodes {
          __typename
          ... on PullRequest {
            id
            number
            title
            url
            isDraft
            additions
            deletions
            changedFiles
            repository { nameWithOwner }
            author {
              login
              ... on User { avatarUrl }
            }
            timelineItems(first: 100, itemTypes: [REVIEW_REQUESTED_EVENT, READY_FOR_REVIEW_EVENT]) {
              nodes {
                __typename
                ... on ReviewRequestedEvent {
                  createdAt
                  requestedReviewer {
                    __typename
                    ... on User { login }
                    ... on Team { slug }
                  }
                }
                ... on ReadyForReviewEvent { createdAt }
              }
            }
          }
        }
      }
    }
    """

    private static let outgoingPRsQuery = """
    query OutgoingPRs($first: Int!) {
      viewer {
        pullRequests(first: $first, states: [OPEN], orderBy: {field: UPDATED_AT, direction: DESC}) {
          nodes {
            id
            number
            title
            url
            isDraft
            updatedAt
            mergeable
            repository { nameWithOwner }
            commits(last: 1) {
              nodes {
                commit {
                  statusCheckRollup {
                    state
                    contexts(first: 100) {
                      totalCount
                      nodes {
                        ... on CheckRun { status conclusion }
                        ... on StatusContext { state }
                      }
                    }
                  }
                }
              }
            }
            reviewThreads(first: 100) {
              nodes {
                isResolved
                isOutdated
                comments(first: 1) {
                  nodes {
                    author { login }
                    pullRequestReview {
                      state
                      author { login }
                    }
                  }
                }
              }
            }
            latestReviews: reviews(last: 20) {
              nodes {
                author { login ... on User { avatarUrl } }
                state
              }
            }
          }
        }
      }
    }
    """

    private static let draftPullRequestsQuery = """
    query DraftPullRequests($first: Int!) {
      viewer {
        pullRequests(first: $first, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
          nodes {
            id
            number
            title
            isDraft
            url
            updatedAt
            repository { nameWithOwner }
            commits(last: 1) { totalCount }
          }
        }
      }
    }
    """
}

/// Deterministic pastel color from login string — no external dependency.
private func colorForLogin(_ login: String) -> Color {
    let hue = Double(login.unicodeScalars.reduce(0) { $0 &+ $1.value } % 360) / 360.0
    return Color(hue: hue, saturation: 0.55, brightness: 0.85)
}
