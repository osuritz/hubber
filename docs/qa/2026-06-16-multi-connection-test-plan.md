# Hubber Multi-Connection Test Plan

**Document version:** 1.0  
**Date:** 2026-06-16  
**Author:** QA / SDET (generated)  
**Milestone coverage:** M6 (multi-connection), GitLab provider (#60), multi-account UI (#61), provider-switcher stub (#31)  
**Codebase branch:** main (pre-M6)

---

## 1. Scope, Goals, and Non-Goals

### 1.1 Scope

This test plan covers the behavioral contract for the multi-connection milestone (**M6**) and the GitLab provider (**#60**). The generalizing abstraction is that the app holds a **set of connections**, where each connection = { a `CodeHostProvider` value, an account identity/login, a credential/token, its own refresh scheduler, notification baseline, and error state }.

The codebase today is single-tenant: `HubberStore` holds one `authState`, one `viewerLogin`, one `GitHubTokenStoring` instance, one `RefreshScheduler`, one `notificationBaseline`, and a single Keychain item at `service = "com.osuritz.hubber.github-auth"` / `account = "github-app-user-token"`. Every story in this plan targets a behavioral assumption that must change or be proven to remain correct under multi-connection.

The two-axis extension under test:

1. **Multi-account, same provider:** two GitHub accounts at once — one personal (github.com), one work (github.com). The sharpest, highest-risk case because the existing code has a single-key Keychain store, a single `authState` enum, and a single snapshot file.
2. **Multi-provider:** a GitLab account coexisting with one or more GitHub accounts, sharing the same UI aggregation layer, scheduler, and notification pipeline.

### 1.2 Goals

- Establish a living regression suite that gates the M6 acceptance milestone.
- Surface every single-tenant assumption explicitly, with a story ID traceable to source-level evidence.
- Provide automatable, assertable stories (Given / When / Then) runnable under XCTest / Swift Testing with the existing `MockURLProtocol`, `InMemoryManagedPreferences`, and injectable-provider idioms.
- Cover the nastiest cross-connection interactions: dedup, partial failure, sign-out isolation, token collision, notification cross-fire, and MDM policy enforcement across hosts.

### 1.3 Non-Goals

- This plan does not cover GitLab UI design, GitLab-specific Premium features beyond what is needed to test protocol conformance, or SAML/SSO auth flows.
- GitHub Enterprise Cloud (GHEC) is treated as a GHES variant for routing purposes; specific GHEC API differences are out of scope.
- This plan does not cover MAS sandboxing differences (covered separately) or Sparkle update delivery.
- Performance profiling and memory footprint are not in scope.
- Accessibility testing is not in scope for this document.

---

## 2. High-Level Test Areas

- **A. Connection lifecycle** — add, authenticate (device flow), restore on relaunch, remove connections; ordering and concurrency of multiple simultaneous device flows.
- **B. Token-storage isolation** — per-connection Keychain items (service/account key uniqueness); no credential collision between accounts on same or different hosts.
- **C. Data aggregation and dedup** — union of incoming/outgoing/drafts across connections; same PR node ID appearing under two accounts must produce exactly one row.
- **D. Per-connection refresh scheduling** — independent `RefreshScheduler` instances, each with its own `RefreshContext`; rate-limit on connection A must not suppress connection B.
- **E. Per-connection notification baselines** — `SnapshotStore` path uniqueness per connection; no cross-connection false-fire; no re-fire on restart; dedup at the coordinator level.
- **F. Badge and SLO aggregation** — badge count and attention-needed count aggregated across all connections; SLO clock is per-item regardless of host.
- **G. Settings and MDM / provider allowlist** — `ProviderAccessPolicy` enforcement per host at add-connection time; `allowPersonalGitHub=false` blocks a second personal github.com connection; GHES host must be in the allowlist to be addable; GitLab host policy.
- **H. Sign-out isolation** — signing out of connection A must not touch B's token, snapshot, cache, or error state.
- **I. Per-connection error, offline, and rate-limit** — partial fetch failure (A fails, B succeeds); network offline mid-refresh; rate-limit backoff scoped to the offending connection only.
- **J. Provider-switcher UI stub** — `#31` provider-switcher: GitLab entry point visible but disabled until `#60` ships; correct disabled UI state; no crash on tap.
- **K. GitLab provider protocol conformance** — `GitLabProvider` conforms to `CodeHostProvider`; Merge Requests map to `IncomingReview` / `OutgoingReview`; pipelines map to `PullRequestCI`; approval rules (free tier: 0 required approvals, Premium: N); unresolved discussions map to `unresolved` count.
- **L. Cross-provider mixing** — GitHub + GitLab coexisting: aggregated lists sorted correctly; SLO clocks tick independently; notifications fired per-connection, not globally.

---

## 3. Detailed Testing Stories

### Area A — Connection Lifecycle

---

#### MC-AUTH-01: Add first connection (GitHub) succeeds on clean install

**Preconditions:** Fresh install; no stored tokens; no managed restrictions.  
**When:** User initiates sign-in via device flow.  
**Then:**
- `authState` for connection-0 transitions: `.signedOut` → `.restoring` → `.waitingForUser(deviceAuth)` → `.signedIn(login:)`.
- A Keychain item is created at a deterministic key scoped to connection-0 (e.g. `service = "com.osuritz.hubber.github-auth"`, `account = "github-app-user-token:0"` or an account-scoped variant).
- `refreshPullRequestsLoop` starts for connection-0 only.

**Automation layer:** Unit — inject `SpyGitHubAuthService` (already exists in `HubberStoreProviderPolicyTests.swift`) returning a canned `GitHubDeviceAuthorization` then a `GitHubStoredToken`. Assert state transitions on a multi-connection `HubberStore` variant. **Automatable now** with existing spy infrastructure.

**Regression risk:** Single-tenant `startSignIn()` sets `authState` on the store directly; multi-connection must scope state to the connection object.

---

#### MC-AUTH-02: Add second GitHub account while first is signed in

**Preconditions:** Connection-0 is `.signedIn(login: "personal")`.  
**When:** User adds a second connection and completes device flow for `login: "work"`.  
**Then:**
- Connection-0 remains `.signedIn(login: "personal")` throughout.
- Connection-1 transitions through `.waitingForUser` → `.signedIn(login: "work")`.
- Two distinct Keychain items exist (verified by reading both keys).
- Both refresh loops are running (two active `RefreshScheduler` tasks).

**Automation layer:** Unit — two `SpyGitHubAuthService` instances, each injected into their respective connection. Assert both connections independently reach `.signedIn`. **Automatable now.**

**Regression risk:** Current `HubberStore.startSignIn()` cancels any in-flight `authTask`. With two connections, each connection must own its own `authTask`.

---

#### MC-AUTH-03: Device flow cancellation on one connection does not affect the other

**Preconditions:** Connection-0 is `.signedIn`. Connection-1 is in `.waitingForUser` state.  
**When:** User calls `cancelSignIn()` on connection-1.  
**Then:**
- Connection-1 transitions to `.signedOut`.
- Connection-0 remains `.signedIn`; its refresh loop keeps running.
- No Keychain write or delete occurs for connection-0's key.

**Automation layer:** Unit — `SpyGitHubAuthService` for connection-1 with a controlled `pollForToken` that suspends indefinitely until the task is cancelled. Assert connection-0 state is unchanged. **Automatable now.**

---

#### MC-AUTH-04: Relaunch restores all connections from persisted tokens

**Preconditions:** Two tokens persisted (one per connection) from a previous run.  
**When:** App launches and calls `restoreSession()` for each connection.  
**Then:**
- Each connection independently resolves its token, refreshes if stale, fetches the authenticated user, and reaches `.signedIn`.
- If one token is expired/invalid, that connection transitions to `.sessionExpired(login:)` while the other reaches `.signedIn`.

**Automation layer:** Unit — inject two `SpyTokenStore` instances (pattern from `HubberStoreProviderPolicyTests.swift`) pre-loaded with tokens. **Automatable now.**

**Regression risk:** `HubberStore.restoreSession()` currently reads a single `tokenStore`. Multi-connection must iterate over connection-keyed stores.

---

#### MC-AUTH-05: GitLab OAuth device flow completes and stores token under GitLab-scoped key

**Preconditions:** No GitLab connection exists. A `GitLabAuthServicing` protocol injectable is defined analogously to `GitHubAuthServicing`.  
**When:** User initiates GitLab connection.  
**Then:**
- Auth flow uses GitLab OAuth endpoints (e.g. `https://gitlab.com/oauth/authorize`).
- Token stored under a key distinct from any GitHub key.
- Connection transitions to `.signedIn(login: "gitlab-user")`.

**Automation layer:** Unit — inject a spy conforming to a `GitLabAuthServicing` protocol. **Automatable now** once protocol exists; architecture work needed.

---

### Area B — Token-Storage Isolation

---

#### MC-TOKEN-01: Keychain keys are unique per connection

**Preconditions:** Two GitHub connections and one GitLab connection are signed in.  
**When:** All three tokens are written to Keychain.  
**Then:**
- Three distinct `(service, account)` pairs exist in Keychain — none share both `service` and `account` fields.
- Reading key for connection-A returns only connection-A's token.
- Reading key for connection-B returns only connection-B's token.

**Automation layer:** Unit — use injectable `GitHubTokenStoring` spies. Verify that `save()` is called with distinct keys; verify `load()` returns the token from the correct spy. No real Keychain access needed. **Automatable now.**

**Regression risk:** Current `GitHubKeychainTokenStore` has `service = "com.osuritz.hubber.github-auth"` and `account = "github-app-user-token"` as constants (lines 26–27 of `GitHubAuth.swift`). Any second GitHub connection would overwrite the first without a key-derivation scheme. This is the primary token-collision risk.

---

#### MC-TOKEN-02: Sign-out of connection A deletes only A's Keychain item

**Preconditions:** Connection-A (`login: "personal"`) and connection-B (`login: "work"`) are both signed in.  
**When:** `signOut()` is called on connection-A.  
**Then:**
- `delete()` is called exactly once on connection-A's `GitHubTokenStoring` spy.
- `delete()` is never called on connection-B's `GitHubTokenStoring` spy.
- Connection-B's `authState` remains `.signedIn(login: "work")`.

**Automation layer:** Unit — two spy token stores, each tracking `deleteCallCount`. **Automatable now.**

---

#### MC-TOKEN-03: Expired token on connection A triggers refresh only for A

**Preconditions:** Connection-A's token has `hasFreshAccessToken == false`. Connection-B's token is fresh.  
**When:** `refreshPullRequestsFromGitHub()` runs for both connections.  
**Then:**
- `authService.refresh()` is called for connection-A.
- `authService.refresh()` is NOT called for connection-B.
- Both connections complete their fetch after the refresh.

**Automation layer:** Unit — inject `SpyGitHubAuthService` (separate instance per connection); assert `refresh` call count per spy. **Automatable now.**

---

#### MC-TOKEN-04: Bad refresh token on connection A transitions A to sessionExpired without affecting B

**Preconditions:** Both connections signed in. Connection-A's refresh attempt throws `GitHubAuthError.missingRefreshToken`.  
**When:** Connection-A attempts to refresh during a PR fetch cycle.  
**Then:**
- Connection-A's `authState` becomes `.sessionExpired(login: "personal")`.
- Connection-A's refresh loop stops.
- Connection-B's `authState` remains `.signedIn(login: "work")`.
- Connection-B's refresh loop continues uninterrupted.

**Automation layer:** Unit — spy auth service for A throws `missingRefreshToken`; spy for B returns a valid token. **Automatable now.**

---

### Area C — Data Aggregation and Dedup

---

#### MC-AGG-01: Incoming reviews from two connections are unioned

**Preconditions:** Connection-A returns 2 incoming reviews (IDs `"pr-A1"`, `"pr-A2"`). Connection-B returns 3 incoming reviews (IDs `"pr-B1"`, `"pr-B2"`, `"pr-B3"`).  
**When:** Both connections complete their fetch.  
**Then:**
- Aggregated `HubberData.incoming.count == 5`.
- Each review is present exactly once.
- Sort order is by `sloClockStart` descending (oldest first) across all items.

**Automation layer:** Unit — two stub `CodeHostProvider` implementations returning fixed arrays; aggregation logic under test is the new multi-connection aggregator. **Automatable now** once aggregation layer exists.

---

#### MC-AGG-02: Same PR under two accounts appears only once (dedup by node ID)

**Preconditions:** User is a member of org under both `personal` and `work` GitHub accounts. Both accounts have the same PR (node ID `"pr-X1"`) in their incoming queues.  
**When:** Both connections fetch incoming reviews.  
**Then:**
- `HubberData.incoming` contains exactly one item with `id == "pr-X1"`.
- Dedup keeps the entry with the earlier `sloClockStart` (to preserve urgency).

**Automation layer:** Unit — two stub providers both returning a review with the same `id`. Assert dedup logic in the aggregator. **Automatable now** once aggregator exists.

**Regression risk:** `NotificationDiffer` uses `IncomingReview.id` as the dedup key for notification baselines. A duplicate ID appearing under two connections would fire two `newReview` events on first add-of-second-connection. This must be prevented at the aggregation layer.

---

#### MC-AGG-03: Outgoing PRs aggregated and sorted across connections

**Preconditions:** Connection-A: 1 outgoing PR updated 2h ago. Connection-B: 2 outgoing PRs updated 1h and 3h ago.  
**When:** Aggregation runs.  
**Then:**
- `HubberData.outgoing.count == 3`.
- Sorted most-recently-updated first: B(1h), A(2h), B(3h).

**Automation layer:** Unit. **Automatable now** once aggregator exists.

---

#### MC-AGG-04: Drafts deduplicated by ID across connections

**Preconditions:** Same draft PR (node ID `"draft-X"`) exists under both connections (e.g. org-fork visible from both accounts).  
**When:** Aggregation runs.  
**Then:**
- Exactly one `DraftReview` with `id == "draft-X"` in the aggregated list.

**Automation layer:** Unit. **Automatable now** once aggregator exists.

---

#### MC-AGG-05: Partial fetch failure does not corrupt aggregated result

**Preconditions:** Connection-A fetch succeeds (returns 2 items). Connection-B fetch throws a network error.  
**When:** Aggregation runs.  
**Then:**
- Aggregated incoming list contains the 2 items from connection-A.
- A per-connection error indicator is set for connection-B (`incomingError` or equivalent field).
- No crash; `HubberData` is not replaced with empty data.
- The badge count reflects only connection-A's data.

**Automation layer:** Unit — stub provider for B throws `URLError(.notConnectedToInternet)`. **Automatable now.**

---

### Area D — Per-Connection Refresh Scheduling

---

#### MC-SCHED-01: Each connection gets an independent RefreshScheduler

**Preconditions:** Two signed-in connections.  
**When:** Both schedulers start.  
**Then:**
- Two distinct `RefreshScheduler` task objects are running.
- Stopping connection-A's scheduler (e.g. on sign-out) does not cancel connection-B's task.

**Automation layer:** Unit — inject `ControlledSleeper` (pattern from `RefreshSchedulerTests.swift`) per scheduler. **Automatable now.**

---

#### MC-SCHED-02: Rate-limit on connection A does not suppress B

**Preconditions:** Connection-A receives a 429 response with `Retry-After: 900`. Connection-B is healthy.  
**When:** Next refresh cycle runs for both connections.  
**Then:**
- Connection-A skips its fetch and logs `"Skipped refresh: rate-limited until ..."`.
- Connection-B proceeds with its fetch normally.
- `rateLimitedUntil` is scoped to connection-A only.

**Automation layer:** Unit/Integration — `MockURLProtocol` returning 429 for connection-A's token; normal response for connection-B's token. **Automatable now** once connection is keyed by token/URL.

---

#### MC-SCHED-03: Urgent SLO on connection A accelerates only A's cadence

**Preconditions:** Connection-A has an incoming review 90% through its SLO budget (`hasUrgentSLO == true`). Connection-B is all-green.  
**When:** Each scheduler computes its next interval.  
**Then:**
- Connection-A's `RefreshCadence.interval(for:)` returns 30 s.
- Connection-B's `RefreshCadence.interval(for:)` returns 300 s (or 900 s if idle+all-green).

**Automation layer:** Unit — `RefreshContext` constructed independently per connection. **Automatable now.**

---

#### MC-SCHED-04: Sleep/wake triggers immediate refresh on all connections

**Preconditions:** Both connections signed in and idle.  
**When:** System wake notification fires.  
**Then:**
- Both connections' schedulers call `reset()`.
- Both perform an immediate refresh.

**Automation layer:** Unit — verify `reset()` is called on each scheduler's spy. **Automatable now** once wake-handling iterates over connections.

---

### Area E — Per-Connection Notification Baselines

---

#### MC-NOTIF-01: Snapshot file paths are unique per connection

**Preconditions:** Two connections exist.  
**When:** Each connection's `SnapshotStore` is initialised.  
**Then:**
- Two distinct file paths are used (e.g. `notification-snapshot-<connectionID>.json`).
- Writing connection-A's snapshot does not overwrite connection-B's file.

**Automation layer:** Unit — inject two `SnapshotStore` instances with different `snapshotURL` values (pattern from `SnapshotStoreTests.swift`). Assert URL distinctness. **Automatable now.**

**Regression risk:** Current `SnapshotStore.defaultSnapshotURL` resolves to a single path `Application Support/Hubber/notification-snapshot.json`. A second connection would read and overwrite the same file.

---

#### MC-NOTIF-02: New review on connection A does not fire notification for connection B

**Preconditions:** Connection-A baseline: `{}`. Connection-B baseline: `{incomingIDs: ["pr-B1"]}`.  
**When:** Connection-A fetch returns new incoming `"pr-A1"`. Connection-B fetch returns same `"pr-B1"` (unchanged).  
**Then:**
- Exactly one `newReview` notification fires, for `pr-A1`.
- No notification fires for connection-B.

**Automation layer:** Unit — run `NotificationDiffer.events(previous:current:enabled:)` independently per connection baseline. **Automatable now** (the differ already exists; this tests the isolation of baselines).

---

#### MC-NOTIF-03: No re-fire on app restart with persisted baseline

**Preconditions:** Both connections have persisted baselines matching their current data.  
**When:** App restarts and restores sessions for both connections.  
**Then:**
- No notifications fire during restore (both `previous` snapshots equal the current data → `events` is empty).

**Automation layer:** Unit — `SnapshotStore` with matching baseline, `NotificationDiffer.events` must return `[]`. Already covered for single connection in `SnapshotStoreTests.testPersistedBaselineMeansRelaunchProducesNoEvents`; extend to two connections. **Automatable now.**

---

#### MC-NOTIF-04: Cross-connection dedup — same PR approved under both accounts fires one notification

**Preconditions:** PR `"pr-X1"` appears in both connection-A's and connection-B's outgoing lists (same author). Both baselines show `reviewerState: "pending"` for `"alice"`. `alice` approves.  
**When:** Both connections' fetches return `alice`'s state as `"approved"`.  
**Then:**
- Exactly one `reviewApproved` notification fires (dedup at the aggregated diff layer).

**Automation layer:** Unit — aggregate outgoing lists first (dedup by `OutgoingReview.id`), then run a single `NotificationDiffer.events`. **Automatable now** once aggregation is in place.

---

#### MC-NOTIF-05: Sign-out of connection A clears A's baseline without touching B's

**Preconditions:** Both connections have persisted snapshot files.  
**When:** Connection-A's `signOut()` completes.  
**Then:**
- Connection-A's snapshot file is deleted (or reset to empty).
- Connection-B's snapshot file is unchanged.
- On next launch, connection-B restores its baseline and produces no spurious notifications.

**Automation layer:** Unit — two `SnapshotStore` spies; assert only A's `deleteOrReset()` is called. **Automatable now.**

---

### Area F — Badge and SLO Aggregation

---

#### MC-BADGE-01: Badge attention count is sum across all connections (with dedup)

**Preconditions:** Connection-A contributes 2 attention items. Connection-B contributes 3 attention items. No overlap.  
**When:** `AttentionState.attentionCount(data:settings:)` is called on aggregated data.  
**Then:** Badge shows 5.

**Automation layer:** Unit — construct `HubberData` with 5 distinct items meeting the attention criteria (failing CI or incoming review). **Automatable now** (`AttentionStateTests.swift` exists).

---

#### MC-BADGE-02: Deduplicated cross-connection PR counts once toward badge

**Preconditions:** `"pr-X1"` is incoming under both accounts. After dedup it appears once.  
**When:** Badge count is computed.  
**Then:** `"pr-X1"` contributes exactly 1 to the attention count.

**Automation layer:** Unit — verify dedup at aggregation layer before `AttentionState` runs. **Automatable now.**

---

#### MC-BADGE-03: SLO clock is scoped per IncomingReview item regardless of which connection fetched it

**Preconditions:** `"pr-A1"` from connection-A has `sloClockStart` = 5 hours ago (amber). `"pr-B1"` from connection-B has `sloClockStart` = 1 hour ago (green).  
**When:** `ReviewSLOPresentation` is evaluated.  
**Then:**
- `"pr-A1"` renders amber regardless of connection-B's state.
- `"pr-B1"` renders green.
- SLO thresholds are applied using `SettingsStore.sloHours` (global) as input.

**Automation layer:** Unit — `ReviewSLOPresentationTests.swift` already exercises this; extend with items from two different stub providers. **Automatable now.**

---

#### MC-BADGE-04: isAllGreen is false when any connection has items

**Preconditions:** Connection-A has 0 incoming. Connection-B has 1 incoming.  
**When:** `AttentionState.isAllGreen(data:)` is called on the aggregated data.  
**Then:** Returns `false`.

**Automation layer:** Unit. **Automatable now.**

---

### Area G — Settings, MDM, and Provider Allowlist

---

#### MC-MDM-01: allowPersonalGitHub=false blocks adding a second personal github.com connection

**Preconditions:** `InMemoryManagedPreferences([ManagedKey.allowPersonalGitHub: false])`. Connection-0 is already signed in as `personal`.  
**When:** User tries to add connection-1 via `startSignIn()` targeting github.com.  
**Then:**
- `authState` for connection-1 transitions to `.error("Sign-in to github.com is restricted...")`.
- `startDeviceFlow()` is never called (spy call count == 0).

**Automation layer:** Unit — extends `HubberStoreProviderPolicyTests` pattern directly. `SpyGitHubAuthService` already exists. **Automatable now.**

---

#### MC-MDM-02: Non-empty allowlist without github.com blocks personal connection

**Preconditions:** `InMemoryManagedPreferences([ManagedKey.providerAllowlist: ["github.enterprise.acme.com"]])`.  
**When:** User tries to add github.com connection.  
**Then:** `ProviderAccessPolicy.canConnectGitHubDotCom == false`; sign-in attempt is blocked before device flow starts.

**Automation layer:** Unit — `ProviderAccessPolicyTests.swift` already covers this rule; extend to verify enforcement in `HubberStore.startSignIn()`. **Automatable now.**

---

#### MC-MDM-03: Allowlist containing github.enterprise.acme.com permits GHES connection

**Preconditions:** `InMemoryManagedPreferences([ManagedKey.providerAllowlist: ["github.enterprise.acme.com"]])`.  
**When:** User adds a GHES connection for `github.enterprise.acme.com`.  
**Then:** Policy permits the connection; device flow starts.

**Automation layer:** Unit — extend `ProviderAccessPolicy` with a `canConnect(host:)` method that checks the allowlist. **Automatable now** once host-parameterised policy exists.

---

#### MC-MDM-04: GitLab host not in allowlist is blocked

**Preconditions:** `InMemoryManagedPreferences([ManagedKey.providerAllowlist: ["github.com"]])`. GitLab not in allowlist.  
**When:** User tries to add gitlab.com connection.  
**Then:** Connection is blocked; `.error` state set; no auth flow starts.

**Automation layer:** Unit — requires `ProviderAccessPolicy` to be extended with a host-generic `canConnect(host:)` predicate. **Automatable now** once extension exists.

---

#### MC-MDM-05: Forced MDM settings apply equally across all connections

**Preconditions:** MDM forces `sloEnabled = false`.  
**When:** `SettingsStore` initialises with `InMemoryManagedPreferences([ManagedKey.sloEnabled: false])`.  
**Then:**
- `settings.sloEnabled == false` for the global `SettingsStore`.
- All connections' SLO rendering uses the same `SettingsStore`; no connection bypasses the forced value.

**Automation layer:** Unit — `SettingsStoreMDMTests.swift` already covers this. Verify that aggregated `AttentionState.hasUrgentSLO` returns `false` when `sloEnabled == false`. **Automatable now.**

---

#### MC-MDM-06: GHES base URL routing uses the correct connection's host

**Preconditions:** Connection-A: `github.com`. Connection-B: `github.enterprise.acme.com`.  
**When:** `GitHubProvider` (or a GHES variant) constructs the GraphQL URL.  
**Then:**
- Connection-A's requests go to `https://api.github.com/graphql`.
- Connection-B's requests go to `https://github.enterprise.acme.com/api/graphql`.
- Tokens from connection-A are never sent to connection-B's host (verified via `MockURLProtocol.lastRequest.url.host`).

**Automation layer:** Integration — `MockURLProtocol` handler inspects `request.url.host` and `request.value(forHTTPHeaderField: "Authorization")`. Assert no cross-host credential leakage. **Automatable now** using `MockURLProtocol`.

---

### Area H — Sign-Out Isolation

---

#### MC-SIGNOUT-01: signOut() for connection A does not clear connection B's HubberData

**Preconditions:** Both connections have fetched data. Aggregated `HubberData` has items from both.  
**When:** Connection-A is signed out.  
**Then:**
- Connection-A's items are removed from the aggregated lists.
- Connection-B's items remain visible.
- Connection-B's `authState` is unchanged.

**Automation layer:** Unit — stub providers; verify aggregated `HubberData` after sign-out re-aggregation. **Automatable now** once aggregation layer exists.

---

#### MC-SIGNOUT-02: signOut() for connection A calls invalidateAll() on A's provider only

**Preconditions:** Both connections use a `CachingCodeHostProvider` wrapping their respective stub providers. Connection-A's cache is warm.  
**When:** Connection-A is signed out.  
**Then:**
- `invalidateAll()` is called on connection-A's `CachingCodeHostProvider`.
- `invalidateAll()` is NOT called on connection-B's provider.

**Automation layer:** Unit — two `CachingCodeHostProvider` instances; add a spy wrapper or observe via `CodeHostCacheInvalidating`. **Automatable now.**

**Regression risk:** Current `signOut()` casts `self.provider as? CodeHostCacheInvalidating` and calls it (line 541 of `GitHubAuth.swift`). This works for one provider; multi-connection must call it on the right provider.

---

#### MC-SIGNOUT-03: signOut() for connection A stops only A's refresh scheduler

**Preconditions:** Both schedulers running.  
**When:** Connection-A is signed out.  
**Then:**
- Connection-A's `scheduler.stop()` is called.
- Connection-B's scheduler continues ticking (verified by refresh count increment after sign-out).

**Automation layer:** Unit — two `ControlledSleeper` instances, one per scheduler. **Automatable now.**

---

#### MC-SIGNOUT-04: Signing out all connections leaves app in .signedOut state with empty data

**Preconditions:** Two connections signed in.  
**When:** Both are signed out sequentially.  
**Then:**
- Aggregated `HubberData` is empty (`incoming: [], outgoing: [], drafts: []`).
- No active scheduler tasks remain.
- No Keychain items remain (both tokens deleted).

**Automation layer:** Unit. **Automatable now.**

---

### Area I — Per-Connection Error, Offline, and Rate-Limit

---

#### MC-ERR-01: Network failure on connection A leaves B's data intact

**Preconditions:** Both connections have previously-fetched data.  
**When:** Connection-A's provider throws `URLError(.notConnectedToInternet)`.  
**Then:**
- Connection-A's `incomingError` is set to a user-facing string.
- Connection-B's data is re-fetched and replaces B's stale items (not A's).
- Aggregated `HubberData` contains B's fresh items and A's last-good items (or empty if never fetched).
- No crash.

**Automation layer:** Unit/Integration — `MockURLProtocol` failing for A's token pattern, succeeding for B's. **Automatable now.**

---

#### MC-ERR-02: Rate-limit backoff is scoped to the offending connection

**Preconditions:** Connection-A receives `GitHubAuthError.rateLimited(retryAfter: 900)`. Connection-B is healthy.  
**When:** Both schedulers compute next interval.  
**Then:**
- Connection-A's scheduler uses 900 s interval.
- Connection-B's scheduler uses its normal interval (30 s / 60 s / 300 s depending on context).
- `rateLimitedUntil` is stored in connection-A's state only.

**Automation layer:** Unit — `RefreshCadence.interval(for: RefreshContext(isRateLimited: true))` returns 900 s; verify isolation. **Automatable now.**

---

#### MC-ERR-03: 401 on connection A's token triggers sessionExpired without sign-out loop propagation

**Preconditions:** Connection-A token becomes invalid mid-session; GitHub returns 401.  
**When:** Connection-A's fetch catches `GitHubAuthError.badCredentials`.  
**Then:**
- Connection-A transitions to `.sessionExpired(login: "personal")`.
- Re-auth prompt is shown for connection-A only.
- Connection-B continues fetching normally.
- No infinite retry loop.

**Automation layer:** Unit — `MockURLProtocol` returning 401 for A's token; verify state transition using `HubberStore.authState(afterRefreshError:signedInLogin:)` (already `nonisolated static` in `GitHubAuth.swift` line 694). **Automatable now.**

---

#### MC-ERR-04: GraphQL partial error (data + errors[]) does not corrupt B's data

**Preconditions:** Connection-A's GraphQL response contains a `"data"` dict AND an `"errors"` array (FORBIDDEN on one field).  
**When:** `GitHubProvider.graphQL()` receives the mixed response.  
**Then:**
- Connection-A degrades gracefully (e.g. `additions: 0`, `files: 0` for the affected PR).
- Connection-B's response is unaffected.
- No throw; partial data is returned.

**Automation layer:** Integration — `MockURLProtocol` returning a JSON fixture with both `"data"` and `"errors"` keys. Asserts that `fetchIncomingReviews` returns non-nil items with zero-defaulted fields. **Automatable now** (pattern from `GitHubProviderTests.swift`).

---

### Area J — Provider-Switcher UI Stub (#31)

---

#### MC-UI-01: Provider-switcher entry for GitLab is visible but disabled before #60 ships

**Preconditions:** App built without GitLab provider; feature flag for #60 is off.  
**When:** User opens the "Add connection" sheet.  
**Then:**
- A GitLab row/button exists in the UI.
- It is rendered as disabled (non-interactive).
- No crash on render.

**Automation layer:** E2E-Manual — Xcode UI test asserting `isEnabled == false` on the GitLab button identifier. Needs real app bundle. **Needs E2E / app target.**

---

#### MC-UI-02: Tapping a disabled provider entry does not navigate or crash

**Preconditions:** GitLab button exists and is disabled.  
**When:** User taps the disabled GitLab entry.  
**Then:**
- No navigation occurs.
- No crash.
- No network request is made.

**Automation layer:** E2E-Manual. **Needs real app target.**

---

#### MC-UI-03: Provider-switcher shows correct icon and label for each supported provider

**Preconditions:** GitHub and GitLab entries rendered.  
**When:** Provider picker list is displayed.  
**Then:**
- GitHub row shows the GitHub octocat icon and "GitHub" label.
- GitLab row shows the GitLab tanuki icon and "GitLab" label.
- GHES entry (if shown) includes the host URL.

**Automation layer:** E2E-Manual / snapshot test. **Needs real app target.**

---

### Area K — GitLab Provider Protocol Conformance

---

#### MC-GL-01: GitLabProvider conforms to CodeHostProvider

**Preconditions:** `GitLabProvider` class exists.  
**When:** Compiled.  
**Then:** Zero compiler errors; `GitLabProvider` satisfies all three `CodeHostProvider` requirements: `fetchIncomingReviews`, `fetchOutgoingPullRequests`, `fetchDraftPullRequests`.

**Automation layer:** Unit / compile-time — a protocol-conformance assertion test. **Automatable now** once class exists.

---

#### MC-GL-02: GitLab Merge Requests map to IncomingReview

**Preconditions:** GitLab REST/GraphQL response fixture with open MRs where the viewer is a reviewer.  
**When:** `GitLabProvider.fetchIncomingReviews(accessToken:viewerLogin:mode:)` parses the fixture.  
**Then:**
- Each MR maps to an `IncomingReview` with:
  - `id` = stable identifier (e.g. `"gl-mr-<iid>"` or the global ID).
  - `repo` = `"namespace/project"`.
  - `number` = the MR IID.
  - `title` = MR title.
  - `url` = the MR web URL.
  - `sloClockStart` = `max(reviewRequestedAt, readyForReviewAt)` equivalent (MR `created_at` or `reviewer_added_at`).
  - `additions`, `deletions`, `files` populated from diff stats.

**Automation layer:** Unit — fixture JSON, `MockURLProtocol`, assert `IncomingReview` fields. **Automatable now** once provider exists.

---

#### MC-GL-03: GitLab pipelines map to PullRequestCI

**Preconditions:** MR with pipeline status `success` / `failed` / `running` / `created`.  
**When:** Provider parses the pipeline status.  
**Then:**
- `success` → `.passing`
- `failed` → `.failing`
- `running` → `.running`
- `created` / `pending` → `.pending`
- Unknown status → `.pending` (safe default)

**Automation layer:** Unit — parameterised test over the mapping table. **Automatable now** once provider exists.

---

#### MC-GL-04: GitLab free-tier approval rules map to 0 required approvals

**Preconditions:** MR on a free-tier GitLab.com project (no approval rules configured).  
**When:** Provider parses the MR.  
**Then:**
- `OutgoingReview.requiredApprovals == 0` (or 1 as a safe default if the field is absent).
- No crash on absent `approval_rules` field.

**Automation layer:** Unit — fixture with no `approval_rules` key. **Automatable now** once provider exists.

---

#### MC-GL-05: GitLab Premium approval rules map to requiredApprovals correctly

**Preconditions:** MR with `approval_rules[0].approvals_required = 2`.  
**When:** Provider parses the approval rules.  
**Then:** `OutgoingReview.requiredApprovals == 2`.

**Automation layer:** Unit — fixture with `approval_rules` array. **Automatable now** once provider exists.

---

#### MC-GL-06: GitLab unresolved discussions map to OutgoingReview.unresolved

**Preconditions:** MR with 3 unresolved discussions.  
**When:** Provider parses discussions.  
**Then:** `OutgoingReview.unresolved == 3`.

**Automation layer:** Unit — fixture with `user_notes_count` or discussions array. **Automatable now** once provider exists.

---

#### MC-GL-07: GitLab reviewer states map to ReviewerState

**Preconditions:** MR with reviewer A in `APPROVED`, reviewer B in `REQUESTED_CHANGES`, reviewer C in `UNREVIEWED`.  
**When:** Provider parses reviewer states.  
**Then:**
- Reviewer A → `.approved`
- Reviewer B → `.changesRequested`
- Reviewer C → `.pending`

**Automation layer:** Unit — parameterised. **Automatable now** once provider exists.

---

#### MC-GL-08: GitLabProvider sends tokens only to the correct GitLab host

**Preconditions:** `GitLabProvider` configured for `gitlab.com`. A GHES GitHubProvider configured for `github.enterprise.acme.com`.  
**When:** Both providers make API calls.  
**Then:**
- GitLab token appears only in requests to `gitlab.com` domain.
- GitHub token appears only in requests to `github.enterprise.acme.com` domain.
- No cross-host token leakage (checked via `MockURLProtocol.lastRequest.allHTTPHeaderFields`).

**Automation layer:** Integration — `MockURLProtocol` intercepts all requests; assert per-request auth header matches expected token for that host. **Automatable now** once providers are injectable.

---

#### MC-GL-09: Self-managed GitLab instance base URL is configurable

**Preconditions:** Connection configured with `baseURL = "https://gitlab.intra.acme.com"`.  
**When:** Provider constructs API requests.  
**Then:** All requests use `https://gitlab.intra.acme.com/api/v4/...` (or GraphQL equivalent).

**Automation layer:** Unit — assert `MockURLProtocol.lastRequest.url?.host == "gitlab.intra.acme.com"`. **Automatable now** once `GitLabProvider` accepts a `baseURL` parameter.

---

### Area L — Cross-Provider Mixing

---

#### MC-MIX-01: GitHub and GitLab incoming reviews aggregated in a single unified list

**Preconditions:** GitHub connection returns 2 `IncomingReview` items. GitLab connection returns 1.  
**When:** Aggregation runs.  
**Then:**
- `HubberData.incoming.count == 3`.
- List sorted by `sloClockStart` ascending (oldest / most urgent first) regardless of provider.

**Automation layer:** Unit — two stub providers (one per provider type). **Automatable now** once aggregation layer exists.

---

#### MC-MIX-02: SLO clocks are independent across providers

**Preconditions:** GitHub item was assigned 6h ago (past a 4h SLO). GitLab item was assigned 1h ago.  
**When:** `AttentionState.hasUrgentSLO(data:settings:)` is evaluated.  
**Then:** Returns `true` (due to the GitHub item being past SLO), not `false` (GitLab item is still green).

**Automation layer:** Unit. **Automatable now.**

---

#### MC-MIX-03: Notification baselines are scoped per connection, not per provider type

**Preconditions:** GitHub connection baseline has `incomingIDs = {"gh-pr-1"}`. GitLab connection baseline has `incomingIDs = {}`.  
**When:** GitLab returns new MR `"gl-mr-42"`.  
**Then:**
- One `newReview` notification fires for `"gl-mr-42"`.
- GitHub baseline is not mutated.

**Automation layer:** Unit — two `NotificationDiffer.events` calls (one per connection baseline). **Automatable now.**

---

#### MC-MIX-04: Badge count correctly aggregates attention items across GitHub and GitLab

**Preconditions:** GitHub: 1 incoming review. GitLab: 1 outgoing with failing pipeline (CI `.failing`).  
**When:** Badge attention count is computed.  
**Then:** Attention count == 2.

**Automation layer:** Unit — `AttentionState` receives aggregated `HubberData` with items from both providers. **Automatable now.**

---

## 4. Test Data and Environment Matrix

### 4.1 Account Fixtures

| Fixture ID | Type | Host | Auth method | Notes |
|---|---|---|---|---|
| `github-personal` | GitHub.com personal | github.com | PAT (dev file store) or device-flow spy | Primary single-tenant regression baseline |
| `github-work` | GitHub.com work | github.com | PAT (dev file store) or device-flow spy | Same host, second account — collision test |
| `github-ghes` | GHES | github.enterprise.acme.com | PAT | Base-URL routing tests; requires `providerAllowlist` to include the host |
| `gitlab-cloud` | GitLab.com | gitlab.com | OAuth device-flow or PAT | GitLab provider conformance |
| `gitlab-selfmanaged` | GitLab self-managed | gitlab.intra.acme.com | OAuth or PAT | Base-URL routing for GitLab |

### 4.2 Token Fixtures (Unit Tests)

```swift
// Use SpyTokenStore (from HubberStoreProviderPolicyTests) — pre-load with:
let freshToken = GitHubStoredToken(
    accessToken: "ghs_A1B2C3",
    accessTokenExpiresAt: Date().addingTimeInterval(3600),
    refreshToken: "ghr_R1R2R3",
    refreshTokenExpiresAt: Date().addingTimeInterval(30 * 24 * 3600),
    tokenType: "bearer",
    login: "personal"
)
let expiredToken = GitHubStoredToken(
    accessToken: "ghs_EXPIRED",
    accessTokenExpiresAt: Date().addingTimeInterval(-1),
    refreshToken: "ghr_VALID",
    refreshTokenExpiresAt: Date().addingTimeInterval(30 * 24 * 3600),
    tokenType: "bearer",
    login: "personal"
)
let noRefreshToken = GitHubStoredToken(
    accessToken: "ghs_NOREFRESH",
    accessTokenExpiresAt: Date().addingTimeInterval(-1),
    refreshToken: nil,
    refreshTokenExpiresAt: nil,
    tokenType: "bearer",
    login: "work"
)
```

### 4.3 Mock HTTP Fixtures

Extend `MockURLProtocol` handler dispatch to branch on `request.url?.host` and `request.value(forHTTPHeaderField: "Authorization")`, enabling per-connection response stubs in the same test.

### 4.4 `InMemoryManagedPreferences` Combinations

| Test scenario | Managed prefs dict |
|---|---|
| Personal GitHub blocked | `[ManagedKey.allowPersonalGitHub: false]` |
| GHES-only allowlist | `[ManagedKey.providerAllowlist: ["github.enterprise.acme.com"]]` |
| Both github.com and GHES | `[ManagedKey.providerAllowlist: ["github.com", "github.enterprise.acme.com"]]` |
| GitLab not allowed | `[ManagedKey.providerAllowlist: ["github.com"]]` |
| SLO forced off | `[ManagedKey.sloEnabled: false]` |

### 4.5 `UserDefaults` Isolation

All tests use a unique suite name (`UserDefaults(suiteName: "TestCase-\(UUID())")`) and call `defaults.removePersistentDomain(forName:)` in `tearDown`. This pattern already exists in `HubberStoreProviderPolicyTests.swift`.

---

## 5. Coverage Traceability

| Test Area | Behaviors Covered |
|---|---|
| A. Connection lifecycle | Sign-in flow per connection; state machine isolation; session restore for N connections; GitLab OAuth |
| B. Token-storage isolation | Keychain key uniqueness; no overwrite on second account; per-connection delete; token refresh scoping |
| C. Data aggregation and dedup | Union of items; node-ID dedup; partial failure isolation; cross-account dedup |
| D. Per-connection refresh scheduling | Independent schedulers; rate-limit scoping; SLO cadence per connection; sleep/wake broadcast |
| E. Per-connection notification baselines | Snapshot path uniqueness; cross-connection false-fire prevention; restart dedup; sign-out cleanup |
| F. Badge and SLO aggregation | Attention count summation; dedup contribution; per-item SLO; isAllGreen logic |
| G. Settings, MDM, provider allowlist | `allowPersonalGitHub` enforcement; allowlist host matching; GHES routing; GitLab host policy; MDM forced settings |
| H. Sign-out isolation | Data isolation; cache invalidation scoping; scheduler stop scoping; full-sign-out empty state |
| I. Errors, offline, rate-limit | Per-connection error state; partial aggregation; rate-limit backoff scoping; 401 sessionExpired isolation; GraphQL partial data |
| J. Provider-switcher UI stub | Disabled state; no-crash on tap; icon/label rendering |
| K. GitLab protocol conformance | All three `CodeHostProvider` methods; MR → canonical model mapping; CI mapping; approval rules; unresolved discussions; reviewer states; self-managed base URL |
| L. Cross-provider mixing | Unified list aggregation; independent SLO clocks; per-connection notification baselines; cross-provider badge aggregation |

---

## 6. Phasing

### Phase 1 — Automate-First (cheap unit/integration; no real accounts)

These stories are executable against stub/spy infrastructure today or as soon as the multi-connection refactor introduces the required protocols. All are tagged **Automatable now** in Section 3.

Priority order (M6 acceptance gate — must pass before merging M6):

| Story ID | Rationale |
|---|---|
| MC-TOKEN-01 | Highest-risk regression: Keychain key collision silently corrupts credentials |
| MC-TOKEN-02 | Sign-out must not delete the wrong token |
| MC-AUTH-02 | Second account must not disrupt the first |
| MC-AUTH-04 | Session restore must boot all connections |
| MC-NOTIF-01 | Snapshot file collision would corrupt baselines and refire stale notifications |
| MC-NOTIF-02 | Cross-connection notification false-fire would degrade trust |
| MC-SIGNOUT-02 | Cache invalidation on wrong connection leaks previous-user data |
| MC-SCHED-02 | Rate-limit propagation across connections degrades the healthy connection |
| MC-AGG-02 | Dedup failure causes double notifications and incorrect badge count |
| MC-AGG-05 | Partial failure must not corrupt aggregated state |
| MC-ERR-02 | Rate-limit isolation is user-visible |
| MC-MDM-01 | Policy enforcement is a hard security requirement |
| MC-GL-01 | Protocol conformance is the minimum bar for GitLab provider |
| MC-GL-02 | Incoming review mapping is the first user-visible GitLab value |
| MC-GL-03 | CI mapping drives the badge; wrong mapping misleads the user |

### Phase 2 — GitLab Provider Unit Suite

Once `GitLabProvider` is implemented:

- MC-GL-04 through MC-GL-09 (all GitLab provider conformance stories)
- MC-MIX-01 through MC-MIX-04 (cross-provider mixing)

### Phase 3 — E2E and Manual

After the Xcode app target is available (prerequisite documented in PRD §Architecture §6):

- MC-UI-01, MC-UI-02, MC-UI-03 (provider-switcher UI)
- Full account E2E with two real GitHub PATs in CI (separate secret-holding environment)
- Manual: GitLab.com with Premium approval rules (requires Premium project fixture)
- Manual: GHES with a real GHES instance or GHES simulator

### Continuous Regression

All Phase 1 unit/integration tests must run on every PR targeting `main` and be green before merge (aligns with the "Verify CI before merging" memory note). The CI runner must use `macos-26` (not `macos-latest`) per the existing CI constraint documented in `hubber-ci-macos-26-toolchain.md`.
