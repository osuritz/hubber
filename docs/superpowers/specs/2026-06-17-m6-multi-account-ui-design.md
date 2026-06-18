# M6 — Multi-Account UI Design (#61)

> Design spec. The implementation plan follows via `superpowers:writing-plans`. Branch: `feat/m6-multi-account-ui`.

## Goal

Let a single user run **multiple code-host accounts** in Hubber at once — personal GitHub, a company/EMU GitHub account, a self-hosted GitHub Enterprise Server, and GitLab — surfaced as **one unified menu-bar inbox** with per-account show/hide toggles. This is the capstone of M6 (epic #80): it wires the multi-connection rails (#81/#85), the GitLab provider (#60), and GHES host support (#82) to a real add-account UI, and lands the deferred items those milestones left for #61.

## Context

The backend is already a coordinator over `[Connection]`:
- `HubberStore.addConnection(id:provider:authService:tokenStore:snapshotStore:scheduler:)`, `removeConnection`, `signOut`, `restoreAllConnections()`, and a `ConnectionRegistry` (persists the connection-id list).
- `ConnectionID = (provider, host, login)` keys per-connection token/snapshot storage (no cross-account collision).
- `ConnectionAggregator.aggregate([HubberData])` already merges + dedups across connections; notifications run as one coordinator diff over the union of per-connection baselines.
- Providers are `baseURL`-parameterized (`GitHubProvider(baseURL:)`, `GitLabProvider(baseURL:)`); auth is `baseURL`-parameterized (`GitHubAuthService(baseURL:)`); `ProviderAccessPolicy.canConnect(host:)` exists.

What's missing (this spec): the **add-account UI**, a **PAT credential path** (auth is device-flow-only today), **per-connection host/provider wiring** at add time, **launch-time `restoreAllConnections()`**, the **account menu + visibility toggles**, and **Settings → Accounts** management.

Production today is single-connection: the header (`HubberPopoverView.swift:113`) is a static "GitHub · @login", and the popover branches on `store.authState` forwarded from the one primary connection.

---

## Locked design decisions

### View model
1. **Unified inbox** — all *visible* connections' data merged into one list per tab (rides `ConnectionAggregator`), with **per-account show/hide toggles** (Calendar/Fantastical metaphor) and an **"All accounts"** master toggle.
2. **Visibility filters the aggregate and the menu-bar badge** — the list and badge reflect only visible accounts. Toggling an account off removes its items from both.
3. **No per-row account identity in v1.** The app is read-only (the only action is opening a PR in the browser, which routes by URL), so account identity is informational, never safety-critical; the repo name + PR-number style (`#214` vs `!88`) + the toggles carry it. This keeps merged items free of any account tag (no per-item model change).
   - **Documented fast-follow (not v1):** a 4px full-height account-color strip on each row's leading edge (Calendar color), shown only when 2+ accounts are visible, with the account-color legend in the menu. Failing-CI would drop its left accent and lean on the red badge + row tint (validated to coexist). Adding it later is additive (per-item account color), not a rework.

### Header & account menu
4. **Header account menu = toggle list only** — "All accounts" master + a checkbox per account; it flags an account in error inline (⚠ "Needs attention") but does **not** manage accounts.
5. **Header label (option A):** "All accounts" when all visible; "`<Provider>` · @`<login>`" when exactly one is visible (mirrors today's single-account header); "N of M accounts" for a partial subset.

### Management — Settings → Accounts
6. **All account management lives in Settings**, replacing/expanding today's single sign-out button: a list of accounts each with **Sign out / Remove** and **Re-authenticate** (when in error), plus **"Add account…"**.

### Add-account flow
7. **Provider picker:** GitHub.com · GitHub Enterprise Server · GitLab.
8. **Credential by provider:**
   - **GitHub.com** → device flow (default), **plus a "use a token instead" (PAT) path**. The PAT path covers **EMU/company accounts** (e.g. `@osuritz_LinkedIn`) where org SSO blocks browser OAuth.
   - **GitHub Enterprise Server** → **Server URL + PAT** (Hubber's OAuth app isn't installed on the appliance, so no device flow).
   - **GitLab** → **Server URL (default `https://gitlab.com`, editable for self-managed) + PAT**.
9. **Multiple accounts per provider/host** are supported and isolated, keyed by `ConnectionID (provider, host, login)`. Personal + EMU on github.com coexist with separate tokens.

### Identity resolution
10. After authenticating (device flow or PAT), Hubber **fetches the authenticated user** to resolve the `login` before forming the `ConnectionID` — GitHub `GET /user` (`GitHubAuthService.fetchAuthenticatedUser`), GitLab `currentUser` (new). A PAT with the wrong/blocked scope surfaces as an add-account error, not a silent failure.

### Errors / partial failure
11. A connection in error keeps its **last-good data** in the list (locked #81 rule — baseline never dropped) and is **flagged "Needs attention"** in the menu and Settings. **Re-authenticate**: device-flow accounts re-run sign-in; PAT accounts re-enter their token (Settings).

### Empty / first-run
12. Zero accounts (first run, or after removing the last) → the existing **"Welcome to Hubber"** `SignInScreen`, which now leads into the **provider picker** (rather than going straight to github.com device flow).

### Notifications
13. Notifications fire for **all signed-in accounts regardless of visibility** (a hidden account still alerts on a new failing CI). A **Settings option "Notify for hidden accounts" (default on)** lets the user mute hidden accounts.

### Persistence
14. **Per-account visibility** (the toggle states) is persisted (SettingsStore/UserDefaults, keyed by `ConnectionID`) so the view scope survives restart. Unknown/new connections default to visible.

---

## Architecture & components

Designed as small, independently-testable units with clear interfaces.

### 1. `ConnectionVisibility` (new) — the toggle state
A small `@Published` model (owned by `HubberStore`, persisted via `SettingsStore`) holding the set of hidden `ConnectionID`s. Interface: `isVisible(_:) -> Bool`, `setVisible(_:_:)`, `visibleConnections([Connection]) -> [Connection]`. `recomputeAggregate()` aggregates over `visibility.visibleConnections(connections)` instead of all `connections`. Badge count derives from the already-filtered `data`.

### 2. PAT credential path — `CodeHostAuthServicing` extension
Today `CodeHostAuthServicing` is `refresh` + `fetchAuthenticatedUser`; sign-in is GitHub device-flow only (`GitHubDeviceFlowServicing`). Add a **token-based sign-in seam**:
- `PATAuthServicing` (or a method on `CodeHostAuthServicing`): `signIn(token:) async throws -> (GitHubStoredToken, login)` — stores the PAT as the access token (no refresh token; `canRefresh == false`) and resolves the login via the provider's authenticated-user query.
- **GitHub** PAT: validate via `GET <restBase>/user`.
- **GitLab** PAT: validate via a `currentUser { username }` GraphQL query (new tiny method on `GitLabProvider` or a `GitLabAuthService`).
- Errors map to existing `GitHubAuthError` (`.badCredentials` for 401, `.github(msg)` otherwise) — reuse, do not add cases.

### 3. Per-connection provider/auth wiring (closes the #82/#60 seams)
A **connection factory** that, given a provider kind + host + credential, builds the right `Connection`:
- GitHub.com / GHES → `GitHubProvider(baseURL: host)`, `GitHubAuthService(baseURL: host)`.
- GitLab → `GitLabProvider(baseURL: host)`, GitLab auth.
- Token store / snapshot store / scheduler keyed by `ConnectionID` (existing `makeStore(for:)`).
This factory is passed to `addConnection` (the `provider:`/`authService:` overrides already exist) and to `restoreAllConnections()` (which already accepts a `connectionFactory`). Replaces the current default-to-`GitHubProvider()` behavior so a GitLab/GHES connection actually targets its own host.

### 4. Add-account flow — `AddAccountView` (new)
A self-contained flow surfaced from Settings (sheet or pushed panel):
- **Step 1 — provider picker** (3 options).
- **Step 2 — authenticate**, branching: GitHub.com → reuse `DeviceCodeScreen` (with a "use a token instead" affordance switching to the PAT form) ; GHES/GitLab → a **host + PAT form** (`Server URL`, `Personal access token`, a "Create a token ↗" deep link, Connect button).
- On success: resolve login → `ConnectionID` → `store.addConnection(...)` with the factory-built connection → the new account appears in the menu (visible by default) and Settings list. `ProviderAccessPolicy.canConnect(host:)` is enforced for the chosen host **before** auth starts; a blocked host shows the policy's `blockedReason(host:)`.

### 5. Account menu — `AccountMenuView` (new), wired into the header seam
Replaces the static label at `HubberPopoverView.swift:113` with a `Menu`/popover: "All accounts" master row + a checkbox row per connection (avatar, `<provider> · @login`, ⚠ if in error), bound to `ConnectionVisibility`. The header label renders per decision #5.

### 6. Settings → Accounts — `AccountsSettingsSection` (new)
Replaces the single sign-out control: a list of connections (avatar, identity, error state) with Sign out / Remove / Re-authenticate, and "Add account…" launching `AddAccountView`. Plus the "Notify for hidden accounts" toggle.

### 7. Launch wiring
`main.swift` / `HubberStore` init calls `restoreAllConnections()` (multi-connection path with the connection factory) instead of the legacy single-connection `restoreSession()`. Empty registry → the legacy single-connection/welcome path (back-compat for existing installs and first run).

---

## Key flows

- **Add account:** Settings → "Add account…" → pick provider → (device flow | host+PAT) → resolve login → `addConnection` → visible in menu + Settings.
- **Toggle visibility:** header menu checkbox → `ConnectionVisibility.setVisible` → `recomputeAggregate()` over visible set → list + badge update; persisted.
- **Error → re-auth:** refresh fails (bad creds/expired) → connection flagged, last-good data retained → menu + Settings show ⚠ → user re-authenticates in Settings (device flow re-run, or re-enter PAT).
- **Remove last account:** Settings → Remove → registry empties → popover shows "Welcome to Hubber".

---

## Data / model changes (summary)

- New: `ConnectionVisibility` (+ persistence in `SettingsStore`).
- New: PAT sign-in seam on `CodeHostAuthServicing`; GitLab `currentUser` login-resolution query.
- New: connection factory (provider kind + host + credential → `Connection`).
- New SwiftUI: `AccountMenuView`, `AddAccountView`, `AccountsSettingsSection`.
- Changed: `recomputeAggregate()` filters by visibility; `HubberStore` launch path uses `restoreAllConnections()`; header seam becomes the account menu; Settings sign-out becomes Accounts section.
- New Settings flag: `notifyHiddenAccounts` (default true).
- **No change** to the merged item models (`IncomingReview`/`OutgoingReview`/`DraftReview`) — per decision #3.

## Folded-in deferred work

- **#5** — `ConnectionAggregator.mergeOutgoingSnapshots` conflicting non-pending reviewer-state merge: fix with deterministic "already-observed" semantics + a unit test. Multi-account makes the conflicting-merge path reachable, so it lands here.
- **GitHub Enterprise host enforcement** — `startSignIn`/add-account enforces `canConnect(host:)` for arbitrary hosts (not just github.com).
- **GitLab E2E** — once a GitLab account is addable via this UI, verify the GraphQL field names against the live schema using the user's free gitlab.com PAT (highest-risk: `currentUser.reviewRequestedMergeRequests`, `mergeRequestInteraction.reviewState`, `resolvableDiscussionsCount`). Manual verification step.

## Testing strategy

- **Unit (no account):** `ConnectionVisibility` filtering + persistence; aggregate/badge reflect visibility; PAT sign-in path (mock `MockURLProtocol` — 401 → badCredentials, success → login resolved + token stored, no refresh token); connection factory builds the right provider/host per kind; `canConnect(host:)` enforcement blocks a non-allowlisted host before auth; multi-connection `restoreAllConnections()` rebuilds connections from the registry with correct providers; notifications fire for hidden accounts when `notifyHiddenAccounts` is on and are muted when off; #5 reviewer-state merge determinism.
- **Scheduler/test gotchas:** any test that signs a connection in / refreshes must inject a stub provider + no-op `NotificationDispatching` (real `GitHubProvider`/`UNUserNotificationCenter` hang in the bundle-less xctest host).
- **Manual / app:** add a GitLab account end-to-end (E2E field-name check), add an EMU account via PAT, toggle visibility, force a re-auth, remove the last account → welcome.

## Scope & phasing

This is one design but a large build; the implementation plan should phase it so each phase is green and reviewable:
1. **Backend rails:** `ConnectionVisibility` + PAT sign-in seam + connection factory + `restoreAllConnections()` launch wiring + #5 fix. (Pure unit; a 2nd account becomes technically addable.)
2. **UI:** account menu + visibility toggles + header label; `AddAccountView`; Settings → Accounts; empty-state routing; `notifyHiddenAccounts`.
3. **Verification:** GitLab E2E with a real PAT; EMU-via-PAT manual pass.

**Out of scope (v1):** the per-row account-color strip (documented fast-follow); GHES device-flow (PAT only); OAuth for GitLab/GHES; org-side app registration.

## Open risks

- **GitLab/EMU PAT scopes** — a token with insufficient/blocked scope must fail loudly at add time (handled by the login-resolution validation). Enterprise PAT restrictions are the org's call; Hubber can't work around a disallowed PAT.
- **GitLab GraphQL field accuracy** — still fixture-pinned, not live-verified; the E2E pass (needs the user's PAT) de-risks it.
- **Device-flow "use a token instead" affordance** — must not complicate the common github.com path; keep it a quiet secondary link.
- **MDM policy vs EMU on github.com** — `canConnect(host:)` is host-based, so an org that sets `allowPersonalGitHub == false` would also block a legitimate EMU/company PAT on github.com (same host). The personal-vs-managed distinction on github.com is finer than host granularity; v1 accepts this (the policy targets locking down *personal* github.com), with a possible later refinement to distinguish EMU logins.
