# Hubber — Product Requirements Document

**Date:** 2026-06-15
**Status:** In Review

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

## Success Metrics

### Primary (A + C)

**Engagement:**
- Daily and weekly active users
- Sessions per day per user
- Tab switch distribution per session (which tab is most-viewed)
- Click-through rate per tab (items opened in browser / items shown)
- Manual refresh frequency (high frequency = user doesn't trust auto-refresh)

**Retention and feature adoption:**
- 7-day and 30-day retention
- % of users who configure SLO (change from default 4h)
- % of users who enable at least one notification type
- % of users who change row density
- Notification → click-through time distribution

### Outcome Proxies (B-adjacent)

All values reported as distributions (avg / median / P90 / P95 / P99):

- Item count per tab at session open (incoming, outgoing, drafts)
- SLO status distribution at session open (% green / amber / red in Reviews tab)
- % of sessions where Reviews tab opens to "All clear"
- Time-in-queue for incoming items: bucketed as <1h / 1–4h / 4–24h / 24h+
- Average age of outgoing PRs (proxy for PR cycle time)
- Average age of drafts (stale draft signal)
- % of outgoing PRs with failing CI at session open
- % of outgoing PRs with unresolved comments at session open

**What is never tracked:** repo names, PR titles, usernames, org names, branch names. Only counts, ages, and distributions.

### Analytics Stack

- **Product events:** TelemetryDeck (privacy-first, hashed identifiers, no PII stored, GDPR-compliant, Swift SDK)
- **Crashes and hangs:** Apple `MetricKit` (no SDK dependency, data via Apple pipeline)
- **Opt-out:** users can disable telemetry in Settings; IT can disable it via MDM managed preference

---

## Architecture Principles

### 1. Provider Abstraction

All data access goes through a `CodeHostProvider` protocol backed by a canonical domain model. `GitHubProvider` is the first implementation. GitLab later conforms to the same protocol mapping its merge request model to the canonical types. UI and business logic depend only on the domain model, not provider-specific shapes.

```
CodeHostProvider (protocol)
  └── GitHubProvider
  └── GitLabProvider  ← future, backlog

Domain model (provider-independent):
  PullRequest, ReviewRequest, CIStatus, ReviewThread,
  Reviewer, ReviewState, CapabilityFlags
```

`CapabilityFlags` lets providers declare which features they support (e.g. team review requests, draft PRs), so UI can adapt without provider-specific branches.

### 2. SettingsStore

Single source of truth for all user and managed settings. Reads in strict priority order:

1. MDM managed preferences (`com.hubber.app` domain via `CFPreferences`)
2. `UserDefaults`
3. Hardcoded default

IT can lock any key at the managed-preferences layer. The corresponding settings control renders as disabled (visible but non-interactive) when a managed value is present. Enforced from M1 so enterprise provisioning (M5) is a configuration exercise, not a refactor.

### 3. SLO Resolution Function

```swift
func sloHours(for repo: String) -> Double
```

Today returns the global `SettingsStore` value. Per-repo overrides (backlog) slot in here without touching any call sites.

### 4. SLO Clock Definition

- **Starts:** `max(reviewRequestedAt, readyForReviewAt)` — the later of when the reviewer was assigned and when the PR was marked ready for review. Handles reviewers assigned while the PR was still a draft.
- **Stops:** reviewer submits any review (approve, changes requested, or comment-review)
- **Suspended:** PR converted back to draft — only non-draft PRs are in scope
- **Removed:** PR merged or closed

### 5. RefreshScheduler (M2)

Owns all polling cadence. State priority (highest wins):

| State | Interval |
|---|---|
| Any PR within 20% of SLO budget | 30 s |
| Popover open | 1 min |
| Background, normal | 5 min |
| Machine idle, all green | 15 min |

Manual refresh (⌘R) cancels the current timer and schedules the next tick from the refresh completion time. On GitHub rate-limit (429 / 403): back off to 15 min and surface a non-blocking status message in the footer. On sleep/wake: trigger an immediate refresh on wake, then resume normal cadence.

### 6. App Bundle Prerequisite

The project is currently an SPM executable. Notifications, Keychain access groups, sandboxing, code signing, and Sparkle all require a proper `.app` bundle. Converting to an Xcode app target with the correct entitlements is an explicit prerequisite task within M1, before any feature work that depends on those capabilities.

### 7. Build Variants

Two distinct build targets sharing one codebase:

| Variant | Sandbox | Update | Channels |
|---|---|---|---|
| Standard | No | Sparkle | GitHub Releases, Homebrew |
| MAS | Yes | App Store | Mac App Store |

Sandbox compliance is validated from M1. MAS-incompatible capabilities are flagged immediately, not discovered at submission time.

---

## Data Layer

### GitHub API Approach

- **Discovery:** GitHub Search API (`is:pr is:open review-requested:@me`, etc.) for the list of relevant PR node IDs
- **Enrichment:** GitHub GraphQL API for all per-PR details: CI status, reviewer states, review threads, mergeability, `reviewRequestedAt`, `readyForReviewAt`
- **Required OAuth scopes:** `repo` (private repo access), `read:org` (team membership for option B), `notifications` (M3)
- **Auth method:** GitHub App device flow (already implemented), token stored in Keychain. On token expiry: surface inline re-auth prompt, do not silently fail.

---

## Tab Specifications

### Reviews (Incoming)

**Data source:** GitHub Search API for discovery + GraphQL for enrichment

**Queries:**
- Default (mode A): `is:pr is:open review-requested:@me`
- Option B (settings toggle): also includes `team-review-requested:@me`
- Option C (backlog): PRs authored by org/team members — requires team member list with high-TTL cache

**Sort:** by SLO clock start time, oldest first (most urgent at top)

**Row content (normal density):**
- Author avatar (GitHub profile image preferred; initials + color as fallback)
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

**Purpose:** monitor CI health and reviewer progress on authored PRs; surface the two things that need the author's attention right now.

**Data source:** GitHub Search API for discovery + GraphQL for enrichment

**Query:** `is:pr is:open author:@me -is:draft`

**Sort:** most recently updated first

**Row content (normal density):**
- CI badge (passing / failing / running / pending)
- PR number + title
- Repo · CI detail string · unresolved thread count (if > 0)
- Reviewer avatar stack (up to 3, with state dot: approved=green, changes-requested=red, commented=blue)

**Action signals (things that need your attention):**
1. CI **failing** — needs a fix. CI **running** is not actionable and is not an action signal.
2. Unresolved review threads (see definition below)

**Unresolved thread definition:** configurable in settings, default = all open threads (B):
- **B — All open threads (default):** any review thread or standalone PR comment not yet resolved by the author
- **A — Review threads only:** threads from formal review submissions only; excludes standalone comments and bot comments
- **C — Change-requesters only:** threads from reviewers who submitted "changes requested"; highest signal, lowest noise

Outdated threads and dismissed reviews are excluded from all modes.

### Drafts

**Purpose:** let authors monitor CI health and commit activity on in-progress work without navigating to GitHub.

**Data source:** GitHub Search API — `is:pr is:open is:draft author:@me` (already live)

**Sort:** most recently updated first

**Row content (normal density):**
- Dashed-border doc icon
- PR number + title
- Repo · commit count · elapsed time since last update
- CI badge + status text

---

## Menubar Icon & Badge

**Badge value:** configurable via `SettingsStore`, default = **attention-needed count**

**Attention-needed = distinct PR count where the user has something actionable right now:**
- Any incoming review request (you need to review it)
- Any outgoing PR with **failing** CI (you need to fix it) — running CI does not count
- Any outgoing PR with unresolved threads (you need to respond)

A PR with both failing CI and unresolved comments counts as **one** item.

**Badge options (settings picker):**
- Incoming count only
- Attention-needed count (default)
- Off

**Icon states:**
- Normal: hub icon, no badge
- Has attention: badge with count
- Refreshing: subtle animation indicator

---

## Notifications (M3)

Background alerting via macOS `UNUserNotificationCenter`.

**Permission:** requested at first meaningful trigger, not at launch.

**First-run suppression:** on initial sync, a baseline snapshot is taken. Notifications only fire for changes relative to last-known state — never for the initial load. State is persisted across app restarts so a relaunch does not re-fire past events.

**Per-event opt-in (all off by default except "new review requested"):**

| Event | Default |
|---|---|
| New review requested | On |
| Review approved on your PR | Off |
| Changes requested on your PR | Off |
| CI failed on your PR | Off |
| PR merged | Off |

**Deduplication:** if the same event fires twice within one refresh cycle (e.g. two simultaneous approvals), they are batched into one notification.

**Permission denied:** silently no-ops. Settings UI shows a "Enable in System Settings" link if permission was denied.

**VIP filter (backlog):** for "new review requested", optionally restrict to notifications only when the PR author is in a user-defined VIP list.

**Tap action:** opens the PR URL in the default browser.

---

## Settings

### GitHub Account
- Signed-in user display + sign out
- Re-auth prompt when token expires (inline, non-blocking)

### Incoming Reviews
- Review SLO toggle (on/off)
- Review window slider (1–24h, default 4h)
- Show SLO as: Remaining / Elapsed / Light only (segmented control)
- Incoming mode: Explicit requests only / Include team requests (segmented control)

### Outgoing
- Unresolved threads: All open threads / Review threads only / Change-requesters only (segmented control, default: All open threads)

### Appearance
- Row density: Compact / Default / Spacious

### Badge
- Badge shows: Incoming count / Attention-needed / Off

### Notifications (M3)
- Per-event toggles
- "Enable in System Settings" link if permission denied

### Privacy
- Send anonymous usage analytics toggle (default: on)
- Crash reporting toggle (default: on)

### Developer (debug builds only)
- Log viewer, copy/clear, token storage path

---

## Accessibility

- All color-coded signals (SLO pills, CI badges, reviewer state dots) include non-color cues: shape differentiation and text labels at normal and spacious density
- VoiceOver labels on all interactive elements and status indicators
- Keyboard navigation through the popover
- Minimum contrast ratios met in both light and dark mode

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
| `unresolvedThreadMode` | String | `all` / `review` / `changesRequested` |
| `rowDensity` | String | `compact` / `normal` / `spacious` |
| `analyticsEnabled` | Boolean | Disable telemetry fleet-wide |
| `crashReportingEnabled` | Boolean | Disable crash reporting fleet-wide |
| `notificationsEnabled` | Boolean | Master kill switch for all notifications |
| `defaultNotificationEvents` | Array\<String\> | Which events are on by default |
| `providerAllowlist` | Array\<String\> | Allowed host URLs (e.g. `github.myco.com`) |
| `allowPersonalGitHub` | Boolean | Whether `github.com` personal accounts can connect |

When a key is present in the managed domain, `SettingsStore` uses that value and the corresponding settings control renders as disabled (visible but non-interactive).

Provider allowlist is enforced at auth time — disallowed hosts are never presented in the connection UI.

---

## Distribution

Two build variants, three channels:

| Channel | Variant | Format | Updates |
|---|---|---|---|
| GitHub Releases | Standard | Notarized DMG, universal binary | Sparkle |
| Homebrew | Standard | Cask formula | Sparkle |
| Mac App Store | MAS | Sandboxed app | App Store |

Sandbox compliance validated from M1. `brew install --cask hubber`.

---

## Milestones & GitHub Issues

### Milestone 1 — Live Data

**Prerequisite**
- Convert SPM executable to Xcode `.app` target with correct entitlements (required for Keychain access groups, notifications, signing)

**Architecture**
- Introduce `CodeHostProvider` protocol, canonical domain model (`PullRequest`, `ReviewRequest`, `CIStatus`, `ReviewThread`, `CapabilityFlags`), and `GitHubProvider` conformance
- Implement `SettingsStore` with MDM → UserDefaults → hardcoded default priority chain
- Add `sloHours(for repo:) -> Double` resolution function

**GitHub Service**
- Fetch incoming reviews: Search discovery + GraphQL enrichment (`reviewRequestedAt`, `readyForReviewAt`, SLO clock = `max` of both)
- Add option B: include `team-review-requested:@me` (settings toggle)
- Fetch outgoing PRs: CI status, unresolved thread count (configurable mode), reviewer states, mergeable flag
- Migrate Drafts tab to `CodeHostProvider` abstraction
- Response caching layer with per-resource TTL
- Token expiry handling: inline re-auth prompt

**UI**
- Wire Incoming tab to live GitHub data
- Wire Outgoing tab to live GitHub data
- Error and offline empty states for all three tabs
- "All clear" empty state for Incoming
- Settings toggle: incoming review mode (A / B)
- Settings picker: unresolved thread mode (A / B / C)
- GitHub avatar fetching with initials+color fallback

### Milestone 2 — Polish & Adaptive Refresh

- Implement `RefreshScheduler` with adaptive cadence and state priority rules
- Rate-limit handling: back off to 15 min, surface footer status message
- Sleep/wake: trigger immediate refresh on wake
- Smart menubar badge: attention-needed count (distinct actionable PRs), failing CI only
- Badge mode picker in settings
- ⌘R keyboard shortcut wired to manual refresh
- Menubar icon states: normal, has-attention, refreshing
- Provider switcher stub in header (hidden, single-provider — multi-account seam)
- TelemetryDeck integration: engagement and outcome-proxy events
- MetricKit crash/hang reporting

### Milestone 3 — Notifications

- Implement `NotificationScheduler`: baseline snapshot on first sync, diff on subsequent refreshes
- Persist last-known state across app restarts to prevent relaunch re-fires
- Request macOS notification permission at first meaningful trigger
- Permission-denied handling: silent no-op + "Enable in System Settings" link in settings
- Per-event-type opt-in settings UI
- Notification: new review requested
- Notification: review approved
- Notification: changes requested
- Notification: CI failed
- Notification: PR merged
- Event deduplication within one refresh cycle
- Notification tap → open PR in browser

### Milestone 4 — Distribution

- Xcode project: two targets (Standard and MAS) sharing one codebase
- GitHub Actions pipeline: build, sign, notarize, publish release
- Universal binary (arm64 + x86_64)
- GitHub Releases DMG artifact
- Sandbox entitlement audit: confirm MAS target is clean
- Mac App Store submission
- Homebrew cask formula
- Sparkle auto-update integration (Standard builds only)

### Milestone 5 — Enterprise / MDM

- Document `com.hubber.app` managed preferences domain and all lockable keys
- Managed preference enforcement in `SettingsStore` for all lockable keys
- Provider allowlist: disallowed hosts hidden from auth UI, enforced at connection time
- IT deployment guide with sample Jamf / Kandji / Mosyle configuration profiles
- MDM-compatible pkg installer

### Backlog

- Team activity feed — option C for Incoming (org/team member PRs, cached team member list with high TTL)
- VIP author filter for notifications
- Per-repo SLO override rules UI
- GitLab provider implementation (`GitLabProvider` conforming to `CodeHostProvider`)
- Multi-account UI — provider switcher visible when >1 account connected
- Noise controls: mute by repo, snooze per PR
- Accessibility audit: VoiceOver, keyboard navigation, contrast

---

## Open Questions

_None. All key product and implementation decisions resolved in design session 2026-06-15._
