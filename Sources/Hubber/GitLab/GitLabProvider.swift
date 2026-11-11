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
        else { throw CodeHostAuthError.invalidResponse }

        return nodes.compactMap(Self.parseIncomingReview)
    }

    func fetchOutgoingPullRequests(
        accessToken: String,
        viewerLogin _: String,
        unresolvedMode _: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
        let payload = try await graphQL(
            query: Self.authoredMergeRequestsQuery,
            variables: ["first": 100],
            accessToken: accessToken
        )

        guard
            let currentUser = payload["currentUser"] as? [String: Any],
            let mergeRequests = currentUser["authoredMergeRequests"] as? [String: Any],
            let nodes = mergeRequests["nodes"] as? [[String: Any]]
        else { throw CodeHostAuthError.invalidResponse }

        return nodes.compactMap(Self.parseOutgoingReview)
    }

    func fetchDraftPullRequests(accessToken: String, limit: Int = 100) async throws -> [DraftReview] {
        let payload = try await graphQL(
            query: Self.authoredMergeRequestsQuery,
            variables: ["first": limit],
            accessToken: accessToken
        )

        guard
            let currentUser = payload["currentUser"] as? [String: Any],
            let mergeRequests = currentUser["authoredMergeRequests"] as? [String: Any],
            let nodes = mergeRequests["nodes"] as? [[String: Any]]
        else { throw CodeHostAuthError.invalidResponse }

        return nodes.compactMap(Self.parseDraftReview)
    }

    func graphQL(query: String, variables: [String: Any], accessToken: String) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CodeHostAuthError.invalidResponse }

        if http.statusCode == 401 {
            throw CodeHostAuthError.badCredentials
        }
        if http.statusCode == 429 {
            throw CodeHostAuthError.rateLimited(retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After"))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CodeHostAuthError.providerMessage("GitLab returned HTTP \(http.statusCode).")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let payload = json["data"] as? [String: Any] {
            return payload
        }
        if
            let errors = json["errors"] as? [[String: Any]],
            let message = errors.first?["message"] as? String {
            throw CodeHostAuthError.providerMessage(message)
        }
        throw CodeHostAuthError.invalidResponse
    }

    static func mapCI(_ status: String?) -> PullRequestCI {
        guard let status else { return .noChecks }
        switch status.uppercased() {
        case "SUCCESS":
            return .passing
        case "FAILED":
            return .failing
        case "RUNNING":
            return .running
        default:
            return .pending
        }
    }

    static func mapReviewState(_ state: String?) -> ReviewerState {
        switch state?.uppercased() {
        case "APPROVED":
            .approved
        case "REQUESTED_CHANGES":
            .changesRequested
        case "REVIEWED":
            .commented
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
        let author = CodeHostUser(
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

    private static func parseOutgoingReview(_ node: [String: Any]) -> OutgoingReview? {
        guard
            node["draft"] as? Bool == false,
            let id = node["id"] as? String,
            let number = intValue(node["iid"]),
            let title = node["title"] as? String,
            let repo = (node["project"] as? [String: Any])?["fullPath"] as? String
        else { return nil }

        let url = (node["webUrl"] as? String).flatMap(URL.init(string:))
        let updatedAt = (node["updatedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)) ?? Date()
        let pipelineStatus = (node["headPipeline"] as? [String: Any])?["status"] as? String
        let requiredApprovals = intValue(node["approvalsRequired"]) ?? 0
        let approvals = ((node["approvedBy"] as? [String: Any])?["nodes"] as? [[String: Any]])?.count ?? 0
        let resolvableDiscussions = intValue(node["resolvableDiscussionsCount"]) ?? 0
        let resolvedDiscussions = intValue(node["resolvedDiscussionsCount"]) ?? 0
        let mergeStatus = node["mergeStatusEnum"] as? String
        let diffStats = node["diffStatsSummary"] as? [String: Any]

        return OutgoingReview(
            id: id,
            repo: repo,
            number: number,
            title: title,
            url: url,
            ci: mapCI(pipelineStatus),
            ciDetail: pipelineStatus ?? "no pipeline",
            unresolved: max(0, resolvableDiscussions - resolvedDiscussions),
            approvals: approvals,
            requiredApprovals: requiredApprovals,
            reviewers: parseReviewers(node),
            updatedAgoHours: max(0, Date().timeIntervalSince(updatedAt) / 3600),
            mergeable: mergeStatus?.uppercased() == "CAN_BE_MERGED",
            additions: intValue(diffStats?["additions"]) ?? 0,
            deletions: intValue(diffStats?["deletions"]) ?? 0,
            files: intValue(diffStats?["fileCount"]) ?? 0
        )
    }

    private static func parseDraftReview(_ node: [String: Any]) -> DraftReview? {
        guard
            node["draft"] as? Bool == true,
            let id = node["id"] as? String,
            let number = intValue(node["iid"]),
            let title = node["title"] as? String,
            let repo = (node["project"] as? [String: Any])?["fullPath"] as? String
        else { return nil }

        let url = (node["webUrl"] as? String).flatMap(URL.init(string:))
        let updatedAt = (node["updatedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)) ?? Date()
        let pipelineStatus = (node["headPipeline"] as? [String: Any])?["status"] as? String
        let diffStats = node["diffStatsSummary"] as? [String: Any]

        return DraftReview(
            id: id,
            repo: repo,
            number: number,
            title: title,
            url: url,
            ci: mapCI(pipelineStatus),
            ciDetail: pipelineStatus ?? "no pipeline",
            commits: intValue(node["commitCount"]) ?? 0,
            updatedAt: updatedAt,
            additions: intValue(diffStats?["additions"]) ?? 0,
            deletions: intValue(diffStats?["deletions"]) ?? 0,
            files: intValue(diffStats?["fileCount"]) ?? 0
        )
    }

    private static func parseReviewers(_ node: [String: Any]) -> [Reviewer] {
        guard
            let reviewers = node["reviewers"] as? [String: Any],
            let reviewerNodes = reviewers["nodes"] as? [[String: Any]]
        else { return [] }

        return reviewerNodes.compactMap { reviewer -> Reviewer? in
            guard let login = reviewer["username"] as? String else { return nil }

            let avatarURL = (reviewer["avatarUrl"] as? String).flatMap(URL.init(string:))
            let interaction = reviewer["mergeRequestInteraction"] as? [String: Any]
            let user = CodeHostUser(
                login: login,
                initials: String(login.prefix(2)).uppercased(),
                color: colorForLogin(login),
                avatarURL: avatarURL
            )

            return Reviewer(
                user: user,
                state: mapReviewState(interaction?["reviewState"] as? String)
            )
        }
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

    private static let authoredMergeRequestsQuery = """
    query AuthoredMRs($first: Int!) {
      currentUser {
        authoredMergeRequests(state: opened, first: $first) {
          nodes {
            id
            iid
            title
            webUrl
            updatedAt
            draft
            project { fullPath }
            commitCount
            diffStatsSummary { additions deletions fileCount }
            approvalsRequired
            approvedBy {
              nodes { username }
            }
            resolvableDiscussionsCount
            resolvedDiscussionsCount
            mergeStatusEnum
            headPipeline { status }
            reviewers {
              nodes {
                username
                avatarUrl
                mergeRequestInteraction { reviewState }
              }
            }
          }
        }
      }
    }
    """
}
