# Hubber — Product Requirements Document

**Date:** 2026-06-15
**Status:** Approved

---

## Vision

Hubber is a native macOS menubar app that keeps engineers on top of their PR review obligations and authored PR health — without switching context to a browser. It feels like it shipped with macOS: vibrancy, SF Pro, system dark/light mode, Keychain auth. It is free, works for solo engineers and enterprise teams alike, and is extensible to any code host.

---

## Non-Goals

- No web app, no mobile app, no Electron
- No code diff viewing — Hubber opens PRs in the browser, it does not replace it
- No project management (issues, milestones, boards)
- No GitLab provider UI (yet) — code architecture readiness only

---

## User

Engineers at SMB and large tech companies using GitHub (and eventually GitLab) to manage PR review workflows. Two personas:

- **Individual contributor** — wants ambient awareness of their review queue and authored PR health without checking GitHub constantly
- **Enterprise team** — IT needs to pre-configure and lock settings fleet-wide via MDM; team leads want SLO enforcement and notification defaults

---

## Design Direction

Direction A: native macOS. Apple-faithful vibrancy (`.popover` material), SF Pro, segmented control tabs, traffic-light SLO badges, compact/normal/spacious row density. Light and dark mode both supported and maintained. Width: 420pt popover.

Three tabs: **Reviews** (incoming requests), **Outgoing** (authored PRs), **Drafts**.

---

## Architecture Principles

### 1. Provider Abstraction

All data access goes through a `CodeHostProvider` protocol. `GitHubProvider` is the first implementation. Adding GitLab later means a new conformance — zero changes to UI or business logic.

```
CodeHostProvider (protocol)
  └── GitHubProvider
  └── GitLabProvider  ← future, backlog
```

### 2. SettingsStore

Single source of truth for all user and managed settings. Reads in strict priority order:

1. MDM managed preferences (`com.hubber.app` domain via `CFPreferences`)
2. `UserDefaults`
3. Hardcoded default

IT can lock any key at the managed-preferences layer. Enforced from M1 so enterprise provisioning (M5) is a configuration exercise, not a refactor.

### 3. SLO Resolution Function

```swift
func sloHours(for repo: String) -> Double
```

Today returns the global `SettingsStore` value. Per-repo overrides (backlog) slot in here without touching any call sites.

### 4. RefreshScheduler (M2)

Owns all polling cadence. Adaptive logic:

| State | Interval |
|---|---|
| Machine idle, all green | 15 min |
| Background, normal | 5 min |
| Popover open | 1 min |
| Any PR within 20% of SLO budget | 30 s |

Manual refresh (⌘R) always available regardless of cadence.

---

## Tab Specifications

### Reviews (Incoming)

**Data source:** GitHub Search API

- Default query: `is:pr is:open review-requested:@me`
- Option B (settings toggle): adds `team-review-requested:@me`
- Option C (backlog): PRs authored by org/team members — requires team member list fetched separately with high-TTL cache

**Sort:** oldest assignment first (most urgent at top, matches SLO urgency)

**Row content (normal density):**
- Author avatar (initials + color)
- PR number + title (truncated)
- Repo · author login
- SLO pill (configurable: remaining / elapsed / traffic-light only)

**SLO pill states:**
- Green: < 50% of budget consumed
- Amber: 50–100% of budget consumed
- Red: ≥ 100% (past SLO)

**Empty state:** "All clear" — green checkmark icon, "No reviews waiting on you. Enjoy the deep work."

**Error state:** inline message with last-refresh timestamp; retry button.

### Outgoing

**Data source:** GitHub Search API — `is:pr is:open author:@me -is:draft`

**Sort:** most recently updated first (mirrors GitHub default)

**Row content (normal density):**
- CI badge (passing / failing / running / pending)
- PR number + title
- Repo · CI detail string · unresolved comment count (if > 0)
- Reviewer avatar stack (up to 3, with state dot: approved=green, changes-requested=red, commented=blue)

**Action signals (the two things that need your attention):**
1. CI failing or running
2. Unresolved review threads — review comments from reviewers that the PR author has not yet marked resolved

### Drafts

**Data source:** GitHub Search API — `is:pr is:open is:draft author:@me` (already live)

**Sort:** most recently updated first

**Row content (normal density):**
- Dashed-border doc icon
- PR number + title
- Repo · commit count · elapsed time
- CI badge + status text

---

## Menubar Icon & Badge

**Badge value:** configurable via `SettingsStore`, default = **attention-needed count**

- Attention-needed = incoming review count + outgoing PRs with failing CI + outgoing PRs with unresolved comments

**Badge options (settings picker):**
- Incoming count only
- Attention-needed count (default)
- Off

**Icon states:**
- Normal: Octocat/hub icon, no badge
- Has attention: badge with count
- Refreshing: subtle animation indicator

---

## Notifications (M3)

Background alerting via macOS `UNUserNotificationCenter`.

**Permission:** requested at first meaningful trigger, not at launch.

**Per-event opt-in (all off by default except "new review requested"):**

| Event | Default |
|---|---|
| New review requested | On |
| Review approved on your PR | Off |
| Changes requested on your PR | Off |
| CI failed on your PR | Off |
| PR merged | Off |

**VIP filter (backlog):** for "new review requested", optionally restrict to notifications only when the PR author is in a user-defined VIP list.

**Tap action:** opens the PR URL in the default browser.

---

## Settings

### GitHub Account
- Signed-in user display + sign out

### Incoming Reviews
- Review SLO toggle (on/off)
- Review window slider (1–24h, default 4h)
- Show SLO as: Remaining / Elapsed / Light only (segmented control)
- Incoming mode: Explicit requests only / Include team requests (segmented control)

### Appearance
- Row density: Compact / Default / Spacious

### Badge
- Badge shows: Incoming count / Attention-needed / Off

### Notifications (M3)
- Per-event toggles

### Developer (debug builds only)
- Log viewer, copy/clear, token storage path

---

## Enterprise / MDM (M5)

**Managed preferences domain:** `com.hubber.app`

**Lockable keys:**

| Key | Type | Description |
|---|---|---|
| `sloWindowHours` | Integer | Default SLO window |
| `sloEnabled` | Boolean | Whether SLO feature is on |
| `badgeMode` | String | `incoming` / `attention` / `off` |
| `incomingMode` | String | `explicit` / `team` |
| `providerAllowlist` | Array\<String\> | Allowed host URLs (e.g. `github.myco.com`) |
| `allowPersonalGitHub` | Boolean | Whether `github.com` personal accounts can connect |

When a key is present in the managed domain, `SettingsStore` uses that value and the corresponding settings control is rendered as disabled (visible but non-interactive).

Provider allowlist is enforced at auth time — disallowed hosts are never presented in the connection UI.

---

## Distribution

Three channels, one build pipeline:

| Channel | Format | Notes |
|---|---|---|
| GitHub Releases | Notarized DMG, universal binary | Sparkle auto-update |
| Homebrew | Cask formula | `brew install --cask hubber` |
| Mac App Store | Sandboxed build | App Store updates |

Sandbox compliance is a constraint from day one — no capabilities that would block MAS submission.

---

## Milestones & GitHub Issues

### Milestone 1 — Live Data

**Architecture**
- Introduce `CodeHostProvider` protocol and provider abstraction layer
- Implement `SettingsStore` with MDM → UserDefaults → hardcoded default priority chain
- Add `sloHours(for repo:) -> Double` resolution function

**GitHub Service**
- Fetch incoming reviews via GitHub Search API (`review-requested:@me`)
- Add option B: include `team-review-requested:@me` (settings toggle)
- Fetch outgoing PRs: CI status, unresolved comment count, reviewer states, mergeable flag
- Migrate Drafts tab to `CodeHostProvider` abstraction
- Response caching layer with per-resource TTL

**UI**
- Wire Incoming tab to live GitHub data
- Wire Outgoing tab to live GitHub data
- Error and offline empty states for all three tabs
- "All clear" empty state for Incoming
- Settings toggle: incoming review mode

### Milestone 2 — Polish & Adaptive Refresh

- Implement `RefreshScheduler` with adaptive cadence
- Smart menubar badge with attention-needed default
- Badge mode picker in settings
- ⌘R keyboard shortcut wired to manual refresh
- Menubar icon states: normal, has-attention, refreshing
- Provider switcher stub in header (hidden, single-provider — multi-account seam)

### Milestone 3 — Notifications

- Implement `NotificationScheduler`: diff between refresh cycles, emit on state change
- Request macOS notification permission at first meaningful trigger
- Per-event-type opt-in settings UI
- Notification: new review requested
- Notification: review approved
- Notification: changes requested
- Notification: CI failed
- Notification: PR merged
- Notification tap → open PR in browser

### Milestone 4 — Distribution

- GitHub Actions pipeline: build, sign, notarize, publish release
- Universal binary (arm64 + x86_64)
- GitHub Releases DMG artifact
- Sandbox entitlement audit for Mac App Store compliance
- Mac App Store submission
- Homebrew cask formula
- Sparkle auto-update integration

### Milestone 5 — Enterprise / MDM

- Document `com.hubber.app` managed preferences domain and all lockable keys
- Managed preference enforcement in `SettingsStore` for all lockable keys
- Provider allowlist: disallowed hosts hidden from auth UI, enforced at connection time
- IT deployment guide with sample Jamf / Kandji / Mosyle configuration profiles
- MDM-compatible pkg installer

### Backlog

- Team activity feed — option C for Incoming (org/team member PRs, cached)
- VIP author filter for notifications
- Per-repo SLO override rules UI
- GitLab provider implementation
- Multi-account UI — provider switcher visible when >1 account connected

---

## Open Questions

_None at time of writing. All key product decisions resolved in design session 2026-06-15._
