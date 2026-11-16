# `cc` — automatic Claude account switch on limit — design

Date: 2026-11-16
Status: draft, awaiting approval
Builds on: `2026-11-16-multi-account-background-design.md` (multi-account monitor)

## Intent

Bara runs Claude Code in the terminal on several accounts (`~/.claude` and
`~/.claude-abati`, via `CLAUDE_CONFIG_DIR`). When the account in use hits its
limit, work stops. Goal: like Troupe (gnoviawan/troupe, ADR-0004), **switch
automatically to the account with the most room and continue the same
conversation**, without retyping anything.

## Goals

- A `cc` command that is used instead of `claude` and accepts the same arguments.
- When a turn fails with a rate limit, `cc` closes claude, picks the best other
  account, and relaunches `claude --resume <same session id> "lanjutkan"` there.
- Accounts share history and settings like Troupe, so any account can resume
  any session.
- The next account is chosen from Claude Monitor's data (the ★ logic), not by
  extra calls to `oauth/usage`.

## Non-goals

- Switching plain `claude` sessions (only sessions started through `cc`).
- Waiting for a reset when every account is full (cc exits with a message).
- Windows/Linux; non-interactive `claude -p` runs.
- Logging into accounts (still `CLAUDE_CONFIG_DIR=… claude` then `/login`).

## Anti-goals

- Touching OAuth tokens or `Claude Code-credentials*` Keychain items (cc and the
  hook never read them; Troupe hit a lost login when two processes refreshed one token).
- Losing user data during setup: nothing is deleted; every replaced file or
  directory is moved to a backup first.
- Switch loops: a run never switches more times than there are accounts.
- Changing behavior of plain `claude` (the shared hook is a no-op outside `cc`).

## Facts established

- Claude Code 2.1.325 has a **`StopFailure`** hook: "fires instead of Stop when
  an API error (rate limit, auth failure, etc.) ended the turn", fire-and-forget,
  matcher values include **`rate_limit`**. Input includes `session_id`, `cwd`,
  `transcript_path`, `error`, `error_details`.
- Hooks inherit claude's environment, and are read from the account's
  `settings.json` (shared after setup → one hook entry serves every account).
- `claude --resume <id>` finds a session through `<config dir>/projects/…`; with
  `projects` linked, every account sees every session (Troupe spike: account B
  resumes A's session with the conversation intact; first turn costs more
  because the prompt cache is rebuilt).
- Current state: `~/.claude-abati` has its own `projects`, `skills`, `plugins`,
  `file-history`, `settings.json`; `rules`, `plans`, `agents`, `commands`,
  `CLAUDE.md` are missing.

## Approaches considered

**Data source / where it lives**
- **A. `cc` wrapper + Claude Monitor data (chosen):** the monitor writes
  `accounts.json` every refresh; `cc` reads it. One source of truth, no extra
  calls to the strictly rate-limited endpoint. Data can be ≤ 5 min old, so the
  account that just hit the limit is always excluded.
- B. Standalone `cc` calling `oauth/usage` per account itself: no dependency on
  the monitor, but duplicates logic, adds requests (more 429s), needs Keychain reads.
- Dropped: a terminal hosted inside the monitor app (far too big).

**Closing claude on limit**
- **Automatic (chosen):** the hook writes a handoff file and terminates claude;
  `cc` relaunches immediately with `--resume` and the prompt "lanjutkan".
- Semi-automatic: user types `/exit`, then cc switches. Rejected: not hands-off.

**Sharing**: **fully, like Troupe (chosen)** — symlinks to `~/.claude`.
Alternative (copy only the one transcript at switch time) rejected by Bara.

## Design

### 1. Monitor: `accounts.json` (Swift, in the app)
After every `publish()` in `AccountStore`, atomically write
`~/Library/Application Support/ClaudeMonitor/accounts.json`:

```json
{
  "updatedAt": "2026-11-16T15:02:00Z",
  "recommended": "Claude Code-credentials-c6b43821",
  "accounts": [
    { "id": "Claude Code-credentials", "label": "default", "configDir": null,
      "state": "ok", "fiveHour": 38.0, "sevenDay": 18.0,
      "fiveHourResetsAt": "…", "headroom": 62.0 }
  ]
}
```
- `configDir`: absolute path, `null` for the default account. `Account` gains
  `configDir: String?` (set by `AccountDiscovery.build`).
- `state`: `ok|expired|needsLogin|error|loading`. `headroom` = `100 − max(5h, 7d)`
  or `null` without quota.
- No tokens, no emails.

### 2. `cc` — one Python 3 script (`scripts/cc`), installed to `~/.local/bin/cc`
*(my call: Python 3 — JSON, signals and process lookup are simpler than in zsh;
python3 is already used by this repo's verify recipes.)*

Subcommands:
- `cc [claude args…]` — run claude with auto-switch.
- `cc --account <label> [claude args…]` — start on a specific account.
- `cc setup` — link accounts + install the hook (below).
- `cc hook` — invoked by the `StopFailure` hook (internal).
- `cc status` — print accounts from `accounts.json` with headroom and ★.

**Run loop**
1. Starting account: `--account` if given, else the monitor's ★, else `default`
   *(my call: a fresh `cc` starts on the account with most room)*.
2. Per attempt: create handoff path `$TMPDIR/cc-<cc pid>.json` (delete stale);
   run claude in the foreground (inherits the TTY) with env
   `CC_WRAPPER_PID=<cc pid>`, `CC_HANDOFF=<path>`, and `CLAUDE_CONFIG_DIR=<dir>`
   (unset for default). Wait for exit.
3. If no handoff file exists → exit with claude's exit code (normal quit).
4. Handoff exists → record the current account as limited (in
   `~/.claude-switch/limited.json`, until its reset time if known from
   `error_details`/`accounts.json`, else +1 h), pick the next account
   (below), print one line `cc: limit di <a> → lanjut di <b>`, `cd` to the
   handoff `cwd`, and relaunch `claude --resume <session_id> "lanjutkan"` plus
   the kept flags. Switches per run ≤ number of accounts.
5. No account left → print `cc: semua akun penuh — reset paling cepat <time>`
   and exit 0.

**Picking the next account** (pure function): exclude the current account,
accounts in `limited.json` (unexpired), and `needsLogin` (login gone).
1. First, `state == ok` with `headroom > 0`: highest headroom wins (tie → lower 5h).
2. Then `expired` accounts *(my call)*: an idle account's token is usually
   expired only because no claude ran there recently; launching claude refreshes
   it. Usage is unknown, so they rank after every `ok` account, in label order.
If `accounts.json` is missing or older than 15 min → candidates are the other
linked account dirs (`~/.claude` plus every `~/.claude-*` whose `projects` is a
symlink to `~/.claude/projects`), default first then label order, minus limited ones.

**Kept flags on relaunch** *(my call)*: `--model`, `--permission-mode`,
`--dangerously-skip-permissions`, `--add-dir` (with values). Positional prompts,
`-p/--print`, `-c/--continue`, `-r/--resume` are not re-passed.

**Hook (`cc hook`)**: reads the StopFailure JSON on stdin. If `CC_HANDOFF` or
`CC_WRAPPER_PID` is unset → exit 0 (plain `claude`, no-op). Otherwise write
`{session_id, cwd, error, error_details, at}` to `CC_HANDOFF`, find claude's pid
by walking the parent chain from the hook process up to the process whose
parent is `CC_WRAPPER_PID`, and send it `SIGTERM`. Only acts on matcher
`rate_limit` (registered with that matcher; also re-checks `error`).

### 3. `cc setup`
Idempotent; prints what it will do and asks `y/N` before changing anything.
Warns to close every running claude first.
- Accounts = every `~/.claude-*` directory that matches a Keychain item, taken
  from `accounts.json` `configDir` values (so it uses the monitor's discovery).
- Shared dirs: `projects skills plugins rules plans file-history agents commands`;
  shared files: `settings.json CLAUDE.md` (Troupe's list).
- For each account and shared name:
  - correct symlink → keep;
  - wrong symlink → replace;
  - real directory → merge its contents into `~/.claude/<name>` without
    overwriting (`--ignore-existing` semantics), move the original to
    `~/.claude-switch/backup/<label>-<timestamp>/<name>`, create the link;
  - real file → move to backup, create the link (the default account's file wins);
  - missing → link if the `~/.claude` target exists; create missing shared
    *directories* in `~/.claude` first; skip missing *files* (Troupe rule).
- Hook: back up `~/.claude/settings.json`, add under `hooks.StopFailure` an
  entry `{"matcher": "rate_limit", "hooks": [{"type": "command", "command":
  "~/.local/bin/cc hook"}]}` if not present.
- Never touches `.claude.json`, `.credentials*`, or Keychain.
- Installs `scripts/cc` to `~/.local/bin/cc` (copy, executable).

### 4. Docs
README section "Ganti akun otomatis (`cc`)" in Indonesian; CLAUDE.md notes the
script, the hook, and that setup restructures account dirs.

## Risks to verify early (builder)
- **Claude's reaction to SIGTERM** from the hook: it must exit and restore the
  terminal. If it doesn't, fall back to SIGINT twice, then SIGKILL after 3 s.
- `StopFailure` actually firing for a quota limit (`rate_limit`) — the real
  limit can't be triggered on demand; verify the hook path with a fake stdin
  payload and verify registration with `claude` `/hooks`.
- `--resume <id> "lanjutkan"` on another account after linking (Troupe's spike
  says yes) — verify by resuming a short test session on `abati`.

## Left to the builder
- Exact output wording beyond the strings above; `cc status` layout.
- Test layout: Python `unittest` for the pure parts (next-account choice, link
  planning, flag filtering, parent-chain walk with an injected process table),
  plus the existing `Checks/` for the Swift `accounts.json` encoding.
