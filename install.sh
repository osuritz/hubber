#!/usr/bin/env bash
# install.sh — download and install Hubber.
#
#   curl -fsSL https://raw.githubusercontent.com/osuritz/hubber/main/install.sh | bash
#
# What it does:
#   1. Downloads Hubber.zip from the GitHub release (latest, or HUBBER_VERSION).
#   2. Verifies it against the release's published SHA-256 and the app's code signature.
#   3. Installs Hubber.app to /Applications (or ~/Applications if that is not writable),
#      replacing any existing copy.
#   4. Launches it.
#
# Why a script: Hubber is ad-hoc-signed, not notarized. A copy downloaded with a browser is
# quarantined and blocked by Gatekeeper on first launch; a copy fetched with curl is not.
#
# Options (environment variables):
#   HUBBER_VERSION=0.1.2        install a specific release instead of the latest
#   HUBBER_INSTALL_DIR=<dir>    install somewhere other than /Applications
#   HUBBER_NO_OPEN=1            do not launch Hubber after installing
#   HUBBER_DOWNLOAD_BASE=<url>  fetch Hubber.zip (+ .sha256) from another location
set -euo pipefail

REPO="osuritz/hubber"
APP_NAME="Hubber.app"
ASSET="Hubber.zip"

info() { printf '  \033[34m•\033[0m %s\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die() {
  printf '  \033[31m✗\033[0m %s\n' "$*" >&2
  exit 1
}

download_base() {
  if [[ -n "${HUBBER_DOWNLOAD_BASE:-}" ]]; then
    printf '%s' "${HUBBER_DOWNLOAD_BASE%/}"
  elif [[ -n "${HUBBER_VERSION:-}" ]]; then
    printf 'https://github.com/%s/releases/download/v%s' "$REPO" "${HUBBER_VERSION#v}"
  else
    printf 'https://github.com/%s/releases/latest/download' "$REPO"
  fi
}

install_dir() {
  if [[ -n "${HUBBER_INSTALL_DIR:-}" ]]; then
    printf '%s' "$HUBBER_INSTALL_DIR"
  elif [[ -w /Applications ]]; then
    printf '/Applications'
  else
    printf '%s/Applications' "$HOME"
  fi
}

verify_checksum() {
  local zip="$1" base="$2" expected actual
  if ! expected="$(curl -fsSL "$base/$ASSET.sha256" 2>/dev/null | awk '{print $1; exit}')" || [[ -z "$expected" ]]; then
    warn "This release publishes no checksum; skipping the SHA-256 check."
    return
  fi
  actual="$(shasum -a 256 "$zip" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "Checksum mismatch for $ASSET (expected $expected, got $actual)."
  ok "SHA-256 verified"
}

check_macos_version() {
  local app="$1" required current
  required="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist" 2>/dev/null || true)"
  current="$(sw_vers -productVersion)"
  if [[ -n "$required" && "${current%%.*}" -lt "${required%%.*}" ]]; then
    die "Hubber requires macOS $required or newer (this Mac runs $current)."
  fi
}

main() {
  [[ "$(uname -s)" == "Darwin" ]] || die "Hubber is a macOS app; this installer only runs on macOS."

  local base work zip app dest target
  base="$(download_base)"
  work="$(mktemp -d)"
  # shellcheck disable=SC2064 # expand now: `work` is local and gone by the time EXIT fires
  trap "rm -rf '$work'" EXIT
  zip="$work/$ASSET"

  info "Downloading $base/$ASSET"
  curl -fSL --progress-bar "$base/$ASSET" -o "$zip" ||
    die "Download failed. Releases: https://github.com/$REPO/releases"
  verify_checksum "$zip" "$base"

  ditto -x -k "$zip" "$work/extracted"
  app="$work/extracted/$APP_NAME"
  [[ -d "$app" ]] || die "$APP_NAME not found in $ASSET."
  codesign --verify --deep --strict "$app" 2>/dev/null || die "$APP_NAME failed code-signature verification."
  check_macos_version "$app"

  dest="$(install_dir)"
  target="$dest/$APP_NAME"
  mkdir -p "$dest" || die "Cannot create $dest."
  [[ -w "$dest" ]] || die "Cannot write to $dest. Set HUBBER_INSTALL_DIR to a writable folder."

  if [[ -e "$target" ]]; then
    info "Replacing existing $target"
    if pkill -x Hubber 2>/dev/null; then
      sleep 1
    fi
    rm -rf "$target"
  fi
  ditto "$app" "$target"
  # curl does not quarantine downloads; this only matters if the zip came from elsewhere.
  xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/Contents/Info.plist" 2>/dev/null || true)"
  ok "Installed Hubber ${version:-} to $target"

  if [[ -z "${HUBBER_NO_OPEN:-}" ]]; then
    open "$target" || warn "Could not launch Hubber; open $target manually."
    echo "  Look for the Hubber icon in the menu bar. Allow notifications when asked."
  fi
  echo "  To update later, run this installer again. To uninstall, delete $target."
}

# Everything runs from main so a truncated download of this script cannot execute half of it.
main "$@"
