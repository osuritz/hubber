#!/usr/bin/env bash
# Scripts/make-dmg.sh
# Create a distributable DMG containing Hubber.app and an /Applications symlink.
# Usage: ./Scripts/make-dmg.sh [APP_PATH] [OUTPUT_DMG]
# Defaults: Hubber.app → dist/Hubber.dmg
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP="${1:-Hubber.app}"
OUTPUT="${2:-dist/Hubber.dmg}"

if [[ ! -d "$APP" ]]; then
  echo "ERROR: $APP not found. Run 'make app' first." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

# Stage into a temp directory
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging $APP → $STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating DMG: $OUTPUT"
hdiutil create \
  -volname "Hubber" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$OUTPUT"

echo ""
echo "==> DMG created: $OUTPUT"
ls -lh "$OUTPUT"
