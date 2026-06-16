# M4a — Unsigned Distribution Implementation Plan

> Branch: `feat/m4a-distribution` (off `main`). Ship a real, ad-hoc-signed `Hubber.app` + downloadable DMG/zip via GitHub Releases — **no paid Apple Developer account**. Accepts the one-time Gatekeeper "Open Anyway" (developer audience, gauging interest). Also unblocks M3 notification delivery + Keychain (both need a real bundle id).

**Goal:** Turn the SPM executable into a distributable `.app` and a release pipeline, using only free tooling (ad-hoc `codesign`, `hdiutil`, GitHub Actions).

**Issues (partial):** #7/#44 (a real `.app` bundle — via a build script, not yet a full Xcode/MAS project), #45 (CI build+release, no signing/notarization), #46 (universal binary), #47 (DMG artifact — unsigned).

**Key facts:** ad-hoc signing (`codesign --sign -`) is free and REQUIRED for the arm64 binary to launch at all; it is NOT notarization. An un-notarized app downloaded via a browser is Gatekeeper-quarantined → first launch needs right-click→Open / "Open Anyway". A `curl`-downloaded app is never quarantined (bonus no-warning path). The SPM universal build output is at `.build/apple/Products/Release/Hubber`.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Scripts/make-app.sh` | Build universal release → assemble `Hubber.app` → ad-hoc sign |
| Create | `Resources/Info.plist` (template) | Bundle metadata (id, LSUIElement, version) |
| Modify | `Makefile` | `app`, `dmg`, `zip`, `dist` targets |
| Create | `Scripts/make-dmg.sh` | `hdiutil` DMG with `/Applications` symlink |
| Create | `install.sh` | `curl … | bash` installer (download release zip → /Applications → launch) |
| Create | `.github/workflows/release.yml` | Tag → universal build → DMG+zip → GitHub Release (runs-on macos-26) |
| Modify | `README.md` | Install section (download + Open Anyway, or curl one-liner) |

---

## Task 1 — `Hubber.app` bundle (ad-hoc signed)

`Scripts/make-app.sh`:
1. `swift build -c release --arch arm64 --arch x86_64` (universal; verify with `lipo -info .build/apple/Products/Release/Hubber` → two archs).
2. Assemble `Hubber.app/Contents/`: `MacOS/Hubber` (the universal binary), `Info.plist`, `Resources/` (app icon if present — none yet; note as a follow-up, ship without for now), `PkgInfo` (`APPL????`).
3. `Info.plist` keys: `CFBundleIdentifier=com.osuritz.hubber`, `CFBundleExecutable=Hubber`, `CFBundleName`/`CFBundleDisplayName=Hubber`, `CFBundleShortVersionString` (from `VERSION` file or arg, default `0.1.0`), `CFBundleVersion`, `CFBundlePackageType=APPL`, `LSUIElement=true` (menubar accessory — no Dock icon), `LSMinimumSystemVersion=14.0`, `NSHumanReadableCopyright`.
4. Ad-hoc sign: `codesign --force --deep --sign - Hubber.app` (NO `--options runtime` — hardened runtime is only for notarization).
5. Verify: `codesign --verify --deep --strict --verbose=2 Hubber.app` must pass. (`spctl --assess` will report "rejected: unnotarized" — expected and fine.)

`Makefile` `app` target wraps the script. Commit: `feat(dist): build ad-hoc-signed Hubber.app bundle (universal)`.

## Task 2 — DMG + zip packaging

- `make zip`: `ditto -c -k --keepParent Hubber.app dist/Hubber.zip` (ditto preserves the code signature and bundle structure; do NOT use plain `zip`).
- `make dmg` (`Scripts/make-dmg.sh`): stage `Hubber.app` + a symlink to `/Applications` in a temp dir, `hdiutil create -volname Hubber -srcfolder <stage> -ov -format UDZO dist/Hubber.dmg`. (Unsigned DMG — fine; the app inside is what matters.)
- `make dist`: `app` then `dmg` + `zip`.

Commit: `feat(dist): DMG and zip packaging targets`.

## Task 3 — `curl | bash` installer (bonus, no-warning path)

`install.sh`: resolve the latest release's `Hubber.zip` asset URL (via the GitHub API/`gh`), download with `curl`, unzip to a temp dir, `xattr -dr com.apple.quarantine Hubber.app` (belt-and-suspenders), `rm -rf /Applications/Hubber.app`, move it in, `open -a Hubber`. Print clear progress + a fallback note. Commit: `feat(dist): curl|bash install script`.

## Task 4 — GitHub Actions release pipeline (#45/#46/#47, unsigned)

`.github/workflows/release.yml`:
- `on: push: tags: ['v*']` + `workflow_dispatch`.
- `runs-on: macos-26` (REQUIRED — macos-latest pins Swift 6.1 and breaks 6.3-valid code).
- Steps: checkout → `swift build -c release --arch arm64 --arch x86_64` → `make app dmg zip` → upload `dist/Hubber.dmg` + `dist/Hubber.zip` as a GitHub Release (use `gh release create "$GITHUB_REF_NAME" dist/Hubber.dmg dist/Hubber.zip --generate-notes`, or `softprops/action-gh-release`). No secrets needed.
- (Optional) a separate `build.yml` PR-CI job that runs `swift build` + `swift test` + `make lint` on `macos-26` for every PR.

Commit: `ci(dist): GitHub Actions release pipeline on macos-26`.

## Task 5 — README install docs

Add an "Install" section: download the latest `Hubber.dmg` (or `.zip`) from Releases → drag `Hubber` to Applications → **first launch: right-click → Open** (or System Settings → Privacy & Security → "Open Anyway") because it isn't notarized yet → grant notification permission when asked. Also document the one-line `curl -fsSL …/install.sh | bash`. Note it's ad-hoc-signed / not notarized (notarization comes with a paid Apple Developer account). Commit: `docs: install instructions for unsigned builds`.

---

## Acceptance (whole PR)
- `make app` produces `Hubber.app`; `codesign --verify --deep --strict Hubber.app` passes; `lipo -info` shows arm64 + x86_64.
- `make dmg` and `make zip` produce `dist/Hubber.dmg` / `dist/Hubber.zip`.
- `.github/workflows/release.yml` is valid and pinned to `macos-26`; install.sh + README written.
- `swift build`/`swift test` still green; `make lint` 0; `make format` idempotent. (`dist/` and `*.app` added to `.gitignore`.)
- **Maintainer verifies on-device:** the installed `.app` launches, the menubar item appears, sign-in works, and (the M3 payoff) notification permission can be granted + a banner can fire.

## Deferred to "M4b" (needs the paid Apple Developer account)
Notarization (`xcrun notarytool`), Developer ID signing, a notarized/signed DMG, the full Xcode project + sandboxed **MAS** target (#44/#48/#49), **Sparkle** auto-update (#51), **Homebrew** cask (#50), an app icon (`.icns`).

## Self-Review Checklist
- [ ] Universal, ad-hoc-signed `.app` with correct Info.plist (bundle id, LSUIElement)
- [ ] `codesign --verify` passes; DMG + zip build
- [ ] Release workflow on macos-26; no secrets required
- [ ] README "Open Anyway" + curl one-liner; `dist/` gitignored
- [ ] Notifications/Keychain now functional in the bundled app (maintainer-verified)
