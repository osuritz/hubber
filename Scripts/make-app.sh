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
# 1. Universal release build
# ---------------------------------------------------------------------------
echo "==> swift build -c release --arch arm64 --arch x86_64"
swift build -c release --arch arm64 --arch x86_64

BINARY=".build/apple/Products/Release/Hubber"
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

# Note: no app icon (.icns) yet — follow-up in M4b.

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
