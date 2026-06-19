# M7 — Onboarding & First-Run Consent: Design Spec

> **Status:** Approved design (2026-06-19). Drives the M7 implementation plan.
> **Scope:** GitHub issues #101–#107. The last substantive epic before Hubber's v1 public OSS launch.
> **Grounding:** `PRODUCT.md` (v1 = public OSS launch to individuals, unsigned). M7 directly retires three named v1 trust-risks: analytics default-on, no launch-at-login, first-launch friction.

---

## 1. Goal

Turn the single signed-out "Welcome to Hubber" screen into **one cohesive, resumable first-run flow** that:

1. Orients a brand-new user (value prop),
2. Gets a GDPR-safe analytics **consent decision before any telemetry can fire**,
3. Walks them through connecting their first account,
4. Offers notifications and launch-at-login as encouraged-but-optional steps,
5. Reveals the populated popover — and never shows the flow again.

It must read as one experience, not seven disconnected issues. Every screen reuses the existing full-panel visual language (`SignInScreen`: icon → title → body → action) plus a subtle step indicator.

### Non-goals (explicitly out of scope for v1)

- **"Replay setup" from Settings** — dropped. Every choice (analytics, notifications, launch-at-login, accounts) is already individually reachable in Settings. Re-litigate post-v1 if needed. (#101 lists it as *optional*; we decline it.)
- A migration/upgrade path for a large existing-user base — nothing has shipped yet (no release), so the only "existing" users are dev builds. We handle the already-connected case gracefully (§7) but build no data migration.
- Changing the device-flow auth state machine, the notification baseline/diff logic (M3), or the MDM resolution architecture. We *plug into* all three.

---

## 2. The flow

A linear, resumable sequence. Order was chosen so the consent decision is locked **before anything that could emit a telemetry signal** (which rules out connect-first), and so all housekeeping is done before the app reveals.

| # | Step | Forward action(s) | Skippable? | Notes |
|---|------|-------------------|-----------|-------|
| 1 | **Welcome** | "Get started" | — (continue only) | Value prop. Evolves today's `SignInScreen` copy. |
| 2 | **Analytics consent** | "Enable analytics" / "Not now" (equal visual weight) | A choice is required; **default = no analytics** | GDPR opt-in. Links to PRIVACY.md. |
| 3 | **Connect account** | "Sign in with GitHub" (+ "Add GitHub Enterprise or GitLab…") | **No** — required, but resumable (never a trap) | Reuses the existing device-flow machinery. |
| 4 | **Notifications** | "Enable notifications" / "Not now" | Yes | Soft pre-prompt; real OS dialog only on opt-in. |
| 5 | **Launch at login** | "Open Hubber at login" (encouraged primary) / "Not now" | Yes | Explicit opt-in, not pre-enabled. |
| → | **Reveal** | populated popover | | Sets `onboardingCompleted`. |

### Why connect is required, not skippable

A signed-out Hubber has nothing to show — today's signed-out state is already a wall that only renders the sign-in screen. A "Skip for now" button would dump the user on an empty screen, buying nothing. The only thing skippability protected against — *trapping* a user who hits a connect error — is solved by **resumability** instead (§3): consent persists the instant it's answered, and dismissing the panel mid-connect (or hitting an error) resumes at the connect step rather than replaying welcome/consent. So connect has no "skip," yet is never a trap. This matches the reality that an unconnected app already behaves this way.

---

## 3. State & persistence (#101 — the foundation)

### Coordinator

A new `@MainActor final class OnboardingCoordinator: ObservableObject` owns flow state and persistence. UserDefaults is injected (default `.standard`) so the resume/completion logic is unit-testable without touching real defaults.

```
enum OnboardingStep: String, CaseIterable {
    case welcome, consent, connect, notifications, launchAtLogin
}
```

Persisted keys (UserDefaults):

| Key | Type | Meaning |
|-----|------|---------|
| `onboardingCompleted` | Bool | Flow finished (or auto-satisfied). When true, the flow never shows again. |
| `onboardingStep` | String | Cursor — the furthest step reached, for exact resume after a mid-flow dismiss. |
| `analyticsConsentDecided` | Bool | The user actively made a consent choice (distinguishes "chose off" from "default off, never asked"). |

`analyticsEnabled` itself continues to live in `SettingsStore` (its fallback flips to `false`, §4).

### Routing

`HubberPopoverView` gains a top-level branch evaluated **before** the existing `authBranchedBody`:

```
if !coordinator.onboardingCompleted {
    OnboardingFlow(coordinator:, store:)
} else {
    authBranchedBody   // unchanged
}
```

### Resume logic

On launch (panel open) the coordinator computes the entry step:

1. If `onboardingCompleted` → don't show the flow.
2. Else start at `onboardingStep`, with these reconciliations:
   - If the connect step is reached but the user is **already connected** (dev build / prior session), auto-advance past it (§7).
   - If `analyticsEnabled` is **MDM-forced**, the consent step renders as a locked/managed read-out and advances without offering a choice (§7).

`onboardingCompleted` is set `true` when the user finishes the launch-at-login step (the final step), i.e. reaches Reveal. A user who never connects will keep seeing the connect step on each open — identical to today's signed-out behavior, and therefore acceptable.

### Composability

Each step is its own SwiftUI view (`OnboardingWelcomeStep`, `OnboardingConsentStep`, `OnboardingConnectStep`, `OnboardingNotificationsStep`, `OnboardingLaunchAtLoginStep`). `OnboardingFlow` is the container: renders the current step + step indicator + shared chrome, and exposes `advance()` / `goToReveal()`. New steps slot in by extending the enum and the switch — no step knows about its siblings.

### Acceptance criteria (#101)

- First launch shows the flow; subsequent launches (after completion) do not.
- Completion and the consent decision persist across restarts.
- Dismiss-and-reopen mid-flow resumes at the correct step without re-asking consent.

---

## 4. Consent (#102) + live gate (#103) — the GDPR pair

### Consent step (#102)

- **Flip `SettingsStore.analyticsEnabled` fallback `true → false`.** This is the GDPR/ePrivacy-safe posture (TelemetryDeck's persistent hashed identifier is treated as *pseudonymous* personal data → consent-before-collection).
- No analytics signal fires before an explicit opt-in (enforced structurally by the live gate, below — default-off alone is not enough because the bug in #103 means the sink ignores the setting).
- Copy (equal-weight buttons, no dark pattern — neither button is visually de-emphasized):
  > **Help improve Hubber?**
  > Share anonymous usage data — counts and timings only. Never repo names, PR titles, logins, or any personal data.
  > You can change this anytime in Settings.
  >
  > [ Enable analytics ]   [ Not now ]
  > _Read our Privacy Policy_ → links to PRIVACY.md
- Both choices set `analyticsConsentDecided = true` and persist `analyticsEnabled`. The decision is reflected in Settings → Privacy.

### Live gate (#103)

Today: `startTelemetry()` decides at launch whether to call `TelemetryDeck.initialize()`, but `TelemetryDeckSink.send()` *always* calls `TelemetryDeck.signal(...)` regardless of the live setting (sink wired as a default param ~`GitHubAuth.swift:413`). So toggling off mid-session keeps sending, and toggling on does nothing until restart.

**Fix:** introduce a `GatedTelemetrySink` that wraps the real `TelemetryDeckSink` and consults the **live** `analyticsEnabled` before each `send`:

- Holds a thread-safe enabled flag (the sink is `Sendable`; the gate is a `final class` with a lock / atomic, updated whenever `analyticsEnabled` changes).
- `send` is a no-op when disabled.
- On the first enabled `send`, lazy-initialize the TelemetryDeck SDK (preserving the DEBUG `testMode` branch), then forward.
- Wiring: `HubberStore` builds the gated sink bound to `settings.analyticsEnabled` (observes `settings.$analyticsEnabled` and pushes the value into the gate). `startTelemetry()` no longer guards SDK init by itself — it installs the gate and lets the live value drive initialization.
- MetricKit / crash reporting stays as-is (launch-gated). It only writes local `os_log` and transmits nothing, so the live-network-gate requirement does not apply to it.

### Acceptance criteria (#102, #103)

- Fresh install sends **no** telemetry until the user explicitly opts in (verify via `SpyTelemetrySink` — zero sends while disabled).
- Unchecking analytics stops all signals immediately, no restart; re-checking resumes them (lazy-init if needed). DEBUG `testMode` preserved.
- Consent choice persists and is mirrored in Settings → Privacy.

---

## 5. Privacy notice (#104)

### `PRIVACY.md` (new, repo root)

Accurate to the implementation. Sections:

- **What's collected** — the exact event set from `Telemetry.swift`, counts/enum values only:
  `session.opened`, `session.counts` (incoming/outgoing/drafts counts), `tab.switched` (tab enum), `item.opened` (tab enum), `refresh.manual`, `slo.distribution` (green/amber/red counts).
- **What's never collected** — repo names, PR titles, branch names, usernames/logins, org names, email. (Mirrors the PRODUCT.md privacy rail.)
- **Identifier** — pseudonymous: the TelemetryDeck SDK generates a random UUID, SHA-256-hashed, stored in UserDefaults. Hubber never supplies a login/email/PII as the identifier.
- **Processor** — TelemetryDeck. Data hosted in the EU (Hetzner, Nuremberg; some infrastructure at Azure Amsterdam / AWS Frankfurt, consolidating to Hetzner-only during 2026). TelemetryDeck offers a Data Processing Agreement (DPA). *Note: TelemetryDeck positions the data as non-personal/anonymized; Hubber adopts the conservative stance (pseudonymous → consent-first) regardless.*
- **Lawful basis** — consent (GDPR Art. 6(1)(a)); opt-in, default off.
- **Retention** — per TelemetryDeck's policy (cite their figure when writing).
- **Crash/hang diagnostics** — handled **locally via `os_log` only** (MetricKit → `os_log`). **Nothing is transmitted off the device.** Stated plainly so the doc is honest.
- **How to opt out** — Settings → Privacy → toggle off; effective immediately (per #103), no restart.

### In-app changes (#104)

- Link PRIVACY.md from the consent step (§4) and from Settings → Privacy. (Link target: the GitHub-hosted `PRIVACY.md`; open in browser via `NSWorkspace`.)
- **Fix the dishonest crash-reporting label.** Today Settings reads "Send crash & hang reports" / "Reports help diagnose stability issues. No PII is included." — which implies transmission. Rewrite to reflect local-only handling, e.g.:
  > **Diagnostic logging**
  > Crash & hang diagnostics are written to your Mac's local log only — never sent anywhere.

### Acceptance criteria (#104)

- `PRIVACY.md` matches the implementation exactly (no claim of transmitting crash data; correct event list).
- Consent step and Settings → Privacy both link to it.
- The crash-reporting label no longer implies data leaves the device.

---

## 6. Connect / Notifications / Launch-at-login steps

### Connect (#105)

M6 is **done** (#108 merged: multi-account model settled), so this is **unblocked** — build against the current connection model.

- The connect step **reuses the existing device-flow state machine**: `store.startSignIn()` → `.waitingForUser(authorization)` → the `DeviceCodeScreen` UI → `.signedIn`. It does **not** reinvent auth.
- Inside onboarding, a successful connect **advances the flow** (to the notifications step) rather than triggering the normal `SignInSuccessScreen → normalChrome` reveal. The reveal happens only after step 5.
- The first connection becomes the primary; subsequent accounts use the standard M6 path. "Add GitHub Enterprise or GitLab…" reuses the existing `AddAccountView` sheet.
- Edge cases handled inline with retry (reusing the auth state machine's error surface): authorization **denied**, device-code **timeout/expiry**, **no repos visible** → show the GitHub-App install hint. A failed/declined connect keeps the user on the connect step with an explanation and a retry affordance.

**AC:** A brand-new user goes launch → connected → seeing PRs without leaving onboarding; errors are explained inline with retry.

### Notifications priming (#107)

- Soft pre-prompt step explaining *why* Hubber notifies (e.g. "new review requested"), shown **before** the real macOS permission dialog — so a decline doesn't permanently burn the OS prompt.
- "Enable notifications" → calls `dispatcher.ensureAuthorized()` (the only thing that triggers the system dialog). "Not now" → advances without touching `UNUserNotificationCenter`.
- Respects the **bundle guard** (`ensureAuthorized()` already no-ops when not in a real `.app`), the existing **per-event settings** (defaults unchanged: newReview on, others off), and the **M3 baseline/first-run suppression** (untouched).
- If notifications are already **OS-denied**, the step explains how to enable them in System Settings instead of firing a no-op request.

**AC:** New users see the soft pre-prompt; accepting triggers the system dialog, declining does not; no regression to M3 baseline logic.

### Launch-at-login (#106)

- Use `SMAppService.mainApp` (macOS 13+) to register/unregister the login item, behind a testable seam: `protocol LaunchAtLoginManaging` + a real `SMAppServiceLaunchAtLogin` impl. The real impl is guarded (no-op/safe outside a real `.app`, like the notification bundle guard) — SMAppService requires a real bundle, so it can't be exercised in the bundle-less xctest host. Unit tests use a fake conforming to the protocol; the real path is verified manually in the packaged app.
- Onboarding step: **explicit opt-in, encouraged** — "Open Hubber at login" as the primary (recommended) button, **not pre-enabled**; registration happens only on an explicit click. "Not now" advances.
- **Settings toggle** to change later. The system status (`SMAppService.mainApp.status`) is the source of truth; the toggle reflects and mutates it.
- **MDM-lockable:** add `launchAtLogin` to the `ManagedKey` registry + `SettingsStore` resolution + `isLocked`. When forced, apply on launch and render the toggle disabled (per the established managed-prefs pattern: locked = disabled, not hidden).

**AC:** Enabling adds Hubber as a login item; disabling removes it; state survives restart; works in the packaged `.app`.

---

## 7. Edge cases (cross-cutting)

| Case | Behavior |
|------|----------|
| Panel dismissed mid-flow | Resume at saved `onboardingStep`; consent never re-asked once decided. |
| Already-connected user when the flow first runs (dev/upgrade) | Auto-advance past the connect step; still present welcome + consent so a consent choice is recorded. |
| MDM forces `analyticsEnabled` (on or off) | Consent step shows the managed/locked state and advances without a user choice; Settings analytics toggle stays disabled (existing behavior). |
| MDM forces `launchAtLogin` | Apply on launch; onboarding step + Settings toggle reflect locked state (disabled). |
| Notifications already OS-denied | Priming step explains System Settings; no system request fired. |
| No real bundle (`swift run` / xctest) | Notification and launch-at-login real-paths degrade gracefully via their guards; flow still navigable. Never instantiate `UNUserNotificationCenter` or live `SMAppService` in the bundle-less test host. |
| Provider access policy blocks github.com (MDM allowlist) | Connect step shows the existing restricted message; github.com sign-in disabled, GHES/GitLab still available via the add-account sheet. |
| Connect error (denied/timeout/no-repos) | Inline explanation + retry; user stays on the connect step (not trapped, not advanced). |

---

## 8. Build sequence & dependencies

Ordered so each task lands on a green `make ci` and the next builds on settled foundations:

1. **#101 scaffold** — coordinator, persistence, routing branch, composable step shells (welcome step real; others stubbed). Foundation everything else plugs into.
2. **#102 consent + #104 privacy** (the GDPR pair) and **#103 live gate** — done together: flip the default, add the gated sink, write PRIVACY.md, fix the crash label, wire links. #103 is what makes "no signal before consent" actually true.
3. **#105 connect step** — wire the device flow into the connect step shell.
4. **#107 notifications step** — soft pre-prompt.
5. **#106 launch-at-login step** — SMAppService seam, Settings toggle, MDM key. (Manual verification needs the packaged `.app`.)

Each task ties to its issue with `Closes #NN`, Conventional Commits, **no co-author trailers**. `make ci` (build + test + lint + swiftformat --lint) is the pre-push gate. CI is manual-only; for a headless signal run `gh workflow run swift.yml --ref <branch>` (pin macos-26).

---

## 9. Testing strategy

- **Coordinator** — unit-test resume/completion/persistence with an injected `UserDefaults` (in-memory suite). Cover: fresh → welcome; mid-flow resume; completed → skip; already-connected auto-advance; MDM-forced-analytics path.
- **Consent + gate** — `SpyTelemetrySink` asserts **zero sends while disabled** and sends-after-opt-in; toggling off mid-session stops sends without restart; param values never contain PII (existing privacy-contract test pattern).
- **SettingsStore** — assert `analyticsEnabled` fallback is now `false`; `launchAtLogin` resolves through MDM → UserDefaults → default and reports `isLocked` correctly.
- **Launch-at-login** — unit-test against the `LaunchAtLoginManaging` fake (register/unregister/status); never instantiate live `SMAppService` in tests.
- **Notifications / bundle guard** — never instantiate `UNUserNotificationCenter` in the bundle-less host; test the decision logic (opt-in → request, decline → no request) against the existing `NotificationDispatching` seam.
- **Manual (packaged `.app` via `Scripts/make-app.sh`)** — full flow end-to-end, real login-item registration, real notification dialog, PRIVACY.md links open.

---

## 10. Summary of file-level impact (orientation, not prescriptive)

- **New:** `OnboardingCoordinator`, `OnboardingFlow` + per-step views, `GatedTelemetrySink`, `LaunchAtLoginManaging` + impl, `PRIVACY.md`.
- **Evolved:** `SignInScreen.swift` (welcome copy reused into the welcome step), `HubberPopoverView.swift` (routing branch), `SettingsStore.swift` (analytics fallback → false; `launchAtLogin` key + resolution), `ManagedPreferences.swift` (`ManagedKey.launchAtLogin`), `HubberSettingsView.swift` (honest crash label, privacy link, launch-at-login toggle), `main.swift` (`startTelemetry()` installs the gate; launch-at-login apply-on-launch for MDM), `HubberStore` (build gated sink bound to settings).
