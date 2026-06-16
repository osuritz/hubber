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
    ) async throws -> [IncomingReview] {
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
    ) -> Date {
        let iso = ISO8601DateFormatter()
        var reviewRequestedAt: Date?
        var readyForReviewAt: Date?

        for item in timelineNodes {
            switch item["__typename"] as? String {
            case "ReviewRequestedEvent":
                applyReviewRequested(item, iso: iso, viewerLogin: viewerLogin, into: &reviewRequestedAt)
            case "ReadyForReviewEvent":
                applyReadyForReview(item, iso: iso, into: &readyForReviewAt)
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

    private static func applyReviewRequested(
        _ item: [String: Any],
        iso: ISO8601DateFormatter,
        viewerLogin: String,
        into current: inout Date?
    ) {
        guard
            let dateStr = item["createdAt"] as? String,
            let date = iso.date(from: dateStr)
        else { return }
        let reviewer = item["requestedReviewer"] as? [String: Any]
        let login = reviewer?["login"] as? String
        // Accept explicit user request or team request (no login field on Team).
        if login == viewerLogin || login == nil {
            if let prev = current {
                if date < prev { current = date }
            } else {
                current = date
            }
        }
    }

    private static func applyReadyForReview(
        _ item: [String: Any],
        iso: ISO8601DateFormatter,
        into current: inout Date?
    ) {
        guard
            let dateStr = item["createdAt"] as? String,
            let date = iso.date(from: dateStr)
        else { return }
        if let prev = current {
            if date > prev { current = date }
        } else {
            current = date
        }
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

        // Rate-limit detection: 429, or 403 with x-ratelimit-remaining: 0
        let isRateLimitedByHeader =
            http.statusCode == 403 &&
            http.value(forHTTPHeaderField: "x-ratelimit-remaining").flatMap(Int.init) == 0
        if http.statusCode == 429 || isRateLimitedByHeader {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
            throw GitHubAuthError.rateLimited(retryAfter: retryAfter)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw GitHubAuthError.github("GitHub returned HTTP \(http.statusCode).")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if
            let errors = json["errors"] as? [[String: Any]],
            let message = errors.first?["message"] as? String {
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
func colorForLogin(_ login: String) -> Color {
    let hue = Double(login.unicodeScalars.reduce(0) { $0 &+ $1.value } % 360) / 360.0
    return Color(hue: hue, saturation: 0.55, brightness: 0.85)
}
