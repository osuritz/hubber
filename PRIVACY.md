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
