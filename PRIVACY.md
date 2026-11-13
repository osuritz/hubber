# Hubber Privacy Notice

_Last updated: 2026-11-10_

Hubber is a macOS menu-bar app that surfaces your pull-request review queue and PR health.
This notice explains exactly what data Hubber does and does not handle.

## The short version

- **Analytics are opt-in and OFF by default.** Nothing is sent unless you explicitly turn on
  "Share anonymous usage analytics" in onboarding or Settings → Privacy.
- Hubber **never** transmits repo names, PR titles, branch names, usernames/logins, org names,
  or email addresses. Counts, ages, enum values, and (for a crash) the name of the Hubber function
  that crashed — nothing else.
- **Crash & hang details stay on your Mac** — the crash log, error message, and backtrace are
  written to local logs only. If you have turned analytics on, a crash additionally sends the
  minimal `app.crashed` event described below; with analytics off, nothing about a crash is sent.

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
| `app.crashed` | sent on the launch after a crash: the signal number, a crash category from a fixed list (e.g. `duplicateDictionaryKey`, `indexOutOfRange`), and the name of the function in Hubber's own code that crashed. The error message itself is **not** sent, because it can contain your data |

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

## Diagnostics (local only)

Hubber subscribes to Apple's MetricKit to log crash and hang summaries — and basic performance
metric payloads (app version, OS version) — to your Mac's local system log (`os_log`) for
debugging.

Hubber also keeps its own logs in `~/Library/Logs/Hubber/`:

- `hubber.log` / `hubber.previous.log` — the current and previous session's activity log (refresh
  results, errors, and anything the app prints). It can contain your login and repository counts.
- `crash-<date>.log` — written on the launch after a crash: the error message, the backtrace, and
  the last log lines before the crash. The 10 most recent are kept.

**These files never leave your device** unless you choose to share them (for example by attaching
one to a bug report). You can disable all of this under Settings → Privacy ("Diagnostic logging");
that also stops the `app.crashed` analytics event, since no crash is recorded.

## Authentication

Your code-host access token is stored in the macOS Keychain (release builds) and used only to talk
directly to your code host (GitHub, GitHub Enterprise Server, or GitLab). It is never sent to us.

## Questions

Open an issue at https://github.com/osuritz/hubber.
