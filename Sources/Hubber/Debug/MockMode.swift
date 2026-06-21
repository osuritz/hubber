#if DEBUG
    import Combine
    import Foundation

    @MainActor
    final class MockMode: ObservableObject {
        static let shared = MockMode()

        @Published var scenario: MockScenario

        var isActive: Bool {
            scenario != .off
        }

        private var seededIDs = Set<ConnectionID>()
        private var applyTask: Task<Void, Never>?

        private init(environment: [String: String] = ProcessInfo.processInfo.environment) {
            scenario = MockScenario(env: environment["HUBBER_MOCK"]) ?? .off
        }

        func apply(_ scenario: MockScenario, to store: HubberStore) {
            if self.scenario != scenario {
                self.scenario = scenario
            }

            // Persist onboarding completion synchronously — before the popover's lazily
            // created @StateObject coordinator reads the flag — so an active mock scenario
            // reliably lands on the populated popover rather than the onboarding flow.
            if scenario != .off {
                OnboardingCoordinator().complete()
            }

            applyTask?.cancel()
            let idsToRemove = Set(seededIDs).union(MockScenario.allMockConnectionIDs)
            applyTask = Task { @MainActor in
                for id in idsToRemove {
                    guard !Task.isCancelled else { return }
                    await store.removeConnection(id)
                }
                seededIDs.removeAll()

                guard scenario != .off else {
                    store.restoreAllConnections()
                    return
                }

                for plan in scenario.connectionPlan {
                    guard !Task.isCancelled else { return }
                    do {
                        let connection = try store.addConnection(
                            id: plan.id,
                            provider: MockCodeHostProvider(behavior: plan.behavior),
                            authService: MockAuthService(login: plan.login),
                            tokenStore: MockTokenStore(token: Self.token(login: plan.login)),
                            snapshotStore: SnapshotStore(snapshotURL: Self.snapshotURL(for: plan.id)),
                            scheduler: RefreshScheduler(idle: MockIdleProvider())
                        )
                        try? ConnectionRegistry().remove(plan.id)
                        store.setConnectionVisible(plan.id, true)
                        await connection.adopt(
                            token: Self.token(login: plan.login),
                            user: AuthenticatedUser(login: plan.login, name: plan.login, avatarUrl: nil)
                        )
                        seededIDs.insert(plan.id)
                    } catch {
                        store.appendDeveloperLog("Mock seed failed for @\(plan.login): \(error.localizedDescription)")
                    }
                }
            }
        }

        private static func token(login: String) -> StoredToken {
            StoredToken(
                accessToken: "mock-token-\(login)",
                accessTokenExpiresAt: nil,
                refreshToken: nil,
                refreshTokenExpiresAt: nil,
                tokenType: "bearer",
                login: login
            )
        }

        private static func snapshotURL(for id: ConnectionID) -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("hubber-debug-mock-\(id.slug)-snapshot.json")
        }
    }

    private actor MockAuthService: GitHubDeviceFlowServicing {
        private let login: String

        init(login: String) {
            self.login = login
        }

        func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
            GitHubDeviceAuthorization(
                deviceCode: "mock-device-\(login)",
                userCode: "MOCK-\(login)",
                verificationURI: URL(string: "https://github.com/login/device")!,
                expiresAt: Date().addingTimeInterval(600),
                interval: 1
            )
        }

        func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> StoredToken {
            StoredToken(
                accessToken: "mock-token-\(login)",
                accessTokenExpiresAt: nil,
                refreshToken: nil,
                refreshTokenExpiresAt: nil,
                tokenType: "bearer",
                login: login
            )
        }

        func refresh(_ token: StoredToken) async throws -> StoredToken {
            token
        }

        func fetchAuthenticatedUser(accessToken _: String) async throws -> AuthenticatedUser {
            AuthenticatedUser(login: login, name: login, avatarUrl: nil)
        }
    }

    private final class MockTokenStore: TokenStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var token: StoredToken?

        init(token: StoredToken?) {
            self.token = token
        }

        func load() throws -> StoredToken? {
            lock.withLock { token }
        }

        func save(_ token: StoredToken) throws {
            lock.withLock { self.token = token }
        }

        func delete() throws {
            lock.withLock { token = nil }
        }
    }

    private struct MockIdleProvider: MachineIdleProviding {
        let isIdle = false
    }
#endif
