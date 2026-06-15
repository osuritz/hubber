import Foundation

final class GitHubPullRequestService: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchDraftPullRequests(accessToken: String, limit: Int = 100) async throws -> [DraftReview] {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            GraphQLRequest(
                query: Self.draftPullRequestsQuery,
                variables: GraphQLVariables(first: limit)
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAuthError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw GitHubAuthError.badCredentials
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubAuthError.github("GitHub returned HTTP \(httpResponse.statusCode).")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(GraphQLResponse.self, from: data)
        if let message = payload.errors?.first?.message {
            throw GitHubAuthError.github(message)
        }
        guard let responseData = payload.data else {
            throw GitHubAuthError.invalidResponse
        }

        return responseData.viewer.pullRequests.nodes
            .filter(\.isDraft)
            .map { node in
                DraftReview(
                    id: node.id,
                    repo: node.repository.nameWithOwner,
                    number: node.number,
                    title: node.title,
                    url: node.url,
                    ci: .pending,
                    ciDetail: "not checked",
                    commits: node.commits.totalCount,
                    updatedAt: node.updatedAt
                )
            }
    }

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
            repository {
              nameWithOwner
            }
            commits(last: 1) {
              totalCount
            }
          }
        }
      }
    }
    """
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: GraphQLVariables
}

private struct GraphQLVariables: Encodable {
    let first: Int
}

private struct GraphQLResponse: Decodable {
    let data: GraphQLData?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    let message: String
}

private struct GraphQLData: Decodable {
    let viewer: GraphQLViewer
}

private struct GraphQLViewer: Decodable {
    let pullRequests: GraphQLPullRequestConnection
}

private struct GraphQLPullRequestConnection: Decodable {
    let nodes: [GraphQLPullRequest]
}

private struct GraphQLPullRequest: Decodable {
    let id: String
    let number: Int
    let title: String
    let isDraft: Bool
    let url: URL
    let updatedAt: Date
    let repository: GraphQLRepository
    let commits: GraphQLCommitConnection
}

private struct GraphQLRepository: Decodable {
    let nameWithOwner: String
}

private struct GraphQLCommitConnection: Decodable {
    let totalCount: Int
}
