# M2-D — Observability + Refresh Resilience Implementation Plan

> Fourth/final M2 PR (A engine ✅ → B badge ✅ → C visual ✅ → **D observability**). Branch: `feat/m2-observability` (off fixed `main`). TDD where testable; SDK/system glue is build + manual.

**Goal:** Add privacy-safe usage analytics (TelemetryDeck), crash/hang reporting (MetricKit), and make the three-tab refresh resilient so one failing tab no longer blanks the others.

**Issues:** #32 (TelemetryDeck), #33 (MetricKit). Plus a resilience fix flagged during M2-C debugging.

**Architecture:** A small `Telemetry` facade with **typed, privacy-safe event methods** sits between the app and any analytics backend, so (a) the app never passes PII and (b) it's testable with a spy sink. `TelemetryDeckSink` wraps the SDK. MetricKit is a thin `MXMetricManagerSubscriber` with a **pure, tested diagnostic formatter**. Refresh resilience moves from one all-or-nothing `try await` to **independent per-tab fetches with per-tab errors**.

**Tech:** Swift 6, TelemetryDeck Swift SDK (SPM), MetricKit (system framework), existing `SettingsStore`/`HubberStore`.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/Hubber/Telemetry/Telemetry.swift` | `TelemetrySink` protocol + `Telemetry` facade (typed privacy-safe events) |
| Create | `Sources/Hubber/Telemetry/TelemetryDeckSink.swift` | `TelemetrySink` backed by TelemetryDeck SDK; app-ID config; DEBUG test mode |
| Modify | `Package.swift` | Add TelemetryDeck SPM dependency |
| Create | `Sources/Hubber/Telemetry/MetricSubscriber.swift` | `MXMetricManagerSubscriber` + pure diagnostic formatter |
| Modify | `Sources/Hubber/main.swift` | Register MetricKit subscriber; emit session-open + tab counts; init Telemetry |
| Modify | `Sources/Hubber/HubberPopoverView.swift` | Emit tab-switch + click-through events |
| Modify | `Sources/Hubber/GitHubAuth.swift` | `HubberStore`: emit manual-refresh; **independent per-tab fetch + per-tab error** |
| Create | `Tests/HubberTests/TelemetryTests.swift` | Spy sink: event names/params correct, NO PII |
| Create | `Tests/HubberTests/MetricSubscriberTests.swift` | Diagnostic-payload → log formatter |

---

## Task 1 — `Telemetry` facade + `TelemetrySink` (TDD)

```swift
protocol TelemetrySink: Sendable { func send(_ event: String, _ params: [String: String]) }

struct Telemetry: Sendable {
    let sink: TelemetrySink
    func sessionOpened() { sink.send("session.opened", [:]) }
    func tabSwitched(to tab: WorkTab) { sink.send("tab.switched", ["tab": tab.rawValue]) }
    func itemOpened(in tab: WorkTab) { sink.send("item.opened", ["tab": tab.rawValue]) }
    func manualRefresh() { sink.send("refresh.manual", [:]) }
    func sessionCounts(incoming: Int, outgoing: Int, drafts: Int) {
        sink.send("session.counts", ["incoming": "\(incoming)", "outgoing": "\(outgoing)", "drafts": "\(drafts)"])
    }
    func sloDistribution(green: Int, amber: Int, red: Int) {
        sink.send("slo.distribution", ["green": "\(green)", "amber": "\(amber)", "red": "\(red)"])
    }
}
```

**Test first** (`TelemetryTests`, spy sink recording calls): each method sends the right event name + params; params contain ONLY counts/enum raw values — assert no value equals a repo name / PR title / login (the methods structurally can't, but assert the contract). Commit: `feat(telemetry): add Telemetry facade + TelemetrySink (privacy-safe events) (#32)`.

## Task 2 — TelemetryDeck SDK integration (build gate is critical)

Add the dependency to `Package.swift`: `.package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0")`, product `"TelemetryDeck"` on the Hubber target. **VERIFY `swift build` resolves it** (network fetch). If SPM cannot resolve the package in this environment, STOP and report — do not fake it.

`TelemetryConfig.appID = "96FDB900-0C0A-492E-AAC8-E584E6529028"` (constant, alongside `GitHubAppConfig`). `TelemetryDeckSink`: on init call the SDK's initialize with the app ID; in `send`, forward to the SDK's signal API. In **DEBUG**, enable the SDK's test/telemetry-test mode so dev runs don't pollute production data. (Use the current TelemetryDeck 2.x API — verify exact method names from the package; adapt if the API differs.)

Commit: `feat(telemetry): TelemetryDeck sink wired to app ID with DEBUG test mode (#32)`.

## Task 3 — Instrument privacy-safe events (#32)

Wire `Telemetry` (held by `AppDelegate`/`HubberStore`) to emit:
- **session.opened** + **session.counts** + **slo.distribution** when the popover opens (compute counts from `store.data`; SLO buckets from incoming reviews via the existing SLO status logic).
- **tab.switched** when the segmented tab selection changes (`HubberPopoverView`).
- **item.opened** when a row is clicked through to GitHub (`ClickableRow`).
- **refresh.manual** in `HubberStore.refreshPullRequests()` (⌘R / footer).
No repo names, PR titles, or logins anywhere. Build + manual. Commit: `feat(telemetry): instrument session, tab, click-through, refresh, SLO distribution (#32)`.

## Task 4 — MetricKit crash/hang reporting (#33) (TDD on the formatter)

`MetricSubscriber: NSObject, MXMetricManagerSubscriber` implementing `didReceive(_ payloads: [MXMetricPayload])` and `didReceive(_ payloads: [MXDiagnosticPayload])`. Crash (`crashDiagnostics`) and hang (`hangDiagnostics`) payloads are summarized via a **pure formatter** `func summarize(_ diagnostic: ...) -> String` and logged (to `developerLog` via a callback + `os_log`). Register `MXMetricManager.shared.add(subscriber)` in `AppDelegate.applicationDidFinishLaunching`; remove on terminate.

**Test first** (`MetricSubscriberTests`): feed the formatter a representative crash/hang diagnostic (construct the minimal MX types, or test the formatter on a value-type summary struct you map payloads into) and assert the produced log line includes the diagnostic kind + key fields, with no PII. (Real payloads arrive from the OS over time — only the formatter is unit-tested.) Commit: `feat(observability): MetricKit crash/hang subscriber + diagnostic formatter (#33)`.

## Task 5 — Resilient per-tab refresh (folded-in fix)

Replace the all-or-nothing fan-out in `HubberStore.refreshPullRequestsFromGitHub` (currently `data = try await HubberData(incoming:outgoing:drafts:)` — one failure blanks all tabs) with **independent per-tab fetches**: run the three concurrently, catch each independently, update each tab's data from its own success, and record a **per-tab error** (`incomingError`/`outgoingError`/`draftsError`) instead of one shared `pullRequestRefreshError`. `HubberPopoverView` shows each tab's own error. Credential/rate-limit errors still apply globally (sign-out / backoff). 

**Test first**: a `HubberStore`-level or extracted-helper test — given one fetch throwing and two succeeding, the two successful tabs are populated and only the failing tab carries an error (use injected provider + the existing test seams). Commit: `fix(store): independent per-tab refresh so one failing tab doesn't blank the others`.

---

## Acceptance (whole PR)
- `swift build` clean (incl. resolving TelemetryDeck); `swift test` all pass; `make lint` 0; `make format` idempotent.
- `Telemetry` events + MetricKit formatter + per-tab resilience covered by unit tests. SDK/system registration verified by build + manual.
- **No PII** in any telemetry event. DEBUG runs use test mode.
- Open PR `feat/m2-observability` → main, squash-merge → **M2 complete**.

## Self-Review Checklist
- [ ] Telemetry facade typed + privacy-safe; spy tests assert no PII
- [ ] TelemetryDeck resolves + initialized with the app ID; DEBUG test mode on
- [ ] session/tab/click/refresh/counts/SLO events emitted at the right points
- [ ] MetricKit subscriber registered; diagnostic formatter tested
- [ ] Per-tab independent fetch + per-tab error; one failing tab keeps the others populated
