#!/usr/bin/env bash
# Scripts/make-pkg.sh
# Build an MDM-compatible .pkg installer for Hubber.app.
#
# Usage:
#   ./Scripts/make-pkg.sh [VERSION]
#
# Environment variables:
#   HUBBER_INSTALLER_SIGN_IDENTITY  — Developer ID Installer identity string.
#                                     When set, the final .pkg is signed with
#                                     productsign; required for silent MDM deploy.
#                                     Default: unsigned (fine for manual install /
#                                     testing; MDM silent push requires signing).
#   VERSION                         — Override the version string (also accepted as
#                                     positional arg $1, arg takes precedence).
#
# Outputs:
#   dist/Hubber.pkg
#
# Notes:
#   - Assumes Hubber.app exists in the repo root (built by make-app.sh / `make app`).
#   - The installer-location is /Applications — pkgbuild places Hubber.app there.
#   - Package identifier: com.osuritz.hubber.pkg
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Version resolution (positional arg > env var > VERSION file > default)
# ---------------------------------------------------------------------------
if [[ "${1:-}" != "" ]]; then
    VERSION="$1"
elif [[ "${VERSION:-}" != "" ]]; then
    : # keep VERSION from env
elif [[ -f VERSION ]]; then
    VERSION="$(<VERSION)"
    VERSION="${VERSION// /}"  # strip whitespace
else
    VERSION="0.1.0"
fi
echo "==> Packaging Hubber.app version ${VERSION}"

# ---------------------------------------------------------------------------
# 1. Verify Hubber.app is present
# ---------------------------------------------------------------------------
APP="Hubber.app"
if [[ ! -d "$APP" ]]; then
    echo "ERROR: $APP not found in $(pwd). Run 'make app' first." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Prepare output directory
# ---------------------------------------------------------------------------
mkdir -p dist

# Intermediate component pkg (pkgbuild output)
COMPONENT_PKG="dist/Hubber-component.pkg"
# Final product pkg
FINAL_PKG="dist/Hubber.pkg"

# ---------------------------------------------------------------------------
# 3. Build the component pkg
#    --install-location /Applications  → Hubber.app installs to /Applications
#    --component         Hubber.app    → the .app bundle to package
#    --identifier                      → reverse-DNS package identifier
#    --version                         → recorded in the pkg receipt
# ---------------------------------------------------------------------------
echo "==> pkgbuild (component pkg)"
pkgbuild \
    --install-location /Applications \
    --component "$APP" \
    --identifier "com.osuritz.hubber.pkg" \
    --version "$VERSION" \
    "$COMPONENT_PKG"

# ---------------------------------------------------------------------------
# 4. Build the flat distribution pkg
#    productbuild wraps the component pkg in a distribution envelope that MDM
#    vendors expect. No distribution XML is needed for a simple single-pkg wrap.
# ---------------------------------------------------------------------------
echo "==> productbuild (distribution pkg)"
productbuild \
    --package "$COMPONENT_PKG" \
    "$FINAL_PKG"

# Remove the intermediate component pkg; only the final pkg is an artifact.
rm -f "$COMPONENT_PKG"

# ---------------------------------------------------------------------------
# 5. Optional signing with Developer ID Installer cert
#    Set HUBBER_INSTALLER_SIGN_IDENTITY to the full identity string, e.g.:
#      "Developer ID Installer: Acme Corp (TEAMID)"
#    Signing is required for silent MDM deployment (Jamf / Kandji / Mosyle).
# ---------------------------------------------------------------------------
SIGN_IDENTITY="${HUBBER_INSTALLER_SIGN_IDENTITY:-}"
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Signing pkg (identity: $SIGN_IDENTITY)"
    SIGNED_PKG="dist/Hubber-signed.pkg"
    productsign --sign "$SIGN_IDENTITY" "$FINAL_PKG" "$SIGNED_PKG"
    mv "$SIGNED_PKG" "$FINAL_PKG"
    echo "==> Verifying pkg signature"
    pkgutil --check-signature "$FINAL_PKG"
else
    echo "==> HUBBER_INSTALLER_SIGN_IDENTITY not set — producing unsigned pkg."
    echo "    (Unsigned pkg: manual 'installer -pkg' install works; MDM silent push requires signing.)"
fi

# ---------------------------------------------------------------------------
# 6. Report
# ---------------------------------------------------------------------------
PKG_SIZE="$(du -sh "$FINAL_PKG" | cut -f1)"
echo ""
echo "==> dist/Hubber.pkg built successfully (version ${VERSION}, ${PKG_SIZE})"
echo "    Install: sudo installer -pkg dist/Hubber.pkg -target /"
echo "    Verify:  pkgutil --payload-files dist/Hubber.pkg"
