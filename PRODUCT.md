# Hubber — Product Statement

> **What this file is.** The north-star grounding for Hubber, written for both humans
> and AI agents. It answers *why Hubber exists*, *what it is and is not*, and *how we
> decide*. It is the tie-breaker when a decision is ambiguous.
>
> **How it relates to the other docs:**
> - `docs/superpowers/specs/2026-06-15-hubber-prd-design.md` — the detailed PRD/spec (the *what*, in depth).
> - `AGENTS.md` — the build/contribution guide (the *how to work in the repo*).
> - **`PRODUCT.md` (this file)** — the *why* and the decision rules. When the PRD and
>   reality disagree, this file says which way to lean.

---

## One line

**Hubber keeps engineers on top of the PRs waiting on them — and the health of the PRs
they wrote — ambiently, from the macOS menu bar, without opening a browser.**

---

## The statement (for humans)

Engineers lose hours to a small, recurring tax: tabbing to GitHub to check "is anything
waiting on me?", "did my CI pass?", "did someone request changes?". The answer is usually
*no* — but the only way to know is to go look. That polling is context-switch poison.

Hubber removes the polling. It lives in the menu bar and surfaces exactly three streams of
work: **reviews waiting on you**, **your open PRs** (CI + reviewer state), and **your
drafts**. A badge tells you when something actually needs you, and a notification tells you
the moment it changes. When you want to act, Hubber opens the PR in your browser — it never
tries to replace GitHub.

It is built to feel like it shipped with macOS — vibrancy, SF Pro, dark/light mode, Keychain
auth — and to be honest about your data: it reports *counts and ages*, never repo names, PR
titles, or usernames. It is free, works the same for a solo engineer and an enterprise fleet,
and is architected so any code host (GitHub today, GitLab and GitHub Enterprise Server
already supported, others later) plugs into the same UI.

---

## For AI agents — decision grounding

Use this section to evaluate proposals, resolve ambiguity, and prioritize. Prefer these
rules over your own assumptions.

### Prime directive
Maximize an engineer's **ambient awareness of their review obligations and authored-PR
health**, at the lowest possible attention cost. Every feature is judged by whether it
*increases signal* or *adds noise*.

### Hard rails — what Hubber is NOT (reject proposals that cross these)
- ❌ Not a GitHub replacement: **no diff viewing, no review-writing, no merging in-app.**
  Hubber surfaces, then hands off to the browser.
- ❌ Not a project manager: no issues, milestones, boards, or planning.
- ❌ Not cross-platform: macOS-native only. No web, mobile, or Electron.
- ❌ Not a data collector: never transmit repo names, PR titles, usernames, org names, or
  branch names. Counts, ages, and distributions only.

### The inclusion test (apply to any new feature)
Ask, in order:
1. **Does it increase awareness of "what needs me now" or "is my work healthy"?** If no → reject or backlog.
2. **Can it be expressed in the three-stream model (Reviews / Outgoing / Drafts) + badge + notification?** If it needs a new surface, the bar is much higher.
3. **Does it add attention cost (noise)?** If yes, it must ship with a control to suppress that cost.
4. **Does it respect the privacy rail and the native-feel rail?** If no → redesign until it does.
5. **Is it provider-agnostic?** New capabilities go through `CodeHostProvider` + the canonical domain model, never provider-specific UI branches. Use `CapabilityFlags` for providers that lack a feature.

### Invariants (do not violate without an explicit product decision)
- **Settings priority is always:** MDM managed preferences → `UserDefaults` → hardcoded default. Any lockable key IT sets renders its control disabled, not hidden.
- **SLO clock** starts at `max(reviewRequestedAt, readyForReviewAt)`, stops on first review submission, suspends on draft, ends on merge/close. Don't redefine casually.
- **Attention-needed** = distinct PR count that is actionable *right now*: incoming review requested, OR your PR with **failing** CI (running ≠ actionable), OR your PR with unresolved threads. A PR that is both failing+unresolved counts **once**.
- **Notifications** never fire on first sync (baseline snapshot), persist across restarts, and are off by default except "new review requested".
- **Native-feel** is a feature: vibrancy, SF Pro, system appearance, 420pt popover. Regressions here are bugs.

### Quality bars
- Accessibility: color signals always carry a non-color cue (shape + label); VoiceOver labels on all interactive/status elements; full keyboard nav; WCAG AA contrast in both modes.
- Performance: adaptive refresh, never hammer the API; back off on rate-limit and surface it non-blocking.
- Trust: privacy and update behavior must be legible to a skeptical open-source developer.

---

## Who it's for

- **Individual contributor (primary for v1):** wants ambient awareness of their review queue
  and PR health without checking GitHub constantly. Installs in seconds, trusts it with a
  token, forgets it's there until it pings.
- **Enterprise team:** IT pre-configures and locks settings fleet-wide via MDM; leads want
  SLO defaults and notification policy. Served by the same binary, configured via managed
  preferences.

---

## How we measure success

Privacy-first product analytics (TelemetryDeck) + Apple MetricKit for crashes/hangs. The full
metric set lives in the PRD ("Success Metrics"). The headline questions:
- **Engagement:** DAU/WAU, sessions/day, click-through per tab.
- **Retention:** 7-day / 30-day retention; % who enable ≥1 notification; % who tune SLO.
- **Outcome proxies (counts/ages only):** queue depth at open, SLO color mix, % "all clear",
  stale-draft and failing-CI rates.

> Telemetry must never compromise the privacy rail. See the v1 note on default-on analytics below.

---

## v1 Definition & Scope (current — decided 2026-06-17)

**v1 target:** Public open-source launch to **individual engineers**, distributed via
**GitHub Releases + Homebrew**. **No paid Apple Developer account for v1** → the app ships
**unsigned** (ad-hoc), so *reducing first-launch friction by non-notarization means is the
top adoption priority*.

**The core app is feature-complete.** M1–M3 (live data, adaptive refresh, notifications),
M4a (unsigned distribution), and M6 (multi-connection: GitLab + GHES + multi-account
foundation) are shipped. M5 (Enterprise/MDM) is implemented in code and docs.

**In v1 scope:**
- Honest front door: README/AGENTS rewritten to reflect the real (live, multi-connection) app. (App icon ✅ done — `assets/hubber.icon` compiled into the bundle by `Scripts/make-app.sh`.)
- **Homebrew cask** — the friction-killer for the individual-OSS audience; needs *no* Apple account.
- Accessibility audit (#63) to WCAG AA.
- Noise controls (#62): mute-by-repo, snooze-per-PR.
- M5 bookkeeping: verify shipped MDM code against #52–#56 and close them.
- Multi-account UI (#61, in progress) completing M6's visible provider switcher.

**Explicitly deferred (post-v1):**
- **M4b (#79)** in full — Developer ID signing, notarization, Sparkle auto-update, Mac App
  Store. Account-blocked, not engineering-blocked. Revisit when/if a paid Apple account is acquired.
- Backlog niceties: team activity feed (#57), VIP notification filter (#58), per-repo SLO UI (#59).

**v1 watch-items (trust risks for a public dev-tool launch):**
- Analytics + crash reporting **default to `true`**. For a skeptical OSS dev audience, evaluate
  default-off or a prominent first-run opt-in before launch.
- **No update mechanism** ships without Sparkle. Homebrew users get `brew upgrade`; direct
  DMG/curl users have none. Consider a lightweight Releases version-check (no Apple account needed).
- **No launch-at-login.** An ambient app users forget to relaunch is an app they stop using.

---

## Operating principles

1. **Awareness over action.** When torn, choose the design that tells the user something,
   not the one that does something. Action lives in the browser.
2. **Signal is sacred; noise needs a knob.** Anything that can add to the badge or fire a
   notification ships with a way to turn it down.
3. **Native by default.** Match macOS conventions before inventing.
4. **Privacy is a promise, not a setting.** The "never tracked" list is a contract.
5. **One codebase, many hosts.** Generalize through the provider abstraction; never fork the UI per provider.
6. **Ship honest.** Docs, install instructions, and data behavior must match reality at all times.
