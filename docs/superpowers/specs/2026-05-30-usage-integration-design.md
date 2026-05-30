# ClaudeMonitor — Usage Integration Design

**Date:** 2026-05-30
**Status:** Approved

## Goal

Replace the hardcoded placeholder data in the menu bar popover with real Claude
Code usage read from this Mac's local logs. The user is on a Claude
subscription (not pay-per-token API), so the dollar figure is an **equivalent
API cost** ("≈ what these tokens would cost at API rates"), not actual billing.
Tokens are the literal metric; cost is a value/intensity gauge.

## Data source

Local Claude Code transcripts: `~/.claude/projects/**/*.jsonl`.

Each assistant message line is a JSON object. Relevant fields:

- `timestamp` — ISO 8601 string (entry time).
- `requestId` — API request id.
- `message.id` — assistant message id.
- `message.model` — e.g. `claude-haiku-4-5-20251001`.
- `message.usage` — `{ input_tokens, output_tokens, cache_creation_input_tokens,
  cache_read_input_tokens, ... }`.

Lines without `message.usage` (user turns, tool results, summaries) are skipped.
There is **no cost field** in the logs — cost is computed locally from a pricing
table.

## Approach

**Native Swift parser**, no external dependencies. Read and parse the JSONL
files directly, compute cost from an embedded pricing table. (Rejected
alternative: shelling out to `npx ccusage --json` — requires Node/npx and
network, fragile.)

## Components (new files under `ClaudeMonitor/`)

### `UsageEntry.swift`
A single usage record:
```
struct UsageEntry {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let dedupKey: String?   // "<message.id>:<requestId>" when both present
}
```
`totalTokens` = sum of the four token counts.

### `Pricing.swift`
Static table mapping a model to per-million-token USD rates for input, output,
cache-write (5m), and cache-read. Lookup is by substring match on the model id
(e.g. contains `opus`, `sonnet`, `haiku`) with a sane fallback, so dated model
ids still resolve. Embedded rates (USD per 1M tokens), to be updated manually
when Anthropic pricing changes:

| Family   | input | output | cache write | cache read |
|----------|-------|--------|-------------|------------|
| Opus     | 15.00 | 75.00  | 18.75       | 1.50       |
| Sonnet   |  3.00 | 15.00  |  3.75       | 0.30       |
| Haiku    |  1.00 |  5.00  |  1.25       | 0.10       |
| fallback |  3.00 | 15.00  |  3.75       | 0.30       |

`func cost(for entry: UsageEntry) -> Double` computes equivalent cost.
A `// PRICING: update when Anthropic rates change` comment marks the table.

### `LogParser.swift`
- Resolve `~/.claude/projects`. If absent → return empty.
- Enumerate `*.jsonl` recursively; filter to files with `mtime >= startOfMonth`
  (the widest window any view needs), to avoid parsing all ~1,200+ files.
- Parse each file line-by-line; decode each line; keep only lines with
  `message.usage`; build `UsageEntry`.
- Tolerate malformed lines / missing fields → skip silently.
- Runs off the main thread.

### `UsageStats.swift`
Aggregation result published to the UI:
```
struct ModelUsage { let model: String; let tokens: Int; let cost: Double }
struct UsageStats {
    let todayTokens: Int;   let todayCost: Double
    let monthTokens: Int;   let monthCost: Double
    let blockTokens: Int;   let blockCost: Double; let blockStart: Date?
    let perModel: [ModelUsage]          // today, sorted by cost desc
    let isEmpty: Bool
}
```

Aggregation rules:
- **Dedup**: drop entries whose `dedupKey` was already seen (logs can be
  duplicated across files — matches ccusage behavior). Entries without a
  dedupKey are always counted.
- **Today**: entries with `timestamp` in the current local calendar day.
- **Month**: entries since the start of the current local calendar month.
- **Per-model**: today's entries grouped by model family/id.
- **5-hour block (ccusage-style)**: sort entries by time; block start = first
  activity timestamp floored to the hour; each block spans 5 hours; a new block
  begins when an entry falls outside the current block window. The **active
  block** is the one whose 5-hour window contains `now`; if none, block totals
  are zero and `blockStart` is nil.

### `UsageStore.swift`
`@MainActor final class UsageStore: ObservableObject`:
- `@Published var stats: UsageStats`
- `@Published var lastUpdated: Date?`
- `@Published var isRefreshing: Bool`
- `func refresh()` — parse + aggregate on a background task, publish on main.
- Refresh triggers: on popover appear, a 60-second `Timer`, and the manual
  Refresh button.

### `ClaudeMonitorApp.swift` (modified)
- Hold a `@StateObject private var store = UsageStore()`.
- Menu bar label: `MenuBarExtra` title shows today's equivalent cost
  (e.g. `≈ $1.25`); icon stays `cpu`.
- Popover content sections:
  1. **Hari ini** — tokens + `≈ $cost`.
  2. **Sesi 5-jam** — tokens since `blockStart` (+ start time), or "tidak aktif".
  3. **Per model** — list of `ModelUsage` (today).
  4. **Bulan ini** — tokens + `≈ $cost`.
  - Footer: last-updated time; Refresh (⌘R) and Quit (⌘Q) buttons.
- Empty state (`stats.isEmpty`): show "Belum ada data usage".
- Keep Indonesian comments/labels to match existing code style.

`ContentView.swift` remains unused (default scaffold); left untouched.

## Error handling
- Missing `~/.claude/projects` or no files → empty state, no crash.
- Corrupt/usage-less JSONL lines → skipped silently.
- Unknown model id → fallback pricing row.

## Out of scope (YAGNI)
Historical charts, persistence/DB, limit notifications, multi-machine
aggregation, live pricing fetch. Can follow later.

## Testing
No test target exists. Verify manually by building/running and comparing the
"today" / "month" totals against `npx ccusage` output as a sanity check.
