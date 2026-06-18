# M6 Multi-Account — Rail B: PAT Credential Path + Connection Factory + Launch Restore (#61) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> Branch: `feat/m6-multi-account-ui` (off `main`; continues after Rail A). TDD task-by-task; commit per green task. Gate with **`make ci`**; `.githooks/pre-push` runs it on push.

**Goal:** Make a second (non-github-device) account technically addable and restorable: a Personal Access Token sign-in path, a GitLab auth service, a provider/host-aware connection factory, launch-time `restoreAllConnections()`, and the `notifyHiddenAccounts` setting that keeps hidden accounts alerting.

**Architecture:** `GitLabAuthService` conforms to the existing `GitHubDeviceFlowServicing` seam (real `fetchAuthenticatedUser` via GitLab `currentUser`; device-flow/refresh throw "unsupported" because GitLab uses PATs), so `Connection`'s `authService` type is unchanged. `Connection.signIn(withToken:)` validates a PAT via `fetchAuthenticatedUser`, stores a non-refreshable `GitHubStoredToken`, and finishes the session — enforcing `canConnect(host:)` for the connection's host. A `ConnectionFactory` maps a `ConnectionID` (provider+host) to the right `GitHubProvider(baseURL:)`/`GitLabProvider(baseURL:)` + auth service; `HubberStore` uses it for both `addConnection` defaults and `restoreAllConnections()`, which the launch path now calls instead of the legacy single-connection `restoreSession()`.

**Tech Stack:** Swift 6.3, SPM, XCTest, `MockURLProtocol`, Combine.

**Issues:** Refs #61, #80. **Rail B** of the multi-account build (after Rail A, `143690a`). Spec: `docs/superpowers/specs/2026-06-17-m6-multi-account-ui-design.md`. **Phase 2** (account-menu / add-account / Settings UI) is the next plan.

---

## Coordinator decisions (do not relitigate)

1. **No `Connection.authService` type change.** It stays `any GitHubDeviceFlowServicing`. `GitLabAuthService` conforms to that seam; its `startDeviceFlow`/`pollForToken` throw `GitHubAuthError.github("…use a personal access token")`, and `refresh` throws `.missingRefreshToken`. Only `fetchAuthenticatedUser` is real. PAT sign-in never calls the device methods.
2. **PAT = a non-refreshable stored token.** `GitHubStoredToken(accessToken: pat, accessTokenExpiresAt: nil, refreshToken: nil, refreshTokenExpiresAt: nil, tokenType: "bearer", login: resolvedLogin)` → `hasFreshAccessToken == true` forever, `canRefresh == false`. Restore uses it directly; a revoked PAT surfaces as `.badCredentials` on the next fetch (existing session-expired handling).
3. **Reuse `GitHubAuthenticatedUser`** as the resolved-user type for GitLab (`login` ← `currentUser.username`). Reuse `GitHubAuthError`. No new error cases.
4. **Host enforcement:** device sign-in (`startSignIn`) stays github.com-only (`canConnectGitHubDotCom`). PAT sign-in (`signIn(withToken:)`) enforces `settings.providerAccessPolicy.canConnect(host: id.host)` before validating — this is the generalized non-github host gate.
5. **`ConnectionID.host` → `baseURL`** = `URL(string: "https://\(id.host)")!`. The factory builds providers/auth from that. github.com host → `GitHubProvider`/`GitHubAuthService` (device-capable); any other github host (GHES) → same types but only the PAT path is used; gitlab host → `GitLabProvider`/`GitLabAuthService`.
6. **Launch back-compat:** `restoreAllConnections()` with an empty registry still falls back to the legacy single-connection path (existing installs / first run unaffected). Only the launch *call site* changes from `restoreSession()` to `restoreAllConnections()`.
7. **`notifyHiddenAccounts` default true.** When false, `performNotificationPass` diffs only visible connections. Display/badge filtering (Rail A) is unchanged.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/Hubber/GitLab/GitLabAuthService.swift` | `GitHubDeviceFlowServicing` for GitLab: `fetchAuthenticatedUser` via `currentUser`; device/refresh unsupported |
| Modify | `Sources/Hubber/Core/Connection.swift` | `signIn(withToken:)` PAT path (host-policy gate + token build + finish) |
| Create | `Sources/Hubber/Core/ConnectionFactory.swift` | `ConnectionID → (provider, authService)` by provider/host |
| Modify | `Sources/Hubber/GitHubAuth.swift` | `HubberStore` default factory wiring; `restoreAllConnections()` uses it; launch calls it |
| Modify | `Sources/Hubber/main.swift` | launch path triggers multi-connection restore |
| Modify | `Sources/Hubber/Core/SettingsStore.swift` | `notifyHiddenAccounts` flag |
| Modify | `Sources/Hubber/GitHub/HubberStoreNotifications.swift` | notification pass honors `notifyHiddenAccounts` |
| Create | `Tests/HubberTests/GitLabAuthServiceTests.swift` | currentUser → user; PAT 401 → badCredentials; device/refresh throw |
| Create | `Tests/HubberTests/ConnectionFactoryTests.swift` | provider/host routing per `ConnectionID` |
| Modify | `Tests/HubberTests/ConnectionPATSignInTests.swift` (create) | PAT sign-in resolves login + stores non-refreshable token + host gate |
| Modify | `Tests/HubberTests/MultiConnectionNotificationTests.swift` | `notifyHiddenAccounts` gating |

---

## Tasks

### Task 1 — `GitLabAuthService` (TDD)

**Files:**
- Create: `Sources/Hubber/GitLab/GitLabAuthService.swift`
- Test: `Tests/HubberTests/GitLabAuthServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/HubberTests/GitLabAuthServiceTests.swift
import Foundation
import XCTest
@testable import Hubber

final class GitLabAuthServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testFetchAuthenticatedUserMapsCurrentUser() async throws {
        MockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = Data("""
            { "data": { "currentUser": { "username": "osuritz", "name": "Olivier", "avatarUrl": "https://x/a.png" } } }
            """.utf8)
            return (response, body)
        }
        let service = GitLabAuthService(
            baseURL: try XCTUnwrap(URL(string: "https://gitlab.com")),
            session: makeSession()
        )

        let user = try await service.fetchAuthenticatedUser(accessToken: "glpat-x")

        XCTAssertEqual(user.login, "osuritz")
        XCTAssertEqual(user.name, "Olivier")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.absoluteString, "https://gitlab.com/api/graphql")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer glpat-x")
    }

    func testFetchAuthenticatedUserThrowsBadCredentialsOn401() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let service = GitLabAuthService(session: makeSession())
        do {
            _ = try await service.fetchAuthenticatedUser(accessToken: "bad")
            XCTFail("expected badCredentials")
        } catch GitHubAuthError.badCredentials {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testDeviceFlowAndRefreshAreUnsupported() async {
        let service = GitLabAuthService(session: makeSession())
        do { _ = try await service.startDeviceFlow(); XCTFail() } catch { /* expected */ }
        let token = GitHubStoredToken(
            accessToken: "x",
            accessTokenExpiresAt: nil,
            refreshToken: nil,
            refreshTokenExpiresAt: nil,
            tokenType: "bearer",
            login: "osuritz"
        )
        do { _ = try await service.refresh(token); XCTFail() } catch GitHubAuthError.missingRefreshToken {
            // expected
        } catch { XCTFail("wrong error: \(error)") }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter GitLabAuthServiceTests`
Expected: FAIL — `cannot find 'GitLabAuthService' in scope`.

- [ ] **Step 3: Implement**

```swift
// Sources/Hubber/GitLab/GitLabAuthService.swift
import Foundation

/// GitLab authentication over a Personal Access Token. Conforms to the device-flow seam for
/// `Connection` compatibility, but GitLab has no device flow and PATs don't refresh — only
/// `fetchAuthenticatedUser` is real; the rest throw. Reuses `GitLabProvider`'s GraphQL transport.
final class GitLabAuthService: GitHubDeviceFlowServicing, Sendable {
    private let transport: GitLabProvider

    init(baseURL: URL = URL(string: "https://gitlab.com")!, session: URLSession = .shared) {
        transport = GitLabProvider(baseURL: baseURL, session: session)
    }

    func fetchAuthenticatedUser(accessToken: String) async throws -> GitHubAuthenticatedUser {
        let payload = try await transport.graphQL(
            query: Self.currentUserQuery,
            variables: [:],
            accessToken: accessToken
        )
        guard
            let currentUser = payload["currentUser"] as? [String: Any],
            let username = currentUser["username"] as? String
        else { throw GitHubAuthError.invalidResponse }
        return GitHubAuthenticatedUser(
            login: username,
            name: currentUser["name"] as? String,
            avatarUrl: currentUser["avatarUrl"] as? String
        )
    }

    func refresh(_: GitHubStoredToken) async throws -> GitHubStoredToken {
        throw GitHubAuthError.missingRefreshToken
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        throw GitHubAuthError.github("GitLab does not support device sign-in; use a personal access token.")
    }

    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> GitHubStoredToken {
        throw GitHubAuthError.github("GitLab does not support device sign-in; use a personal access token.")
    }

    private static let currentUserQuery = "query { currentUser { username name avatarUrl } }"
}
```

> Note: `GitLabProvider.graphQL` already maps 401→`.badCredentials`, 429→`.rateLimited`, and returns the `data` dict — so the auth service inherits that error handling. `GitHubAuthenticatedUser(login:name:avatarUrl:)` is the synthesized memberwise initializer (no custom init on that struct).

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter GitLabAuthServiceTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/GitLab/GitLabAuthService.swift Tests/HubberTests/GitLabAuthServiceTests.swift
git commit -m "feat(m6): GitLabAuthService — currentUser identity over PAT (#61)"
```

---

### Task 2 — `Connection.signIn(withToken:)` PAT path (TDD)

**Files:**
- Modify: `Sources/Hubber/Core/Connection.swift` (add method after `startSignIn`)
- Test: `Tests/HubberTests/ConnectionPATSignInTests.swift`

- [ ] **Step 1: Write the failing test**

The other test files' stubs are `private` (file-scoped), so this file defines its own minimal doubles. The empty-returning provider + `isIdle: false` keep the post-sign-in scheduler from hanging the bundle-less xctest host (the documented gotcha).

```swift
// Tests/HubberTests/ConnectionPATSignInTests.swift
import Foundation
import XCTest
@testable import Hubber

// MARK: - Local test doubles (other files' doubles are file-private)

private struct PATStubProvider: CodeHostProvider {
    func fetchIncomingReviews(accessToken _: String, viewerLogin _: String, mode _: IncomingReviewMode) async throws -> [IncomingReview] { [] }
    func fetchOutgoingPullRequests(accessToken _: String, viewerLogin _: String, unresolvedMode _: UnresolvedThreadMode) async throws -> [OutgoingReview] { [] }
    func fetchDraftPullRequests(accessToken _: String, limit _: Int) async throws -> [DraftReview] { [] }
}

private struct PATIdleProvider: MachineIdleProviding { let isIdle = false }

private final class PATAuthService: GitHubDeviceFlowServicing, @unchecked Sendable {
    let user: GitHubAuthenticatedUser
    private(set) var fetchUserCallCount = 0
    init(user: GitHubAuthenticatedUser) { self.user = user }
    func fetchAuthenticatedUser(accessToken _: String) async throws -> GitHubAuthenticatedUser {
        fetchUserCallCount += 1
        return user
    }
    func refresh(_: GitHubStoredToken) async throws -> GitHubStoredToken { throw GitHubAuthError.missingRefreshToken }
    func startDeviceFlow() async throws -> GitHubDeviceAuthorization { throw GitHubAuthError.invalidResponse }
    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> GitHubStoredToken { throw GitHubAuthError.invalidResponse }
}

private final class PATTokenStore: GitHubTokenStoring, @unchecked Sendable {
    private var token: GitHubStoredToken?
    func load() throws -> GitHubStoredToken? { token }
    func save(_ token: GitHubStoredToken) throws { self.token = token }
    func delete() throws { token = nil }
}

@MainActor
final class ConnectionPATSignInTests: XCTestCase {
    private func makeConnection(
        id: ConnectionID,
        authService: any GitHubDeviceFlowServicing,
        tokenStore: any GitHubTokenStoring,
        settings: SettingsStore
    ) -> Connection {
        Connection(
            id: id,
            provider: PATStubProvider(),
            authService: authService,
            tokenStore: tokenStore,
            snapshotStore: SnapshotStore(
                snapshotURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            scheduler: RefreshScheduler(idle: PATIdleProvider()),
            settings: settings
        )
    }

    func testPATSignInResolvesLoginAndStoresNonRefreshableToken() async throws {
        let id = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        let store = PATTokenStore()
        let auth = PATAuthService(user: GitHubAuthenticatedUser(login: "osuritz", name: "O", avatarUrl: nil))
        let suite = "PAT-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let conn = makeConnection(id: id, authService: auth, tokenStore: store, settings: settings)

        await conn.signIn(withToken: "glpat-secret")

        XCTAssertEqual(conn.authState, .signedIn(login: "osuritz"))
        let saved = try store.load()
        XCTAssertEqual(saved?.accessToken, "glpat-secret")
        XCTAssertNil(saved?.refreshToken)
        XCTAssertEqual(saved?.login, "osuritz")
    }

    func testPATSignInBlockedByHostPolicy() async throws {
        let id = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        let suite = "PAT-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let managed = InMemoryManagedPreferences([ManagedKey.providerAllowlist: ["github.com"]])
        let settings = SettingsStore(defaults: defaults, managed: managed) // gitlab.com NOT allowed
        let auth = PATAuthService(user: GitHubAuthenticatedUser(login: "osuritz", name: nil, avatarUrl: nil))
        let conn = makeConnection(id: id, authService: auth, tokenStore: PATTokenStore(), settings: settings)

        await conn.signIn(withToken: "glpat-secret")

        guard case .error = conn.authState else { return XCTFail("expected .error, got \(conn.authState)") }
        XCTAssertEqual(auth.fetchUserCallCount, 0) // gate runs BEFORE validation
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ConnectionPATSignInTests`
Expected: FAIL — `value of type 'Connection' has no member 'signIn'`.

- [ ] **Step 3: Implement** — add to `Connection` (after `startSignIn(policy:)`, ~`Connection.swift:133`):

```swift
    /// Token-based sign-in (Personal Access Token) for providers without device flow
    /// (GitLab, GitHub Enterprise, EMU/company github.com accounts). Validates the token by
    /// resolving the authenticated user, stores a non-refreshable token, and starts the session.
    func signIn(withToken token: String) async {
        let policy = settings.providerAccessPolicy
        guard policy.canConnect(host: id.host) else {
            let reason = policy.blockedReason(host: id.host) ?? "Sign-in is restricted by your organization."
            appendDeveloperLog("Token sign-in blocked by policy: \(reason)")
            authState = .error(reason)
            return
        }

        authState = .restoring
        do {
            let user = try await authService.fetchAuthenticatedUser(accessToken: token)
            let stored = GitHubStoredToken(
                accessToken: token,
                accessTokenExpiresAt: nil,
                refreshToken: nil,
                refreshTokenExpiresAt: nil,
                tokenType: "bearer",
                login: user.login
            )
            try await saveStoredToken(stored)
            finishSignedInSession(login: user.login, name: user.name, avatarUrl: user.avatarUrl)
        } catch GitHubAuthError.badCredentials {
            authState = .error("That token was rejected. Check the token and its scopes.")
            appendDeveloperLog("Token sign-in rejected (bad credentials)")
        } catch {
            authState = .error(error.localizedDescription)
            appendDeveloperLog("Token sign-in failed: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter ConnectionPATSignInTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Core/Connection.swift Tests/HubberTests/ConnectionPATSignInTests.swift
git commit -m "feat(m6): Connection.signIn(withToken:) PAT path with host-policy gate (#61)"
```

---

### Task 3 — `ConnectionFactory` (provider/host routing) (TDD)

**Files:**
- Create: `Sources/Hubber/Core/ConnectionFactory.swift`
- Test: `Tests/HubberTests/ConnectionFactoryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/HubberTests/ConnectionFactoryTests.swift
import Foundation
import XCTest
@testable import Hubber

final class ConnectionFactoryTests: XCTestCase {
    func testGitHubDotComRoutesToGitHubProviderAndAuth() {
        let id = ConnectionID.gitHubDotCom(login: "osuritz")
        let built = ConnectionFactory.providerAndAuth(for: id)
        XCTAssertTrue(built.provider is GitHubProvider || built.provider is CachingCodeHostProvider)
        XCTAssertTrue(built.authService is GitHubAuthService)
    }

    func testGHESRoutesToGitHubProviderAtHost() {
        let id = ConnectionID(provider: "github", host: "github.enterprise.acme.com", login: "osuritz")
        let built = ConnectionFactory.providerAndAuth(for: id)
        XCTAssertTrue(built.authService is GitHubAuthService)
        // Routing to the host is covered by ProviderHostRoutingTests; here we assert the type mapping.
    }

    func testGitLabRoutesToGitLabProviderAndAuth() {
        let id = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        let built = ConnectionFactory.providerAndAuth(for: id)
        XCTAssertTrue(built.provider is GitLabProvider || built.provider is CachingCodeHostProvider)
        XCTAssertTrue(built.authService is GitLabAuthService)
    }

    func testBaseURLDerivedFromHost() throws {
        let id = ConnectionID(provider: "gitlab", host: "gitlab.intra.acme.com", login: "x")
        XCTAssertEqual(ConnectionFactory.baseURL(for: id).absoluteString, "https://gitlab.intra.acme.com")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ConnectionFactoryTests`
Expected: FAIL — `cannot find 'ConnectionFactory' in scope`.

- [ ] **Step 3: Implement**

```swift
// Sources/Hubber/Core/ConnectionFactory.swift
import Foundation

/// Maps a `ConnectionID` (provider + host) to the concrete provider + auth service that target
/// that host. github.com / GitHub Enterprise → GitHub types; gitlab → GitLab types. The `baseURL`
/// is derived from the id's host, so the #82/#60 baseURL seams route to the right server.
enum ConnectionFactory {
    static func baseURL(for id: ConnectionID) -> URL {
        URL(string: "https://\(id.host)") ?? URL(string: "https://github.com")!
    }

    static func providerAndAuth(
        for id: ConnectionID,
        session: URLSession = .shared
    ) -> (provider: any CodeHostProvider, authService: any GitHubDeviceFlowServicing) {
        let url = baseURL(for: id)
        switch id.provider {
        case "gitlab":
            return (
                CachingCodeHostProvider(wrapping: GitLabProvider(baseURL: url, session: session)),
                GitLabAuthService(baseURL: url, session: session)
            )
        default: // "github" (github.com + GitHub Enterprise Server)
            return (
                CachingCodeHostProvider(wrapping: GitHubProvider(baseURL: url, session: session)),
                GitHubAuthService(baseURL: url, session: session)
            )
        }
    }
}
```

> Note: `id.provider` is lowercased by `ConnectionID.init`, so the `"gitlab"` match is safe. `CachingCodeHostProvider` is the production wrapper used everywhere else (`GitHubAuth.swift`).

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter ConnectionFactoryTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Core/ConnectionFactory.swift Tests/HubberTests/ConnectionFactoryTests.swift
git commit -m "feat(m6): ConnectionFactory maps ConnectionID to provider+auth by host (#61)"
```

---

### Task 4 — Launch-time `restoreAllConnections()` via the factory (TDD)

**Files:**
- Modify: `Sources/Hubber/GitHubAuth.swift` (`HubberStore` default factory + restore path)
- Modify: `Sources/Hubber/main.swift` (launch call)
- Test: `Tests/HubberTests/MultiConnectionStoreTests.swift`

- [ ] **Step 1: Write the failing test** (add to `MultiConnectionStoreTests`)

```swift
    @MainActor
    func testRestoreAllConnectionsRebuildsGitLabConnectionFromRegistry() throws {
        let suite = "restore-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Pre-register a GitLab connection id.
        let registry = ConnectionRegistry(defaults: defaults)
        let glID = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        try registry.append(glID)

        // Store built with restoreOnInit:false and NO injected factory → uses the default factory.
        let store = HubberStore(defaults: defaults, restoreOnInit: false)
        store.restoreAllConnections()

        let conn = try XCTUnwrap(store.connections.first { $0.id == glID })
        XCTAssertTrue(conn.provider is CachingCodeHostProvider)
        XCTAssertTrue(conn.authService is GitLabAuthService)
    }
```

> Implementer note: `ConnectionRegistry` is the existing id-list persistence (`Sources/Hubber/Core/`); confirm `append`/`load` signatures and `HubberStore(defaults:restoreOnInit:)`'s init labels, matching them exactly.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter MultiConnectionStoreTests/testRestoreAllConnectionsRebuildsGitLabConnectionFromRegistry`
Expected: FAIL — the default (no-factory) restore path builds a GitHub connection (legacy default), so `authService is GitLabAuthService` is false.

- [ ] **Step 3: Give `HubberStore` a default factory**

In `Sources/Hubber/GitHubAuth.swift`, find `restoreAllConnections()`'s multi-connection branch (the `else` that builds `Connection(... provider: legacyProvider, authService: legacyAuthService ...)` when `connectionFactory == nil`). Replace that fallback construction so a `nil` injected factory uses `ConnectionFactory`:

```swift
                } else {
                    let built = ConnectionFactory.providerAndAuth(for: id)
                    conn = Connection(
                        id: id,
                        provider: built.provider,
                        authService: built.authService,
                        tokenStore: GitHubTokenStore.makeStore(for: id),
                        snapshotStore: SnapshotStore(connectionID: id),
                        scheduler: RefreshScheduler(idle: legacyIdle),
                        settings: settings
                    )
                }
```

Apply the same `ConnectionFactory.providerAndAuth(for: id)` default in `addConnection(id:provider:...)` where `resolvedProvider`/`resolvedAuthService` currently default to `GitHubProvider()`/`legacyAuthService`:

```swift
        let factoryBuilt = ConnectionFactory.providerAndAuth(for: id)
        let resolvedProvider = provider ?? factoryBuilt.provider
        let resolvedAuthService = authService ?? factoryBuilt.authService
```

- [ ] **Step 4: Wire the launch call**

In `Sources/Hubber/main.swift`, the store is `private let store = HubberStore()` (`:21`), whose `restoreOnInit: true` calls the legacy `restoreSession()`. Change the launch so multi-connection restore runs. Construct with `restoreOnInit: false` and restore explicitly in `applicationDidFinishLaunching` (where other launch wiring lives):

```swift
    private let store = HubberStore(restoreOnInit: false)
```

and in `applicationDidFinishLaunching(_:)`, after the existing store setup, add:

```swift
        store.restoreAllConnections()
```

> `restoreAllConnections()` already falls back to the legacy single-connection path when the registry is empty (existing installs / first run unaffected).

- [ ] **Step 5: Run tests + check the legacy path still restores**

Run: `swift test --filter MultiConnectionStoreTests` then `swift test --filter HubberStoreRestoreSessionTests`
Expected: PASS — GitLab connection rebuilt with `GitLabAuthService`; legacy single-connection restore unaffected (empty registry → legacy path).

- [ ] **Step 6: Commit**

```bash
git add Sources/Hubber/GitHubAuth.swift Sources/Hubber/main.swift Tests/HubberTests/MultiConnectionStoreTests.swift
git commit -m "feat(m6): launch restores all connections via ConnectionFactory (#61)"
```

---

### Task 5 — `notifyHiddenAccounts` setting + notification gating (TDD)

**Files:**
- Modify: `Sources/Hubber/Core/SettingsStore.swift` (flag)
- Modify: `Sources/Hubber/GitHub/HubberStoreNotifications.swift` (gate the pass)
- Test: `Tests/HubberTests/MultiConnectionNotificationTests.swift`

- [ ] **Step 1: Add the setting (TDD via SettingsStore default test)** — add to `Sources/Hubber/Core/SettingsStore.swift` after `notifyPRMerged`:

```swift
    /// When false, accounts hidden via the visibility toggles do not produce notifications.
    @Published var notifyHiddenAccounts: Bool {
        didSet { defaults.set(notifyHiddenAccounts, forKey: "notifyHiddenAccounts") }
    }
```

In `init` (after `providerAllowlist`/`connectionVisibility` resolution):

```swift
        notifyHiddenAccounts = Self.bool(
            managedKey: "notifyHiddenAccounts",
            defaultsKey: "notifyHiddenAccounts",
            defaults: defaults,
            managed: managed,
            fallback: true
        )
```

- [ ] **Step 2: Write the failing test** (add to `MultiConnectionNotificationTests`)

```swift
    @MainActor
    func testHiddenAccountSuppressedWhenNotifyHiddenAccountsOff() {
        // Two connections' data; hide the second; with notifyHiddenAccounts == false the pass
        // should diff only the visible connection.
        let visibleID = ConnectionID.gitHubDotCom(login: "osuritz")
        let hiddenID = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        let visibility = ConnectionVisibility().setting(hiddenID, visible: false)

        let all: [(id: ConnectionID, data: HubberData)] = [
            (visibleID, HubberData(incoming: [], outgoing: [], drafts: [])),
            (hiddenID, HubberData(incoming: [], outgoing: [], drafts: [])),
        ]

        XCTAssertEqual(HubberStore.notificationConnectionIDs(all, visibility: visibility, notifyHidden: true).count, 2)
        XCTAssertEqual(
            HubberStore.notificationConnectionIDs(all, visibility: visibility, notifyHidden: false),
            [visibleID]
        )
    }
```

- [ ] **Step 3: Implement the gate** — add a pure static helper to `HubberStore` (in `HubberStoreNotifications.swift`) and use it in `performNotificationPass`:

```swift
    /// The connection ids whose data participates in the notification pass. When `notifyHidden`
    /// is false, hidden connections are excluded.
    static func notificationConnectionIDs(
        _ items: [(id: ConnectionID, data: HubberData)],
        visibility: ConnectionVisibility,
        notifyHidden: Bool
    ) -> [ConnectionID] {
        items
            .filter { notifyHidden || visibility.isVisible($0.id) }
            .map(\.id)
    }
```

In `performNotificationPass` (`HubberStoreNotifications.swift:38-39`), filter `connections` first:

```swift
        let notifyHidden = settings.notifyHiddenAccounts
        let participating = connections.filter {
            notifyHidden || settings.connectionVisibility.isVisible($0.id)
        }
        let current = ConnectionAggregator.aggregate(participating.map(\.data))
        let baselinesForDiff = participating.map { connection in
```

> Keep the rest of the pass (baseline write-back of the *refreshed* connection) unchanged — the refreshed connection still advances its own baseline even if hidden, so re-showing it later doesn't replay old notifications.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MultiConnectionNotificationTests` then `swift test --filter SettingsStoreTests`
Expected: PASS — helper filters correctly; default `notifyHiddenAccounts == true` preserves existing notification behavior (all existing notification tests unaffected).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Core/SettingsStore.swift Sources/Hubber/GitHub/HubberStoreNotifications.swift Tests/HubberTests/MultiConnectionNotificationTests.swift
git commit -m "feat(m6): notifyHiddenAccounts gates notifications for hidden accounts (#61)"
```

---

### Task 6 — Full gate

- [ ] **Step 1: Run the gate**

Run: `make ci`
Expected: build + `swift test` green (prior suite + ~13 new tests); swiftlint 0; `swiftformat --lint` clean. If swiftformat flags new files, run `swiftformat .` and re-stage; multi-line init calls in tests must be one-arg-per-line (swiftlint `multiline_arguments`).

---

## Acceptance (whole plan)

- `make ci` green; existing suite unaffected (default `notifyHiddenAccounts == true`; empty registry → legacy restore; github.com defaults unchanged).
- A GitLab/GHES/EMU account is technically addable via `Connection.signIn(withToken:)` (host-policy-gated) and restorable at launch via `ConnectionFactory` + `restoreAllConnections()`.
- `GitLabAuthService` resolves identity via `currentUser`; PAT tokens are non-refreshable; bad PAT → `.error`.
- `notifyHiddenAccounts` (default on) gates notifications for hidden accounts.
- **Deferred to Phase 2:** the account-menu UI, the add-account flow UI (provider picker / PAT form / device-flow "use a token instead"), Settings → Accounts. The visibility toggle UI must route through `HubberStore.setConnectionVisible(_:_:)` (or add a `$connectionVisibility` sink) — see Rail A review note.

## Self-Review Checklist
- [ ] `GitLabAuthService` conforms to `GitHubDeviceFlowServicing`; only `fetchAuthenticatedUser` is real; device/refresh throw; transport reuses `GitLabProvider` (401→badCredentials inherited).
- [ ] `signIn(withToken:)` gates on `canConnect(host: id.host)` BEFORE validating; stores `refreshToken: nil`/`accessTokenExpiresAt: nil`; finishes the session.
- [ ] `ConnectionFactory` routes gitlab→GitLab types, github/GHES→GitHub types, baseURL from host.
- [ ] `restoreAllConnections()` default factory rebuilds the right provider/auth; empty registry still hits the legacy path; launch calls it once.
- [ ] `notifyHiddenAccounts` default true → no behavior change; off → hidden connections excluded from the pass; refreshed connection still advances its baseline.
- [ ] Names consistent: `GitLabAuthService`, `signIn(withToken:)`, `ConnectionFactory.providerAndAuth(for:)`, `baseURL(for:)`, `notifyHiddenAccounts`, `notificationConnectionIDs`.
