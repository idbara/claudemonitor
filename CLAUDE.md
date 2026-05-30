# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ClaudeMonitor is a native macOS **menu bar** app (SwiftUI) that displays the user's **Claude subscription quota** — the same data Claude Code's own `/usage` shows — as live progress meters. It fetches real utilization percentages straight from Anthropic; there is no cost/token estimation.

The app lives entirely in the menu bar via `MenuBarExtra` with `.menuBarExtraStyle(.window)` (popover-style); the menu bar label shows the 5-hour session utilization (e.g. `5h 29%`). `ContentView.swift` is the default Xcode "Hello, world!" view and is **not wired into the app** — the live UI is `QuotaPopover` in `ClaudeMonitorApp.swift`.

### Architecture

- `Credentials.swift` — reads Claude Code's OAuth token from the macOS **Keychain** generic-password item `Claude Code-credentials` (`claudeAiOauth.accessToken`) via the Security framework. Reading it triggers a one-time macOS approval prompt.
- `QuotaClient.swift` — `async` `URLSession` GET to **`https://api.anthropic.com/api/oauth/usage`** with headers `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`. Maps 401/403 → `.unauthorized`.
- `QuotaUsage.swift` — `Decodable` model. The response has windows `five_hour`, `seven_day`, `seven_day_sonnet`, `seven_day_opus` (others ignored), each `{ utilization: Double 0–100, resets_at: ISO-8601 } | null`; a `null` window decodes to `nil` and its meter is hidden.
- `QuotaStore.swift` — `@MainActor ObservableObject`; `refresh()` loads creds → fetches → publishes `quota` + a `QuotaState` (`.loading/.ok/.needsLogin/.error`). Refreshes on launch, popover `onAppear`, every 60s, and the manual button.

### Key facts (don't regress these)

- **App Sandbox is disabled** (`ENABLE_APP_SANDBOX = NO` in both configs). Required: a sandboxed app cannot read another app's Keychain item or make network calls without entitlements.
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

There is **no test target** in this project, so there are no tests to run.

## Project facts

- **Target / scheme:** `ClaudeMonitor` (single app target, no test or extension targets)
- **Bundle ID:** `id.misindo.ClaudeMonitor`
- **Deployment target:** macOS 26.5 — uses recent SwiftUI APIs; keep this in mind when suggesting APIs.
- **Swift:** 5.0
- Code comments and the `print` log string are in **Indonesian** — match this when editing existing comments in `ClaudeMonitorApp.swift`.
