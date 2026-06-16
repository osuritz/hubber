#!/usr/bin/env bash
# install.sh — Download and install the latest Hubber release.
# Usage: curl -fsSL https://raw.githubusercontent.com/osuritz/hubber/main/install.sh | bash
#
# This script:
#  1. Finds the latest GitHub release for Hubber
#  2. Downloads Hubber.zip
#  3. Extracts it to a temp directory
#  4. Removes the macOS quarantine attribute (no Gatekeeper prompt needed)
#  5. Installs to /Applications/Hubber.app
#  6. Launches Hubber
#
# Note: Hubber is ad-hoc-signed, NOT notarized (notarization requires a
# paid Apple Developer account). The quarantine attribute is stripped here
# so that curl-downloaded builds launch without a Gatekeeper warning.
# If you downloaded the DMG/zip manually from a browser, right-click →
# Open on first launch, or go to System Settings → Privacy & Security →
# "Open Anyway".
set -euo pipefail

GITHUB_REPO="osuritz/hubber"
ASSET_NAME="Hubber.zip"
INSTALL_DIR="/Applications"
APP_NAME="Hubber.app"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf '  \033[34m•\033[0m %s\n' "$*"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
err()   { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }
die()   { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Resolve latest release asset URL
# ---------------------------------------------------------------------------
info "Fetching latest Hubber release from GitHub…"

if command -v gh &>/dev/null; then
  ASSET_URL="$(gh release view --repo "$GITHUB_REPO" --json assets \
    --jq ".assets[] | select(.name == \"$ASSET_NAME\") | .url" 2>/dev/null || true)"
fi

if [[ -z "${ASSET_URL:-}" ]]; then
  # Fall back to the public GitHub API (no auth required for public repos)
  RELEASES_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
  ASSET_URL="$(curl -fsSL "$RELEASES_URL" \
    | grep -o '"browser_download_url": *"[^"]*Hubber\.zip"' \
    | head -1 \
    | sed 's/.*: *"\(.*\)"/\1/')"
fi

if [[ -z "${ASSET_URL:-}" ]]; then
  die "Could not resolve download URL for $ASSET_NAME.
  Manual fallback: go to https://github.com/${GITHUB_REPO}/releases/latest,
  download $ASSET_NAME, double-click to extract, drag Hubber to /Applications."
fi

info "Download URL: $ASSET_URL"

# ---------------------------------------------------------------------------
# 2. Download into a temp directory
# ---------------------------------------------------------------------------
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

ZIP_PATH="$TMPDIR_WORK/$ASSET_NAME"
info "Downloading $ASSET_NAME…"
curl -fSL --progress-bar "$ASSET_URL" -o "$ZIP_PATH"
ok "Downloaded $ASSET_NAME"

# ---------------------------------------------------------------------------
# 3. Extract
# ---------------------------------------------------------------------------
info "Extracting…"
ditto -x -k "$ZIP_PATH" "$TMPDIR_WORK/"
ok "Extracted"

EXTRACTED_APP="$TMPDIR_WORK/$APP_NAME"
if [[ ! -d "$EXTRACTED_APP" ]]; then
  die "$APP_NAME not found in archive."
fi

# ---------------------------------------------------------------------------
# 4. Strip quarantine attribute
# ---------------------------------------------------------------------------
info "Removing macOS quarantine attribute…"
xattr -dr com.apple.quarantine "$EXTRACTED_APP" 2>/dev/null || true
ok "Quarantine attribute removed"

# ---------------------------------------------------------------------------
# 5. Install to /Applications
# ---------------------------------------------------------------------------
TARGET="$INSTALL_DIR/$APP_NAME"
if [[ -d "$TARGET" ]]; then
  info "Replacing existing $TARGET"
  rm -rf "$TARGET"
fi

info "Installing to $TARGET…"
cp -R "$EXTRACTED_APP" "$TARGET"
ok "Installed $TARGET"

# ---------------------------------------------------------------------------
# 6. Launch
# ---------------------------------------------------------------------------
info "Launching Hubber…"
open -a Hubber || true

echo ""
ok "Hubber installed successfully!"
echo ""
echo "  If Hubber doesn't appear in the menu bar, open $TARGET manually."
echo "  On first launch you may need to grant notification permission."
echo ""
echo "  Note: Hubber is ad-hoc-signed, not notarized."
echo "  If Gatekeeper blocks it: System Settings → Privacy & Security → 'Open Anyway'."
