#!/usr/bin/env python3
"""cc — jalankan Claude Code dan ganti akun otomatis saat limit habis.

Pemakaian:
  cc [argumen claude…]          jalankan claude; saat limit → lanjut di akun lain
  cc --account <label> [arg…]   mulai di akun tertentu
  cc status                     tampilkan akun dari Claude Monitor
  cc setup                      sambungkan akun (symlink ke ~/.claude) + pasang hook
  cc hook                       dipanggil oleh hook StopFailure (internal)

Tidak pernah membaca/menulis token OAuth atau item Keychain Claude Code.
"""

from __future__ import annotations

import calendar
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DEFAULT_SERVICE = "Claude Code-credentials"
MONITOR_MAX_AGE = 900          # detik; accounts.json lebih tua dari ini dianggap basi
DEFAULT_LIMIT_SECONDS = 3600   # lama akun dianggap penuh bila waktu reset tak diketahui
MONITOR_PATH = Path.home() / "Library/Application Support/ClaudeMonitor/accounts.json"
SWITCH_DIR = Path.home() / ".claude-switch"
LIMITED_PATH = SWITCH_DIR / "limited.json"
CONTINUE_PROMPT = "lanjutkan"


# ---------------------------------------------------------------- akun

def service_for(config_dir: str | None) -> str:
    """Nama item Keychain Claude Code untuk sebuah config dir (aturan Claude Code)."""
    if config_dir is None:
        return DEFAULT_SERVICE
    return f"{DEFAULT_SERVICE}-{hashlib.sha256(config_dir.encode()).hexdigest()[:8]}"


def parse_iso(stamp: str | None) -> float | None:
    if not stamp:
        return None
    try:
        return float(calendar.timegm(time.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S")))
    except ValueError:
        return None


def load_monitor(path: Path, now: float) -> list[dict] | None:
    """Akun dari accounts.json Claude Monitor; None bila tidak ada/rusak/basi."""
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None
    updated = parse_iso(data.get("updatedAt")) if isinstance(data, dict) else None
    if updated is None or now - updated > MONITOR_MAX_AGE:
        return None
    accounts = data.get("accounts")
    return accounts if isinstance(accounts, list) else None


def fallback_accounts(home: Path) -> list[dict]:
    """Akun tanpa data monitor: ~/.claude + tiap ~/.claude-* yang projects-nya
    symlink ke ~/.claude/projects (artinya sudah di-`cc setup`)."""
    home = Path(home)
    shared_projects = (home / ".claude" / "projects").resolve()
    result = [{"id": DEFAULT_SERVICE, "label": "default", "configDir": None,
               "state": "unknown", "headroom": None, "fiveHour": None}]
    linked = []
    for entry in sorted(home.glob(".claude-*")):
        projects = entry / "projects"
        if entry.is_dir() and projects.is_symlink() and projects.resolve() == shared_projects:
            linked.append({"id": service_for(str(entry)), "label": entry.name[len(".claude-"):],
                           "configDir": str(entry), "state": "unknown", "headroom": None,
                           "fiveHour": None})
    return result + sorted(linked, key=lambda a: a["label"])


def load_limited(path: Path) -> dict[str, float]:
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}
    return {k: float(v) for k, v in data.items()} if isinstance(data, dict) else {}


def mark_limited(path: Path, account_id: str, until: float, now: float) -> None:
    """Catat akun penuh sampai `until`; entri yang sudah lewat dibuang."""
    path = Path(path)
    data = {k: v for k, v in load_limited(path).items() if v > now}
    data[account_id] = until
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))


def _ranked(accounts: list[dict], exclude: str | None, limited: dict[str, float], now: float) -> list[dict]:
    usable = [a for a in accounts
              if a.get("id") != exclude
              and limited.get(a.get("id"), 0) <= now
              and a.get("state") != "needsLogin"]
    ok = [a for a in usable if a.get("state") == "ok" and (a.get("headroom") or 0) > 0]
    ok.sort(key=lambda a: (-(a.get("headroom") or 0), a.get("fiveHour") or 0))
    # Token akun yang lama menganggur biasanya kedaluwarsa saja; menjalankan
    # claude di sana menyegarkannya. Pemakaiannya tak diketahui → setelah `ok`.
    unknown = [a for a in usable if a.get("state") in ("expired", "unknown")]
    return ok + unknown


def pick_next(accounts: list[dict], current_id: str, limited: dict[str, float], now: float) -> dict | None:
    """Akun berikutnya setelah `current_id` kena limit, atau None."""
    ranked = _ranked(accounts, current_id, limited, now)
    return ranked[0] if ranked else None


def pick_start(accounts: list[dict], limited: dict[str, float], now: float) -> dict | None:
    """Akun untuk memulai sesi baru (sisa limit terbanyak)."""
    ranked = _ranked(accounts, None, limited, now)
    return ranked[0] if ranked else None


# ---------------------------------------------------------------- hook

def find_claude_pid(start_pid: int, wrapper_pid: int, parent_of) -> int | None:
    """Naik dari proses hook sampai proses yang induknya `cc` (= claude)."""
    pid = start_pid
    for _ in range(32):
        if pid is None or pid <= 1:
            return None
        parent = parent_of(pid)
        if parent == wrapper_pid:
            return pid
        pid = parent
    return None


def parent_of_ps(pid: int) -> int | None:
    try:
        out = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)],
                             capture_output=True, text=True, check=False).stdout.strip()
        return int(out) if out else None
    except (OSError, ValueError):
        return None


def handle_hook(payload: dict, env, kill, parent_of, self_pid: int) -> bool:
    """StopFailure: bila sesi dijalankan lewat `cc` dan errornya rate_limit,
    tulis handoff lalu hentikan claude. Di luar `cc` tidak melakukan apa-apa."""
    handoff = env.get("CC_HANDOFF")
    wrapper = env.get("CC_WRAPPER_PID")
    if not handoff or not wrapper or payload.get("error") != "rate_limit":
        return False
    try:
        wrapper_pid = int(wrapper)
    except ValueError:
        return False
    Path(handoff).write_text(json.dumps({
        "session_id": payload.get("session_id"),
        "cwd": payload.get("cwd"),
        "error": payload.get("error"),
        "error_details": payload.get("error_details"),
        "at": time.time(),
    }))
    claude_pid = find_claude_pid(self_pid, wrapper_pid, parent_of)
    if claude_pid is not None:
        kill(claude_pid, signal.SIGTERM)
    return True


# ---------------------------------------------------------------- run loop

VALUE_FLAGS = ("--model", "--permission-mode", "--add-dir")
BARE_FLAGS = ("--dangerously-skip-permissions",)


def kept_flags(argv: list[str]) -> list[str]:
    """Flag yang ikut dibawa saat melanjutkan di akun lain."""
    kept, i = [], 0
    while i < len(argv):
        arg = argv[i]
        if arg in VALUE_FLAGS and i + 1 < len(argv):
            kept += [arg, argv[i + 1]]
            i += 2
            continue
        if arg in BARE_FLAGS or any(arg.startswith(f + "=") for f in VALUE_FLAGS):
            kept.append(arg)
        i += 1
    return kept


def _restore_terminal(out) -> None:
    """claude dihentikan paksa — pastikan kursor tampil dan mode tty normal."""
    if hasattr(out, "isatty") and out.isatty():
        out.write("\x1b[?25h")
        out.flush()
        subprocess.call(["stty", "sane"], stderr=subprocess.DEVNULL)


def run(argv: list[str], *, home: Path, monitor_path: Path, limited_path: Path, tmpdir: Path,
        claude_bin: str, now, out, environ=None) -> int:
    environ = dict(os.environ if environ is None else environ)
    label, args = None, []
    i = 0
    while i < len(argv):
        if argv[i] == "--account" and i + 1 < len(argv):
            label = argv[i + 1]
            i += 2
            continue
        args.append(argv[i])
        i += 1

    accounts = load_monitor(monitor_path, now()) or fallback_accounts(home)
    limited = load_limited(limited_path)
    if label is not None:
        current = next((a for a in accounts if a.get("label") == label), None)
        if current is None:
            names = ", ".join(a.get("label", "?") for a in accounts)
            out.write(f"cc: akun '{label}' tidak ditemukan (ada: {names})\n")
            return 2
    else:
        current = pick_start(accounts, limited, now()) or accounts[0]

    handoff = Path(tmpdir) / f"cc-{os.getpid()}.json"
    claude_args, cwd, switches = args, None, 0
    while True:
        if handoff.exists():
            handoff.unlink()
        env = dict(environ)
        env["CC_WRAPPER_PID"] = str(os.getpid())
        env["CC_HANDOFF"] = str(handoff)
        if current.get("configDir"):
            env["CLAUDE_CONFIG_DIR"] = current["configDir"]
        else:
            env.pop("CLAUDE_CONFIG_DIR", None)
        code = subprocess.call([claude_bin, *claude_args], env=env, cwd=cwd)
        if not handoff.exists():
            return code
        try:
            info = json.loads(handoff.read_text())
        except (OSError, ValueError):
            info = {}
        handoff.unlink(missing_ok=True)
        _restore_terminal(out)
        if not info.get("session_id"):
            return code

        t = now()
        reset = parse_iso(current.get("fiveHourResetsAt"))
        mark_limited(limited_path, current["id"], reset if reset and reset > t else t + DEFAULT_LIMIT_SECONDS, t)
        limited = load_limited(limited_path)
        accounts = load_monitor(monitor_path, t) or accounts
        nxt = pick_next(accounts, current["id"], limited, t) if switches < len(accounts) else None
        if nxt is None:
            soonest = min((v for v in limited.values() if v > t), default=t)
            out.write(f"cc: semua akun penuh — reset paling cepat {time.strftime('%H:%M', time.localtime(soonest))}\n")
            return 0
        out.write(f"cc: limit di {current.get('label')} → lanjut di {nxt.get('label')}\n")
        out.flush()
        switches += 1
        current = nxt
        cwd = info.get("cwd") if info.get("cwd") and Path(info["cwd"]).is_dir() else None
        claude_args = ["--resume", info["session_id"], *kept_flags(args), CONTINUE_PROMPT]


def status(out, monitor_path: Path = MONITOR_PATH, home: Path = Path.home()) -> int:
    t = time.time()
    accounts = load_monitor(monitor_path, t)
    source = "Claude Monitor"
    if accounts is None:
        accounts, source = fallback_accounts(home), "folder tertaut (data monitor tidak ada/basi)"
    start = pick_start(accounts, load_limited(LIMITED_PATH), t)
    out.write(f"Sumber: {source}\n")
    for a in accounts:
        star = "★" if start and a.get("id") == start.get("id") else " "
        room = "-" if a.get("headroom") is None else f"{a['headroom']:.0f}%"
        out.write(f"{star} {a.get('label', '?'):<12} {a.get('state', '?'):<10} sisa {room}\n")
    return 0


def main(argv: list[str]) -> int:
    if argv[:1] == ["hook"]:
        try:
            payload = json.load(sys.stdin)
        except ValueError:
            return 0
        try:
            handle_hook(payload, os.environ, os.kill, parent_of_ps, os.getpid())
        except Exception:  # hook tidak boleh mengganggu claude
            pass
        return 0
    if argv[:1] == ["status"]:
        return status(sys.stdout)
    if argv[:1] == ["setup"]:
        return setup_main()
    return run(argv, home=Path.home(), monitor_path=MONITOR_PATH, limited_path=LIMITED_PATH,
               tmpdir=Path(tempfile.gettempdir()), claude_bin=os.environ.get("CC_CLAUDE_BIN", "claude"),
               now=time.time, out=sys.stdout)


# ---------------------------------------------------------------- setup

SHARED_DIRS = ("projects", "skills", "plugins", "rules", "plans", "file-history", "agents", "commands")
SHARED_FILES = ("settings.json", "CLAUDE.md")
NO_CHANGE = ("keep", "skip")


def plan_links(shared: Path, account: Path) -> list[tuple[str, str]]:
    """Rencana per entri bersama: keep | relink | merge_dir | backup_file | link |
    mkdir_shared_link | skip (aturan Troupe ADR-0004)."""
    plan = []
    for name, is_dir in [(n, True) for n in SHARED_DIRS] + [(n, False) for n in SHARED_FILES]:
        target, entry = shared / name, account / name
        if entry.is_symlink():
            ok = target.exists() and entry.resolve() == target.resolve()
            plan.append(("keep" if ok else ("relink" if target.exists() or is_dir else "skip"), name))
        elif entry.is_dir():
            plan.append(("merge_dir", name))
        elif entry.exists():
            # File milik akun: diganti link bila versi bersama ada (akun default menang).
            plan.append(("backup_file" if target.exists() else "skip", name))
        elif target.exists():
            plan.append(("link", name))
        else:
            plan.append(("mkdir_shared_link" if is_dir else "skip", name))
    return plan


def _merge_tree(src: Path, dst: Path) -> None:
    """Salin isi src ke dst tanpa menimpa file yang sudah ada."""
    for root, dirs, files in os.walk(src):
        rel = Path(root).relative_to(src)
        (dst / rel).mkdir(parents=True, exist_ok=True)
        for name in files + [d for d in dirs if (Path(root) / d).is_symlink()]:
            source, dest = Path(root) / name, dst / rel / name
            if not dest.exists() and not dest.is_symlink():
                shutil.copy2(source, dest, follow_symlinks=False)


def apply_links(plan, shared: Path, account: Path, backup_dir: Path) -> None:
    for action, name in plan:
        target, entry = shared / name, account / name
        if action in NO_CHANGE:
            continue
        if action == "relink":
            entry.unlink()
        elif action == "mkdir_shared_link":
            target.mkdir(parents=True, exist_ok=True)
        elif action in ("merge_dir", "backup_file"):
            if action == "merge_dir":
                target.mkdir(parents=True, exist_ok=True)
                _merge_tree(entry, target)
            backup_dir.mkdir(parents=True, exist_ok=True)
            shutil.move(str(entry), str(backup_dir / name))
        os.symlink(target, entry)


def _hook_present(data: dict, command: str) -> bool:
    for entry in data.get("hooks", {}).get("StopFailure", []) or []:
        for hook in entry.get("hooks", []) or []:
            if hook.get("command") == command:
                return True
    return False


def install_hook(settings: Path, command: str, backup_dir: Path) -> bool:
    """Tambahkan hook StopFailure(rate_limit) → `command`; False bila sudah ada."""
    data = json.loads(settings.read_text()) if settings.exists() else {}
    if _hook_present(data, command):
        return False
    if settings.exists():
        backup_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(settings, backup_dir / "settings.json")
    data.setdefault("hooks", {}).setdefault("StopFailure", []).append(
        {"matcher": "rate_limit", "hooks": [{"type": "command", "command": command}]})
    settings.write_text(json.dumps(data, indent=2) + "\n")
    return True


def keychain_has_login(service: str) -> bool:
    """Ada item Keychain dengan nama ini? Hanya atribut (tanpa -w → token tidak dibaca)."""
    return subprocess.call(["security", "find-generic-password", "-s", service],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0


def account_dirs(home: Path, has_login) -> list[Path]:
    """Folder ~/.claude-* yang benar-benar akun Claude Code (punya login di Keychain)."""
    return [d for d in sorted(Path(home).glob(".claude-*"))
            if d.is_dir() and not d.is_symlink() and has_login(service_for(str(d)))]


def setup(home: Path, monitor_path: Path, confirm, install_to: Path, out, has_login=keychain_has_login,
          source: Path = Path(__file__)) -> int:
    home = Path(home)
    shared = home / ".claude"
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup_root = home / ".claude-switch" / "backup"
    plans = {d: plan_links(shared, d) for d in account_dirs(home, has_login)}
    settings = shared / "settings.json"
    hook_cmd = f"{install_to} hook"
    try:
        hook_needed = not _hook_present(json.loads(settings.read_text()) if settings.exists() else {}, hook_cmd)
    except ValueError:
        out.write(f"cc setup: {settings} bukan JSON yang valid — perbaiki dulu.\n")
        return 1
    install_needed = not install_to.exists() or install_to.read_bytes() != Path(source).read_bytes()

    changes = {d: [p for p in plan if p[0] not in NO_CHANGE] for d, plan in plans.items()}
    if not any(changes.values()) and not hook_needed and not install_needed:
        out.write("cc setup: sudah terpasang, tidak ada perubahan.\n")
        return 0

    out.write("cc setup akan:\n")
    for d, items in changes.items():
        for action, name in items:
            out.write(f"  {d.name}/{name}: {action}\n")
    if hook_needed:
        out.write(f"  {settings}: tambah hook StopFailure(rate_limit) → {hook_cmd}\n")
    if install_needed:
        out.write(f"  pasang {install_to}\n")
    out.write(f"Yang diganti dipindah ke {backup_root}/ (tidak ada yang dihapus).\n"
              "Tutup semua sesi claude sebelum melanjutkan.\n")
    if not confirm("Lanjutkan? [y/N] "):
        out.write("Dibatalkan.\n")
        return 1

    for d, plan in plans.items():
        label = d.name[len(".claude-"):] or d.name
        apply_links(plan, shared, d, backup_root / f"{label}-{stamp}")
    if hook_needed:
        install_hook(settings, hook_cmd, backup_root / f"settings-{stamp}")
    if install_needed:
        install_to.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, install_to)
        install_to.chmod(0o755)
    out.write("cc setup selesai.\n")
    return 0


def setup_main() -> int:
    return setup(Path.home(), MONITOR_PATH,
                 confirm=lambda q: input(q).strip().lower() in ("y", "ya", "yes"),
                 install_to=Path.home() / ".local" / "bin" / "cc", out=sys.stdout)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
