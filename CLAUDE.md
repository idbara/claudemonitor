# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ClaudeMonitor is a native macOS **menu bar** app (SwiftUI) that displays the **Claude subscription quota of every Claude Code account on the Mac** — the same data Claude Code's own `/usage` shows — as live progress meters. It fetches real utilization percentages straight from Anthropic; there is no cost/token estimation.

The app lives entirely in the menu bar via `MenuBarExtra` with `.menuBarExtraStyle(.window)` (popover-style); the menu bar label shows the 5-hour utilization (`5h 29%` with one account, `★abati 12%` for the recommended account when there are several). It runs as an agent (`INFOPLIST_KEY_LSUIElement = YES`, no Dock icon) with an optional login item. `ContentView.swift` is the default Xcode "Hello, world!" view and is **not wired into the app** — the live UI is `QuotaPopover` in `ClaudeMonitorApp.swift`.

### Architecture

- `Credentials.swift` — `listServices()` enumerates Keychain generic-password items named `Claude Code-credentials` / `Claude Code-credentials-<8 hex>` (attributes only → no prompt); `load(service:)` reads `claudeAiOauth.accessToken` + `expiresAt` from one item (one-time approval prompt per item).
- `AccountMath.swift` — pure, `nonisolated` logic: keychain service name for a config dir, labels, launch command (quoted when the dir name is unsafe), dedup by profile uuid (keep latest `expiresAt`), ★ recommendation (`100 − max(5h, 7d)`, needs ≥2 accounts with data), menu label.
- `Account.swift` — `AccountDiscovery.discover()` matches keychain suffixes to directories directly in `$HOME` whose name starts with `.claude`; unmatched suffixes (orphans) are dropped. `build(services:dirNames:home:)` is the pure part.
- `ProfileCache.swift` — `CachedProfile` (uuid, name, email, hasClaudeMax) per keychain service in `UserDefaults` (`profile.<service>`), so expired accounts keep a name/uuid.
- `QuotaClient.swift` — `async` `URLSession` GET to **`https://api.anthropic.com/api/oauth/usage`** with headers `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`. Maps 401/403 → `.unauthorized`.
- `QuotaUsage.swift` — `Decodable` model. The response has windows `five_hour`, `seven_day`, `seven_day_sonnet`, `seven_day_opus` (others ignored), each `{ utilization: Double 0–100, resets_at: ISO-8601 } | null`; a `null` window decodes to `nil` and its meter is hidden.
- `AccountStore.swift` — `@MainActor ObservableObject`; each `refresh()` re-runs discovery, then refreshes accounts **sequentially** (expired token → `.expired` without a network call; profile fetched once per launch per account), publishes `accounts` (deduped, ★ first), `recommendedID`, `lastUpdated`. Per-account `AccountState` `.loading/.ok/.expired/.needsLogin/.error`; a 429 keeps old data and retries only that account. Refreshes on launch, popover `onAppear` (if >120s stale), every 300s, and the manual button. `arrange(_:)` / `menuLabel(visible:recommendedID:)` are pure statics.
- `AccountsExport.swift` — after every `publish()`, writes `~/Library/Application Support/ClaudeMonitor/accounts.json` (`updatedAt`, `recommended`, per account `id, label, configDir, state, fiveHour, sevenDay, fiveHourResetsAt, headroom`) for `cc`. No tokens or emails.
- `scripts/cc.py` — Python 3 stdlib wrapper around `claude` (installed as `~/.local/bin/cc` by `cc setup`). A `StopFailure` hook (matcher `rate_limit`, command `~/.local/bin/cc hook`) writes a handoff (`$TMPDIR/cc-<pid>.json`, env `CC_HANDOFF`/`CC_WRAPPER_PID`) and SIGTERMs claude; the run loop relaunches `claude --resume <id> lanjutkan` with the next account's `CLAUDE_CONFIG_DIR`. `cc setup` **restructures account dirs**: shared entries become symlinks to `~/.claude` (Troupe ADR-0004), originals go to `~/.claude-switch/backup/`; only `~/.claude-*` dirs with a matching Keychain item name are touched (e.g. `~/.claude-mem` is plugin data, not an account). Tests: `python3 -m unittest discover -s scripts -p 'test_*.py'`.
- `LoginItem.swift` — "Buka saat login" via `SMAppService.mainApp` (registers the app's current path — enable from `/Applications`).

### Key facts (don't regress these)

- **App Sandbox is disabled** (`ENABLE_APP_SANDBOX = NO` in both configs). Required: a sandboxed app cannot read another app's Keychain item or make network calls without entitlements.
- **Stable code signing is required, NOT ad-hoc** (`CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = "Claude Monitor Self-Signed"` in both target configs). Keychain "Always Allow" trust is pinned to the app's designated requirement; an ad-hoc signature's DR is `cdhash H"…"` which changes every rebuild, so macOS re-prompts for the login password on every build. With the self-signed cert the DR is `identifier "id.misindo.ClaudeMonitor" and certificate leaf = H"…"` — constant across rebuilds, so the prompt appears once and never again. **Do not revert to Automatic/ad-hoc.** On a fresh machine/clone the cert must exist in the login keychain (`security find-identity -v -p codesigning` must list it); recreate it with openssl (codeSigning EKU) → `security import` (non-empty PKCS12 password, `-macalg sha1`) → `security add-trusted-cert -r trustRoot -p codeSign`.
- Keychain naming (Claude Code's own): default `Claude Code-credentials`; with `CLAUDE_CONFIG_DIR=<path>` → `Claude Code-credentials-<first 8 hex of sha256(absolute path)>`.
- **Never use the refresh token or write to any `Claude Code-credentials*` item** — refresh tokens rotate, so using one would break Claude Code's login for that account.
- The OAuth token is sent **only** to `api.anthropic.com`. Token refresh is **not** implemented — on 401 the UI shows "login ulang di Claude Code" (Claude Code keeps the Keychain token fresh).

To re-verify after changes, `curl` the same endpoint with the token and compare to the popover:
```bash
TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w | python3 -c "import sys,json;print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])")
curl -sS https://api.anthropic.com/api/oauth/usage -H "Authorization: Bearer $TOKEN" -H "anthropic-beta: oauth-2025-04-20" -H "anthropic-version: 2023-06-01" | python3 -m json.tool
```

> History: an earlier iteration parsed `~/.claude/projects/**/*.jsonl` locally to estimate cost (see `docs/superpowers/specs|plans/2026-05-30-usage-integration*`). That pipeline was removed in favor of the live quota endpoint.

## Build & run

No CocoaPods/SPM/Carthage dependencies — pure Xcode project, build with `xcodebuild` or open in Xcode.

```bash
# Build (Debug) from CLI
xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build

# Run: open in Xcode and ⌘R (menu bar apps don't show a Dock window — look in the status bar)
open ClaudeMonitor.xcodeproj
```

There is **no test target**. The pure logic is covered by a standalone check program — run it after changing `AccountMath`/`Account`/`AccountStore`/`Profile*`:

```bash
swiftc ClaudeMonitor/AccountMath.swift ClaudeMonitor/Account.swift ClaudeMonitor/Credentials.swift ClaudeMonitor/Profile.swift ClaudeMonitor/ProfileCache.swift ClaudeMonitor/QuotaUsage.swift ClaudeMonitor/QuotaClient.swift ClaudeMonitor/AccountStore.swift Checks/main.swift -o "$TMPDIR/am-checks" && "$TMPDIR/am-checks"   # → ALL CHECKS PASSED
```

Types used by these checks are marked `nonisolated` because the app target defaults to `MainActor` isolation while plain `swiftc` does not.

## Project facts

- **Target / scheme:** `ClaudeMonitor` (single app target, no test or extension targets)
- **Bundle ID:** `id.misindo.ClaudeMonitor`
- **Deployment target:** macOS 26.5 — uses recent SwiftUI APIs; keep this in mind when suggesting APIs.
- **Swift:** 5.0
- Code comments and the `print` log string are in **Indonesian** — match this when editing existing comments in `ClaudeMonitorApp.swift`.
