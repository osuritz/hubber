# Approach C Spike Results

**Date:** 2026-06-22  
**Worktree branch:** feat/pr-widget  
**Spike dir:** `spike-c/` (gitignored throwaway)  
**Xcode:** 26.5 (17F42)  
**macOS:** 26 (Tahoe)  
**Signing:** `Apple Development: olivier.suritz@gmail.com (7TT7VMRR8M)` — TeamID **4XP97LDDTH** (free Personal Team)

---

## Overall verdict: **APPROACH C WORKS. GATE 3 PASSES. FREE PERSONAL TEAM IS SUFFICIENT.**

| Gate | Result | Notes |
|------|--------|-------|
| Build + sign | **PASS** | Automatic signing, free Personal Team, no App Groups capability error |
| App Groups | **PASS** | Free Personal Team provisions `com.apple.security.application-groups` without error |
| Gate 3 (discovery) | **PASS** | `com.osuritz.hubbercspike.widget(1.0)` appears in pluginkit |
| Host container write | **PASS** | `cspike.json` written with `value: hello-from-C-host` |
| Gate 4 (render) | **NEEDS-GUI** | Discovery confirmed; render test requires human GUI action — see checklist below |

---

## 1. Build + Signing

### Automatic signing — SUCCEEDED (no App Groups capability error)

```
xcodebuild \
  -project HubberCSpike.xcodeproj \
  -scheme HubberCSpike \
  -configuration Debug \
  -derivedDataPath dd \
  DEVELOPMENT_TEAM=4XP97LDDTH \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates

** BUILD SUCCEEDED **
```

**CRITICAL FINDING: The free Personal Team did NOT reject the App Groups capability.** No error of the form "Personal development teams do not support the App Groups capability". The entitlement was provisioned silently and correctly.

One intermediate build error was encountered and fixed: `APPLICATION_EXTENSION_API_ONLY` must be `YES` for the widget extension target. Fixed in `project.yml` before the successful build.

### Signatures

```
$ codesign -d --verbose=4 HubberCSpike.app

Identifier=com.osuritz.hubbercspike
Format=app bundle with Mach-O thin (arm64)
Authority=Apple Development: olivier.suritz@gmail.com (7TT7VMRR8M)
Authority=Apple Worldwide Developer Relations Certification Authority
Authority=Apple Root CA
TeamIdentifier=4XP97LDDTH        ← real Team ID, not "not set"

$ codesign -d --verbose=4 HubberCSpikeWidget.appex

Identifier=com.osuritz.hubbercspike.widget
Format=bundle with Mach-O thin (arm64)
Authority=Apple Development: olivier.suritz@gmail.com (7TT7VMRR8M)
Authority=Apple Worldwide Developer Relations Certification Authority
Authority=Apple Root CA
TeamIdentifier=4XP97LDDTH        ← real Team ID on widget too
```

### Entitlements

**App entitlements:**
```xml
<key>com.apple.application-identifier</key><string>4XP97LDDTH.com.osuritz.hubbercspike</string>
<key>com.apple.developer.team-identifier</key><string>4XP97LDDTH</string>
<key>com.apple.security.application-groups</key><array><string>group.com.osuritz.hubber</string></array>
<key>com.apple.security.get-task-allow</key><true/>
```

**Widget entitlements:**
```xml
<key>com.apple.application-identifier</key><string>4XP97LDDTH.com.osuritz.hubbercspike.widget</string>
<key>com.apple.developer.team-identifier</key><string>4XP97LDDTH</string>
<key>com.apple.security.app-sandbox</key><true/>                          ← REQUIRED for discovery
<key>com.apple.security.application-groups</key><array><string>group.com.osuritz.hubber</string></array>
<key>com.apple.security.get-task-allow</key><true/>
```

---

## 2. Key discovery: `com.apple.security.app-sandbox` is required on the widget

The first build attempt used only the app-groups entitlement on the widget (no sandbox). The widget was in lsregister but NOT in pluginkit. After comparing against Crouton (a working widget), the difference was that Crouton's widget has `com.apple.security.app-sandbox = YES`.

Adding `com.apple.security.app-sandbox` to the widget entitlements and rebuilding immediately fixed pluginkit discovery. **The sandbox entitlement is mandatory for the widget extension, not optional.** The host app does NOT require sandboxing.

---

## 3. Gate 3 — Discovery

**PASS.**

```
$ pluginkit -m -A -p com.apple.widgetkit-extension | grep -i cspike
     com.osuritz.hubbercspike.widget(1.0)

$ pluginkit -m -i com.osuritz.hubbercspike.widget -v
     com.osuritz.hubbercspike.widget(1.0)    1154E66F-5A4A-46FC-8582-78B9B7E6AD93
     2026-06-22 23:01:58 +0000
     /Applications/HubberCSpike.app/Contents/PlugIns/HubberCSpikeWidget.appex
```

**Contrast with prior spike (Approach A, ad-hoc):** The previous `SPIKE-RESULTS.md` showed `TeamIdentifier=not set` → pluginkit returned no matches. Now with a real Team ID from the free Personal Team, the widget IS discovered.

### What makes discovery work (all three required)

1. **Real TeamIdentifier** — `4XP97LDDTH`, not `not set` (ad-hoc). A free Personal Team suffices.
2. **`com.apple.security.app-sandbox = YES`** on the widget extension entitlements. Without it, lsregister registers the bundle but pluginkit silently ignores it.
3. **App installed in `/Applications/`** and registered via `lsregister -f`, then the host app launched.

### Gatekeeper note

`spctl --assess` reports the app as `rejected` (Gatekeeper requires notarization for Developer ID or App Store distribution). However, this does **not** block pluginkit discovery — Gatekeeper rejection affects distribution-to-end-users, not local developer signing. The `Apple Development` cert IS sufficient for local pluginkit discovery.

---

## 4. App Group + Container

### Host write (non-sandboxed host)

```
containerURL: /Users/oliviersuritz/Library/Group Containers/group.com.osuritz.hubber
Wrote cspike.json to: /Users/oliviersuritz/Library/Group Containers/group.com.osuritz.hubber/cspike.json

$ cat ~/Library/Group\ Containers/group.com.osuritz.hubber/cspike.json
{"value":"hello-from-C-host","writtenAt":1782169442.13711}
```

`containerURL(forSecurityApplicationGroupIdentifier:)` is non-nil for the non-sandboxed host app using a free Personal Team. The host can write the App Group JSON without being sandboxed itself.

### Widget read (sandboxed widget) — NEEDS-GUI to confirm

The widget is sandboxed with the App Group entitlement. Whether the **sandboxed widget process** can read from the container when running under a free Personal Team (without a properly registered App Group in the developer portal) is the **remaining open question** — Gate 4 tests this at runtime.

---

## 5. Gate 4 — Render (GUI checklist for human)

Gate 3 is PASS. Gate 4 requires a human to add the widget in the macOS widget gallery.

**Steps:**

1. Confirm `HubberCSpike.app` is installed in `/Applications/` and has been launched at least once (to write `cspike.json`).

2. Confirm the host wrote the file:
   ```sh
   cat ~/Library/Group\ Containers/group.com.osuritz.hubber/cspike.json
   ```
   Expected: `{"value":"hello-from-C-host","writtenAt":<epoch>}`

3. Open the widget gallery:
   - **Desktop:** right-click → Edit Widgets
   - OR **Notification Center:** click the date/time in the menu bar → scroll down → Edit Widgets

4. In the widget gallery, find **"HubberCSpike"** in the left panel. It should appear as a result of Gate 3 passing.

5. Click the widget or drag a **Medium** or **Large** instance onto the desktop / Notification Center panel.

6. Observe the widget render. Report:

   - **(a) Does it render at all?** (even showing placeholder text)
   - **(b) What does the circle indicator show?**
     - Green + "container NON-NIL" → the sandboxed widget process can access the App Group container under the free Personal Team. **App Groups work end-to-end.**
     - Red + "container NIL" → the sandboxed process is denied the container. App Groups are blocked under this signing for sandboxed processes.
   - **(c) What does the `value:` line show?**
     - `value: hello-from-C-host` → the widget successfully read `cspike.json` from the App Group. Full round-trip works.
     - `value: (file not found or parse error)` → container URL was non-nil but the file wasn't found (timing/ordering issue).
     - `value: (no app-group read)` → `containerURL` returned nil in the sandboxed widget process.

---

## 6. Revised go/no-go for the widget feature

### What this spike proves

| Question | Answer |
|----------|--------|
| Does Approach C (Xcode-built appex) produce a widget discoverable by pluginkit? | **YES** |
| Does a free Personal Team suffice for Team ID signing? | **YES** |
| Does the free Personal Team reject App Groups capability during build? | **NO** — no error |
| Is `app-sandbox` entitlement required on the widget extension? | **YES** — pluginkit silently ignores non-sandboxed widgets |
| Does the host (non-sandboxed) App Group container write work? | **YES** |
| Does the sandboxed widget App Group read work under free Personal Team? | **OPEN — Gate 4 (GUI test)** |
| Does the Approach A (pure SPM) ad-hoc signing fix carry over? | **NO** — Gate 3 fails without a real Team ID |

### Build recommendation

**Use Approach C (XcodeGen + xcodebuild) for the widget appex.** This spike confirms:
- xcodegen generates a working project in one command.
- Automatic signing with a free Personal Team works and provisions App Groups without error.
- The resulting appex is discovered by pluginkit.

The `APPLICATION_EXTENSION_API_ONLY = YES` setting is required on the widget extension target. The `com.apple.security.app-sandbox` entitlement is required on the widget extension (host app does NOT need to be sandboxed).

### Remaining risk

The **only remaining open question** is whether the sandboxed widget process can read from the App Group container under a free Personal Team. If the free team hasn't registered `group.com.osuritz.hubber` in the developer portal, the sandbox may deny the group container to the widget process at runtime even though the entitlement is present. Gate 4 (human GUI test above) resolves this.

**If Gate 4 shows green (container NON-NIL):** Full widget development can proceed now with the free Personal Team.

**If Gate 4 shows red (container NIL):** App Group data sharing requires a paid Apple Developer Program account (which also unlocks notarization/Gatekeeper acceptance for distribution). This defers the interactive widget to M4b.

---

## 7. Build artifacts

All under `spike-c/` (gitignored). Key files:

| Path | Description |
|------|-------------|
| `spike-c/project.yml` | xcodegen config — two targets (host + widget), App Group, deployment target macOS 14 |
| `spike-c/Sources/HubberCSpike/AppDelegate.swift` | Non-sandboxed host; writes cspike.json; logs containerURL |
| `spike-c/Sources/HubberCSpikeWidget/HubberCSpikeWidget.swift` | Static WidgetKit widget; reads cspike.json; shows green/red container indicator |
| `spike-c/Sources/HubberCSpikeWidget/HubberCSpikeWidget.entitlements` | `app-sandbox = YES` + app-groups (this is the fix that unblocked discovery) |
| `spike-c/dd/Build/Products/Debug/HubberCSpike.app` | Built + signed app bundle |
| `/Applications/HubberCSpike.app` | Installed (throwaway — delete when done) |

---

## 8. Cleanup

When done testing Gate 4:

```sh
pkill -x HubberCSpike 2>/dev/null || true
rm -rf /Applications/HubberCSpike.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/HubberCSpike.app
pluginkit -r /Applications/HubberCSpike.app/Contents/PlugIns/HubberCSpikeWidget.appex
```

`spike-c/` itself is already gitignored and can be deleted from the worktree at any time.
