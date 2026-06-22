# PR Widget — Design

**Date:** 2026-06-22 · **Scope:** A configurable macOS (Tahoe 26) WidgetKit widget that
surfaces one PR list — Incoming (Reviews), Outgoing, or Drafts — on the desktop and in
Notification Center, echoing the app's row design. Each instance is configured independently
(list × connection × attention-filter × sort). Rows open the PR in the browser; the header
opens Hubber. **Delivery:** phased. **Build:** a thin XcodeGen/`xcodebuild` target for the
`.appex` (**Approach C**) — Phase 0 **ruled out** the pure-SPM Approach A (see Phase 0 Outcome
below). **Distribution:** developed/tested locally with a **free Apple ID Personal Team** cert;
ships to users only once the app is signed/notarized (Apple Developer account / M4b).

## Phase 0 — Outcome (RESOLVED 2026-06-22)

The de-risking spike (§8) is complete. Findings, verified on this machine under a **free Apple
ID "Personal Team"** `Apple Development` certificate (Team ID present):

- **Build approach = C (Xcode-built appex).** Approach A (pure-SPM hand-assembled `.appex`) is
  **ruled out**: a `swift build`-linked widget binary lacks the `NSExtensionMain` entry point real
  app-extensions have, so PlugInKit (`pkd`) never registers it — confirmed by *even a trivial
  static widget* failing discovery regardless of signing/metadata/entitlements. Xcode's
  app-extension build produces the correct binary; an Xcode-built widget **is** discovered.
- **Free signing is sufficient for local dev** (no paid account). One-time fix: the cert chain was
  broken (`errSecInternalComponent`, "unable to build chain to self-signed root") until the **Apple
  WWDR G3** intermediate was installed (`security import AppleWWDRCAG3.cer`). After that, `codesign`
  embeds a real `TeamIdentifier` and the bundle passes `--verify --deep --strict`.
- **The widget extension MUST carry `com.apple.security.app-sandbox = YES`** (alongside
  `application-groups`). Without `app-sandbox`, `lsregister` registers the bundle but `pluginkit`
  **silently ignores it** — a non-obvious requirement that compounded the Approach-A failure.
- **App Groups provision under the free Personal Team** via Xcode automatic signing
  (`DEVELOPMENT_TEAM=<id> CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates`) — no "Personal teams
  don't support App Groups" error. Both host and sandboxed widget receive the signed
  `application-groups` entitlement.
- **Verified end-to-end (free team):** Xcode-built widget is **discovered** (`pluginkit -m`),
  appears in the gallery, **renders** on the desktop, and the **sandboxed widget resolves the App
  Group container** (`containerURL` non-nil).

**Still to confirm in the real build (not a blocker):** the file **round-trip** — a non-sandboxed
(but entitled) host writing the snapshot, then the sandboxed widget reading it. The spike could not
confirm this cleanly: the throwaway host had an AppKit delegate-wiring bug that prevented a reliable
*entitled* write, and an *unentitled* `printf` write was (correctly) sandbox-denied — not
representative of the real host. This is the standard non-sandboxed-app + sandboxed-widget sharing
pattern, so it's **expected to work**; it will be validated in Phase 1b/2 with the real, properly
signed host. **Fallback if raw container files prove finicky across the sandbox boundary:**
`UserDefaults(suiteName: "group.com.osuritz.hubber")` or `NSFileCoordinator` (both route through
`cfprefsd`/file coordination, which handle cross-process/cross-sandbox sharing). This supersedes
§4's "single JSON file" decision if needed.

Detailed gate-by-gate evidence: `docs/superpowers/SPIKE-RESULTS.md` (Approach A) and
`docs/superpowers/SPIKE-C-RESULTS.md` (Approach C).

## 1. Goal & motivation

Hubber today surfaces PRs only through the menu-bar popover, which requires a click and is
gone the moment it closes. A widget gives an always-visible, glanceable surface for "what
needs me right now" on the desktop and in Notification Center, without opening the app. The
widget is configurable so one person can pin, say, a "Reviews · needs-attention" instance next
to an "Outgoing · failing-CI" instance.

**Non-goals:** Small and Lock-screen widget families; interactive refresh buttons/intents; any
widget-side networking; live remote avatars; notarized/Apple-account distribution (separately
gated by M4b).

## 2. The load-bearing constraints

- **Separate sandboxed process.** A WidgetKit widget is an `.appex` extension that runs in its
  own sandboxed process. It **cannot** read `HubberStore`'s in-memory `HubberData`. All data
  reaches it through a shared **App Group** container. The widget **never** touches the network.
- **App Group requires entitlements + signing — and may be unavailable under ad-hoc signing.**
  `com.apple.security.application-groups` must be present on both the host and the widget, both
  code-signed with it. Reliable end-user distribution requires a properly signed app (Apple
  Developer account) — an accepted, known gate. The sharper, nearer risk is **local development**:
  a non-sandboxed, ad-hoc-signed binary carrying only the app-groups entitlement may get `nil`
  back from `containerURL(forSecurityApplicationGroupIdentifier:)` (no Team ID / provisioning). If
  that holds, the feature **cannot be developed or tested locally at all**, regardless of build
  approach (A or C). Phase 0 (§8, Gate 1) proves or kills this **first**, before any other work.
- **Host sandbox decision.** App Groups are entitlement/sandbox-sensitive. The host is currently
  **non-sandboxed** (Keychain, file token store, Sparkle, launch-at-login, Application Support).
  The design's default is to keep it non-sandboxed and confirm group-container access works that
  way in §8. Adding `com.apple.security.app-sandbox` to the host is a **last resort** with a large
  blast radius — it would touch Sparkle, the token stores, launch-at-login, and existing file
  paths. If §8 shows the container is usable *only* when the host is sandboxed, that trade-off is
  re-evaluated with the user before proceeding; it may defer the feature under the unsigned model.
- **Pure-SPM repo, hand-assembled bundle.** The repo is a SwiftPM executable; `Scripts/make-app.sh`
  hand-assembles and inside-out-signs the `.app` (including embedding `Sparkle.framework`) with no
  Xcode project. The widget must fit this model — see §8/§9.
- **No persistence today.** `HubberStore` holds the PR lists in memory only. The snapshot store in
  §4 is net-new.

## 3. Architecture overview

Strictly **host-writes / widget-reads**:

```
HubberStore (per-connection aggregate)  ──maps live models──▶  WidgetSnapshot (Codable DTOs)
        │                                                          │
        │                                        WidgetSnapshotStore.write(atomic JSON)
        │                                                          ▼
        └── WidgetCenter.reloadTimelines(ofKind:) ───▶  App Group container
                                                       group.com.osuritz.hubber
                                                                   │
                      Widget TimelineProvider ◀── WidgetSnapshotStore.read() ── (no network)
                                       │
                            apply instance config (list/connection/filter/sort) → render
```

### 3a. `HubberKit` — new shared SPM library target

Everything the widget and app must share moves into a new library target `HubberKit`, which both
the `Hubber` executable and the widget target depend on. This is a real refactor and the **first
build step**. It contains only what the widget needs — not the whole app:

- **Snapshot DTOs** (§4): Codable value types for the rows + meta + connection list.
- **Status-presentation logic**: the derivations that turn a PR's state into a CI **rail** color,
  a review **verdict pill**, an **SLO age** band, and the **size +/-** indicator. Where the app
  already has this (e.g. `ReviewSLOPresentation`, the CI-rail + review-verdict-pill row indicator
  shipped in PR #122, `MenubarPresentation`/`TabBadgePresentation`), it is **moved**
  into `HubberKit` and reused by both — not duplicated.
- **Design tokens / colors** (`HubberColors` and the token set) so app and widget render identically.
- **`WidgetSnapshotStore`**: the App Group read/write seam. Named to avoid colliding with the
  **existing** `Sources/Hubber/Notifications/SnapshotStore.swift`, which is unrelated
  per-connection notification state.

Extraction is mechanical but touches many files (current code is one monolithic `Hubber`
executable target). The plan must sequence it so the app keeps building/testing green at each
step before the widget target is added.

### 3b. App Group + `WidgetSnapshotStore`

- **Group id:** `group.com.osuritz.hubber` (host bundle id is `com.osuritz.hubber`). Treated as
  **provisional** — the final identifier may be constrained by the Apple Developer team / app-group
  registration once the app is signed, so it lives behind a single constant and is **not** baked
  into tests or the on-disk schema in a way that's painful to change later.
- **Availability is gated by §8.** The container path comes from
  `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`, which §8 Gate 1 proves
  returns a usable, shared, non-`nil` path under the planned local signing **before** this seam is
  built upon.
- **Storage:** a single JSON file written **atomically** into the group container. One file, not
  three — the widget reads the whole snapshot and selects its list. (UserDefaults(suiteName:) is
  rejected: the lists are unbounded and JSON-on-disk is cleaner for the row arrays.)
- **Write trigger + merge semantics.** Refresh aggregates **per connection** and can **partially
  fail** (one connection errors while others succeed). So the host does **not** blindly overwrite
  on "refresh finished". Instead the snapshot is rebuilt from the store's current **aggregated**
  state whenever that state changes: successful connections contribute fresh rows; failed/stale
  connections keep their **last-known** rows (never silently collapsed to empty). On **sign-out /
  no connections**, the host writes an explicit signed-out/empty snapshot. Every write is followed
  by a timeline reload.
- **Reload:** `WidgetCenter.shared.reloadTimelines(ofKind:)` for the widget's kind. Reloads are
  system-coalesced, so the widget's stale-state rendering (§11) — not the reload call — is the
  correctness backstop.
- **Read path:** the widget's `TimelineProvider` reads the file, applies the instance's config, and
  renders. No fetching, ever.

## 4. Snapshot schema

A single Codable `WidgetSnapshot` (versioned with a `schemaVersion` int for forward-compat):

- `meta`: `lastUpdated: Date`, `isSignedIn: Bool`.
- `connections: [ConnectionSummary]` — `{ id, displayName }`, the lightweight list the widget's
  config picker needs **without the app running** (see §5 connection query).
- `incoming / outgoing / drafts: [PRRowSnapshot]`, each carrying exactly the fields the widget
  renders and filters/sorts on:
  - identity: `id`, `connectionID`, `repo`, `number`, `title`, `url` (the PR's `https://` link)
  - status: `ciState` (passing/failing/running/pending/noChecks), `verdict`/reviewer-summary enum,
    `sloAgeHours` (or `updatedAgoHours` for outgoing/drafts), `additions`/`deletions`/`files`
  - `needsAttention: Bool` — precomputed by the host from the same rule the app uses (past-SLO /
    failing CI / changes-requested), so the widget's attention filter is a pure predicate.

DTOs are intentionally **separate from the live `Models.swift` types** (which embed SwiftUI `Color`
and aren't Codable). The host owns the live→DTO mapping; the widget owns DTO→view.

## 5. Widget configuration (`AppIntentConfiguration`)

A `ConfigurationAppIntent` with four parameters (all four chosen):

- **list** — `AppEnum`: Incoming (Reviews) / Outgoing / Drafts. Default Incoming.
- **connection** — `AppEntity` + `EntityQuery` backed by `snapshot.connections`, plus a synthetic
  **"All"** entry that aggregates across connections. The query reads the snapshot file so the
  picker populates even when the app isn't running.
- **attentionOnly** — `Bool`. When true the widget shows only rows with `needsAttention == true`.
- **sort** — `AppEnum`: Urgency (SLO clock — default for Incoming) / Recently updated (default for
  Outgoing & Drafts) / PR size.

## 6. Layouts — Medium, Large, Extra Large

Shared anatomy: a **header** over a fixed-length **row list** with a `+N more` overflow line. No
scrolling (WidgetKit can't scroll); the widget shows the top-N after filter+sort and summarizes
the rest.

- **Header:** `list name · connection · count` (e.g. "Reviews · Acme · 7"), with the attention
  state reflected in the count styling. The whole header is a tap target → opens Hubber (§7).
- **Row (echoes the app's CI-rail + verdict-pill indicator):** leading **CI status rail**;
  `repo #number` as secondary text; **title** on one truncated line; trailing **verdict pill** or
  **SLO age + size +/-** depending on list. **No live avatars** — the rail+pill change already
  retired reviewer avatars, so nothing remote needs loading.
- **Row counts:** Medium ≈ 3 rows · Large ≈ 6–8 rows · Extra Large ≈ 12+ rows (two-column on the
  wide macOS size). Exact counts are tuned to the rendered height during implementation.

On macOS 26 the widget adopts the system Liquid Glass widget background; pre-26 falls back to the
standard widget material. (The app already branches on `#available(macOS 26, *)` — the widget
reuses the same tokens.)

## 7. Interaction

- **Row → PR:** each row is a SwiftUI `Link(destination: prURL)` opening the PR's `https://` URL in
  the browser. No URL scheme needed.
- **Header → app:** a `Link` to a new **`hubber://open`** URL scheme, registered via `CFBundleURLTypes`
  in the host Info.plist and handled in `main.swift` to bring up the popover.

## 8. Phase 0 — de-risking spike (the real go/no-go)

> **RESOLVED 2026-06-22 → Approach C.** See the "Phase 0 — Outcome" section above for what the
> spike actually found. The original plan below is retained for context.

The spike is **not** "can a static widget render?" — that would pass while the actual design still
fails. It must prove the **exact** signing + configurable-AppIntents + App-Group model works under
the planned local signing. Build a throwaway but **representative** widget:

1. Add a minimal widget SPM target with a **configurable** widget — `AppIntentConfiguration` plus a
   real `AppEntity` + `EntityQuery` that reads the App Group snapshot file — **not** a
   `StaticConfiguration`. (Rationale: `AppIntentConfiguration` depends on App Intents metadata
   extraction, which Xcode runs via `appintentsmetadataprocessor`; `swift build` does **not** run
   that step automatically. A static-only spike would hide this failure mode entirely.)
2. Hand-assemble the `.appex` with the **full** Xcode-equivalent bundle shape (see §9), signed with
   the exact local identity dev will use (ad-hoc or self-signed) carrying
   `com.apple.security.application-groups`; embed in `Hubber.app/Contents/PlugIns/`. The host also
   carries the app-groups entitlement.

Then verify the four gates **in this order** — each is independently decisive:

- **Gate 1 — App Group container (most likely to fail).** Both host and widget get a non-`nil`,
  shared `containerURL`, and the widget reads a value the host wrote. Confirm this holds with the
  host **non-sandboxed** (preferred); only if it doesn't, test whether sandboxing the host fixes it
  (§2 host-sandbox decision).
- **Gate 2 — AppIntents metadata.** The configurable widget's intent / `EntityQuery` actually
  surfaces in the widget's edit/configuration UI — proving the metadata pipeline produced usable
  output outside Xcode.
- **Gate 3 — Discovery.** The widget is registered and offered by the system, verified with
  `pluginkit -m -A` (not just eyeballing the gallery) under the **exact** local signing mode that
  day-to-day development will use.
- **Gate 4 — Render.** A timeline entry renders.

**Failure handling — disaggregated, because the fallback differs by failure type:**

- **Build-product failure** (can't produce a valid `.appex` from `swift build` — wrong Mach-O type,
  missing AppIntents metadata, link/entry issues) → fall back to **Approach C**: a thin XcodeGen
  `project.yml` defining only the widget extension target (consuming `HubberKit` as a local
  package), built via `xcodebuild`, embedded by `make-app.sh`. C fixes Xcode-only **build mechanics**.
- **Signing / discovery / App-Group failure** (Gate 1 or Gate 3 fails for *signing* reasons — e.g.
  the container only materializes under a real Team ID, or the system refuses an ad-hoc extension)
  → **C does not help.** This is an Apple-Developer-account / provisioning question, not a build
  one. Surface it to the user as a go/no-go on the feature under the current unsigned model: the
  honest outcome may be **"defer until the app is signed"** rather than "switch build tools".

Everything in §3–§7 and §10 is identical under A or C; only the appex's build/sign mechanics differ.

## 9. Build / CI integration

> **RESOLVED 2026-06-22 → Approach C.** The widget `.appex` is built by **XcodeGen + `xcodebuild`**
> (the Approach-A hand-assembly bullets below are obsolete and kept only for context). The widget
> extension entitlements MUST include **both** `application-groups` **and**
> `com.apple.security.app-sandbox`. `make-app.sh` will `xcodebuild` the appex (consuming `HubberKit`)
> and embed + inside-out-sign it into `Contents/PlugIns/`. Working reference: `spike-c/project.yml`.

- **Targets:** new `HubberKit` library; `Hubber` executable depends on it; the widget target depends
  on it. The widget target is built only by `make app` (Approach A) or the XcodeGen step (Approach
  C), plus a dedicated `make widget-spike` for Phase 0 — **not** by default `swift build` / unit CI
  (see CI bullet).
- **`.appex` bundle shape (Approach A).** Hand-assembling the appex requires the full
  Xcode-equivalent layout, not just `NSExtensionPointIdentifier`:
  - `Contents/Info.plist`: `CFBundlePackageType = XPC!`, a **unique** `CFBundleIdentifier`
    (`com.osuritz.hubber.widget`), `CFBundleExecutable`, `CFBundleShortVersionString` /
    `CFBundleVersion` matching the host, `LSMinimumSystemVersion`, `CFBundleSupportedPlatforms =
    [MacOSX]`, and the `NSExtension` dict (`NSExtensionPointIdentifier = com.apple.widgetkit-extension`).
  - The binary is a Mach-O **executable** (`@main WidgetBundle`) at `Contents/MacOS/<exec>` — note
    Codex confirmed system widgets are `EXECUTE`, not `MH_BUNDLE`, so an SPM executable target is
    plausible — with correct runpaths only if it links shared frameworks (`HubberKit` is statically
    linked, so likely none).
  - Its own `.entitlements` (app-groups) passed to `codesign --entitlements`.
- **Universal + inside-out signing.** Release host builds are universal (`arm64` + `x86_64`); the
  `.appex` binary must be **lipo'd universal too**, and signed **before** the host app (inside-out,
  no `--deep`), mirroring the existing `Sparkle.framework` flow. Embed under `Contents/PlugIns/`.
  Add the `hubber://` URL scheme (`CFBundleURLTypes`) + app-groups entitlement to the **host**.
- **Verification in `make-app.sh`.** After assembly, assert: `lipo -info` (two arches), `file` /
  `otool -hv` (Mach-O executable, both slices), and `codesign -d --entitlements :-` (app-groups
  present on **both** host and appex), in addition to the existing `codesign --verify --deep --strict`.
- **CI scope.** Unit CI runs `swift build/test/lint` on the pinned `macos-26` runner and continues
  to build **only** the library + executable + tests — the widget target is excluded from the
  default build-product set so CI never depends on the WidgetKit / AppIntents extension pipeline.
  The appex assembly lives in `make app` (distribution), exercised manually + in the §10 matrix.
  (Locally-green is not CI-green until the PR's CI passes on the runner.)

## 10. Testing

- **SPM unit tests (`HubberKit` / `HubberTests`)** — run in CI as today:
  - `WidgetSnapshot` encode/decode round-trip (incl. `schemaVersion`).
  - live `HubberData` → snapshot-DTO mapping (field-by-field, incl. `needsAttention`).
  - attention-filter predicate + each sort order.
  - staleness computation (lastUpdated vs threshold).
  - connection-list persistence + the config `EntityQuery` selecting from it.
- **Widget views** — render-tested with sample snapshots (SwiftUI previews + optional snapshot
  tests); covers each size × each state.
- **Manual verification matrix** — the Phase 0 four-gate checklist, then a locally-signed install
  exercising each size (Medium/Large/XL) × each config axis (list/connection/attentionOnly/sort) ×
  each state (§11), plus the two interactions: a **row tap** opens the PR in the browser, and the
  **header tap** (`hubber://open`) launches/raises Hubber and shows the popover.

## 11. States

All driven by the snapshot — no network:

- **Signed-out** (`meta.isSignedIn == false`): "Open Hubber to sign in" CTA (header → app).
- **Empty** (list empty after filter): list-specific copy — "You're all caught up" (Incoming) /
  "No outgoing PRs" / "No drafts".
- **Stale** (`now − lastUpdated >` threshold, e.g. app not running): dimmed content + a relative
  "updated Nm ago" timestamp.
- **Placeholder**: a neutral redacted preview for the gallery.

## 12. Phasing

- **Phase 0 — Spike.** §8 four-gate go/no-go (App Group container · AppIntents metadata · discovery
  · render). Decides **A vs C vs defer**.
- **Phase 1 — Shared foundation.** Extract `HubberKit`; define `WidgetSnapshot` + `WidgetSnapshotStore`;
  host writes snapshots + reloads timelines; register `hubber://open` and handle it. App stays green.
- **Phase 2 — Configuration.** Widget target + `ConfigurationAppIntent` (4 axes) + connection
  `EntityQuery`.
- **Phase 3 — Layouts & states.** Medium/Large/XL layouts, the app-echoing row, all §11 states.
- **Phase 4 — Packaging.** `make-app.sh` embeds/signs the appex + entitlements + URL scheme; run the
  manual verification matrix.

## 13. Open questions / risks

- **App Group under local signing is the top risk** (§2/§8). If `containerURL` is `nil` for a
  non-sandboxed ad-hoc/self-signed host+widget, the feature can't be developed or tested locally at
  all. Gate 1 of the spike resolves this first; sandboxing the host to fix it is a last resort with
  a large blast radius (§2).
- **A-vs-C is unresolved until the spike — but C only covers *build* failures** (§8). A
  signing/discovery/App-Group failure is an Apple-account/provisioning question that C doesn't fix;
  the honest fallback there may be "defer until the app is signed", surfaced to the user.
- **`AppIntentConfiguration` outside Xcode** (§5/§8). The App Intents metadata pipeline
  (`appintentsmetadataprocessor`) isn't run by `swift build`; Gate 2 proves the *configurable*
  widget works under Approach A, not just a static one.
- **`HubberKit` extraction blast radius.** Moving presentation/token code out of the monolithic
  target touches many files; sequence it to keep the app green at each step.
- **Partial-refresh correctness** (§3b). Snapshot writes must preserve last-known rows for failed
  connections and never collapse to empty on a partial failure; covered by unit tests (§10).
- **Row-count tuning** per size is empirical (rendered height), settled during Phase 3.
