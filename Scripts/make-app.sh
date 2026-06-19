#!/usr/bin/env bash
# Scripts/make-app.sh
# Build a universal release binary and assemble an ad-hoc-signed Hubber.app.
# Usage: ./Scripts/make-app.sh [VERSION]
# VERSION defaults to the contents of VERSION file, or 0.1.0.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Version resolution (arg > VERSION file > default)
# ---------------------------------------------------------------------------
if [[ "${1:-}" != "" ]]; then
  VERSION="$1"
elif [[ -f VERSION ]]; then
  VERSION="$(<VERSION)"
  VERSION="${VERSION// /}"  # strip whitespace
else
  VERSION="0.1.0"
fi
echo "==> Building Hubber.app version ${VERSION}"

# ---------------------------------------------------------------------------
# 1. Build the binary.
#    HUBBER_BUILD_CONFIG=release (default) → universal distribution binary.
#    HUBBER_BUILD_CONFIG=debug   → native-arch dev binary, compiled with
#    `#if DEBUG`, so the app uses the file token store (GitHubDevelopmentFileTokenStore)
#    instead of the Keychain — no repeated "allow access" prompts after each
#    ad-hoc-signed rebuild. Driven by `make app-dev`.
# ---------------------------------------------------------------------------
CONFIG="${HUBBER_BUILD_CONFIG:-release}"
if [[ "$CONFIG" == "debug" ]]; then
  echo "==> swift build (debug, native arch — dev build: file token store)"
  swift build
  BINARY=".build/debug/Hubber"
else
  echo "==> swift build -c release --arch arm64 --arch x86_64"
  swift build -c release --arch arm64 --arch x86_64
  BINARY=".build/apple/Products/Release/Hubber"
fi

if [[ ! -f "$BINARY" ]]; then
  echo "ERROR: expected binary not found at $BINARY" >&2
  exit 1
fi

echo "==> lipo check:"
lipo -info "$BINARY"

# ---------------------------------------------------------------------------
# 2. Assemble Hubber.app bundle
# ---------------------------------------------------------------------------
APP="Hubber.app"
CONTENTS="$APP/Contents"
echo "==> Assembling $APP"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Copy universal binary
cp "$BINARY" "$CONTENTS/MacOS/Hubber"

# SPM links Sparkle via @rpath but emits @executable_path/../lib, not ../Frameworks.
# Add the standard Frameworks rpath so dyld finds our embedded copy.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/Hubber" 2>/dev/null || true

# Write PkgInfo
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Write Info.plist
YEAR="$(date +%Y)"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.osuritz.hubber</string>
    <key>CFBundleExecutable</key>
    <string>Hubber</string>
    <key>CFBundleName</key>
    <string>Hubber</string>
    <key>CFBundleDisplayName</key>
    <string>Hubber</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>hubber</string>
    <key>CFBundleIconName</key>
    <string>hubber</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © ${YEAR} Olivier Suritz. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
    <key>SUAllowsAutomaticUpdates</key>
    <true/>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------------------
# 2b. App icon — compile the Icon Composer bundle (assets/hubber.icon) into
#     Assets.car (Liquid Glass on macOS 26) + hubber.icns (classic fallback).
#     The matching CFBundleIconFile / CFBundleIconName keys are set in the
#     Info.plist above. Requires Xcode's actool (full Xcode, not just the CLT).
# ---------------------------------------------------------------------------
ICON_SRC="assets/hubber.icon"
if [[ -d "$ICON_SRC" ]] && xcrun --find actool >/dev/null 2>&1; then
  echo "==> Compiling app icon from $ICON_SRC"
  ICON_PARTIAL="$(mktemp -t hubber-icon-partial).plist"
  xcrun actool \
    --output-format human-readable-text \
    --app-icon hubber \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --target-device mac \
    --output-partial-info-plist "$ICON_PARTIAL" \
    --compile "$CONTENTS/Resources" \
    "$ICON_SRC"
  rm -f "$ICON_PARTIAL"
else
  echo "WARNING: $ICON_SRC missing or actool unavailable — building without an app icon" >&2
fi

# ---------------------------------------------------------------------------
# 2c. Sparkle feed URL + public key are injected from the environment so no
#     secrets are committed. Omitted when unset (dev builds; pre-rollout CI).
#     IMPORTANT: this must run BEFORE code signing below — mutating Info.plist
#     after signing would invalidate the app's seal.
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

echo ""
echo "==> Hubber.app built successfully (version ${VERSION})"
echo "    $(pwd)/$APP"
