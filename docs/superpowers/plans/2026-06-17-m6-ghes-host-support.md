# M6 — GitHub Enterprise Server (GHES) Host Support Implementation Plan (#82)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> Branch: `feat/m6-ghes-host-support` (off `main` @ `ba852be`). TDD task-by-task; commit per green task. Gate locally with **`make ci`** (build + `swift test` + swiftlint + `swiftformat --lint`) — the `.githooks/pre-push` hook runs it on push (CI is manual-only). One PR → main.

**Goal:** Parameterize `GitHubProvider` and `GitHubAuthService` by a `baseURL` so a GitHub Enterprise Server (GHES) account routes its GraphQL/REST/login traffic to `https://<host>/...` instead of the hardcoded github.com endpoints — and generalize `ProviderAccessPolicy` to a host-generic `canConnect(host:)` predicate.

**Architecture:** A single `GitHubEndpoints` value type resolves the concrete endpoint URLs from a host's *web* base URL, special-casing public github.com (which splits its API onto `api.github.com`) versus GHES (uniform `/api/graphql`, `/api/v3/...`, `/login/...` under one host). Both `GitHubProvider` and `GitHubAuthService` gain a `baseURL` parameter (default github.com) and route through this resolver, so the dotcom-vs-GHES branching lives in exactly one place. `ProviderAccessPolicy` gains `canConnect(host:)`; the existing `canConnectGitHubDotCom`/`blockedReason` become shims delegating to host `"github.com"`, preserving every current call site.

**Tech Stack:** Swift 6.3, SPM, XCTest, `MockURLProtocol` (host-aware request interception), `URLSessionConfiguration.ephemeral`.

**Issues:** Closes #82. Refs #80. Builds on the `CodeHostProvider` / `CodeHostAuthServicing` seams from #81/#86 and mirrors the `baseURL` pattern `GitLabProvider` already shipped in #60.

---

## Coordinator decisions (do not relitigate)

1. **One endpoint resolver, not two.** `GitHubEndpoints` owns the only place that knows github.com splits its API onto `api.github.com` while GHES keeps everything under one host (`/api/graphql`, `/api/v3/...`, `/login/...`). Both the provider and the auth service consume it. This is DRY and keeps the special-case auditable for the security-sensitive routing.
2. **`baseURL` is the *web* host root**, e.g. `https://github.com` or `https://github.enterprise.acme.com` — NOT the API subdomain. `isDotCom` is detected by `webBaseURL.host == "github.com"`. GitHub Enterprise *Cloud* (GHEC) is treated as a GHES variant for routing and is out of scope here (per QA plan §34).
3. **Defaults preserve today's behavior exactly.** `GitHubProvider(baseURL:)` and `GitHubAuthService(baseURL:)` default to github.com, so every existing call site (`CachingCodeHostProvider(wrapping: GitHubProvider())`, `GitHubAuthService()`, the legacy `Connection`, `main.swift`) compiles unchanged and keeps hitting `api.github.com` / `github.com`. **No production wiring changes in this PR.**
4. **Scope boundary = the routing parameter + the host-generic policy predicate, with unit/integration tests.** Per-connection host *plumbing* (passing a connection's host into its provider/auth at add-connection time) and enforcing `canConnect(host:)` inside `startSignIn` for non-github hosts is **#61 (multi-account UI)** — out of scope here. #82 makes the seam *exist and be correct*; #61 wires it to the UI. This mirrors how #60 shipped `GitLabProvider(baseURL:)` without UI wiring.
5. **`canConnect(host:)` semantics** (the host-generic generalization of the existing rule):
   - Non-empty allowlist: host allowed iff `allowlist.contains(host)`, OR (`host == "github.com"` AND `allowPersonalGitHub`). `allowPersonalGitHub` is the *personal-github* override only — it never grants an enterprise host.
   - Empty allowlist (no restriction configured): `host == "github.com"` is gated by `allowPersonalGitHub`; any other host is allowed.
   - `canConnectGitHubDotCom == canConnect(host: "github.com")` — provably identical to today's logic, so existing tests/call sites are untouched.
6. **Reuse the existing types** — `GitHubStoredToken` / `GitHubAuthenticatedUser` / `GitHubAuthError` are unchanged; `GitHubEndpoints` is a new pure value type only. No new error cases.

---

## Endpoint mapping (the authoritative routing contract)

`webBaseURL` is the sign-in host root. All other URLs derive from it:

| Endpoint | github.com (`webBaseURL = https://github.com`) | GHES (`webBaseURL = https://github.enterprise.acme.com`) |
|---|---|---|
| `graphQL` | `https://api.github.com/graphql` | `https://github.enterprise.acme.com/api/graphql` |
| `restBase` | `https://api.github.com` | `https://github.enterprise.acme.com/api/v3` |
| `authenticatedUser` | `https://api.github.com/user` | `https://github.enterprise.acme.com/api/v3/user` |
| `deviceCode` | `https://github.com/login/device/code` | `https://github.enterprise.acme.com/login/device/code` |
| `accessToken` | `https://github.com/login/oauth/access_token` | `https://github.enterprise.acme.com/login/oauth/access_token` |

Hardcoded sites being replaced (verified by grep):
- `Sources/Hubber/GitHub/GitHubProvider.swift:195` — GraphQL URL.
- `Sources/Hubber/GitHubAuth.swift:169` — device-code URL.
- `Sources/Hubber/GitHubAuth.swift:193` — access-token URL (device-flow poll).
- `Sources/Hubber/GitHubAuth.swift:235` — access-token URL (refresh).
- `Sources/Hubber/GitHubAuth.swift:256` — authenticated-user URL.

`GitHubProvider+Outgoing.swift` and the rest of the provider route through the shared `graphQL(...)` transport — no separate URLs to change.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/Hubber/GitHub/GitHubEndpoints.swift` | Pure `Sendable` value type mapping a web `baseURL` → graphQL / restBase / authenticatedUser / deviceCode / accessToken URLs; the single dotcom-vs-GHES special-case |
| Modify | `Sources/Hubber/GitHub/GitHubProvider.swift` | `init(baseURL:session:)`; `graphQL` uses `endpoints.graphQL` |
| Modify | `Sources/Hubber/GitHubAuth.swift` | `GitHubAuthService.init(clientID:baseURL:session:)`; device-flow/refresh/user URLs use `endpoints.*` |
| Modify | `Sources/Hubber/Core/ProviderAccessPolicy.swift` | Add `canConnect(host:)` + `blockedReason(host:)`; make `canConnectGitHubDotCom`/`blockedReason` shims |
| Create | `Tests/HubberTests/GitHubEndpointsTests.swift` | Endpoint-mapping matrix (dotcom + GHES) |
| Modify | `Tests/HubberTests/ProviderHostRoutingTests.swift` | Add GHES GraphQL routing + cross-host (github.com vs GHES) token-isolation tests (MC-MDM-06); fix the `:51` "belongs to #82" comment |
| Create | `Tests/HubberTests/GitHubAuthServiceRoutingTests.swift` | Device-flow + authenticated-user URL routing for github.com default and GHES baseURL |
| Modify | `Tests/HubberTests/ProviderAccessPolicyTests.swift` | MC-MDM-03/04 host-generic `canConnect(host:)` cases + shim-equivalence |

---

## Tasks

### Task 1 — `GitHubEndpoints` resolver (TDD)

**Files:**
- Create: `Sources/Hubber/GitHub/GitHubEndpoints.swift`
- Test: `Tests/HubberTests/GitHubEndpointsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/HubberTests/GitHubEndpointsTests.swift
import Foundation
import XCTest
@testable import Hubber

final class GitHubEndpointsTests: XCTestCase {
    func testDotComDefaultRoutesAPIToApiGitHubCom() {
        let endpoints = GitHubEndpoints()
        XCTAssertTrue(endpoints.isDotCom)
        XCTAssertEqual(endpoints.graphQL.absoluteString, "https://api.github.com/graphql")
        XCTAssertEqual(endpoints.restBase.absoluteString, "https://api.github.com")
        XCTAssertEqual(endpoints.authenticatedUser.absoluteString, "https://api.github.com/user")
        XCTAssertEqual(endpoints.deviceCode.absoluteString, "https://github.com/login/device/code")
        XCTAssertEqual(endpoints.accessToken.absoluteString, "https://github.com/login/oauth/access_token")
    }

    func testGHESKeepsEverythingUnderOneHost() throws {
        let base = try XCTUnwrap(URL(string: "https://github.enterprise.acme.com"))
        let endpoints = GitHubEndpoints(webBaseURL: base)
        XCTAssertFalse(endpoints.isDotCom)
        XCTAssertEqual(endpoints.graphQL.absoluteString, "https://github.enterprise.acme.com/api/graphql")
        XCTAssertEqual(endpoints.restBase.absoluteString, "https://github.enterprise.acme.com/api/v3")
        XCTAssertEqual(endpoints.authenticatedUser.absoluteString, "https://github.enterprise.acme.com/api/v3/user")
        XCTAssertEqual(endpoints.deviceCode.absoluteString, "https://github.enterprise.acme.com/login/device/code")
        XCTAssertEqual(
            endpoints.accessToken.absoluteString,
            "https://github.enterprise.acme.com/login/oauth/access_token"
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GitHubEndpointsTests`
Expected: FAIL — compile error, `cannot find 'GitHubEndpoints' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/Hubber/GitHub/GitHubEndpoints.swift
import Foundation

/// Resolves the concrete API/login endpoints for a GitHub host from its *web* base URL.
///
/// github.com and GitHub Enterprise Server (GHES) lay out their endpoints differently:
/// github.com splits its API onto the `api.github.com` subdomain, while GHES keeps GraphQL,
/// REST (`/api/v3`), and OAuth/device (`/login`) under the single appliance host. This is the
/// only place that knows that distinction — both `GitHubProvider` and `GitHubAuthService` route
/// through it.
///
/// `webBaseURL` is the host root the user signs in against (e.g. `https://github.com` or
/// `https://github.enterprise.acme.com`) — NOT the API subdomain.
struct GitHubEndpoints: Sendable, Equatable {
    let webBaseURL: URL

    /// The default github.com web host root. Reused as the default `baseURL` for the provider
    /// and auth service so existing call sites preserve today's behavior.
    static let dotComWebBaseURL = URL(string: "https://github.com")!

    init(webBaseURL: URL = GitHubEndpoints.dotComWebBaseURL) {
        self.webBaseURL = webBaseURL
    }

    /// True when this resolver targets public github.com (which splits its API onto `api.github.com`).
    var isDotCom: Bool {
        webBaseURL.host == "github.com"
    }

    /// GraphQL endpoint. github.com → `https://api.github.com/graphql`; GHES → `https://<host>/api/graphql`.
    var graphQL: URL {
        if isDotCom {
            return URL(string: "https://api.github.com/graphql")!
        }
        return webBaseURL.appendingPathComponent("api/graphql")
    }

    /// REST API base. github.com → `https://api.github.com`; GHES → `https://<host>/api/v3`.
    var restBase: URL {
        if isDotCom {
            return URL(string: "https://api.github.com")!
        }
        return webBaseURL.appendingPathComponent("api/v3")
    }

    /// Authenticated-user REST endpoint (`<restBase>/user`).
    var authenticatedUser: URL {
        restBase.appendingPathComponent("user")
    }

    /// OAuth device-code request endpoint (`<webBaseURL>/login/device/code`).
    var deviceCode: URL {
        webBaseURL.appendingPathComponent("login/device/code")
    }

    /// OAuth access-token endpoint (`<webBaseURL>/login/oauth/access_token`).
    var accessToken: URL {
        webBaseURL.appendingPathComponent("login/oauth/access_token")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GitHubEndpointsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/GitHub/GitHubEndpoints.swift Tests/HubberTests/GitHubEndpointsTests.swift
git commit -m "feat(ghes): GitHubEndpoints resolver (github.com vs GHES routing) (#82)"
```

---

### Task 2 — `GitHubProvider(baseURL:)` routes GraphQL via endpoints (TDD)

**Files:**
- Modify: `Sources/Hubber/GitHub/GitHubProvider.swift:4-9` (stored props + init), `:195` (graphQL URL)
- Test: `Tests/HubberTests/ProviderHostRoutingTests.swift`

- [ ] **Step 1: Write the failing test** (add to `ProviderHostRoutingTests`)

```swift
    func testGitHubProviderRoutesGraphQLToGHESHostWithBearerToken() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.dataResponse)
        }
        let provider = GitHubProvider(
            baseURL: try XCTUnwrap(URL(string: "https://github.enterprise.acme.com")),
            session: makeSession()
        )

        _ = try await provider.graphQL(
            query: "query Test { viewer { login } }",
            variables: [:],
            accessToken: "ghes-secret"
        )

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://github.enterprise.acme.com/api/graphql")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ghes-secret")
    }

    func testGitHubProviderDefaultStillRoutesToApiGitHubCom() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.dataResponse)
        }
        let provider = GitHubProvider(session: makeSession())

        _ = try await provider.graphQL(
            query: "query Test { viewer { login } }",
            variables: [:],
            accessToken: "gh-secret"
        )

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/graphql")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProviderHostRoutingTests/testGitHubProviderRoutesGraphQLToGHESHostWithBearerToken`
Expected: FAIL — `GitHubProvider` has no `baseURL:` initializer (extra argument 'baseURL' in call).

- [ ] **Step 3: Write minimal implementation**

Replace `Sources/Hubber/GitHub/GitHubProvider.swift:4-9`:

```swift
final class GitHubProvider: CodeHostProvider {
    private let session: URLSession
    private let endpoints: GitHubEndpoints

    init(baseURL: URL = GitHubEndpoints.dotComWebBaseURL, session: URLSession = .shared) {
        self.endpoints = GitHubEndpoints(webBaseURL: baseURL)
        self.session = session
    }
```

Replace the URL at `Sources/Hubber/GitHub/GitHubProvider.swift:195`:

```swift
        var request = URLRequest(url: endpoints.graphQL)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProviderHostRoutingTests`
Expected: PASS — new GHES + default tests pass; the pre-existing GitLab/GitHub isolation test still passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/GitHub/GitHubProvider.swift Tests/HubberTests/ProviderHostRoutingTests.swift
git commit -m "feat(ghes): parameterize GitHubProvider baseURL via endpoints (#82)"
```

---

### Task 3 — `GitHubAuthService(baseURL:)` routes device-flow + REST (TDD)

**Files:**
- Modify: `Sources/Hubber/GitHubAuth.swift:158-165` (stored props + init), `:169`, `:193`, `:235`, `:256` (the five URLs)
- Test: `Tests/HubberTests/GitHubAuthServiceRoutingTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/HubberTests/GitHubAuthServiceRoutingTests.swift
import Foundation
import XCTest
@testable import Hubber

final class GitHubAuthServiceRoutingTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testStartDeviceFlowRoutesToGHESLoginHost() async throws {
        MockURLProtocol.handler = { request in
            (try Self.ok(for: request), Self.deviceCodeResponse)
        }
        let service = GitHubAuthService(
            clientID: "client-123",
            baseURL: try XCTUnwrap(URL(string: "https://github.enterprise.acme.com")),
            session: makeSession()
        )

        _ = try await service.startDeviceFlow()

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://github.enterprise.acme.com/login/device/code")
    }

    func testFetchAuthenticatedUserRoutesToGHESRestV3() async throws {
        MockURLProtocol.handler = { request in
            (try Self.ok(for: request), Self.userResponse)
        }
        let service = GitHubAuthService(
            clientID: "client-123",
            baseURL: try XCTUnwrap(URL(string: "https://github.enterprise.acme.com")),
            session: makeSession()
        )

        _ = try await service.fetchAuthenticatedUser(accessToken: "ghes-secret")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://github.enterprise.acme.com/api/v3/user")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ghes-secret")
    }

    func testDefaultsPreserveDotComEndpoints() async throws {
        MockURLProtocol.handler = { request in
            (try Self.ok(for: request), Self.deviceCodeResponse)
        }
        let service = GitHubAuthService(clientID: "client-123", session: makeSession())

        _ = try await service.startDeviceFlow()

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://github.com/login/device/code")
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func ok(for request: URLRequest) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    private static let deviceCodeResponse = Data("""
    {
      "device_code": "dc-1",
      "user_code": "WDJB-MJHT",
      "verification_uri": "https://github.enterprise.acme.com/login/device",
      "expires_in": 900,
      "interval": 5
    }
    """.utf8)

    private static let userResponse = Data("""
    { "login": "enterprise-user", "name": "Enterprise User", "avatar_url": "https://example.com/a.png" }
    """.utf8)
}
```

> Note: `DeviceCodeResponse` decodes snake_case keys (`device_code`, `user_code`, `verification_uri`, `expires_in`); `GitHubAuthenticatedUser` decodes `login`/`name`/`avatar_url`. If a field name in these fixtures fails to decode, open `Sources/Hubber/GitHub/GitHubModels.swift` and match the existing `CodingKeys` — do not change the model.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GitHubAuthServiceRoutingTests/testStartDeviceFlowRoutesToGHESLoginHost`
Expected: FAIL — `GitHubAuthService` has no `baseURL:` parameter (extra argument 'baseURL' in call).

- [ ] **Step 3: Write minimal implementation**

Replace `Sources/Hubber/GitHubAuth.swift:158-165` (stored props + init):

```swift
final class GitHubAuthService: GitHubAuthServicing, Sendable {
    private let clientID: String
    private let session: URLSession
    private let endpoints: GitHubEndpoints

    init(
        clientID: String = GitHubAppConfig.clientID,
        baseURL: URL = GitHubEndpoints.dotComWebBaseURL,
        session: URLSession = .shared
    ) {
        self.clientID = clientID
        self.endpoints = GitHubEndpoints(webBaseURL: baseURL)
        self.session = session
    }
```

Replace the device-code URL at `:169` (inside `startDeviceFlow`):

```swift
            url: endpoints.deviceCode,
```

Replace the access-token URL at `:193` (inside `pollForToken`):

```swift
                url: endpoints.accessToken,
```

Replace the access-token URL at `:235` (inside `refresh`):

```swift
            url: endpoints.accessToken,
```

Replace the authenticated-user URL at `:256` (inside `fetchAuthenticatedUser`):

```swift
        var request = URLRequest(url: endpoints.authenticatedUser)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GitHubAuthServiceRoutingTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/GitHubAuth.swift Tests/HubberTests/GitHubAuthServiceRoutingTests.swift
git commit -m "feat(ghes): parameterize GitHubAuthService baseURL (device-flow + REST) (#82)"
```

---

### Task 4 — `ProviderAccessPolicy.canConnect(host:)` (TDD)

**Files:**
- Modify: `Sources/Hubber/Core/ProviderAccessPolicy.swift:37-50`
- Test: `Tests/HubberTests/ProviderAccessPolicyTests.swift`

- [ ] **Step 1: Write the failing test** (add to `ProviderAccessPolicyTests`)

```swift
    // MARK: - Host-generic canConnect(host:) — #82

    // MC-MDM-03: allowlist containing the GHES host permits that host (but not github.com).
    func testAllowlistWithGHESHostPermitsGHESButNotGitHubDotCom() {
        let policy = ProviderAccessPolicy(
            allowPersonalGitHub: false,
            allowlist: ["github.enterprise.acme.com"]
        )
        XCTAssertTrue(policy.canConnect(host: "github.enterprise.acme.com"))
        XCTAssertNil(policy.blockedReason(host: "github.enterprise.acme.com"))
        XCTAssertFalse(policy.canConnect(host: "github.com"))
    }

    // MC-MDM-04: a host not in a non-empty allowlist is blocked.
    func testAllowlistWithoutHostBlocksThatHost() {
        let policy = ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: ["github.com"])
        XCTAssertFalse(policy.canConnect(host: "gitlab.com"))
        XCTAssertNotNil(policy.blockedReason(host: "gitlab.com"))
    }

    // Empty allowlist = no host restriction: enterprise hosts allowed; github.com gated by the flag.
    func testEmptyAllowlistAllowsAnyEnterpriseHostButGatesGitHubDotCom() {
        let permissive = ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: [])
        XCTAssertTrue(permissive.canConnect(host: "github.enterprise.acme.com"))
        XCTAssertTrue(permissive.canConnect(host: "github.com"))

        let blocked = ProviderAccessPolicy(allowPersonalGitHub: false, allowlist: [])
        XCTAssertTrue(blocked.canConnect(host: "github.enterprise.acme.com"))
        XCTAssertFalse(blocked.canConnect(host: "github.com"))
    }

    // The github.com shim must stay provably identical to canConnect(host: "github.com").
    func testCanConnectGitHubDotComShimMatchesHostPredicate() {
        let cases = [
            ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: []),
            ProviderAccessPolicy(allowPersonalGitHub: false, allowlist: []),
            ProviderAccessPolicy(allowPersonalGitHub: false, allowlist: ["github.com"]),
            ProviderAccessPolicy(allowPersonalGitHub: false, allowlist: ["github.enterprise.acme.com"]),
            ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: ["github.enterprise.acme.com"]),
        ]
        for policy in cases {
            XCTAssertEqual(policy.canConnectGitHubDotCom, policy.canConnect(host: "github.com"))
            XCTAssertEqual(policy.blockedReason, policy.blockedReason(host: "github.com"))
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProviderAccessPolicyTests/testAllowlistWithGHESHostPermitsGHESButNotGitHubDotCom`
Expected: FAIL — `value of type 'ProviderAccessPolicy' has no member 'canConnect'`.

- [ ] **Step 3: Write minimal implementation**

Replace `Sources/Hubber/Core/ProviderAccessPolicy.swift:34-50` (the `// MARK: - github.com (personal) policy` block through `blockedReason`) with:

```swift
    // MARK: - Host-generic policy

    /// True when the current policy permits connecting to `host`.
    ///
    /// - Non-empty allowlist: `host` must appear in the allowlist, OR be github.com with
    ///   `allowPersonalGitHub == true` (the personal-github override never grants an enterprise host).
    /// - Empty allowlist (no restriction configured): github.com is gated by `allowPersonalGitHub`;
    ///   every other host is permitted.
    func canConnect(host: String) -> Bool {
        if !allowlist.isEmpty {
            if allowlist.contains(host) { return true }
            return host == "github.com" && allowPersonalGitHub
        }
        if host == "github.com" { return allowPersonalGitHub }
        return true
    }

    /// A user-facing explanation of why connecting to `host` is blocked, or `nil` when not blocked.
    func blockedReason(host: String) -> String? {
        guard !canConnect(host: host) else { return nil }
        return "Sign-in to \(host) is restricted by your organization."
    }

    // MARK: - github.com (personal) shims — preserved for existing call sites

    /// True when the current policy permits signing in to github.com with a personal account.
    var canConnectGitHubDotCom: Bool {
        canConnect(host: "github.com")
    }

    /// A user-facing explanation of why github.com sign-in is blocked, or `nil` when not blocked.
    var blockedReason: String? {
        blockedReason(host: "github.com")
    }
```

> The github.com shim produces the identical string today's code emits (`"Sign-in to github.com is restricted by your organization."`), so `Connection.startSignIn`, `SignInScreen`, `GitHubAuthSettingsView`, and the existing `ProviderAccessPolicyTests` are unaffected.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProviderAccessPolicyTests`
Expected: PASS — new host-generic tests plus all pre-existing policy tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Core/ProviderAccessPolicy.swift Tests/HubberTests/ProviderAccessPolicyTests.swift
git commit -m "feat(ghes): generalize ProviderAccessPolicy.canConnect(host:) (#82)"
```

---

### Task 5 — Cross-host token isolation (MC-MDM-06) + full sweep

**Files:**
- Modify: `Tests/HubberTests/ProviderHostRoutingTests.swift` (add the cross-host isolation test; fix the stale `:51` comment)

- [ ] **Step 1: Write the failing test** (add to `ProviderHostRoutingTests`)

```swift
    // MC-MDM-06: a github.com provider and a GHES provider in the same test each send their
    // token only to their own host — no cross-host credential leakage.
    func testGitHubDotComAndGHESProvidersKeepCredentialsIsolatedByHost() async throws {
        nonisolated(unsafe) var seen: [(host: String?, auth: String?)] = []
        MockURLProtocol.handler = { request in
            seen.append((request.url?.host, request.value(forHTTPHeaderField: "Authorization")))
            return try (Self.response(for: request), Self.dataResponse)
        }

        let dotCom = GitHubProvider(session: makeSession())
        let ghes = GitHubProvider(
            baseURL: try XCTUnwrap(URL(string: "https://github.enterprise.acme.com")),
            session: makeSession()
        )

        _ = try await dotCom.graphQL(query: "query { viewer { login } }", variables: [:], accessToken: "dotcom-token")
        _ = try await ghes.graphQL(query: "query { viewer { login } }", variables: [:], accessToken: "ghes-token")

        let dotComRequest = seen.first { $0.host == "api.github.com" }
        let ghesRequest = seen.first { $0.host == "github.enterprise.acme.com" }
        XCTAssertEqual(dotComRequest?.auth, "Bearer dotcom-token")
        XCTAssertEqual(ghesRequest?.auth, "Bearer ghes-token")
        // The GHES token must never reach api.github.com and vice versa.
        XCTAssertNil(seen.first { $0.host == "api.github.com" && $0.auth == "Bearer ghes-token" })
        XCTAssertNil(seen.first { $0.host == "github.enterprise.acme.com" && $0.auth == "Bearer dotcom-token" })
    }
```

Also fix the now-stale comment at `Tests/HubberTests/ProviderHostRoutingTests.swift:51`:

```swift
        // GitHub now routes per-baseURL (#82): the default targets api.github.com; GHES routing
        // is covered by the GHES-specific tests above.
```

- [ ] **Step 2: Run test to verify it fails, then passes**

Run: `swift test --filter ProviderHostRoutingTests/testGitHubDotComAndGHESProvidersKeepCredentialsIsolatedByHost`
Expected: PASS (the routing was implemented in Task 2; this test asserts isolation across two live providers). If it does not pass, the bug is in Task 2's routing — fix there.

- [ ] **Step 3: Run the full gate**

Run: `make ci`
Expected: build succeeds; `swift test` all green (prior suite count **367** + the new GHES/auth/policy tests, ~**13** added → ~380, 0 failures); swiftlint 0; `swiftformat --lint` clean.

> If `swiftformat --lint` flags the new files, run `swiftformat .` and re-stage.

- [ ] **Step 4: Commit**

```bash
git add Tests/HubberTests/ProviderHostRoutingTests.swift
git commit -m "test(m6): GHES base-URL routing + cross-host token isolation (#82)"
```

---

## Acceptance (whole PR)

- `make ci` green (build + `swift test` + swiftlint + `swiftformat --lint`); existing suite unaffected (all prior tests still pass via the github.com defaults).
- `GitHubProvider(baseURL:)` and `GitHubAuthService(baseURL:)` route GraphQL/REST/login to the correct host; github.com defaults preserve `api.github.com` / `github.com` exactly.
- `GitHubEndpoints` is the single source of the dotcom-vs-GHES URL distinction.
- `ProviderAccessPolicy.canConnect(host:)` covers MC-MDM-03 (GHES host allowed) and MC-MDM-04 (non-allowlisted host blocked); `canConnectGitHubDotCom`/`blockedReason` shims are provably identical to today.
- MC-MDM-06 cross-host token isolation proven via `MockURLProtocol` host inspection — no credential leakage between github.com and a GHES host.
- Open PR → main with `Closes #82`, `Refs #80`; locally-green via the pre-push hook (CI manual-only).
- **Deferred (not this PR):** per-connection host plumbing into provider/auth at add-connection time and enforcing `canConnect(host:)` in `startSignIn` for non-github hosts (**#61**, multi-account UI); GHES validation against a real appliance (manual, needs an instance).

## Self-Review Checklist

- [ ] `GitHubEndpoints` matches the endpoint-mapping table for both github.com and GHES (graphQL, restBase, authenticatedUser, deviceCode, accessToken).
- [ ] All five hardcoded sites (`GitHubProvider.swift:195`; `GitHubAuth.swift:169/193/235/256`) now route through `endpoints.*`; no `api.github.com`/`github.com` string literals remain in those methods.
- [ ] Both new `baseURL:` params default to `GitHubEndpoints.dotComWebBaseURL`; every existing call site compiles unchanged and preserves behavior.
- [ ] `canConnect(host:)` semantics match decision #5; github.com shim equals `canConnect(host: "github.com")` and the blocked-reason string is byte-identical to today's.
- [ ] No cross-host credential leakage (MC-MDM-06); GHES GraphQL → `/api/graphql`, REST user → `/api/v3/user`, login → `/login/...`.
- [ ] Type/name consistency: `GitHubEndpoints`, `webBaseURL`, `dotComWebBaseURL`, `graphQL`, `restBase`, `authenticatedUser`, `deviceCode`, `accessToken`, `canConnect(host:)`, `blockedReason(host:)` used identically across all tasks.
- [ ] Scope boundary honored: no production wiring changes; per-connection host injection + `startSignIn` host enforcement left to #61.
