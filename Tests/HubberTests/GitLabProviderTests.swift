import Foundation
import XCTest
@testable import Hubber

final class GitLabProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testConformsToCodeHostProvider() {
        let provider: any CodeHostProvider = GitLabProvider()

        XCTAssertTrue(provider is GitLabProvider)
    }

    func testGraphQLPostsToGitLabEndpointWithBearerTokenAndReturnsData() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.dataResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        let data = try await provider.graphQL(
            query: "query Test { currentUser { username } }",
            variables: ["first": 1],
            accessToken: "glpat-token"
        )

        XCTAssertEqual(
            MockURLProtocol.lastRequest?.url?.absoluteString,
            "https://gitlab.com/api/graphql"
        )
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer glpat-token")
        XCTAssertEqual(data["ok"] as? Bool, true)
    }

    func testGraphQL401ThrowsBadCredentials() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request, statusCode: 401), Data())
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        do {
            _ = try await provider.graphQL(
                query: "query Test { currentUser { username } }",
                variables: [:],
                accessToken: "bad"
            )
            XCTFail("Expected badCredentials")
        } catch CodeHostAuthError.badCredentials {
            // expected
        }
    }

    func testGraphQL200WithErrorsAndNoDataThrowsGitHubMessage() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.errorsResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        do {
            _ = try await provider.graphQL(
                query: "query Test { currentUser { username } }",
                variables: [:],
                accessToken: "tok"
            )
            XCTFail("Expected github error")
        } catch let CodeHostAuthError.providerMessage(message) {
            XCTAssertEqual(message, "x")
        }
    }

    func testFetchIncomingReviewsMapsReviewRequestedMergeRequestsAndSkipsDrafts() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.incomingMergeRequestsResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        let reviews = try await provider.fetchIncomingReviews(
            accessToken: "glpat-reviewer",
            viewerLogin: "osuritz",
            mode: .explicit
        )

        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.absoluteString, "https://gitlab.com/api/graphql")
        XCTAssertEqual(
            MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer glpat-reviewer"
        )
        XCTAssertEqual(reviews.count, 2)

        let first = try XCTUnwrap(reviews.first(where: { $0.id == "gid://gitlab/MergeRequest/101" }))
        XCTAssertEqual(first.repo, "namespace/project")
        XCTAssertEqual(first.number, 7)
        XCTAssertEqual(first.title, "Add GitLab incoming reviews")
        XCTAssertEqual(first.url?.absoluteString, "https://gitlab.com/namespace/project/-/merge_requests/7")
        XCTAssertEqual(first.author.login, "alice")
        XCTAssertEqual(first.author.initials, "AL")
        XCTAssertEqual(
            first.author.avatarURL?.absoluteString,
            "https://gitlab.com/uploads/-/system/user/avatar/1/avatar.png"
        )
        XCTAssertEqual(first.sloClockStart, try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-16T12:34:56Z")))
        XCTAssertEqual(first.additions, 42)
        XCTAssertEqual(first.deletions, 5)
        XCTAssertEqual(first.files, 3)

        let second = try XCTUnwrap(reviews.first(where: { $0.id == "gid://gitlab/MergeRequest/202" }))
        XCTAssertEqual(second.repo, "other/group-service")
        XCTAssertEqual(second.number, 7)
        XCTAssertEqual(second.title, "Keep iid project scoped")
        XCTAssertEqual(second.url?.absoluteString, "https://gitlab.com/other/group-service/-/merge_requests/7")
        XCTAssertEqual(second.author.login, "bob")
        XCTAssertEqual(second.sloClockStart, try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-17T09:00:00Z")))
        XCTAssertEqual(second.additions, 10)
        XCTAssertEqual(second.deletions, 11)
        XCTAssertEqual(second.files, 4)
    }

    func testMapCIMapsGitLabPipelineStatuses() {
        let cases: [(String?, PullRequestCI)] = [
            ("SUCCESS", .passing),
            ("success", .passing),
            ("FAILED", .failing),
            ("RUNNING", .running),
            ("CREATED", .pending),
            ("PENDING", .pending),
            ("MANUAL", .pending),
            ("SCHEDULED", .pending),
            ("CANCELED", .pending),
            ("SKIPPED", .pending),
            ("WAITING_FOR_RESOURCE", .pending),
            ("PREPARING", .pending),
            ("EXPLODING", .pending),
            (nil, .noChecks),
        ]

        for (status, expected) in cases {
            XCTAssertEqual(GitLabProvider.mapCI(status), expected, "status: \(status ?? "nil")")
        }
    }

    func testFetchOutgoingPullRequestsMapsAuthoredMergeRequestsAndSkipsDrafts() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.authoredMergeRequestsResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        let reviews = try await provider.fetchOutgoingPullRequests(
            accessToken: "glpat-author",
            viewerLogin: "osuritz",
            unresolvedMode: .allOpen
        )

        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.absoluteString, "https://gitlab.com/api/graphql")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer glpat-author")
        XCTAssertEqual(reviews.count, 3)
        XCTAssertNil(reviews.first(where: { $0.id == "gid://gitlab/MergeRequest/903" }))
    }

    func testFetchOutgoingPullRequestsCountsApprovedByForFreeTier() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.authoredMergeRequestsResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        let reviews = try await provider.fetchOutgoingPullRequests(
            accessToken: "glpat-author",
            viewerLogin: "osuritz",
            unresolvedMode: .allOpen
        )

        let freeTier = try XCTUnwrap(reviews.first(where: { $0.id == "gid://gitlab/MergeRequest/901" }))
        XCTAssertEqual(freeTier.requiredApprovals, 0)
        XCTAssertEqual(freeTier.approvals, 2)
    }

    func testFetchOutgoingPullRequestsMapsPremiumApprovalsUnresolvedPipelineAndMergeability() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.authoredMergeRequestsResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        let reviews = try await provider.fetchOutgoingPullRequests(
            accessToken: "glpat-author",
            viewerLogin: "osuritz",
            unresolvedMode: .allOpen
        )

        let premium = try XCTUnwrap(reviews.first(where: { $0.id == "gid://gitlab/MergeRequest/902" }))
        XCTAssertEqual(premium.repo, "namespace/premium-project")
        XCTAssertEqual(premium.number, 43)
        XCTAssertEqual(premium.title, "Premium approvals")
        XCTAssertEqual(premium.url?.absoluteString, "https://gitlab.com/namespace/premium-project/-/merge_requests/43")
        XCTAssertEqual(premium.requiredApprovals, 2)
        XCTAssertEqual(premium.approvals, 1)
        XCTAssertEqual(premium.unresolved, 3)
        XCTAssertEqual(premium.ci, .failing)
        XCTAssertEqual(premium.ciDetail, "FAILED")
        XCTAssertTrue(premium.mergeable)
        XCTAssertLessThanOrEqual(premium.updatedAgoHours, 24 * 370)
    }

    func testFetchOutgoingPullRequestsMapsBareNodeWithDefaults() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.authoredMergeRequestsResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        let reviews = try await provider.fetchOutgoingPullRequests(
            accessToken: "glpat-author",
            viewerLogin: "osuritz",
            unresolvedMode: .allOpen
        )

        let bare = try XCTUnwrap(reviews.first(where: { $0.id == "gid://gitlab/MergeRequest/905" }))
        XCTAssertEqual(bare.repo, "namespace/bare-project")
        XCTAssertEqual(bare.number, 46)
        XCTAssertEqual(bare.title, "Bare MR")
        XCTAssertNil(bare.url)
        XCTAssertEqual(bare.requiredApprovals, 0)
        XCTAssertEqual(bare.approvals, 0)
        XCTAssertEqual(bare.unresolved, 0)
        XCTAssertEqual(bare.ci, .noChecks)
        XCTAssertEqual(bare.ciDetail, "no pipeline")
        XCTAssertFalse(bare.mergeable)
        XCTAssertTrue(bare.reviewers.isEmpty)
    }

    func testFetchOutgoingPullRequestsMapsReviewerStates() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.authoredMergeRequestsResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        let reviews = try await provider.fetchOutgoingPullRequests(
            accessToken: "glpat-author",
            viewerLogin: "osuritz",
            unresolvedMode: .allOpen
        )

        let premium = try XCTUnwrap(reviews.first(where: { $0.id == "gid://gitlab/MergeRequest/902" }))
        XCTAssertEqual(premium.reviewers.count, 3)

        let approved = try XCTUnwrap(premium.reviewers.first(where: { $0.user.login == "alice" }))
        XCTAssertEqual(approved.state, .approved)
        XCTAssertEqual(approved.user.avatarURL?.absoluteString, "https://gitlab.com/alice.png")

        let changesRequested = try XCTUnwrap(premium.reviewers.first(where: { $0.user.login == "bob" }))
        XCTAssertEqual(changesRequested.state, .changesRequested)

        let pending = try XCTUnwrap(premium.reviewers.first(where: { $0.user.login == "carol" }))
        XCTAssertEqual(pending.state, .pending)
    }

    func testFetchDraftPullRequestsMapsAuthoredDraftMergeRequestsOnly() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.authoredMergeRequestsResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        let drafts = try await provider.fetchDraftPullRequests(accessToken: "glpat-author", limit: 7)

        let body = try XCTUnwrap(MockURLProtocol.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let variables = try XCTUnwrap(json["variables"] as? [String: Any])
        XCTAssertEqual(variables["first"] as? Int, 7)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.absoluteString, "https://gitlab.com/api/graphql")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer glpat-author")
        XCTAssertEqual(drafts.count, 2)
        XCTAssertNil(drafts.first(where: { $0.id == "gid://gitlab/MergeRequest/901" }))
        XCTAssertNil(drafts.first(where: { $0.id == "gid://gitlab/MergeRequest/902" }))

        let successDraft = try XCTUnwrap(drafts.first(where: { $0.id == "gid://gitlab/MergeRequest/903" }))
        XCTAssertEqual(successDraft.repo, "namespace/premium-project")
        XCTAssertEqual(successDraft.number, 44)
        XCTAssertEqual(successDraft.title, "Draft should be included in drafts")
        XCTAssertEqual(
            successDraft.url?.absoluteString,
            "https://gitlab.com/namespace/premium-project/-/merge_requests/44"
        )
        XCTAssertEqual(successDraft.ci, .passing)
        XCTAssertEqual(successDraft.ciDetail, "SUCCESS")
        XCTAssertEqual(successDraft.commits, 6)
        XCTAssertEqual(successDraft.updatedAt, try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-17T08:00:00Z")))

        let noPipelineDraft = try XCTUnwrap(drafts.first(where: { $0.id == "gid://gitlab/MergeRequest/904" }))
        XCTAssertEqual(noPipelineDraft.repo, "namespace/free-project")
        XCTAssertEqual(noPipelineDraft.number, 45)
        XCTAssertEqual(noPipelineDraft.title, "Draft without pipeline")
        XCTAssertEqual(
            noPipelineDraft.url?.absoluteString,
            "https://gitlab.com/namespace/free-project/-/merge_requests/45"
        )
        XCTAssertEqual(noPipelineDraft.ci, .noChecks)
        XCTAssertEqual(noPipelineDraft.ciDetail, "no pipeline")
        XCTAssertEqual(noPipelineDraft.commits, 0)
        XCTAssertEqual(
            noPipelineDraft.updatedAt,
            try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-17T07:00:00Z"))
        )
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func response(for request: URLRequest, statusCode: Int = 200) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        guard
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
        else { throw URLError(.badServerResponse) }
        return response
    }
}

private extension GitLabProviderTests {
    private static let dataResponse = Data("""
    { "data": { "ok": true } }
    """.utf8)

    private static let errorsResponse = Data("""
    { "errors": [{ "message": "x" }] }
    """.utf8)

    private static let incomingMergeRequestsResponse = Data("""
    {
      "data": {
        "currentUser": {
          "reviewRequestedMergeRequests": {
            "nodes": [
              {
                "id": "gid://gitlab/MergeRequest/101",
                "iid": "7",
                "title": "Add GitLab incoming reviews",
                "webUrl": "https://gitlab.com/namespace/project/-/merge_requests/7",
                "createdAt": "2026-06-16T12:34:56Z",
                "draft": false,
                "project": { "fullPath": "namespace/project" },
                "author": {
                  "username": "alice",
                  "avatarUrl": "https://gitlab.com/uploads/-/system/user/avatar/1/avatar.png"
                },
                "diffStatsSummary": { "additions": 42, "deletions": 5, "fileCount": 3 }
              },
              {
                "id": "gid://gitlab/MergeRequest/202",
                "iid": "7",
                "title": "Keep iid project scoped",
                "webUrl": "https://gitlab.com/other/group-service/-/merge_requests/7",
                "createdAt": "2026-06-17T09:00:00Z",
                "draft": false,
                "project": { "fullPath": "other/group-service" },
                "author": { "username": "bob", "avatarUrl": null },
                "diffStatsSummary": { "additions": 10, "deletions": 11, "fileCount": 4 }
              },
              {
                "id": "gid://gitlab/MergeRequest/303",
                "iid": "8",
                "title": "Draft should be skipped",
                "webUrl": "https://gitlab.com/namespace/project/-/merge_requests/8",
                "createdAt": "2026-06-17T10:00:00Z",
                "draft": true,
                "project": { "fullPath": "namespace/project" },
                "author": { "username": "carol", "avatarUrl": null },
                "diffStatsSummary": { "additions": 99, "deletions": 99, "fileCount": 9 }
              }
            ]
          }
        }
      }
    }
    """.utf8)

    private static let authoredMergeRequestsResponse = Data("""
    {
      "data": {
        "currentUser": {
          "authoredMergeRequests": {
            "nodes": [
              {
                "id": "gid://gitlab/MergeRequest/901",
                "iid": "42",
                "title": "Free tier approvals",
                "webUrl": "https://gitlab.com/namespace/free-project/-/merge_requests/42",
                "updatedAt": "2026-06-17T10:00:00Z",
                "draft": false,
                "project": { "fullPath": "namespace/free-project" },
                "commitCount": 1,
                "approvedBy": {
                  "nodes": [
                    { "username": "alice" },
                    { "username": "bob" }
                  ]
                },
                "resolvableDiscussionsCount": 0,
                "resolvedDiscussionsCount": 0,
                "mergeStatusEnum": "CANNOT_BE_MERGED",
                "headPipeline": null,
                "reviewers": { "nodes": [] }
              },
              {
                "id": "gid://gitlab/MergeRequest/902",
                "iid": "43",
                "title": "Premium approvals",
                "webUrl": "https://gitlab.com/namespace/premium-project/-/merge_requests/43",
                "updatedAt": "2026-06-17T09:00:00Z",
                "draft": false,
                "project": { "fullPath": "namespace/premium-project" },
                "commitCount": 3,
                "approvalsRequired": 2,
                "approvedBy": {
                  "nodes": [
                    { "username": "alice" }
                  ]
                },
                "resolvableDiscussionsCount": 5,
                "resolvedDiscussionsCount": 2,
                "mergeStatusEnum": "CAN_BE_MERGED",
                "headPipeline": { "status": "FAILED" },
                "reviewers": {
                  "nodes": [
                    {
                      "username": "alice",
                      "avatarUrl": "https://gitlab.com/alice.png",
                      "mergeRequestInteraction": { "reviewState": "APPROVED" }
                    },
                    {
                      "username": "bob",
                      "avatarUrl": null,
                      "mergeRequestInteraction": { "reviewState": "REQUESTED_CHANGES" }
                    },
                    {
                      "username": "carol",
                      "avatarUrl": null,
                      "mergeRequestInteraction": { "reviewState": "UNREVIEWED" }
                    }
                  ]
                }
              },
              {
                "id": "gid://gitlab/MergeRequest/903",
                "iid": "44",
                "title": "Draft should be included in drafts",
                "webUrl": "https://gitlab.com/namespace/premium-project/-/merge_requests/44",
                "updatedAt": "2026-06-17T08:00:00Z",
                "draft": true,
                "project": { "fullPath": "namespace/premium-project" },
                "commitCount": "6",
                "approvalsRequired": 1,
                "resolvableDiscussionsCount": 9,
                "resolvedDiscussionsCount": 0,
                "mergeStatusEnum": "CAN_BE_MERGED",
                "headPipeline": { "status": "SUCCESS" },
                "reviewers": { "nodes": [] }
              },
              {
                "id": "gid://gitlab/MergeRequest/904",
                "iid": "45",
                "title": "Draft without pipeline",
                "webUrl": "https://gitlab.com/namespace/free-project/-/merge_requests/45",
                "updatedAt": "2026-06-17T07:00:00Z",
                "draft": true,
                "project": { "fullPath": "namespace/free-project" },
                "commitCount": null,
                "approvalsRequired": 0,
                "resolvableDiscussionsCount": 0,
                "resolvedDiscussionsCount": 0,
                "mergeStatusEnum": "CANNOT_BE_MERGED",
                "headPipeline": null,
                "reviewers": { "nodes": [] }
              },
              {
                "id": "gid://gitlab/MergeRequest/905",
                "iid": "46",
                "title": "Bare MR",
                "project": { "fullPath": "namespace/bare-project" },
                "draft": false
              }
            ]
          }
        }
      }
    }
    """.utf8)
}
