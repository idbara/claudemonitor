# Usage Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hardcoded placeholder data in ClaudeMonitor's menu bar popover with real Claude Code usage parsed from local `~/.claude/projects/**/*.jsonl` logs, showing today/per-model/5-hour-block/month tokens and equivalent cost.

**Architecture:** Pure-value types (`UsageEntry`, `Pricing`, `UsageStats`/`UsageAggregator`) hold all parsing and math; a `LogParser` reads JSONL off the main thread; a `UsageStore` `ObservableObject` orchestrates background refresh and publishes stats; the `MenuBarExtra` UI in `ClaudeMonitorApp.swift` renders them.

**Tech Stack:** Swift 5 / SwiftUI, macOS 26.5, no external dependencies. `Foundation.JSONSerialization` for parsing.

**Testing note:** This project has no test target (per spec). Verification per task = the app compiles via `xcodebuild`. Final task = manual cross-check of "today"/"month" totals against `npx ccusage`. The logic types are isolated and pure so an XCTest target can be added later without restructuring.

**Build command used throughout:**
```bash
xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build
```
Expected on success: ends with `** BUILD SUCCEEDED **`.

---

### Task 1: UsageEntry model

**Files:**
- Create: `ClaudeMonitor/UsageEntry.swift`

- [ ] **Step 1: Create the value type**

```swift
//
//  UsageEntry.swift
//  ClaudeMonitor
//

import Foundation

/// Satu baris usage dari log Claude Code (~/.claude/projects/**/*.jsonl).
struct UsageEntry {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    /// "<message.id>:<requestId>" bila keduanya ada; dipakai untuk dedup.
    let dedupKey: String?

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run the build command above.
Expected: `** BUILD SUCCEEDED **`. (The new file is auto-included by Xcode's file-system-synchronized group.)

- [ ] **Step 3: Commit**

```bash
git add ClaudeMonitor/UsageEntry.swift
git commit -m "feat: add UsageEntry model"
```

---

### Task 2: Pricing table

**Files:**
- Create: `ClaudeMonitor/Pricing.swift`

- [ ] **Step 1: Create the pricing table and cost function**

```swift
//
//  Pricing.swift
//  ClaudeMonitor
//

import Foundation

// PRICING: update when Anthropic rates change. USD per 1.000.000 token.
enum Pricing {
    struct Rates {
        let input: Double
        let output: Double
        let cacheWrite: Double
        let cacheRead: Double
    }

    /// Cocokkan berdasarkan substring nama model supaya id bertanggal tetap kena.
    static func rates(for model: String) -> Rates {
        let m = model.lowercased()
        if m.contains("opus") {
            return Rates(input: 15.0, output: 75.0, cacheWrite: 18.75, cacheRead: 1.50)
        }
        if m.contains("haiku") {
            return Rates(input: 1.0, output: 5.0, cacheWrite: 1.25, cacheRead: 0.10)
        }
        if m.contains("sonnet") {
            return Rates(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30)
        }
        // fallback (kelas sonnet)
        return Rates(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30)
    }

    /// Equivalent cost (USD) untuk satu entri.
    static func cost(for entry: UsageEntry) -> Double {
        let r = rates(for: entry.model)
        return (Double(entry.inputTokens) * r.input
              + Double(entry.outputTokens) * r.output
              + Double(entry.cacheCreationTokens) * r.cacheWrite
              + Double(entry.cacheReadTokens) * r.cacheRead) / 1_000_000.0
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClaudeMonitor/Pricing.swift
git commit -m "feat: add model pricing table and equivalent-cost calc"
```

---

### Task 3: Log parser

**Files:**
- Create: `ClaudeMonitor/LogParser.swift`

- [ ] **Step 1: Create the parser**

```swift
//
//  LogParser.swift
//  ClaudeMonitor
//

import Foundation

/// Membaca dan mem-parse log JSONL Claude Code menjadi UsageEntry.
enum LogParser {
    /// ~/.claude/projects
    static func projectsDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Parse semua entri usage dari file yang dimodifikasi sejak `since`.
    /// Dijalankan di luar main thread oleh pemanggil.
    static func parseEntries(since: Date) -> [UsageEntry] {
        let dir = projectsDirectory()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        var entries: [UsageEntry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let mtime = values?.contentModificationDate, mtime < since { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            content.enumerateLines { line, _ in
                if let entry = parseLine(line, iso: iso, isoNoFrac: isoNoFrac) {
                    entries.append(entry)
                }
            }
        }
        return entries
    }

    private static func parseLine(
        _ line: String,
        iso: ISO8601DateFormatter,
        isoNoFrac: ISO8601DateFormatter
    ) -> UsageEntry? {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return nil }

        let model = message["model"] as? String ?? "unknown"
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

        let tsString = obj["timestamp"] as? String ?? ""
        let timestamp = iso.date(from: tsString)
            ?? isoNoFrac.date(from: tsString)
            ?? Date(timeIntervalSince1970: 0)

        var dedupKey: String?
        if let mid = message["id"] as? String, let rid = obj["requestId"] as? String {
            dedupKey = "\(mid):\(rid)"
        }

        return UsageEntry(
            timestamp: timestamp,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheCreation,
            cacheReadTokens: cacheRead,
            dedupKey: dedupKey
        )
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClaudeMonitor/LogParser.swift
git commit -m "feat: parse Claude Code JSONL logs into usage entries"
```

---

### Task 4: Stats aggregation

**Files:**
- Create: `ClaudeMonitor/UsageStats.swift`

- [ ] **Step 1: Create stats types and aggregator**

```swift
//
//  UsageStats.swift
//  ClaudeMonitor
//

import Foundation

struct ModelUsage: Identifiable {
    let model: String
    let tokens: Int
    let cost: Double
    var id: String { model }
}

struct UsageStats {
    var todayTokens: Int = 0
    var todayCost: Double = 0
    var monthTokens: Int = 0
    var monthCost: Double = 0
    var blockTokens: Int = 0
    var blockCost: Double = 0
    var blockStart: Date?
    var perModel: [ModelUsage] = []

    var isEmpty: Bool { monthTokens == 0 }

    static let empty = UsageStats()
}

enum UsageAggregator {
    /// Bangun UsageStats dari entri. `now`/`calendar` di-inject agar deterministik.
    static func aggregate(entries: [UsageEntry], now: Date, calendar: Calendar = .current) -> UsageStats {
        // Dedup berdasarkan dedupKey; entri tanpa key selalu dihitung.
        var seen = Set<String>()
        let deduped = entries.filter { entry in
            guard let key = entry.dedupKey else { return true }
            return seen.insert(key).inserted
        }

        let startOfDay = calendar.startOfDay(for: now)
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? startOfDay

        var stats = UsageStats()
        var perModelTokens: [String: Int] = [:]
        var perModelCost: [String: Double] = [:]

        for entry in deduped {
            let cost = Pricing.cost(for: entry)
            let tokens = entry.totalTokens

            if entry.timestamp >= startOfMonth {
                stats.monthTokens += tokens
                stats.monthCost += cost
            }
            if entry.timestamp >= startOfDay {
                stats.todayTokens += tokens
                stats.todayCost += cost
                perModelTokens[entry.model, default: 0] += tokens
                perModelCost[entry.model, default: 0] += cost
            }
        }

        stats.perModel = perModelTokens.map { model, tokens in
            ModelUsage(model: model, tokens: tokens, cost: perModelCost[model] ?? 0)
        }.sorted { $0.cost > $1.cost }

        if let block = activeBlock(deduped: deduped, now: now, calendar: calendar) {
            stats.blockStart = block.start
            for entry in deduped where entry.timestamp >= block.start && entry.timestamp < block.end {
                stats.blockTokens += entry.totalTokens
                stats.blockCost += Pricing.cost(for: entry)
            }
        }

        return stats
    }

    /// Block 5-jam ala ccusage: start = aktivitas pertama dibulatkan ke bawah ke
    /// jam bulat; block 5 jam; block baru bila entri keluar window atau ada gap >5 jam.
    /// Mengembalikan block yang memuat `now`, atau nil bila tidak ada yang aktif.
    private static func activeBlock(
        deduped: [UsageEntry],
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        let sorted = deduped.map(\.timestamp).sorted()
        guard let first = sorted.first else { return nil }

        let blockDuration: TimeInterval = 5 * 60 * 60
        var blockStart = floorToHour(first, calendar: calendar)
        var lastTimestamp = first

        for ts in sorted {
            let sinceStart = ts.timeIntervalSince(blockStart)
            let sinceLast = ts.timeIntervalSince(lastTimestamp)
            if sinceStart > blockDuration || sinceLast > blockDuration {
                blockStart = floorToHour(ts, calendar: calendar)
            }
            lastTimestamp = ts
        }

        let blockEnd = blockStart.addingTimeInterval(blockDuration)
        if now >= blockStart && now < blockEnd {
            return (blockStart, blockEnd)
        }
        return nil
    }

    private static func floorToHour(_ date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: comps) ?? date
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClaudeMonitor/UsageStats.swift
git commit -m "feat: aggregate usage entries into today/month/block/per-model stats"
```

---

### Task 5: Usage store (background refresh)

**Files:**
- Create: `ClaudeMonitor/UsageStore.swift`

- [ ] **Step 1: Create the observable store**

```swift
//
//  UsageStore.swift
//  ClaudeMonitor
//

import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published var stats: UsageStats = .empty
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false

    private var timer: Timer?

    init() {
        refresh()
        // Auto-refresh tiap 60 detik.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let now = Date()
        let calendar = Calendar.current
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now

        Task.detached(priority: .utility) {
            let entries = LogParser.parseEntries(since: startOfMonth)
            let stats = UsageAggregator.aggregate(entries: entries, now: now, calendar: calendar)
            await MainActor.run {
                self.stats = stats
                self.lastUpdated = Date()
                self.isRefreshing = false
            }
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClaudeMonitor/UsageStore.swift
git commit -m "feat: add UsageStore with background + timed refresh"
```

---

### Task 6: Wire the UI

**Files:**
- Modify: `ClaudeMonitor/ClaudeMonitorApp.swift` (full replace)

- [ ] **Step 1: Replace the app entry point and add the popover view**

Replace the entire contents of `ClaudeMonitor/ClaudeMonitorApp.swift` with:

```swift
//
//  ClaudeMonitorApp.swift
//  ClaudeMonitor
//
//  Created by Bara Ramadhan on 30/05/26.
//

import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        // Label menu bar = equivalent cost hari ini.
        MenuBarExtra {
            UsagePopover(store: store)
        } label: {
            Image(systemName: "cpu")
            Text("≈ $\(store.stats.todayCost, specifier: "%.2f")")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Isi popover menu bar.
struct UsagePopover: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Code Usage")
                .font(.headline)
            Text("≈ equivalent cost (subscription — bukan tagihan nyata)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            if store.stats.isEmpty {
                Text("Belum ada data usage")
                    .foregroundColor(.secondary)
            } else {
                amountRow("Hari ini", tokens: store.stats.todayTokens, cost: store.stats.todayCost)

                if let start = store.stats.blockStart {
                    VStack(alignment: .leading, spacing: 2) {
                        amountRow("Sesi 5-jam", tokens: store.stats.blockTokens, cost: store.stats.blockCost)
                        Text("mulai \(start, format: .dateTime.hour().minute())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Text("Sesi 5-jam")
                        Spacer()
                        Text("tidak aktif").foregroundColor(.secondary)
                    }
                }

                Divider()
                Text("Per model (hari ini)")
                    .font(.subheadline).bold()
                ForEach(store.stats.perModel) { m in
                    HStack {
                        Text(shortModel(m.model))
                        Spacer()
                        Text("≈ $\(m.cost, specifier: "%.2f")")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }

                Divider()
                amountRow("Bulan ini", tokens: store.stats.monthTokens, cost: store.stats.monthCost)
            }

            Divider()
            if let updated = store.lastUpdated {
                Text("Diperbarui \(updated, format: .dateTime.hour().minute().second())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            HStack {
                Button("Refresh") { store.refresh() }
                    .keyboardShortcut("r")
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding()
        .frame(width: 260)
    }

    @ViewBuilder
    private func amountRow(_ title: String, tokens: Int, cost: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing) {
                Text("≈ $\(cost, specifier: "%.2f")").bold()
                Text("\(tokens.formatted()) tok")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func shortModel(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        return model
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClaudeMonitor/ClaudeMonitorApp.swift
git commit -m "feat: render live usage stats in menu bar popover"
```

---

### Task 7: Manual verification

**Files:** none (verification only)

- [ ] **Step 1: Run the app**

Open `ClaudeMonitor.xcodeproj` in Xcode and press ⌘R, or build & launch the
`.app` from the `xcodebuild` output. The menu bar should show `≈ $<today cost>`.
Click it — the popover shows Hari ini / Sesi 5-jam / Per model / Bulan ini.

- [ ] **Step 2: Cross-check totals against ccusage**

```bash
npx ccusage@latest daily --json
```
Compare ccusage's most recent day total cost/tokens with the app's "Hari ini".
Expected: same order of magnitude. Exact match is not required (ccusage pulls
live LiteLLM pricing; this app uses the embedded table), but a large divergence
(e.g. 10x) signals a bug in parsing/pricing — investigate before declaring done.

- [ ] **Step 3: Verify empty/edge behavior**

Confirm the app does not crash and shows "Belum ada data usage" when there is no
data for the current month (can be checked by reasoning about the code path —
`stats.isEmpty` when `monthTokens == 0`).
