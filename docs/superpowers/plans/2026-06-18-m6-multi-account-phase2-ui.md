# M6 Multi-Account — Phase 2: Account Menu + Add-Account Flow + Settings → Accounts (#61) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> Branch: `feat/m6-multi-account-ui` (continues after Rail A `143690a` + Rail B `776bddb…d65390d`). TDD task-by-task; commit per green task. Gate with **`make ci`**; `.githooks/pre-push` runs it on push.

**Goal:** Turn the multi-connection plumbing (Rail A visibility + Rail B PAT/factory/restore) into the real user-facing multi-account experience: an account toggle menu in the popover header, an add-account flow (provider picker → github.com device-flow *or* host+PAT), Settings → Accounts management (sign out / remove / re-authenticate / add), and empty-state routing.

**Architecture:** Identity resolution is decoupled from connection materialization so the network logic is unit-testable without spinning a real `RefreshScheduler`. A new `AddAccountController` (`ObservableObject`) drives the add flow: it gates `canConnect(host:)`, runs github.com device-flow *or* validates a PAT, resolves the `login` via `fetchAuthenticatedUser`, then hands a fully-resolved `(ConnectionID, GitHubStoredToken, GitHubAuthenticatedUser)` to `HubberStore.addResolvedAccount(...)`, which calls the existing `addConnection(...)` and a new `Connection.adopt(token:user:)` (stores the pre-validated token — preserving a device-flow refresh token — and finishes the session). The header's static label is replaced by `AccountMenuView`; Settings' single `GitHubAuthSettingsView` is replaced by `AccountsSettingsSection`. No item-model changes (locked decision #3).

**Tech Stack:** Swift 6.3, SPM, XCTest, `MockURLProtocol`, Combine, SwiftUI/AppKit.

**Issues:** Refs #61, #80. **Phase 2** of the multi-account build. Spec: `docs/superpowers/specs/2026-06-17-m6-multi-account-ui-design.md` (locked decisions). Phase 1 backend = Rail A (`143690a`) + Rail B (`776bddb…d65390d`). **Phase 3** = manual GitLab E2E + EMU-via-PAT verification (needs the user's PAT).

## Global Constraints

- Swift 6.3 / SPM / XCTest; UI + store are `@MainActor`. (copied from repo conventions)
- **No item-model changes** — `IncomingReview`/`OutgoingReview`/`DraftReview` are untouched (locked decision #3; merged rows carry no per-account tag in v1).
- **Reuse existing components**: `SettingsSection`/`SettingsGroup`/`SettingsRow` (`HubberSettingsView.swift`), `AvatarView` + `AvatarSize` (`HubberAvatarView.swift`), `SignInButtonStyle` + `DeviceCodeScreen` (`SignInScreen.swift`), `HubberDesign`/`HubberType` tokens. Do not reinvent chrome.
- **Reuse shared types**: `GitHubAuthenticatedUser(login:name:avatarUrl:)`, `GitHubStoredToken`, `GitHubAuthError`, `GitHubDeviceAuthorization`. No new error cases.
- **Scheduler-hang gotcha:** any test that signs a connection in / calls `adopt`/`finishSignedInSession`/`refreshNow` starts a real `RefreshScheduler`; inject a stub `CodeHostProvider` returning `[]` + a `MachineIdleProviding` stub with `isIdle = false`. Real `GitHubProvider`→network and `UNUserNotificationCenter` hang the bundle-less xctest host. A `swift test` running >~30s is HUNG — kill + re-run with `--filter`.
- **swiftlint `multiline_arguments`:** multi-line init/function calls in tests are one-arg-per-line. **swiftformat:** `--commas always` (trailing commas in collection literals); `redundantSendable` strips explicit `Sendable` from non-public types — let it.
- **No `Co-Authored-By` trailers** (project rule). Commits reference `(#61)`.
- `#5` (reviewer-state merge determinism) was already fixed in Rail A — **not** in scope here.

## Coordinator decisions (do not relitigate)

1. **Device flow is supported in the add picker** (spec decision #8, user-confirmed 2026-06-18). New github.com accounts run device flow via `AddAccountController`, which resolves the login *before* forming the `ConnectionID`, then materializes the connection via `addResolvedAccount` adopting the **device-flow token with its refresh token intact**. (PAT tokens are non-refreshable, per Rail B.)
2. **Identity resolution ⟂ materialization.** `AddAccountController` only does auth + resolve (unit-testable with `MockURLProtocol`, no `Connection`). Materialization (`addConnection` + `adopt`) lives on `HubberStore` and is tested separately with stub provider/idle. The controller takes an injected `addAccount` closure so its tests never start a scheduler.
3. **Re-auth reuses existing seams.** PAT accounts re-auth via the existing `Connection.signIn(withToken:)` (Rail B). Device-flow (github.com) accounts re-auth via the existing `Connection.startSignIn(policy:)` (which targets *that* connection and stores under its own id — login already known, no rekey needed).
4. **Host gate before auth.** `canConnect(host:)` is enforced in `AddAccountController` *before* any `startDeviceFlow`/`fetchAuthenticatedUser`; a blocked host shows `blockedReason(host:)`.
5. **Dedup by `ConnectionID`.** If the resolved id already exists in `connections`, the add fails with "This account is already added." (No silent no-op, no duplicate registry entry.)
6. **Visibility toggles route through `store.setConnectionVisible(_:_:)`** (exists, `GitHubAuth.swift:683`) — satisfies the Rail A review note. Badge already reflects visibility (Rail A `recomputeAggregate`), so no badge work.
7. **Provider picker = 3 kinds** (`AddAccountProvider`): `.gitHubDotCom` (device flow + "use a token instead"), `.gitHubEnterprise` (server URL + PAT), `.gitLab` (server URL default `https://gitlab.com` + PAT). github.com and GHES both map to `provider == "github"`; gitlab → `"gitlab"`.

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Modify | `Sources/Hubber/Core/ConnectionFactory.swift` | `authService(provider:host:session:)` — build an auth service pre-login (identity resolution) |
| Modify | `Sources/Hubber/Core/ConnectionID.swift` | `providerDisplayName` (GitHub / GitHub Enterprise / GitLab) for header + Settings labels |
| Modify | `Sources/Hubber/Core/Connection.swift` | `adopt(token:user:)` — store a pre-validated token + finish session |
| Modify | `Sources/Hubber/GitHubAuth.swift` | `addResolvedAccount(id:token:user:)` — `addConnection` + `adopt` + dedup |
| Create | `Sources/Hubber/AddAccount/AddAccountController.swift` | `ObservableObject` add-account state machine (gate → device/PAT → resolve → materialize) |
| Create | `Sources/Hubber/AddAccount/AddAccountView.swift` | provider picker → device-flow / host+PAT form (binds the controller) |
| Create | `Sources/Hubber/Account/AccountHeaderLabel.swift` | pure header-label logic (decision #5) |
| Create | `Sources/Hubber/Account/AccountMenuView.swift` | header toggle menu (All accounts + per-account checkbox + ⚠) |
| Create | `Sources/Hubber/Settings/AccountsSettingsSection.swift` | Settings list (sign out / remove / re-auth / add) + "Notify for hidden accounts" |
| Modify | `Sources/Hubber/HubberPopoverView.swift` | header seam → `AccountMenuView`; empty-state → add-account routing |
| Modify | `Sources/Hubber/HubberSettingsView.swift` | "GitHub Account" section → `AccountsSettingsSection` |
| Create | `Tests/HubberTests/ConnectionFactoryAuthServiceTests.swift` | factory auth-service routing |
| Create | `Tests/HubberTests/ConnectionAdoptTests.swift` | adopt stores token + finishes session; refresh token preserved |
| Create | `Tests/HubberTests/AddResolvedAccountTests.swift` | store materialization + dedup |
| Create | `Tests/HubberTests/AddAccountControllerTests.swift` | gate / PAT 401 / PAT success / device-flow happy path |
| Create | `Tests/HubberTests/AccountHeaderLabelTests.swift` | header-label decision #5 |

---

## Tasks

### Task 1 — `ConnectionFactory.authService(provider:host:)` + `ConnectionID.providerDisplayName` (TDD)

**Files:**
- Modify: `Sources/Hubber/Core/ConnectionFactory.swift`, `Sources/Hubber/Core/ConnectionID.swift`
- Test: `Tests/HubberTests/ConnectionFactoryAuthServiceTests.swift`

**Interfaces:**
- Produces: `ConnectionFactory.authService(provider: String, host: String, session: URLSession = .shared) -> any GitHubDeviceFlowServicing`; `ConnectionID.providerDisplayName: String`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/HubberTests/ConnectionFactoryAuthServiceTests.swift
import Foundation
import XCTest
@testable import Hubber

final class ConnectionFactoryAuthServiceTests: XCTestCase {
    func testGitHubHostBuildsGitHubAuthService() {
        let svc = ConnectionFactory.authService(provider: "github", host: "github.com")
        XCTAssertTrue(svc is GitHubAuthService)
    }

    func testGitLabHostBuildsGitLabAuthService() {
        let svc = ConnectionFactory.authService(provider: "gitlab", host: "gitlab.com")
        XCTAssertTrue(svc is GitLabAuthService)
    }

    func testProviderDisplayName() {
        XCTAssertEqual(ConnectionID.gitHubDotCom(login: "o").providerDisplayName, "GitHub")
        XCTAssertEqual(ConnectionID(provider: "github", host: "ghe.acme.com", login: "o").providerDisplayName, "GitHub Enterprise")
        XCTAssertEqual(ConnectionID(provider: "gitlab", host: "gitlab.com", login: "o").providerDisplayName, "GitLab")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ConnectionFactoryAuthServiceTests`
Expected: FAIL — `type 'ConnectionFactory' has no member 'authService'` / `no member 'providerDisplayName'`.

- [ ] **Step 3: Implement**

Add to `ConnectionFactory` (reuse the existing `baseURL(for:)`; build only the auth service):

```swift
    /// Builds an auth service for a provider+host BEFORE a login is known (identity resolution
    /// during add-account). Mirrors `providerAndAuth(for:)`'s auth half.
    static func authService(
        provider: String,
        host: String,
        session: URLSession = .shared
    ) -> any GitHubDeviceFlowServicing {
        let url = URL(string: "https://\(host)") ?? URL(string: "https://github.com")!
        switch provider.lowercased() {
        case "gitlab":
            return GitLabAuthService(baseURL: url, session: session)
        default:
            return GitHubAuthService(baseURL: url, session: session)
        }
    }
```

Add to `ConnectionID` (after `slug`):

```swift
    /// Human label for the header / Settings: "GitHub", "GitHub Enterprise", or "GitLab".
    var providerDisplayName: String {
        switch provider {
        case "gitlab": return "GitLab"
        case "github": return host == "github.com" ? "GitHub" : "GitHub Enterprise"
        default: return provider.capitalized
        }
    }
```

> Note: `GitHubAuthService(baseURL:session:)` and `GitLabAuthService(baseURL:session:)` both exist (#82, Rail B). `id.provider`/`host` are already lowercased by `ConnectionID.init`.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter ConnectionFactoryAuthServiceTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Core/ConnectionFactory.swift Sources/Hubber/Core/ConnectionID.swift Tests/HubberTests/ConnectionFactoryAuthServiceTests.swift
git commit -m "feat(m6): ConnectionFactory.authService + ConnectionID.providerDisplayName (#61)"
```

---

### Task 2 — `Connection.adopt(token:user:)` (TDD)

**Files:**
- Modify: `Sources/Hubber/Core/Connection.swift` (add after `signIn(withToken:)`)
- Test: `Tests/HubberTests/ConnectionAdoptTests.swift`

**Interfaces:**
- Produces: `func adopt(token: GitHubStoredToken, user: GitHubAuthenticatedUser) async` on `Connection`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/HubberTests/ConnectionAdoptTests.swift
import Foundation
import XCTest
@testable import Hubber

private struct AdoptStubProvider: CodeHostProvider {
    func fetchIncomingReviews(accessToken _: String, viewerLogin _: String, mode _: IncomingReviewMode) async throws -> [IncomingReview] { [] }
    func fetchOutgoingPullRequests(accessToken _: String, viewerLogin _: String, unresolvedMode _: UnresolvedThreadMode) async throws -> [OutgoingReview] { [] }
    func fetchDraftPullRequests(accessToken _: String, limit _: Int) async throws -> [DraftReview] { [] }
}

private struct AdoptIdleProvider: MachineIdleProviding { let isIdle = false }

private final class AdoptTokenStore: GitHubTokenStoring, @unchecked Sendable {
    private var token: GitHubStoredToken?
    func load() throws -> GitHubStoredToken? { token }
    func save(_ token: GitHubStoredToken) throws { self.token = token }
    func delete() throws { token = nil }
}

private final class AdoptAuthService: GitHubDeviceFlowServicing, @unchecked Sendable {
    func fetchAuthenticatedUser(accessToken _: String) async throws -> GitHubAuthenticatedUser {
        GitHubAuthenticatedUser(login: "x", name: nil, avatarUrl: nil)
    }
    func refresh(_: GitHubStoredToken) async throws -> GitHubStoredToken { throw GitHubAuthError.missingRefreshToken }
    func startDeviceFlow() async throws -> GitHubDeviceAuthorization { throw GitHubAuthError.invalidResponse }
    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> GitHubStoredToken { throw GitHubAuthError.invalidResponse }
}

@MainActor
final class ConnectionAdoptTests: XCTestCase {
    private func makeConnection(id: ConnectionID, store: any GitHubTokenStoring, settings: SettingsStore) -> Connection {
        Connection(
            id: id,
            provider: AdoptStubProvider(),
            authService: AdoptAuthService(),
            tokenStore: store,
            snapshotStore: SnapshotStore(
                snapshotURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            scheduler: RefreshScheduler(idle: AdoptIdleProvider()),
            settings: settings
        )
    }

    func testAdoptStoresTokenAndFinishesSession() async throws {
        let suite = "adopt-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let store = AdoptTokenStore()
        let conn = makeConnection(id: .gitHubDotCom(login: "osuritz"), store: store, settings: settings)

        let token = GitHubStoredToken(
            accessToken: "gho_x",
            accessTokenExpiresAt: nil,
            refreshToken: "ghr_refresh",
            refreshTokenExpiresAt: nil,
            tokenType: "bearer",
            login: "osuritz"
        )
        await conn.adopt(token: token, user: GitHubAuthenticatedUser(login: "osuritz", name: "O", avatarUrl: nil))

        XCTAssertEqual(conn.authState, .signedIn(login: "osuritz"))
        XCTAssertEqual(conn.viewerName, "O")
        let saved = try store.load()
        XCTAssertEqual(saved?.accessToken, "gho_x")
        XCTAssertEqual(saved?.refreshToken, "ghr_refresh") // device-flow refresh token preserved
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ConnectionAdoptTests`
Expected: FAIL — `value of type 'Connection' has no member 'adopt'`.

- [ ] **Step 3: Implement** — add to `Connection` (after `signIn(withToken:)`, ~`Connection.swift:167`):

```swift
    /// Adopts an already-validated token + resolved user from an external auth flow (multi-account
    /// add, where the login was resolved before this Connection existed). Stores the token AS-IS —
    /// preserving a device-flow refresh token — and finishes the session WITHOUT re-fetching.
    func adopt(token: GitHubStoredToken, user: GitHubAuthenticatedUser) async {
        authState = .restoring
        do {
            try await saveStoredToken(token)
            finishSignedInSession(login: user.login, name: user.name, avatarUrl: user.avatarUrl)
        } catch {
            authState = .error(error.localizedDescription)
            appendDeveloperLog("Adopt token failed: \(error.localizedDescription)")
        }
    }
```

> Note: `saveStoredToken`/`finishSignedInSession` are private to `Connection` — that's why `adopt` lives in this file. `finishSignedInSession` starts the refresh loop (hence the stub provider + `isIdle:false` in the test).

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter ConnectionAdoptTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Core/Connection.swift Tests/HubberTests/ConnectionAdoptTests.swift
git commit -m "feat(m6): Connection.adopt(token:user:) for external-flow sign-in (#61)"
```

---

### Task 3 — `HubberStore.addResolvedAccount(id:token:user:)` (TDD)

**Files:**
- Modify: `Sources/Hubber/GitHubAuth.swift` (add near `addConnection`)
- Test: `Tests/HubberTests/AddResolvedAccountTests.swift`

**Interfaces:**
- Consumes: `addConnection(id:)` (Task uses the factory defaults), `Connection.adopt(token:user:)` (Task 2).
- Produces: `func addResolvedAccount(id: ConnectionID, token: GitHubStoredToken, user: GitHubAuthenticatedUser) async throws -> Connection`; `enum AddAccountError: Error { case alreadyAdded }`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/HubberTests/AddResolvedAccountTests.swift
import Foundation
import XCTest
@testable import Hubber

@MainActor
final class AddResolvedAccountTests: XCTestCase {
    private func makeStore(_ defaults: UserDefaults) -> HubberStore {
        // restoreOnInit:false → no legacy connection; factory-built connections only.
        HubberStore(defaults: defaults, restoreOnInit: false)
    }

    func testAddResolvedAccountMaterializesGitLabConnection() async throws {
        let suite = "ara-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults)

        let id = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        let token = GitHubStoredToken(accessToken: "glpat", accessTokenExpiresAt: nil, refreshToken: nil, refreshTokenExpiresAt: nil, tokenType: "bearer", login: "osuritz")
        let conn = try await store.addResolvedAccount(id: id, token: token, user: GitHubAuthenticatedUser(login: "osuritz", name: nil, avatarUrl: nil))

        XCTAssertEqual(conn.authState, .signedIn(login: "osuritz"))
        XCTAssertTrue(store.connections.contains { $0.id == id })
        XCTAssertTrue(conn.authService is GitLabAuthService)
    }

    func testAddResolvedAccountRejectsDuplicate() async throws {
        let suite = "ara-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults)
        let id = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        let token = GitHubStoredToken(accessToken: "glpat", accessTokenExpiresAt: nil, refreshToken: nil, refreshTokenExpiresAt: nil, tokenType: "bearer", login: "osuritz")
        let user = GitHubAuthenticatedUser(login: "osuritz", name: nil, avatarUrl: nil)
        _ = try await store.addResolvedAccount(id: id, token: token, user: user)

        do {
            _ = try await store.addResolvedAccount(id: id, token: token, user: user)
            XCTFail("expected alreadyAdded")
        } catch HubberStore.AddAccountError.alreadyAdded {
            // expected
        }
    }
}
```

> Note: a GitLab `ConnectionID` makes the factory build a `GitLabProvider` (no network on construction). `adopt` starts the scheduler; GitLab provider's `fetchIncoming…` would network, but with `isIdle` from the store's default `SystemIdleProvider` the refresh loop parks until idle — if this test ever hangs, inject a stub via the existing `connectionFactory` parameter returning a `Connection` with a stub provider + `isIdle:false`. Run with `--filter` and the 30s rule.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AddResolvedAccountTests`
Expected: FAIL — `no member 'addResolvedAccount'`.

- [ ] **Step 3: Implement** — add to `HubberStore` (near `addConnection`, `GitHubAuth.swift:~513`):

```swift
    enum AddAccountError: Error { case alreadyAdded }

    /// Materializes an account whose identity was already resolved by an external auth flow
    /// (`AddAccountController`): builds the factory-routed connection, adopts the validated token,
    /// and registers it. Rejects a duplicate `ConnectionID`.
    @discardableResult
    func addResolvedAccount(
        id: ConnectionID,
        token: GitHubStoredToken,
        user: GitHubAuthenticatedUser
    ) async throws -> Connection {
        guard !connections.contains(where: { $0.id == id }) else {
            throw AddAccountError.alreadyAdded
        }
        let conn = try addConnection(id: id)   // factory-built provider/auth + keyed token store + registry append
        await conn.adopt(token: token, user: user)
        return conn
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter AddResolvedAccountTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/GitHubAuth.swift Tests/HubberTests/AddResolvedAccountTests.swift
git commit -m "feat(m6): HubberStore.addResolvedAccount materializes + dedups accounts (#61)"
```

---

### Task 4 — `AddAccountController` (TDD)

**Files:**
- Create: `Sources/Hubber/AddAccount/AddAccountController.swift`
- Test: `Tests/HubberTests/AddAccountControllerTests.swift`

**Interfaces:**
- Consumes: `ConnectionFactory.authService(provider:host:)` (Task 1), `ProviderAccessPolicy.canConnect(host:)`/`blockedReason(host:)`, an injected `addAccount` closure (in production → `store.addResolvedAccount`).
- Produces: `enum AddAccountProvider`, `AddAccountController` with `@Published var stage: Stage`, `func connectWithToken(...) async`, `func beginDeviceFlow() async`, `func cancel()`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/HubberTests/AddAccountControllerTests.swift
import Foundation
import XCTest
@testable import Hubber

private final class FakeAuthService: GitHubDeviceFlowServicing, @unchecked Sendable {
    var userResult: Result<GitHubAuthenticatedUser, Error> = .success(GitHubAuthenticatedUser(login: "osuritz", name: "O", avatarUrl: nil))
    var deviceAuth = GitHubDeviceAuthorization(deviceCode: "d", userCode: "ABCD-1234", verificationUri: "https://github.com/login/device", expiresIn: 900, interval: 1)
    var pollToken = GitHubStoredToken(accessToken: "gho_x", accessTokenExpiresAt: nil, refreshToken: "ghr", refreshTokenExpiresAt: nil, tokenType: "bearer", login: nil)
    private(set) var fetchCount = 0

    func fetchAuthenticatedUser(accessToken _: String) async throws -> GitHubAuthenticatedUser {
        fetchCount += 1
        return try userResult.get()
    }
    func refresh(_: GitHubStoredToken) async throws -> GitHubStoredToken { throw GitHubAuthError.missingRefreshToken }
    func startDeviceFlow() async throws -> GitHubDeviceAuthorization { deviceAuth }
    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> GitHubStoredToken { pollToken }
}

@MainActor
final class AddAccountControllerTests: XCTestCase {
    private func make(
        auth: FakeAuthService = FakeAuthService(),
        policy: ProviderAccessPolicy = ProviderAccessPolicy(allowlist: nil),
        onAdd: @escaping (ConnectionID, GitHubStoredToken, GitHubAuthenticatedUser) async throws -> Void = { _, _, _ in }
    ) -> AddAccountController {
        AddAccountController(
            policy: policy,
            authServiceFactory: { _, _ in auth },
            addAccount: onAdd
        )
    }

    func testTokenSignInResolvesLoginAndAdds() async throws {
        var added: ConnectionID?
        let c = make(onAdd: { id, token, _ in
            added = id
            XCTAssertNil(token.refreshToken)            // PAT → non-refreshable
            XCTAssertEqual(token.accessToken, "glpat")
        })
        await c.connectWithToken(provider: .gitLab, serverURL: "https://gitlab.com", token: "glpat")
        XCTAssertEqual(added, ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz"))
        guard case .added = c.stage else { return XCTFail("expected .added, got \(c.stage)") }
    }

    func testBadTokenSurfacesError() async {
        let auth = FakeAuthService(); auth.userResult = .failure(GitHubAuthError.badCredentials)
        let c = make(auth: auth)
        await c.connectWithToken(provider: .gitLab, serverURL: "https://gitlab.com", token: "bad")
        guard case .failed = c.stage else { return XCTFail("expected .failed") }
    }

    func testBlockedHostFailsBeforeFetch() async {
        let auth = FakeAuthService()
        let policy = ProviderAccessPolicy(allowlist: ["github.com"]) // gitlab.com NOT allowed
        let c = make(auth: auth, policy: policy)
        await c.connectWithToken(provider: .gitLab, serverURL: "https://gitlab.com", token: "x")
        guard case .failed = c.stage else { return XCTFail("expected .failed") }
        XCTAssertEqual(auth.fetchCount, 0) // gate before validation
    }

    func testDeviceFlowHappyPath() async {
        var added: ConnectionID?
        let c = make(onAdd: { id, token, _ in
            added = id
            XCTAssertEqual(token.refreshToken, "ghr") // device-flow refresh token preserved
            XCTAssertEqual(token.login, "osuritz")
        })
        await c.beginDeviceFlow()
        XCTAssertEqual(added, ConnectionID.gitHubDotCom(login: "osuritz"))
        guard case .added = c.stage else { return XCTFail("expected .added, got \(c.stage)") }
    }
}
```

> Implementer note: confirm the real `ProviderAccessPolicy` initializer label (the codebase builds it from the settings allowlist — match its actual `init`; the test's `ProviderAccessPolicy(allowlist:)` is illustrative). Confirm `GitHubDeviceAuthorization`'s member labels (`userCode`, `verificationUri`, …) and adjust the fake. If `pollForToken` in production loops with real delays, the fake returns immediately so the test stays fast.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AddAccountControllerTests`
Expected: FAIL — `cannot find 'AddAccountController' in scope`.

- [ ] **Step 3: Implement**

```swift
// Sources/Hubber/AddAccount/AddAccountController.swift
import AppKit
import Foundation

/// The three add-account provider kinds (spec decision #7).
enum AddAccountProvider: String, CaseIterable, Identifiable {
    case gitHubDotCom, gitHubEnterprise, gitLab
    var id: String { rawValue }

    var providerString: String { self == .gitLab ? "gitlab" : "github" }
    var title: String {
        switch self {
        case .gitHubDotCom: return "GitHub.com"
        case .gitHubEnterprise: return "GitHub Enterprise Server"
        case .gitLab: return "GitLab"
        }
    }
    /// github.com is fixed; the others take a user-entered server URL.
    var usesDeviceFlow: Bool { self == .gitHubDotCom }
    var defaultServerURL: String { self == .gitLab ? "https://gitlab.com" : "" }
}

/// Drives the add-account flow: gate `canConnect(host:)` → device-flow OR PAT → resolve login →
/// hand a fully-resolved identity to `addAccount`. Pure of `Connection`/scheduler (the `addAccount`
/// closure is injected; production wires it to `HubberStore.addResolvedAccount`).
@MainActor
final class AddAccountController: ObservableObject {
    enum Stage: Equatable {
        case picker
        case form(AddAccountProvider)
        case authenticating
        case deviceCode(GitHubDeviceAuthorization)
        case failed(String)
        case added(ConnectionID)
    }

    @Published private(set) var stage: Stage = .picker
    @Published var selectedProvider: AddAccountProvider = .gitHubDotCom

    private let policy: ProviderAccessPolicy
    private let authServiceFactory: (_ provider: String, _ host: String) -> any GitHubDeviceFlowServicing
    private let addAccount: (ConnectionID, GitHubStoredToken, GitHubAuthenticatedUser) async throws -> Void
    private var deviceAuthService: (any GitHubDeviceFlowServicing)?
    private var currentAuthorization: GitHubDeviceAuthorization?

    init(
        policy: ProviderAccessPolicy,
        authServiceFactory: @escaping (String, String) -> any GitHubDeviceFlowServicing = { ConnectionFactory.authService(provider: $0, host: $1) },
        addAccount: @escaping (ConnectionID, GitHubStoredToken, GitHubAuthenticatedUser) async throws -> Void
    ) {
        self.policy = policy
        self.authServiceFactory = authServiceFactory
        self.addAccount = addAccount
    }

    func choose(_ provider: AddAccountProvider) {
        selectedProvider = provider
        stage = .form(provider)
    }

    func reset() { stage = .picker }

    // MARK: - PAT path (GitLab / GHES / EMU github.com)

    func connectWithToken(provider: AddAccountProvider, serverURL: String, token: String) async {
        let host = Self.host(from: serverURL, provider: provider)
        guard policy.canConnect(host: host) else {
            stage = .failed(policy.blockedReason(host: host) ?? "Sign-in is restricted by your organization.")
            return
        }
        stage = .authenticating
        let auth = authServiceFactory(provider.providerString, host)
        do {
            let user = try await auth.fetchAuthenticatedUser(accessToken: token)
            let id = ConnectionID(provider: provider.providerString, host: host, login: user.login)
            let stored = GitHubStoredToken(
                accessToken: token,
                accessTokenExpiresAt: nil,
                refreshToken: nil,
                refreshTokenExpiresAt: nil,
                tokenType: "bearer",
                login: user.login
            )
            try await addAccount(id, stored, user)
            stage = .added(id)
        } catch GitHubAuthError.badCredentials {
            stage = .failed("That token was rejected. Check the token and its scopes.")
        } catch let HubberStore.AddAccountError.alreadyAdded {
            stage = .failed("This account is already added.")
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    // MARK: - Device-flow path (github.com)

    func beginDeviceFlow() async {
        let host = "github.com"
        guard policy.canConnect(host: host) else {
            stage = .failed(policy.blockedReason(host: host) ?? "Sign-in is restricted by your organization.")
            return
        }
        let auth = authServiceFactory("github", host)
        deviceAuthService = auth
        do {
            let authorization = try await auth.startDeviceFlow()
            currentAuthorization = authorization
            stage = .deviceCode(authorization)
            var token = try await auth.pollForToken(deviceAuthorization: authorization)
            let user = try await auth.fetchAuthenticatedUser(accessToken: token.accessToken)
            token.login = user.login
            let id = ConnectionID.gitHubDotCom(login: user.login)
            try await addAccount(id, token, user)
            stage = .added(id)
        } catch let HubberStore.AddAccountError.alreadyAdded {
            stage = .failed("This account is already added.")
        } catch is CancellationError {
            stage = .picker
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    func openDeviceVerificationPage() {
        guard let url = currentAuthorization.flatMap({ URL(string: $0.verificationUri) }) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyDeviceCode() {
        guard let code = currentAuthorization?.userCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    func cancel() { stage = .picker }

    // MARK: - Host parsing

    /// github.com is fixed; otherwise derive the host from the entered server URL.
    static func host(from serverURL: String, provider: AddAccountProvider) -> String {
        if provider == .gitHubDotCom { return "github.com" }
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comps = URLComponents(string: trimmed), let h = comps.host { return h }
        return trimmed.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }
}
```

> Implementer note: match the real `ProviderAccessPolicy` init + `GitHubDeviceAuthorization` field names (the snippet's `verificationUri`/`userCode` mirror `DeviceCodeScreen`'s usage). Production `pollForToken` may poll on an interval; that's fine — `beginDeviceFlow` awaits it.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter AddAccountControllerTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/AddAccount/AddAccountController.swift Tests/HubberTests/AddAccountControllerTests.swift
git commit -m "feat(m6): AddAccountController — gate + device-flow/PAT identity resolution (#61)"
```

---

### Task 5 — `AccountHeaderLabel` (decision #5) (TDD)

**Files:**
- Create: `Sources/Hubber/Account/AccountHeaderLabel.swift`
- Test: `Tests/HubberTests/AccountHeaderLabelTests.swift`

**Interfaces:**
- Produces: `enum AccountHeaderLabel { static func text(ids: [ConnectionID], hidden: Set<ConnectionID>) -> String }`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/HubberTests/AccountHeaderLabelTests.swift
import XCTest
@testable import Hubber

final class AccountHeaderLabelTests: XCTestCase {
    private let gh = ConnectionID.gitHubDotCom(login: "osuritz")
    private let gl = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")

    func testAllVisible() {
        XCTAssertEqual(AccountHeaderLabel.text(ids: [gh, gl], hidden: []), "All accounts")
    }
    func testExactlyOneVisible() {
        XCTAssertEqual(AccountHeaderLabel.text(ids: [gh, gl], hidden: [gl]), "GitHub · @osuritz")
    }
    func testPartialSubset() {
        let gl2 = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "other")
        XCTAssertEqual(AccountHeaderLabel.text(ids: [gh, gl, gl2], hidden: [gl2]), "2 of 3 accounts")
    }
    func testSingleAccountShowsItsLabel() {
        XCTAssertEqual(AccountHeaderLabel.text(ids: [gh], hidden: []), "GitHub · @osuritz")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AccountHeaderLabelTests`
Expected: FAIL — `cannot find 'AccountHeaderLabel' in scope`.

- [ ] **Step 3: Implement**

```swift
// Sources/Hubber/Account/AccountHeaderLabel.swift
import Foundation

/// Header label per spec decision #5: "All accounts" when all visible; "<Provider> · @login" when
/// exactly one visible; "N of M accounts" for a partial subset.
enum AccountHeaderLabel {
    static func text(ids: [ConnectionID], hidden: Set<ConnectionID>) -> String {
        let total = ids.count
        let visible = ids.filter { !hidden.contains($0) }
        if total == 0 { return "All accounts" }
        if visible.count == total { return "All accounts" }
        if visible.count == 1, let only = visible.first {
            return "\(only.providerDisplayName) · @\(only.login)"
        }
        return "\(visible.count) of \(total) accounts"
    }
}
```

> Note: when exactly one account exists and is visible, `visible.count == total == 1` → returns its `<Provider> · @login` (mirrors today's single-account header).

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter AccountHeaderLabelTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Account/AccountHeaderLabel.swift Tests/HubberTests/AccountHeaderLabelTests.swift
git commit -m "feat(m6): AccountHeaderLabel — header text per visibility (#61)"
```

---

### Task 6 — `AccountMenuView` wired into the header seam (UI)

**Files:**
- Create: `Sources/Hubber/Account/AccountMenuView.swift`
- Modify: `Sources/Hubber/HubberPopoverView.swift` (replace the static label at `:117-139` with `AccountMenuView`)

**Interfaces:**
- Consumes: `store.connections`, `store.settings.connectionVisibility`, `store.setConnectionVisible(_:_:)`, `AccountHeaderLabel.text(...)`, `ConnectionID.providerDisplayName`.

- [ ] **Step 1: Implement `AccountMenuView`**

```swift
// Sources/Hubber/Account/AccountMenuView.swift
import SwiftUI

/// Header account menu (spec decision #4/#5): a `Menu` whose label is the current visibility
/// summary, containing an "All accounts" master toggle + one checkbox row per connection
/// (⚠ when in error). Toggles route through `store.setConnectionVisible`. Toggle-only — no
/// account management here (that lives in Settings → Accounts).
struct AccountMenuView: View {
    @ObservedObject var store: HubberStore

    private var ids: [ConnectionID] { store.connections.map(\.id) }
    private var hidden: Set<ConnectionID> { store.settings.connectionVisibility.hidden }
    private var allVisible: Bool { hidden.isEmpty }

    var body: some View {
        Menu {
            Button {
                setAll(visible: !allVisible)
            } label: {
                Label("All accounts", systemImage: allVisible ? "checkmark" : "")
            }
            Divider()
            ForEach(store.connections, id: \.id) { conn in
                Button {
                    store.setConnectionVisible(conn.id, !store.settings.connectionVisibility.isVisible(conn.id))
                } label: {
                    let visible = store.settings.connectionVisibility.isVisible(conn.id)
                    Label(
                        rowTitle(conn),
                        systemImage: visible ? "checkmark" : ""
                    )
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HubberDesign.accent)
                Text(AccountHeaderLabel.text(ids: ids, hidden: hidden))
                    .font(HubberType.headerTitle)
                    .foregroundStyle(HubberDesign.text)
                if store.connections.contains(where: { $0.authState.isError }) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(HubberDesign.sloAmber.fg)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(HubberDesign.text3)
            }
            .frame(minWidth: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func rowTitle(_ conn: Connection) -> String {
        let base = "\(conn.id.providerDisplayName) · @\(conn.id.login)"
        return conn.authState.isError ? "\(base)  ⚠ Needs attention" : base
    }

    private func setAll(visible: Bool) {
        for conn in store.connections {
            store.setConnectionVisible(conn.id, visible)
        }
    }
}
```

> Implementer note: confirm `HubberAuthState.isError` exists (used in `removeConnection`, `GitHubAuth.swift:520`). Confirm `HubberType.headerTitle`/`HubberDesign.sloAmber.fg` token names (used elsewhere in this file). If `.menuStyle(.borderlessButton)` clips the custom label oddly, fall back to a `Menu { … } label: { … }` inside a fixed-width container — keep the `minWidth: 44` tap target the seam comment reserved.

- [ ] **Step 2: Wire into the header** — in `HubberPopoverView.swift`, replace the static label block (the `HStack(spacing: 5) { Image… "GitHub" · login }` at `:117-139`, including its `.frame(minWidth: 44…)`/`.contentShape`) with:

```swift
                AccountMenuView(store: store)
```

- [ ] **Step 3: Build + smoke-test**

Run: `swift build --disable-sandbox` then `swift test --filter AccountHeaderLabelTests`
Expected: builds clean; label tests still pass. (View has no separate unit test — its logic is `AccountHeaderLabel`, covered in Task 5.)

- [ ] **Step 4: Commit**

```bash
git add Sources/Hubber/Account/AccountMenuView.swift Sources/Hubber/HubberPopoverView.swift
git commit -m "feat(m6): account toggle menu in the popover header (#61)"
```

---

### Task 7 — `AddAccountView` (UI)

**Files:**
- Create: `Sources/Hubber/AddAccount/AddAccountView.swift`

**Interfaces:**
- Consumes: `AddAccountController` (Task 4), `AddAccountProvider`, `SignInButtonStyle`/`DeviceCodeScreen` patterns, `HubberDesign`/`HubberType`.

- [ ] **Step 1: Implement** — a self-contained sheet bound to an `AddAccountController`, branching on `controller.stage`:

```swift
// Sources/Hubber/AddAccount/AddAccountView.swift
import SwiftUI

/// Add-account flow (spec §4): provider picker → github.com device-flow (with "use a token
/// instead") OR host+PAT form. Binds an `AddAccountController`. `onDone` dismisses the sheet.
struct AddAccountView: View {
    @ObservedObject var controller: AddAccountController
    var onDone: () -> Void

    @State private var serverURL: String = ""
    @State private var token: String = ""
    @State private var usePATForGitHub = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch controller.stage {
            case .picker:
                providerPicker
            case let .form(provider):
                if provider == .gitHubDotCom, !usePATForGitHub {
                    gitHubDotComStart
                } else {
                    patForm(provider: provider)
                }
            case .authenticating:
                ProgressView("Connecting…").frame(maxWidth: .infinity)
            case let .deviceCode(authorization):
                deviceCode(authorization)
            case let .failed(message):
                errorState(message)
            case .added:
                addedState
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { serverURL = controller.selectedProvider.defaultServerURL }
    }

    private var header: some View {
        HStack {
            Text("Add account").font(.system(size: 15, weight: .semibold))
            Spacer()
            Button("Cancel") { controller.cancel(); onDone() }.buttonStyle(.plain).foregroundStyle(HubberDesign.text2)
        }
    }

    private var providerPicker: some View {
        VStack(spacing: 8) {
            ForEach(AddAccountProvider.allCases) { provider in
                Button {
                    usePATForGitHub = false
                    serverURL = provider.defaultServerURL
                    controller.choose(provider)
                } label: {
                    HStack {
                        Text(provider.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(HubberDesign.text3)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(HubberDesign.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var gitHubDotComStart: some View {
        VStack(spacing: 12) {
            Button {
                Task { await controller.beginDeviceFlow() }
            } label: {
                Text("Sign in with GitHub").font(.system(size: 13.5, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: .light))
            Button("Use a token instead") { usePATForGitHub = true }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(HubberDesign.text2)
        }
    }

    private func patForm(provider: AddAccountProvider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if provider != .gitHubDotCom {
                Text("Server URL").font(HubberType.settingsSub).foregroundStyle(HubberDesign.text2)
                TextField("https://…", text: $serverURL).textFieldStyle(.roundedBorder)
            }
            Text("Personal access token").font(HubberType.settingsSub).foregroundStyle(HubberDesign.text2)
            SecureField("Paste your token", text: $token).textFieldStyle(.roundedBorder)
            Link("Create a token ↗", destination: tokenHelpURL(provider))
                .font(.system(size: 11)).foregroundStyle(HubberDesign.accent)
            Button {
                Task { await controller.connectWithToken(provider: provider, serverURL: serverURL, token: token) }
            } label: {
                Text("Connect").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: .light))
            .disabled(token.isEmpty || (provider != .gitHubDotCom && serverURL.isEmpty))
        }
    }

    private func deviceCode(_ authorization: GitHubDeviceAuthorization) -> some View {
        VStack(spacing: 12) {
            Text("Enter this code at github.com/login/device.").font(.system(size: 12.5)).foregroundStyle(HubberDesign.text2)
            Text(authorization.userCode).font(.system(size: 22, weight: .semibold, design: .monospaced))
            HStack(spacing: 10) {
                Button("Copy code") { controller.copyDeviceCode() }
                Button("Open GitHub") { controller.openDeviceVerificationPage() }
            }
            Button("Cancel") { controller.cancel() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(HubberDesign.text2)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message).font(.system(size: 12)).foregroundStyle(HubberDesign.sloRed.fg).multilineTextAlignment(.center)
            Button("Try again") { controller.reset() }
        }
    }

    private var addedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(HubberDesign.sloGreen.fg)
            Text("Account added").font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .onAppear { Task { @MainActor in try? await Task.sleep(for: .seconds(0.8)); onDone() } }
    }

    private func tokenHelpURL(_ provider: AddAccountProvider) -> URL {
        switch provider {
        case .gitLab: return URL(string: "https://gitlab.com/-/user_settings/personal_access_tokens")!
        default: return URL(string: "https://github.com/settings/tokens")!
        }
    }
}
```

> Implementer note: confirm `HubberDesign.fill`/`sloRed.fg`/`sloGreen.fg` token names (used in `SignInScreen`/`HubberPopoverView`). `SignInButtonStyle` takes a `colorScheme`; thread the real `@Environment(\.colorScheme)` rather than `.light` if you want correct dark-mode styling (the placeholder keeps it compiling). GHES token-help URL is host-relative; a static github.com link is an acceptable v1 default.

- [ ] **Step 2: Build**

Run: `swift build --disable-sandbox`
Expected: builds clean. (No unit test — flow logic is `AddAccountControllerTests`.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Hubber/AddAccount/AddAccountView.swift
git commit -m "feat(m6): AddAccountView — provider picker + device-flow/PAT forms (#61)"
```

---

### Task 8 — `AccountsSettingsSection` replaces `GitHubAuthSettingsView` (UI)

**Files:**
- Create: `Sources/Hubber/Settings/AccountsSettingsSection.swift`
- Modify: `Sources/Hubber/HubberSettingsView.swift` (the "GitHub Account" section → "Accounts" + `AccountsSettingsSection`)

**Interfaces:**
- Consumes: `store.connections`, `store.removeConnection(_:)`, per-connection `signOut()`/`signIn(withToken:)`/`startSignIn(policy:)`, `store.addResolvedAccount` (via an `AddAccountController` built here), `settings.$notifyHiddenAccounts`.

- [ ] **Step 1: Implement** — a list of accounts + an "Add account…" sheet + the hidden-notify toggle:

```swift
// Sources/Hubber/Settings/AccountsSettingsSection.swift
import SwiftUI

/// Settings → Accounts (spec §6): one row per connection (avatar, identity, ⚠) with Sign out /
/// Remove / Re-authenticate, an "Add account…" button (presents `AddAccountView`), and the
/// "Notify for hidden accounts" toggle. Replaces the single-account `GitHubAuthSettingsView`.
struct AccountsSettingsSection: View {
    @ObservedObject var store: HubberStore
    @ObservedObject var settings: SettingsStore
    @State private var showingAdd = false
    @State private var reauthToken: [ConnectionID: String] = [:]

    var body: some View {
        SettingsGroup {
            ForEach(Array(store.connections.enumerated()), id: \.element.id) { index, conn in
                accountRow(conn, isLast: false)
            }
            // Add account row
            SettingsRow(isLast: false) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add account…", systemImage: "plus.circle")
                }
                .buttonStyle(.plain).foregroundStyle(HubberDesign.accent)
            }
            // Notify for hidden accounts
            SettingsRow(isLast: true) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify for hidden accounts").font(HubberType.settingsLabel).foregroundStyle(HubberDesign.text)
                    Text("Hidden accounts still alert on new activity.").font(HubberType.settingsSub).foregroundStyle(HubberDesign.text2)
                }
                Toggle("", isOn: $settings.notifyHiddenAccounts).toggleStyle(.switch).labelsHidden()
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddAccountView(controller: makeController(), onDone: { showingAdd = false })
        }
    }

    @ViewBuilder
    private func accountRow(_ conn: Connection, isLast: Bool) -> some View {
        SettingsRow(isLast: isLast) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    AvatarView(
                        user: GitHubUser(login: conn.id.login, initials: initials(conn.id.login), color: avatarColor(conn.id.login), avatarURL: conn.viewerAvatarURL),
                        size: AvatarSize.row.rawValue
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(conn.id.providerDisplayName) · @\(conn.id.login)").font(HubberType.title).foregroundStyle(HubberDesign.text)
                        if conn.authState.isError {
                            Text("⚠ Needs attention").font(HubberType.secondary).foregroundStyle(HubberDesign.sloAmber.fg)
                        }
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    if conn.authState.isError {
                        if isDeviceFlow(conn) {
                            Button("Re-authenticate") { conn.startSignIn(policy: settings.providerAccessPolicy) }
                        } else {
                            // PAT re-auth: inline token field
                            SecureField("New token", text: Binding(
                                get: { reauthToken[conn.id] ?? "" },
                                set: { reauthToken[conn.id] = $0 }
                            )).textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                            Button("Re-authenticate") {
                                let t = reauthToken[conn.id] ?? ""
                                Task { await conn.signIn(withToken: t); reauthToken[conn.id] = nil }
                            }.disabled((reauthToken[conn.id] ?? "").isEmpty)
                        }
                    }
                    Button("Sign out") { Task { await conn.signOut() } }
                    Button("Remove") { Task { await store.removeConnection(conn.id) } }
                }
                .controlSize(.small)
            }
        }
    }

    private func makeController() -> AddAccountController {
        AddAccountController(
            policy: settings.providerAccessPolicy,
            addAccount: { [weak store] id, token, user in
                _ = try await store?.addResolvedAccount(id: id, token: token, user: user)
            }
        )
    }

    private func isDeviceFlow(_ conn: Connection) -> Bool {
        conn.id.provider == "github" && conn.id.host == "github.com"
    }

    private func initials(_ login: String) -> String { String(login.prefix(1)).uppercased() }
    private func avatarColor(_ login: String) -> Color {
        Color(hue: Double(abs(login.hashValue) % 360) / 360.0, saturation: 0.55, brightness: 0.70)
    }
}
```

> Implementer note: reuse the avatar `initials`/`avatarColor` helpers that already exist in `GitHubAuthSettingsView` (extract to a shared place if you prefer DRY, or inline as above). Confirm `GitHubUser(login:initials:color:avatarURL:)` and `AvatarView(user:size:)`/`AvatarSize.row` (used in `GitHubAuthSettingsView:145`). `conn.startSignIn(policy:)`/`conn.signIn(withToken:)`/`conn.signOut()` are existing `Connection` methods. Device-flow re-auth here flips that connection to `.waitingForUser`; surfacing the device code inside Settings is a follow-up — for v1 the popover header/`DeviceCodeScreen` already renders `.waitingForUser` for the primary; for a non-primary github.com account, route re-auth through the same `AddAccountView` device-code sheet if the inline button proves insufficient (note this in the PR).

- [ ] **Step 2: Replace the section in `SettingsView`** — in `HubberSettingsView.swift`, change the first section from:

```swift
            SettingsSection(title: "GitHub Account") {
                SettingsGroup {
                    GitHubAuthSettingsView(store: store)
                }
            }
```

to:

```swift
            SettingsSection(title: "Accounts") {
                AccountsSettingsSection(store: store, settings: settings)
            }
```

(`AccountsSettingsSection` provides its own `SettingsGroup`.) Leave `GitHubAuthSettingsView.swift` in the tree for now (still referenced by no one — remove in a cleanup commit only if `make ci`'s unused-symbol lint flags it; otherwise leave to keep this task focused).

- [ ] **Step 3: Build**

Run: `swift build --disable-sandbox`
Expected: builds clean.

- [ ] **Step 4: Commit**

```bash
git add Sources/Hubber/Settings/AccountsSettingsSection.swift Sources/Hubber/HubberSettingsView.swift
git commit -m "feat(m6): Settings → Accounts management section (#61)"
```

---

### Task 9 — Empty-state routing → add-account (UI)

**Files:**
- Modify: `Sources/Hubber/HubberPopoverView.swift` (the `.signedOut` branch / `SignInScreen` path)

**Interfaces:**
- Consumes: `AddAccountView`/`AddAccountController`; existing `SignInScreen`.

- [ ] **Step 1: Route the welcome screen into the provider picker** — the simplest spec-faithful change: keep `SignInScreen` (with its github.com device-flow button via `store.startSignIn()`, which bootstraps the primary connection) and add a secondary "Add a different account" affordance that opens `AddAccountView`. In `HubberPopoverView`, add an `@State private var showingAdd = false`, and present the sheet from the `.signedOut`/`.error` branches:

```swift
        case .signedOut:
            SignInScreen(store: store)
                .overlay(alignment: .bottom) { addDifferentAccountLink }
                .sheet(isPresented: $showingAdd) { addAccountSheet }
```

with helpers:

```swift
    private var addDifferentAccountLink: some View {
        Button("Add GitHub Enterprise or GitLab…") { showingAdd = true }
            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(HubberDesign.text2)
            .padding(.bottom, 12)
    }

    private var addAccountSheet: some View {
        AddAccountView(
            controller: AddAccountController(
                policy: store.settings.providerAccessPolicy,
                addAccount: { [weak store] id, token, user in _ = try await store?.addResolvedAccount(id: id, token: token, user: user) }
            ),
            onDone: { showingAdd = false }
        )
    }
```

> Note: the github.com device-flow first-run path is unchanged (`store.startSignIn()` → `.waitingForUser` → `DeviceCodeScreen`). The new link covers first-run GHES/GitLab/EMU. Once ≥1 account exists, the normal chrome + header menu + Settings → Accounts take over.

- [ ] **Step 2: Build**

Run: `swift build --disable-sandbox`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/Hubber/HubberPopoverView.swift
git commit -m "feat(m6): empty-state routes into the add-account flow (#61)"
```

---

### Task 10 — Full gate

- [ ] **Step 1: Run the gate**

Run: `make ci`
Expected: build + `swift test` green (prior suite + ~14 new tests); swiftlint 0; `swiftformat --lint` clean. If swiftformat flags new files, run `swiftformat .` and re-stage; keep multi-line calls one-arg-per-line.

- [ ] **Step 2: Build the dev app for a manual smoke**

Run: `make app-dev` (debug → file token store, no Keychain re-prompts — see `dev-builds-use-file-token-store`).
Expected: launches; header shows the account menu; Settings → Accounts lists the account + "Add account…".

---

## Acceptance (whole plan)

- `make ci` green; existing suite unaffected.
- Header shows `AccountMenuView` with the decision-#5 label + per-account visibility toggles (route through `setConnectionVisible`); badge already reflects visibility.
- "Add account…" (Settings) and the empty-state link open `AddAccountView`: provider picker → github.com device flow (with "use a token instead") / GHES+GitLab host+PAT → host gate → identity resolution → `addResolvedAccount` (dedup) → account appears, visible by default.
- Settings → Accounts lists each connection with Sign out / Remove / Re-authenticate, plus the "Notify for hidden accounts" toggle.
- Device-flow tokens keep their refresh token (via `adopt`); PAT tokens are non-refreshable (Rail B).

## Deferred to Phase 3 (manual, needs the user's PAT)

- **GitLab E2E:** add a real gitlab.com account; verify `GitLabAuthService.currentUser { username name avatarUrl }` and the provider's `currentUser.reviewRequestedMergeRequests` / `mergeRequestInteraction.reviewState` / `resolvableDiscussionsCount` against the live schema.
- **EMU-via-PAT:** add a company github.com account (e.g. `@osuritz_LinkedIn`) via the PAT path; confirm isolation from the personal account.
- **Device-flow add of a 2nd github.com account** end-to-end (the path Task 4 enables) — confirm the refresh token persists and survives relaunch via `restoreAllConnections()`.
- **Non-primary device-flow re-auth UX** — if the inline Settings "Re-authenticate" for a non-primary github.com account doesn't surface the device code well, route it through the `AddAccountView` device-code sheet.

## Self-Review Checklist
- [ ] Identity resolution (`AddAccountController`) is pure of `Connection`/scheduler; its tests inject `addAccount` + a fake auth service → no scheduler hang.
- [ ] Host gate (`canConnect(host:)`) runs BEFORE any device-flow/fetch in the controller; blocked host → `.failed(blockedReason)`.
- [ ] `adopt` preserves a device-flow refresh token; PAT path builds `refreshToken: nil`.
- [ ] Dedup: `addResolvedAccount` throws `alreadyAdded`; controller maps it to "already added".
- [ ] Visibility toggles call `store.setConnectionVisible`; badge unchanged (Rail A).
- [ ] Header label matches decision #5 for 0 / all-visible / exactly-one / partial.
- [ ] Names consistent: `authService(provider:host:)`, `providerDisplayName`, `adopt(token:user:)`, `addResolvedAccount(id:token:user:)`, `AddAccountController`, `AddAccountProvider`, `AccountHeaderLabel`, `AccountMenuView`, `AddAccountView`, `AccountsSettingsSection`.
- [ ] No item-model changes; reused `SettingsSection`/`AvatarView`/`SignInButtonStyle`/`DeviceCodeScreen`/`HubberDesign`.
