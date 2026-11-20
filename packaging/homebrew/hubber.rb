# DRAFT cask — not yet publishable. See packaging/homebrew/README.md.
#
# Blocked on: (1) the repo being public, and (2) a public GitHub Release existing
# so the download URL resolves and a real `sha256` can be computed. Until then this
# is a reference draft; `brew install` against it will fail (no release asset).
#
# When the first release ships: set `version`, replace `sha256 :no_check` with the
# real checksum (see README), move this file to Casks/hubber.rb in the tap repo.
cask "hubber" do
  version "0.1.0"
  sha256 :no_check # TODO: real sha256 of Hubber.zip — `shasum -a 256 dist/Hubber.zip`

  url "https://github.com/osuritz/hubber/releases/download/v#{version}/Hubber.zip",
      verified: "github.com/osuritz/hubber/"
  name "Hubber"
  desc "Menu-bar app for tracking GitHub and GitLab review requests and PR status"
  homepage "https://github.com/osuritz/hubber"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Hubber updates itself via Sparkle, so Homebrew should not manage upgrades.
  auto_updates true
  depends_on macos: ">= :sonoma" # matches LSMinimumSystemVersion (macOS 14)

  app "Hubber.app"

  # Remove app data on `brew uninstall --zap` (bundle id com.osuritz.hubber).
  zap trash: [
    "~/Library/Application Support/com.osuritz.hubber",
    "~/Library/Caches/com.osuritz.hubber",
    "~/Library/HTTPStorages/com.osuritz.hubber",
    "~/Library/Preferences/com.osuritz.hubber.plist",
  ]

  caveats <<~EOS
    Hubber is open-source and currently distributed unsigned (no paid Apple
    Developer account for v1). On first launch macOS Gatekeeper will block it;
    open it once via System Settings → Privacy & Security → "Open Anyway", or
    right-click the app → Open. Subsequent Sparkle auto-updates install in place
    without further Gatekeeper prompts.
  EOS
end
