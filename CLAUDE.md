# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ClaudeMonitor is a native macOS **menu bar** app (SwiftUI) that displays **Claude Code** usage parsed from this Mac's local logs (`~/.claude/projects/**/*.jsonl`). The user is on a Claude **subscription**, so the dollar figures are **equivalent API cost** ("≈ what these tokens would cost at API rates"), not real billing — tokens are the literal metric.

The app lives entirely in the menu bar via `MenuBarExtra` with `.menuBarExtraStyle(.window)` (popover-style); the menu bar label shows today's equivalent cost. `ContentView.swift` is the default Xcode "Hello, world!" view and is **not wired into the app** — the live UI is `UsagePopover` in `ClaudeMonitorApp.swift`.

### Architecture (data pipeline)

Pure value types hold the logic; `UsageStore` is the only async coordinator. Layers:

- `LogParser.swift` — enumerates `~/.claude/projects/**/*.jsonl`, filters by file mtime (≥ start of month) so the ~1,200+ files aren't all read, parses each line with `JSONSerialization`, keeps only lines with `message.usage`.
- `UsageEntry.swift` — one parsed usage record (tokens per bucket, model, timestamp, `dedupKey`).
- `Pricing.swift` — embedded per-model rate table (USD per 1M tokens) + `cost(for:)`. **Manually maintained** — `// PRICING:` marks it.
- `UsageStats.swift` — `UsageAggregator.aggregate(entries:now:calendar:)` dedups, then computes today / month / per-model / active 5-hour-block stats. `now`/`calendar` are injected for determinism.
- `UsageStore.swift` — `@MainActor ObservableObject`; runs parse+aggregate off-main via `Task.detached`, publishes `stats`; refreshes on launch, on popover `onAppear`, every 60s, and via the manual button.

### Two correctness facts verified against `ccusage` (don't regress these)

- **Dedup by `message.id` alone**, not `message.id`+`requestId`. Resumed sessions replay earlier assistant messages *without* a `requestId` but with the same `message.id`; keying on both let replays through and inflated totals ~45%. Verified: matches `ccusage` within ~1%.
- **Opus 4.6/4.8 are priced 5/25/6.25/0.50** (input/output/cache-write/cache-read per 1M) — ⅓ of legacy Opus 4 rates. Sonnet and Haiku match the standard table. Cross-checked per-model against `ccusage`.

To re-verify after changes: `npx -y ccusage@latest daily --json` and compare today's/month totals to the popover (same order of magnitude; per-model cost should match closely).

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
