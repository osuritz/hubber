# Hubber

Hubber is a macOS menu-bar app that keeps GitHub and GitLab review work visible at a glance, so you do not have to open a browser to find out what is waiting on you.

It shows three streams of work in a native popover:

- **Incoming**: pull requests where your review is requested, with review-SLO timing.
- **Outgoing**: your open pull requests, with CI status, unresolved review threads, and reviewer state.
- **Drafts**: your draft pull requests, with CI status and freshness.

Hubber surfaces work and opens it in your browser. It does not show diffs, write reviews, or merge.

## What it does today

- Live data from github.com, GitHub Enterprise Server, and GitLab (gitlab.com or a self-hosted server).
- Sign-in: GitHub App device flow or a personal access token for github.com; personal access tokens for GitHub Enterprise Server and GitLab.
- Multiple accounts at once, added under Settings → Accounts, with a first-run onboarding flow.
- Menu-bar badge and per-tab count badges.
- Review-SLO timing on incoming reviews, with a configurable threshold.
- Notifications for new review requests, approvals, requested changes, failed CI, and merged PRs. Each type can be toggled.
- Settings for the badge, row density, panel width, status indicator style, and open at login.
- Managed preferences for IT-deployed configuration; see [`docs/enterprise`](docs/enterprise).
- Opt-in anonymous usage analytics, off by default. See [`PRIVACY.md`](PRIVACY.md).

## Install

### Quick install (recommended)

```sh
curl -fsSL https://raw.githubusercontent.com/osuritz/hubber/main/install.sh | bash
```

The [installer](install.sh) downloads `Hubber.zip` from the latest release, verifies its SHA-256 and code signature, installs `Hubber.app` to `/Applications` (replacing any existing copy), and launches it. Run it again to update.

Hubber is ad-hoc-signed but not notarized. A copy fetched with `curl` is not quarantined, so it opens without a Gatekeeper prompt; that is why this is the recommended path.

Options, set as environment variables before `bash`:

| Variable | Effect |
| --- | --- |
| `HUBBER_VERSION=0.1.2` | Install a specific release instead of the latest. |
| `HUBBER_INSTALL_DIR=~/Applications` | Install somewhere other than `/Applications`. |
| `HUBBER_NO_OPEN=1` | Do not launch Hubber after installing. |

For example: `curl -fsSL https://raw.githubusercontent.com/osuritz/hubber/main/install.sh | HUBBER_VERSION=0.1.2 bash`

When Hubber asks for notification permission, click **Allow** so review banners can appear.

### Manual download (DMG or zip)

1. Go to the [latest release](https://github.com/osuritz/hubber/releases/latest) and download `Hubber.dmg` or `Hubber.zip`.
2. Open the DMG and drag **Hubber** to your **Applications** folder (or unzip and move `Hubber.app` to `/Applications`).
3. Try to open Hubber once. macOS will block it, because a browser-downloaded copy is quarantined. Then go to **System Settings → Privacy & Security** and click **Open Anyway**. Alternatively, remove the quarantine attribute:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Hubber.app
   ```

### Updates

Release builds do not currently ship an update feed, so there is no in-app auto-update yet. To update, re-run the installer or re-download the latest release. The Sparkle updater is wired in and activates only when a build is made with a feed URL and public key (`SPARKLE_FEED_URL`, `SPARKLE_PUBLIC_ED_KEY`); the release workflow does not set them.

## Signing in and access problems

For token setup and required permissions for github.com, GitHub Enterprise Server, and GitLab, and for what to do when a token is rejected, see [`docs/token-permissions.md`](docs/token-permissions.md).

If you are signed in but the lists are empty, or an organization's pull requests are missing, the cause is almost always access rather than a bug: see [Not seeing your organization's pull requests?](docs/token-permissions.md#not-seeing-your-organizations-pull-requests).

## Build from source

Requires macOS 14 or newer, Xcode 26 or newer, and Swift 6 or newer.

```sh
swift build
swift run Hubber   # runs the menu-bar app; the terminal stays attached until you quit
make app           # universal, ad-hoc-signed Hubber.app in the project root
make dist          # Hubber.app plus dist/Hubber.dmg and dist/Hubber.zip
make ci            # build, tests, SwiftLint, SwiftFormat check (what CI runs)
```

Debug builds store tokens in a file under `~/Library/Application Support/Hubber/` instead of the Keychain; release builds use the Keychain. See [`AGENTS.md`](AGENTS.md) for the repository layout and tooling.

## Using Hubber

- Left-click the menu-bar item to open or close the popover.
- Right-click it for a menu with Sign Out and Quit.
- Use the gear button for settings and the refresh button to fetch immediately.

## Troubleshooting

If `swift run Hubber` appears to hang, that is expected: the process is running the menu-bar event loop.

If the status item is hard to find, look on the right side of the macOS menu bar for the Hubber symbol and count.

### Logs and crash reports

Hubber keeps its own logs in `~/Library/Logs/Hubber/` (also listed in Console.app under *Log Reports*):

- `hubber.log` and `hubber.previous.log`: the current and previous session's activity log.
- `crash-<date>.log`: written on the launch after a crash, with the error message, the backtrace, and the last log lines before it. Attach this file when reporting a crash.

macOS's own report (`~/Library/Logs/DiagnosticReports/Hubber-*.ips`) is still produced, but it does not include the Swift error message. To check that crash capture works on a build, run `open Hubber.app --env HUBBER_CRASH_SELFTEST=1`, then launch Hubber again normally. Logging can be turned off under Settings → Privacy ("Diagnostic logging").

## Not done yet

- Notarization, which needs a paid Apple Developer account. Builds are ad-hoc-signed.
- A published update feed for in-app updates (see Updates above).

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Contributions require agreeing to the CLA described there.

## License

Hubber is **dual-licensed**:

- **GPL-3.0** (open source) — see [`LICENSE`](LICENSE). Use, modify, and redistribute
  Hubber under the GNU General Public License v3.0; any version you distribute must also
  be GPL-3.0 with its source.
- **Commercial license** — for use without the copyleft obligations (e.g. shipping a
  closed-source derivative or embedding Hubber in a proprietary product) and for
  enterprise support. See [`COMMERCIAL.md`](COMMERCIAL.md).

Using Hubber as-is — including inside a company — is free under GPL-3.0; a commercial
license is only needed to distribute a proprietary derivative or to obtain commercial
support.

Copyright © 2026 Olivier Suritz.
