# Runbook: Manual accessibility acceptance test

The accessibility audit (#63) added VoiceOver labels, keyboard focus, contrast,
Reduce Motion / Reduce Transparency / Increase Contrast / Differentiate Without Color,
and a scalable type system. The unit-testable parts (label text, contrast ratios, motion
gates, font scaling) are covered by `swift test`. **This runbook covers what only a human
with the app running can confirm:** VoiceOver speech, keyboard focus order + ring, and the
visual effect of each display preference.

Run this on **macOS 14+** before tagging a release. It is the owner's acceptance pass for
the issue's requirement: *"Test with VoiceOver enabled end-to-end."*

Build/run the app: `make app` (or `Scripts/make-app.sh`), then launch `Hubber.app`.

---

## A. VoiceOver end-to-end (⌘F5 toggles VoiceOver)

Walk the exact path from issue #63: **sign in → open popover → navigate all three tabs →
open a PR → walk Settings.**

### A1. Onboarding / sign-in
- [ ] Each step's heading is announced **as a heading** (VO rotor → Headings lists them).
- [ ] On each step, focus lands on the primary button when the step appears; **Return**
      activates it. (Welcome "Get started", Consent "Enable analytics", etc.)
- [ ] Step dots are announced once as **"Step N of M"** (not 5 separate capsules).
- [ ] **Managed path:** with a setting MDM-locked (Consent or Launch-at-Login showing the
      managed notice), focus is NOT silently lost — the visible control is reachable.
- [ ] Device-code screen: the **Copy** button announces "Copy code".
- [ ] The "Add GitHub Enterprise / GitLab" control announces its hint.

### A2. Popover + tabs
- [ ] **P0 — initial focus:** opening the popover places keyboard focus on the tab bar /
      first row (not nowhere). *If focus lands nowhere on first open, see Fix F-1 below.*
- [ ] **P0 — tab bar is reachable & rings:** Tab/VO-navigate reaches the Reviews/Outgoing/
      Drafts tabs; each shows a focus ring. *If the tab bar is not focusable, see Fix F-2.*
- [ ] Each tab announces its **title + value** ("Outgoing, 3 items") and the active tab
      reads as **selected**.
- [ ] Switch to each of the three tabs.

### A3. Rows (the critical check)
- [ ] **P0 — one focus stop per row:** VO navigation stops **once** per PR row and speaks a
      single coherent phrase — NOT a stream of separate fragments and NOT the same content
      twice. Expected shapes:
  - Incoming: *"Pull request 1234, Fix login crash, in acme/app, by alice, review overdue, 2h overdue"*
  - Outgoing: *"Pull request 42, Add cache, in acme/app, checks failing, 1 unresolved thread, 1 reviewer: 1 changes requested"*
  - Draft: *"Draft pull request 9, Spike, in acme/app, checks running, 6 commits"*
- [ ] Each row announces the **button** trait and the hint **"Opens the pull request"**.
- [ ] **P0 — tap still works:** VO-activate a row (VO+Space) → the PR URL opens. Confirm the
      grouped accessibility element did not swallow the tap. *If a row double-speaks OR the
      tap no longer fires, see Fix F-3 below.*
- [ ] Avatars/reviewer dots are not announced as separate noise inside a row (the row label
      subsumes them).

### A4. Settings (⌘,)
- [ ] Every toggle announces **"<name>, on/off"** (e.g. "Enable notifications, on") — not an
      empty/unlabeled switch. Check: notifications master + per-type, Share analytics,
      Diagnostic logging, Open at login.
- [ ] The SLO-hours **slider** announces "Review SLO" and a value like "8 hours", and the
      value updates as you adjust it.
- [ ] Each segmented picker announces a **group name** (Show SLO as / Incoming requests /
      Unresolved threads / Row density / badge pickers) and its selected segment.
- [ ] Account rows announce the account and any status ("Needs attention") as one element.

---

## B. Keyboard-only navigation (VoiceOver off)

- [ ] **Focus order matches visual order** through onboarding → popover → tabs → Settings;
      no surprising jumps.
- [ ] A **visible focus ring** appears on the focused control at every stop.
- [ ] Every control operable by mouse is operable by keyboard: switch tabs, activate a row,
      toggle switches, move the slider, change segmented pickers.
- [ ] Existing shortcuts still work: **⌘,** (Settings), **⌘R** (Refresh).
- [ ] No keyboard trap (you can always Tab back out).

---

## C. Display-preference checklist

Toggle each in **System Settings → Accessibility → Display** (and Motion), then observe.
**With every preference OFF, the app must look/behave exactly as before** (regression check).

- [ ] **Reduce Motion ON:** onboarding step transitions are instant (no slide), the sign-in
      success screen shows its **final state immediately** (checkmark + label visible, no
      spring), and the menu-bar icon does **not** pulse while refreshing (it shows a static
      icon). Toggle it back OFF mid-run → pulsing resumes (live observer).
- [ ] **Reduce Transparency ON:** the popover background renders as a **solid** surface
      (no vibrancy/blur). OFF → translucent material returns.
- [ ] **Increase Contrast ON:** header/footer separators read as **stronger** lines. OFF →
      faint separators return.
- [ ] **Differentiate Without Color ON:** the account "needs attention" / "session expired"
      states show a **symbol/glyph** (⚠ / exclamation), not color alone.
- [ ] **Larger text / Bold Text (Dynamic Type):** if the Dynamic Type phase shipped, confirm
      text scales and the fixed-width popover reflows without clipping/truncation; Bold Text
      thickens labels. (See the Dynamic Type note in the design spec for macOS limitations.)

---

## Fallback fixes (only if a P0 check fails)

These are pre-diagnosed remedies for the runtime-only risks flagged during implementation.

- **F-1 — popover initial focus lands nowhere on first open.** The `.onAppear` focus set in
  `HubberPopoverView` can be dropped if the `NSPopover` window isn't key yet. Wrap the set:
  `Task { @MainActor in tabBarFocused = true }`.
- **F-2 — tab bar not keyboard-focusable / no ring.** `HubberTabBar` may not expose a
  focusable root for `.focused(...)`. Target a child control (the first tab `Button`) or add
  `.focusable()` to the tab bar.
- **F-3 — a PR row double-speaks or its tap no longer opens the PR.** The row groups itself
  with `.accessibilityElement(children: .ignore)` inside `ClickableRow`'s `Button`. If the
  nesting misbehaves on this macOS version, move the
  `.accessibilityElement(children: .ignore)` + `.accessibilityLabel(...)` from the row's
  `RowShell` up to `ClickableRow`'s outer `Button` (after `.accessibilityHint`), so the
  button itself is the single accessibility element.

Record the date, macOS version, and any failures (with the fix applied) below each run.
