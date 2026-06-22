# PR Widget — Design

**Date:** 2026-06-22 · **Scope:** A configurable macOS (Tahoe 26) WidgetKit widget that
surfaces one PR list — Incoming (Reviews), Outgoing, or Drafts — on the desktop and in
Notification Center, echoing the app's row design. Each instance is configured independently
(list × connection × attention-filter × sort). Rows open the PR in the browser; the header
opens Hubber. **Delivery:** phased; a de-risking spike gates the build approach. **Build:**
hand-assembled `.appex` staying pure-SPM (Approach A), falling back to a thin XcodeGen target
for just the appex (Approach C) if the spike fails. **Distribution:** developed/tested locally
with self-signed entitlements; ships to users only once the app is signed (Apple account /
M4b) — the same Apple Developer account gate that the currently-unsigned v1 has not yet met.

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
- **App Group requires entitlements + signing.** `com.apple.security.application-groups` must be
  present on both the host and the widget, and both must be code-signed with it. This works with
  ad-hoc signing for **local** development; reliable end-user distribution requires the app to be
  properly signed (Apple Developer account). This work is built and tested locally now and ships
  to users when the app is signed. This is an accepted, known gate — not a blocker for the work.
- **Pure-SPM repo, hand-assembled bundle.** The repo is a SwiftPM executable; `Scripts/make-app.sh`
  hand-assembles and inside-out-signs the `.app` (including embedding `Sparkle.framework`) with no
  Xcode project. The widget must fit this model — see §8/§9.
- **No persistence today.** `HubberStore` holds the PR lists in memory only. The snapshot store in
  §4 is net-new.

## 3. Architecture overview

Strictly **host-writes / widget-reads**:

```
HubberStore.refreshPullRequests()  ──maps live models──▶  WidgetSnapshot (Codable DTOs)
        │                                                          │
        │                                              SnapshotStore.write(atomic JSON)
        │                                                          ▼
        └── WidgetCenter.reloadAllTimelines() ───────▶  App Group container
                                                       group.com.osuritz.hubber
                                                                   │
                            Widget TimelineProvider ◀── SnapshotStore.read() ── (no network)
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
- **`SnapshotStore`**: the App Group read/write seam.

Extraction is mechanical but touches many files (current code is one monolithic `Hubber`
executable target). The plan must sequence it so the app keeps building/testing green at each
step before the widget target is added.

### 3b. App Group + `SnapshotStore`

- **Group id:** `group.com.osuritz.hubber` (host bundle id is `com.osuritz.hubber`).
- **Storage:** a single JSON file written **atomically** into the group container
  (`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`). One file, not three —
  the widget reads the whole snapshot and selects its list. (UserDefaults(suiteName:) is rejected:
  the lists are unbounded and JSON-on-disk is cleaner for the row arrays.)
- **Write trigger:** at the end of every **successful** `refreshPullRequests()`, `HubberStore` maps
  its live `IncomingReview`/`OutgoingReview`/`DraftReview` arrays → snapshot DTOs, writes the file,
  then calls `WidgetCenter.shared.reloadAllTimelines()`.
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

## 8. Phase 0 — de-risking spike (go/no-go for Approach A)

Before committing to the hand-assembled path, prove it works end-to-end with a throwaway
hello-world widget:

1. Add a minimal widget SPM target (`@main WidgetBundle` with one static widget).
2. Hand-assemble a `.appex`: widget `Info.plist` with `NSExtensionPointIdentifier =
   com.apple.widgetkit-extension`, ad-hoc signature, `com.apple.security.application-groups`
   entitlement; embed in `Hubber.app/Contents/PlugIns/`.
3. Install the locally-signed app and verify **all three**:
   - (a) the widget appears in the macOS widget gallery ("Edit Widgets");
   - (b) it renders a static timeline entry;
   - (c) it reads a value the host wrote to the App Group container (proves entitlement/group
     sharing works under ad-hoc signing).

**Success = all three pass → proceed with Approach A.** Any failure → fall back to **Approach C**:
a thin XcodeGen `project.yml` defining only the widget extension target (consuming `HubberKit` as a
local package), built via `xcodebuild` and embedded by `make-app.sh`. Everything in §3–§7 and §10
is identical either way; only the appex's build/sign mechanics differ.

## 9. Build / CI integration

- **Targets:** new `HubberKit` library; `Hubber` executable depends on it; widget target depends on it.
- **`make-app.sh`:** build the widget binary, hand-assemble + inside-out sign the `.appex` (mirroring
  the existing `Sparkle.framework` embed/sign flow — no `--deep`), inject the App Group entitlement
  into the **host** as well, and embed the appex under `Contents/PlugIns/`. Add the `hubber://` URL
  scheme to the host Info.plist.
- **CI is unchanged.** Unit CI runs `swift build/test/lint` on the pinned `macos-26` runner and
  already does **not** build the `.app`; the appex assembly lives in `make app` (distribution),
  exercised manually + in the local verification matrix. (Locally-green is not CI-green until the
  PR's CI passes on the runner.)

## 10. Testing

- **SPM unit tests (`HubberKit` / `HubberTests`)** — run in CI as today:
  - `WidgetSnapshot` encode/decode round-trip (incl. `schemaVersion`).
  - live `HubberData` → snapshot-DTO mapping (field-by-field, incl. `needsAttention`).
  - attention-filter predicate + each sort order.
  - staleness computation (lastUpdated vs threshold).
  - connection-list persistence + the config `EntityQuery` selecting from it.
- **Widget views** — render-tested with sample snapshots (SwiftUI previews + optional snapshot
  tests); covers each size × each state.
- **Manual verification matrix** — the Phase 0 spike checklist, then a locally-signed install
  exercising each size (Medium/Large/XL) × each config axis (list/connection/attentionOnly/sort) ×
  each state (§11).

## 11. States

All driven by the snapshot — no network:

- **Signed-out** (`meta.isSignedIn == false`): "Open Hubber to sign in" CTA (header → app).
- **Empty** (list empty after filter): list-specific copy — "You're all caught up" (Incoming) /
  "No outgoing PRs" / "No drafts".
- **Stale** (`now − lastUpdated >` threshold, e.g. app not running): dimmed content + a relative
  "updated Nm ago" timestamp.
- **Placeholder**: a neutral redacted preview for the gallery.

## 12. Phasing

- **Phase 0 — Spike.** §8 go/no-go for A-vs-C.
- **Phase 1 — Shared foundation.** Extract `HubberKit`; define `WidgetSnapshot` + `SnapshotStore`;
  host writes snapshots + reloads timelines; register `hubber://open` and handle it. App stays green.
- **Phase 2 — Configuration.** Widget target + `ConfigurationAppIntent` (4 axes) + connection
  `EntityQuery`.
- **Phase 3 — Layouts & states.** Medium/Large/XL layouts, the app-echoing row, all §11 states.
- **Phase 4 — Packaging.** `make-app.sh` embeds/signs the appex + entitlements + URL scheme; run the
  manual verification matrix.

## 13. Open questions / risks

- **A-vs-C is unresolved until the spike.** The single biggest technical risk is whether a
  hand-assembled widget appex registers with the system; §8 resolves it before any downstream work.
- **`HubberKit` extraction blast radius.** Moving presentation/token code out of the monolithic
  target touches many files; sequence it to keep the app green at each step.
- **Row-count tuning** per size is empirical (rendered height), settled during Phase 3.
