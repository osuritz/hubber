# Hubber — Managed Preferences Reference

> **Audience:** IT administrators deploying Hubber via MDM (Jamf, Kandji, Mosyle, etc.).
>
> **Issue:** [#52](https://github.com/osuritz/hubber/issues/52)

---

## Managed Domain

All Hubber managed preferences are read from the domain:

```
com.hubber.app
```

This domain is **intentionally different** from the app bundle identifier (`com.osuritz.hubber`).
Decoupling the managed domain from the bundle id means:

- A single configuration profile works across all Hubber build variants (Standard, MAS) without
  modification.
- Managed settings survive a bundle-id change without requiring profile redistribution.
- macOS reads forced/managed preferences from `/Library/Managed Preferences/<user>/<domain>.plist`
  and `/Library/Managed Preferences/<domain>.plist` (machine scope), keyed by whatever domain
  string the profile declares. The app calls `CFPreferencesCopyAppValue` / `CFPreferencesAppValueIsForced`
  with `com.hubber.app` — so the profile domain must match exactly.

**Do not change the profile domain to the bundle id.** It is correct as-is.

---

## When Values Are Applied

Managed preferences are resolved **at application launch**. There is no live-reload mechanism:
changes pushed to a device via MDM take effect the next time Hubber is quit and relaunched.

When a key is forced by MDM:

- Hubber reads the forced value at startup via `CFPreferencesCopyAppValue`.
- The corresponding setting in the UI is rendered as a **disabled (locked)** control — the user
  can see the current value but cannot change it.
- UserDefaults values for that key are silently ignored; the forced MDM value always wins.

---

## Lockable Key Reference

The table below is the authoritative IT-facing contract. Key names in the `Managed Key` column
**must be used verbatim** in configuration profiles targeting `com.hubber.app`. They are defined
as constants in `Sources/Hubber/Core/ManagedPreferences.swift` (`ManagedKey` enum) — the code
and this table share a single source of truth.

| Managed Key | Type | Default | Accepted Values / Format | Notes |
|---|---|---|---|---|
| `sloEnabled` | Boolean | `true` | `true` / `false` | Enables or disables the review SLO feature. UserDefaults persistence key is `reviewSLOEnabled` (legacy); the managed key is `sloEnabled` as per PRD. |
| `sloWindowHours` | Integer | `24` | Positive integer (hours) | SLO window duration. E.g. `48` for a 48-hour SLO. |
| `sloDisplay` | String | `"badge"` | `"badge"` \| `"menu"` \| `"both"` | Where the SLO countdown is shown. |
| `badgeMode` | String | `"count"` | `"count"` \| `"dot"` \| `"none"` | Dock/menu-bar badge style. |
| `incomingMode` | String | `"all"` | `"all"` \| `"assigned"` \| `"team"` | Which incoming PRs Hubber monitors. |
| `unresolvedThreadMode` | String | `"badge"` | `"badge"` \| `"none"` | How unresolved review threads are surfaced. |
| `rowDensity` | String or Integer | `"normal"` (`1`) | `"compact"` / `0`, `"normal"` / `1`, `"spacious"` / `2` | List row density. Accepts either the human-readable string or the raw integer — use the string form in profiles for clarity. |
| `analyticsEnabled` | Boolean | `true` | `true` / `false` | Gates TelemetryDeck anonymous usage analytics. Set `false` to disable entirely; the SDK is never initialised. |
| `crashReportingEnabled` | Boolean | `true` | `true` / `false` | Gates MetricKit crash and hang reports. Set `false` to disable; the MetricKit subscriber is never registered. |
| `notificationsEnabled` | Boolean | `true` | `true` / `false` | Master switch for all Hubber notifications. Forcing `false` also locks all per-event notification toggles. |
| `defaultNotificationEvents` | Array\<String\> (CSV) | all events | Comma-separated list of event codes | Restricts which notification event types are enabled. Forcing this key also locks all per-type notification toggles. See [Notification Event Codes](#notification-event-codes) below. |
| `providerAllowlist` | Array\<String\> | `[]` (no restriction) | Array of host strings, e.g. `["github.com"]` | When non-empty, only the listed provider hosts are permitted. An empty array means no host restriction. |
| `allowPersonalGitHub` | Boolean | `true` | `true` / `false` | When `false`, sign-in to `github.com` (personal) is blocked even if `providerAllowlist` is empty or contains `github.com`. Sign-in UI shows a "restricted by your organization" message and the button is disabled. |

### Notification Event Codes

Used in the `defaultNotificationEvents` array:

| Code | Description |
|---|---|
| `review_requested` | Review requested on a PR |
| `mentioned` | Direct mention in a PR or comment |
| `assigned` | PR assigned to you |
| `push` | New commit pushed to a PR you are reviewing |
| `resolved` | Review thread resolved |
| `closed` | PR closed or merged |

---

## How Locked Controls Render

When a key is forced by MDM, Hubber:

1. Reads the forced value at launch (MDM value always wins over UserDefaults).
2. Renders the corresponding toggle or picker as **disabled** (greyed out / `SwiftUI .disabled(true)`).
3. Does not expose a way for the user to override the setting.

This means IT can both *restrict* settings (set a value and lock it) or simply *set a default*
(write to UserDefaults via a configuration profile without forcing, letting users override it).

---

## Provider Allowlist Enforcement

The `providerAllowlist` and `allowPersonalGitHub` keys are enforced in two layers:

1. **UI layer:** The "Sign in with GitHub" button is disabled and a "Sign-in is restricted by your
   organization." message is shown when the policy blocks `github.com`.
2. **Logic layer:** `HubberStore.startSignIn()` checks the policy before starting the OAuth device
   flow and returns an error state immediately if blocked.

This defense-in-depth ensures enforcement even if the UI is bypassed.

---

## Deploying a Configuration Profile

Refer to [it-deployment-guide.md](./it-deployment-guide.md) for end-to-end MDM deployment steps.

A ready-to-edit sample profile is provided at
[sample-profiles/hubber-managed.mobileconfig](./sample-profiles/hubber-managed.mobileconfig).

---

## Version History

| Version | Change |
|---|---|
| M5 | Initial managed-preferences support: all 13 lockable keys, injectable seam, UI lock indicators |
