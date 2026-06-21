#if DEBUG
    import Foundation

    enum MockError: LocalizedError {
        case requestedFailure

        var errorDescription: String? {
            "Mock provider failure"
        }
    }

    actor MockCodeHostProvider: CodeHostProvider {
        private let behavior: MockBehavior

        init(behavior: MockBehavior) {
            self.behavior = behavior
        }

        func fetchIncomingReviews(
            accessToken _: String,
            viewerLogin _: String,
            mode _: IncomingReviewMode
        ) async throws -> [IncomingReview] {
            try await resolve(\.incoming)
        }

        func fetchOutgoingPullRequests(
            accessToken _: String,
            viewerLogin _: String,
            unresolvedMode _: UnresolvedThreadMode
        ) async throws -> [OutgoingReview] {
            try await resolve(\.outgoing)
        }

        func fetchDraftPullRequests(
            accessToken _: String,
            limit _: Int
        ) async throws -> [DraftReview] {
            try await resolve(\.drafts)
        }

        private func resolve<Value>(_ keyPath: KeyPath<HubberData, Value>) async throws -> Value {
            if Task.isCancelled {
                throw CancellationError()
            }
            switch behavior {
            case let .data(data):
                return data[keyPath: keyPath]
            case .error:
                throw MockError.requestedFailure
            case .loading:
                try await Task.sleep(for: .seconds(60 * 60))
                throw CancellationError()
            }
        }
    }
#endif
