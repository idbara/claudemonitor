# Multi-account + Background Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show quota for every Claude Code account on the Mac, recommend (★) the one to use next with a one-click copy of its launch command, and run as a Dock-less menu bar agent with an optional login item.

**Architecture:** Pure logic (Keychain-suffix hashing, labels, launch command, dedup, recommendation) lives in one Foundation/CryptoKit-only file, verified by a standalone `swiftc` check program (the Xcode project has no test target). Keychain discovery feeds an `AccountStore` that refreshes each account sequentially with the existing `QuotaClient`, and the popover renders one row per account.

**Tech Stack:** Swift 5 / SwiftUI `MenuBarExtra`, Security framework, CryptoKit, ServiceManagement (`SMAppService`), `swiftc` for logic checks.

**Spec:** `docs/superpowers/specs/2026-11-16-multi-account-background-design.md`

## Global Constraints

- Never read or use `refreshToken`; never write/modify any `Claude Code-credentials*` Keychain item.
- Tokens go only to `https://api.anthropic.com` (existing `QuotaClient`, unchanged headers).
- Keychain service names: default `Claude Code-credentials`; per config dir `Claude Code-credentials-<first 8 lowercase hex of sha256(absolute dir path, UTF-8, no trailing slash)>`.
- Refresh interval stays 300 s; `refreshIfStale(maxAge: 120)`; accounts fetched sequentially, never in parallel.
- Keep `CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = "Claude Monitor Self-Signed"`, `ENABLE_APP_SANDBOX = NO`.
- Project uses `PBXFileSystemSynchronizedRootGroup`: any `.swift` file placed in `ClaudeMonitor/` is compiled into the app automatically; files in `Checks/` are not.
- Default actor isolation is `MainActor` in the app target; mark the pure-logic types `nonisolated` so they compile identically under plain `swiftc`.
- UI strings and code comments in Indonesian (e.g. "Disalin ✓", "Buka saat login", "token kedaluwarsa — jalankan claude di akun ini").
- Build: `xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build` → `** BUILD SUCCEEDED **`.
- Logic checks: `swiftc ClaudeMonitor/AccountMath.swift Checks/main.swift -o "$TMPDIR/am-checks" && "$TMPDIR/am-checks"` → prints `ALL CHECKS PASSED`, exit 0.

## Review Focus

1. Config dir name with a space or shell metacharacter (`~/.claude my`) — the copied command must still work when pasted into zsh (quoted absolute path). → Task 1 check `launchCommandQuotesUnsafeNames`.
2. A 429 or 401 on one account — other accounts must still refresh and keep their data; the failing account keeps its last good quota on 429. → Task 4 manual step.
3. Two Keychain items for the same login (same profile uuid), one expired — show one row, the fresher token. → Task 1 check `dedupeKeepsLatestExpiry`.
4. Only one account exists — menu bar must look exactly like today (`5h 29%`, no ★, no name). → Task 1 check `menuLabelSingleAccount` + Task 5 manual step.
5. Every account at ≥100% — no ★ at all, and the label falls back to the default account. → Task 1 check `noRecommendationWhenAllFull`.

---

### Task 1: Pure account logic + check program

**Files:**
- Create: `ClaudeMonitor/AccountMath.swift`
- Create: `Checks/main.swift`

**Interfaces:**
- Produces (all `nonisolated`, in `AccountMath.swift`):
  - `enum AccountMath`
  - `static let defaultService = "Claude Code-credentials"`
  - `static func serviceName(forConfigDir absolutePath: String) -> String`
  - `static func suffix(ofService service: String) -> String?` — `nil` for the default service, `"c6b43821"` for `"Claude Code-credentials-c6b43821"`; services not starting with the default name are not passed in (caller filters).
  - `static func isClaudeService(_ service: String) -> Bool` — exactly default, or default + `"-"` + 8 hex.
  - `static func label(forDirName name: String) -> String` — strip leading `.claude-`, else leading `.`; `.claude-abati`→`abati`, `.claude`→`claude`, `.claude-`→`.claude-`.
  - `static func launchCommand(dirName: String?, home: String) -> String` — `nil` → `claude`; safe name (`[A-Za-z0-9._-]+`) → `CLAUDE_CONFIG_DIR=~/<name> claude`; otherwise `CLAUDE_CONFIG_DIR='<home>/<name>' claude` (single quotes; `'` escaped as `'\''`).
  - `struct DedupItem { let id: String; let uuid: String?; let expiresAt: Date? }`
  - `static func dedupe(_ items: [DedupItem]) -> Set<String>` — ids kept; items with same non-nil uuid collapse to the one with latest `expiresAt` (nil = oldest); nil-uuid items always kept.
  - `struct UsageSnapshot { let id: String; let fiveHour: Double?; let sevenDay: Double? }`
  - `static func recommend(_ snaps: [UsageSnapshot]) -> String?` — headroom `100 − max(fiveHour ?? 0, sevenDay ?? 0)`; highest wins; tie → lower `fiveHour ?? 0`, then lower id; `nil` if `snaps.count < 2` or best headroom ≤ 0.
  - `static func menuLabel(accountCount: Int, recommendedLabel: String?, fiveHour: Double?) -> String` — `fiveHour == nil` → `""`; count ≤ 1 or no recommendation → `"5h N%"`; else `"★<label> N%"`; N = rounded Int.

- [ ] **Step 1: Write `Checks/main.swift` with these checks** (a `check(_ cond: Bool, _ name: String)` helper that records failures; at end print `ALL CHECKS PASSED` or the failed names and `exit(1)`):

```swift
check(AccountMath.serviceName(forConfigDir: "/Users/bara/.claude-abati") == "Claude Code-credentials-c6b43821", "hashMatchesClaudeCode")
check(AccountMath.serviceName(forConfigDir: "/Users/bara/.claude") == "Claude Code-credentials-6ea33fa1", "hashDefaultDir")
check(AccountMath.suffix(ofService: "Claude Code-credentials") == nil, "suffixDefault")
check(AccountMath.suffix(ofService: "Claude Code-credentials-c6b43821") == "c6b43821", "suffixHex")
check(AccountMath.isClaudeService("Claude Code-credentials"), "isServiceDefault")
check(!AccountMath.isClaudeService("Claude Code-credentials-xyz"), "rejectsNonHex")
check(!AccountMath.isClaudeService("Other"), "rejectsOther")
check(AccountMath.label(forDirName: ".claude-abati") == "abati", "labelStrip")
check(AccountMath.label(forDirName: ".claude") == "claude", "labelBare")
check(AccountMath.launchCommand(dirName: nil, home: "/Users/b") == "claude", "launchDefault")
check(AccountMath.launchCommand(dirName: ".claude-abati", home: "/Users/b") == "CLAUDE_CONFIG_DIR=~/.claude-abati claude", "launchSafe")
check(AccountMath.launchCommand(dirName: ".claude my", home: "/Users/b") == "CLAUDE_CONFIG_DIR='/Users/b/.claude my' claude", "launchCommandQuotesUnsafeNames")
let t0 = Date(timeIntervalSince1970: 1000), t1 = Date(timeIntervalSince1970: 2000)
check(AccountMath.dedupe([.init(id: "a", uuid: "u", expiresAt: t0), .init(id: "b", uuid: "u", expiresAt: t1), .init(id: "c", uuid: nil, expiresAt: nil)]) == ["b", "c"], "dedupeKeepsLatestExpiry")
check(AccountMath.recommend([.init(id: "x", fiveHour: 78, sevenDay: 65), .init(id: "y", fiveHour: 12, sevenDay: 40)]) == "y", "recommendMostHeadroom")
check(AccountMath.recommend([.init(id: "x", fiveHour: 10, sevenDay: 90), .init(id: "y", fiveHour: 50, sevenDay: 50)]) == "y", "recommendUsesWorstWindow")
check(AccountMath.recommend([.init(id: "x", fiveHour: 100, sevenDay: 20), .init(id: "y", fiveHour: 30, sevenDay: 100)]) == nil, "noRecommendationWhenAllFull")
check(AccountMath.recommend([.init(id: "x", fiveHour: 10, sevenDay: 10)]) == nil, "noStarForSingleAccount")
check(AccountMath.menuLabel(accountCount: 1, recommendedLabel: nil, fiveHour: 29.4) == "5h 29%", "menuLabelSingleAccount")
check(AccountMath.menuLabel(accountCount: 2, recommendedLabel: "abati", fiveHour: 12.0) == "★abati 12%", "menuLabelStar")
check(AccountMath.menuLabel(accountCount: 2, recommendedLabel: nil, fiveHour: nil) == "", "menuLabelNoData")
```

- [ ] **Step 2: Run the checks — expect compile failure** (`AccountMath` undefined), using the Global Constraints command.
- [ ] **Step 3: Implement `AccountMath.swift`** per the Interfaces block. Hash with `CryptoKit.SHA256.hash(data: Data(path.utf8))`, hex lowercase, prefix 8.
- [ ] **Step 4: Run the checks** → `ALL CHECKS PASSED`.
- [ ] **Step 5: Build the app** (Global Constraints command) → `** BUILD SUCCEEDED **`.
- [ ] **Step 6: Commit** (include the spec and this plan)

```bash
git add ClaudeMonitor/AccountMath.swift Checks/main.swift docs/superpowers/specs/2026-11-16-multi-account-background-design.md docs/superpowers/plans/2026-11-16-multi-account-background.md
git commit -m "feat: add pure multi-account logic (keychain suffix, labels, dedup, recommendation) with swiftc checks"
```

---

### Task 2: Keychain discovery + per-service credential load

**Files:**
- Modify: `ClaudeMonitor/Credentials.swift`
- Create: `ClaudeMonitor/Account.swift`

**Interfaces:**
- Consumes: `AccountMath.isClaudeService`, `.suffix(ofService:)`, `.serviceName(forConfigDir:)`, `.label(forDirName:)`, `.launchCommand(dirName:home:)`.
- Produces:
  - `struct Account: Identifiable, Hashable { let id: String /* = service */; let service: String; let label: String; let command: String }`
  - `enum AccountDiscovery { static func discover(home: String = NSHomeDirectory()) -> [Account] }` — default item → label `default`, command `claude`; suffixed item matched to a dir directly in `home` whose name starts with `.claude` → label/command from that dir; unmatched suffix dropped (orphan). Sorted: `default` first, then label.
  - `Credentials.listServices() -> [String]` — `SecItemCopyMatching` with `kSecClassGenericPassword`, `kSecMatchLimitAll`, `kSecReturnAttributes: true` (no data → no prompt), filtered by `isClaudeService`, deduplicated.
  - `Credentials.load(service: String) throws -> ClaudeCredentials` — existing `load()` body parameterized by service; keep `load()` as `load(service: AccountMath.defaultService)`. Do not touch `refreshToken`.

- [ ] **Step 1: Implement `Credentials.listServices()` and `load(service:)`**.
- [ ] **Step 2: Implement `Account` + `AccountDiscovery.discover(home:)`** (directory listing via `FileManager.contentsOfDirectory(atPath:)` + `fileExists(atPath:isDirectory:)`; hash `home + "/" + name`).
- [ ] **Step 3: Build** → `** BUILD SUCCEEDED **`.
- [ ] **Step 4: Verify discovery against the Keychain.** Temporarily add `print("[ClaudeMonitor] akun:", AccountDiscovery.discover().map(\.label))` in `ClaudeMonitorApp.init`, run the built app from the terminal (`"$(xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -showBuildSettings | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/Claude Monitor.app/Contents/MacOS/Claude Monitor"`), expect a list containing `default` and `abati` and no orphan-only entries. Compare to `security dump-keychain | grep -o '"svce"<blob>="Claude Code[^"]*"' | sort -u`. Remove the print.
- [ ] **Step 5: Commit** — `feat: discover all Claude Code keychain accounts by config-dir hash`.

---

### Task 3: Profile uuid + profile cache

**Files:**
- Modify: `ClaudeMonitor/Profile.swift`
- Create: `ClaudeMonitor/ProfileCache.swift`

**Interfaces:**
- Produces:
  - `Profile` gains `let uuid: String?` (`account.uuid`) and becomes `Codable` with a memberwise-compatible encoding (encode flat keys `uuid, fullName, email, hasClaudeMax`; keep the existing nested decode for API JSON — use a separate `CachedProfile: Codable` struct if mixing is awkward).
  - `enum ProfileCache { static func get(_ service: String) -> CachedProfile?; static func set(_ p: CachedProfile, for service: String) }` — `UserDefaults.standard`, key `profile.<service>`, JSON-encoded.
  - `struct CachedProfile: Codable, Equatable { let uuid: String?; let fullName: String?; let email: String?; let hasClaudeMax: Bool }` with `init(_ p: Profile)`.

- [ ] **Step 1: Add `uuid` to `Profile` decoding and implement `CachedProfile` / `ProfileCache`.**
- [ ] **Step 2: Build** → `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Verify the field exists in the live API** with the CLAUDE.md `curl` recipe against `/api/oauth/profile` → JSON has `account.uuid`.
- [ ] **Step 4: Commit** — `feat: decode profile uuid and cache profiles per keychain item`.

---

### Task 4: `AccountStore` — multi-account refresh

**Files:**
- Create: `ClaudeMonitor/AccountStore.swift`
- Delete: `ClaudeMonitor/QuotaStore.swift` (its `QuotaState` enum moves into `AccountStore.swift` as `AccountState`)

**Interfaces:**
- Consumes: `AccountDiscovery.discover()`, `Credentials.load(service:)`, `QuotaClient.fetch/fetchProfile`, `ProfileCache`, `AccountMath.dedupe/recommend`.
- Produces (`@MainActor final class AccountStore: ObservableObject`):
  - `enum AccountState: Equatable { case loading, ok, expired, needsLogin, error(String) }`
  - `struct AccountStatus: Identifiable { let account: Account; var profile: CachedProfile?; var quota: QuotaUsage?; var state: AccountState; var expiresAt: Date?; var id: String { account.id } }`
  - `@Published private(set) var accounts: [AccountStatus]` — after dedup, sorted: recommended first, then `default`, then label.
  - `@Published private(set) var recommendedID: String?`
  - `@Published private(set) var lastUpdated: Date?`
  - `func refresh()`, `func refreshIfStale(maxAge: TimeInterval = 120)` — same semantics as old `QuotaStore`.
  - `var menuLabel: String` — via `AccountMath.menuLabel` using the recommended account, else the `default` account, else the first account with quota.

Behavior (copy from old `QuotaStore`, then extend):
- Each `refresh()`: re-run discovery; merge with existing statuses by id (keep last quota); for each account **sequentially**: load creds → if `expiresAt < now` set `.expired` and skip network; else fetch profile once if none cached (store via `ProfileCache`), then usage. Errors map per account exactly as today (`unauthorized → .needsLogin`, 429 keeps old quota and schedules one retry for that account only if it has no quota, network/other keep old quota). One account's error never stops the loop.
- After the loop: dedupe with `DedupItem(id:, uuid: profile?.uuid, expiresAt:)`; recommend over statuses with `state == .ok && quota != nil`.
- Timer: 300 s, as today.

- [ ] **Step 1: Implement `AccountStore.swift`; delete `QuotaStore.swift`; point `ClaudeMonitorApp` at `AccountStore` with a minimal temporary popover (list of `label: 5h N%`) so it builds.**
- [ ] **Step 2: Build** → `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Run and verify numbers.** For each shown account, run the CLAUDE.md `curl` recipe with `-s "<that account's service>"` and confirm 5h/7d match the popover (±1%). Approve each Keychain prompt with "Always Allow".
- [ ] **Step 4: Verify isolation of failures.** Temporarily force `QuotaClient.fetch` to throw `.rateLimited(retryAfter: 60)` for one service (e.g. `if service.hasSuffix("c6b43821")`), run: other accounts still update; the forced one keeps its previous quota after a second refresh. Remove the hack.
- [ ] **Step 5: Commit** — `feat: AccountStore refreshes every discovered account with dedup and recommendation`.

---

### Task 5: Popover UI + menu bar label

**Files:**
- Modify: `ClaudeMonitor/ClaudeMonitorApp.swift`

**Interfaces:**
- Consumes: `AccountStore` (`accounts`, `recommendedID`, `menuLabel`, `lastUpdated`, `refresh`, `refreshIfStale`); existing `meter(_:_:)` and `countdown(to:)` stay.

UI (spec § UI):
- Menu bar label: `Image("ClaudeLogo")` + `Text(store.menuLabel)`.
- Popover width 300. One `AccountRow` per status: leading `★` when `id == recommendedID`; label (bold); compact `5h N%` and `7d N%` with thin `ProgressView`s; caption = `profile.fullName ?? email` + `· reset dalam <countdown>` of 5h. `.expired`/`.needsLogin` rows: caption `⚠ token kedaluwarsa — jalankan claude di akun ini` (show last quota if any, dimmed). `.error(msg)` with no quota: caption `msg`. `.loading` with no quota: `Memuat…`.
- Tapping the row copies `account.command` via `NSPasteboard.general` (clearContents + setString) and shows `Disalin ✓` in place of the caption for ~1.5 s.
- Chevron button on the trailing edge toggles expanded state (per row, `@State Set<String>`); expanded shows the four `meter(...)` rows as today. Chevron tap must not trigger copy.
- Footer as today (Diperbarui…, Refresh ⌘R, Quit ⌘Q); the login toggle is added in Task 6.
- No accounts at all: `Tidak menemukan kredensial Claude Code`.

- [ ] **Step 1: Implement the rows, label, copy feedback and expand.**
- [ ] **Step 2: Build** → `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Manual check** — run; ★ is on the account with most headroom and the menu bar shows `★<label> N%`; click a row then `pbpaste` prints its command; chevron expands without copying. Temporarily make `discover()` return only the default account: label reads `5h N%`, no ★. Revert.
- [ ] **Step 4: Commit** — `feat: multi-account popover with recommendation and copy-launch-command`.

---

### Task 6: Background mode — no Dock icon + login item

**Files:**
- Modify: `ClaudeMonitor.xcodeproj/project.pbxproj` (both target build configurations, next to `INFOPLIST_KEY_CFBundleDisplayName`)
- Create: `ClaudeMonitor/LoginItem.swift`
- Modify: `ClaudeMonitor/ClaudeMonitorApp.swift` (footer toggle)

**Interfaces:**
- Produces: `@MainActor final class LoginItem: ObservableObject { @Published private(set) var isEnabled: Bool; @Published private(set) var needsApproval: Bool; func setEnabled(_ on: Bool); func reload() }` wrapping `SMAppService.mainApp` (`register()`/`unregister()`, `.status == .enabled` / `.requiresApproval`); errors leave state as reloaded from `.status`.

- [ ] **Step 1: Add `INFOPLIST_KEY_LSUIElement = YES;` to both target configs.**
- [ ] **Step 2: Implement `LoginItem` and the footer `Toggle("Buka saat login", …)`**; when `needsApproval`, a caption `Setujui di Pengaturan Sistem › Item Login`. Call `reload()` in popover `onAppear`.
- [ ] **Step 3: Build** → `** BUILD SUCCEEDED **`; `plutil -extract LSUIElement raw "<built app>/Contents/Info.plist"` → `true`.
- [ ] **Step 4: Manual check** — run: no Dock icon; toggle on → `sfltool dumpbtm | grep -i "Claude Monitor"` lists it; toggle off → gone. Confirm signing unchanged: `codesign -d -r- "<built app>"` shows `certificate leaf = H"…"`, not `cdhash`.
- [ ] **Step 5: Commit** — `feat: run as menu bar agent (LSUIElement) with optional login item`.

---

### Task 7: Docs

**Files:**
- Modify: `CLAUDE.md` (Architecture: `AccountMath`, `AccountDiscovery`, `AccountStore`, `ProfileCache`, `LoginItem`; Key facts: keychain naming rule, never touch refresh tokens, `LSUIElement`; the `Checks/` command)
- Modify: `README.md` (multi-account + ★ + copy command + Buka saat login, in Indonesian)

- [ ] **Step 1: Update both files.**
- [ ] **Step 2: Run the logic checks and the build one last time** → `ALL CHECKS PASSED`, `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Commit** — `docs: describe multi-account discovery and background mode`.
