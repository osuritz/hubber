# Claude Design Prompt — Hubber Visual Assets

**Date:** 2026-06-16
**Purpose:** Prompt to give Claude Design to produce the full visual design system and screen mocks for Hubber. Paste this verbatim into a Claude Design session.

---

**Context:** You are designing assets for **Hubber**, a native macOS menubar app (420pt wide popover, `.popover` vibrancy material) that keeps engineers on top of their GitHub PR review obligations — without switching to the browser. Design direction **A** has been chosen: Apple-faithful, SF Pro, system dark/light mode, traffic-light SLO badges, segmented control tabs, compact/normal/spacious row density. The app currently has working SwiftUI code; you are producing the visual design system and screen mocks that the engineers will implement.

---

## App Structure

**Menubar icon** — `arrow.triangle.pull` SF Symbol today; may become a custom hub icon. Shows a numeric badge (attention-needed count by default). Three states: normal, has-attention (badge), refreshing (subtle animation).

**Popover** — 420 × 540pt, `.popover` vibrancy material (translucent, adapts to light/dark automatically). Rounded corners (26pt radius). No title bar. Three tabs at the top via a segmented control: **Reviews**, **Outgoing**, **Drafts**. Below the tab bar: a scrollable list of PR rows. At the bottom: a slim footer with the last-refresh timestamp and a manual refresh button (⌘R).

---

## Screens to design

### 1. Reviews tab (Incoming)

Show a list of incoming review requests, sorted oldest-first (most urgent at top). Each row at **normal density** contains:
- Left: author avatar (36pt circle; GitHub profile image preferred; fallback = initials on a deterministic pastel background color)
- PR number (`#1234`) + title (truncated, one line)
- Repo · author login (secondary, smaller)
- Right: SLO pill — three states: **green** (<50% budget consumed), **amber** (50–100%), **red** (≥100%, overdue). Pill shows time remaining/elapsed as text (e.g. "2h 14m left", "1h overdue") — this is configurable but design the default (remaining).

Provide three row density variants side-by-side: **compact** (tighter padding, no secondary line), **normal** (default above), **spacious** (avatar larger, secondary line, more breathing room).

**Empty state ("All clear"):** green checkmark icon, "No reviews waiting on you. Enjoy the deep work." — centered in the list area.

**Error state:** inline message with "Couldn't load reviews · Last updated 3m ago" + a "Retry" link.

**Loading state:** skeleton rows (shimmer or placeholder) while the first fetch is in flight.

---

### 2. Outgoing tab

Authored PRs that need the author's attention. Each row at normal density:
- Left: CI badge — four states: **passing** (green checkmark), **failing** (red ✕), **running** (spinning/animated), **pending** (grey clock). The badge is the primary signal — it is large and prominent.
- PR number + title
- Repo · CI detail string (e.g. "3/11 checks passing") · unresolved thread count if >0 (e.g. "2 threads")
- Right: reviewer avatar stack (up to 3, 20pt circles, overlapping). Each avatar has a state dot: **approved** = green filled circle, **changes requested** = red filled circle, **commented** = blue filled circle, **pending** = grey ring.

Action signal rows (CI failing or unresolved threads) should be visually distinct — a subtle left-edge accent or tinted background to draw the eye. CI **running** is not an action signal and should look neutral.

---

### 3. Drafts tab

In-progress work, not yet ready for review. Each row at normal density:
- Left: dashed-border document icon (signals "not ready")
- PR number + title
- Repo · commit count · elapsed time since last update (e.g. "6 commits · updated 2h ago")
- CI badge + status text (same four states as Outgoing, but smaller — this is informational, not an action signal)

---

### 4. Settings screen

The popover switches to a full-height settings scroll view when the user taps a gear icon in the header. Sections (use native-feeling section dividers and labels):

**GitHub Account**
- Signed-in user: avatar + `@login` + "Sign out" button
- Re-auth state: "Session expired — Sign in again" inline prompt with a button

**Incoming Reviews**
- Review SLO toggle (on/off switch)
- Review window slider: 1–24h, current value shown as "4 hours" label (disabled when SLO is off)
- Show SLO as: segmented control — Remaining / Elapsed / Light only (disabled when SLO is off)
- Incoming mode: segmented control — Explicit requests / Include team requests

**Outgoing**
- Unresolved threads: segmented control — All threads / Review threads / Changes requested

**Appearance**
- Row density: segmented control — Compact / Default / Spacious (show a tiny preview row thumbnail for each option if space allows — otherwise just labels)

**Badge**
- Badge shows: segmented control — Incoming count / Attention-needed / Off

**Privacy**
- Send anonymous usage analytics: toggle (default on)
- Crash reporting: toggle (default on)
- "What we collect" disclosure link (expands inline or opens in browser)

**Developer** *(debug builds only — show with a subtle "debug" chip label on the section header)*
- A compact log viewer: monospaced 11pt text, rows of `HH:mm:ss · message`. Last 12 entries visible; older entries scroll.
- Two action buttons: **Copy** (copies all log entries as plain text, e.g. for pasting into a bug report or AI chat) and **Clear**
- The log already exists in code: `store.developerLog: [DeveloperLogEntry]` — each entry has a `timestamp: Date` and `message: String`. Copy formats entries as `[HH:mm:ss] message`, one per line.
- Empty state: "No logs yet" in secondary text
- This section is the sharing mechanism for debugging sessions — engineers paste it into Slack or an AI chat to share what the app has been doing

---

## Visual design system to produce

1. **Color tokens** — semantic colors for: SLO green/amber/red, CI passing/failing/running/pending, reviewer state dots (approved/changes/commented/pending), error red, action signal tint, and any surface/fill colors for rows. All tokens must have light and dark mode values. Map to SwiftUI `Color` assets.

2. **Typography scale** — SF Pro sizes used in the app: PR title (13pt medium), secondary line (11pt regular), SLO pill (11pt medium monospacedDigit), CI detail (11pt regular), log viewer (11pt monospaced), section header (11pt medium uppercase), footer (11pt regular). No custom typefaces — SF Pro only.

3. **SLO pill component** — three color states (green/amber/red), contains a colored dot + text label. Corner radius consistent with macOS controls (~6pt). Show all three states.

4. **CI badge component** — four states. The passing/failing states are the primary action signals. Show all four.

5. **Avatar component** — 36pt (normal), 24pt (reviewer stack), 20pt (reviewer stack compact). Circular clip. Fallback: initials (1–2 chars) on deterministic pastel background. State dot overlay for reviewer state (8pt circle, 1.5pt white border, positioned bottom-right).

6. **Row components** — full normal-density row for each of the three tab types, showing all sub-states (green SLO, amber SLO, red SLO for Incoming; CI passing/failing/running for Outgoing; stale draft vs. recently updated for Drafts).

7. **Full popover mocks** — light and dark mode for each of the four screens (Reviews, Outgoing, Drafts, Settings). Show the popover floating above a blurred macOS desktop to communicate the real context.

8. **Menubar icon states** — all three badge states at 2× on a simulated menubar (both light and dark menubar).

---

## Constraints and decisions already made

- **Width:** 420pt. Height: 540pt (fixed panel, content scrolls inside).
- **No custom fonts.** SF Pro / SF Mono only.
- **Vibrancy material:** `.popover` — the background is translucent and shifts with the desktop. Do not design a flat opaque background for the popover itself; the content sits on the vibrancy layer.
- **All color signals must have a non-color cue** (shape, text label, or icon) so they work for colorblind users. E.g. the SLO pill always has a dot + text, not just color.
- **Segmented controls** for all multi-option settings — native macOS `NSSegmentedControl` style, not toggles or radio buttons.
- **No custom icons** unless absolutely necessary — use SF Symbols throughout. Dashed document icon for Drafts: try `doc.badge.clock` or `doc.text.below.ecg` — pick whichever reads best at 20pt.
- The popover is **not resizable** and is **not a window** — there is no title bar, traffic lights, or resize handle.
