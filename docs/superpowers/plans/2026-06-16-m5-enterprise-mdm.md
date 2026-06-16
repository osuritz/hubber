# M5 — Enterprise / MDM Implementation Plan

> Branch: `feat/m5-enterprise-mdm` (off `main`). TDD task-by-task. Commit after each green task (`swift build && swift test && make lint`). One PR → main; verify CI green on `macos-26` before squash-merge.

**Goal:** Make Hubber deployable and lockable fleet-wide by IT. Every PRD "lockable key" is actually enforced (and unit-tested), the provider allowlist gates sign-in, telemetry has user + MDM kill-switches, and there's an MDM-deployable `.pkg` plus an IT deployment guide.

**Issues:** #52 (document `com.hubber.app` managed domain + all lockable keys), #53 (enforce managed preferences in `SettingsStore` for **all** lockable keys), #54 (provider allowlist hidden from auth UI + enforced at connection time), #55 (IT deployment guide + sample Jamf/Kandji/Mosyle profiles), #56 (MDM-compatible pkg installer).

---

## Coordinator decisions (do not relitigate)

1. **`com.hubber.app` is the intentional managed-preferences domain** — deliberately decoupled from the app bundle id (`com.osuritz.hubber`) so a *single* configuration profile works across both build variants (Standard + MAS) and survives bundle-id changes. macOS forced/managed preferences are keyed by whatever domain string the config profile declares (`/Library/Managed Preferences/<user>/<domain>.plist`), so reading from `com.hubber.app` is correct. **Keep it.** Document the rationale; do not "fix" it to the bundle id.
2. **Introduce an injectable `ManagedPreferences` seam.** `SettingsStoreTests` notes `CFPreferencesAppValueIsForced` cannot be forced in unit tests — so today the entire MDM enforcement path is untestable. Wrap the CF calls behind a protocol with a real `CFManagedPreferences` impl and an in-memory fake for tests. This is the foundation that makes #53 verifiable.
3. **Managed-domain key names are the IT-facing contract → they must match the PRD table exactly.** Reconcile the one mismatch: PRD documents `sloEnabled`, but the code's UserDefaults/lock key is `reviewSLOEnabled`. Separate the two concerns — managed-domain key = PRD name; UserDefaults persistence key may stay as-is to avoid migrating existing users' data. Centralize the mapping in one registry so code and docs can't drift.
4. **Forced values are resolved at launch** (CFPreferences re-reads on next launch). Document this; do not build a live-reload mechanism for M5.
5. **Telemetry kill-switches are real and wired:** `analyticsEnabled` gates `TelemetryDeckSink.initialize()`; `crashReportingEnabled` gates `MXMetricManager.shared.add(...)`. Both also lockable via MDM and toggleable by the user in a new Privacy section. `store.settings` (owned by `HubberStore`) is available in the AppDelegate, so gate there.
6. **Provider allowlist (#54)** is enforced in two layers (defense in depth): the sign-in UI disables the button + explains when blocked, AND `HubberStore.startSignIn()` refuses to start the device flow when policy blocks. Today only `github.com` (personal) exists, so the practical gate is `allowPersonalGitHub` + an optional host `providerAllowlist`.
7. **pkg signing is deferred** (needs a paid Developer ID Installer cert). M5 ships an **unsigned** `.pkg` that installs `Hubber.app` to `/Applications`; the script exposes `HUBBER_INSTALLER_SIGN_IDENTITY` for later. The IT guide states that silent MDM deployment requires a signed pkg (M4b/paid account); unsigned is fine for manual/`installer`/testing.

---

## Lockable keys — the authoritative contract (matches PRD §Enterprise/MDM)

| Managed key (PRD / profile) | Type | UserDefaults key (persistence) | SettingsStore property |
|---|---|---|---|
| `sloEnabled` | Bool | `reviewSLOEnabled` | `sloEnabled` |
| `sloWindowHours` | Int | `sloWindowHours` | `sloHours` |
| `sloDisplay` | String | `sloDisplay` | `sloDisplay` |
| `badgeMode` | String | `badgeMode` | `badgeMode` |
| `incomingMode` | String | `incomingMode` | `incomingMode` |
| `unresolvedThreadMode` | String | `unresolvedThreadMode` | `unresolvedMode` |
| `rowDensity` | String/Int | `rowDensity` | `rowDensity` |
| `analyticsEnabled` | Bool | `analyticsEnabled` | `analyticsEnabled` *(new)* |
| `crashReportingEnabled` | Bool | `crashReportingEnabled` | `crashReportingEnabled` *(new)* |
| `notificationsEnabled` | Bool | `notificationsEnabled` | `notificationsEnabled` |
| `defaultNotificationEvents` | Array<String> (csv) | per-type `notify*` | `enabledNotificationTypes` |
| `providerAllowlist` | Array<String> | `providerAllowlist` | `providerAllowlist` *(new)* |
| `allowPersonalGitHub` | Bool | `allowPersonalGitHub` | `allowPersonalGitHub` *(new)* |

> `rowDensity` is currently persisted as an Int rawValue. Accept both an Int and a String managed value (map string `compact|normal|spacious` → rawValue) so IT can write a human-readable profile; document the accepted form.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/Hubber/Core/ManagedPreferences.swift` | `ManagedPreferences` protocol + `CFManagedPreferences` (domain `com.hubber.app`) + `ManagedKey` registry |
| Modify | `Sources/Hubber/Core/SettingsStore.swift` | Inject `ManagedPreferences`; route all forced reads through it; reconcile `sloEnabled`; add `analyticsEnabled`/`crashReportingEnabled`/`providerAllowlist`/`allowPersonalGitHub`; fix `isLocked` for per-type notifications + composite key |
| Create | `Sources/Hubber/Core/ProviderAccessPolicy.swift` | Pure policy: can github.com (personal) connect, given allowlist + allowPersonalGitHub |
| Modify | `Sources/Hubber/GitHubAuth.swift` | Enforce policy in `startSignIn()` (defense in depth); expose policy for views |
| Modify | `Sources/Hubber/SignInScreen.swift` | Disable "Sign in with GitHub" + restricted-by-org message when blocked |
| Modify | `Sources/Hubber/GitHubAuthSettingsView.swift` | Same restricted treatment in the signed-out settings row |
| Modify | `Sources/Hubber/HubberSettingsView.swift` | New "Privacy" section: analytics + crash-reporting toggles (honor `isLocked`) |
| Modify | `Sources/Hubber/main.swift` | Gate `TelemetryDeckSink.initialize()` and `MXMetricManager.add` on `store.settings` |
| Create | `Tests/HubberTests/ManagedPreferencesTests.swift` | Forced wins / fallback for every type via the fake |
| Modify | `Tests/HubberTests/SettingsStoreTests.swift` | Inject fake managed prefs; forced-key enforcement for all lockable keys; `isLocked` mapping; per-type lock under composite/master; sloEnabled reconciliation |
| Create | `Tests/HubberTests/ProviderAccessPolicyTests.swift` | Allow/block matrix |
| Modify | `Tests/HubberTests/HubberAuthStateTests.swift` (or new) | `startSignIn()` blocked-by-policy does not start device flow |
| Create | `Scripts/make-pkg.sh` | Build unsigned (optionally signed) `.pkg` that installs to `/Applications` |
| Modify | `Makefile` | `pkg` target |
| Create | `docs/enterprise/managed-preferences.md` | #52: domain + full lockable-key reference + rationale + "applied at launch" |
| Create | `docs/enterprise/it-deployment-guide.md` | #55: deploy via MDM, install pkg, push profile; Jamf/Kandji/Mosyle notes |
| Create | `docs/enterprise/sample-profiles/hubber-managed.mobileconfig` | #55: ready-to-edit configuration profile keyed to `com.hubber.app` |

---

## Task 1 — `ManagedPreferences` seam + `ManagedKey` registry (TDD)

Create `ManagedPreferences.swift`:

```swift
protocol ManagedPreferences: Sendable {
    func isForced(_ key: String) -> Bool
    func value(_ key: String) -> Any?
}

struct CFManagedPreferences: ManagedPreferences {
    static let domain = "com.hubber.app" as CFString
    func isForced(_ key: String) -> Bool { CFPreferencesAppValueIsForced(key as CFString, Self.domain) }
    func value(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, Self.domain) }
}
```

Add a `ManagedKey` registry (single source of truth) mapping each setting to its managed key (PRD name) and, where different, its UserDefaults persistence key. Test fixture `InMemoryManagedPreferences` (in Tests) backed by `[String: Any]` (presence ⇒ forced).

**Tests (`ManagedPreferencesTests`):** fake returns forced bool/int/double/string/array when present; `isForced` false + `value` nil when absent. Commit: `feat(mdm): injectable ManagedPreferences seam + managed-key registry (#52, #53)`.

## Task 2 — Route `SettingsStore` through the seam + reconcile keys (TDD)

Inject `managed: ManagedPreferences = CFManagedPreferences()` into `SettingsStore.init`. Refactor the static `string/bool/double/int` helpers to take/use the injected `managed` instead of direct `CFPreferences*` calls. Add an array helper for `providerAllowlist`/`defaultNotificationEvents`. Make `isLocked(_:)` consult `managed.isForced` and map UI/UserDefaults keys → managed keys (esp. `reviewSLOEnabled` → `sloEnabled`).

**Tests (extend `SettingsStoreTests`):** construct `SettingsStore(defaults:, managed: fake)`; for **every** lockable key, a forced managed value overrides UserDefaults and the hardcoded default; `isLocked` returns true for the forced key (including `isLocked("reviewSLOEnabled")` true when `sloEnabled` is forced). Keep existing non-forced tests green. Commit: `feat(mdm): enforce all lockable managed keys via the seam; reconcile sloEnabled (#53)`.

## Task 3 — Notification lock propagation (TDD)

When `defaultNotificationEvents` is forced **or** `notificationsEnabled` is forced, the per-type notification toggles must report locked. Update the lock logic so `isLocked` for a `notify*` key (and the master) returns true if its own managed key is forced, or `defaultNotificationEvents` is forced, or `notificationsEnabled` is forced. Also resolve per-type *values* from the forced composite (already present) — keep that.

**Tests:** with the fake forcing `defaultNotificationEvents`, per-type `isLocked` is true and `enabledNotificationTypes` matches the forced set; with `notificationsEnabled` forced false, master + per-type locked and `enabledNotificationTypes` empty. Commit: `feat(mdm): propagate managed notification locks to per-type toggles (#53)`.

## Task 4 — Telemetry kill-switches: keys + gating + Privacy UI (TDD + wiring)

Add `analyticsEnabled` (default **true**) and `crashReportingEnabled` (default **true**) to `SettingsStore` (managed-lockable, persisted). In `main.swift applicationDidFinishLaunching`, gate: `if store.settings.analyticsEnabled { TelemetryDeckSink.initialize() }` and `if store.settings.crashReportingEnabled { MXMetricManager.shared.add(metricSubscriber) }` (and only `remove` what was added). Add a **Privacy** `SettingsSection` to `HubberSettingsView` with two toggles ("Share anonymous usage analytics", "Send crash & hang reports"), each `.disabled(settings.isLocked(...))`, mirroring the existing notification-row layout (left label, right switch).

**Tests:** defaults true; persistence; forced-false (fake) wins for both. Telemetry gating itself is build + manual-verify (note in PR). Commit: `feat(privacy): analytics + crash-reporting kill-switches, MDM-lockable + user toggles (#53)`.

## Task 5 — `ProviderAccessPolicy` (TDD, pure)

Create a pure policy:

```swift
struct ProviderAccessPolicy: Sendable {
    let allowPersonalGitHub: Bool      // default true
    let allowlist: [String]            // default [] == no host restriction
    var canConnectGitHubDotCom: Bool { ... }   // github.com personal
    var blockedReason: String? { ... }          // user-facing when blocked
}
```

Rules: empty allowlist + `allowPersonalGitHub == true` → allowed. `allowPersonalGitHub == false` → github.com blocked. Non-empty allowlist that does not contain `github.com` (and personal not separately allowed) → blocked. Allowlist containing `github.com` → allowed. `SettingsStore` exposes `providerAllowlist: [String]` and `allowPersonalGitHub: Bool` (managed-lockable) and a computed `providerAccessPolicy`.

**Tests (`ProviderAccessPolicyTests`):** the full allow/block matrix above. Commit: `feat(allowlist): pure ProviderAccessPolicy + SettingsStore keys (#54)`.

## Task 6 — Enforce allowlist in auth UI + at connection time (TDD + wiring)

In `HubberStore.startSignIn()`, first check `settings.providerAccessPolicy.canConnectGitHubDotCom`; if blocked, set `authState = .error(<blockedReason>)`, log it, and **return before** `authService.startDeviceFlow()` (defense in depth). In `SignInScreen` and `GitHubAuthSettingsView` signed-out states, when blocked: disable the "Sign in with GitHub" button and show "Sign-in is restricted by your organization." instead of/below the button.

**Tests:** a `HubberStore`-level test with an injected spy `authService` asserts that, under a blocking policy, `startSignIn()` does **not** call `startDeviceFlow()` and sets a blocked/error state; under an allowing policy it proceeds. Commit: `feat(allowlist): enforce provider policy in sign-in UI and at connection time (#54)`.

## Task 7 — #52/#55 docs + sample profiles

- `docs/enterprise/managed-preferences.md` (#52): managed domain `com.hubber.app`; the full lockable-key table (must match the registry from Task 1, value formats + examples); rationale for domain ≠ bundle id; "values applied at launch"; how locked controls render (visible, disabled).
- `docs/enterprise/it-deployment-guide.md` (#55): end-to-end IT flow — deploy the pkg via MDM, push a custom-settings configuration profile targeting `com.hubber.app`, verify in `/Library/Managed Preferences`. Per-tool notes for **Jamf** (Application & Custom Settings / "External Applications" with a custom domain), **Kandji** (Custom Profile), **Mosyle** (Custom Profile / Custom Command). Note that silent pkg deploy requires a signed pkg (M4b).
- `docs/enterprise/sample-profiles/hubber-managed.mobileconfig` (#55): a valid configuration profile (`PayloadType` payload for domain `com.hubber.app`) with a representative set of forced keys (e.g. `sloWindowHours`, `notificationsEnabled`, `analyticsEnabled=false`, `allowPersonalGitHub=false`, `providerAllowlist`), with placeholder UUIDs and inline comments on what to edit.

No code; `swift build`/tests unaffected. Commit: `docs(enterprise): managed-preferences reference + IT deployment guide + sample profile (#52, #55)`.

## Task 8 — #56 MDM-compatible pkg installer

`Scripts/make-pkg.sh`: ensure `Hubber.app` exists (build via `make app` if missing), then `pkgbuild --install-location /Applications --component "Hubber.app" --identifier com.osuritz.hubber.pkg --version <VERSION> dist/Hubber-component.pkg`, then `productbuild --package dist/Hubber-component.pkg dist/Hubber.pkg` (or a distribution XML). Sign only if `HUBBER_INSTALLER_SIGN_IDENTITY` is set (`productsign`/`--sign`); default unsigned. Verify with `pkgutil --check-signature` (informational) and `installer -pkg dist/Hubber.pkg -target CurrentUserHomeDirectory -dumplog` dry inspection / `pkgutil --payload-files`. `Makefile`: add `pkg: app` (+ `.PHONY`). 

**Verify:** `make pkg` produces `dist/Hubber.pkg`; `pkgutil --payload-files dist/Hubber.pkg` lists `Applications/Hubber.app/...`. Commit: `feat(dist): MDM-compatible pkg installer + make pkg target (#56)`.

---

## Acceptance (whole PR)
- `swift build` clean; `swift test` all pass (existing + new managed-prefs/policy/auth tests); `make lint` 0; `make format` idempotent.
- Every PRD lockable key is enforced through the seam **and** covered by a forced-value unit test.
- `sloEnabled` reconciled; per-type notification locks propagate; analytics/crash kill-switches gate the real sinks; allowlist blocks sign-in in UI and at connection time.
- `make pkg` builds `dist/Hubber.pkg` installing to `/Applications`; enterprise docs + sample profile present and consistent with the code registry.
- Open PR → main; **watch CI green on `macos-26` before squash-merge.**

## Self-Review Checklist
- [ ] `ManagedPreferences` seam injected; no direct `CFPreferences*` left in `SettingsStore`
- [ ] All 13 registry keys: forced value overrides defaults + UserDefaults (unit-tested via fake)
- [ ] `isLocked("reviewSLOEnabled")` true when `sloEnabled` forced; views still compile against their keys
- [ ] Per-type notification toggles lock under forced `defaultNotificationEvents` / `notificationsEnabled`
- [ ] Telemetry + MetricKit only start when their setting is on; Privacy toggles honor `isLocked`
- [ ] `startSignIn()` cannot start device flow when policy blocks; UI shows restricted message
- [ ] Unsigned pkg installs to `/Applications`; signing hook present but optional
- [ ] Docs’ key table matches the code registry exactly (no drift); domain rationale documented
