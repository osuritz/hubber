#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building HubberWidget extension..."
xcodebuild -project HubberWidget.xcodeproj \
  -scheme HubberWidget \
  -configuration Debug \
  DEVELOPMENT_TEAM=4XP97LDDTH \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  -derivedDataPath /tmp/HubberWidgetBuild \
  build
