# M7 — Onboarding & First-Run Consent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Hubber's single signed-out screen into one cohesive, resumable first-run flow (welcome → analytics consent → connect → notifications → launch-at-login → reveal), with GDPR-safe opt-in analytics that take effect live.

**Architecture:** A new `@MainActor OnboardingCoordinator` (UserDefaults-persisted step + completion) drives a composable `OnboardingFlow` that `HubberPopoverView` renders ahead of its existing auth-branched body while onboarding is incomplete. Each step reuses the existing full-panel visual language (`SignInScreen`). Telemetry is routed through a new `GatedTelemetrySink` that consults the live `analyticsEnabled` value; analytics now defaults OFF. Launch-at-login uses `SMAppService.mainApp` behind a testable protocol.

**Tech Stack:** Swift 6.3, SwiftPM, macOS 14+, AppKit + SwiftUI, XCTest, TelemetryDeck SDK, ServiceManagement (`SMAppService`), UserNotifications.

**Design spec:** `docs/superpowers/specs/2026-06-19-m7-onboarding-design.md`

## Global Constraints

- **Build/test gate:** `make ci` (= `swift build` + `swift test` + `swiftlint lint` + `swiftformat --lint`) must pass before every task's final commit. Run `make fix` to auto-format/lint-fix if `swiftformat --lint` or swiftlint fails.
- **Run a single test:** `swift test --filter <ClassName>` or `swift test --filter <ClassName>/<testMethod>`.
- **Commits:** Conventional Commits. Tie each completed issue with `Closes #NN`. **NO co-author trailers of any kind.**
- **Tests use XCTest**, `@testable import Hubber`; `@MainActor` on test classes that touch `@MainActor` types (`SettingsStore`, `HubberStore`, `OnboardingCoordinator`). Inject a fresh `UserDefaults(suiteName:)` per test; tear it down with `removePersistentDomain(forName:)`.
- **Bundle guard (non-negotiable):** NEVER instantiate `UNUserNotificationCenter.current()` or call live `SMAppService.mainApp.register()/unregister()` in the bundle-less xctest host — both crash/throw without a real `.app`. Guard real paths on `Bundle.main.bundleURL.pathExtension == "app"`; tests use fakes.
- **Privacy rail:** telemetry params are counts or enum raw values only — never repo/PR/login/branch/org strings.
- **CI:** auto-triggers are commented out (manual-only). For a headless signal: `gh workflow run swift.yml --ref <branch>` (always macos-26, never macos-latest). The pre-push `make ci` hook is the real gate.
- **Reuse, don't reinvent:** the device-flow auth state machine (`startSignIn`/`DeviceCodeScreen`), the notification dispatcher (`requestNotificationAuthorization()`/`notificationsDenied`), and the MDM resolution pattern (`ManagedKey` + `SettingsStore.bool(...)` + `isLocked`) already exist — plug into them.

---

## File Structure

**New files:**
- `Sources/Hubber/Onboarding/OnboardingCoordinator.swift` — flow state + persistence (logic).
- `Sources/Hubber/Onboarding/OnboardingFlow.swift` — container + step indicator + step switch.
- `Sources/Hubber/Onboarding/OnboardingSteps.swift` — the per-step SwiftUI views (welcome, consent, connect, notifications, launch-at-login).
- `Sources/Hubber/Telemetry/GatedTelemetrySink.swift` — live analytics gate.
- `Sources/Hubber/Core/LaunchAtLogin.swift` — `LaunchAtLoginManaging` protocol + `SMAppService` impl.
- `PRIVACY.md` — privacy notice (repo root).
- `Tests/HubberTests/OnboardingCoordinatorTests.swift`
- `Tests/HubberTests/GatedTelemetrySinkTests.swift`
- `Tests/HubberTests/LaunchAtLoginTests.swift`

**Modified files:**
- `Sources/Hubber/Core/SettingsStore.swift` — analytics fallback `true→false`; add `launchAtLoginEnabled`.
- `Sources/Hubber/Core/ManagedPreferences.swift` — add `ManagedKey.launchAtLogin`.
- `Sources/Hubber/GitHubAuth.swift` (`HubberStore`) — build gated sink + subscribe to `analyticsEnabled`; add launch-at-login service + methods.
- `Sources/Hubber/main.swift` — `startTelemetry()` drops manual analytics init; launch-at-login reconcile at startup.
- `Sources/Hubber/HubberPopoverView.swift` — onboarding routing branch.
- `Sources/Hubber/HubberSettingsView.swift` — honest crash label, PRIVACY link, launch-at-login toggle.
- `Tests/HubberTests/SettingsStoreTests.swift` — flip the analytics-default assertion; add launch-at-login tests.

---

## Task 1: OnboardingCoordinator (state, persistence, resume)

Pure logic — fully TDD. Foundation for #101. No UI yet.

**Files:**
- Create: `Sources/Hubber/Onboarding/OnboardingCoordinator.swift`
- Test: `Tests/HubberTests/OnboardingCoordinatorTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor final class OnboardingCoordinator: ObservableObject`
  - `enum OnboardingCoordinator.Step: String, CaseIterable { case welcome, consent, connect, notifications, launchAtLogin }`
  - `init(defaults: UserDefaults = .standard)`
  - `@Published private(set) var currentStep: Step`
  - `@Published private(set) var isCompleted: Bool`
  - `func advance()` — moves to the next step; on the last step, calls `complete()`.
  - `func skipConnectIfAlreadyConnected(_ isConnected: Bool)` — if on `.connect` and connected, advances.
  - `func complete()` — sets `isCompleted` + persists.
  - UserDefaults keys: `"onboardingCompleted"` (Bool), `"onboardingStep"` (String).

- [ ] **Step 1: Write the failing tests**

Create `Tests/HubberTests/OnboardingCoordinatorTests.swift`:

```swift
import Foundation
import XCTest
@testable import Hubber

@MainActor
final class OnboardingCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private nonisolated(unsafe) var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "OnboardingCoordinatorTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFreshStartsAtWelcomeNotCompleted() {
        let sut = OnboardingCoordinator(defaults: defaults)
        XCTAssertEqual(sut.currentStep, .welcome)
        XCTAssertFalse(sut.isCompleted)
    }

    func testAdvanceMovesThroughStepsInOrder() {
        let sut = OnboardingCoordinator(defaults: defaults)
        sut.advance(); XCTAssertEqual(sut.currentStep, .consent)
        sut.advance(); XCTAssertEqual(sut.currentStep, .connect)
        sut.advance(); XCTAssertEqual(sut.currentStep, .notifications)
        sut.advance(); XCTAssertEqual(sut.currentStep, .launchAtLogin)
        XCTAssertFalse(sut.isCompleted)
    }

    func testAdvancePastLastStepCompletes() {
        let sut = OnboardingCoordinator(defaults: defaults)
        for _ in OnboardingCoordinator.Step.allCases { sut.advance() }
        XCTAssertTrue(sut.isCompleted)
        XCTAssertTrue(defaults.bool(forKey: "onboardingCompleted"))
    }

    func testStepPersistsAndResumes() {
        let first = OnboardingCoordinator(defaults: defaults)
        first.advance() // welcome -> consent
        first.advance() // consent -> connect
        let resumed = OnboardingCoordinator(defaults: defaults)
        XCTAssertEqual(resumed.currentStep, .connect)
        XCTAssertFalse(resumed.isCompleted)
    }

    func testCompletedPersistsAcrossInstances() {
        let first = OnboardingCoordinator(defaults: defaults)
        first.complete()
        let resumed = OnboardingCoordinator(defaults: defaults)
        XCTAssertTrue(resumed.isCompleted)
    }

    func testSkipConnectAdvancesWhenConnected() {
        let sut = OnboardingCoordinator(defaults: defaults)
        sut.advance() // consent
        sut.advance() // connect
        sut.skipConnectIfAlreadyConnected(true)
        XCTAssertEqual(sut.currentStep, .notifications)
    }

    func testSkipConnectNoOpWhenNotConnected() {
        let sut = OnboardingCoordinator(defaults: defaults)
        sut.advance(); sut.advance() // connect
        sut.skipConnectIfAlreadyConnected(false)
        XCTAssertEqual(sut.currentStep, .connect)
    }

    func testSkipConnectNoOpWhenNotOnConnectStep() {
        let sut = OnboardingCoordinator(defaults: defaults)
        sut.skipConnectIfAlreadyConnected(true) // on welcome
        XCTAssertEqual(sut.currentStep, .welcome)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter OnboardingCoordinatorTests`
Expected: FAIL — `cannot find 'OnboardingCoordinator' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Hubber/Onboarding/OnboardingCoordinator.swift`:

```swift
import Foundation

/// Drives the first-run onboarding flow: tracks the current step, persists progress so a
/// dismissed-then-reopened panel resumes where it left off, and records completion so the
/// flow never re-shows. UserDefaults is injectable for testing. See #101.
@MainActor
final class OnboardingCoordinator: ObservableObject {
    enum Step: String, CaseIterable {
        case welcome, consent, connect, notifications, launchAtLogin
    }

    private let defaults: UserDefaults
    private static let completedKey = "onboardingCompleted"
    private static let stepKey = "onboardingStep"

    @Published private(set) var currentStep: Step
    @Published private(set) var isCompleted: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isCompleted = defaults.bool(forKey: Self.completedKey)
        let saved = defaults.string(forKey: Self.stepKey).flatMap(Step.init(rawValue:))
        currentStep = saved ?? .welcome
    }

    /// Advances to the next step, or completes the flow if already on the last step.
    func advance() {
        guard let idx = Step.allCases.firstIndex(of: currentStep) else { return }
        let next = idx + 1
        if next < Step.allCases.count {
            currentStep = Step.allCases[next]
            defaults.set(currentStep.rawValue, forKey: Self.stepKey)
        } else {
            complete()
        }
    }

    /// When resuming onto the connect step but an account is already connected
    /// (dev build / prior session), skip straight past it.
    func skipConnectIfAlreadyConnected(_ isConnected: Bool) {
        guard currentStep == .connect, isConnected else { return }
        advance()
    }

    /// Marks onboarding finished — the flow never shows again.
    func complete() {
        isCompleted = true
        defaults.set(true, forKey: Self.completedKey)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter OnboardingCoordinatorTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Run the full gate and commit**

Run: `make ci`
Expected: build + all tests + lint + format-lint pass.

```bash
git add Sources/Hubber/Onboarding/OnboardingCoordinator.swift Tests/HubberTests/OnboardingCoordinatorTests.swift
git commit -m "feat(onboarding): add OnboardingCoordinator state machine (#101)"
```

---

## Task 2: Onboarding flow container + welcome step + routing

Wires the coordinator into the popover. Builds the container, the welcome step, and **stub** views for the remaining four steps (each just shows a title + a "Continue" button calling `advance()`); later tasks replace the stubs. UI — verified by compile + manual. Completes #101.

**Files:**
- Create: `Sources/Hubber/Onboarding/OnboardingFlow.swift`
- Create: `Sources/Hubber/Onboarding/OnboardingSteps.swift`
- Modify: `Sources/Hubber/HubberPopoverView.swift`

**Interfaces:**
- Consumes: `OnboardingCoordinator` (Task 1); `HubberStore` (`authState`, `connections`, `startSignIn()`, etc.).
- Produces:
  - `struct OnboardingFlow: View` — `init(coordinator: OnboardingCoordinator, store: HubberStore)`.
  - `struct OnboardingScaffold<Content: View>: View` — shared chrome (icon/title/body/step-dots); reused by every step.
  - Step views: `OnboardingWelcomeStep`, `OnboardingConsentStep`, `OnboardingConnectStep`, `OnboardingNotificationsStep`, `OnboardingLaunchAtLoginStep` — all take `coordinator`/`store` as needed. Tasks 5–8 fill in the non-welcome ones; this task ships them as stubs.

- [ ] **Step 1: Build the shared scaffold + welcome step + stubs**

Create `Sources/Hubber/Onboarding/OnboardingSteps.swift`. Follow `SignInScreen.swift` for visual tokens (`HubberDesign.text/text2/text3`, `SignInButtonStyle`, 64×64 icon tile, 264pt max width). Step-dots are a simple `HStack` of 5 capsules highlighting the current index.

```swift
import SwiftUI

// MARK: - Shared scaffold

/// Full-panel onboarding chrome: optional icon, title, body, content slot, and a step indicator.
/// Mirrors the SignInScreen layout so onboarding feels like the rest of the app.
struct OnboardingScaffold<Content: View>: View {
    let stepIndex: Int
    let stepCount: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 40)
            Spacer()
            stepDots.padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { i in
                Capsule()
                    .fill(i == stepIndex ? HubberDesign.accent : HubberDesign.text3.opacity(0.35))
                    .frame(width: i == stepIndex ? 18 : 6, height: 6)
            }
        }
        .accessibilityLabel("Step \(stepIndex + 1) of \(stepCount)")
    }
}

// MARK: - Welcome (#101)

struct OnboardingWelcomeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        OnboardingScaffold(stepIndex: 0, stepCount: OnboardingCoordinator.Step.allCases.count) {
            VStack(spacing: 0) {
                appIconTile
                Text("Welcome to Hubber")
                    .font(.system(size: 19, weight: .semibold)).tracking(-0.4)
                    .foregroundStyle(HubberDesign.text).padding(.bottom, 8)
                Text("Keep an eye on your PR reviews, CI, and drafts — right from the menu bar. Let's get you set up.")
                    .font(.system(size: 12.5)).foregroundStyle(HubberDesign.text2)
                    .multilineTextAlignment(.center).lineSpacing(3)
                    .frame(maxWidth: 264).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 24)
                Button { coordinator.advance() } label: {
                    Text("Get started").font(.system(size: 13.5, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 16)
                }
                .buttonStyle(SignInButtonStyle(colorScheme: colorScheme)).frame(maxWidth: 264)
            }
        }
    }

    private var appIconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(light: "#1f2328", dark: "#0d1117"))
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.30), radius: 11, y: 8)
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 30, weight: .medium)).foregroundStyle(.white)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Step stubs (replaced by later tasks)

/// Minimal placeholder used until the real step lands. Title + Continue (advances the flow).
struct OnboardingStepStub: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let stepIndex: Int
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        OnboardingScaffold(stepIndex: stepIndex, stepCount: OnboardingCoordinator.Step.allCases.count) {
            VStack(spacing: 16) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(HubberDesign.text)
                Button { coordinator.advance() } label: {
                    Text("Continue").font(.system(size: 13.5, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 16)
                }
                .buttonStyle(SignInButtonStyle(colorScheme: colorScheme)).frame(maxWidth: 264)
            }
        }
    }
}
```

- [ ] **Step 2: Build the flow container**

Create `Sources/Hubber/Onboarding/OnboardingFlow.swift`:

```swift
import SwiftUI

/// Renders the current onboarding step. Shown by HubberPopoverView ahead of the normal
/// auth-branched body while onboarding is incomplete. See #101.
struct OnboardingFlow: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var store: HubberStore

    var body: some View {
        Group {
            switch coordinator.currentStep {
            case .welcome:
                OnboardingWelcomeStep(coordinator: coordinator)
            case .consent:
                OnboardingStepStub(coordinator: coordinator, stepIndex: 1, title: "Analytics consent")
            case .connect:
                OnboardingStepStub(coordinator: coordinator, stepIndex: 2, title: "Connect account")
            case .notifications:
                OnboardingStepStub(coordinator: coordinator, stepIndex: 3, title: "Notifications")
            case .launchAtLogin:
                OnboardingStepStub(coordinator: coordinator, stepIndex: 4, title: "Launch at login")
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: coordinator.currentStep)
    }
}
```

- [ ] **Step 3: Wire routing into HubberPopoverView**

In `Sources/Hubber/HubberPopoverView.swift`, add a coordinator state object and branch on it ahead of `authBranchedBody`.

Add the state object near the other `@State`/`@StateObject` declarations (after line 12, `@State private var showingAdd = false`):

```swift
    @StateObject private var onboarding = OnboardingCoordinator()
```

Replace the `authBranchedBody` reference inside `body` (line 22, `authBranchedBody`) with:

```swift
            if !onboarding.isCompleted {
                OnboardingFlow(coordinator: onboarding, store: store)
            } else {
                authBranchedBody
            }
```

- [ ] **Step 4: Build and verify it compiles**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 5: Run the full gate**

Run: `make ci`
Expected: pass (existing tests unaffected; new coordinator tests pass).

- [ ] **Step 6: Manual verification (packaged app)**

Run: `make app-dev` then launch `Hubber.app`. With a clean profile (`defaults delete com.osuritz.hubber onboardingCompleted` first if needed), open the panel → Welcome shows with step-dots. "Get started" advances to the "Analytics consent" stub; each "Continue" advances; after the last stub the normal app appears. Quit and relaunch mid-flow → resumes at the same step. (This is the only step in this task without an automated test, because SwiftUI views have no snapshot harness here.)

- [ ] **Step 7: Commit**

```bash
git add Sources/Hubber/Onboarding/OnboardingFlow.swift Sources/Hubber/Onboarding/OnboardingSteps.swift Sources/Hubber/HubberPopoverView.swift
git commit -m "feat(onboarding): multi-step flow scaffold + welcome step + routing

Closes #101"
```

---

## Task 3: Telemetry live gate + analytics default OFF

Pure logic — TDD. Adds `GatedTelemetrySink`, flips the analytics default to `false`, and wires the gate into `HubberStore` so toggling analytics takes effect with no restart. Completes #103 (and the #102 default-flip half).

**Files:**
- Create: `Sources/Hubber/Telemetry/GatedTelemetrySink.swift`
- Create: `Tests/HubberTests/GatedTelemetrySinkTests.swift`
- Modify: `Sources/Hubber/Core/SettingsStore.swift:156-162` (analytics fallback) and the doc comment at `:54-58`
- Modify: `Sources/Hubber/GitHubAuth.swift` (init telemetry default + subscription)
- Modify: `Sources/Hubber/main.swift:152-160` (`startTelemetry`)
- Modify: `Tests/HubberTests/SettingsStoreTests.swift:415-417` (flip the default assertion)

**Interfaces:**
- Produces:
  - `final class GatedTelemetrySink: TelemetrySink, @unchecked Sendable`
  - `init(enabled: Bool, underlying: any TelemetrySink, initializeSDK: @escaping @Sendable () -> Void = { TelemetryDeckSink.initialize() })`
  - `func setEnabled(_ enabled: Bool)`
  - `send` no-ops while disabled; lazily calls `initializeSDK` once before the first forwarded send.
- Consumes: `TelemetrySink` (`Sources/Hubber/Telemetry/Telemetry.swift`), `SpyTelemetrySink` (already in `TelemetryTests.swift`).

- [ ] **Step 1: Write the failing tests**

Create `Tests/HubberTests/GatedTelemetrySinkTests.swift`:

```swift
import Foundation
import XCTest
@testable import Hubber

final class GatedTelemetrySinkTests: XCTestCase {
    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        var count: Int { lock.withLock { _count } }
        func increment() { lock.withLock { _count += 1 } }
    }

    func testDisabledDoesNotForward() {
        let spy = SpyTelemetrySink()
        let sut = GatedTelemetrySink(enabled: false, underlying: spy, initializeSDK: {})
        sut.send("session.opened", [:])
        XCTAssertEqual(spy.calls.count, 0)
    }

    func testEnabledForwards() {
        let spy = SpyTelemetrySink()
        let sut = GatedTelemetrySink(enabled: true, underlying: spy, initializeSDK: {})
        sut.send("session.opened", [:])
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].event, "session.opened")
    }

    func testDisabledNeverInitializes() {
        let counter = CallCounter()
        let sut = GatedTelemetrySink(enabled: false, underlying: SpyTelemetrySink(),
                                     initializeSDK: { counter.increment() })
        sut.send("a", [:]); sut.send("b", [:])
        XCTAssertEqual(counter.count, 0)
    }

    func testInitializesOnceBeforeFirstForward() {
        let counter = CallCounter()
        let sut = GatedTelemetrySink(enabled: true, underlying: SpyTelemetrySink(),
                                     initializeSDK: { counter.increment() })
        sut.send("a", [:]); sut.send("b", [:]); sut.send("c", [:])
        XCTAssertEqual(counter.count, 1)
    }

    func testSetEnabledStopsAndResumesLive() {
        let spy = SpyTelemetrySink()
        let sut = GatedTelemetrySink(enabled: true, underlying: spy, initializeSDK: {})
        sut.send("one", [:])
        sut.setEnabled(false)
        sut.send("two", [:])
        sut.setEnabled(true)
        sut.send("three", [:])
        XCTAssertEqual(spy.calls.map(\.event), ["one", "three"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GatedTelemetrySinkTests`
Expected: FAIL — `cannot find 'GatedTelemetrySink' in scope`.

- [ ] **Step 3: Implement the gate**

Create `Sources/Hubber/Telemetry/GatedTelemetrySink.swift`:

```swift
import Foundation

/// A `TelemetrySink` that forwards to an underlying sink only while analytics is enabled,
/// consulting the LIVE enabled value before every send so the privacy toggle takes effect
/// immediately (no restart). Lazily initializes the analytics SDK once, just before the first
/// forwarded send. See #103.
final class GatedTelemetrySink: TelemetrySink, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    private var initialized = false
    private let underlying: any TelemetrySink
    private let initializeSDK: @Sendable () -> Void

    init(
        enabled: Bool,
        underlying: any TelemetrySink,
        initializeSDK: @escaping @Sendable () -> Void = { TelemetryDeckSink.initialize() }
    ) {
        self.enabled = enabled
        self.underlying = underlying
        self.initializeSDK = initializeSDK
    }

    /// Updates the live enabled value. Safe to call from any thread / executor.
    func setEnabled(_ value: Bool) {
        lock.withLock { enabled = value }
    }

    func send(_ event: String, _ params: [String: String]) {
        let needsInit: Bool = lock.withLock {
            guard enabled else { return false }
            if initialized { return false }
            initialized = true
            return true
        }
        guard lock.withLock({ enabled }) else { return }
        if needsInit { initializeSDK() }
        underlying.send(event, params)
    }
}
```

- [ ] **Step 4: Flip the analytics default to OFF**

In `Sources/Hubber/Core/SettingsStore.swift`, change the `analyticsEnabled` resolution (around line 156-162) so `fallback` is `false`:

```swift
        analyticsEnabled = Self.bool(
            managedKey: ManagedKey.analyticsEnabled,
            defaultsKey: ManagedKey.analyticsEnabled,
            defaults: defaults,
            managed: managed,
            fallback: false
        )
```

Update the doc comment at lines 54-58 to read:

```swift
    // MARK: - Privacy / Telemetry kill-switches (#53, #102)

    //
    // analyticsEnabled defaults to FALSE (opt-in, GDPR-safe — see #102); crashReportingEnabled
    // defaults to true (local os_log only, transmits nothing). Both MDM-lockable and user-toggleable
    // in Privacy settings. Analytics is gated LIVE via GatedTelemetrySink (#103), not just at launch.
```

- [ ] **Step 5: Update the existing default-assertion test**

In `Tests/HubberTests/SettingsStoreTests.swift`, replace the test at lines 415-417:

```swift
    func testDefaultAnalyticsEnabledIsFalse() {
        XCTAssertFalse(sut.analyticsEnabled)
    }
```

(Leave `testDefaultCrashReportingEnabledIsTrue` unchanged — crash reporting still defaults true.)

- [ ] **Step 6: Wire the gate into HubberStore**

In `Sources/Hubber/GitHubAuth.swift`:

a) Add a stored property near the other private lets (e.g. after `private let fallbackProvider: any CodeHostProvider` ~line 398):

```swift
    /// Live analytics gate when telemetry is not injected (production path); nil when a
    /// caller injects its own Telemetry (tests). Subscribed to `settings.$analyticsEnabled`.
    private let telemetryGate: GatedTelemetrySink?
```

b) Change the init parameter (line 413) from a concrete default to optional:

```swift
        telemetry: Telemetry? = nil,
```

c) In the init body, replace `self.telemetry = telemetry` (line 421) with the gated-default construction. Place it AFTER `self.settings = settings` (line 420):

```swift
        if let telemetry {
            self.telemetry = telemetry
            telemetryGate = nil
        } else {
            let gate = GatedTelemetrySink(enabled: settings.analyticsEnabled, underlying: TelemetryDeckSink())
            self.telemetry = Telemetry(sink: gate)
            telemetryGate = gate
        }
```

d) After `registry = ConnectionRegistry(defaults: defaults)` (line 431) and before the `if restoreOnInit` block, subscribe the gate to live changes:

```swift
        if let telemetryGate {
            settings.$analyticsEnabled
                .sink { [weak telemetryGate] enabled in telemetryGate?.setEnabled(enabled) }
                .store(in: &cancellables)
        }
```

(The 4 existing test call sites pass a non-nil `telemetry:` and are unaffected.)

- [ ] **Step 7: Simplify startTelemetry (gate now owns analytics init)**

In `Sources/Hubber/main.swift`, replace `startTelemetry()` (lines 152-160) so it no longer initializes TelemetryDeck directly (the gate lazy-inits on first enabled send); it keeps only the local-only MetricKit subscription:

```swift
    /// Crash/hang diagnostics (MetricKit → local os_log only) are gated here at launch.
    /// Analytics (TelemetryDeck) is gated LIVE by GatedTelemetrySink, so it is NOT started here.
    private func startTelemetry() {
        if store.settings.crashReportingEnabled {
            MXMetricManager.shared.add(metricSubscriber)
            metricKitStarted = true
        }
    }
```

- [ ] **Step 8: Run tests**

Run: `swift test --filter GatedTelemetrySinkTests` then `swift test --filter SettingsStoreTests`
Expected: PASS.

- [ ] **Step 9: Run the full gate and commit**

Run: `make ci`
Expected: pass.

```bash
git add Sources/Hubber/Telemetry/GatedTelemetrySink.swift Tests/HubberTests/GatedTelemetrySinkTests.swift Sources/Hubber/Core/SettingsStore.swift Sources/Hubber/GitHubAuth.swift Sources/Hubber/main.swift Tests/HubberTests/SettingsStoreTests.swift
git commit -m "feat(telemetry): live analytics gate + default analytics OFF

Route telemetry through GatedTelemetrySink so the analytics toggle takes
effect immediately with no restart, and flip analyticsEnabled to opt-in.

Closes #103"
```

---

## Task 4: PRIVACY.md + honest crash label + in-app privacy link

Docs + a small, reviewable Settings change. Completes #104.

**Files:**
- Create: `PRIVACY.md` (repo root)
- Modify: `Sources/Hubber/HubberSettingsView.swift:171-185` (crash label) + add a privacy-policy link row in the Privacy section.

**Interfaces:**
- Produces: a stable URL constant for the in-app link. Add to `OnboardingSteps.swift` or a small shared place; define in this task as:
  - `enum PrivacyLinks { static let privacyPolicy = URL(string: "https://github.com/osuritz/hubber/blob/main/PRIVACY.md")! }`
  (Consent step, Task 5, reuses `PrivacyLinks.privacyPolicy`.)

- [ ] **Step 1: Write PRIVACY.md**

Create `PRIVACY.md` at the repo root. Use these exact facts (verified 2026-06-19):

```markdown
# Hubber Privacy Notice

_Last updated: 2026-06-19_

Hubber is a macOS menu-bar app that surfaces your pull-request review queue and PR health.
This notice explains exactly what data Hubber does and does not handle.

## The short version

- **Analytics are opt-in and OFF by default.** Nothing is sent unless you explicitly turn on
  "Share anonymous usage analytics" in onboarding or Settings → Privacy.
- Hubber **never** transmits repo names, PR titles, branch names, usernames/logins, org names,
  or email addresses. Counts, ages, and enum values only.
- **Crash & hang diagnostics stay on your Mac** — they are written to the local system log only
  and are never transmitted anywhere.

## Anonymous usage analytics (opt-in)

When (and only when) you enable analytics, Hubber sends a small set of count/enum events to help
us understand how the app is used:

| Event | Data |
|-------|------|
| `session.opened` | none |
| `session.counts` | counts of incoming / outgoing / draft items |
| `tab.switched` | which tab (incoming \| outgoing \| drafts) |
| `item.opened` | which tab the opened item was in |
| `refresh.manual` | none |
| `slo.distribution` | counts of reviews in the green / amber / red SLO buckets |

**Identifier.** The analytics SDK generates a random UUID, SHA-256-hashed, stored locally in
UserDefaults. It is pseudonymous — Hubber never supplies your GitHub login, email, or any other
personal data as the identifier.

**Processor.** Analytics are processed by [TelemetryDeck](https://telemetrydeck.com), a
privacy-focused analytics service. Data is hosted in the European Union (Hetzner, Nuremberg;
some infrastructure currently at Azure Amsterdam / AWS Frankfurt, consolidating to Hetzner during
2026). TelemetryDeck offers a Data Processing Agreement (DPA). TelemetryDeck positions the data as
anonymized/non-personal; Hubber takes the conservative stance and treats the hashed identifier as
pseudonymous personal data, which is why analytics are opt-in.

**Lawful basis (GDPR).** Consent (Art. 6(1)(a)) — opt-in, off by default.

**Retention.** Per TelemetryDeck's data-retention policy (see their privacy documentation).

**How to opt out.** Turn off "Share anonymous usage analytics" in Settings → Privacy. It takes
effect immediately — no restart — and stops all further events.

## Crash & hang diagnostics (local only)

Hubber subscribes to Apple's MetricKit to log crash and hang summaries to your Mac's local system
log (`os_log`) for debugging. **This data never leaves your device** and is not sent to Hubber or
any third party. You can disable it under Settings → Privacy ("Diagnostic logging").

## Authentication

Your code-host access token is stored in the macOS Keychain (release builds) and used only to talk
directly to your code host (GitHub, GitHub Enterprise Server, or GitLab). It is never sent to us.

## Questions

Open an issue at https://github.com/osuritz/hubber.
```

- [ ] **Step 2: Fix the dishonest crash-reporting label**

In `Sources/Hubber/HubberSettingsView.swift`, replace the crash-reporting `SettingsRow` (lines 171-185). Change the title/subtitle to reflect local-only handling (do not change the binding or the `isLocked` check):

```swift
                    // Crash reporting toggle — LOCAL os_log only (transmits nothing). Label must
                    // not imply transmission. See #104.
                    SettingsRow(isLast: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Diagnostic logging")
                                .font(HubberType.settingsLabel)
                                .foregroundStyle(HubberDesign.text)
                            Text("Crash & hang diagnostics are written to your Mac's local log only — never sent anywhere.")
                                .font(HubberType.settingsSub)
                                .foregroundStyle(HubberDesign.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("", isOn: $settings.crashReportingEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(settings.isLocked(ManagedKey.crashReportingEnabled))
                    }
```

Note: this row's `isLast` flips from `true` to `false` because we add a new last row below it.

- [ ] **Step 3: Add the privacy-policy link row + the shared URL**

Add the link constant. At the top of `Sources/Hubber/HubberSettingsView.swift` (after `import SwiftUI`), add:

```swift
/// Stable in-app privacy-policy link (GitHub-hosted PRIVACY.md). Reused by the onboarding
/// consent step. See #104.
enum PrivacyLinks {
    static let privacyPolicy = URL(string: "https://github.com/osuritz/hubber/blob/main/PRIVACY.md")!
}
```

Then add a final row in the Privacy `SettingsGroup`, after the crash-reporting row:

```swift
                    // Privacy policy link (#104)
                    SettingsRow(isLast: true) {
                        Text("Privacy Policy")
                            .font(HubberType.settingsLabel)
                            .foregroundStyle(HubberDesign.text)
                        Spacer()
                        Button("Read") { NSWorkspace.shared.open(PrivacyLinks.privacyPolicy) }
                            .buttonStyle(.plain)
                            .font(HubberType.settingsSub)
                            .foregroundStyle(HubberDesign.accent)
                    }
```

Add `import AppKit` at the top of the file if `NSWorkspace` is not already in scope (it isn't — only `import SwiftUI` is present).

- [ ] **Step 4: Build and verify**

Run: `swift build`
Expected: compiles. Then `make ci` → pass (no test changes, but lint/format must be clean).

- [ ] **Step 5: Manual verification**

`make app-dev`, open Settings → Privacy. Confirm the crash row reads "Diagnostic logging" with the local-only subtitle, and "Privacy Policy → Read" opens the GitHub PRIVACY.md page.

- [ ] **Step 6: Commit**

```bash
git add PRIVACY.md Sources/Hubber/HubberSettingsView.swift
git commit -m "docs(privacy): add PRIVACY.md, honest crash label + in-app link

Closes #104"
```

---

## Task 5: Consent step UI

Replaces the consent stub with the real GDPR opt-in step. Completes #102.

**Files:**
- Modify: `Sources/Hubber/Onboarding/OnboardingSteps.swift` (add `OnboardingConsentStep`)
- Modify: `Sources/Hubber/Onboarding/OnboardingFlow.swift` (use the real step)

**Interfaces:**
- Consumes: `OnboardingCoordinator.advance()`; `HubberStore.settings.analyticsEnabled`; `PrivacyLinks.privacyPolicy` (Task 4); `GatedTelemetrySink` wiring (Task 3, already live — setting `analyticsEnabled = true` enables the gate via the subscription).
- Produces: `struct OnboardingConsentStep: View` with `init(coordinator:store:)`.

- [ ] **Step 1: Build the consent step**

Add to `Sources/Hubber/Onboarding/OnboardingSteps.swift`. Two equal-weight buttons; "Not now" must not be visually de-emphasized into a dark pattern — both are full-width buttons, "Enable" filled (primary `SignInButtonStyle`), "Not now" a bordered/secondary style of equal size.

```swift
import AppKit

// MARK: - Analytics consent (#102)

struct OnboardingConsentStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var store: HubberStore
    @Environment(\.colorScheme) private var colorScheme

    /// When MDM forces analyticsEnabled, the choice is not the user's to make — show the
    /// managed state and let them continue (the gate already reflects the forced value).
    private var isManaged: Bool { store.settings.isLocked(ManagedKey.analyticsEnabled) }

    var body: some View {
        OnboardingScaffold(stepIndex: 1, stepCount: OnboardingCoordinator.Step.allCases.count) {
            VStack(spacing: 0) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(HubberDesign.accent)
                    .padding(.bottom, 16)

                Text("Help improve Hubber?")
                    .font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                    .foregroundStyle(HubberDesign.text).padding(.bottom, 8)

                Text("Share anonymous usage data — counts and timings only. Never repo names, PR titles, logins, or any personal data. You can change this anytime in Settings.")
                    .font(.system(size: 12.5)).foregroundStyle(HubberDesign.text2)
                    .multilineTextAlignment(.center).lineSpacing(3)
                    .frame(maxWidth: 264).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)

                if isManaged {
                    managedNotice
                } else {
                    choiceButtons
                }

                Button("Read our Privacy Policy") { NSWorkspace.shared.open(PrivacyLinks.privacyPolicy) }
                    .buttonStyle(.plain).font(.system(size: 11))
                    .foregroundStyle(HubberDesign.accent).padding(.top, 14)
            }
        }
    }

    private var choiceButtons: some View {
        VStack(spacing: 10) {
            Button {
                store.settings.analyticsEnabled = true
                coordinator.advance()
            } label: {
                Text("Enable analytics").font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 16)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: colorScheme)).frame(maxWidth: 264)

            Button {
                store.settings.analyticsEnabled = false
                coordinator.advance()
            } label: {
                Text("Not now").font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 16)
                    .foregroundStyle(HubberDesign.text)
                    .background(HubberDesign.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(HubberDesign.sep, lineWidth: 0.5) }
            }
            .buttonStyle(.plain).frame(maxWidth: 264)
        }
    }

    private var managedNotice: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 11))
                Text(store.settings.analyticsEnabled
                    ? "Analytics is enabled by your organization."
                    : "Analytics is disabled by your organization.")
                    .font(.system(size: 11))
            }
            .foregroundStyle(HubberDesign.text2)
            Button { coordinator.advance() } label: {
                Text("Continue").font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 16)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: colorScheme)).frame(maxWidth: 264)
        }
    }
}
```

(If `HubberDesign.fill`/`.sep` are not the exact token names, use the ones referenced in `DeviceCodeScreen` in `SignInScreen.swift:187,192` — `HubberDesign.fill` and `HubberDesign.sep` are used there, so they exist.)

- [ ] **Step 2: Use the real step in the flow**

In `Sources/Hubber/Onboarding/OnboardingFlow.swift`, replace the `.consent` case:

```swift
            case .consent:
                OnboardingConsentStep(coordinator: coordinator, store: store)
```

- [ ] **Step 3: Build + gate**

Run: `swift build` then `make ci`
Expected: pass.

- [ ] **Step 4: Manual verification (the GDPR-critical assertion)**

`make app-dev` with a clean profile (`defaults delete com.osuritz.hubber`). Onboard to the consent step. Pick **"Not now"** → finish onboarding → open the panel a few times / switch tabs (this would emit `session.opened`/`tab.switched`). Confirm via Console.app (filter subsystem `com.hubber.app` or the TelemetryDeck test logging) that **no analytics signal is sent**. Then Settings → Privacy → enable analytics → confirm subsequent events flow. This is the manual confirmation of "fresh install sends NO telemetry until opt-in" + the live gate.

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Onboarding/OnboardingSteps.swift Sources/Hubber/Onboarding/OnboardingFlow.swift
git commit -m "feat(onboarding): GDPR consent step (opt-in, default off)

Closes #102"
```

---

## Task 6: Guided first-account connection step

Replaces the connect stub. Reuses the existing device-flow machinery; on success, advances the flow (instead of the normal reveal). Completes #105.

**Files:**
- Modify: `Sources/Hubber/Onboarding/OnboardingSteps.swift` (add `OnboardingConnectStep`)
- Modify: `Sources/Hubber/Onboarding/OnboardingFlow.swift`

**Interfaces:**
- Consumes: `HubberStore.authState`, `connections`, `startSignIn()`, `cancelSignIn()`, `openDeviceVerificationPage()`, `copyDeviceCode()`; `OnboardingCoordinator.advance()`, `skipConnectIfAlreadyConnected(_:)`; existing `DeviceCodeScreen` and `AddAccountView`.
- Produces: `struct OnboardingConnectStep: View`.

Notes on `authState` values (from `HubberAuthState`): `.signedOut`, `.waitingForUser(GitHubDeviceAuthorization)`, `.signedIn(login:)`, `.error(String)`, `.restoring`, `.sessionExpired`. The connect step branches on these.

- [ ] **Step 1: Build the connect step**

Add to `Sources/Hubber/Onboarding/OnboardingSteps.swift`. The step:
- On appear, if already connected (`store.authState` is `.signedIn` OR `!store.connections.isEmpty`), calls `coordinator.skipConnectIfAlreadyConnected(true)`.
- `.signedOut`/`.error` → a connect prompt (reuse the look of `SignInScreen`'s sign-in button) + an "Add GitHub Enterprise or GitLab…" affordance opening the existing `AddAccountView` sheet. On `.error`, show the message inline with a retry (the retry is just "Sign in with GitHub" again).
- `.waitingForUser(auth)` → embed `DeviceCodeScreen(store:authorization:)` (already handles copy/open/cancel).
- `.signedIn` → call `coordinator.advance()` (advance the flow; do NOT show the normal success screen).

```swift
struct OnboardingConnectStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var store: HubberStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAdd = false

    private var isRestricted: Bool { !store.settings.providerAccessPolicy.canConnectGitHubDotCom }

    var body: some View {
        OnboardingScaffold(stepIndex: 2, stepCount: OnboardingCoordinator.Step.allCases.count) {
            content
        }
        .onAppear {
            if case .signedIn = store.authState { coordinator.skipConnectIfAlreadyConnected(true) }
            else if !store.connections.isEmpty { coordinator.skipConnectIfAlreadyConnected(true) }
        }
        .onChange(of: store.authState) { _, newState in
            if case .signedIn = newState { coordinator.advance() }
        }
        .sheet(isPresented: $showingAdd) { addAccountSheet }
    }

    @ViewBuilder private var content: some View {
        switch store.authState {
        case let .waitingForUser(authorization):
            DeviceCodeScreen(store: store, authorization: authorization)
        case let .error(message):
            connectPrompt(errorMessage: message)
        default:
            connectPrompt(errorMessage: nil)
        }
    }

    private func connectPrompt(errorMessage: String?) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 26, weight: .medium)).foregroundStyle(HubberDesign.accent).padding(.bottom, 16)
            Text("Connect your account")
                .font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                .foregroundStyle(HubberDesign.text).padding(.bottom, 8)
            Text("Sign in with GitHub to start seeing the PRs waiting on you. Hubber only requests read-only access.")
                .font(.system(size: 12.5)).foregroundStyle(HubberDesign.text2)
                .multilineTextAlignment(.center).lineSpacing(3)
                .frame(maxWidth: 264).fixedSize(horizontal: false, vertical: true).padding(.bottom, 18)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11)).foregroundStyle(HubberDesign.sloRed.fg)
                    .multilineTextAlignment(.center).frame(maxWidth: 264).padding(.bottom, 12)
            }

            Button { store.startSignIn() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle").font(.system(size: 17))
                    Text(errorMessage == nil ? "Sign in with GitHub" : "Try again")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 16)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: colorScheme)).frame(maxWidth: 264)
            .disabled(isRestricted).opacity(isRestricted ? 0.45 : 1)

            if isRestricted {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 11))
                    Text("Sign-in is restricted by your organization.").font(.system(size: 11))
                }
                .foregroundStyle(HubberDesign.text2).padding(.top, 10)
            }

            Button("Add GitHub Enterprise or GitLab…") { showingAdd = true }
                .buttonStyle(.plain).font(.system(size: 11))
                .foregroundStyle(HubberDesign.text2).padding(.top, 12)
        }
    }

    private var addAccountSheet: some View {
        AddAccountView(
            policy: store.settings.providerAccessPolicy,
            isDuplicate: { [weak store] id in store?.connections.contains { $0.id == id } ?? false },
            addAccount: { [weak store] id, token, user in
                _ = try await store?.addResolvedAccount(id: id, token: token, user: user)
            },
            onActiveChange: { store.setAddingAccount($0) },
            onDone: { showingAdd = false }
        )
    }
}
```

(The `addAccountSheet` mirrors `HubberPopoverView.addAccountSheet` exactly — keep the signatures identical.)

- [ ] **Step 2: Use the real step in the flow**

In `Sources/Hubber/Onboarding/OnboardingFlow.swift`:

```swift
            case .connect:
                OnboardingConnectStep(coordinator: coordinator, store: store)
```

- [ ] **Step 3: Build + gate**

Run: `swift build` then `make ci`
Expected: pass.

- [ ] **Step 4: Manual verification**

`make app-dev`, clean profile. Onboard through consent to connect. Complete the real device flow → on success the flow advances to the Notifications stub (not the normal app). Test edges: cancel mid-device-flow returns to the prompt; an auth error shows inline with "Try again". Then test the already-connected case: with an existing connection and a reset `onboardingCompleted=false`, the connect step auto-advances on appear.

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Onboarding/OnboardingSteps.swift Sources/Hubber/Onboarding/OnboardingFlow.swift
git commit -m "feat(onboarding): guided first-account connection step

Closes #105"
```

---

## Task 7: Notification-permission priming step

Replaces the notifications stub with a soft pre-prompt. Completes #107.

**Files:**
- Modify: `Sources/Hubber/Onboarding/OnboardingSteps.swift` (add `OnboardingNotificationsStep`)
- Modify: `Sources/Hubber/Onboarding/OnboardingFlow.swift`

**Interfaces:**
- Consumes: `HubberStore.requestNotificationAuthorization() async` (`GitHubAuth.swift:672`), `HubberStore.notificationsDenied` (`@Published`, `:320`); `OnboardingCoordinator.advance()`.
- Produces: `struct OnboardingNotificationsStep: View`.

Behavior: a soft pre-prompt explaining *why* Hubber notifies. "Enable notifications" calls `await store.requestNotificationAuthorization()` (the ONLY thing that triggers the real macOS dialog), then advances. "Not now" advances without touching `UNUserNotificationCenter`. If `store.notificationsDenied` is already true, show System-Settings guidance instead of re-prompting. The bundle guard lives inside `ensureAuthorized()` already, so this view never touches `UNUserNotificationCenter` directly.

- [ ] **Step 1: Build the notifications step**

Add to `Sources/Hubber/Onboarding/OnboardingSteps.swift`:

```swift
struct OnboardingNotificationsStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var store: HubberStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var requesting = false

    var body: some View {
        OnboardingScaffold(stepIndex: 3, stepCount: OnboardingCoordinator.Step.allCases.count) {
            VStack(spacing: 0) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 26, weight: .medium)).foregroundStyle(HubberDesign.accent).padding(.bottom, 16)
                Text("Stay in the loop")
                    .font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                    .foregroundStyle(HubberDesign.text).padding(.bottom, 8)
                Text("Get a heads-up the moment a review is requested from you. You control exactly which events notify you in Settings.")
                    .font(.system(size: 12.5)).foregroundStyle(HubberDesign.text2)
                    .multilineTextAlignment(.center).lineSpacing(3)
                    .frame(maxWidth: 264).fixedSize(horizontal: false, vertical: true).padding(.bottom, 18)

                if store.notificationsDenied {
                    deniedGuidance
                } else {
                    choiceButtons
                }
            }
        }
    }

    private var choiceButtons: some View {
        VStack(spacing: 10) {
            Button {
                requesting = true
                Task {
                    await store.requestNotificationAuthorization()
                    requesting = false
                    coordinator.advance()
                }
            } label: {
                Text(requesting ? "Requesting…" : "Enable notifications")
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 16)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: colorScheme)).frame(maxWidth: 264).disabled(requesting)

            Button { coordinator.advance() } label: {
                Text("Not now").font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 16)
                    .foregroundStyle(HubberDesign.text)
                    .background(HubberDesign.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(HubberDesign.sep, lineWidth: 0.5) }
            }
            .buttonStyle(.plain).frame(maxWidth: 264)
        }
    }

    private var deniedGuidance: some View {
        VStack(spacing: 10) {
            Text("Notifications are turned off for Hubber in macOS. You can enable them in System Settings → Notifications → Hubber.")
                .font(.system(size: 11)).foregroundStyle(HubberDesign.text2)
                .multilineTextAlignment(.center).frame(maxWidth: 264)
            Button { coordinator.advance() } label: {
                Text("Continue").font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 16)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: colorScheme)).frame(maxWidth: 264)
        }
    }
}
```

- [ ] **Step 2: Use the real step in the flow**

In `Sources/Hubber/Onboarding/OnboardingFlow.swift`:

```swift
            case .notifications:
                OnboardingNotificationsStep(coordinator: coordinator, store: store)
```

- [ ] **Step 3: Build + gate**

Run: `swift build` then `make ci`
Expected: pass. (No new unit test — this view only calls the already-tested `requestNotificationAuthorization()`; do NOT add a test that instantiates `UNUserNotificationCenter` in the bundle-less host.)

- [ ] **Step 4: Manual verification**

`make app-dev`, clean profile, reach the notifications step. "Enable notifications" → the real macOS dialog appears once; accepting/declining advances. "Not now" → advances with no dialog (verify no system prompt fires). Confirm M3 behavior is intact: no notification fires on the first sync after onboarding (baseline).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Onboarding/OnboardingSteps.swift Sources/Hubber/Onboarding/OnboardingFlow.swift
git commit -m "feat(onboarding): notification-permission priming step

Closes #107"
```

---

## Task 8: Launch-at-login (service + setting + onboarding step + Settings toggle)

The largest task: a testable launch-at-login service, an MDM-lockable setting, the onboarding step, the Settings toggle, and the launch-time reconcile. Completes #106.

**Files:**
- Create: `Sources/Hubber/Core/LaunchAtLogin.swift`
- Create: `Tests/HubberTests/LaunchAtLoginTests.swift`
- Modify: `Sources/Hubber/Core/ManagedPreferences.swift` (add `ManagedKey.launchAtLogin`)
- Modify: `Sources/Hubber/Core/SettingsStore.swift` (add `launchAtLoginEnabled`)
- Modify: `Sources/Hubber/GitHubAuth.swift` (`HubberStore`: hold the service; add `setLaunchAtLogin(_:)` + `reconcileLaunchAtLogin()`)
- Modify: `Sources/Hubber/main.swift` (call `store.reconcileLaunchAtLogin()` at launch)
- Modify: `Sources/Hubber/Onboarding/OnboardingSteps.swift` (add `OnboardingLaunchAtLoginStep`)
- Modify: `Sources/Hubber/Onboarding/OnboardingFlow.swift`
- Modify: `Sources/Hubber/HubberSettingsView.swift` (Settings toggle)
- Modify: `Tests/HubberTests/SettingsStoreTests.swift` (launchAtLogin resolution tests)

**Interfaces:**
- Produces:
  - `protocol LaunchAtLoginManaging: Sendable { var isEnabled: Bool { get }; func setEnabled(_ enabled: Bool) throws }`
  - `struct SMAppServiceLaunchAtLogin: LaunchAtLoginManaging`
  - `SettingsStore.launchAtLoginEnabled: Bool` (MDM→UserDefaults→`false`; `isLocked(ManagedKey.launchAtLogin)`)
  - `HubberStore.setLaunchAtLogin(_ enabled: Bool)` — persists `settings.launchAtLoginEnabled` and applies via the service.
  - `HubberStore.reconcileLaunchAtLogin()` — applies the resolved desired state to the system at launch.
  - `ManagedKey.launchAtLogin = "launchAtLogin"`
- Consumes: existing `SettingsStore.bool(...)`/`isLocked`, `InMemoryManagedPreferences` (tests).

- [ ] **Step 1: Write the failing tests (service + setting)**

Create `Tests/HubberTests/LaunchAtLoginTests.swift`:

```swift
import Foundation
import XCTest
@testable import Hubber

/// In-memory fake — never touches SMAppService.
final class FakeLaunchAtLogin: LaunchAtLoginManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var _enabled: Bool
    private var _calls: [Bool] = []
    init(enabled: Bool = false) { _enabled = enabled }
    var isEnabled: Bool { lock.withLock { _enabled } }
    var calls: [Bool] { lock.withLock { _calls } }
    func setEnabled(_ enabled: Bool) throws { lock.withLock { _enabled = enabled; _calls.append(enabled) } }
}

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    private var defaults: UserDefaults!
    private nonisolated(unsafe) var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "LaunchAtLoginTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultLaunchAtLoginIsFalse() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.launchAtLoginEnabled)
    }

    func testLaunchAtLoginPersists() {
        let store = SettingsStore(defaults: defaults)
        store.launchAtLoginEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "launchAtLogin"))
    }

    func testForcedLaunchAtLoginWinsAndLocks() {
        let managed = InMemoryManagedPreferences([ManagedKey.launchAtLogin: true])
        let store = SettingsStore(defaults: defaults, managed: managed)
        XCTAssertTrue(store.launchAtLoginEnabled)
        XCTAssertTrue(store.isLocked(ManagedKey.launchAtLogin))
    }

    func testFakeServiceRecordsSetCalls() throws {
        let fake = FakeLaunchAtLogin()
        try fake.setEnabled(true)
        XCTAssertTrue(fake.isEnabled)
        XCTAssertEqual(fake.calls, [true])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LaunchAtLoginTests`
Expected: FAIL — `LaunchAtLoginManaging` / `launchAtLoginEnabled` / `ManagedKey.launchAtLogin` not found.

- [ ] **Step 3: Add the managed key**

In `Sources/Hubber/Core/ManagedPreferences.swift`, add to the `ManagedKey` enum (after `allowPersonalGitHub`, line 103):

```swift

    // Launch at login
    static let launchAtLogin = "launchAtLogin"
```

Add a row to the doc table comment (lines 60-74) for completeness:

```swift
//   launchAtLogin               Bool         launchAtLogin           launchAtLoginEnabled
```

- [ ] **Step 4: Add the setting**

In `Sources/Hubber/Core/SettingsStore.swift`, add a published property (e.g. after the `crashReportingEnabled` block, line 66):

```swift
    /// Whether Hubber registers itself as a macOS login item. MDM-lockable. The actual
    /// SMAppService registration is applied by HubberStore; this is the persisted desired state. (#106)
    @Published var launchAtLoginEnabled: Bool {
        didSet { defaults.set(launchAtLoginEnabled, forKey: ManagedKey.launchAtLogin) }
    }
```

In `init`, resolve it (e.g. after `crashReportingEnabled = ...`, line 169):

```swift
        launchAtLoginEnabled = Self.bool(
            managedKey: ManagedKey.launchAtLogin,
            defaultsKey: ManagedKey.launchAtLogin,
            defaults: defaults,
            managed: managed,
            fallback: false
        )
```

(`isLocked(ManagedKey.launchAtLogin)` already works via the default `managed.isForced` path — no change needed.)

- [ ] **Step 5: Implement the service**

Create `Sources/Hubber/Core/LaunchAtLogin.swift`:

```swift
import Foundation
import ServiceManagement

/// Registers/unregisters Hubber as a macOS login item. Injectable so the logic that drives it
/// is testable without touching the real SMAppService (which requires a real .app bundle). (#106)
protocol LaunchAtLoginManaging: Sendable {
    /// True when Hubber is currently registered as a login item.
    var isEnabled: Bool { get }
    /// Registers (enabled) or unregisters (disabled) the login item.
    func setEnabled(_ enabled: Bool) throws
}

/// Production implementation backed by `SMAppService.mainApp` (macOS 13+).
///
/// Guarded on a real `.app` bundle: `SMAppService` register/unregister throw or no-op outside one
/// (e.g. `swift run` / xctest), so we never call it there — mirrors the notification bundle guard.
struct SMAppServiceLaunchAtLogin: LaunchAtLoginManaging {
    private var isBundledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var isEnabled: Bool {
        guard isBundledApp else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard isBundledApp else { return }
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        }
    }
}
```

- [ ] **Step 6: Run service + setting tests**

Run: `swift test --filter LaunchAtLoginTests`
Expected: PASS (4 tests).

- [ ] **Step 7: Wire the service into HubberStore**

In `Sources/Hubber/GitHubAuth.swift`:

a) Add an init parameter (after `connectionFactory:`, line 418) and a stored property:

```swift
        launchAtLogin: any LaunchAtLoginManaging = SMAppServiceLaunchAtLogin(),
```

Stored property (near `private let fallbackProvider`):

```swift
    private let launchAtLogin: any LaunchAtLoginManaging
```

Assign in init body (e.g. near `self.settings = settings`):

```swift
        self.launchAtLogin = launchAtLogin
```

b) Add the two methods (anywhere in the `HubberStore` body, e.g. near `requestNotificationAuthorization`):

```swift
    /// Sets the launch-at-login preference: persists the desired state and applies it to the system.
    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLoginEnabled = enabled
        try? launchAtLogin.setEnabled(enabled)
    }

    /// Applies the resolved (incl. MDM-forced) desired launch-at-login state to the system at launch.
    func reconcileLaunchAtLogin() {
        try? launchAtLogin.setEnabled(settings.launchAtLoginEnabled)
    }
```

- [ ] **Step 8: Reconcile at launch**

In `Sources/Hubber/main.swift`, in `applicationDidFinishLaunching` after `store.restoreAllConnections()` (line 105), add:

```swift
        store.reconcileLaunchAtLogin()
```

- [ ] **Step 9: Add the onboarding step**

Add to `Sources/Hubber/Onboarding/OnboardingSteps.swift`:

```swift
struct OnboardingLaunchAtLoginStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var store: HubberStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        OnboardingScaffold(stepIndex: 4, stepCount: OnboardingCoordinator.Step.allCases.count) {
            VStack(spacing: 0) {
                Image(systemName: "power")
                    .font(.system(size: 26, weight: .medium)).foregroundStyle(HubberDesign.accent).padding(.bottom, 16)
                Text("Open at login")
                    .font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                    .foregroundStyle(HubberDesign.text).padding(.bottom, 8)
                Text("Hubber works best running quietly in your menu bar. Open it automatically when you log in so you never miss a review.")
                    .font(.system(size: 12.5)).foregroundStyle(HubberDesign.text2)
                    .multilineTextAlignment(.center).lineSpacing(3)
                    .frame(maxWidth: 264).fixedSize(horizontal: false, vertical: true).padding(.bottom, 18)

                VStack(spacing: 10) {
                    Button { store.setLaunchAtLogin(true); coordinator.advance() } label: {
                        Text("Open Hubber at login").font(.system(size: 13.5, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 16)
                    }
                    .buttonStyle(SignInButtonStyle(colorScheme: colorScheme)).frame(maxWidth: 264)

                    Button { coordinator.advance() } label: {
                        Text("Not now").font(.system(size: 13.5, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 16)
                            .foregroundStyle(HubberDesign.text)
                            .background(HubberDesign.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(HubberDesign.sep, lineWidth: 0.5) }
                    }
                    .buttonStyle(.plain).frame(maxWidth: 264)
                }
            }
        }
    }
}
```

In `Sources/Hubber/Onboarding/OnboardingFlow.swift`:

```swift
            case .launchAtLogin:
                OnboardingLaunchAtLoginStep(coordinator: coordinator, store: store)
```

- [ ] **Step 10: Add the Settings toggle**

In `Sources/Hubber/HubberSettingsView.swift`, add a new `SettingsSection` (place it after "Appearance", before "Menubar Badge", or wherever fits the existing order — a "General" section is fine):

```swift
            // Launch at login (#106)
            SettingsSection(title: "General") {
                SettingsGroup {
                    SettingsRow(isLast: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open at login")
                                .font(HubberType.settingsLabel)
                                .foregroundStyle(HubberDesign.text)
                            Text("Start Hubber automatically when you log in.")
                                .font(HubberType.settingsSub)
                                .foregroundStyle(HubberDesign.text2)
                        }
                        Toggle("", isOn: Binding(
                            get: { settings.launchAtLoginEnabled },
                            set: { store.setLaunchAtLogin($0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(settings.isLocked(ManagedKey.launchAtLogin))
                    }
                }
            }
```

- [ ] **Step 11: Build + gate**

Run: `swift build` then `make ci`
Expected: pass (LaunchAtLoginTests + all existing).

- [ ] **Step 12: Manual verification (requires the packaged .app)**

`make app-dev`, clean profile. Reach the launch-at-login step → "Open Hubber at login". Verify in System Settings → General → Login Items that **Hubber** appears. Quit + relaunch → still listed (reconcile holds it). Toggle it off in Settings → Privacy/General → it disappears from Login Items. (Login items require a real bundle; `make app-dev` provides one.)

- [ ] **Step 13: Commit**

```bash
git add Sources/Hubber/Core/LaunchAtLogin.swift Tests/HubberTests/LaunchAtLoginTests.swift Sources/Hubber/Core/ManagedPreferences.swift Sources/Hubber/Core/SettingsStore.swift Sources/Hubber/GitHubAuth.swift Sources/Hubber/main.swift Sources/Hubber/Onboarding/OnboardingSteps.swift Sources/Hubber/Onboarding/OnboardingFlow.swift Sources/Hubber/HubberSettingsView.swift Tests/HubberTests/SettingsStoreTests.swift
git commit -m "feat(onboarding): launch-at-login via SMAppService + setting

Closes #106"
```

---

## Final: whole-branch verification

- [ ] Run `make ci` once more on the full branch — build + all tests + lint + format-lint green.
- [ ] Optional headless CI signal: `gh workflow run swift.yml --ref worktree-m7` (macos-26).
- [ ] Full manual smoke (`make app-dev`, clean profile): welcome → consent (pick each path) → connect (device flow) → notifications → launch-at-login → populated popover; relaunch → no onboarding; Settings reflects every choice (analytics, diagnostics label, privacy link, launch-at-login).
- [ ] Open the PR; body closes all seven: `Closes #101 #102 #103 #104 #105 #106 #107`.

---

## Self-Review (completed during planning)

**Spec coverage:** #101 → Tasks 1–2; #102 → Tasks 3 (default) + 5 (UI); #103 → Task 3; #104 → Task 4; #105 → Task 6; #107 → Task 7; #106 → Task 8. All seven issues + the edge cases (resume, already-connected, MDM-forced analytics, OS-denied notifications, bundle guard, restricted provider) are covered. **Deviation from spec §3:** the `analyticsConsentDecided` flag is dropped (YAGNI — nothing reads it; default-OFF + the always-shown consent step already guarantee "no signal before a choice"). The "no signal before consent" guarantee is preserved by the default-false + live gate.

**Placeholder scan:** no TBD/TODO; logic + tests are complete code; views are complete and follow `SignInScreen` tokens. View-only tasks use compile + manual verification (no SwiftUI snapshot harness exists in this repo) — this is called out explicitly, not hidden.

**Type consistency:** `OnboardingCoordinator.Step`, `advance()`, `skipConnectIfAlreadyConnected(_:)`, `GatedTelemetrySink(enabled:underlying:initializeSDK:)`/`setEnabled(_:)`, `LaunchAtLoginManaging.setEnabled(_:)`/`isEnabled`, `HubberStore.setLaunchAtLogin(_:)`/`reconcileLaunchAtLogin()`, `PrivacyLinks.privacyPolicy`, `ManagedKey.launchAtLogin` — names are consistent across all tasks that consume them.
