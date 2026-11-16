# Multi-account + background mode — design

Date: 2026-11-16
Status: draft, awaiting approval

## Intent

Bara uses several Claude accounts, each launched through its own
`CLAUDE_CONFIG_DIR` (e.g. `~/.claude-abati`). The monitor currently shows only
the default account. Goals, in Bara's words: **see used limit on every account**
and, if possible, **pick which account to use next**. The app should also live
fully in the background: no Dock icon, starts at login.

## Goals

- Show 5-hour and weekly utilization for every Claude Code account found on the Mac.
- Recommend one account (★) as "use this next" and make switching one click
  (copy the launch command).
- Menu bar label reflects the recommended account.
- No Dock icon; optional "Buka saat login" toggle.

## Non-goals

- Logging into accounts from the app, or storing tokens of our own.
- Token refresh (unchanged from today).
- Launching a terminal / running `claude` for the user — we only copy the command.
- Manual account management UI (add/rename/hide). Discovery is automatic.

## Anti-goals (failure even if it "works")

- **Breaking Claude Code's login.** The app must never use a refresh token or
  write to any `Claude Code-credentials*` item. Refresh tokens rotate; using one
  would invalidate Claude Code's copy.
- Sending a token anywhere but `api.anthropic.com`.
- Hammering `oauth/usage` (strict 429s) — N accounts must not mean N× aggressive polling.
- Showing junk rows: duplicates of one account, or dead leftovers of temp config dirs.

## Constraints / facts established

- Claude Code stores the default account in Keychain generic password
  `Claude Code-credentials`. With `CLAUDE_CONFIG_DIR=<path>` it uses
  `Claude Code-credentials-<first 8 hex of sha256(<absolute path>)>`.
  Verified: `sha256("/Users/bara/.claude-abati")[:8] = c6b43821`, which exists.
  This Mac has the default item + 7 suffixed items; most suffixes match no
  existing `~/.claude*` directory (leftover temp dirs).
- Each item's data is JSON `{claudeAiOauth: {accessToken, expiresAt(ms), ...}}`.
- `GET /api/oauth/profile` returns `account.{uuid, email, full_name, display_name, has_claude_max, ...}`.
- Reading each item's data prompts once per item; with the stable self-signed
  identity, "Always Allow" persists across rebuilds (see CLAUDE.md).
- Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`), so `LSUIElement`
  is set via `INFOPLIST_KEY_LSUIElement = YES` in both configs.
- Deployment target macOS 26.5: `SMAppService.mainApp` available.

## Approaches considered

**Account discovery**
- **A. Automatic (chosen):** enumerate all `Claude Code-credentials*` items;
  label them by hashing `~/.claude*` dirs. Zero setup, new accounts appear by
  themselves. Cost: several Keychain prompts on first run.
- B. Manual list of config dirs in settings. Fewer prompts, but re-configure
  every time an account is added.

**Choosing the next account**
- **A. Recommendation + copy command (chosen):** ★ on the account with most
  headroom, click a row to copy `CLAUDE_CONFIG_DIR=~/.claude-x claude`; menu bar
  shows the ★ account.
- B. Display only, menu bar stays on default. Simpler, but the user compares
  numbers manually — misses the "pick next" goal.

Bara picked A + A.

## Design

### Discovery (`AccountDiscovery`)
1. Query generic passwords with `kSecMatchLimitAll` + `kSecReturnAttributes`
   (no data → no prompt); keep items whose service is `Claude Code-credentials`
   or starts with `Claude Code-credentials-`.
2. Build a suffix→directory map: for each directory directly in `$HOME` whose
   name starts with `.claude`, compute `sha256(absolutePath).hex.prefix(8)`.
   Only `$HOME` is scanned *(my call)*: config dirs elsewhere would show as
   orphans and be dropped.
3. Each item becomes an `Account`:
   - default item → label `default`, command `claude`, configDir `nil`.
   - suffix matches a dir `~/.claude-foo` → label `foo` (strip `.claude-`/`.claude`
     prefix; fall back to the full dir name), command
     `CLAUDE_CONFIG_DIR=~/.claude-foo claude`.
   - suffix matches no dir → **orphan**: dropped. (Its config dir is gone, so
     the user can't launch it anyway.)
4. Re-run discovery on every refresh cycle (cheap, attributes only) so new
   accounts appear without restart.

### Per-account fetch
- Read token (data) per account → existing `QuotaClient.fetch` and, once per
  account, `fetchProfile`. Cache profile `{uuid, email, fullName, hasMax}` in
  `UserDefaults` keyed by service name so an expired account still has a name.
- If `expiresAt` is in the past, skip the network call and mark the account
  `expired` (no wasted 401s).
- Fetch accounts **sequentially** within a refresh, keep the 5-minute interval
  and the existing `refreshIfStale(120s)` / 429 retry rules, per account.

### Dedup
Accounts sharing the same profile `uuid` collapse to one row; keep the one whose
token expires latest (freshest). Accounts without a known uuid are not merged.

### Per-account state
`loading | ok(quota) | expired | needsLogin (401) | error(msg)`; like today, a
transient failure keeps the last good quota.

### Recommendation (★)
Among accounts with quota data: headroom = `100 − max(fiveHour, sevenDay)`
(missing windows count as 0). Highest headroom wins; tie → lower `fiveHour`.
No ★ if every account is at ≥ 100. *(my call)*

### UI
- **Menu bar label:** `★<label> <5h>%` of the recommended account, e.g.
  `★abati 12%`. With a single account: today's `5h 29%` (no ★, no name).
- **Popover** (width ~300): one row per account, sorted ★ first then by label:
  `★ abati   5h ▓░░ 12%  7d 40%` plus a small caption with name/email and the
  5h reset countdown. Expired/needsLogin rows show
  `⚠ token kedaluwarsa — jalankan claude di akun ini`.
- **Click a row** → copy its command to the clipboard; row briefly shows
  "Disalin ✓".
- A disclosure chevron on each row expands the full meters (5h, 7d, Sonnet 7d,
  Opus 7d with reset countdowns) — reuses today's `meter(...)`. *(my call: keeps
  the Sonnet/Opus detail without crowding the list)*
- Footer: "Diperbarui HH:MM:SS", **☑ Buka saat login**, Refresh, Quit.

### Background
- `INFOPLIST_KEY_LSUIElement = YES` in Debug and Release → no Dock icon, no app
  menu (Quit stays in the popover).
- "Buka saat login" toggle backed by `SMAppService.mainApp`
  (`register()`/`unregister()`; reflect `.status`). If status is
  `.requiresApproval`, show a hint to approve in System Settings › Login Items.
  Default: off. Note: registration pins the app's current path — install to
  `/Applications` (the .dmg flow) before enabling.

### Code layout (indicative)
- `Credentials.swift` → add `Account` discovery + load-by-service.
- New `AccountStore` (replaces single-account `QuotaStore` state with
  `[AccountStatus]`), reusing `QuotaClient` unchanged.
- `ClaudeMonitorApp.swift` → new popover rows + login toggle; comments in Indonesian.
- `LoginItem.swift` → thin `SMAppService` wrapper.

## Left to the builder

- Exact visual styling of rows, the "Disalin" feedback timing, sorting of non-★ rows.
- How to verify with no test target: build, run, compare each account's numbers
  against the `curl` recipe in CLAUDE.md using that account's service name.
