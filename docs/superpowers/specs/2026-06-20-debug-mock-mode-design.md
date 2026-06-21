# Debug Mock Mode — Design

**Date:** 2026-06-20 · **Scope:** A DEBUG-only "mock mode" that renders the popover
against controlled, generated data scenarios with no network, so UI states — especially
20+ PRs + scrolling, plus empty / error / loading / multi-connection — are testable on
demand. **Delivery:** its own PR. Provider-level injection; `HUBBER_MOCK` env var +
Developer-panel picker toggles.

## 1. Goal & motivation

The app's lists come only from the live provider, so data-dependent UI states have never
been exercised under controlled conditions. We want an MSW-style "turn on mocks" capability
to drive the popover through known scenarios — initially to validate long-list (20+) +
scrolling behavior, and going forward for manual QA, screenshots, and deterministic repro.

Non-goal: testing the network/JSON-parsing layer (already covered by the existing
`MockURLProtocol`-based unit tests). Non-goal: shipping any of this in release builds.

## 2. Hard requirements

- **DEBUG-only, no release footprint.** Every mock unit, the `HUBBER_MOCK` env-var read,
  the seed path, and the Developer-panel picker live entirely inside `#if DEBUG`. A release
  build must contain **no** mock code and must **never** read `HUBBER_MOCK`. This matters
  because mock mode bypasses real auth/onboarding — that bypass must not be expressible in a
  shipped binary. Verified two ways: (a) the `#if DEBUG` guards; (b) a plan step that greps
  the release `Hubber.app` binary (`nm`/`strings`) and asserts no `MockMode` / `HUBBER_MOCK`
  symbols are present.
- **Zero behavior change when off.** With mock mode inactive (env unset / `off`), the real
  `ConnectionFactory` → provider → auth path is untouched and the app behaves exactly as
  today.
- **Provider-level.** Mocks are injected at the `CodeHostProvider` seam, not the network.

## 3. Architecture

Three small units under `Sources/Hubber/Debug/`, all `#if DEBUG`:

### 3a. `MockScenario`
```
enum MockScenario: String, CaseIterable { case off, empty, small, large, error, loading, multiConnection }
```
- `init?(env:)` maps the `HUBBER_MOCK` string → scenario (unknown/empty → `off`).
- Each scenario produces a **connection plan**: an ordered list of fake connections, each
  with an identity (provider + host + login) and a **behavior**:
  ```
  enum MockBehavior { case data(HubberData); case error; case loading }
  struct MockConnectionPlan { let id: ConnectionID; let login: String; let behavior: MockBehavior }
  ```
- Plans:
  - `empty` → one connection, `.data` with empty incoming/outgoing/drafts.
  - `small` → one connection, `.data` with ~3 incoming / ~2 outgoing / ~1 draft.
  - `large` → one connection, `.data` with **~25 incoming, ~25 outgoing, ~12 drafts**,
    deterministically varied by index across CI states, reviewer states, SLO colors, and a
    few long / unicode / emoji titles (so scrolling exercises real visual variety).
  - `error` → one connection, `.error`.
  - `loading` → one connection, `.loading`.
  - `multiConnection` → **two** connections — a fake `github.com` account and a fake
    `gitlab.com` account — each `.data` with its own slice, and **one deliberately
    overlapping PR id across the two** so the manual test visibly exercises
    `ConnectionAggregator` dedup + visibility filtering and the multi-account UI (account
    menu, per-connection rows in Settings).
- Data is built from the existing `CodeHostUser` sample factories (`.marisol`, `.tobi`,
  `.kenji`, `.priyanka`, `.ines`) and `Date.hoursAgo(_)`. Generation is **deterministic**
  (index-driven, no randomness) so runs and tests are repeatable.

### 3b. `MockCodeHostProvider: CodeHostProvider`
- Constructed with one `MockBehavior`. Its three `fetch…` methods:
  - `.data(d)` → return the matching slice of `d` (incoming / outgoing / drafts).
  - `.error` → throw a sample `MockError` (drives the per-tab error states).
  - `.loading` → `await` a long, **cancellable** `Task.sleep` (keeps `isRefreshing` true →
    drives `LoadingState`; cancelled when the scenario changes).
- Conforms to the protocol exactly; honors `Task.isCancelled`.

### 3c. `MockMode` (`@MainActor`, `ObservableObject`, singleton `shared`)
- `@Published var scenario: MockScenario` — initial value from `MockScenario(env:)`.
- `var isActive: Bool { scenario != .off }`.
- `func apply(_ scenario:, to store: HubberStore)`:
  1. remove any previously-seeded fake connections from the store;
  2. for each plan entry, add a **signed-in** fake connection — injected
     `MockCodeHostProvider(behavior:)`, an **in-memory token store** (no Keychain/file), a
     fake resolved user/login — via the store's existing inject-provider connection API;
  3. mark onboarding complete (so the app skips onboarding → lands on the popover);
  4. trigger a refresh so the mock data flows through the real
     store → aggregation → popover path.
- Single-connection scenarios are a 1-element plan; `multiConnection` is 2. Both the env
  var and the Dev-panel picker drive `apply(...)`, so **live switching** (incl. between
  single- and multi-connection) works with no relaunch.

## 4. Wiring (all `#if DEBUG`)

- **Startup** (`main.swift` AppDelegate): 
  ```swift
  #if DEBUG
  if MockMode.shared.isActive { MockMode.shared.apply(MockMode.shared.scenario, to: store) }
  else { /* normal restore */ }
  #else
  /* normal restore — the only path compiled in release */
  #endif
  ```
- **Developer panel** (`DeveloperPanelView`): a `Picker` over `MockScenario.allCases` bound
  to `MockMode.shared.scenario`; `.onChange` calls `MockMode.shared.apply(newValue, to: store)`.
- **No release footprint:** the `#else` branch is the only startup path in release; nothing
  references `MockMode` or reads `HUBBER_MOCK`.

## 5. Toggle

Mock mode requires a **DEBUG build** — `make app-dev` (NOT `make app`, which is release and
compiles all of this out). Then:

- `open -n --env HUBBER_MOCK=large Hubber.app` → deterministic startup scenario (for
  screenshots, the 20+ test, future CI). Note: a bare `HUBBER_MOCK=large open Hubber.app`
  does **not** work — `open` launches via LaunchServices and the shell-prefixed var isn't
  inherited; pass it with `open`'s `--env` flag (or run the binary directly:
  `HUBBER_MOCK=large .build/debug/Hubber`). `-n` forces a fresh instance if one is running.
- Developer panel picker → live switch during manual QA (works regardless of launch method).
- Unset / `off` → normal app, real providers.

## 6. Testing

**Automated (pure, deterministic — no UI, no network):**
- `MockScenarioTests`: each scenario's connection plan — count of connections (1 for
  data-shape scenarios, **2** for `multiConnection`), and the generated `HubberData` shape
  (`large` incoming ≥ 20 and outgoing ≥ 20; `empty` all-empty; `small` small). The
  `multiConnection` plan contains the intended overlapping id across its two connections.
- `MockScenario(env:)` mapping: known strings → scenarios; unknown/nil → `off`.
- `MockCodeHostProvider`: `.data` returns the configured slices; `.error` throws.

**Manual (run the app):**
- `HUBBER_MOCK=large` → confirm 20+ scrolls smoothly; this is the signal for whether the
  lists need `LazyVStack` (separate follow-up, below).
- `HUBBER_MOCK=multiConnection` → confirm aggregation/dedup + multi-account UI.
- `empty` / `error` / `loading` → confirm the corresponding states render.
- Documented in the Developer-panel UI and (optionally) a short note in
  `docs/runbooks/` if useful.

## 7. Out of scope / follow-ups

- **`LazyVStack` list hardening** — switching the three tab lists from eager `VStack` to
  `LazyVStack`. This harness is the tool that decides whether it's needed; it ships as a
  **separate PR after this one lands** (explicitly agreed).
- Network-level (true MSW) fixtures, and any mock surface beyond the popover.

## 8. Risks

- **Auth/onboarding bypass leaking into release** — mitigated by the `#if DEBUG` gate + the
  release-binary symbol check (§2).
- **Seeded fake connections colliding with real ones** — mock mode is only entered when
  `isActive`, and `apply` removes prior fake connections before re-seeding; in normal use
  the seed path is never taken.
- **Live-switch races** (e.g. switching scenario mid-`loading`) — the `.loading` sleep is
  cancellable and `apply` removes/replaces connections, so an in-flight mock fetch is
  cancelled on switch.
