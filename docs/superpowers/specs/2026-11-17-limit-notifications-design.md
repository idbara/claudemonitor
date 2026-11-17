# Limit notifications — design

Date: 2026-11-17 · Status: draft, awaiting approval

## Intent

Bara wants macOS notifications at three moments for each account: when a limit
is **almost used up**, when a reset is **coming** (both meanings: a full account
will be usable again, and unused quota is about to be lost), and when a limit
**has reset**. Goal: never be surprised by a limit, and don't waste quota that
is about to expire (same spirit as the ★ rule).

## Goals

Four notification kinds, per account, for the **5-hour** and **weekly** windows:

| Kind | When | Condition | Example body |
|---|---|---|---|
| `nearLimit` | on refresh, when crossing 80%, then 95% | once per threshold per window (per `resets_at`) | "5 jam sudah 82% — reset 1j 10m lagi" |
| `usableSoon` (a) | 15 min before `resets_at` | utilization ≥ 80% | "Hampir penuh (96%) — reset 15 menit lagi" |
| `expiring` (b) | 30 min before `resets_at` | headroom ≥ 20% | "Sisa 60% hangus dalam 30 menit — pakai sekarang" |
| `didReset` | exactly at `resets_at` | utilization ≥ 80% at last data | "Limit 5 jam sudah reset — kembali 100%" |

Title = account label (+ window): e.g. "default · 5 jam", "kerja · mingguan".
Headroom for `expiring`: 5-hour → `100 − max(5h, 7d)`; weekly → `100 − 7d`
*(my call: for the 5-hour window the weekly cap still limits what can be used)*.

- A **Notifikasi** checkbox in the popover footer (default **on**) enables or
  disables everything; turning it off removes all pending notifications.
- Never the same notification twice for the same window instance.

## Non-goals

- Sonnet / Opus windows. Per-kind or per-threshold settings. Clicking a
  notification to open the popover. Sounds beyond the system default.

## Anti-goals

- Spam: repeats every refresh, or notifications for accounts whose quota is unknown.
- Wrong numbers: a scheduled notification must be re-planned on every refresh,
  so its text is at most one refresh (≤ 5 min) old.
- Extra calls to `oauth/usage` (strict 429s): notifications use existing refresh data only.

## Constraints / facts

- Data refreshes every 300 s; `QuotaWindow` has `utilization` and `resetsAt`.
- `UserNotifications` (`UNUserNotificationCenter`): needs one-time authorization;
  pending notifications with a `UNCalendarNotificationTrigger` are delivered by
  macOS at the exact time even if the app is not running. Adding a request with
  an existing identifier replaces it.
- The app is an `LSUIElement` agent, self-signed (stable designated requirement).
- No test target: pure logic is checked in `Checks/main.swift`.

## Approaches

- **A. Hybrid (chosen):** `nearLimit` checked on each refresh; the three
  time-based kinds are scheduled with exact triggers and re-planned on every
  refresh. Exact timing; works while the app is closed.
- B. Poll only: every condition checked on refresh. Simpler, but up to 5 min
  late ("15 menit lagi" may arrive at 11) and `didReset` waits for the next refresh.

## Design

### Pure planner — `NotificationPlanner` (`nonisolated`, in `Checks`)
Input: the visible `[AccountStatus]` (accounts with `quota != nil` only), `now`,
and a `NotificationLedger` (set of keys already delivered or scheduled).
Output:
- `immediate: [PlannedNote]` — post now (`nearLimit`; and time-based ones whose
  fire time already passed but were never scheduled/sent, e.g. first seen late —
  text uses the real remaining minutes; `didReset` is not sent late if more than
  15 min past *(my call)*).
- `scheduled: [PlannedNote]` — fire dates in the future.
- `ledgerKeys` to add.

`PlannedNote { id, title, body, fireDate? }`. Identifier and ledger key:
`cm.<service>.<window>.<kind>[.<threshold>].<resetsAt epoch>` — a new
`resets_at` means a new window instance, so dedup restarts naturally.
Rules from the table above; a time-based note whose fire time has passed and
whose key is in the ledger is skipped (already delivered).

### Notifier — `LimitNotifier` (`@MainActor`)
- Owns the toggle (`@AppStorage`-style `UserDefaults` key `notificationsEnabled`, default true)
  and the ledger (`UserDefaults`, pruned of keys whose `resetsAt` is > 8 days old).
- `update(accounts:)` is called by `AccountStore` after every refresh cycle:
  run the planner → `add` immediate requests (no trigger) → replace the pending
  `cm.*` set with the scheduled ones (remove pending `cm.*` ids not in the plan,
  add the rest) → save ledger.
- Authorization requested on first `update` while enabled; if denied, the
  footer shows "Izinkan notifikasi di Pengaturan Sistem › Notifikasi".
- Disabling removes all pending `cm.*` requests.

### UI
Footer gains `Toggle("Notifikasi", …)` (checkbox) next to "Buka saat login".

### Docs
README "Sorotan" + a short "Notifikasi" section; CLAUDE.md architecture line.

## Risks to verify early
- Notification delivery from the self-signed, LSUIElement Debug build (post one
  test notification right after authorization).
- A scheduled notification firing while the app is quit.

## Left to the builder
Exact wording beyond the examples, sound (default), how the countdown is formatted
(reuse `QuotaPopover.countdown`).
