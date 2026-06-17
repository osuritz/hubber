import Foundation

final class GitLabProvider: CodeHostProvider {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "https://gitlab.com")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchIncomingReviews(
        accessToken: String,
        viewerLogin _: String,
        mode _: IncomingReviewMode
    ) async throws -> [IncomingReview] {
        let payload = try await graphQL(
            query: Self.incomingMergeRequestsQuery,
            variables: ["first": 100],
            accessToken: accessToken
        )

        guard
            let currentUser = payload["currentUser"] as? [String: Any],
            let mergeRequests = currentUser["reviewRequestedMergeRequests"] as? [String: Any],
            let nodes = mergeRequests["nodes"] as? [[String: Any]]
        else { throw GitHubAuthError.invalidResponse }

        return nodes.compactMap(Self.parseIncomingReview)
    }

    func fetchOutgoingPullRequests(
        accessToken: String,
        viewerLogin: String,
        unresolvedMode: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
        []
    }

    func fetchDraftPullRequests(accessToken: String, limit: Int = 100) async throws -> [DraftReview] {
        []
    }

    func graphQL(query: String, variables: [String: Any], accessToken: String) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubAuthError.invalidResponse }

        if http.statusCode == 401 { throw GitHubAuthError.badCredentials }
        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
            throw GitHubAuthError.rateLimited(retryAfter: retryAfter)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubAuthError.github("GitLab returned HTTP \(http.statusCode).")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let payload = json["data"] as? [String: Any] {
            return payload
        }
        if
            let errors = json["errors"] as? [[String: Any]],
            let message = errors.first?["message"] as? String {
            throw GitHubAuthError.github(message)
        }
        throw GitHubAuthError.invalidResponse
    }

    static func mapCI(_ status: String?) -> PullRequestCI {
        switch status?.uppercased() {
        case "SUCCESS":
            .passing
        case "FAILED":
            .failing
        case "RUNNING":
            .running
        default:
            .pending
        }
    }

    private static func parseIncomingReview(_ node: [String: Any]) -> IncomingReview? {
        guard
            node["draft"] as? Bool == false,
            let id = node["id"] as? String,
            let number = intValue(node["iid"]),
            let title = node["title"] as? String,
            let repo = (node["project"] as? [String: Any])?["fullPath"] as? String,
            let authorNode = node["author"] as? [String: Any],
            let authorLogin = authorNode["username"] as? String
        else { return nil }

        let url = (node["webUrl"] as? String).flatMap(URL.init(string:))
        let avatarURL = (authorNode["avatarUrl"] as? String).flatMap(URL.init(string:))
        let diffStats = node["diffStatsSummary"] as? [String: Any]
        let createdAt = (node["createdAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)) ?? Date()
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
            sloClockStart: createdAt,
            additions: intValue(diffStats?["additions"]) ?? 0,
            deletions: intValue(diffStats?["deletions"]) ?? 0,
            files: intValue(diffStats?["fileCount"]) ?? 0
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private static let incomingMergeRequestsQuery = """
    query IncomingMRs($first: Int!) {
      currentUser {
        reviewRequestedMergeRequests(state: opened, first: $first) {
          nodes {
            id
            iid
            title
            webUrl
            createdAt
            draft
            project { fullPath }
            author { username avatarUrl }
            diffStatsSummary { additions deletions fileCount }
          }
        }
      }
    }
    """
}
