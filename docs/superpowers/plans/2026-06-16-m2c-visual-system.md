# M2-C — Visual Design System Implementation Plan

> Third of four M2 PRs (A engine ✅ → B badge ✅ → **C visual** → D observability). Branch: `feat/m2-visual` (off merged Stream B; carries the design bundle).

**Goal:** Implement the Claude Design "Direction A" visual system natively in SwiftUI — map design tokens to a single source of truth, apply the SF Pro type scale, and refine every component and the four screens to match the mocks. Also: #19 (Drafts error/loading states), #31 (header provider-switcher seam), and the deferred AvatarCache task-cancellation fix.

**Issues:** #19, #31 (plus the visual polish that the M2 milestone scopes for the design system).

**Design source of truth (read these — do NOT copy JSX structure, recreate natively):**
- `docs/design/github-macos-menu-app/project/tokens.jsx` — exact light/dark hex + type scale (authoritative)
- `primitives.jsx` (pill/badge/avatar primitives), `rows.jsx` (3 row types × densities), `popover.jsx` (chrome/header/tabs/footer), `settings.jsx` (settings sections), `boards.jsx`/`design-canvas.jsx` (full mocks for reference)

**Verification reality:** build + lint + token-resolution unit tests are objective gates. **Pixel fidelity is verified manually by the user** (`swift run Hubber` on their Mac — the menubar popover can't be screenshotted from here). Each task notes what is auto-checked vs. eyeballed.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/Hubber/Design/HubberDesign.swift` | Semantic color tokens (light/dark) from `tokens.jsx` — single source of truth |
| Create | `Sources/Hubber/Design/HubberType.swift` | SF Pro type scale roles (`.title`, `.secondary`, `.sloPill`, `.ciDetail`, `.log`, `.section`, `.footer`) |
| Modify | `Sources/Hubber/HubberColors.swift` | Re-point existing helpers (`sloColor`, fills, strokes) at `HubberDesign`; keep call sites working |
| Modify | `Sources/Hubber/HubberPopoverView.swift` | SLO pill, CI badge, rows, empty/error/loading/all-clear, chrome, header (#31), tab bar, footer |
| Modify | `Sources/Hubber/HubberAvatarView.swift` | 36/24/20pt sizes + reviewer state dot |
| Modify | `Sources/Hubber/GitHub/AvatarCache.swift` | Cancellable in-flight task (deferred from Stream B) |
| Modify | `Sources/Hubber/HubberSettingsView.swift` | Section styling + type scale per `settings.jsx` |
| Modify | `Sources/Hubber/ReauthPromptRow.swift` | Token/type-scale alignment |
| Create | `Tests/HubberTests/HubberDesignTests.swift` | Token light/dark resolution + type-scale presence |

---

## Task 1 — Token foundation (`HubberDesign` + `HubberType`) (TDD where testable)

Create `HubberDesign` as the single source of truth, transcribing `tokens.jsx` PALETTE/T() exactly. Provide each semantic token as a SwiftUI `Color` that resolves light/dark (use a `Color(light:dark:)` helper backed by `NSColor(name:nil){ $0.bestMatch... }` or `Color(nsColor: NSColor(name:nil, dynamicProvider:))`). Cover: SLO green/amber/red (fg/bg/border), CI passing/failing/running/pending, reviewer approved/changes/commented/pending, accent, error, signalTint, signalAccent, materials, text/text2/text3, sep/sepStrong, fill/fillHover, control track/thumb/shadow.

`HubberType`: each role as `(size, weight, design)` → a `Font` (e.g. `.system(size: 13, weight: .medium)`; SLO pill uses `.monospacedDigit`; log uses `.system(.body, design: .monospaced)` at 11; section is 11 semibold uppercase +0.4 tracking).

**Test** (`HubberDesignTests`, light verification): for a representative set of tokens, resolve against `.aqua` and `.darkAqua` `NSAppearance` and assert the two differ (or match the known hex) — proves the light/dark split is wired. Assert every `HubberType` role exists and has the expected point size.

Reconcile `HubberColors.swift`: re-implement `sloColor(_:for:)`, `sloFillOpacity`, fills, strokes in terms of `HubberDesign` so existing call sites keep compiling.

Commit: `feat(design): add HubberDesign tokens and HubberType scale from Claude Design`.

## Task 2 — SLO pill & CI badge components

Refactor the SLO pill (3 states: green/amber/red) and CI badge (4 states: passing/failing/running/pending) in `HubberPopoverView.swift` to use `HubberDesign` tokens + `HubberType`. SLO pill: colored dot + text, ~6pt corner radius (`primitives.jsx`). Every color signal keeps a non-color cue (dot/icon/text). CI badge: passing/failing are the prominent action signals; running is neutral; running animates subtly.

Auto: build/lint. Manual: state appearance vs. `primitives.jsx`. Commit: `feat(ui): SLO pill and CI badge use design tokens (all states)`.

## Task 3 — Avatar component + AvatarCache cancellation

`HubberAvatarView`: support 36pt (row), 24pt (reviewer stack), 20pt (compact) per `primitives.jsx`; circular clip; initials fallback on deterministic pastel; reviewer **state dot** overlay (8pt circle, 1.5pt white border, bottom-right) using reviewer tokens. AvatarCache fix (deferred from Stream B): make the in-flight fetch cancellable — return the `Task` (or expose cancel) from `image(for:)` and cancel it from `AvatarView.task` via `withTaskCancellationHandler`, so a disappeared row doesn't tie up the cache/MainActor.

Auto: build/lint + an AvatarCache test that a cancelled fetch doesn't populate the cache. Commit: `feat(ui): avatar sizes + reviewer state dot; cancellable AvatarCache fetch`.

## Task 4 — Row components (3 types × densities + action-signal treatment)

Recreate per `rows.jsx`: incoming (avatar + #num/title + repo·author + SLO pill), outgoing (CI badge + #num/title + repo·CI detail·threads + reviewer avatar stack with state dots), drafts (dashed-doc icon + #num/title + repo·commits·updated + small CI). Three densities (compact/normal/spacious) with the specified paddings. **Action-signal rows** (failing CI or unresolved>0) get a subtle left-edge accent / tinted background (`signalTint`/`signalAccent`); running CI is neutral.

Auto: build/lint. Manual: density + signal treatment vs. `rows.jsx`. Commit: `feat(ui): row components for all three tabs at compact/normal/spacious`.

## Task 5 — Empty / error / loading / all-clear / reauth states + #19

Align all states to the design (`design-canvas.jsx`/spec): All-clear (green check + copy), error ("Couldn't load … · Last updated …" + Retry), loading (skeleton/placeholder rows), reauth prompt. **#19:** add the Drafts tab error + loading + empty states (Incoming/Outgoing already have them from M1/A) so all three tabs are consistent.

Auto: build/lint. Manual: states vs. mocks. Commit: `feat(ui): unify empty/error/loading/all-clear states; add Drafts error state (#19)`.

## Task 6 — Popover chrome + header seam (#31)

Per `popover.jsx`: fixed 420×540pt, 26pt corner radius, `.popover` vibrancy material (content sits on the blur — no flat opaque bg), no title bar. Header shows `GitHub · @login`; **#31:** reserve a tap-target/layout slot in the header for a future provider switcher (no visible change now, but the layout supports it without redesign). Segmented tab bar (Reviews/Outgoing/Drafts); slim footer (last-refresh + ⌘R) using `HubberType.footer`.

Auto: build/lint. Manual: chrome vs. `popover.jsx`. Commit: `feat(ui): popover chrome, header provider seam (#31), tab bar, footer`.

## Task 7 — Settings screen polish

Per `settings.jsx`: native-feeling section dividers/labels, the type scale, and consistent control styling for all sections (GitHub Account, Incoming Reviews, Outgoing, Appearance, Menubar badge, Developer). Developer section keeps the debug chip + log viewer (`HubberType.log`).

Auto: build/lint. Manual: settings vs. `settings.jsx`. Commit: `feat(ui): settings screen polish to design tokens and type scale`.

---

## Acceptance (whole PR)
- `swift build` clean; `swift test` all pass (Stream B's 110 + token tests); `make lint` 0; `make format` idempotent.
- `HubberDesign`/`HubberType` are the single source of truth; no ad-hoc hex left in views.
- **User performs the visual sign-off** (`swift run Hubber`, compare to the mocks) before squash-merge.
- Open PR `feat/m2-visual` → main, squash-merge after visual sign-off.

## Self-Review Checklist
- [ ] All tokens from `tokens.jsx` mapped with light+dark; views use `HubberDesign`/`HubberType` only
- [ ] SLO pill (3) + CI badge (4) + avatar (3 sizes + state dot) match `primitives.jsx`; non-color cues present
- [ ] 3 row types × 3 densities + action-signal treatment match `rows.jsx`
- [ ] All-clear/error/loading/reauth unified; Drafts error state added (#19)
- [ ] 420×540, 26pt radius, vibrancy; header provider seam (#31); tab bar + footer
- [ ] AvatarCache fetch is cancellable
