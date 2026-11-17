# Release → .dmg Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publishing a GitHub release builds a `.dmg` signed with "Claude Monitor Self-Signed" and attaches it to the release.

**Architecture:** `make-dmg.sh` learns optional `VERSION`/`BUILD_NUMBER`; a GitHub Actions workflow on a hosted macOS runner imports the certificate from secrets into a temporary keychain, runs `make-dmg.sh`, guards against ad-hoc signing, and uploads with `gh`.

**Tech Stack:** bash, xcodebuild, hdiutil, `security`, GitHub Actions, `gh`.

**Spec:** `docs/superpowers/specs/2026-11-17-release-dmg-workflow-design.md`

## Global Constraints

- Secrets: `MACOS_CERT_P12` (base64 `.p12`), `MACOS_CERT_PASSWORD`. Identity name `Claude Monitor Self-Signed`. No project setting changes.
- Triggers: `release` `published`; `workflow_dispatch` input `tag` (required). `permissions: contents: write`. Runner `macos-26`. No third-party actions besides `actions/checkout`.
- Version: tag with leading `v` stripped → `MARKETING_VERSION`; `CURRENT_PROJECT_VERSION` = `github.run_number`.
- Output: `dist/Claude-Monitor-<VERSION>.dmg` when `VERSION` set; `dist/Claude Monitor.dmg` otherwise (unchanged).
- Guard: `codesign -d -r-` must contain `certificate leaf = H"`; fail otherwise.
- Temporary keychain always deleted (`if: always()`).

## Review Focus

1. Secrets missing (first release before setup) — job fails early with a clear message, not a confusing Xcode signing error. → Task 2 step "secrets check".
2. Tag without `v` (`1.2.0`) — version still `1.2.0`. → Task 2 version step uses `${TAG#v}`.
3. Re-running for a release that already has the dmg — `--clobber` replaces it. → Task 2 upload step.
4. Local `./make-dmg.sh` without env — same name and behavior as before. → Task 1 Step 3.
5. Runner Xcode too old for macOS 26.5 — job prints the selected Xcode version before building. → Task 2 Xcode step.

---

### Task 1: `make-dmg.sh` version parameters

**Files:** Modify `make-dmg.sh`.

- [ ] **Step 1: Implement** — optional env `VERSION`, `BUILD_NUMBER`: when set, append `MARKETING_VERSION="$VERSION"` / `CURRENT_PROJECT_VERSION="$BUILD_NUMBER"` to the `xcodebuild` call; `OUT="$DIST/Claude-Monitor-${VERSION}.dmg"` when `VERSION` is set. Print the output path (CI reads it from `dist/`).
- [ ] **Step 2: Verify with version** — `VERSION=9.9.9 BUILD_NUMBER=42 ./make-dmg.sh` → `dist/Claude-Monitor-9.9.9.dmg` exists; mount it (`hdiutil attach -nobrowse -readonly`) and `plutil -extract CFBundleShortVersionString raw` → `9.9.9`, `CFBundleVersion` → `42`; `codesign -d -r-` shows `certificate leaf = H"`. Detach and delete the test dmg.
- [ ] **Step 3: Verify without version** — `bash -n make-dmg.sh` passes, and the `OUT` line still resolves to `dist/Claude Monitor.dmg` when `VERSION` is unset (check by reading the script; a full second build is not needed).
- [ ] **Step 4: Commit** (with spec + plan) — `build: make-dmg.sh accepts VERSION/BUILD_NUMBER`.

### Task 2: Workflow + docs

**Files:** Create `.github/workflows/release-dmg.yml`; modify `README.md`, `CLAUDE.md`.

Workflow steps (one job `dmg`, `runs-on: macos-26`):
1. `actions/checkout@v4` (ref = the tag).
2. Resolve tag: `${{ github.event.release.tag_name || inputs.tag }}` → `TAG`, `VERSION=${TAG#v}`.
3. Secrets check: fail with `::error::` "Set MACOS_CERT_P12 and MACOS_CERT_PASSWORD (README › Rilis)" if either is empty.
4. Select Xcode: newest `/Applications/Xcode*.app` via `sudo xcode-select -s`; print `xcodebuild -version`.
5. Import certificate: random keychain password; `security create-keychain`, `set-keychain-settings -lut 21600`, `unlock-keychain`; decode `.p12` to `$RUNNER_TEMP`; `security import … -P "$MACOS_CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security`; `security set-key-partition-list -S apple-tool:,apple: -s -k <pw> <kc>`; prepend to `security list-keychains -d user -s`; extract cert (`openssl pkcs12 -in … -clcerts -nokeys -passin env:… -legacy` falling back without `-legacy`) and `sudo security add-trusted-cert -d -r trustRoot -p codeSign`; assert `security find-identity -v -p codesigning` lists `Claude Monitor Self-Signed`.
6. Build: `VERSION=$VERSION BUILD_NUMBER=${{ github.run_number }} ./make-dmg.sh`.
7. Guard: mount the dmg, `codesign -d -r-` on the app must contain `certificate leaf = H"`.
8. Upload: `gh release upload "$TAG" "dist/Claude-Monitor-$VERSION.dmg" --clobber` with `GH_TOKEN: ${{ github.token }}`.
9. Cleanup (`if: always()`): delete the temporary keychain and decoded files.

- [ ] **Step 1: Write** the workflow.
- [ ] **Step 2: Verify syntax** — `python3 -c "import yaml…"` is unavailable on stock macOS Python; use `ruby -ryaml -e 'YAML.load_file(".github/workflows/release-dmg.yml")'` → no error; run each `run:` block through `bash -n` (extracted with ruby) → no error; `actionlint` if installed.
- [ ] **Step 3: Docs** — README "🚀 Rilis" (developer section): one-time secret setup (Keychain Access export → `base64 -i cm.p12 | gh secret set MACOS_CERT_P12`, `gh secret set MACOS_CERT_PASSWORD`, delete the `.p12`), then `gh release create v1.0.0 --generate-notes` → dmg appears on the release in a few minutes; local `VERSION=… ./make-dmg.sh`. CLAUDE.md: workflow line + "CI signs with the same self-signed identity from secrets; never switch CI to ad-hoc".
- [ ] **Step 4: Commit** — `ci: build and attach the dmg when a release is published`.
