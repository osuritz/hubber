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
        viewerLogin: String,
        mode: IncomingReviewMode
    ) async throws -> [IncomingReview] {
        []
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
}
