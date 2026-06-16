# Hubber — IT Deployment Guide

> **Audience:** IT administrators deploying Hubber fleet-wide via MDM.
>
> **Issues:** [#55](https://github.com/osuritz/hubber/issues/55), [#56](https://github.com/osuritz/hubber/issues/56)

---

## Overview

Hubber is a macOS menu-bar app (`.app` bundle) that ships as a distributable `.pkg` installer.
End-to-end MDM deployment involves two independent steps that can be done in either order:

1. **Deploy the pkg** — install `Hubber.app` to `/Applications` on managed devices.
2. **Push a configuration profile** — lock or preset managed preferences via `com.hubber.app`.

You do not need to do both. You can deploy the pkg and let users configure the app themselves, or
push a profile to restrict settings without managing installation (e.g. if users install manually).

---

## Requirements

| Requirement | Details |
|---|---|
| macOS version | 14.0 Sonoma or later |
| Architecture | Universal binary (arm64 + x86_64) — no separate M-chip / Intel builds |
| Signed pkg for silent deploy | Required for MDM-silent installation (see [Signing](#signing)) |
| MDM enrollment | Standard macOS MDM enrollment (any vendor) |

---

## Step 1 — Deploy Hubber.app via pkg

### Building the pkg

```bash
# From the Hubber source repository:
make pkg
# Produces: dist/Hubber.pkg
```

The `make pkg` target runs `Scripts/make-app.sh` (builds a universal release binary and assembles
`Hubber.app`) then `Scripts/make-pkg.sh` (packages it for installation to `/Applications`).

You can also download a pre-built `Hubber.pkg` from the GitHub releases page.

### Signing {#signing}

**Silent MDM deployment requires a signed pkg.** An unsigned pkg can be installed interactively
via `installer -pkg Hubber.pkg -target /` or double-clicked in Finder, but MDM vendors (Jamf,
Kandji, Mosyle) require a Developer ID Installer certificate to push packages silently.

To sign the pkg, set `HUBBER_INSTALLER_SIGN_IDENTITY` before running `make pkg`:

```bash
export HUBBER_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Acme Corp (TEAMID)"
make pkg
```

This requires a paid Apple Developer Program membership with a Developer ID Installer certificate
in the build machine's keychain. This capability is planned for M4b (Xcode project + notarization).

### Verifying the pkg

```bash
# List files included in the pkg:
pkgutil --payload-files dist/Hubber.pkg
# Expected: Applications/Hubber.app/... entries

# Check signature (informational; unsigned pkgs report "none"):
pkgutil --check-signature dist/Hubber.pkg
```

### Installing the pkg

```bash
# Install to /Applications (requires sudo):
sudo installer -pkg dist/Hubber.pkg -target /

# Verify installation:
ls /Applications/Hubber.app
```

---

### Deploying via Jamf Pro

1. In Jamf Pro, go to **Computers → Packages** and upload `Hubber.pkg`.
2. Create a **Policy** (or use a Pre-Stage Enrollment package):
   - Trigger: **Enrollment Complete** (or recurring check-in).
   - Package: select the uploaded `Hubber.pkg`.
   - Action: **Install**.
3. Scope the policy to the target Smart Group or static group.
4. The pkg must be **signed** with a Developer ID Installer certificate for Jamf to push silently.

### Deploying via Kandji

1. In Kandji, go to **Library → Auto Apps** or **Custom Apps**.
2. Upload `Hubber.pkg` as a **Custom App** (PKG install type).
3. Set **Install Enforcement** to **Continuously Enforce** or **Install Once**.
4. Assign the blueprint to the target devices.
5. The pkg must be **signed** for Kandji to install silently.

### Deploying via Mosyle

1. In Mosyle Business/Manager, go to **Apps → macOS Apps → Add App → Enterprise App**.
2. Upload `Hubber.pkg`.
3. Set the install scope (devices/groups).
4. The pkg must be **signed** for Mosyle to push silently. Unsigned pkgs can be delivered via
   the Self-Service portal with user interaction.

---

## Step 2 — Push a Configuration Profile

Hubber's managed preferences use the domain `com.hubber.app`. Push a **Custom Settings** (also
called "Custom Profile" by some vendors) profile targeting this domain to lock or preset app settings.

> **Important:** The profile domain `com.hubber.app` is different from the bundle identifier
> `com.osuritz.hubber`. Use `com.hubber.app` in your profile. See
> [managed-preferences.md](./managed-preferences.md) for the rationale.

A ready-to-edit sample profile is at
[sample-profiles/hubber-managed.mobileconfig](./sample-profiles/hubber-managed.mobileconfig).

### Deploying via Jamf Pro

1. Go to **Computers → Configuration Profiles → New**.
2. In **General**, give the profile a name (e.g. "Hubber MDM Settings").
3. Add the **Application & Custom Settings** payload.
4. Choose **External Applications** (custom domain).
5. Enter the Preference Domain: `com.hubber.app`.
6. Upload the `.plist` content from the sample profile (or paste PLIST XML directly).
7. Save and scope to the target computers.

> **Jamf note:** The "External Applications" option appears in Jamf Pro 10.35+. Earlier versions
> use "Application & Custom Settings → Custom Schema" with manual PLIST upload.

### Deploying via Kandji

1. Go to **Library → Custom Profiles → Add Profile**.
2. Upload the `hubber-managed.mobileconfig` file directly (edit UUIDs and keys before uploading).
3. Assign to the target blueprint.

### Deploying via Mosyle

1. Go to **Management → Profiles → Add Profile → Custom Profile**.
2. Upload the `hubber-managed.mobileconfig` file.
3. Assign the profile to the target device group.

> **Mosyle note:** For MDM Custom Profiles, Mosyle requires a valid `.mobileconfig` with unique
> `PayloadUUID` values. Ensure you replaced the placeholder UUIDs in the sample profile.

---

## Step 3 — Verify Managed Preferences on a Device

After the profile is pushed and Hubber is relaunched:

```bash
# Check machine-scope managed preferences (requires root):
sudo defaults read /Library/Managed\ Preferences/com.hubber.app

# Check user-scope managed preferences:
defaults read /Library/Managed\ Preferences/$(whoami)/com.hubber.app 2>/dev/null || echo "No user-scope prefs"

# Use cfprefsd to verify a specific key is forced:
/usr/libexec/cfprefsd read-defaults com.hubber.app analyticsEnabled
```

Locked settings appear greyed out in Hubber's preferences window. If a setting is not greyed out,
the profile is not yet applied — ensure MDM has checked in and Hubber has been relaunched.

---

## Managed Keys Quick Reference

See [managed-preferences.md](./managed-preferences.md) for the full reference table. Common
keys for a typical IT deployment:

| Goal | Key | Value |
|---|---|---|
| Disable analytics telemetry | `analyticsEnabled` | `false` |
| Disable crash reporting | `crashReportingEnabled` | `false` |
| Block personal GitHub sign-in | `allowPersonalGitHub` | `false` |
| Restrict to GitHub Enterprise only | `providerAllowlist` | `["github.yourcompany.com"]` |
| Set SLO window | `sloWindowHours` | `48` |
| Disable all notifications | `notificationsEnabled` | `false` |

---

## Troubleshooting

| Symptom | Likely cause | Resolution |
|---|---|---|
| Settings not greyed out after profile push | Profile not yet applied, or Hubber not relaunched | Force MDM check-in; quit and relaunch Hubber |
| pkg fails to install silently | pkg is unsigned | Sign with Developer ID Installer cert (requires paid Apple Developer account) |
| Profile shows "unknown" keys in MDM | Profile uploaded before Hubber was installed | MDM does not validate keys; this is cosmetic — keys still apply |
| `analyticsEnabled=false` but analytics still running | Hubber was not relaunched after profile push | Quit and relaunch Hubber (managed prefs are read at launch) |
| `providerAllowlist` not blocking sign-in | Key type mismatch in profile | Ensure the value is an Array of Strings, not a single String |

---

## Support

For deployment questions, open an issue at <https://github.com/osuritz/hubber/issues> with the
`enterprise` label.
