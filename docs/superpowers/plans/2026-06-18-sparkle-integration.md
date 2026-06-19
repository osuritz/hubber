# Sparkle Integration (code + build) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire Sparkle 2.x into Hubber's Standard build — the app updater + menu item, the `make-app.sh` embed/sign rework, release version threading, and a rollout runbook — without performing the operational rollout (keys/hosting/CI cert).

**Architecture:** Sparkle ships as a binary XCFramework SPM dependency. A thin `UpdaterController` owns `SPUStandardUpdaterController`; a "Check for Updates…" menu item is wired straight to Sparkle's controller so its built-in validation applies. `make-app.sh` embeds `Sparkle.framework` and signs **inside-out** (no `--deep`). Update integrity is EdDSA-based (`SUPublicEDKey`/private key), independent of Apple code signing — so the existing `Hubber Self-Signed` cert is sufficient. The feed URL and public key are injected from env vars and omitted when unset, so this PR bakes in no secrets.

**Tech Stack:** Swift 6.3 / SwiftPM, AppKit menu-bar app, Sparkle 2.9.x, bash build scripts, GitHub Actions.

## Global Constraints

- **Swift toolchain 6.3**; macOS deployment floor **14.0**; CI/release runner **macos-26** (never `macos-latest` — it pins Swift 6.1 and rejects valid 6.3 code).
- **Sparkle pinned `from: "2.9.0"`** (resolves 2.9.x).
- **No secrets in the repo.** `SUFeedURL` ← env `SPARKLE_FEED_URL`; `SUPublicEDKey` ← env `SPARKLE_PUBLIC_ED_KEY`; both omitted from `Info.plist` when their env var is unset.
- **Signing:** release verification uses `HUBBER_SIGN_IDENTITY="Hubber Self-Signed"`; default stays ad-hoc (`-`) for dev. Sign **inside-out, never `--deep`** on the app.
- **Bundle id:** `com.osuritz.hubber`.
- **Commits:** Conventional Commits; **no co-author trailer**. PR body uses **`Refs #51`** (not `Closes` — rollout is deferred, so #51's end-to-end acceptance criteria aren't met yet).
- **Pre-push gate:** `make ci` = `swift build` + `swift test` + `swiftlint lint` + `swiftformat --lint`. "Passes locally" means this is green. Then watch the PR's CI to green before merge.

## File Structure

- **Modify** `Package.swift` — add Sparkle dependency + product on the `Hubber` target only.
- **Auto** `Package.resolved` — updated by `swift package resolve`.
- **Create** `Sources/Hubber/Updates/UpdaterController.swift` — owns `SPUStandardUpdaterController`; exposes the menu target/action. Sole responsibility: encapsulate Sparkle so the rest of the app doesn't import it.
- **Modify** `Sources/Hubber/main.swift` — instantiate `UpdaterController`; add "Check for Updates…" to `statusMenu` without clobbering its Sparkle target.
- **Modify** `Scripts/make-app.sh` — Sparkle `Info.plist` keys, embed `Sparkle.framework`, inside-out signing.
- **Modify** `.github/workflows/release.yml` — thread the tag version into `make dist`.
- **Create** `docs/runbooks/sparkle-auto-update.md` — operator runbook for the deferred rollout.

> **Verification note (applies to all tasks):** Per the approved spec, the Swift glue and shell changes are **build/integration-verified, not unit-TDD'd** — Sparkle is runtime/AppKit wiring with no pure logic to test-drive, and a Sparkle-importing unit test risks crashing the bundle-less xctest host. Each task therefore ends with concrete verification commands and expected output in place of a unit test. This is deliberate and matches the spec.

---

### Task 1: Add the Sparkle SPM dependency

**Files:**
- Modify: `Package.swift`
- Auto: `Package.resolved`

**Interfaces:**
- Consumes: nothing.
- Produces: the `Sparkle` product is linkable by the `Hubber` target; `Sparkle.framework` lands under `.build/artifacts/` after resolve (consumed by Task 3's `make-app.sh`).

- [ ] **Step 1: Add the dependency and product to `Package.swift`**

Edit `Package.swift` so the `dependencies` array and the `Hubber` target read exactly:

```swift
    dependencies: [
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Hubber",
            dependencies: [
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Hubber"
        ),
```

Leave the `HubberTests` target unchanged — do **not** add Sparkle to it.

- [ ] **Step 2: Resolve and build**

Run: `swift package resolve && swift build`
Expected: resolve downloads `Sparkle` (a binary XCFramework zip, verified by checksum); build succeeds. First resolve is slower due to the download.

- [ ] **Step 3: Verify the framework artifact is present**

Run: `find .build/artifacts -name 'Sparkle.framework' -maxdepth 6 | head -1`
Expected: a non-empty path, e.g. `.build/artifacts/sparkle/Sparkle/Sparkle.framework` (exact path may differ — Task 3 discovers it via `find`, never hardcodes).

- [ ] **Step 4: Confirm the test target still builds and the gate is green**

Run: `make ci`
Expected: PASS — `swift build`, `swift test`, `swiftlint`, and `swiftformat --lint` all succeed. (This confirms the binary target links cleanly for both the executable and the xctest bundle.)

- [ ] **Step 5: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "build: add Sparkle 2.9 SPM dependency

Refs #51"
```

---

### Task 2: UpdaterController + "Check for Updates…" menu item

**Files:**
- Create: `Sources/Hubber/Updates/UpdaterController.swift`
- Modify: `Sources/Hubber/main.swift` (add stored property near `:21`; rewrite `configureStatusMenu()` at `:207-221`)

**Interfaces:**
- Consumes: the `Sparkle` product from Task 1.
- Produces: `UpdaterController` — `@MainActor final class`, `init()`, properties `var checkForUpdatesTarget: AnyObject` and `var checkForUpdatesAction: Selector`. `main.swift` uses these two to wire the menu item; nothing else in the app imports Sparkle.

- [ ] **Step 1: Create `UpdaterController.swift`**

```swift
import AppKit
import Sparkle

/// Owns Sparkle's standard updater for the Standard (non-MAS) build and exposes
/// the menu wiring for "Check for Updates…".
///
/// The rest of the app does not import Sparkle: it drives updates through
/// `checkForUpdatesTarget` / `checkForUpdatesAction`, which point straight at
/// `SPUStandardUpdaterController` so Sparkle's own `canCheckForUpdates`
/// menu-item validation applies automatically.
///
/// Auto-update only activates when the bundle carries `SUFeedURL` + `SUPublicEDKey`
/// (injected at build time in release/CI). In dev builds those keys are absent, so
/// scheduled checks are inert and "Check for Updates…" reports no feed — which still
/// proves the wiring.
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Target for the "Check for Updates…" menu item — Sparkle's controller itself.
    var checkForUpdatesTarget: AnyObject { controller }

    /// Action for the "Check for Updates…" menu item.
    var checkForUpdatesAction: Selector { #selector(SPUStandardUpdaterController.checkForUpdates(_:)) }
}
```

- [ ] **Step 2: Add the `UpdaterController` stored property to `AppDelegate`**

In `Sources/Hubber/main.swift`, alongside the other stored properties (after `private let store = HubberStore()` at `:21`), add:

```swift
    private let updaterController = UpdaterController()
```

- [ ] **Step 3: Add "Check for Updates…" to the status menu**

Replace `configureStatusMenu()` (`main.swift:207-221`) with:

```swift
    private func configureStatusMenu() {
        statusMenu.removeAllItems()

        // Routed straight to Sparkle's controller so its canCheckForUpdates
        // validation enables/disables this item without AppDelegate proxying it.
        let checkForUpdates = statusMenu.addItem(
            withTitle: "Check for Updates…",
            action: updaterController.checkForUpdatesAction,
            keyEquivalent: ""
        )
        checkForUpdates.target = updaterController.checkForUpdatesTarget

        statusMenu.addItem(.separator())
        statusMenu.addItem(
            withTitle: "Sign Out",
            action: #selector(signOut(_:)),
            keyEquivalent: ""
        )
        statusMenu.addItem(.separator())
        statusMenu.addItem(
            withTitle: "Quit",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        // Point the Hubber-owned items at self, but DON'T clobber the updater item
        // (its target must stay the Sparkle controller). Separators have no target.
        for item in statusMenu.items where item.target == nil && !item.isSeparatorItem {
            item.target = self
        }
    }
```

- [ ] **Step 4: Run the gate**

Run: `make ci`
Expected: PASS. If `swiftformat --lint` or `swiftlint` flags the new file, run `make format` then `make fix`, re-run `make ci`, and re-stage.

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Updates/UpdaterController.swift Sources/Hubber/main.swift
git commit -m "feat(updates): wire Sparkle updater + Check for Updates menu item

Refs #51"
```

---

### Task 3: Embed Sparkle and rework `make-app.sh` signing

**Files:**
- Modify: `Scripts/make-app.sh` (Info.plist heredoc `:70-103`; signing block `:129-148`)

**Interfaces:**
- Consumes: `Sparkle.framework` from `.build/artifacts` (Task 1); the menu item from Task 2 (for the launch check).
- Produces: a `Hubber.app` with `Contents/Frameworks/Sparkle.framework` embedded and signed inside-out, Sparkle `Info.plist` keys present, passing `codesign --verify --deep --strict`.

- [ ] **Step 1: Add the always-on Sparkle keys to the Info.plist heredoc**

In `Scripts/make-app.sh`, inside the `Info.plist` heredoc, add these keys immediately before the closing `</dict>` (after the `NSPrincipalClass` block at `:99-100`):

```xml
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
    <key>SUAllowsAutomaticUpdates</key>
    <true/>
```

- [ ] **Step 2: Inject the env-driven Sparkle keys after the icon section**

Add this block **after the icon-compile section** (which ends with `fi` near `:127`) and **immediately before** the signing block you replace in Step 3 — so the file order stays monotonic (heredoc → `2b` icon → `2c` keys → `3` embed). PlistBuddy only needs `Info.plist`, which already exists from the heredoc:

```bash
# ---------------------------------------------------------------------------
# 2c. Sparkle feed URL + public key are injected from the environment so no
#     secrets are committed. Omitted when unset (dev builds; pre-rollout CI).
# ---------------------------------------------------------------------------
PLIST="$CONTENTS/Info.plist"
if [[ -n "${SPARKLE_FEED_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string ${SPARKLE_FEED_URL}" "$PLIST"
  echo "==> Set SUFeedURL"
fi
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${SPARKLE_PUBLIC_ED_KEY}" "$PLIST"
  echo "==> Set SUPublicEDKey"
fi
```

- [ ] **Step 3: Replace the signing block with embed + inside-out signing**

Replace the entire current section 3+4 (`make-app.sh:129-148`, from the `# 3. Code signing` comment through the closing `fi` of the verify block) with:

```bash
# ---------------------------------------------------------------------------
# 3. Embed Sparkle.framework (auto-update). SPM leaves it in the artifacts dir;
#    it does NOT embed it for us. Discover the path (it varies by SPM version)
#    rather than hardcoding it.
# ---------------------------------------------------------------------------
SPARKLE_FW="$(find .build/artifacts -name 'Sparkle.framework' -maxdepth 6 2>/dev/null | head -1)"
if [[ -z "$SPARKLE_FW" ]]; then
  echo "ERROR: Sparkle.framework not found under .build/artifacts — run 'swift build' first" >&2
  exit 1
fi
echo "==> Embedding Sparkle.framework from $SPARKLE_FW"
mkdir -p "$CONTENTS/Frameworks"
cp -R "$SPARKLE_FW" "$CONTENTS/Frameworks/"   # cp -R preserves the framework's symlinks
EMBEDDED_FW="$CONTENTS/Frameworks/Sparkle.framework"
FW_VERSION="$EMBEDDED_FW/Versions/Current"    # symlink → the real version dir (e.g. B)

# ---------------------------------------------------------------------------
# 4. Code sign INSIDE-OUT (no --deep). --deep corrupts the nested XPC service and
#    helper signatures. Sign the framework's components first, then the framework,
#    then the outer app last. Identity defaults to ad-hoc; set HUBBER_SIGN_IDENTITY
#    to the stable self-signed cert for release/verification (ad-hoc trips Sparkle's
#    Library Validation). No --options runtime (that requires notarization).
# ---------------------------------------------------------------------------
SIGN_IDENTITY="${HUBBER_SIGN_IDENTITY:--}"
echo "==> Code signing $APP inside-out (identity: $SIGN_IDENTITY)"

# XPC services (present even for non-sandboxed apps; sign each individually).
if [[ -d "$FW_VERSION/XPCServices" ]]; then
  for xpc in "$FW_VERSION/XPCServices/"*.xpc; do
    [[ -e "$xpc" ]] || continue
    codesign --force --sign "$SIGN_IDENTITY" "$xpc"
  done
fi

# Helper tools inside the framework.
codesign --force --sign "$SIGN_IDENTITY" "$FW_VERSION/Autoupdate"
codesign --force --sign "$SIGN_IDENTITY" "$FW_VERSION/Updater.app"

# The framework itself.
codesign --force --sign "$SIGN_IDENTITY" "$EMBEDDED_FW"

# Finally the outer app (NOT --deep).
codesign --force --sign "$SIGN_IDENTITY" "$APP"

# ---------------------------------------------------------------------------
# 5. Verify the whole nested structure.
# ---------------------------------------------------------------------------
echo "==> Verifying signature"
if ! codesign --verify --deep --strict --verbose=2 "$APP" 2>&1; then
  echo "ERROR: codesign --verify failed for $APP" >&2
  exit 1
fi
```

> **Fallback note (only if Step 6 verify fails on `Updater.app`):** some Sparkle releases nest signed helpers inside `Updater.app`. If `--verify --deep --strict` reports a seal problem there, sign its inner executable first (`codesign --force --sign "$SIGN_IDENTITY" "$FW_VERSION/Updater.app/Contents/MacOS/"*`) before re-signing `Updater.app`. Re-run the build after editing.

- [ ] **Step 4: Build the signed app with the self-signed identity**

Run: `HUBBER_SIGN_IDENTITY="Hubber Self-Signed" make app`
Expected: ends with `==> Hubber.app built successfully`, having printed `Embedding Sparkle.framework…`, `Set …` lines, and no codesign errors.

- [ ] **Step 5: Verify the embed, the keys, and the signature**

```bash
test -d Hubber.app/Contents/Frameworks/Sparkle.framework && echo "framework: OK"
/usr/libexec/PlistBuddy -c "Print :SUEnableAutomaticChecks" Hubber.app/Contents/Info.plist   # → true
codesign --verify --deep --strict --verbose=2 Hubber.app                                      # → "valid on disk" / "satisfies its Designated Requirement"
```
Expected: `framework: OK`, `true`, and a passing verify with no nested-seal errors. (SUFeedURL/SUPublicEDKey are intentionally absent here — env vars unset.)

- [ ] **Step 6: Launch-check (Library Validation: does the framework load?)**

```bash
open Hubber.app && sleep 3 && pgrep -xl Hubber && osascript -e 'quit app "Hubber"'
```
Expected: `pgrep` prints a PID — the app launched and stayed alive, i.e. `Sparkle.framework` loaded with no Library Validation crash. Manually click the menu-bar icon → right-click → confirm **"Check for Updates…"** is present and, when clicked, opens Sparkle's standard updater window (it will report it can't check — no feed configured — which proves the wiring).

- [ ] **Step 7: Dev-build smoke check (ad-hoc still launches)**

```bash
make app-dev && open Hubber.app && sleep 3 && pgrep -xl Hubber && osascript -e 'quit app "Hubber"'
```
Expected: a PID prints — the ad-hoc debug build embeds Sparkle and still launches (no Hardened Runtime ⇒ Library Validation not enforced). If this crashes on launch, gate the embed behind `[[ "$CONFIG" != "debug" ]]` and note it; otherwise leave embed unconditional.

- [ ] **Step 8: Commit**

```bash
git add Scripts/make-app.sh
git commit -m "build: embed Sparkle.framework and sign the app inside-out

Refs #51"
```

---

### Task 4: Thread the release version into the build

**Files:**
- Modify: `.github/workflows/release.yml` (`:38-39`)

**Interfaces:**
- Consumes: `make-app.sh`'s existing `VERSION` arg handling (`$1` → Info.plist `CFBundleShortVersionString`/`CFBundleVersion`).
- Produces: release builds whose bundle version equals the git tag (minus the leading `v`) — required so Sparkle can compare versions across releases.

- [ ] **Step 1: Pass the tag version to `make dist`**

In `.github/workflows/release.yml`, replace the step at `:38-39`:

```yaml
      - name: Assemble Hubber.app and package artifacts
        run: make dist
```

with:

```yaml
      - name: Assemble Hubber.app and package artifacts
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          echo "Building release version $VERSION"
          make dist VERSION="$VERSION"
```

(On a `v1.2.3` tag, `GITHUB_REF_NAME` is `v1.2.3` → `VERSION=1.2.3`. `workflow_dispatch` on a branch yields the branch name, same as the existing `gh release create` behavior — no new regression.)

- [ ] **Step 2: Verify the mechanism locally (make-app.sh honors VERSION)**

```bash
make app VERSION=9.9.9
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Hubber.app/Contents/Info.plist   # → 9.9.9
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Hubber.app/Contents/Info.plist               # → 9.9.9
```
Expected: both print `9.9.9`, proving the version flows arg → Info.plist (the same path `make dist VERSION=…` uses in CI).

- [ ] **Step 3: Lint the workflow YAML (syntax sanity)**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('yaml OK')"`
Expected: `yaml OK`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: thread the git tag version into the release build

Refs #51"
```

---

### Task 5: Rollout runbook

**Files:**
- Create: `docs/runbooks/sparkle-auto-update.md`

**Interfaces:**
- Consumes: the env-var contract from Task 3 (`SPARKLE_FEED_URL`, `SPARKLE_PUBLIC_ED_KEY`), the version threading from Task 4, the `Hubber Self-Signed` cert.
- Produces: documentation only.

- [ ] **Step 1: Write the runbook**

Create `docs/runbooks/sparkle-auto-update.md` with exactly this content:

````markdown
# Runbook: Sparkle auto-update rollout

Operator guide for turning Hubber's Sparkle auto-update **on**. The app + build
mechanism ships with the code+build PR for [#51]; this runbook is the procedure to
make auto-update actually live. Run sections 1–3 once; repeat sections 4–5 per
release. This is the work that finally closes [#51]. Notarization (no Gatekeeper
prompt on first install) is a separate track — epic #79 (M4b), blocked on a paid
Apple Developer account.

**Project specifics**
- Repo: `osuritz/hubber`
- Bundle id: `com.osuritz.hubber`
- Signing identity: `Hubber Self-Signed` (login keychain; **expires 2027-06-16**)
- `Scripts/make-app.sh` reads `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY` from the
  environment and writes them into `Info.plist` (omitted when unset).

## 1. One-time: generate the EdDSA keypair

Sparkle's CLI tools ship inside the resolved SPM artifact.

```bash
swift build   # ensure the artifact exists
SPARKLE_BIN="$(find .build/artifacts -name 'generate_keys' | head -1)"
"$SPARKLE_BIN" -p > sparkle_public_key.txt   # prints the base64 public key
```

- The **private key** is stored automatically in your login Keychain as
  "Private key for signing Sparkle updates". Back it up securely (see §7).
- The contents of `sparkle_public_key.txt` is the value for `SPARKLE_PUBLIC_ED_KEY`.

Export the private key for CI and store it as a GitHub Actions secret:

```bash
"$SPARKLE_BIN" -x sparkle_private_key.pem
gh secret set SPARKLE_PRIVATE_KEY < sparkle_private_key.pem
rm -f sparkle_private_key.pem            # do not commit; delete after upload
```

Also store the public key as a (non-secret) Actions variable so the release build can
inject it:

```bash
gh variable set SPARKLE_PUBLIC_ED_KEY < sparkle_public_key.txt
```

## 2. One-time: choose appcast hosting + set SUFeedURL

**Decision:** GitHub Pages (recommended — free, stable URL, version-controlled) vs. a
GitHub Releases raw asset. Record the choice here when made.

For GitHub Pages serving `appcast.xml` from the `/docs` folder on the default branch
(or a `gh-pages` branch), the feed URL is:

```
https://osuritz.github.io/hubber/appcast.xml
```

Store it as an Actions variable:

```bash
gh variable set SPARKLE_FEED_URL --body "https://osuritz.github.io/hubber/appcast.xml"
```

The URL must remain stable forever — every shipped build embeds it, and Sparkle will
only ever check the URL baked into the running app.

## 3. One-time: signing cert in CI

Release builds must use the stable `Hubber Self-Signed` identity (ad-hoc trips
Sparkle's Library Validation). Export it and import it in CI.

```bash
# Export cert + private key as a password-protected .p12:
security export -k login.keychain-db -t identities -f pkcs12 \
  -P "$P12_PASSWORD" -o hubber-signing.p12   # use a strong, throwaway password

base64 -i hubber-signing.p12 | gh secret set HUBBER_SIGNING_P12
gh secret set HUBBER_SIGNING_P12_PASSWORD --body "$P12_PASSWORD"
rm -f hubber-signing.p12
```

In `.github/workflows/release.yml`, before the build step, import into a temporary
keychain and export `HUBBER_SIGN_IDENTITY`:

```yaml
      - name: Import signing certificate
        env:
          P12_B64: ${{ secrets.HUBBER_SIGNING_P12 }}
          P12_PASSWORD: ${{ secrets.HUBBER_SIGNING_P12_PASSWORD }}
        run: |
          KEYCHAIN="$RUNNER_TEMP/hubber.keychain-db"
          security create-keychain -p "" "$KEYCHAIN"
          security set-keychain-settings "$KEYCHAIN"
          security unlock-keychain -p "" "$KEYCHAIN"
          echo "$P12_B64" | base64 --decode > "$RUNNER_TEMP/cert.p12"
          security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" \
            -P "$P12_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -k "" "$KEYCHAIN"
          security list-keychains -d user -s "$KEYCHAIN" login.keychain-db
          rm -f "$RUNNER_TEMP/cert.p12"
          echo "HUBBER_SIGN_IDENTITY=Hubber Self-Signed" >> "$GITHUB_ENV"
```

Pass the Sparkle env vars into the build step:

```yaml
      - name: Assemble Hubber.app and package artifacts
        env:
          SPARKLE_FEED_URL: ${{ vars.SPARKLE_FEED_URL }}
          SPARKLE_PUBLIC_ED_KEY: ${{ vars.SPARKLE_PUBLIC_ED_KEY }}
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          make dist VERSION="$VERSION"
```

## 4. Per-release: build, sign, package, generate the appcast

The release workflow already builds, signs, and packages `dist/Hubber.zip` +
`dist/Hubber.dmg`. Add appcast generation after packaging:

```yaml
      - name: Generate appcast
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          SPARKLE_BIN="$(find .build/artifacts -name 'generate_appcast' | head -1)"
          echo "$SPARKLE_PRIVATE_KEY" > "$RUNNER_TEMP/sparkle_key.pem"
          mkdir -p release-archives && cp dist/Hubber.zip release-archives/
          "$SPARKLE_BIN" \
            --ed-key-file "$RUNNER_TEMP/sparkle_key.pem" \
            --download-url-prefix "https://github.com/osuritz/hubber/releases/download/${GITHUB_REF_NAME}/" \
            --link "https://github.com/osuritz/hubber" \
            -o docs/appcast.xml \
            release-archives/
          rm -f "$RUNNER_TEMP/sparkle_key.pem"
```

`generate_appcast` reads the version from each archive's embedded `Info.plist` and
writes `sparkle:edSignature` for every item. Delta updates are out of scope for v1.

## 5. Per-release: publish

1. Commit the regenerated `docs/appcast.xml` (Pages serves it) — or push to `gh-pages`.
2. The existing `gh release create` step uploads `dist/Hubber.zip` + `dist/Hubber.dmg`
   and tags the release.
3. Running instances check the feed on schedule, verify the EdDSA signature, download,
   and install in place.

## 6. Acceptance tests (issue #51 criteria)

- [ ] A running build N detects N+1 from the appcast, verifies the signature, installs,
      and relaunches with **no Gatekeeper prompt** (in-place update strips quarantine).
- [ ] "Check for Updates…" opens Sparkle's standard update UI.
- [ ] An appcast entry with a **wrong EdDSA signature** is rejected (update refused).
- [ ] A `SUPublicEDKey` mismatch between the running app and an update is rejected with a
      clear error (not a silent failure).
- [ ] On a fresh macOS 14+ machine, install via DMG/zip then auto-update → no new
      Gatekeeper dialog for the updated version.

## 7. Key rotation, recovery, cert expiry

- **Back up the EdDSA private key.** If it's lost, existing users cannot auto-update and
  must reinstall manually — there is no recovery path.
- **Cert expiry:** `Hubber Self-Signed` expires **2027-06-16**. Renew/replace before then
  and keep the same identity name so Keychain ACLs (stored tokens) stay continuous.
- **Public-key rotation** requires shipping a build whose `Info.plist` lists both the old
  and new keys (`SUPublicEDKeys`) before retiring the old one.

[#51]: https://github.com/osuritz/hubber/issues/51
````

- [ ] **Step 2: Verify it renders and contains every section**

```bash
test -f docs/runbooks/sparkle-auto-update.md && \
grep -c '^## ' docs/runbooks/sparkle-auto-update.md   # → 7
```
Expected: the file exists and prints `7` (sections 1–7).

- [ ] **Step 3: Commit**

```bash
git add docs/runbooks/sparkle-auto-update.md
git commit -m "docs: add Sparkle auto-update rollout runbook

Refs #51"
```

---

## Final verification (before opening the PR)

- [ ] `make ci` is green.
- [ ] `HUBBER_SIGN_IDENTITY="Hubber Self-Signed" make app` → app launches, "Check for Updates…" opens Sparkle's UI, `codesign --verify --deep --strict Hubber.app` passes.
- [ ] `make app-dev` launches (ad-hoc + Sparkle).
- [ ] Working tree clean except the intended changes; branch pushed; PR body summarizes the change and ends with `Refs #51`.
- [ ] Watch the PR's CI to green before merging (locally-green ≠ CI-green).
