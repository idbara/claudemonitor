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
import signal
import subprocess
import time
from pathlib import Path

DEFAULT_SERVICE = "Claude Code-credentials"
MONITOR_MAX_AGE = 900          # detik; accounts.json lebih tua dari ini dianggap basi
DEFAULT_LIMIT_SECONDS = 3600   # lama akun dianggap penuh bila waktu reset tak diketahui


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
