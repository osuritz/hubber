import Foundation
import SwiftUI

extension GitHubProvider {

    // MARK: - Outgoing PRs

    func fetchOutgoingPullRequests(
        accessToken: String,
        viewerLogin: String,
        unresolvedMode: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
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

    static func parseOutgoingPR(
        _ node: [String: Any],
        unresolvedMode: UnresolvedThreadMode
    ) -> OutgoingReview? {
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

    static func parseCIStatus(_ node: [String: Any]) -> (PullRequestCI, String) {
        guard
            let commits = node["commits"] as? [String: Any],
            let commitNodes = commits["nodes"] as? [[String: Any]],
            let rollup = commitNodes.first?["commit"] as? [String: Any],
            let statusNode = rollup["statusCheckRollup"] as? [String: Any]
        else { return (.noChecks, "No checks") }

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
            return (.noChecks, "No checks")
        }
    }

    static func parseReviewers(_ node: [String: Any]) -> [Reviewer] {
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

    static func countUnresolved(_ node: [String: Any], mode: UnresolvedThreadMode) -> Int {
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
                return comment?.first?["pullRequestReview"] is [String: Any]
            case .changesRequested:
                let comment = (thread["comments"] as? [String: Any])?["nodes"] as? [[String: Any]]
                let review = comment?.first?["pullRequestReview"] as? [String: Any]
                return review?["state"] as? String == "CHANGES_REQUESTED"
            }
        })
    }

    // MARK: - Outgoing Query

    static let outgoingPRsQuery = """
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
}
