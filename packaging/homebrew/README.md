# Homebrew cask (draft)

`hubber.rb` is a **draft** Homebrew cask for installing Hubber via
`brew install --cask`. It is committed here for review; it is **not yet
publishable or testable**.

## Why it can't ship yet

A cask installs from a **public** GitHub Release asset. Two preconditions are
unmet today (tracked in #50, gated on the public launch — see #113):

1. **The repo is private.** Release assets on a private repo require auth that
   `brew` can't supply.
2. **No public Release exists.** The download URL
   (`releases/download/v0.1.0/Hubber.zip`) 404s, so the cask can't be installed
   and its real `sha256` can't be computed.

The release pipeline already produces the asset this cask expects: `make dist`
builds `dist/Hubber.zip` (a `ditto --keepParent` archive containing
`Hubber.app`) and the release workflow uploads it to
`releases/download/<tag>/Hubber.zip`.

## Publishing it (after the repo is public and v0.1.0 is tagged)

Homebrew casks live in a **tap** (a separate `homebrew-<name>` repo), not in the
app repo. To publish:

1. Create a tap repo, e.g. `osuritz/homebrew-tap`.
2. Copy this file to `Casks/hubber.rb` in that tap.
3. Set `version` to the release (e.g. `0.1.0`) and replace `sha256 :no_check`
   with the real checksum:
   ```sh
   curl -fsSL https://github.com/osuritz/hubber/releases/download/v0.1.0/Hubber.zip -o Hubber.zip
   shasum -a 256 Hubber.zip   # paste the digest into the cask's sha256
   ```
4. Validate locally:
   ```sh
   brew audit --cask --new ./Casks/hubber.rb
   brew install --cask ./Casks/hubber.rb
   ```
5. Users then install with:
   ```sh
   brew tap osuritz/tap
   brew install --cask hubber
   ```

## Notes

- `auto_updates true` — Hubber self-updates via Sparkle, so Homebrew won't fight
  it on `brew upgrade`.
- `depends_on macos: ">= :sonoma"` mirrors the app's macOS 14 floor.
- Unsigned for v1: the cask's `caveats` tells users about the one-time Gatekeeper
  approval on first launch. (Notarization to remove that prompt is the separate
  M4b track, #79.)
