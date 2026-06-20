# Accessibility Audit & Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Hubber's onboarding, popover, Settings, and menu-bar item to WCAG 2.1 AA + macOS accessibility conventions, without changing the visual design (except minimal, flagged contrast-token tweaks).

**Architecture:** Extract the *semantic content* VoiceOver speaks into pure, unit-tested functions (`AccessibilityText`); verify contrast with a code gate (`ContrastRatio` + token sweep test); centralize preference gating (`AccessibilityGates`); then wire these into the views. Dynamic Type is built last as a revertable phase.

**Tech Stack:** Swift 6.3, SwiftUI + AppKit, SwiftPM. Tests use **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — match `Tests/HubberTests/HubberDesignTests.swift`. Test target: `HubberTests`.

## Global Constraints

- **Swift 6.3 / macOS 14+ floor.** New view-facing types are `@MainActor` where they touch SwiftUI/AppKit (match existing files). Pure logic (`AccessibilityText`, `ContrastRatio`, `AccessibilityGates` math) is non-isolated and `Sendable`-safe.
- **No visual redesign.** Only contrast-token values may change, and only by the minimal delta to reach AA; every such change is listed in the PR body with before/after ratio for design sign-off.
- **Pre-push gate is `make ci`** (build + test + lint + swiftformat --lint). Every task ends green under `swift test`; the final push runs `make ci`.
- **Conventional Commits**, tie to the issue with `Closes #63` on the final commit. **No co-author trailers.**
- **CI is manual-only** — the pre-push `make ci` hook is the real gate.
- Do **not** instantiate `UNUserNotificationCenter` in a unit test (crashes bundle-less). N/A here but noted.
- New source files live under `Sources/Hubber/Accessibility/` (create the dir); new tests under `Tests/HubberTests/`.

---

## Phase 1 — Testable foundations

### Task 1: Atomic accessibility phrases

**Files:**
- Create: `Sources/Hubber/Accessibility/AccessibilityText.swift`
- Test: `Tests/HubberTests/AccessibilityTextTests.swift`

**Interfaces:**
- Consumes: `PullRequestCI`, `ReviewerState`, `SLOStatus` (from `Models.swift`).
- Produces: `enum AccessibilityText` with `static func ciPhrase(_:) -> String`, `reviewerPhrase(_:) -> String`, `sloPhrase(_:) -> String`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import Hubber

@Suite("AccessibilityText atomic phrases")
struct AccessibilityTextAtomicTests {
    @Test("CI phrases")
    func ciPhrases() {
        #expect(AccessibilityText.ciPhrase(.passing) == "checks passing")
        #expect(AccessibilityText.ciPhrase(.failing) == "checks failing")
        #expect(AccessibilityText.ciPhrase(.running) == "checks running")
        #expect(AccessibilityText.ciPhrase(.pending) == "checks pending")
        #expect(AccessibilityText.ciPhrase(.noChecks) == "no checks")
    }

    @Test("Reviewer phrases")
    func reviewerPhrases() {
        #expect(AccessibilityText.reviewerPhrase(.approved) == "approved")
        #expect(AccessibilityText.reviewerPhrase(.changesRequested) == "changes requested")
        #expect(AccessibilityText.reviewerPhrase(.commented) == "commented")
        #expect(AccessibilityText.reviewerPhrase(.pending) == "review pending")
    }

    @Test("SLO phrases")
    func sloPhrases() {
        #expect(AccessibilityText.sloPhrase(.green) == "on track")
        #expect(AccessibilityText.sloPhrase(.amber) == "due soon")
        #expect(AccessibilityText.sloPhrase(.red) == "overdue")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AccessibilityTextAtomicTests`
Expected: FAIL — `cannot find 'AccessibilityText' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Pure, testable text that VoiceOver speaks. No SwiftUI/AppKit so it unit-tests cleanly.
enum AccessibilityText {
    static func ciPhrase(_ ci: PullRequestCI) -> String {
        switch ci {
        case .passing: "checks passing"
        case .failing: "checks failing"
        case .running: "checks running"
        case .pending: "checks pending"
        case .noChecks: "no checks"
        }
    }

    static func reviewerPhrase(_ state: ReviewerState) -> String {
        switch state {
        case .approved: "approved"
        case .changesRequested: "changes requested"
        case .commented: "commented"
        case .pending: "review pending"
        }
    }

    static func sloPhrase(_ status: SLOStatus) -> String {
        switch status {
        case .green: "on track"
        case .amber: "due soon"
        case .red: "overdue"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AccessibilityTextAtomicTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Accessibility/AccessibilityText.swift Tests/HubberTests/AccessibilityTextTests.swift
git commit -m "feat(a11y): atomic accessibility phrases for CI/reviewer/SLO state"
```

---

### Task 2: Composed row & tab labels

**Files:**
- Modify: `Sources/Hubber/Accessibility/AccessibilityText.swift`
- Modify: `Tests/HubberTests/AccessibilityTextTests.swift`

**Interfaces:**
- Consumes: Task 1 phrases; `Reviewer`, `PullRequestCI`, `SLOStatus`.
- Produces: `AccessibilityText.reviewersSummary(_ reviewers: [Reviewer]) -> String`, `incomingRow(number:title:repo:authorLogin:sloEnabled:sloStatus:sloText:) -> String`, `outgoingRow(number:title:repo:ci:unresolved:reviewers:) -> String`, `draftRow(number:title:repo:ci:commits:) -> String`, `tabValue(count:) -> String`.

- [ ] **Step 1: Write the failing test** (append to the suite file)

```swift
@Suite("AccessibilityText composed labels")
struct AccessibilityTextComposedTests {
    private func user(_ login: String) -> GitHubUser {
        GitHubUser(login: login, initials: "XX", color: .gray)
    }

    @Test("reviewers summary groups by state in canonical order")
    func reviewersSummary() {
        let reviewers = [
            Reviewer(user: user("a"), state: .approved),
            Reviewer(user: user("b"), state: .pending),
            Reviewer(user: user("c"), state: .approved),
        ]
        #expect(AccessibilityText.reviewersSummary(reviewers) == "3 reviewers: 2 approved, 1 review pending")
    }

    @Test("empty reviewers summary")
    func emptyReviewers() {
        #expect(AccessibilityText.reviewersSummary([]) == "no reviewers")
    }

    @Test("incoming row label with SLO")
    func incomingWithSLO() {
        let label = AccessibilityText.incomingRow(
            number: 1234, title: "Fix login crash", repo: "acme/app",
            authorLogin: "alice", sloEnabled: true, sloStatus: .red, sloText: "2h overdue"
        )
        #expect(label == "Pull request 1234, Fix login crash, in acme/app, by alice, review overdue, 2h overdue")
    }

    @Test("incoming row label without SLO")
    func incomingNoSLO() {
        let label = AccessibilityText.incomingRow(
            number: 7, title: "Tweak", repo: "acme/app",
            authorLogin: "bob", sloEnabled: false, sloStatus: nil, sloText: nil
        )
        #expect(label == "Pull request 7, Tweak, in acme/app, by bob")
    }

    @Test("outgoing row label with unresolved threads")
    func outgoing() {
        let label = AccessibilityText.outgoingRow(
            number: 42, title: "Add cache", repo: "acme/app", ci: .failing,
            unresolved: 1, reviewers: [Reviewer(user: user("a"), state: .changesRequested)]
        )
        #expect(label == "Pull request 42, Add cache, in acme/app, checks failing, 1 unresolved thread, 1 reviewer: 1 changes requested")
    }

    @Test("draft row label")
    func draft() {
        let label = AccessibilityText.draftRow(
            number: 9, title: "Spike", repo: "acme/app", ci: .running, commits: 6
        )
        #expect(label == "Draft pull request 9, Spike, in acme/app, checks running, 6 commits")
    }

    @Test("tab value pluralization")
    func tabValue() {
        #expect(AccessibilityText.tabValue(count: 0) == "0 items")
        #expect(AccessibilityText.tabValue(count: 1) == "1 item")
        #expect(AccessibilityText.tabValue(count: 5) == "5 items")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AccessibilityTextComposedTests`
Expected: FAIL — missing members.

- [ ] **Step 3: Write minimal implementation** (append to `AccessibilityText.swift`)

```swift
extension AccessibilityText {
    /// Canonical state order so the summary is deterministic for tests + consistent for users.
    private static let reviewerOrder: [ReviewerState] = [.approved, .changesRequested, .commented, .pending]

    static func reviewersSummary(_ reviewers: [Reviewer]) -> String {
        guard !reviewers.isEmpty else { return "no reviewers" }
        let groups = reviewerOrder.compactMap { state -> String? in
            let n = reviewers.filter { $0.state == state }.count
            return n > 0 ? "\(n) \(reviewerPhrase(state))" : nil
        }
        let noun = reviewers.count == 1 ? "reviewer" : "reviewers"
        return "\(reviewers.count) \(noun): " + groups.joined(separator: ", ")
    }

    static func incomingRow(
        number: Int, title: String, repo: String, authorLogin: String,
        sloEnabled: Bool, sloStatus: SLOStatus?, sloText: String?
    ) -> String {
        var parts = ["Pull request \(number)", title, "in \(repo)", "by \(authorLogin)"]
        if sloEnabled, let sloStatus {
            parts.append("review \(sloPhrase(sloStatus))")
            if let sloText, !sloText.isEmpty { parts.append(sloText) }
        }
        return parts.joined(separator: ", ")
    }

    static func outgoingRow(
        number: Int, title: String, repo: String, ci: PullRequestCI,
        unresolved: Int, reviewers: [Reviewer]
    ) -> String {
        var parts = ["Pull request \(number)", title, "in \(repo)", ciPhrase(ci)]
        if unresolved > 0 {
            parts.append("\(unresolved) unresolved \(unresolved == 1 ? "thread" : "threads")")
        }
        parts.append(reviewersSummary(reviewers))
        return parts.joined(separator: ", ")
    }

    static func draftRow(number: Int, title: String, repo: String, ci: PullRequestCI, commits: Int) -> String {
        let commitText = "\(commits) \(commits == 1 ? "commit" : "commits")"
        return ["Draft pull request \(number)", title, "in \(repo)", ciPhrase(ci), commitText]
            .joined(separator: ", ")
    }

    static func tabValue(count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AccessibilityTextComposedTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Accessibility/AccessibilityText.swift Tests/HubberTests/AccessibilityTextTests.swift
git commit -m "feat(a11y): composed accessibility labels for rows and tabs"
```

---

### Task 3: Contrast ratio gate

**Files:**
- Create: `Tests/HubberTests/ContrastRatio.swift` (test-target utility)
- Create: `Tests/HubberTests/ContrastTests.swift`
- Possibly modify: `Sources/Hubber/Design/HubberDesign.swift` (only if a token fails)

**Interfaces:**
- Consumes: `HubberDesign` tokens; the `performAsCurrentDrawingAppearance` resolution pattern from `HubberDesignTests.swift`.
- Produces: `ContrastRatio` enum with `linearLuminance(_ nsColor: NSColor) -> Double`, `composite(_ fg: NSColor, over bg: NSColor) -> NSColor`, `ratio(_ a: NSColor, _ b: NSColor) -> Double`.

- [ ] **Step 1: Write the failing test** (calibration first — these are pure math with known answers)

```swift
import AppKit
import SwiftUI
import Testing
@testable import Hubber

@Suite("Contrast ratio math")
struct ContrastRatioMathTests {
    @Test("black on white is 21:1")
    func blackWhite() {
        let r = ContrastRatio.ratio(.black, .white)
        #expect(abs(r - 21.0) < 0.1)
    }

    @Test("identical colors are 1:1")
    func identical() {
        let r = ContrastRatio.ratio(.white, .white)
        #expect(abs(r - 1.0) < 0.01)
    }

    @Test("compositing 50% black over white yields mid-gray")
    func composite() {
        let half = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)
        let out = ContrastRatio.composite(half, over: .white).usingColorSpace(.sRGB)!
        #expect(abs(out.redComponent - 0.5) < 0.02)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ContrastRatioMathTests`
Expected: FAIL — `cannot find 'ContrastRatio'`.

- [ ] **Step 3: Implement the utility** (`ContrastRatio.swift`)

```swift
import AppKit

/// WCAG 2.1 relative-luminance + contrast-ratio math, plus alpha compositing.
/// Lives in the test target — it exists to gate design tokens, not ship in the app.
enum ContrastRatio {
    /// Composite a (possibly translucent) foreground over an opaque background.
    static func composite(_ fg: NSColor, over bg: NSColor) -> NSColor {
        guard let f = fg.usingColorSpace(.sRGB), let b = bg.usingColorSpace(.sRGB) else { return fg }
        let a = f.alphaComponent
        return NSColor(
            srgbRed: f.redComponent * a + b.redComponent * (1 - a),
            green: f.greenComponent * a + b.greenComponent * (1 - a),
            blue: f.blueComponent * a + b.blueComponent * (1 - a),
            alpha: 1
        )
    }

    private static func linearize(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// WCAG relative luminance of an opaque color.
    static func luminance(_ color: NSColor) -> Double {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * linearize(c.redComponent)
            + 0.7152 * linearize(c.greenComponent)
            + 0.0722 * linearize(c.blueComponent)
    }

    /// Contrast ratio between two opaque colors (composite translucent ones first).
    static func ratio(_ a: NSColor, _ b: NSColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        let hi = max(la, lb), lo = min(la, lb)
        return (hi + 0.05) / (lo + 0.05)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ContrastRatioMathTests`
Expected: PASS.

- [ ] **Step 5: Write the token-sweep test** (`ContrastTests.swift`)

```swift
import AppKit
import SwiftUI
import Testing
@testable import Hubber

@Suite("Token contrast meets WCAG AA")
struct ContrastTests {
    /// Resolve a SwiftUI Color to its sRGB NSColor in a specific appearance.
    private func resolve(_ color: Color, _ appearance: NSAppearance) -> NSColor {
        var out = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            out = NSColor(color).usingColorSpace(.sRGB) ?? .black
        }
        return out
    }

    private struct Pair {
        let name: String
        let fg: Color
        let bg: Color        // opaque or translucent; composited over base
        let min: Double      // 4.5 text, 3.0 UI/large
    }

    /// Representative opaque base each surface sits on (popover material).
    private func base(_ appearance: NSAppearance) -> NSColor {
        resolve(HubberDesign.materialSolid, appearance)
    }

    private func pairs() -> [Pair] {
        [
            Pair(name: "text on base", fg: HubberDesign.text, bg: HubberDesign.materialSolid, min: 4.5),
            Pair(name: "text2 on base", fg: HubberDesign.text2, bg: HubberDesign.materialSolid, min: 4.5),
            Pair(name: "SLO green fg on its bg", fg: HubberDesign.sloGreen.fg, bg: HubberDesign.sloGreen.bg, min: 4.5),
            Pair(name: "SLO amber fg on its bg", fg: HubberDesign.sloAmber.fg, bg: HubberDesign.sloAmber.bg, min: 4.5),
            Pair(name: "SLO red fg on its bg", fg: HubberDesign.sloRed.fg, bg: HubberDesign.sloRed.bg, min: 4.5),
            Pair(name: "CI passing on base", fg: HubberDesign.ciPassing, bg: HubberDesign.materialSolid, min: 3.0),
            Pair(name: "CI failing on base", fg: HubberDesign.ciFailing, bg: HubberDesign.materialSolid, min: 3.0),
            Pair(name: "accent on base", fg: HubberDesign.accent, bg: HubberDesign.materialSolid, min: 3.0),
        ]
    }

    @Test("all token pairs meet AA in light and dark")
    func tokenPairs() {
        guard let light = NSAppearance(named: .aqua), let dark = NSAppearance(named: .darkAqua) else {
            Issue.record("appearances unavailable"); return
        }
        for appearance in [light, dark] {
            let label = appearance.name == .darkAqua ? "dark" : "light"
            for p in pairs() {
                let bg = ContrastRatio.composite(resolve(p.bg, appearance), over: base(appearance))
                let fg = ContrastRatio.composite(resolve(p.fg, appearance), over: bg)
                let r = ContrastRatio.ratio(fg, bg)
                #expect(r >= p.min, "\(p.name) [\(label)] = \(String(format: "%.2f", r)):1, need \(p.min):1")
            }
        }
    }
}
```

- [ ] **Step 6: Run the sweep; record failures**

Run: `swift test --filter ContrastTests`
Expected: PASS, OR one/more `#expect` failures printing the exact ratio. **If any fail:** for each failing token, edit its value in `HubberDesign.swift` by the smallest delta (darken fg in light, lighten in dark) until it passes; note the old→new hex and old→new ratio for the PR body. Re-run until green. If a token *cannot* reach AA without a visible design change, leave it, mark the `#expect` with a `// KNOWN: needs design decision` comment, and surface it to the reviewer instead of forcing it.

- [ ] **Step 7: Commit**

```bash
git add Tests/HubberTests/ContrastRatio.swift Tests/HubberTests/ContrastTests.swift Sources/Hubber/Design/HubberDesign.swift
git commit -m "test(a11y): WCAG AA contrast gate for design tokens"
```

---

### Task 4: Accessibility preference gates

**Files:**
- Create: `Sources/Hubber/Accessibility/AccessibilityGates.swift`
- Test: `Tests/HubberTests/AccessibilityGatesTests.swift`

**Interfaces:**
- Produces: `enum AccessibilityGates` with `static func pulseEnabled(reduceMotion: Bool) -> Bool` and `static func animation(_ base: Animation, reduceMotion: Bool) -> Animation?`.

- [ ] **Step 1: Write the failing test**

```swift
import SwiftUI
import Testing
@testable import Hubber

@Suite("Accessibility preference gates")
struct AccessibilityGatesTests {
    @Test("pulse disabled under reduce motion")
    func pulse() {
        #expect(AccessibilityGates.pulseEnabled(reduceMotion: false) == true)
        #expect(AccessibilityGates.pulseEnabled(reduceMotion: true) == false)
    }

    @Test("animation nil under reduce motion")
    func animation() {
        #expect(AccessibilityGates.animation(.easeInOut, reduceMotion: false) != nil)
        #expect(AccessibilityGates.animation(.easeInOut, reduceMotion: true) == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter AccessibilityGatesTests`
Expected: FAIL — `cannot find 'AccessibilityGates'`.

- [ ] **Step 3: Implement**

```swift
import SwiftUI

/// Central decisions for system accessibility preferences, so views/AppKit gate uniformly.
enum AccessibilityGates {
    /// The menu-bar refresh pulse animates only when Reduce Motion is off.
    static func pulseEnabled(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// The animation to apply for a transition, or nil to switch state instantly under Reduce Motion.
    static func animation(_ base: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter AccessibilityGatesTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Accessibility/AccessibilityGates.swift Tests/HubberTests/AccessibilityGatesTests.swift
git commit -m "feat(a11y): centralized reduce-motion gating helpers"
```

---

## Phase 2 — Wire foundations into the UI

> Wiring tasks are verified by `swift build` + `swift test` (the called functions are already tested) + the manual runbook (Task 12). Each adds accessibility modifiers only; no behavior/layout change.

### Task 5: VoiceOver semantics — rows, indicators, avatars

**Files:**
- Modify: `Sources/Hubber/HubberRows.swift`
- Modify: `Sources/Hubber/HubberAvatarView.swift`

**Interfaces:**
- Consumes: `AccessibilityText.*` (Tasks 1–2).

- [ ] **Step 1: Group each row into one labeled, button-trait element.** In `IncomingReviewRow.body`, wrap the `RowShell { ... }` with:

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel(AccessibilityText.incomingRow(
    number: review.number, title: review.title, repo: review.repo,
    authorLogin: review.author.login, sloEnabled: isSLOEnabled,
    sloStatus: isSLOEnabled ? sloStatus : nil,
    sloText: isSLOEnabled ? sloText : nil
))
```

(`sloStatus`/`sloText` are the existing private computed vars — they remain.) Do the same for `OutgoingReviewRow` (use `AccessibilityText.outgoingRow(number:title:repo:ci:unresolved:reviewers:)` with `review.reviewers`) and `DraftPRRow` (`AccessibilityText.draftRow(...)`). The row's tap is on the wrapping `ClickableRow` (Task 6) which supplies the `.isButton` trait + hint; here `children: .ignore` collapses inner Text/badges so VoiceOver speaks one phrase.

- [ ] **Step 2: Give standalone indicators text equivalents** (for any context where they are *not* inside a collapsed row — e.g. future reuse). In `SLOPillView.body` add `.accessibilityLabel("Review \(AccessibilityText.sloPhrase(status)), \(text)")`; in `CIBadgeView.body` add `.accessibilityLabel(AccessibilityText.ciPhrase(ci))`. These are harmless when the parent row ignores children.

- [ ] **Step 3: Label avatars + reviewer dots.** In `AvatarView`, add a parameter `var accessibilityRole: String? = nil` and apply:

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel(
    [user.login, accessibilityRole, reviewerState.map(AccessibilityText.reviewerPhrase)]
        .compactMap { $0 }.joined(separator: ", ")
)
```

In `ReviewerStack`, pass nothing extra (the dot state is already covered via `reviewerState`). In `IncomingReviewRow`, pass `accessibilityRole: "author"` to its `AvatarView`. (When the avatar sits inside a `children: .ignore` row, this label is suppressed — it matters only for standalone use such as Settings account rows in Task 7.)

- [ ] **Step 4: Hide decorative glyphs.** Add `.accessibilityHidden(true)` to `RowDot` and to the `Circle()` dot inside `SLOPillView`.

- [ ] **Step 5: Build + test**

Run: `swift build && swift test --filter AccessibilityText`
Expected: builds; tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Hubber/HubberRows.swift Sources/Hubber/HubberAvatarView.swift
git commit -m "feat(a11y): VoiceOver labels for PR rows, indicators, and avatars"
```

---

### Task 6: VoiceOver semantics — tabs, popover chrome, menu-bar

**Files:**
- Modify: `Sources/Hubber/HubberPopoverView.swift` (HubberTabBar ~422–483; ClickableRow ~400–420; header buttons ~179/191)
- Modify: `Sources/Hubber/main.swift` (status item button ~91–101; `updateStatusItem` ~173–205)
- Modify: `Sources/Hubber/Core/MenubarPresentation.swift` (reuse existing `accessibilityValue`)

**Interfaces:**
- Consumes: `AccessibilityText.tabValue(count:)`.

- [ ] **Step 1: Tabs.** In `HubberTabBar`'s per-tab `Button`, add after the label:

```swift
.accessibilityLabel(tab.title)
.accessibilityValue(AccessibilityText.tabValue(count: counts[tab, default: 0]))
.accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
```

- [ ] **Step 2: Clickable rows.** In `ClickableRow` (the row-wrapping Button), add `.accessibilityAddTraits(.isButton)` and `.accessibilityHint("Opens the pull request")` so the grouped row label from Task 5 reads with button semantics.

- [ ] **Step 3: Header buttons.** Ensure Refresh / Settings buttons carry `.accessibilityLabel("Refresh")` / `.accessibilityLabel("Settings")` (they currently rely on `.help()`; keep `.help()` and add the label).

- [ ] **Step 4: Menu-bar button.** In `main.swift` where the status item button is configured, add `button.setAccessibilityLabel("Hubber")` and keep the existing `setAccessibilityValue(...)`. Confirm `MenubarPresentation.accessibilityValue` is still used in `updateStatusItem`.

- [ ] **Step 5: Build**

Run: `swift build`
Expected: builds.

- [ ] **Step 6: Commit**

```bash
git add Sources/Hubber/HubberPopoverView.swift Sources/Hubber/main.swift Sources/Hubber/Core/MenubarPresentation.swift
git commit -m "feat(a11y): VoiceOver labels for tabs, rows, and menu-bar item"
```

---

### Task 7: VoiceOver semantics — Settings

**Files:**
- Modify: `Sources/Hubber/HubberSettingsView.swift`
- Modify: `Sources/Hubber/Settings/AccountsSettingsSection.swift`
- Modify: `Sources/Hubber/Notifications/NotificationsSettingsView.swift`
- Modify: `Sources/Hubber/Design/NativeSegmentedControl.swift`
- Modify: any settings subview using `Toggle("", ...).labelsHidden()` or `NativeSegmentedPicker` (Privacy, General, Developer panel)

**Interfaces:** none new.

- [ ] **Step 1: Toggles get accessible names.** For every `Toggle("", isOn: $x).labelsHidden()`, add `.accessibilityLabel("<the visible sibling Text>")` (e.g. "Enable notifications", "Share analytics", "Open at login"). VoiceOver then reads "<name>, on/off". Keep `.labelsHidden()` for layout.

- [ ] **Step 2: Sliders get value.** On the SLO-hours `Slider`, add `.accessibilityLabel("Review SLO") ` and `.accessibilityValue("\(Int(hours)) hours")`.

- [ ] **Step 3: Segmented pickers get a group label.** Add an optional label to `NativeSegmentedPicker`:

```swift
var accessibilityLabel: String? = nil
// ...in body, on the NativeSegmentedControl():
.accessibilityElement(children: .contain)
.accessibilityLabel(accessibilityLabel ?? "")
```

Then pass it at call sites: "Show SLO as", "Incoming requests", "Unresolved threads", "Row density", "Menubar badge", "Tab badges".

- [ ] **Step 4: Account rows.** In `AccountsSettingsSection.accountRow`, add `.accessibilityElement(children: .combine)` to the row and ensure the status line text (e.g. "Needs attention") is real `Text` (already is) so it's announced. Pass `accessibilityRole: "account"` to the row's `AvatarView`.

- [ ] **Step 5: Build**

Run: `swift build`
Expected: builds.

- [ ] **Step 6: Commit**

```bash
git add Sources/Hubber/HubberSettingsView.swift Sources/Hubber/Settings/AccountsSettingsSection.swift Sources/Hubber/Notifications/NotificationsSettingsView.swift Sources/Hubber/Design/NativeSegmentedControl.swift
git commit -m "feat(a11y): VoiceOver names for settings toggles, sliders, pickers, accounts"
```

---

### Task 8: VoiceOver semantics — onboarding & sign-in

**Files:**
- Modify: `Sources/Hubber/OnboardingSteps.swift`
- Modify: `Sources/Hubber/SignInScreen.swift`

**Interfaces:** none new.

- [ ] **Step 1: Headings as headers.** On each step's title `Text` in `OnboardingScaffold`/steps, add `.accessibilityAddTraits(.isHeader)`.

- [ ] **Step 2: Step dots.** Keep the existing `.accessibilityLabel("Step \(stepIndex + 1) of \(stepCount)")` but add `.accessibilityHidden(false)` is unnecessary; instead add `.accessibilityElement(children: .ignore)` on the `stepDots` container so the individual capsules don't read.

- [ ] **Step 3: Buttons.** Confirm primary/secondary onboarding buttons render their text as the label (they do via `Text`); add `.accessibilityHint` only where the action is non-obvious (e.g. "Add GitHub Enterprise/GitLab" → hint "Opens the device-code flow").

- [ ] **Step 4: Device-code copy button.** In `SignInScreen`, add `.accessibilityLabel("Copy code")` to the copy button (currently only `.help`).

- [ ] **Step 5: Build**

Run: `swift build`
Expected: builds.

- [ ] **Step 6: Commit**

```bash
git add Sources/Hubber/OnboardingSteps.swift Sources/Hubber/SignInScreen.swift
git commit -m "feat(a11y): VoiceOver headers, hints, and labels for onboarding"
```

---

### Task 9: Keyboard navigation & focus

**Files:**
- Modify: `Sources/Hubber/OnboardingFlow.swift` / `OnboardingSteps.swift`
- Modify: `Sources/Hubber/HubberPopoverView.swift`

**Interfaces:** none new.

- [ ] **Step 1: Default focus on onboarding.** Add `@FocusState private var primaryFocused: Bool` to each step (or the scaffold) and `.focused($primaryFocused)` on the primary button, with `.onAppear { primaryFocused = true }`. This makes Return activate the obvious next action.

- [ ] **Step 2: Default focus on popover open.** In `HubberPopoverView`, add a `@FocusState` for the tab bar / first row and set it when the view appears so keyboard users land somewhere predictable.

- [ ] **Step 3: Verify tab order & ring.** Build, run the app (`make app` or the run skill), Tab through onboarding → popover → settings; confirm order matches visual order and a focus ring is visible. Fix order only where wrong (reorder views or add `.accessibilitySortPriority`). Record the walk in the runbook (Task 12).

- [ ] **Step 4: Build**

Run: `swift build`
Expected: builds.

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/OnboardingFlow.swift Sources/Hubber/OnboardingSteps.swift Sources/Hubber/HubberPopoverView.swift
git commit -m "feat(a11y): keyboard focus management for onboarding and popover"
```

---

### Task 10: Reduce Motion

**Files:**
- Modify: `Sources/Hubber/OnboardingFlow.swift` (step transition animation ~25)
- Modify: `Sources/Hubber/SignInScreen.swift` (success animation ~266–358)
- Modify: `Sources/Hubber/main.swift` (`startPulse`/`updateStatusItem`)

**Interfaces:** Consumes `AccessibilityGates` (Task 4).

- [ ] **Step 1: SwiftUI transitions.** Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to `OnboardingFlow` and `SignInScreen`. Replace the animation value with `AccessibilityGates.animation(.easeInOut(duration: 0.2), reduceMotion: reduceMotion)` (and gate the sign-in success spring the same way — when nil, present the final state directly).

- [ ] **Step 2: Menu-bar pulse.** In `main.swift`, before calling `startPulse`, check `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` and only pulse when `AccessibilityGates.pulseEnabled(reduceMotion:)` is true; otherwise set a static alpha (1.0). Observe `NSWorkspace.shared.notificationCenter` `accessibilityDisplayOptionsDidChangeNotification` to re-evaluate if it changes mid-run.

- [ ] **Step 3: Build + test**

Run: `swift build && swift test --filter AccessibilityGatesTests`
Expected: builds; tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Hubber/OnboardingFlow.swift Sources/Hubber/SignInScreen.swift Sources/Hubber/main.swift
git commit -m "feat(a11y): respect Reduce Motion in onboarding, sign-in, and menu-bar pulse"
```

---

### Task 11: Reduce Transparency, Increase Contrast, Differentiate Without Color

**Files:**
- Modify: the `VisualEffectView`/material surfaces (popover background, any vibrancy) — find via `grep -rn "VisualEffectView\|NSVisualEffectView\|.ultraThinMaterial\|.regularMaterial" Sources`
- Modify: `Sources/Hubber/Settings/AccountsSettingsSection.swift` (the "needs attention" signal)

**Interfaces:** none new.

- [ ] **Step 1: Reduce Transparency.** In views using vibrancy/material, add `@Environment(\.accessibilityReduceTransparency) private var reduceTransparency` and render a solid `HubberDesign.materialSolid` fill instead of the translucent material when it's true.

- [ ] **Step 2: Differentiate Without Color.** In `AccountsSettingsSection`, add `@Environment(\.accessibilityDifferentiateWithoutColor) private var diffWithoutColor`. The "needs attention" line already carries a "⚠" glyph; ensure the glyph is always present (not color-only) and the text is announced (it is, via Task 7). For any signal that is color-only, add an SF Symbol when `diffWithoutColor` is true.

- [ ] **Step 3: Increase Contrast.** Where separators/borders are faint (`HubberDesign.sep`), optionally swap to `sepStrong` under `@Environment(\.colorSchemeContrast) == .increased`. Keep minimal.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: builds.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(a11y): honor Reduce Transparency, Increase Contrast, Differentiate Without Color"
```

---

### Task 12: Manual accessibility test runbook

**Files:**
- Create: `docs/runbooks/accessibility-test.md`

**Interfaces:** none.

- [ ] **Step 1: Write the runbook.** Include: (a) VoiceOver end-to-end script — enable VO (⌘F5), open popover, Tab/VO-navigate all three tabs, confirm each row speaks one coherent phrase (number, title, repo, author/CI/reviewer/SLO), open a PR, walk every Settings control confirming name + value, sign in via onboarding confirming step headers + focus; (b) keyboard-only walk confirming focus order + visible ring + every control operable; (c) a checklist for Reduce Motion, Reduce Transparency, Increase Contrast, and larger-text screenshots. Fill in the actual results observed during Tasks 9–11.

- [ ] **Step 2: Commit**

```bash
git add docs/runbooks/accessibility-test.md
git commit -m "docs(a11y): manual VoiceOver + keyboard acceptance runbook"
```

---

## Phase 3 — Dynamic Type (built last; revertable)

> **Checkpoint before starting Phase 3:** confirm with the reviewer that the call-site churn is wanted. On current macOS this phase has limited observable effect (no system Dynamic Type slider); it is future-proofing. If declined, open a follow-up issue and stop after Task 12 — the PR still `Closes #63` for the three named pillars + motion/transparency/contrast.

### Task 13: Scalable type system

**Files:**
- Create: `Sources/Hubber/Design/HubberFont.swift`
- Test: `Tests/HubberTests/HubberFontTests.swift`
- Modify: `.font(HubberType.xxx)` call sites (sweep via `grep -rn "HubberType\." Sources`)

**Interfaces:**
- Produces: `HubberFont.scaledSize(base:factor:) -> CGFloat`; a `View.hubberFont(_ role: HubberFont.Role)` modifier.

- [ ] **Step 1: Write the failing test**

```swift
import SwiftUI
import Testing
@testable import Hubber

@Suite("HubberFont scaling")
struct HubberFontTests {
    @Test("scaled size grows with factor and honors base")
    func scaling() {
        #expect(HubberFont.scaledSize(base: 13, factor: 1.0) == 13)
        #expect(HubberFont.scaledSize(base: 13, factor: 1.5) == 19.5)
        #expect(HubberFont.scaledSize(base: 11, factor: 2.0) > HubberFont.scaledSize(base: 11, factor: 1.0))
    }

    @Test("role base sizes match HubberType.PointSize")
    func roleBases() {
        #expect(HubberFont.Role.title.base == HubberType.PointSize.title)
        #expect(HubberFont.Role.secondary.base == HubberType.PointSize.secondary)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter HubberFontTests`
Expected: FAIL — `cannot find 'HubberFont'`.

- [ ] **Step 3: Implement**

```swift
import SwiftUI

/// Scalable replacement for HubberType's fixed-size fonts. Sizes scale with the
/// environment's Dynamic Type via @ScaledMetric. macOS exposes no system Dynamic Type
/// slider today, so this is primarily future-proofing + Bold Text support.
enum HubberFont {
    enum Role {
        case title, secondary, sloPill, ciDetail, log, section, footer, prNumber, headerTitle, settingsLabel, settingsSub, badge

        var base: CGFloat {
            switch self {
            case .title: 13
            case .headerTitle: 15
            case .settingsLabel: 12.5
            case .badge: 10
            default: 11
            }
        }

        var weight: Font.Weight {
            switch self {
            case .title: .medium
            case .section, .headerTitle, .badge: .semibold
            default: .regular
            }
        }

        var textStyle: Font.TextStyle {
            switch self {
            case .headerTitle: .headline
            case .title, .settingsLabel: .body
            default: .caption
            }
        }
    }

    static func scaledSize(base: CGFloat, factor: CGFloat) -> CGFloat { base * factor }
}

private struct HubberFontModifier: ViewModifier {
    let role: HubberFont.Role
    @ScaledMetric private var scaled: CGFloat

    init(role: HubberFont.Role) {
        self.role = role
        _scaled = ScaledMetric(wrappedValue: role.base, relativeTo: role.textStyle)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaled, weight: role.weight))
    }
}

extension View {
    func hubberFont(_ role: HubberFont.Role) -> some View {
        modifier(HubberFontModifier(role: role))
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter HubberFontTests`
Expected: PASS.

- [ ] **Step 5: Migrate call sites incrementally.** Replace `.font(HubberType.title)` → `.hubberFont(.title)` etc., one file at a time, building after each. Preserve monospaced-digit roles (`sloPill`, `badge`, `prNumber`, `log`) by adding `.monospacedDigit()`/`.monospaced()` after `.hubberFont(...)` where the original used them. Leave `HubberType` in place (still referenced by `PointSize` tests) until the sweep is complete.

- [ ] **Step 6: Verify no layout breakage.** Build, run, and visually confirm the fixed-width popover reflows without clipping at the largest accessibility size (and with Bold Text). Note results in the runbook.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(a11y): scalable Dynamic Type font system"
```

---

## Finalize

- [ ] **Run the full gate:** `make ci` — expect build + all tests + lint + swiftformat clean.
- [ ] **Open the PR** with `Closes #63`, a summary of each workstream, the contrast before/after table (from Task 3 Step 6), a link to the runbook, and an explicit note of what was verified automatically vs. needs the owner's manual VoiceOver pass.

---

## Self-Review (completed by plan author)

- **Spec coverage:** A (VoiceOver)→Tasks 1,2,5,6,7,8; B (keyboard)→Task 9; C (contrast)→Task 3; D (Reduce Motion)→Tasks 4,10; E (Transparency/Contrast/Color)→Task 11; F (Dynamic Type)→Task 13; testing deliverables→Tasks 1–4,13 + runbook Task 12. All covered.
- **Placeholder scan:** foundational tasks (1–4,13) contain complete code; wiring tasks give exact files, exact modifier snippets, and the named functions they call (all defined in Tasks 1–4). No "TBD/handle edge cases".
- **Type consistency:** function names used in wiring (`incomingRow`, `outgoingRow`, `draftRow`, `tabValue`, `ciPhrase`, `reviewerPhrase`, `sloPhrase`, `reviewersSummary`, `AccessibilityGates.animation/pulseEnabled`, `HubberFont.Role.base/scaledSize`) match their definitions verbatim.
</content>
</invoke>
