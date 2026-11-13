#!/bin/bash
# Install the pinned SwiftFormat and SwiftLint (see Scripts/lint-tools.env)
# into a directory. No sudo, no Homebrew: downloads the release assets over
# HTTPS from GitHub and fails closed unless their sha256 matches the pin.
#
# Usage: bash Scripts/install-lint-tools.sh <install-dir>
#   CI:    bash Scripts/install-lint-tools.sh "$RUNNER_TEMP/lint-tools"
#   Local: bash Scripts/install-lint-tools.sh .build/lint-tools
# Env: LINT_TOOLS_ENV overrides the pin file (used to test the sha256 check).
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: $0 <install-dir>" >&2
	exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=Scripts/lint-tools.env
source "${LINT_TOOLS_ENV:-$root/Scripts/lint-tools.env}"

mkdir -p "$1"
dest="$(cd "$1" && pwd)"

# Cache downloaded zips in the runner tool cache when there is one.
cache="${RUNNER_TOOL_CACHE:+$RUNNER_TOOL_CACHE/hubber-lint-tools}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# install_tool <binary> <version> <sha256> <release-url-base> <asset>
install_tool() {
	local bin="$1" version="$2" sha="$3" base="$4" asset="$5"
	local stamp="$dest/.$bin.sha256"

	if [[ -x "$dest/$bin" && "$(cat "$stamp" 2>/dev/null)" == "$sha" ]]; then
		echo "==> $bin $version already installed"
		return
	fi

	local zip="$tmp/$bin.zip"
	local cached="${cache:+$cache/$bin-$version-$sha.zip}"
	if [[ -n "$cached" && -f "$cached" ]]; then
		cp "$cached" "$zip"
	else
		echo "==> Downloading $bin $version"
		curl -fsSL --retry 3 -o "$zip" "$base/$version/$asset"
	fi

	local actual
	actual="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
	if [[ "$actual" != "$sha" ]]; then
		echo "error: sha256 mismatch for $bin $version" >&2
		echo "  expected $sha" >&2
		echo "  actual   $actual" >&2
		exit 1
	fi

	if [[ -n "$cached" && ! -f "$cached" ]]; then
		mkdir -p "$cache" && cp "$zip" "$cached"
	fi

	local out="$tmp/$bin-unzipped"
	mkdir -p "$out"
	unzip -oq "$zip" "$bin" -d "$out"
	chmod +x "$out/$bin"
	mv -f "$out/$bin" "$dest/$bin"
	echo "$sha" >"$stamp"
	echo "==> Installed $bin $version"
}

install_tool swiftformat "$SWIFTFORMAT_VERSION" "$SWIFTFORMAT_SHA256" \
	"https://github.com/nicklockwood/SwiftFormat/releases/download" swiftformat.zip
install_tool swiftlint "$SWIFTLINT_VERSION" "$SWIFTLINT_SHA256" \
	"https://github.com/realm/SwiftLint/releases/download" portable_swiftlint.zip
