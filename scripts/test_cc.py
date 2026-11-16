"""Tes untuk scripts/cc.py.

Jalankan: python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cc  # noqa: E402


def acct(id, state="ok", headroom=None, five=None, label=None, config_dir=None):
    return {"id": id, "label": label or id, "configDir": config_dir, "state": state,
            "headroom": headroom, "fiveHour": five, "sevenDay": None, "fiveHourResetsAt": None}


class SelectionTests(unittest.TestCase):
    def test_service_for_matches_claude_code(self):
        self.assertEqual(cc.service_for("/Users/bara/.claude-abati"), "Claude Code-credentials-c6b43821")
        self.assertEqual(cc.service_for(None), "Claude Code-credentials")

    def test_pick_next_prefers_most_headroom(self):
        accounts = [acct("cur", headroom=90), acct("a", headroom=20, five=80), acct("b", headroom=62, five=38)]
        self.assertEqual(cc.pick_next(accounts, "cur", {}, 1000)["id"], "b")

    def test_pick_next_tie_prefers_lower_five_hour(self):
        accounts = [acct("a", headroom=50, five=50), acct("b", headroom=50, five=10)]
        self.assertEqual(cc.pick_next(accounts, "cur", {}, 1000)["id"], "b")

    def test_pick_next_skips_current_limited_and_needs_login(self):
        accounts = [acct("cur", headroom=99), acct("lim", headroom=80), acct("gone", state="needsLogin"),
                    acct("ok", headroom=10)]
        self.assertEqual(cc.pick_next(accounts, "cur", {"lim": 2000}, 1000)["id"], "ok")

    def test_pick_next_expired_limit_entry_is_ignored(self):
        accounts = [acct("lim", headroom=80)]
        self.assertEqual(cc.pick_next(accounts, "cur", {"lim": 500}, 1000)["id"], "lim")

    def test_pick_next_expired_after_ok(self):
        self.assertEqual(cc.pick_next([acct("x", state="expired"), acct("y", headroom=5)], "cur", {}, 1000)["id"], "y")
        self.assertEqual(cc.pick_next([acct("x", state="expired")], "cur", {}, 1000)["id"], "x")

    def test_pick_next_skips_full_ok_accounts(self):
        self.assertIsNone(cc.pick_next([acct("full", headroom=0)], "cur", {}, 1000))

    def test_pick_next_none_when_nothing_left(self):
        self.assertIsNone(cc.pick_next([acct("cur", headroom=50)], "cur", {}, 1000))

    def test_pick_start_uses_same_ranking(self):
        accounts = [acct("a", state="expired"), acct("b", headroom=30), acct("c", headroom=70)]
        self.assertEqual(cc.pick_start(accounts, {}, 1000)["id"], "c")


class MonitorFileTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def write_monitor(self, updated_at: float):
        path = self.tmp / "accounts.json"
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(updated_at))
        path.write_text(json.dumps({"updatedAt": stamp, "recommended": None, "accounts": [acct("a", headroom=10)]}))
        return path

    def test_load_monitor_stale_returns_none(self):
        now = 1_800_000_000
        self.assertIsNone(cc.load_monitor(self.write_monitor(now - 901), now))
        self.assertEqual([a["id"] for a in cc.load_monitor(self.write_monitor(now - 10), now)], ["a"])

    def test_load_monitor_missing_returns_none(self):
        self.assertIsNone(cc.load_monitor(self.tmp / "nope.json", 1000))

    def test_load_monitor_garbage_returns_none(self):
        path = self.tmp / "bad.json"
        path.write_text("{not json")
        self.assertIsNone(cc.load_monitor(path, 1000))

    def test_fallback_accounts_only_linked_dirs(self):
        home = self.tmp
        (home / ".claude" / "projects").mkdir(parents=True)
        (home / ".claude-a").mkdir()
        os.symlink(home / ".claude" / "projects", home / ".claude-a" / "projects")
        (home / ".claude-b" / "projects").mkdir(parents=True)
        accounts = cc.fallback_accounts(home)
        self.assertEqual([a["label"] for a in accounts], ["default", "a"])
        self.assertIsNone(accounts[0]["configDir"])
        self.assertEqual(accounts[1]["configDir"], str(home / ".claude-a"))
        self.assertEqual(accounts[1]["id"], cc.service_for(str(home / ".claude-a")))
        self.assertEqual(accounts[1]["state"], "unknown")

    def test_mark_limited_roundtrip_and_expiry(self):
        path = self.tmp / "sw" / "limited.json"
        cc.mark_limited(path, "old", until=10, now=5)
        cc.mark_limited(path, "new", until=2000, now=1000)
        self.assertEqual(cc.load_limited(path), {"new": 2000})
        self.assertEqual(cc.load_limited(self.tmp / "missing.json"), {})


class HookTests(unittest.TestCase):
    TABLE = {50: 40, 40: 30, 30: 10, 10: 1}

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.kills = []

    def kill(self, pid, sig):
        self.kills.append((pid, sig))

    def test_find_claude_pid_walks_to_child_of_wrapper(self):
        self.assertEqual(cc.find_claude_pid(50, 10, self.TABLE.get), 30)

    def test_find_claude_pid_none_when_not_descendant(self):
        self.assertIsNone(cc.find_claude_pid(50, 999, self.TABLE.get))

    def payload(self, error="rate_limit"):
        return {"hook_event_name": "StopFailure", "error": error, "session_id": "S1",
                "cwd": "/tmp/proj", "error_details": "5-hour limit reached"}

    def test_hook_noop_without_wrapper_env(self):
        self.assertFalse(cc.handle_hook(self.payload(), {}, self.kill, self.TABLE.get, 50))
        self.assertEqual(self.kills, [])
        self.assertEqual(list(self.tmp.iterdir()), [])

    def test_hook_ignores_other_errors(self):
        env = {"CC_HANDOFF": str(self.tmp / "h.json"), "CC_WRAPPER_PID": "10"}
        self.assertFalse(cc.handle_hook(self.payload("overloaded"), env, self.kill, self.TABLE.get, 50))
        self.assertEqual(self.kills, [])
        self.assertFalse((self.tmp / "h.json").exists())

    def test_hook_writes_handoff_and_terms_claude(self):
        import signal
        env = {"CC_HANDOFF": str(self.tmp / "h.json"), "CC_WRAPPER_PID": "10"}
        self.assertTrue(cc.handle_hook(self.payload(), env, self.kill, self.TABLE.get, 50))
        handoff = json.loads((self.tmp / "h.json").read_text())
        self.assertEqual(handoff["session_id"], "S1")
        self.assertEqual(handoff["cwd"], "/tmp/proj")
        self.assertEqual(self.kills, [(30, signal.SIGTERM)])


if __name__ == "__main__":
    unittest.main()
