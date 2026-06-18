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
# 3. Code signing (no --options runtime; that requires notarization).
#    Defaults to ad-hoc ("-"). Set HUBBER_SIGN_IDENTITY to a stable self-signed
#    code-signing certificate name to keep the signature consistent across
#    rebuilds — that stops the repeated Keychain "allow access" prompts that
#    ad-hoc causes (its signature changes every build). Gatekeeper still needs
#    "Open Anyway" for a self-signed identity.
# ---------------------------------------------------------------------------
SIGN_IDENTITY="${HUBBER_SIGN_IDENTITY:--}"
echo "==> Code signing $APP (identity: $SIGN_IDENTITY)"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"

# ---------------------------------------------------------------------------
# 4. Verify signature
# ---------------------------------------------------------------------------
echo "==> Verifying signature"
if ! codesign --verify --deep --strict --verbose=2 "$APP" 2>&1; then
  echo "ERROR: codesign --verify failed for $APP" >&2
  exit 1
fi

echo ""
echo "==> Hubber.app built successfully (version ${VERSION})"
echo "    $(pwd)/$APP"
