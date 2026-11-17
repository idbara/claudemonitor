# Release → .dmg GitHub Actions workflow — design (short)

Date: 2026-11-17 · Status: draft, awaiting approval

**Why:** publishing a GitHub release should produce the installable `.dmg`
automatically, signed exactly like local builds so users' Keychain
"Always Allow" survives updates.

**Approaches:** A — GitHub-hosted macOS runner + the existing self-signed
certificate imported from repo secrets (**chosen**). B — ad-hoc signing in CI
(rejected: new designated requirement every release → Keychain password prompt
after every update). C — self-hosted runner on Bara's Mac (rejected: Mac must be
on; runs repo code locally).

**Design**
- `.github/workflows/release-dmg.yml`, triggers: `release: [published]` and
  `workflow_dispatch` with input `tag` (to rebuild/re-attach for an existing
  release) *(my call)*. `permissions: contents: write`. Runner `macos-26`; select
  the newest installed Xcode (must build the macOS 26.5 target) *(my call: plain
  shell, no third-party actions)*.
- **Signing:** secrets `MACOS_CERT_P12` (base64 of the `.p12`) and
  `MACOS_CERT_PASSWORD`. The job creates a temporary keychain with a random
  password, imports the `.p12` (`-T /usr/bin/codesign`), sets the key partition
  list, adds it to the search list, extracts the certificate with `openssl` and
  marks it trusted for code signing (`sudo security add-trusted-cert -d -r
  trustRoot -p codeSign`), so Xcode finds "Claude Monitor Self-Signed" exactly as
  locally. The keychain is deleted in an `always()` step. No project settings change.
- **Version:** tag `v1.2.0` → `MARKETING_VERSION=1.2.0`;
  `CURRENT_PROJECT_VERSION=<run number>`.
- `make-dmg.sh` gains optional env `VERSION` / `BUILD_NUMBER` (passed to
  `xcodebuild`) and, when `VERSION` is set, names the output
  `dist/Claude-Monitor-<VERSION>.dmg`. Without them it behaves as today.
- **Guard:** after the build, fail unless `codesign -d -r-` shows
  `certificate leaf = H"…"` (never `cdhash`, i.e. never ad-hoc).
- Upload with `gh release upload <tag> <dmg> --clobber` (`GITHUB_TOKEN`).
- README: a short "Rilis" section — one-time secret setup and how to release.

**One-time setup (Bara, by hand — it involves the private key):** Keychain Access
→ My Certificates → "Claude Monitor Self-Signed" → Export → `.p12` with a password;
then `base64 -i cm.p12 | gh secret set MACOS_CERT_P12` and
`gh secret set MACOS_CERT_PASSWORD`; delete the `.p12` file.

**Not included:** notarization / Developer ID, Sparkle auto-update, building on
every push.

**Verification:** local `make-dmg.sh` with and without `VERSION`; workflow syntax
via `actionlint` if available; the real run happens on the first release (or
`workflow_dispatch`) after the secrets exist.
