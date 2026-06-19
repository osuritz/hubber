# Runbook: Sparkle auto-update rollout

Operator guide for turning Hubber's Sparkle auto-update **on**. The app + build
mechanism ships with the code+build PR for [#51]; this runbook is the procedure to
make auto-update actually live. Run sections 1–3 once; repeat sections 4–5 per
release. This is the work that finally closes [#51]. Notarization (no Gatekeeper
prompt on first install) is a separate track — epic #79 (M4b), blocked on a paid
Apple Developer account.

**Project specifics**
- Repo: `osuritz/hubber`
- Bundle id: `com.osuritz.hubber`
- Signing identity: `Hubber Self-Signed` (login keychain; **expires 2027-06-16**)
- `Scripts/make-app.sh` reads `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY` from the
  environment and writes them into `Info.plist` (omitted when unset).

## 1. One-time: generate the EdDSA keypair

Sparkle's CLI tools ship inside the resolved SPM artifact.

```bash
swift build   # ensure the artifact exists
SPARKLE_BIN="$(find .build/artifacts -name 'generate_keys' | head -1)"
"$SPARKLE_BIN" -p > sparkle_public_key.txt   # prints the base64 public key
```

- The **private key** is stored automatically in your login Keychain as
  "Private key for signing Sparkle updates". Back it up securely (see §7).
- The contents of `sparkle_public_key.txt` is the value for `SPARKLE_PUBLIC_ED_KEY`.

Export the private key for CI and store it as a GitHub Actions secret:

```bash
"$SPARKLE_BIN" -x sparkle_private_key.pem
gh secret set SPARKLE_PRIVATE_KEY < sparkle_private_key.pem
rm -f sparkle_private_key.pem            # do not commit; delete after upload
```

Also store the public key as a (non-secret) Actions variable so the release build can
inject it:

```bash
gh variable set SPARKLE_PUBLIC_ED_KEY < sparkle_public_key.txt
```

## 2. One-time: choose appcast hosting + set SUFeedURL

**Decision:** GitHub Pages (recommended — free, stable URL, version-controlled) vs. a
GitHub Releases raw asset. Record the choice here when made.

For GitHub Pages serving `appcast.xml` from the `/docs` folder on the default branch
(or a `gh-pages` branch), the feed URL is:

```
https://osuritz.github.io/hubber/appcast.xml
```

Store it as an Actions variable:

```bash
gh variable set SPARKLE_FEED_URL --body "https://osuritz.github.io/hubber/appcast.xml"
```

The URL must remain stable forever — every shipped build embeds it, and Sparkle will
only ever check the URL baked into the running app.

## 3. One-time: signing cert in CI

Release builds must use the stable `Hubber Self-Signed` identity (ad-hoc trips
Sparkle's Library Validation). Export it and import it in CI.

```bash
# Export cert + private key as a password-protected .p12:
security export -k login.keychain-db -t identities -f pkcs12 \
  -P "$P12_PASSWORD" -o hubber-signing.p12   # use a strong, throwaway password

base64 -i hubber-signing.p12 | gh secret set HUBBER_SIGNING_P12
gh secret set HUBBER_SIGNING_P12_PASSWORD --body "$P12_PASSWORD"
rm -f hubber-signing.p12
```

In `.github/workflows/release.yml`, before the build step, import into a temporary
keychain and export `HUBBER_SIGN_IDENTITY`:

```yaml
      - name: Import signing certificate
        env:
          P12_B64: ${{ secrets.HUBBER_SIGNING_P12 }}
          P12_PASSWORD: ${{ secrets.HUBBER_SIGNING_P12_PASSWORD }}
        run: |
          KEYCHAIN="$RUNNER_TEMP/hubber.keychain-db"
          security create-keychain -p "" "$KEYCHAIN"
          security set-keychain-settings "$KEYCHAIN"
          security unlock-keychain -p "" "$KEYCHAIN"
          echo "$P12_B64" | base64 --decode > "$RUNNER_TEMP/cert.p12"
          security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" \
            -P "$P12_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -k "" "$KEYCHAIN"
          security list-keychains -d user -s "$KEYCHAIN" login.keychain-db
          rm -f "$RUNNER_TEMP/cert.p12"
          echo "HUBBER_SIGN_IDENTITY=Hubber Self-Signed" >> "$GITHUB_ENV"
```

Pass the Sparkle env vars into the build step:

```yaml
      - name: Assemble Hubber.app and package artifacts
        env:
          SPARKLE_FEED_URL: ${{ vars.SPARKLE_FEED_URL }}
          SPARKLE_PUBLIC_ED_KEY: ${{ vars.SPARKLE_PUBLIC_ED_KEY }}
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          make dist VERSION="$VERSION"
```

## 4. Per-release: build, sign, package, generate the appcast

The release workflow already builds, signs, and packages `dist/Hubber.zip` +
`dist/Hubber.dmg`. Add appcast generation after packaging:

```yaml
      - name: Generate appcast
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          SPARKLE_BIN="$(find .build/artifacts -name 'generate_appcast' | head -1)"
          echo "$SPARKLE_PRIVATE_KEY" > "$RUNNER_TEMP/sparkle_key.pem"
          mkdir -p release-archives && cp dist/Hubber.zip release-archives/
          "$SPARKLE_BIN" \
            --ed-key-file "$RUNNER_TEMP/sparkle_key.pem" \
            --download-url-prefix "https://github.com/osuritz/hubber/releases/download/${GITHUB_REF_NAME}/" \
            --link "https://github.com/osuritz/hubber" \
            -o docs/appcast.xml \
            release-archives/
          rm -f "$RUNNER_TEMP/sparkle_key.pem"
```

`generate_appcast` reads the version from each archive's embedded `Info.plist` and
writes `sparkle:edSignature` for every item. Delta updates are out of scope for v1.

## 5. Per-release: publish

1. Commit the regenerated `docs/appcast.xml` (Pages serves it) — or push to `gh-pages`.
2. The existing `gh release create` step uploads `dist/Hubber.zip` + `dist/Hubber.dmg`
   and tags the release.
3. Running instances check the feed on schedule, verify the EdDSA signature, download,
   and install in place.

## 6. Acceptance tests (issue #51 criteria)

- [ ] A running build N detects N+1 from the appcast, verifies the signature, installs,
      and relaunches with **no Gatekeeper prompt** (in-place update strips quarantine).
- [ ] "Check for Updates…" opens Sparkle's standard update UI.
- [ ] An appcast entry with a **wrong EdDSA signature** is rejected (update refused).
- [ ] A `SUPublicEDKey` mismatch between the running app and an update is rejected with a
      clear error (not a silent failure).
- [ ] On a fresh macOS 14+ machine, install via DMG/zip then auto-update → no new
      Gatekeeper dialog for the updated version.

## 7. Key rotation, recovery, cert expiry

- **Back up the EdDSA private key.** If it's lost, existing users cannot auto-update and
  must reinstall manually — there is no recovery path.
- **Cert expiry:** `Hubber Self-Signed` expires **2027-06-16**. Renew/replace before then
  and keep the same identity name so Keychain ACLs (stored tokens) stay continuous.
- **Public-key rotation** requires shipping a build whose `Info.plist` lists both the old
  and new keys (`SUPublicEDKeys`) before retiring the old one.

[#51]: https://github.com/osuritz/hubber/issues/51
