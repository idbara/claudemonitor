# Limit Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS notifications per account for the 5-hour and weekly windows: near limit (80%/95%), usable again soon, unused quota expiring, and limit reset.

**Architecture:** A pure `NotificationPlanner` turns the refreshed account list + a ledger of already-sent keys into "post now" and "schedule at" notes (checked in `Checks/`). A `@MainActor LimitNotifier` posts/schedules them with `UNUserNotificationCenter`, re-planning the pending set after every refresh, and owns the on/off toggle shown in the popover.

**Tech Stack:** Swift / SwiftUI, UserNotifications.

**Spec:** `docs/superpowers/specs/2026-11-17-limit-notifications-design.md`

## Global Constraints

- Windows: 5-hour (`fiveHour`, label `5 jam`) and weekly (`sevenDay`, label `mingguan`) only; accounts with `quota != nil` only.
- Thresholds: nearLimit 80 and 95; usableSoon when utilization ≥ 80, fires `resetsAt − 15 min`; expiring when headroom ≥ 20, fires `resetsAt − 30 min`; didReset when utilization ≥ 80, fires at `resetsAt`, not sent if found more than 15 min late.
- Headroom: 5-hour `100 − max(5h, 7d)`; weekly `100 − 7d`.
- Identifier = ledger key: `cm.<service>.<window>.<kind>[.<threshold>].<Int(resetsAt epoch) or 0>`; kinds `nearLimit|usableSoon|expiring|didReset`; window `fiveHour|sevenDay`.
- Title `"<label> · <window label>"`. Bodies (exact): nearLimit `"Sudah <p>% terpakai — reset <countdown> lagi"` (without ` — reset …` when no resetsAt); usableSoon `"Hampir penuh (<p>%) — reset <m> menit lagi"`; expiring `"Sisa <h>% hangus dalam <m> menit — pakai sekarang"`; didReset `"Limit <window label> sudah reset — kembali 100%"`. `<countdown>` = `Xj Ym` / `Ym` / `<1m`; `<m>` = minutes rounded up, minimum 1.
- Toggle `Notifikasi`, `UserDefaults` key `notificationsEnabled`, default `true`; ledger key `notificationLedger` (`[String]`), pruned of entries whose epoch is older than 8 days.
- No new calls to `oauth/usage`. Comments/UI strings in Indonesian.
- Checks: command in `Checks/main.swift` header (+ `ClaudeMonitor/NotificationPlanner.swift`) → `ALL CHECKS PASSED`; build → `** BUILD SUCCEEDED **`.

## Review Focus

1. Usage jumps from 70% to 97% between refreshes — exactly one nearLimit note (95), and 80 is marked sent too. → Task 1 `nearLimitJumpSendsOnlyHighest`.
2. Mac wakes after a scheduled time already passed and the note was scheduled earlier — no duplicate post. → Task 1 `scheduledPastSkippedWhenInLedger`.
3. Window resets (new `resetsAt`) — notifications start again for the new window. → Task 1 `newWindowRestartsDedup`.
4. Expiring note scheduled, then usage climbs so headroom < 20 — note disappears from the plan (notifier removes it). → Task 1 `expiringDroppedWhenHeadroomFalls`.
5. Account without quota data (expired, never fetched) — no notes. → Task 1 `noQuotaNoNotes`.

---

### Task 1: `NotificationPlanner` (pure)

**Files:**
- Create: `ClaudeMonitor/NotificationPlanner.swift`
- Modify: `Checks/main.swift` (tests + add the file to the header compile command)

**Interfaces:**
- Produces (`nonisolated`):
  - `struct PlannedNote: Equatable { let id: String; let title: String; let body: String; let fireDate: Date? }` — `fireDate == nil` means post now.
  - `enum NotificationPlanner { static func plan(_ accounts: [AccountStatus], now: Date, ledger: Set<String>) -> (immediate: [PlannedNote], scheduled: [PlannedNote], newKeys: Set<String>); static func countdown(_ seconds: TimeInterval) -> String }`
  - Rules: a time-based note whose fire time is in the future is always in `scheduled` (and its key in `newKeys`); if the fire time has passed (but `resetsAt` not, for usableSoon/expiring) it goes to `immediate` only when its key is not in `ledger`, with the real remaining minutes; nearLimit for the highest crossed threshold not in `ledger` goes to `immediate`, and every crossed threshold's key goes to `newKeys`.

- [ ] **Step 1: Write checks** (helper builds an `AccountStatus` with `fiveHour`/`sevenDay` utilization and `resetsAt` offsets from `n0`, service `"svc"`, label `"kerja"`):
  - `nearLimitAt82`: 5h 82%, reset +70 min → one immediate, title `"kerja · 5 jam"`, body `"Sudah 82% terpakai — reset 1j 10m lagi"`, id ends `.nearLimit.80.<epoch>`.
  - `nearLimitJumpSendsOnlyHighest`: 97% → one immediate (`.nearLimit.95.`), `newKeys` contains both `.80.` and `.95.` keys.
  - `nearLimitNotRepeated`: same input with those keys in ledger → no immediate nearLimit.
  - `usableSoonScheduled`: 96%, reset +120 min → scheduled usableSoon at `reset − 15 min`, body `"Hampir penuh (96%) — reset 15 menit lagi"`; also scheduled didReset at reset, body `"Limit 5 jam sudah reset — kembali 100%"`.
  - `expiringScheduled`: 5h 40%, 7d 10%, reset +120 → scheduled expiring at `reset − 30 min`, body `"Sisa 60% hangus dalam 30 menit — pakai sekarang"`; no usableSoon/didReset.
  - `expiringLateImmediate`: same but reset +10 min, ledger empty → immediate expiring with `"… dalam 10 menit …"`.
  - `scheduledPastSkippedWhenInLedger`: reset +10, expiring key in ledger → no expiring note at all.
  - `didResetLateWithin15`: 90%, reset −5 min, ledger empty → immediate didReset; reset −20 min → none.
  - `newWindowRestartsDedup`: ledger has keys for epoch E; same account with resetsAt E+5h at 82% → immediate nearLimit.
  - `expiringDroppedWhenHeadroomFalls`: 5h 85% reset +120 → no expiring note.
  - `weeklyWindowUsesOwnHeadroom`: 7d 70% reset +60 → title `"kerja · mingguan"`, expiring body `"Sisa 30% hangus …"`.
  - `noQuotaNoNotes`: `quota == nil` → all empty.
  - `countdownFormat`: `countdown(4200) == "1j 10m"`, `countdown(600) == "10m"`, `countdown(20) == "<1m"`.
- [ ] **Step 2: Run checks** → compile error (`NotificationPlanner` missing).
- [ ] **Step 3: Implement** `NotificationPlanner.swift`.
- [ ] **Step 4: Run checks** → `ALL CHECKS PASSED`; build → `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Commit** (with spec + plan) — `feat: pure planner for limit notifications`.

---

### Task 2: `LimitNotifier`, wiring, toggle

**Files:**
- Create: `ClaudeMonitor/LimitNotifier.swift`
- Modify: `ClaudeMonitor/AccountStore.swift` (owns `let notifier = LimitNotifier()`; calls `notifier.update(accounts: accounts)` once after each refresh cycle's loop, and after a per-account retry)
- Modify: `ClaudeMonitor/ClaudeMonitorApp.swift` (footer toggle)

**Interfaces:**
- Consumes: `NotificationPlanner.plan`, `PlannedNote`.
- Produces: `@MainActor final class LimitNotifier: ObservableObject { @Published private(set) var enabled: Bool; @Published private(set) var denied: Bool; func setEnabled(_ on: Bool); func update(accounts: [AccountStatus]) }`
  - `update`: if disabled → return. Request authorization (`.alert, .sound`) once; if not granted → `denied = true`, return. Plan with the stored ledger → add immediate requests (trigger `nil`) → get pending requests, remove those with id prefix `cm.` not in the scheduled set, add scheduled ones with `UNCalendarNotificationTrigger(dateMatching: all components to the second, repeats: false)` → save ledger ∪ newKeys, pruned (> 8 days old).
  - `setEnabled(false)` removes all pending `cm.*` requests.
- UI: in `QuotaPopover` footer, `Toggle("Notifikasi", …).toggleStyle(.checkbox)` bound to `store.notifier`; when `denied`, caption `"Izinkan notifikasi di Pengaturan Sistem › Notifikasi"`. Observe the notifier with `@ObservedObject`.

- [ ] **Step 1: Implement** the three changes.
- [ ] **Step 2: Build** → `** BUILD SUCCEEDED **`; checks still `ALL CHECKS PASSED`.
- [ ] **Step 3: Delivery spike** — temporarily, in `LimitNotifier.update`, also post one immediate note `"Tes notifikasi Claude Monitor"`; run the Debug app; Bara confirms it appears (and approves the permission prompt). Then schedule a temporary test note 60 s ahead, quit the app, and Bara confirms it still appears. Remove the temporary code; ledger the result.
- [ ] **Step 4: Live check** — run the app; `UNUserNotificationCenter.getPendingNotificationRequests` count logged once (temporary) matches the plan for the real accounts (e.g. didReset/usableSoon for an account ≥ 80%); remove the log.
- [ ] **Step 5: Commit** — `feat: limit notifications (near limit, usable soon, expiring, reset)`.

---

### Task 3: Docs

**Files:** Modify `README.md`, `CLAUDE.md`.

- [ ] **Step 1:** README — add a "🔔 Notifikasi" row to "Sorotan" and a short section with the four kinds (table from the spec), the toggle, and that scheduled ones arrive even when the app is closed; remove "notifikasi saat mendekati limit" from "Belum ada"; add `NotificationPlanner.swift` / `LimitNotifier.swift` to the developer table and the checks command. CLAUDE.md — architecture lines for both files and the updated checks command.
- [ ] **Step 2:** Checks `ALL CHECKS PASSED`, Python tests `OK`, build `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Commit** — `docs: document limit notifications`.
