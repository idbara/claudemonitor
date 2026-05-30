# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ClaudeMonitor is a native macOS **menu bar** app (SwiftUI) that displays Claude API usage — daily cost and token totals. It is an early-stage scaffold: the data shown is hardcoded placeholder `@State`, and the intended design is to fetch real usage from a **server proxy / usage database endpoint** via `URLSession` (see the `fetchUsageData()` stub in `ClaudeMonitorApp.swift`).

The app lives entirely in the menu bar via `MenuBarExtra` with `.menuBarExtraStyle(.window)` (popover-style). `ContentView.swift` is the default Xcode-generated "Hello, world!" view and is **not currently wired into the app** — the live UI is the `MenuBarExtra` closure in `ClaudeMonitorApp.swift`.

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
