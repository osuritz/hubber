# Accessibility Audit & Remediation — Design

**Issue:** #63 · **Date:** 2026-06-20 · **Scope:** Comprehensive WCAG 2.1 AA + macOS
accessibility across onboarding (M7), the popover, Settings, and the menu-bar item.
**Delivery:** one PR, `Closes #63`, organized as independently-revertable phase commits.

## 1. Goal

Make Hubber usable with VoiceOver, fully operable from the keyboard, legible at AA
contrast, and respectful of the system accessibility preferences (Reduce Motion, Reduce
Transparency, Increase Contrast / Differentiate Without Color, Bold Text, Dynamic Type).
Do this **without changing the visual design**, except for minimal contrast-token tweaks
that are individually flagged for design sign-off.

Non-goal: changing app behavior or layout beyond what accessibility requires.

## 2. Current state (from the audit)

**Foundation already present**
- Status signals carry non-color cues today: SLO pill = colored dot + text; CI badge =
  SF Symbol per state (checkmark / xmark / clock / minus / spinner); reviewer dots =
  filled vs. hollow shape. So *sighted* color-blind users are largely covered.
- Menu-bar item: icon has `accessibilityDescription = "Hubber"`; badge count is exposed
  via `button.setAccessibilityValue(...)`; tooltip text is set.
- Colors are centralized in `HubberDesign.swift`; type roles in `HubberType.swift` (with
  a `PointSize` enum already consumed by tests — a clean seam for scaling).
- `NativeSegmentedControl` wraps `NSSegmentedControl`, which is natively accessible
  (announces segments + selection); it only lacks a group label.
- Two keyboard shortcuts exist: ⌘, (Settings), ⌘R (Refresh).

**Gaps**
- Almost no `.accessibilityLabel/Value/Hint` on interactive elements. PR rows are
  clickable buttons that announce only the tooltip "Open pull request" — not PR number,
  title, author, CI/SLO/reviewer state.
- SwiftUI toggles use `Toggle("", ...).labelsHidden()` → **no accessible name** (the
  visible label lives in a sibling `Text`, invisible to VoiceOver).
- Avatars and reviewer state dots have no text equivalent (state is shape+color only —
  fine visually, silent to VoiceOver).
- Segmented pickers lack a group label ("what does this control?").
- No keyboard focus management: no `@FocusState`, no default focus on open, focus order
  is implicit source order, focus ring not verified.
- Animations ignore `accessibilityReduceMotion` (onboarding step transitions, sign-in
  success animation, menu-bar refresh pulse timer).
- No response to Reduce Transparency, Increase Contrast, Bold Text, or Dynamic Type.
- The account-status "⚠ Needs attention" line is the one signal whose differentiation
  leans on color (amber). It does carry a "⚠" glyph today, but should get an explicit
  non-color cue + label under Differentiate Without Color.
- Contrast of the token set is plausible but never formally verified.

## 3. Approach & principles

1. **Extract semantics into pure, testable functions.** The *content* VoiceOver speaks
   is logic, not presentation. A new `Accessibility/AccessibilityLabels.swift` holds pure
   functions that turn a model into a label string. Views call them; tests assert them.
2. **Verify contrast with code, not eyeballs.** A WCAG relative-luminance utility plus a
   test that walks every token/background pair turns contrast into a hard CI gate.
3. **Centralize preference gating.** Small helpers/environment reads for Reduce Motion,
   Reduce Transparency, Differentiate Without Color, so each view opts in uniformly
   instead of ad-hoc checks.
4. **Preserve the existing design-token architecture.** Contrast fixes edit token values
   in `HubberDesign.swift` only; Dynamic Type extends `HubberType` rather than replacing
   it. No call-site churn beyond what's required.
5. **Each workstream is one revertable commit.** The PR can land incrementally and phase
   F (Dynamic Type) can be dropped to a follow-up without unpicking A–E.

## 4. Workstreams

### A. VoiceOver semantics
- **PR rows** (`HubberRows.swift`): wrap each row as one accessibility element with a
  composed label (number, title, repo, author; plus the row's signal — SLO state for
  incoming, CI + reviewer summary for outgoing/drafts) and the `.isButton` trait + hint
  "Opens the pull request". Mark inner decorative pieces (`RowDot`, separators)
  `.accessibilityHidden(true)`.
- **SLO pill / CI badge / reviewer dots / avatars**: give each a text equivalent via the
  pure label functions (e.g. CI `.failing` → "checks failing"; reviewer `.approved` →
  "approved"; avatar → "<login>, <role>"). When subsumed into a row's combined label,
  hide the child to avoid double-speak.
- **Tabs** (`HubberTabBar`): label = tab title, value = count ("3 items"), `.isButton`
  + selected trait on the active tab.
- **Toggles** (Settings, Notifications, Privacy, onboarding): replace
  `Toggle("").labelsHidden()` with a real accessible name (use `Toggle(text, isOn:)` with
  `.labelsHidden()` for layout, or `.accessibilityLabel(text)`), so state reads as
  "<name>, on/off".
- **Sliders** (SLO hours): `.accessibilityValue("<n> hours")` + label.
- **Segmented pickers**: `.accessibilityLabel("<group name>")` on the wrapper (e.g. "Row
  density"); native control already speaks segment + selection.
- **Menu-bar item**: add an `accessibilityLabel` ("Hubber") distinct from the value, and
  a hint ("Opens Hubber").
- **Onboarding**: label each step's heading as a header; ensure primary/secondary buttons
  read their text and traits; device-code copy button gets a label.

### B. Keyboard navigation & focus
- `@FocusState` to set a sensible default focus when the popover opens and when each
  onboarding step appears (primary action).
- Verify Tab/Shift-Tab order matches visual order across popover, tabs, Settings; add
  `.focusable()`/order fixes only where SwiftUI's default is wrong.
- Confirm a visible focus indicator (`.focusEffect` / default ring) on custom controls.
- Ensure every action reachable by pointer is reachable by keyboard (tab switching, row
  activation, settings controls).

### C. Contrast
- Add `ContrastRatio` (WCAG relative luminance + ratio) to the **test target**.
- Resolve each `HubberDesign` token in light and dark against its real rendered
  background (e.g. SLO `fg` over SLO `bg` over window material; `text3` over base) and
  assert ≥4.5:1 for text, ≥3:1 for large text / UI components.
- For any failure, compute the smallest value change that reaches AA, apply it to the
  token, and record before/after ratio in the PR body for sign-off. Translucent tokens
  are composited over their base before measuring.

### D. Reduce Motion
- A single read of `@Environment(\.accessibilityReduceMotion)` (or an
  `AppKit`-side `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` for the
  menu-bar pulse timer) gates: onboarding step transition animation, sign-in success
  animation, and the refresh pulse. When reduced: no animation / instant state change,
  functionality unchanged.

### E. Reduce Transparency + Increase Contrast / Differentiate Without Color
- **Reduce Transparency**: when set, render vibrancy/`VisualEffectView` surfaces as solid
  equivalents (`materialSolid`-style) instead of translucent.
- **Differentiate Without Color**: ensure the account "needs attention" state and any
  other color-leaning signal also presents a shape/symbol + the text label is announced.
- **Increase Contrast**: where the system requests it, prefer the higher-contrast token
  variants (e.g. stronger separators/borders). Keep changes minimal and reversible.

### F. Dynamic Type (built last; revertable)
- Extend `HubberType` so its sizes scale with the environment via `@ScaledMetric`
  (anchored to the matching `Font.TextStyle`), and honor Bold Text via `legibilityWeight`.
- Verify the fixed-width popover reflows without truncation/clipping at larger sizes;
  adjust `lineLimit`/layout only where it breaks.
- **macOS reality (on record):** macOS exposes no system-wide Dynamic Type slider like
  iOS, so present-day user-visible payoff is Bold Text + future-proofing. This phase is
  the most invasive (touches every font + the compact layout); if it proves too
  disruptive it ships as a follow-up issue without blocking A–E.

## 5. Testing strategy

**Automated (added to the Swift test target, gated by `make ci`):**
- `AccessibilityLabelsTests` — every pure label function asserted against model fixtures
  (incoming/outgoing/draft rows, each CI state, each reviewer state, SLO states, tabs).
- `ContrastTests` — every token/background pair meets AA in light and dark (hard gate).
- `MotionGateTests` / `TransparencyGateTests` — the gating helpers return the right
  presentation for each preference value.
- `DynamicTypeScalingTests` — scaled sizes increase monotonically with type size and
  honor Bold Text.

**Manual (cannot be automated — committed as a runbook):**
- `docs/runbooks/accessibility-test.md`: a step-by-step VoiceOver + keyboard-only script
  covering the issue's end-to-end path (sign in → open popover → navigate all three tabs
  → open a PR → walk Settings), plus a Reduce Motion / Reduce Transparency / Increase
  Contrast / larger-text visual checklist. This is the owner's repeatable acceptance &
  regression pass.

## 6. Out of scope (follow-ups)

- VoiceOver rotor customization.
- A UI-automation (XCUITest-style) harness — `.accessibilityIdentifier`s may be added
  opportunistically to enable it later, but building the harness is separate.
- Anything outside onboarding / popover / Settings / menu-bar.

## 7. Risks

- **Scope size.** Comprehensive AA across four areas is large for one PR; mitigated by
  per-workstream commits and the option to defer phase F.
- **Combined-label double-speak.** Grouping rows must hide child elements or VoiceOver
  repeats itself; covered by the manual VO script.
- **Contrast tweaks vs. brand.** Token edits change brand colors; mitigated by minimal
  deltas + explicit per-change sign-off in the PR.
- **Dynamic Type layout breakage** in the fixed-width popover; mitigated by building it
  last, behind tests, and the option to split it out.
