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


FAKE_CLAUDE = r'''#!/usr/bin/env python3
import json, os, sys
log = os.environ["FAKE_LOG"]
calls = sum(1 for _ in open(log)) if os.path.exists(log) else 0
with open(log, "a") as f:
    f.write(json.dumps({"cfg": os.environ.get("CLAUDE_CONFIG_DIR"), "cwd": os.getcwd(),
                        "argv": sys.argv[1:]}) + "\n")
if calls == 0 and os.environ.get("FAKE_HANDOFF_CWD"):
    with open(os.environ["CC_HANDOFF"], "w") as f:
        json.dump({"session_id": "S1", "cwd": os.environ["FAKE_HANDOFF_CWD"], "error": "rate_limit"}, f)
sys.exit(int(os.environ.get("FAKE_EXIT", "0")))
'''


class RunTests(unittest.TestCase):
    NOW = 1_800_000_000.0

    def setUp(self):
        import io
        self.tmp = Path(tempfile.mkdtemp()).resolve()
        self.fake = self.tmp / "fake-claude"
        self.fake.write_text(FAKE_CLAUDE)
        self.fake.chmod(0o755)
        self.log = self.tmp / "calls.jsonl"
        self.proj = self.tmp / "proj"
        self.proj.mkdir()
        self.monitor = self.tmp / "accounts.json"
        self.limited = self.tmp / "sw" / "limited.json"
        self.out = io.StringIO()
        self.abati_dir = str(self.tmp / ".claude-abati")

    def write_monitor(self, accounts):
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(self.NOW))
        self.monitor.write_text(json.dumps({"updatedAt": stamp, "recommended": None, "accounts": accounts}))

    def two_accounts(self):
        self.write_monitor([
            acct(cc.DEFAULT_SERVICE, headroom=10, label="default"),
            acct(cc.service_for(self.abati_dir), headroom=70, label="abati", config_dir=self.abati_dir),
        ])

    def run_cc(self, argv, handoff=True, exit_code=0):
        env = {"FAKE_LOG": str(self.log), "FAKE_EXIT": str(exit_code), "PATH": os.environ["PATH"]}
        if handoff:
            env["FAKE_HANDOFF_CWD"] = str(self.proj)
        code = cc.run(argv, home=self.tmp, monitor_path=self.monitor, limited_path=self.limited,
                      tmpdir=self.tmp, claude_bin=str(self.fake), now=lambda: self.NOW,
                      out=self.out, environ=env)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return code, calls

    def test_run_normal_exit_passes_code(self):
        self.two_accounts()
        code, calls = self.run_cc(["--account", "default", "-p", "hi"], handoff=False, exit_code=3)
        self.assertEqual(code, 3)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["argv"], ["-p", "hi"])
        self.assertIsNone(calls[0]["cfg"])

    def test_run_starts_on_most_headroom(self):
        self.two_accounts()
        _, calls = self.run_cc([], handoff=False)
        self.assertEqual(calls[0]["cfg"], self.abati_dir)

    def test_run_switches_and_resumes(self):
        self.two_accounts()
        code, calls = self.run_cc(["--account", "default"])
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[1]["cfg"], self.abati_dir)
        self.assertEqual(calls[1]["argv"], ["--resume", "S1", "lanjutkan"])
        self.assertIn("cc: limit di default → lanjut di abati", self.out.getvalue())

    def test_run_relaunches_in_handoff_cwd(self):
        self.two_accounts()
        _, calls = self.run_cc(["--account", "default"])
        self.assertEqual(Path(calls[1]["cwd"]).resolve(), self.proj)

    def test_run_keeps_flags(self):
        self.two_accounts()
        _, calls = self.run_cc(["--account", "default", "--model", "opus", "--add-dir", "/x", "-p", "hi"])
        self.assertEqual(calls[1]["argv"], ["--resume", "S1", "--model", "opus", "--add-dir", "/x", "lanjutkan"])

    def test_kept_flags_variants(self):
        argv = ["--model=opus", "--permission-mode", "plan", "--dangerously-skip-permissions",
                "-c", "--resume", "X", "prompt"]
        self.assertEqual(cc.kept_flags(argv),
                         ["--model=opus", "--permission-mode", "plan", "--dangerously-skip-permissions"])

    def test_run_stops_when_no_account_left(self):
        self.write_monitor([acct(cc.DEFAULT_SERVICE, headroom=10, label="default")])
        code, calls = self.run_cc([])
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 1)
        self.assertTrue(self.out.getvalue().startswith("cc: semua akun penuh"))

    def test_run_marks_current_limited(self):
        self.two_accounts()
        self.run_cc(["--account", "default"])
        self.assertIn(cc.DEFAULT_SERVICE, cc.load_limited(self.limited))

    def test_run_survives_sigint_to_process_group(self):
        # Ctrl+C mengirim SIGINT ke seluruh process group (cc + claude);
        # cc tidak boleh mati/membunuh claude karenanya.
        self.two_accounts()
        sigint_fake = self.tmp / "fake-sigint"
        sigint_fake.write_text(FAKE_CLAUDE.replace(
            "sys.exit(", "import signal, time; os.kill(os.getppid(), signal.SIGINT); time.sleep(0.3); sys.exit("))
        sigint_fake.chmod(0o755)
        self.fake = sigint_fake
        code, calls = self.run_cc(["--account", "default"], handoff=False, exit_code=5)
        self.assertEqual(code, 5)
        self.assertEqual(len(calls), 1)

    def test_run_unknown_account_label(self):
        self.two_accounts()
        code = cc.run(["--account", "nope"], home=self.tmp, monitor_path=self.monitor,
                      limited_path=self.limited, tmpdir=self.tmp, claude_bin=str(self.fake),
                      now=lambda: self.NOW, out=self.out, environ={})
        self.assertEqual(code, 2)
        self.assertIn("nope", self.out.getvalue())


class SetupTests(unittest.TestCase):
    def setUp(self):
        import io
        self.home = Path(tempfile.mkdtemp()).resolve()
        self.shared = self.home / ".claude"
        self.account = self.home / ".claude-abati"
        self.shared.mkdir()
        self.account.mkdir()
        self.out = io.StringIO()
        self.install_to = self.home / ".local" / "bin" / "cc"
        self.logins = {cc.service_for(str(self.account))}

    def has_login(self, service):
        return service in self.logins

    def do_setup(self, answer=True):
        return cc.setup(self.home, self.home / "no-monitor.json", confirm=lambda _q: answer,
                        install_to=self.install_to, out=self.out, has_login=self.has_login)

    def test_plan_links_cases(self):
        for d in ("projects", "skills", "rules"):
            (self.shared / d).mkdir()
        (self.shared / "settings.json").write_text("{}")
        os.symlink(self.shared / "projects", self.account / "projects")      # keep
        os.symlink(self.home / "elsewhere", self.account / "skills")         # relink
        (self.account / "plugins").mkdir()                                   # merge_dir
        (self.account / "settings.json").write_text('{"a": 1}')              # backup_file
        plan = dict((name, action) for action, name in cc.plan_links(self.shared, self.account))
        self.assertEqual(plan["projects"], "keep")
        self.assertEqual(plan["skills"], "relink")
        self.assertEqual(plan["plugins"], "merge_dir")
        self.assertEqual(plan["rules"], "link")
        self.assertEqual(plan["plans"], "mkdir_shared_link")
        self.assertEqual(plan["settings.json"], "backup_file")
        self.assertEqual(plan["CLAUDE.md"], "skip")

    def test_apply_merges_without_overwrite(self):
        (self.shared / "projects" / "p").mkdir(parents=True)
        (self.shared / "projects" / "p" / "same.jsonl").write_text("shared")
        (self.account / "projects" / "p").mkdir(parents=True)
        (self.account / "projects" / "p" / "same.jsonl").write_text("account")
        (self.account / "projects" / "p" / "only.jsonl").write_text("mine")
        backup = self.home / "bk"
        cc.apply_links([("merge_dir", "projects")], self.shared, self.account, backup)
        self.assertEqual((self.shared / "projects" / "p" / "same.jsonl").read_text(), "shared")
        self.assertEqual((self.shared / "projects" / "p" / "only.jsonl").read_text(), "mine")
        self.assertEqual((backup / "projects" / "p" / "same.jsonl").read_text(), "account")
        self.assertTrue((self.account / "projects").is_symlink())
        self.assertEqual((self.account / "projects").resolve(), (self.shared / "projects").resolve())

    def test_install_hook_adds_once(self):
        settings = self.shared / "settings.json"
        settings.write_text(json.dumps({"model": "opus", "hooks": {"Stop": [{"hooks": []}]}}))
        self.assertTrue(cc.install_hook(settings, "/x/cc hook", self.home / "bk"))
        self.assertFalse(cc.install_hook(settings, "/x/cc hook", self.home / "bk"))
        data = json.loads(settings.read_text())
        self.assertEqual(data["model"], "opus")
        self.assertIn("Stop", data["hooks"])
        self.assertEqual(data["hooks"]["StopFailure"],
                         [{"matcher": "rate_limit", "hooks": [{"type": "command", "command": "/x/cc hook"}]}])
        self.assertTrue((self.home / "bk" / "settings.json").exists())

    def test_setup_idempotent(self):
        (self.shared / "projects").mkdir()
        (self.shared / "settings.json").write_text("{}")
        (self.account / "skills").mkdir()
        self.assertEqual(self.do_setup(), 0)
        backups = sorted((self.home / ".claude-switch" / "backup").iterdir())
        self.assertTrue(self.install_to.exists())
        self.assertTrue(os.access(self.install_to, os.X_OK))
        self.assertEqual(self.do_setup(), 0)
        self.assertEqual(sorted((self.home / ".claude-switch" / "backup").iterdir()), backups)
        self.assertIn("tidak ada perubahan", self.out.getvalue())
        hooks = json.loads((self.shared / "settings.json").read_text())["hooks"]["StopFailure"]
        self.assertEqual(len(hooks), 1)

    def test_setup_declined_changes_nothing(self):
        (self.account / "skills").mkdir()
        self.assertEqual(self.do_setup(answer=False), 1)
        self.assertFalse((self.account / "skills").is_symlink())
        self.assertFalse(self.install_to.exists())

    def test_setup_skips_dirs_without_login(self):
        other = self.home / ".claude-mem"
        (other / "skills").mkdir(parents=True)
        self.do_setup()
        self.assertFalse((other / "skills").is_symlink())
        self.assertFalse((other / "projects").exists())


if __name__ == "__main__":
    unittest.main()
