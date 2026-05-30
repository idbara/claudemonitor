# ClaudeMonitor — Quota Meters (from Anthropic) Design

**Date:** 2026-05-30
**Status:** Approved

## Goal

Replace the local-log cost/token display with live **subscription quota meters**
fetched directly from Anthropic — the same data Claude Code's own `/usage`
shows. Three meters requested by the user (session 5h, weekly 7d, weekly Sonnet
7d), plus weekly Opus when present. Each meter shows a utilization percentage
and a reset countdown.

This supersedes the usage-integration feature
(`2026-05-30-usage-integration-design.md`): the log-parsing pipeline is removed.

## Data source (verified working)

`GET https://api.anthropic.com/api/oauth/usage`

Headers:
- `Authorization: Bearer <accessToken>`
- `anthropic-beta: oauth-2025-04-20`
- `anthropic-version: 2023-06-01`

Verified response shape (200):
```json
{
  "five_hour":        {"utilization": 26.0, "resets_at": "2026-05-30T17:50:01.019646+00:00"},
  "seven_day":        {"utilization": 52.0, "resets_at": "2026-06-05T09:00:01.019675+00:00"},
  "seven_day_opus":   null,
  "seven_day_sonnet": {"utilization": 2.0,  "resets_at": "2026-06-05T09:00:00.019682+00:00"},
  "seven_day_oauth_apps": null, "seven_day_cowork": null, "seven_day_omelette": null,
  "tangelo": null, "iguana_necktie": null, "omelette_promotional": null,
  "extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": null,
                  "utilization": null, "currency": null, "disabled_reason": null}
}
```

- `utilization` is a percentage 0–100 (already relative to the plan's limit — no
  limit-guessing needed).
- A window value may be `null` (no usage / not applicable) → hide that meter.
- We consume only: `five_hour`, `seven_day`, `seven_day_sonnet`, `seven_day_opus`.
  All other keys are ignored.

### Credentials

macOS Keychain generic-password item, service **`Claude Code-credentials`**.
Its JSON has `claudeAiOauth: { accessToken, refreshToken, expiresAt, scopes,
subscriptionType, rateLimitTier }`. We use `accessToken` (`sk-ant-oat01…`).
`expiresAt` is epoch milliseconds.

Reading another app's Keychain item triggers a **one-time macOS approval prompt**
("ClaudeMonitor wants to use Claude Code-credentials" → Always Allow). The token
is sent **only** to `api.anthropic.com`, nowhere else.

## Sandbox / entitlements change (required)

The project currently sets `ENABLE_APP_SANDBOX = YES` (both Debug and Release,
no `.entitlements` file). A sandboxed app **cannot** read another app's Keychain
item and cannot make outbound network calls without a network-client
entitlement. Therefore: set **`ENABLE_APP_SANDBOX = NO`** in both build
configurations in `ClaudeMonitor.xcodeproj/project.pbxproj`. (Acceptable for a
local personal tool; no hardened runtime is enabled.)

## Components (new files under `ClaudeMonitor/`)

### `Credentials.swift`
```
struct ClaudeCredentials { let accessToken: String; let expiresAt: Date? }
enum CredentialsError: Error { case notFound, unreadable }
enum Credentials {
    static func load() throws -> ClaudeCredentials
}
```
Uses Security framework `SecItemCopyMatching` with `kSecClass =
kSecClassGenericPassword`, `kSecAttrService = "Claude Code-credentials"`,
`kSecReturnData = true`. Decodes the JSON, reads `claudeAiOauth.accessToken` and
`claudeAiOauth.expiresAt` (ms → Date). Throws `.notFound` if the item/keys are
absent, `.unreadable` on decode failure.

### `QuotaUsage.swift`
```
struct QuotaWindow { let utilization: Double; let resetsAt: Date? }
struct QuotaUsage {
    let fiveHour: QuotaWindow?
    let sevenDay: QuotaWindow?
    let sevenDaySonnet: QuotaWindow?
    let sevenDayOpus: QuotaWindow?
}
```
`Decodable`. The raw API window object is `{ "utilization": Double, "resets_at":
String? }`; `resets_at` is ISO-8601 with fractional seconds + offset (parsed with
a formatter that tolerates fractional seconds). A `null` window decodes to `nil`.

### `QuotaClient.swift`
```
enum QuotaClientError: Error { case unauthorized, network(Error), badResponse }
enum QuotaClient {
    static func fetch(accessToken: String) async throws -> QuotaUsage
}
```
Builds the `GET` with the three headers, runs `URLSession.shared.data(for:)`.
HTTP 401/403 → `.unauthorized`; non-2xx → `.badResponse`; transport failure →
`.network`. Decodes the body into `QuotaUsage`.

### `QuotaStore.swift`
```
enum QuotaState { case loading, ok, needsLogin, error(String) }
@MainActor final class QuotaStore: ObservableObject {
    @Published var quota: QuotaUsage?
    @Published var state: QuotaState
    @Published var lastUpdated: Date?
    func refresh()   // load creds → fetch → publish; maps errors to state
}
```
`refresh()` runs the credential read + network fetch off the main actor and
publishes results back on main. Triggers: popover `onAppear`, a 60-second
`Timer`, and the manual Refresh button. `CredentialsError.notFound`/`.unreadable`
→ `.error(...)`; `QuotaClientError.unauthorized` → `.needsLogin`; other →
`.error(...)`.

### `ClaudeMonitorApp.swift` (rewrite)
- `@StateObject private var store = QuotaStore()`.
- **Menu bar label:** `five_hour` utilization as a percent, e.g. `5h 26%`
  (icon `cpu`). If unavailable, show the icon only.
- **Popover:** a `QuotaMeter` row per non-nil window in order — Session (5 jam),
  Weekly (7 hari), Weekly Sonnet (7 hari), Weekly Opus (7 hari, only if non-nil):
  - title, `ProgressView(value: utilization/100)`, trailing `NN%`,
  - caption "reset dalam Xj Ym" derived from `resetsAt` and now (hidden if
    `resetsAt` is nil).
- State handling: `.loading` → "Memuat…"; `.needsLogin` → "Sesi kedaluwarsa —
  login ulang di Claude Code"; `.error(msg)` → show msg (e.g. "Tidak bisa baca
  kredensial Claude Code").
- Footer: last-updated time; Refresh (⌘R) and Quit (⌘Q).

### Files to delete (no longer used)
`UsageEntry.swift`, `Pricing.swift`, `LogParser.swift`, `UsageStats.swift`,
`UsageStore.swift`. The prior spec/plan docs stay as history.

## Error handling summary
- Keychain item missing / unreadable → `.error` with a clear message; no crash.
- Token expired or rejected (401/403) → `.needsLogin`.
- Network down / timeout → `.error("Tidak bisa terhubung ke Anthropic")`.
- Any window `null` → that meter is hidden.

## Out of scope (YAGNI)
Self-managed OAuth token refresh, historical charts, `extra_usage`/credit
display, near-limit notifications, keeping the old log/cost pipeline.

## Testing
No test target. Verify by building/running: the popover shows three (or four)
meters with percentages matching `https://api.anthropic.com/api/oauth/usage`
(cross-check with a manual `curl` using the same token, or with Claude Code's
`/usage`). Confirm the Keychain approval prompt appears once and that denying it
yields the credential-error state rather than a crash.
