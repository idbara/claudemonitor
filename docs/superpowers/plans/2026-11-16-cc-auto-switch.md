# `cc` Auto-Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `cc` command that runs Claude Code and, when a turn fails on a rate limit, relaunches the same session on the account with the most room; plus `cc setup` to share history/settings across accounts like Troupe, and an `accounts.json` export from Claude Monitor.

**Architecture:** Claude Monitor writes `accounts.json` after each refresh. `scripts/cc.py` (Python 3, stdlib only) is installed as `~/.local/bin/cc`; its `StopFailure` hook writes a handoff file and SIGTERMs claude, and the run loop relaunches `claude --resume <id> "lanjutkan"` under another `CLAUDE_CONFIG_DIR`. Pure logic is unit-tested with `unittest`; the Swift export is covered by the existing `Checks/` program.

**Tech Stack:** Swift (existing app), Python 3 stdlib (`json`, `os`, `signal`, `subprocess`, `hashlib`, `shutil`, `unittest`).

**Spec:** `docs/superpowers/specs/2026-11-16-cc-auto-switch-design.md`

## Global Constraints

- Never read or write OAuth tokens, `.credentials*`, `.claude.json`, or any `Claude Code-credentials*` Keychain item (Swift and Python).
- Nothing is deleted by setup: replaced entries move to `~/.claude-switch/backup/<label>-<YYYYmmdd-HHMMSS>/<name>`.
- Shared dirs: `projects skills plugins rules plans file-history agents commands`; shared files: `settings.json CLAUDE.md`.
- Monitor export path: `~/Library/Application Support/ClaudeMonitor/accounts.json`; stale after 15 min.
- Handoff path: `$TMPDIR/cc-<cc pid>.json`; env vars `CC_WRAPPER_PID`, `CC_HANDOFF`; limited store `~/.claude-switch/limited.json`; default limited duration 3600 s when no reset time is known.
- Relaunch: `claude --resume <session_id> lanjutkan` + kept flags `--model`, `--permission-mode`, `--dangerously-skip-permissions`, `--add-dir` (with their values); max switches per run = number of accounts.
- Hook entry in `~/.claude/settings.json`: `{"matcher": "rate_limit", "hooks": [{"type": "command", "command": "~/.local/bin/cc hook"}]}` under `hooks.StopFailure`.
- User-facing strings (Indonesian): `cc: limit di <a> → lanjut di <b>`, `cc: semua akun penuh — reset paling cepat <HH:MM>`.
- `CC_CLAUDE_BIN` env overrides the claude executable (tests only; default `claude` on PATH).
- Python tests: `python3 -m unittest discover -s scripts -p 'test_*.py'` → `OK`. Swift checks: the command in `Checks/main.swift` header → `ALL CHECKS PASSED`. Build: `xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build` → `** BUILD SUCCEEDED **`.

## Review Focus

1. The hook fires in a plain `claude` session (no `CC_*` env) — must do nothing, kill nothing. → Task 3 `test_hook_noop_without_wrapper_env`.
2. All accounts limited — `cc` prints the reset message and exits 0, never loops. → Task 4 `test_run_stops_when_no_account_left`.
3. `accounts.json` missing or stale — falls back to linked dirs instead of failing. → Task 2 `test_load_monitor_stale_returns_none`, `test_fallback_accounts_only_linked_dirs`.
4. `cc setup` run twice — second run changes nothing and creates no new backups. → Task 5 `test_setup_idempotent`.
5. Relaunch must happen in the session's `cwd` from the handoff, not cc's own cwd. → Task 4 `test_run_relaunches_in_handoff_cwd`.

---

### Task 1: Monitor exports `accounts.json`

**Files:**
- Modify: `ClaudeMonitor/Account.swift` (add `configDir`)
- Create: `ClaudeMonitor/AccountsExport.swift`
- Modify: `ClaudeMonitor/AccountStore.swift` (`publish()` writes the file)
- Modify: `Checks/main.swift` (+ add `ClaudeMonitor/AccountsExport.swift` to its compile command)

**Interfaces:**
- Produces:
  - `Account.configDir: String?` — absolute path; `nil` for default. Set in `AccountDiscovery.build` (`"\(home)/\(dir)"`).
  - `nonisolated enum AccountsExport { static func json(visible: [AccountStatus], recommendedID: String?, now: Date) -> Data; static var defaultURL: URL; static func write(_ data: Data, to url: URL) }` — `write` creates the directory and writes atomically, errors ignored.
  - JSON shape (keys exact): `updatedAt` (ISO-8601 UTC), `recommended` (id or null), `accounts[]` with `id, label, configDir, state, fiveHour, sevenDay, fiveHourResetsAt, headroom`. `state` ∈ `ok|expired|needsLogin|error|loading`; `headroom = 100 − max(fiveHour ?? 0, sevenDay ?? 0)` or `null` when quota is nil.

- [ ] **Step 1: Add checks** — `discoveryConfigDir` (`built.last?.configDir == "/Users/bara/.claude-abati"`, `built.first?.configDir == nil`), and `exportShape`: decode `AccountsExport.json(visible: arranged.visible, recommendedID: arranged.recommendedID, now: Date(timeIntervalSince1970: 0))` with `JSONSerialization` and assert `recommended == "svc-abati"`, `accounts[0]["headroom"] == 60.0`, `accounts[0]["state"] == "ok"`, the expired account's `"state" == "expired"`, `updatedAt == "1970-01-01T00:00:00Z"`, and no key named `email` or `accessToken` anywhere.
- [ ] **Step 2: Run checks** → compile error (`configDir` / `AccountsExport` missing).
- [ ] **Step 3: Implement** `configDir`, `AccountsExport`, and call `AccountsExport.write(AccountsExport.json(...), to: AccountsExport.defaultURL)` at the end of `AccountStore.publish()`.
- [ ] **Step 4: Run checks** → `ALL CHECKS PASSED`; **build** → `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Live check** — run the app; `python3 -m json.tool ~/Library/Application\ Support/ClaudeMonitor/accounts.json` shows `default` and `abati` with `configDir` set and no tokens.
- [ ] **Step 6: Commit** (with spec + plan) — `feat: export accounts.json from the monitor for cc`.

---

### Task 2: `cc.py` core — account choice

**Files:**
- Create: `scripts/cc.py`, `scripts/test_cc.py`

**Interfaces:**
- Produces (module `cc`, imported in tests via `sys.path.insert(0, scripts_dir); import cc`):
  - `DEFAULT_SERVICE = "Claude Code-credentials"`
  - `service_for(config_dir: str | None) -> str` — default for `None`, else `DEFAULT_SERVICE + "-" + sha256(path).hexdigest()[:8]`.
  - `load_monitor(path: Path, now: float) -> list[dict] | None` — `None` if missing, unreadable, or `updatedAt` older than 900 s.
  - `fallback_accounts(home: Path) -> list[dict]` — `{"id", "label", "configDir", "state": "unknown", "headroom": None}` for `~/.claude` (label `default`, configDir `None`) plus each `~/.claude-*` whose `projects` is a symlink resolving to `home/.claude/projects`; label = name without `.claude-`; default first, then label.
  - `load_limited(path) -> dict[str, float]`, `mark_limited(path, account_id, until: float) -> None` (drops expired entries on write).
  - `pick_next(accounts: list[dict], current_id: str, limited: dict[str, float], now: float) -> dict | None` — exclude current, unexpired limited, `needsLogin`; rank `ok` with `headroom > 0` by headroom desc then `fiveHour` asc; then `expired` and `unknown` in input order.
  - `pick_start(accounts, limited, now) -> dict | None` — same ranking without a current account.

- [ ] **Step 1: Write tests**

```python
def test_service_for_matches_claude_code(self):
    self.assertEqual(cc.service_for("/Users/bara/.claude-abati"), "Claude Code-credentials-c6b43821")
    self.assertEqual(cc.service_for(None), "Claude Code-credentials")
def test_pick_next_prefers_most_headroom(self):  # ok 62 vs ok 20 → 62
def test_pick_next_skips_current_limited_and_needs_login(self):
def test_pick_next_expired_after_ok(self):  # [expired x, ok y headroom 5] → y; only expired → x
def test_pick_next_none_when_nothing_left(self):
def test_load_monitor_stale_returns_none(self):  # updatedAt now-901 → None; now-10 → list
def test_load_monitor_missing_returns_none(self):
def test_fallback_accounts_only_linked_dirs(self):  # tmp home: .claude/projects, .claude-a/projects→symlink, .claude-b/projects real dir → [default, a]
def test_mark_limited_roundtrip_and_expiry(self):
```

- [ ] **Step 2: Run** `python3 -m unittest discover -s scripts -p 'test_*.py'` → errors (`cc` has no attributes).
- [ ] **Step 3: Implement** the functions above in `scripts/cc.py` (shebang `#!/usr/bin/env python3`, executable bit).
- [ ] **Step 4: Run** → `OK`.
- [ ] **Step 5: Commit** — `feat(cc): account selection core`.

---

### Task 3: `cc hook` — handoff + stop claude

**Files:**
- Modify: `scripts/cc.py`, `scripts/test_cc.py`

**Interfaces:**
- Produces:
  - `find_claude_pid(start_pid: int, wrapper_pid: int, parent_of: Callable[[int], int | None]) -> int | None` — walk up from `start_pid`; return the pid whose parent is `wrapper_pid`; `None` after 32 steps or at pid ≤ 1.
  - `parent_of_ps(pid: int) -> int | None` — `ps -o ppid= -p <pid>`.
  - `handle_hook(payload: dict, env: Mapping[str, str], kill: Callable[[int, int], None], parent_of, self_pid: int) -> bool` — no-op (`False`) unless `CC_HANDOFF` and `CC_WRAPPER_PID` are set and `payload["error"] == "rate_limit"`; writes `{session_id, cwd, error, error_details, at}` to `CC_HANDOFF`, then `kill(pid, SIGTERM)`; returns `True`.
  - CLI: `cc hook` reads stdin JSON → `handle_hook(..., os.kill, parent_of_ps, os.getpid())`; always exits 0.

- [ ] **Step 1: Write tests** — `test_find_claude_pid_walks_to_child_of_wrapper` (table `{50:40, 40:30, 30:10}`, wrapper 10 → 30), `test_find_claude_pid_none_when_not_descendant`, `test_hook_noop_without_wrapper_env` (env `{}` → returns False, `kill` never called, no file), `test_hook_ignores_other_errors` (`error: "overloaded"`), `test_hook_writes_handoff_and_terms_claude` (asserts file JSON `session_id`/`cwd` and `kill` called with `(30, signal.SIGTERM)`).
- [ ] **Step 2: Run** → failures. **Step 3: Implement.** **Step 4: Run** → `OK`.
- [ ] **Step 5: Spike — claude on SIGTERM.** In a pty (`python3 -c 'import pty,os,signal,time,sys; pid,fd=pty.fork()...'` that execs `claude`, waits 5 s, sends SIGTERM, waits up to 5 s), record whether claude exited within 5 s. If it did not: change the kill sequence to SIGINT, SIGINT (1 s apart), then SIGTERM, then SIGKILL after 3 s, re-test, and ledger a ruling.
- [ ] **Step 6: Commit** — `feat(cc): StopFailure hook writes handoff and stops claude`.

---

### Task 4: `cc` run loop, `--account`, `status`

**Files:**
- Modify: `scripts/cc.py`, `scripts/test_cc.py`

**Interfaces:**
- Consumes: Task 2 selection functions; Task 3 handoff format.
- Produces:
  - `kept_flags(argv: list[str]) -> list[str]` — keeps `--model X`, `--model=X`, `--permission-mode X`, `--permission-mode=X`, `--dangerously-skip-permissions`, `--add-dir X…` (one value each occurrence).
  - `run(argv: list[str], *, home: Path, monitor_path: Path, limited_path: Path, tmpdir: Path, claude_bin: str, now: Callable[[], float], out: TextIO) -> int` — the loop from the spec; env per attempt: copy of `os.environ` + `CC_WRAPPER_PID`, `CC_HANDOFF`, and `CLAUDE_CONFIG_DIR` (removed for default). `cwd` for relaunch = handoff `cwd`. Limited-until = account's `fiveHourResetsAt` (if in the future) else `now + 3600`.
  - `main()` dispatch: `hook`, `setup` (Task 5), `status`, `--account <label>`, else run.

- [ ] **Step 1: Write tests** with a fake claude script (in a temp dir) that logs `CLAUDE_CONFIG_DIR`, `cwd`, and argv to a file, and — on its first invocation only — writes a handoff `{"session_id":"S1","cwd":"<tmp>/proj"}` to `$CC_HANDOFF` before exiting 0:
  - `test_run_normal_exit_passes_code` (fake exits 3 without handoff → `run` returns 3, one invocation),
  - `test_run_switches_and_resumes` (monitor: default ok headroom 10 current via `--account default`, abati ok headroom 70 → second invocation has `CLAUDE_CONFIG_DIR=<abati dir>` and argv `--resume S1 lanjutkan`, output contains `cc: limit di default → lanjut di abati`),
  - `test_run_relaunches_in_handoff_cwd`,
  - `test_run_keeps_flags` (`--model opus -p hi` → relaunch has `--model opus`, no `-p`/`hi`),
  - `test_run_stops_when_no_account_left` (only one account → returns 0, output starts with `cc: semua akun penuh`, exactly one invocation),
  - `test_run_marks_current_limited`.
- [ ] **Step 2: Run** → failures. **Step 3: Implement.** **Step 4: Run** → `OK`.
- [ ] **Step 5: Commit** — `feat(cc): run loop relaunches the session on the next account`.

---

### Task 5: `cc setup` — link accounts, install hook and binary

**Files:**
- Modify: `scripts/cc.py`, `scripts/test_cc.py`

**Interfaces:**
- Produces:
  - `plan_links(shared: Path, account: Path) -> list[tuple[str, str]]` — `(action, name)` with action ∈ `keep | relink | merge_dir | backup_file | link | mkdir_shared_link | skip` per the spec rules.
  - `apply_links(plan, shared: Path, account: Path, backup_dir: Path) -> None` — `merge_dir`: copy tree into `shared/name` without overwriting existing files, move original to `backup_dir/name`, symlink; `backup_file`: move to backup, symlink; `relink`: replace symlink.
  - `install_hook(settings: Path, command: str, backup_dir: Path) -> bool` — adds the entry if absent (backup first); `False` if already present.
  - `setup(home: Path, monitor_path: Path, confirm: Callable[[str], bool], install_to: Path, out) -> int` — accounts = `configDir` values from `accounts.json` (fallback: every `~/.claude-*` dir); prints the plan; on `confirm` applies links, installs hook (command `~/.local/bin/cc hook`), copies `scripts/cc.py` to `install_to` with mode 0o755.

- [ ] **Step 1: Write tests** on a temp home with real files: `test_plan_links_cases` (one fixture covering keep / relink / merge_dir / backup_file / link / mkdir_shared_link / skip), `test_apply_merges_without_overwrite` (same filename in both → shared copy unchanged, account copy in backup), `test_install_hook_adds_once`, `test_setup_idempotent` (second `setup` → every action `keep`, no new backup dir, hook not re-added), `test_setup_declined_changes_nothing`.
- [ ] **Step 2: Run** → failures. **Step 3: Implement.** **Step 4: Run** → `OK`.
- [ ] **Step 5: Commit** — `feat(cc): setup links accounts like Troupe and installs the hook`.

---

### Task 6: Real setup, end-to-end check, docs

**Files:**
- Modify: `README.md`, `CLAUDE.md`

- [ ] **Step 1: Ask Bara before running `cc setup` for real** (it restructures `~/.claude-abati`); then run `python3 scripts/cc.py setup` and review the printed plan with him. After: `ls -l ~/.claude-abati` shows the 10 shared names as symlinks into `~/.claude`; `~/.claude-switch/backup/abati-*/` holds the originals; `/hooks` in `claude` lists `StopFailure rate_limit`.
- [ ] **Step 2: Cross-account resume** — `cd` to a scratch dir, `claude -p "ucapkan halo"` on default, take its session id from `~/.claude/projects/<dir>/`, then `CLAUDE_CONFIG_DIR=~/.claude-abati claude -p --resume <id> "apa yang barusan kamu ucapkan?"` → answers with the earlier reply.
- [ ] **Step 3: Simulated switch** — `cc --account default`, then from another terminal pipe a fake payload into the hook with the same env (`CC_HANDOFF`/`CC_WRAPPER_PID` of that cc, `{"error":"rate_limit","session_id":…,"cwd":…}` | `~/.local/bin/cc hook`) → claude closes and cc prints `cc: limit di default → lanjut di …` and resumes.
- [ ] **Step 4: Docs** — README section "Ganti akun otomatis (`cc`)" (setup, usage, what is linked, backups, `cc status`, the hook, limits of the approach); CLAUDE.md: `scripts/cc.py`, `accounts.json`, the test command, and that setup restructures account dirs.
- [ ] **Step 5: Run all checks** (Python tests, Swift checks, build) → `OK`, `ALL CHECKS PASSED`, `** BUILD SUCCEEDED **`.
- [ ] **Step 6: Commit** — `docs: document cc auto-switch`.
