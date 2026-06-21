#if DEBUG
    import Foundation
    import Testing
    @testable import Hubber

    @Suite("Debug mock mode")
    struct MockScenarioTests {
        @Test("Environment strings map to scenarios")
        func environmentMapping() {
            #expect(MockScenario(env: nil) == .off)
            #expect(MockScenario(env: "") == .off)
            #expect(MockScenario(env: "unknown") == .off)
            #expect(MockScenario(env: "off") == .off)
            #expect(MockScenario(env: "empty") == .empty)
            #expect(MockScenario(env: "small") == .small)
            #expect(MockScenario(env: "large") == .large)
            #expect(MockScenario(env: "error") == .error)
            #expect(MockScenario(env: "loading") == .loading)
            #expect(MockScenario(env: "multiConnection") == .multiConnection)
            #expect(MockScenario(env: "multi-connection") == .multiConnection)
        }

        @Test("Connection plan counts match scenario shape")
        func connectionPlanCounts() {
            #expect(MockScenario.off.connectionPlan.isEmpty)
            #expect(MockScenario.empty.connectionPlan.count == 1)
            #expect(MockScenario.small.connectionPlan.count == 1)
            #expect(MockScenario.large.connectionPlan.count == 1)
            #expect(MockScenario.error.connectionPlan.count == 1)
            #expect(MockScenario.loading.connectionPlan.count == 1)
            #expect(MockScenario.multiConnection.connectionPlan.count == 2)
        }

        @Test("Generated data shapes match scenarios")
        func generatedDataShapes() throws {
            let empty = try data(for: .empty)
            #expect(empty.incoming.isEmpty)
            #expect(empty.outgoing.isEmpty)
            #expect(empty.drafts.isEmpty)

            let small = try data(for: .small)
            #expect((1...5).contains(small.incoming.count))
            #expect((1...5).contains(small.outgoing.count))
            #expect((1...3).contains(small.drafts.count))

            let large = try data(for: .large)
            #expect(large.incoming.count >= 20)
            #expect(large.outgoing.count >= 20)
            #expect(large.drafts.count >= 10)
        }

        @Test("Multi-connection scenario has one overlapping PR id")
        func multiConnectionOverlap() throws {
            let plan = MockScenario.multiConnection.connectionPlan
            #expect(plan.count == 2)

            let first = try data(from: plan[0]).outgoing.map(\.id)
            let second = try data(from: plan[1]).outgoing.map(\.id)
            let overlap = Set(first).intersection(second)

            #expect(overlap == [MockScenario.overlappingPullRequestID])
        }

        @Test("Mock provider returns configured data slices")
        func providerDataReturnsConfiguredSlices() async throws {
            let data = HubberData(
                incoming: [incoming(id: "incoming")],
                outgoing: [outgoing(id: "outgoing")],
                drafts: [draft(id: "draft")]
            )
            let provider = MockCodeHostProvider(behavior: .data(data))

            let incoming = try await provider.fetchIncomingReviews(
                accessToken: "token",
                viewerLogin: "viewer",
                mode: .explicit
            )
            let outgoing = try await provider.fetchOutgoingPullRequests(
                accessToken: "token",
                viewerLogin: "viewer",
                unresolvedMode: .allOpen
            )
            let drafts = try await provider.fetchDraftPullRequests(accessToken: "token", limit: 100)

            #expect(incoming.map(\.id) == ["incoming"])
            #expect(outgoing.map(\.id) == ["outgoing"])
            #expect(drafts.map(\.id) == ["draft"])
        }

        @Test("Mock provider error behavior throws")
        func providerErrorThrows() async {
            let provider = MockCodeHostProvider(behavior: .error)
            var didThrow = false

            do {
                _ = try await provider.fetchIncomingReviews(
                    accessToken: "token",
                    viewerLogin: "viewer",
                    mode: .explicit
                )
            } catch {
                didThrow = true
                #expect(error is MockError)
            }

            #expect(didThrow)
        }

        private func data(for scenario: MockScenario) throws -> HubberData {
            let plan = scenario.connectionPlan
            #expect(plan.count == 1)
            return try data(from: plan[0])
        }

        private func data(from plan: MockConnectionPlan) throws -> HubberData {
            switch plan.behavior {
            case let .data(data):
                return data
            case .error, .loading:
                throw TestFailure("Expected data behavior")
            }
        }

        private func incoming(id: String) -> IncomingReview {
            IncomingReview(
                id: id,
                repo: "acme/repo",
                number: 1,
                title: "Review",
                url: nil,
                author: .marisol,
                sloClockStart: .hoursAgo(1),
                additions: 1,
                deletions: 1,
                files: 1
            )
        }

        private func outgoing(id: String) -> OutgoingReview {
            OutgoingReview(
                id: id,
                repo: "acme/repo",
                number: 2,
                title: "Outgoing",
                url: nil,
                ci: .passing,
                ciDetail: "passing",
                unresolved: 0,
                approvals: 1,
                requiredApprovals: 1,
                reviewers: [Reviewer(user: .tobi, state: .approved)],
                updatedAgoHours: 1,
                mergeable: true
            )
        }

        private func draft(id: String) -> DraftReview {
            DraftReview(
                id: id,
                repo: "acme/repo",
                number: 3,
                title: "Draft",
                url: nil,
                ci: .pending,
                ciDetail: "pending",
                commits: 1,
                updatedAt: .hoursAgo(1)
            )
        }
    }

    private struct TestFailure: Error, CustomStringConvertible {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }
#endif
