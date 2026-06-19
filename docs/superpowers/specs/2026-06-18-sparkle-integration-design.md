# Sparkle auto-update integration — code + build (Issue #51)

**Date:** 2026-06-18
**Issue:** [#51](https://github.com/osuritz/hubber/issues/51) — `[infra] Sparkle auto-update integration (Standard builds only)`
**Milestone:** M4 — Distribution
**Status:** Design approved; ready for implementation plan

## Summary

Integrate Sparkle 2.x so Standard (non-MAS) builds of Hubber can auto-update via an
EdDSA-signed appcast. This spec covers **only the code + build half** of issue #51 —
the part that can be implemented and verified locally. The operational rollout
(key generation, appcast hosting, CI signing cert, `generate_appcast` automation,
end-to-end two-release test) is explicitly deferred to a follow-up.

Sparkle's security model is EdDSA-based (`SUPublicEDKey` / private key), fully
independent of Apple code signing. No paid Apple Developer account or notarization
is required. The single existing stable self-signed cert (`Hubber Self-Signed`,
in the login keychain, valid to 2027-06-16) is sufficient and correct for v1 — a
CA-derived cert chain would add nothing, because macOS Gatekeeper trusts only Apple
Developer ID / Mac App Store, not arbitrary CAs. The notarization upgrade is tracked
separately as epic #79 (M4b), blocked on a paid Apple account.

## Scope

### In scope (this PR)
1. Sparkle SPM dependency.
2. `SPUStandardUpdaterController` wiring + a "Check for Updates…" menu item.
3. `make-app.sh` reworked: embed `Sparkle.framework`, inside-out signing
   (drop `--deep`), Sparkle `Info.plist` keys (public key & feed URL injected via
   env, omitted when unset — no secrets hardcoded).
4. Version threading so release builds carry the real `CFBundleVersion`.
5. Local verification against the `Hubber Self-Signed` identity.

### Out of scope (→ rollout follow-up)
- EdDSA keypair generation and storage (Keychain + `SPARKLE_PRIVATE_KEY` CI secret).
- Appcast hosting decision (GitHub Pages vs. Releases) and the stable `SUFeedURL`.
- `generate_appcast` step in `release.yml`.
- Importing the self-signed cert into the CI keychain + related secrets.
- Publishing two real releases and running the end-to-end acceptance criteria.

## Current state (relevant facts)

- `osuritz/hubber`; SPM executable `Hubber`; macOS 14+; menu-bar (`LSUIElement`)
  app assembled by `Scripts/make-app.sh`.
- `make-app.sh` currently signs with `codesign --force --deep --sign "$SIGN_IDENTITY"`,
  defaulting to ad-hoc (`-`). `HUBBER_SIGN_IDENTITY` overrides it.
- Right-click menu is built in `main.swift` `configureStatusMenu()` — currently
  **Sign Out / separator / Quit**. Items target `AppDelegate`.
- Release flow: `release.yml` fires on `v*` tags → `make dist` → `gh release create`
  with `dist/Hubber.dmg` + `dist/Hubber.zip`.
- **Gap:** `make dist` does not pass `VERSION`, so `make-app.sh` always defaults to
  `0.1.0`. Sparkle compares `CFBundleVersion`; releases must carry the real version.
- No GitHub Pages, no `gh-pages` branch, no Actions secrets yet (all rollout concerns).

## Design

### 1. Dependency — `Package.swift`
Add to `dependencies`:
```swift
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
```
Add the `Sparkle` product to the **`Hubber` executable target only**. Do **not** add
it to the test target — Sparkle is runtime/AppKit glue and the bundle-less xctest host
is fragile (cf. the UNUserNotificationCenter-in-xctest crash lesson). `Package.resolved`
will be updated by the resolve.

### 2. Updater wiring
New file `Sources/Hubber/Updates/UpdaterController.swift`: a small `@MainActor` type
owning an `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
userDriverDelegate: nil)` and exposing it.

In `AppDelegate`:
- Hold an `UpdaterController` instance (constructed in `applicationDidFinishLaunching`,
  alongside the other startup wiring).
- In `configureStatusMenu()`, add **"Check for Updates…"** above "Sign Out", followed by
  a separator. Bind that item's `target`/`action` **directly to the Sparkle standard
  controller** (`checkForUpdates(_:)`) so Sparkle's built-in menu validation
  (`canCheckForUpdates`) drives its enabled state — `AppDelegate` does not proxy it.
  (The existing `statusMenu.items.forEach { $0.target = self }` line must not clobber
  the updater item's target; set the updater item's target after that loop or exclude it.)

### 3. `make-app.sh` — embed + inside-out sign
Replace the single `codesign --force --deep` call with:

1. **Locate** the framework: `find .build/artifacts -name 'Sparkle.framework' | head -1`.
   (Discover, never hardcode the artifact path — it varies across SPM versions.)
2. **Copy** preserving symlinks: `mkdir -p "$CONTENTS/Frameworks"` then
   `cp -R "$SPARKLE_FW" "$CONTENTS/Frameworks/"`.
3. **Sign inside-out** with `$SIGN_IDENTITY`, **without `--deep`**, resolving the
   versioned dir via the `Versions/Current` symlink (do not hardcode `Versions/B`):
   each `XPCServices/*.xpc`, then `Autoupdate`, then `Updater.app`, then the framework
   itself, then finally the outer app. **Keep** the XPC services and sign them
   individually (lower risk than surgically stripping the bundle; stripping noted as a
   later size optimization).
4. Keep the final `codesign --verify --deep --strict --verbose=2` gate.

Embed for **both** debug and release configs — the `Hubber` binary link-depends on
Sparkle, so the framework must always be present or the app won't launch. The ad-hoc
`make app-dev` launch is part of verification.

### 4. Sparkle `Info.plist` keys (`make-app.sh` heredoc)
Always write:
```xml
<key>SUEnableAutomaticChecks</key><true/>
<key>SUScheduledCheckInterval</key><integer>86400</integer>
<key>SUAllowsAutomaticUpdates</key><true/>
```
Write **only when the corresponding env var is set** (omit otherwise, so this PR
hardcodes no secrets and dev builds stay key-less):
- `SUFeedURL` ← `SPARKLE_FEED_URL`
- `SUPublicEDKey` ← `SPARKLE_PUBLIC_ED_KEY`

`SUEnableInstallerLauncherService` / `SUEnableDownloaderService` are not written —
Hubber is non-sandboxed.

### 5. Version threading
`release.yml`: compute `VERSION=${GITHUB_REF_NAME#v}` and call `make dist VERSION=$VERSION`
so `CFBundleShortVersionString` / `CFBundleVersion` reflect the tagged release. (Local
`make app` / `make app-dev` behaviour is unchanged when `VERSION` is omitted.)

## Verification (evidence before "done")

1. `make ci` (build + test + lint + swiftformat --lint) is green.
2. `HUBBER_SIGN_IDENTITY="Hubber Self-Signed" make app`, then confirm:
   - the app **launches** (i.e. `Sparkle.framework` loads — no Library Validation crash);
   - **"Check for Updates…"** is present and opens Sparkle's standard update UI
     (it will report no feed configured — that proves the wiring, since `SUFeedURL` /
     `SUPublicEDKey` are intentionally absent in this PR);
   - `codesign --verify --deep --strict` passes on the assembled bundle (acceptance
     criterion #4 from the issue).
3. `make app-dev` (ad-hoc, debug) still launches.

This work is **integration/build-verified, not unit-TDD'd**: Sparkle is runtime/AppKit
wiring with no pure logic to test-drive, and a Sparkle-importing unit test risks
crashing the bundle-less xctest host. This deviation from TDD is deliberate and called
out rather than papered over with a brittle test. The issue's signature-rejection and
end-to-end auto-update acceptance criteria require keys + a live appcast and are
verified in the rollout follow-up.

## Conventions
Single PR; body includes `Closes #51`; no co-author trailer; watch the PR's CI to green
before merging (locally-green ≠ CI-green).

## Risks / notes
- **Ad-hoc + Sparkle on dev builds:** without Hardened Runtime, Library Validation is
  not enforced, so an ad-hoc `make app-dev` build is expected to load the framework.
  Verification step 3 confirms this; if it fails, fall back to gating Sparkle embedding
  out of debug builds.
- **SPM artifact path drift:** mitigated by `find`-ing the framework rather than
  hardcoding `.build/artifacts/...`.
- **Cert expiry:** `Hubber Self-Signed` expires 2027-06-16; renew before then. Keeping a
  stable signing identity across releases also preserves Keychain ACL continuity for
  stored tokens.
