#!/usr/bin/env bash
# Scripts/make-widget-spike.sh — Phase-0 de-risking spike assembly
# Builds HubberWidgetSpike.appex and embeds it in Hubber.app.
# NOT production code. Throwaway. Delete after gates are recorded.
#
# Usage: bash Scripts/make-widget-spike.sh
# Prereq: run `make app-dev` first (or have Hubber.app already assembled).
#
# What this script does:
#   1. Build the host (debug) via make-app.sh, carrying the app-groups entitlement.
#   2. Compile + link HubberWidgetSpike (arm64 debug, native arch).
#   3. Attempt AppIntents metadata extraction via appintentsmetadataprocessor.
#   4. Hand-assemble HubberWidgetSpike.appex with the full bundle shape.
#   5. Sign appex inside-out (ad-hoc) with app-groups entitlement.
#   6. Embed in Hubber.app/Contents/PlugIns/.
#   7. Re-sign host with app-groups entitlement (LAST — inside-out).
#   8. Verify signatures and print Gate 1–3 status.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFT_LIB="$(xcrun --find swiftc | xargs dirname)/../lib/swift/macosx"

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------
VERSION="${1:-$(cat VERSION 2>/dev/null || echo "0.1.0")}"
VERSION="${VERSION// /}"
echo "==> Widget spike build — version ${VERSION}"

# ---------------------------------------------------------------------------
# 1. Build the host app (debug) via existing make-app.sh
#    (This uses the file-token-store path — fine for spike testing.)
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 1: Build host app (debug)"
HUBBER_BUILD_CONFIG=debug bash Scripts/make-app.sh "$VERSION"

APP="$REPO_ROOT/Hubber.app"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: Hubber.app not found after make-app.sh" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Compile the widget spike source
#    SPM builds the module but doesn't link a final binary. We do both steps.
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 2: Build HubberWidgetSpike target"
swift build --target HubberWidgetSpike 2>&1 || {
  echo "FINDING: swift build --target HubberWidgetSpike FAILED."
  echo "         This is a gate-2 blocker. Check output above."
  exit 1
}

OBJ_DIR="$REPO_ROOT/.build/arm64-apple-macosx/debug/HubberWidgetSpike.build"
OBJ="$OBJ_DIR/SpikeWidgetBundle.swift.o"

if [[ ! -f "$OBJ" ]]; then
  echo "ERROR: Object file not found at $OBJ" >&2
  echo "FINDING: SPM compiled but produced no .o — entry-point build failure." >&2
  exit 1
fi

echo "   Object file: $OBJ"
echo "   SPM build: PASS (module compiled)"

# ---------------------------------------------------------------------------
# 3. Link the widget binary as MH_EXECUTE
#    SPM uses the alias trick: _HubberWidgetSpike_main → _main equivalent.
#    Widget extensions ARE executables (confirmed from Crouton.appex).
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 3: Link widget binary (MH_EXECUTE with WidgetKit)"
WIDGET_BIN="$REPO_ROOT/.build/arm64-apple-macosx/debug/HubberWidgetSpike"
clang \
  -target arm64-apple-macosx14.0 \
  -isysroot "$SDK" \
  -framework WidgetKit \
  -framework AppIntents \
  -framework SwiftUI \
  -framework Foundation \
  -L "$SWIFT_LIB" \
  -L "$SDK/usr/lib/swift" \
  -rpath /usr/lib/swift \
  -rpath "@executable_path/../Frameworks" \
  -Xlinker -alias -Xlinker "_HubberWidgetSpike_main" -Xlinker "_main" \
  "$OBJ" \
  -o "$WIDGET_BIN" 2>&1 || {
    echo "ERROR: Link step failed — recording as Gate 2 blocker (build-product failure)." >&2
    exit 1
  }

echo "   Link result:"
file "$WIDGET_BIN"
lipo -info "$WIDGET_BIN"

# ---------------------------------------------------------------------------
# 4. AppIntents metadata extraction
#    swift build does NOT run appintentsmetadataprocessor automatically.
#    We attempt it manually and record the result.
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 4: AppIntents metadata extraction"
APPINTENTS_TOOL="$(xcrun --find appintentsmetadataprocessor 2>/dev/null || echo '')"
METADATA_DIR="$REPO_ROOT/.build/arm64-apple-macosx/debug/HubberWidgetSpike-appintents"
GATE2_METADATA="FAIL"

if [[ -z "$APPINTENTS_TOOL" ]]; then
  echo "   FINDING: appintentsmetadataprocessor not found in toolchain."
  echo "   Gate 2 metadata: TOOL NOT FOUND"
else
  echo "   Tool: $APPINTENTS_TOOL"
  mkdir -p "$METADATA_DIR"

  # Search for any .appintents or Metadata.appintents emitted by swift build
  SPM_METADATA="$(find "$REPO_ROOT/.build" -name "*.appintents" -o -name "Metadata.appintents" 2>/dev/null | head -1)"
  if [[ -n "$SPM_METADATA" ]]; then
    echo "   FINDING: swift build DID emit AppIntents metadata at: $SPM_METADATA"
    GATE2_METADATA="SPM_EMITTED"
  else
    echo "   swift build did NOT emit AppIntents metadata (.appintents not found in .build/)."
  fi

  # Attempt manual extraction
  echo "   Attempting manual appintentsmetadataprocessor..."
  SWIFTMODULE="$REPO_ROOT/.build/arm64-apple-macosx/debug/Modules/HubberWidgetSpike.swiftmodule"

  if "$APPINTENTS_TOOL" \
      --binary-file "$WIDGET_BIN" \
      --module-name HubberWidgetSpike \
      --output "$METADATA_DIR" \
      --sdk-root "$SDK" \
      --swift-module "$SWIFTMODULE" \
      2>&1; then
    echo "   FINDING: appintentsmetadataprocessor SUCCEEDED"
    ls -la "$METADATA_DIR" 2>/dev/null || true
    GATE2_METADATA="MANUAL_PASS"
  else
    echo "   FINDING: appintentsmetadataprocessor FAILED (see output above)"
    echo "   Gate 2: metadata extraction failed — AppIntentConfiguration may not work."
    GATE2_METADATA="MANUAL_FAIL"
  fi
fi

# ---------------------------------------------------------------------------
# 5. Assemble HubberWidgetSpike.appex bundle
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 5: Assemble HubberWidgetSpike.appex"
APPEX="$REPO_ROOT/HubberWidgetSpike.appex"
APPEX_CONTENTS="$APPEX/Contents"
APPEX_MACOS="$APPEX_CONTENTS/MacOS"

rm -rf "$APPEX"
mkdir -p "$APPEX_MACOS"

# Copy binary
cp "$WIDGET_BIN" "$APPEX_MACOS/HubberWidgetSpike"

# Embed AppIntents metadata if available
if [[ "$GATE2_METADATA" == "MANUAL_PASS" && -d "$METADATA_DIR" ]]; then
  APPEX_RESOURCES="$APPEX_CONTENTS/Resources"
  mkdir -p "$APPEX_RESOURCES"
  cp -R "$METADATA_DIR/"* "$APPEX_RESOURCES/" 2>/dev/null || true
  echo "   AppIntents metadata embedded in bundle."
fi

# Write Info.plist — full Xcode-equivalent bundle shape (spec §9)
cat > "$APPEX_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.osuritz.hubber.widget</string>
    <key>CFBundleExecutable</key>
    <string>HubberWidgetSpike</string>
    <key>CFBundleName</key>
    <string>HubberWidgetSpike</string>
    <key>CFBundleDisplayName</key>
    <string>Hubber Widget Spike</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

echo "   Bundle assembled at: $APPEX"
echo "   Binary type:"
file "$APPEX_MACOS/HubberWidgetSpike"
echo "   lipo:"
lipo -info "$APPEX_MACOS/HubberWidgetSpike"

# ---------------------------------------------------------------------------
# 6. Sign appex FIRST (inside-out) with app-groups entitlement
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 6: Sign appex (inside-out, ad-hoc, with app-groups entitlement)"
SIGN_IDENTITY="${HUBBER_SIGN_IDENTITY:--}"
WIDGET_ENTITLEMENTS="$REPO_ROOT/HubberWidget.entitlements"

codesign \
  --force \
  --sign "$SIGN_IDENTITY" \
  --entitlements "$WIDGET_ENTITLEMENTS" \
  "$APPEX" 2>&1
echo "   appex signed."

echo "   appex entitlements:"
codesign -d --entitlements :- "$APPEX" 2>&1 || true

# ---------------------------------------------------------------------------
# 7. Embed appex in Hubber.app/Contents/PlugIns/
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 7: Embed appex in Hubber.app"
PLUGINS_DIR="$APP/Contents/PlugIns"
mkdir -p "$PLUGINS_DIR"
rm -rf "$PLUGINS_DIR/HubberWidgetSpike.appex"
cp -R "$APPEX" "$PLUGINS_DIR/"
echo "   Embedded: $PLUGINS_DIR/HubberWidgetSpike.appex"

# ---------------------------------------------------------------------------
# 8. Re-sign host app with app-groups entitlement (LAST — inside-out)
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 8: Re-sign host app with app-groups entitlement"
HOST_ENTITLEMENTS="$REPO_ROOT/Hubber.entitlements"

codesign \
  --force \
  --sign "$SIGN_IDENTITY" \
  --entitlements "$HOST_ENTITLEMENTS" \
  "$APP" 2>&1
echo "   Host re-signed."

echo "   Host entitlements:"
codesign -d --entitlements :- "$APP" 2>&1 || true

# ---------------------------------------------------------------------------
# 9. Verify the whole structure
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 9: Verify signatures"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 || {
  echo "WARNING: codesign --verify failed — recording as potential Gate 3 blocker." >&2
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "==> Spike assembly complete"
echo ""
echo "  Gate 2 metadata result: $GATE2_METADATA"
echo ""
echo "  Next steps (manual):"
echo ""
echo "  Gate 1 — App Group container:"
echo "    swift Scripts/spike-probe.swift --write"
echo "    (Also run from the signed Hubber.app binary for the real answer.)"
echo ""
echo "  Gate 3 — Discovery:"
echo "    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f \"$(pwd)/Hubber.app\""
echo "    pluginkit -m -A -p com.apple.widgetkit-extension -v 2>&1 | grep -i hubber"
echo ""
echo "  Gate 4 — Render (GUI required):"
echo "    Open Hubber.app, then open System Settings → Notifications & Focus → Widgets"
echo "    or right-click the desktop and choose Edit Widgets."
echo ""
echo "  See docs/superpowers/SPIKE-RESULTS.md for the gate recording template."
echo "======================================================================"
