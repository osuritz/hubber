# Phase 0 Spike Results

**Date:** 2026-06-22  
**Worktree branch:** feat/pr-widget  
**Swift:** 6.3.2 (swiftlang-6.3.2.1.108)  
**macOS:** 26 (Tahoe)  
**Signing:** ad-hoc (`-`), `TeamIdentifier=not set`

---

## Overall verdict: **APPROACH A PARTIALLY VIABLE; GATE 2 + GATE 3 ARE BLOCKERS**

- Gate 1 (App Group): **PASS** — `containerURL` is non-nil; round-trip write+read works.
- Gate 2 (AppIntents metadata): **FAIL** — `appintentsmetadataprocessor` finds no symbols without `SWIFT_ENABLE_EMIT_CONST_VALUES`. Configurable widget won't work under Approach A without extra tooling.
- Gate 3 (Discovery): **FAIL** — `pluginkit` does not surface ad-hoc-signed widgets (`TeamIdentifier=not set`). The widget IS in lsregister, but the system extension host silently ignores it.
- Gate 4 (Render): **NEEDS-GUI** — Not tested; Gate 3 is a prerequisite. If Gate 3 fails, Gate 4 is moot.

**Go/no-go decision:** Gate 3 failure is a signing/provisioning failure, not a build failure. **Approach C (XcodeGen) does not fix it.** The only fix is a real Apple Developer Team ID. **Defer the full widget until M4b (signed app).** Gate 2 failure maps to Approach C as the build-tooling fix, but it is irrelevant if Gate 3 blocks discovery regardless.

---

## Gate 1 — App Group Container

**Verdict: PASS**

### Command 1: unsigned CLI probe (plain `swift` interpreter, no entitlement)

```
$ swift Scripts/spike-probe.swift --write

=== Hubber Widget Spike — Gate 1 Probe ===
App Group ID: group.com.osuritz.hubber

[PASS] containerURL is NON-NIL: /Users/oliviersuritz/Library/Group Containers/group.com.osuritz.hubber
[PASS] Wrote spike.json to: /Users/oliviersuritz/Library/Group Containers/group.com.osuritz.hubber/spike.json
[PASS] Read back: value='hello-from-probe' writtenAt=1782165657.0506139
```

**Finding:** `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` returns a non-nil path even for an unsigned CLI process (no entitlement, no bundle). The Group Containers directory is just a filesystem path — macOS does NOT enforce entitlement presence for a non-sandboxed process at the `containerURL` lookup level. Write+read round-trip works.

**Caveat (important):** A non-sandboxed host only needs the App Group entitlement for App Store / notarized distribution; locally the path is accessible regardless. The widget process (running sandboxed) will need a real Team ID in the entitlement for system enforcement. Gate 1 PASSES for the host (non-sandboxed dev builds); it is NOT tested for the widget process because Gate 3 blocks the widget from ever running.

**Host entitlements after `make widget-spike.sh`:**
```
$ codesign -d --entitlements :- Hubber.app
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>com.apple.security.application-groups</key>
  <array><string>group.com.osuritz.hubber</string></array>
</dict></plist>
```

**Widget appex entitlements:**
```
$ codesign -d --entitlements :- Hubber.app/Contents/PlugIns/HubberWidgetSpike.appex
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>com.apple.security.application-groups</key>
  <array><string>group.com.osuritz.hubber</string></array>
</dict></plist>
```

---

## Gate 2 — AppIntents Metadata

**Verdict: FAIL**

### Finding A: `swift build` does NOT emit AppIntents metadata

```
$ swift build --target HubberWidgetSpike
Build of target: 'HubberWidgetSpike' complete! (1.53s)

$ find .build -name "*.appintents" -o -name "Metadata.appintents"
(no output — no .appintents files emitted)
```

SPM compiles the Swift module and object file but does not run `appintentsmetadataprocessor`. This is expected — SPM has no concept of Xcode build phases.

### Finding B: Manual `appintentsmetadataprocessor` fails without const-values

The tool is present at:
```
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor
```

Required flags (determined from `--help`):
```
--output --toolchain-dir --module-name --sdk-root --xcode-version
--platform-family --deployment-target --target-triple
--source-file-list --swift-const-vals-list
```

Invocation and output:
```
$ xcrun appintentsmetadataprocessor \
    --output .build/widget-spike-appintents \
    --toolchain-dir $(xcrun --find swiftc | xargs dirname)/.. \
    --module-name HubberWidgetSpike \
    --sdk-root $(xcrun --sdk macosx --show-sdk-path) \
    --xcode-version 16E5267c \
    --platform-family macOS \
    --deployment-target 14.0 \
    --target-triple arm64-apple-macosx14.0 \
    --source-file-list .build/source-files.txt \
    --swift-const-vals-list .build/constvals-list.txt

2026-06-22 15:05:12.967 appintentsmetadataprocessor[69229] Starting appintentsmetadataprocessor export
2026-06-22 15:05:12.968 appintentsmetadataprocessor[69229] warning: No swift const values found. If SWIFT_ENABLE_EMIT_CONST_VALUES = NO, AppIntents metadata cannot be extracted.
2026-06-22 15:05:12.979 appintentsmetadataprocessor[69229] Extracted no relevant App Intents symbols, skipping writing output
Exit: 0
```

### Root cause

`SWIFT_ENABLE_EMIT_CONST_VALUES` is an **Xcode build setting** that instructs the compiler to emit per-file `.swiftconstvalues` files using `-emit-const-values-path`. SPM does not pass this flag. Without `.swiftconstvalues`, `appintentsmetadataprocessor` has nothing to work with and cannot extract `AppIntentConfiguration`, `WidgetConfigurationIntent`, `AppEntity`, or `EntityQuery` metadata.

**Confirmed manually:** `swiftc -emit-const-values-path <path>` produces an empty `[]` file (no values extracted), regardless of source content, unless the Xcode const-extract build infrastructure is running. The flag exists but requires companion `-Xfrontend` flags that Xcode injects during its build system phases — these are not documented and not reproducible outside Xcode's build system.

**Consequence:** `AppIntentConfiguration` will silently produce a widget with no configuration UI. The widget renders, but the picker never populates because there are no registered intents. This is a **build-tooling failure**, not a runtime failure — it matches the spec's "Approach C" failure mode, where XcodeGen is the fix (Xcode builds do run the metadata pipeline).

---

## Gate 3 — Discovery

**Verdict: FAIL (signing blocker)**

### lsregister — PASS (registered but not surfaced)

```
$ /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f Hubber.app

$ /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -dump | grep -A 5 "com.osuritz.hubber.widget"

plugin Identifiers: com.osuritz.hubber.widget
---
identifier: com.osuritz.hubber.widget
version:    0.1 (...)
platform:   native
executable: HubberWidgetSpike
slices:     arm64
Mach-O UUIDs: E445F391-BDFE-345E-835C-A2BECF11D251
---
CFBundleIdentifier = "com.osuritz.hubber.widget";
CFBundleName = HubberWidgetSpike;
CFBundlePackageType = "XPC!";
CFBundleShortVersionString = "0.1.0";
CFBundleSupportedPlatforms = (MacOSX);
NSExtension.NSExtensionPointIdentifier = "com.apple.widgetkit-extension";
```

LaunchServices knows about the widget. The bundle shape is correct: `XPC!` package type, correct extension point identifier, correct Info.plist keys.

### pluginkit — FAIL

```
$ pluginkit -m -A -p com.apple.widgetkit-extension -v | grep -i hubber
(no output)

$ pluginkit -m -i com.osuritz.hubber.widget -v
(no matches)

$ pluginkit -a Hubber.app/Contents/PlugIns/HubberWidgetSpike.appex
(exit 0, but widget still absent from -m query)
```

### Root cause

```
$ codesign -d --verbose=4 Hubber.app/Contents/PlugIns/HubberWidgetSpike.appex

Identifier=com.osuritz.hubber.widget
Format=bundle with Mach-O thin (arm64)
CodeDirectory v=20400 flags=0x2(adhoc) ...
Signature=adhoc
TeamIdentifier=not set          ← THE BLOCKER
```

Compare to Crouton (which IS discovered):
```
$ codesign -d --verbose=4 /Applications/Crouton.app/Contents/PlugIns/Crouton\ WidgetsExtension.appex

Identifier=com.meal.plan.ios.Crouton-Widgets
Authority=Apple Mac OS Application Signing
TeamIdentifier=4MQ7FRMKBM      ← real Team ID
```

`pluginkit` (the system extension host daemon) requires a valid `TeamIdentifier` to surface widget extensions. Ad-hoc signed binaries have `TeamIdentifier=not set` and are silently rejected. This is a **provisioning/Apple-Developer-account failure**, not a build failure.

**This cannot be fixed by Approach C (XcodeGen).** XcodeGen generates an Xcode project that still produces an ad-hoc-signed binary unless a real provisioning profile + Team ID is available. The only fix is signing the app with a real Apple Developer account (M4b gate).

---

## Gate 4 — Render

**Verdict: NEEDS-GUI (blocked by Gate 3)**

Gate 3 failure means the system will not offer the widget in the gallery. Gate 4 cannot be meaningfully tested until Gate 3 passes.

**Manual checklist for when Gate 3 passes (i.e., after M4b signing):**

1. Build `Hubber.app` with `make widget-spike` using a real Developer ID (set `HUBBER_SIGN_IDENTITY`).
2. Verify `pluginkit -m -A -p com.apple.widgetkit-extension -v | grep hubber` shows `com.osuritz.hubber.widget`.
3. Open the widget gallery: right-click desktop → Edit Widgets, or Notification Center → Edit Widgets.
4. Find "Hubber" in the gallery. Confirm the spike widget appears.
5. Add the Medium size. Confirm:
   - The widget renders without crashing (shows "Hubber Spike" heading).
   - "Gate 1: container NON-NIL ✓" appears in green.
   - "value: hello-from-probe" (or the spike.json value) appears.
6. Long-press the widget to enter configuration. Confirm:
   - The "Connection" picker appears (Gate 2 PASS: metadata was extracted).
   - The picker shows "github.com", "gitlab.com", and optionally "live:<value>" if spike.json exists.
7. Select a connection. Confirm the widget updates to show "Connection: github.com" (or selected).
8. Confirm the Gate 1 indicator stays green (container URL non-nil from widget process).

---

## Build artifacts produced

All files are uncommitted. Key new artifacts:

| Path | Description |
|------|-------------|
| `Sources/HubberWidgetSpike/SpikeWidgetBundle.swift` | Widget spike source (AppIntentConfiguration + EntityQuery + App Group read) |
| `Hubber.entitlements` | Host app-groups entitlement for `make-widget-spike.sh` |
| `HubberWidget.entitlements` | Widget appex app-groups entitlement |
| `Scripts/make-widget-spike.sh` | Assembly script (build → link → appintents → bundle → sign → embed → verify) |
| `Scripts/spike-probe.swift` | Gate 1 CLI probe (run without Hubber.app) |
| `Package.swift` | Added `HubberWidgetSpike` executable product |
| `Makefile` | Added `widget-spike` target |
| `HubberWidgetSpike.appex/` | Assembled appex (at repo root, gitignored-equivalent) |

---

## Build mechanics learned (Approach A feasibility)

### What works under `swift build`

- **Compilation:** SPM compiles `AppIntentConfiguration`, `WidgetConfigurationIntent`, `AppEntity`, `EntityQuery`, `WidgetBundle` source successfully.
- **Object file:** `.o` produced with `_HubberWidgetSpike_main` symbol (SPM's `@main` alias).
- **Linking:** Manual `clang` invocation with `-Xlinker -alias -Xlinker _HubberWidgetSpike_main -Xlinker _main` produces a valid `Mach-O 64-bit executable arm64` — the correct type for widget extensions (verified against Crouton.appex: both are `EXECUTE`, not `MH_BUNDLE`).
- **Bundle shape:** Hand-assembled `Contents/Info.plist` with `CFBundlePackageType=XPC!`, `NSExtensionPointIdentifier=com.apple.widgetkit-extension`, and all required keys passes `codesign --verify --deep --strict`.
- **App Group entitlement:** Both host and appex carry `com.apple.security.application-groups` in their ad-hoc signatures; `codesign -d --entitlements` confirms it.

### What does NOT work under `swift build` / Approach A

- **AppIntents metadata:** SPM does not run `SWIFT_ENABLE_EMIT_CONST_VALUES` or `appintentsmetadataprocessor`. The const-values pipeline is Xcode-internal. Result: configurable widget (`AppIntentConfiguration`) has no registered intents; the config picker never populates. **This blocks the design goal of the spike.**
- **Widget discovery:** `pluginkit` silently ignores ad-hoc-signed extensions (`TeamIdentifier=not set`). This is independent of Approach A vs C.

### Approach C (XcodeGen) assessment

Approach C fixes the **AppIntents metadata** problem (Xcode runs the full pipeline), but does NOT fix the **discovery** problem (still ad-hoc signing without Team ID). Result:

- Approach C would allow Gate 2 (metadata) to pass.
- Gate 3 (discovery) remains blocked by the Apple Developer account requirement.
- Therefore, Approach C is a build-tooling improvement, not a local-testing enabler.

---

## Honest A-vs-C-vs-Defer read

**Recommend: Defer full widget to M4b (signed app). Prefer Approach C for the build when it proceeds.**

Rationale:
1. **Gate 3 is the terminal blocker.** Without a real Team ID, the system extension host won't load the widget, regardless of whether the build uses SPM or Xcode. Neither A nor C can fix a missing Apple Developer account.
2. **Gate 2 (AppIntents metadata) confirms Approach C is needed** when the feature resumes. The metadata pipeline is Xcode-internal and cannot be replicated by `swift build` + manual `appintentsmetadataprocessor`. A thin XcodeGen target for just the widget appex (consuming a `HubberKit` local package, built via `xcodebuild`) is the correct approach.
3. **Gate 1 is green.** App Group container access works for the non-sandboxed host under ad-hoc signing. The `WidgetSnapshotStore` seam (Phase 1) can be implemented and unit-tested now, without needing the widget to be discoverable.
4. **Actionable now (no Apple account needed):**
   - Phase 1: Extract `HubberKit`, implement `WidgetSnapshot` + `WidgetSnapshotStore`, wire host writes + timeline reloads. All testable via SPM unit tests.
   - Phase 2: Draft the `ConfigurationAppIntent` + `EntityQuery` (compile-tested via SPM even without the metadata pipeline).

---

## ⚠️ Addendum — independent Codex (gpt-5.5) review CORRECTS the read above

The original Gate 2 / Gate 3 conclusions are **partly wrong**. An independent review re-ran the
tooling and reached a different (better) result. Where this addendum and the text above conflict,
**the addendum wins.**

- **Gate 2 — SOLVED, not a blocker.** The AppIntents metadata pipeline *can* be driven from pure
  `swift build`. Verified recipe (emitted `Metadata.appintents` containing the spike's
  `SpikeWidgetIntent` / `SpikeConnectionEntity` / `SpikeConnectionQuery`):
  ```sh
  TOOLCHAIN=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
  plutil -extract constValueProtocols json -o .build/AppIntentsProtocols.json \
    "$TOOLCHAIN/usr/share/swift/SwiftConstantValues/AppIntents.json"
  swift build --target HubberWidgetSpike \
    -Xswiftc -emit-const-values \
    -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file \
    -Xswiftc -Xfrontend -Xswiftc .build/AppIntentsProtocols.json
  xcrun appintentsmetadataprocessor --output <out> --toolchain-dir "$TOOLCHAIN" \
    --module-name HubberWidgetSpike --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
    --xcode-version <ver> --platform-family macOS --deployment-target 14.0 \
    --target-triple arm64-apple-macosx14.0 --source-file-list <files> \
    --swift-const-vals-list <constvals> --force
  ```
  Use `-emit-const-values` (not just `-emit-const-values-path`). ⇒ **Approach A is viable for the
  build pipeline; Approach C is NOT required just for metadata.**

- **Gate 3 — "needs a PAID account" is too strong.** Discovery needs a real `TeamIdentifier`, but a
  **free Apple ID "Personal Team"** `Apple Development` certificate carries a 10-char Team ID and
  should satisfy `pluginkit` for local dev. **Untested here** — this machine has **0 codesigning
  identities** (`security find-identity -v -p codesigning` → 0).

- **Gate 1 PASS was over-claimed.** It proved only that the **non-sandboxed host** can reach the
  Group Containers *path*. The widget runs **sandboxed**; an *authorized* App Group entitlement for
  a sandboxed process likely needs a **PAID** Developer Program profile (free Personal Teams
  generally can't register app-group identifiers). Hand-adding the entitlement via
  `codesign --entitlements` does not make it *authorized*. **This — not Gate 2 or Gate 3 — is the
  real open risk for end-to-end data sharing.**

### Revised go/no-go
- **Build pipeline:** Approach A (pure SPM) viable — Gate 2 solved.
- **Local discovery + render:** needs a Team ID; a **free Personal Team likely suffices** (untested).
- **App Group from the sandboxed widget:** genuine open risk; may need a **paid** membership. Settle
  empirically once a signing identity exists.
- **Low-regret regardless:** Phase 1 (`HubberKit` + `WidgetSnapshot` + `WidgetSnapshotStore` + host
  write path) is additive + fully SPM-unit-testable — safe to build now.
   - **Gate full end-to-end testing** (pluginkit discovery + render) until M4b.
