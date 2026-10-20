#!/usr/bin/env python3
"""Test keyed fact alerts through the CLI and Lark dry-run, without live services."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = Path(os.environ.get("AWB_TEST_BIN", ROOT / "awb")).resolve()


class NewsAlerts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="awb-news-test-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.board = self.work / "board"
        self.board.mkdir()
        self.now = int(time.time()) + 10
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("AWB_")}
        self.env.pop("TMUX", None)
        self.env.pop("TMUX_PANE", None)
        self.env.update(AWB_DIR=str(self.board), AWB_NOW=str(self.now),
                        AWB_COLS="160", AWB_ROWS="200", AWB_NUDGE="0",
                        AWB_OBSERVE="0", XDG_CONFIG_HOME=str(self.work / "config"))

    def run_cli(self, *args, ok=True, env=None):
        result = subprocess.run([str(BIN), *args], cwd=self.work,
                                env=env or self.env, capture_output=True,
                                text=True, timeout=30)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def snapshot(self):
        return json.loads(self.run_cli("view", "--json").stdout)

    def alerts(self):
        return [a for a in self.snapshot()["anomalies"] if a["kind"] in ("fact", "stale")]

    def events(self):
        path = self.board / "events.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def fixture(self, *events):
        # Only this temporary board is writable by the fixtures.
        with (self.board / "events.jsonl").open("a") as stream:
            for event in events:
                stream.write(json.dumps(event) + "\n")

    def test_warning_clears_on_clean_replacement(self):
        self.run_cli("news", "--key", "health", "--warn", "worker exited")
        self.assertEqual(self.alerts(), [{"kind": "fact", "text": "worker exited"}])
        self.run_cli("news", "--key", "health", "worker ok")
        self.assertEqual(self.alerts(), [])
        self.assertEqual([r["text"] for r in self.snapshot()["news"]], ["worker ok"])

    def test_expiry_boundary_refresh_and_removal(self):
        self.fixture({"t": "news", "key": "step", "text": "step 100", "ep": self.now - 60, "ttl": 60})
        self.assertEqual(self.alerts(), [])
        self.env["AWB_NOW"] = str(self.now + 1)
        self.assertEqual([a["kind"] for a in self.alerts()], ["stale"])
        self.fixture({"t": "news", "key": "step", "text": "step 101", "ep": self.now + 1, "ttl": 60})
        self.assertEqual(self.alerts(), [])
        self.run_cli("news", "--key", "step", "permanent summary")
        self.env["AWB_NOW"] = str(self.now + 10000)
        self.assertEqual(self.alerts(), [])

    def test_old_warning_does_not_reappear_after_expiry(self):
        self.fixture({"t": "news", "key": "health", "text": "old failure", "ep": self.now - 90,
                      "warn": True, "ttl": 60},
                     {"t": "news", "key": "health", "text": "recovered", "ep": self.now - 70, "ttl": 60})
        alerts = self.alerts()
        self.assertEqual([a["kind"] for a in alerts], ["stale"])
        self.assertIn("recovered", alerts[0]["text"])
        self.assertNotIn("old failure", json.dumps(alerts))

    def test_keys_are_independent_and_combined_alerts_are_visible(self):
        self.fixture({"t": "news", "key": "health", "text": "worker exited", "ep": self.now - 70,
                      "warn": True, "ttl": 60})
        self.run_cli("news", "--key", "other", "unrelated update")
        self.assertEqual(sorted(a["kind"] for a in self.alerts()), ["fact", "stale"])

    def test_invalid_flags_append_no_events(self):
        self.run_cli("news", "seed")
        before = self.events()
        bad = [("--warn", "x"), ("--ttl", "60", "x"), ("--key",), ("--key", "", "x"),
               ("--key", "--warn", "x"), ("--key", "k", "--ttl"), ("--bogus", "x")]
        for value in ("", "0", "000", "060", "-1", "1.5", "1e3", "x", "2147483648", "9" * 60):
            bad.append(("--key", "k", "--ttl", value, "x"))
        for args in bad:
            with self.subTest(args=args):
                self.run_cli("news", *args, ok=False)
                self.assertEqual(self.events(), before)

    def test_flag_order_and_max_ttl(self):
        self.run_cli("news", "--warn", "--ttl", "2147483647", "--key", "k", "test")
        event = self.events()[-1]
        self.assertEqual(event["ttl"], 2147483647)
        self.assertIs(event["warn"], True)
        self.assertEqual(event["key"], "k")
        self.run_cli("news", "--key", "min", "--ttl", "1", "short")
        self.assertEqual(self.events()[-1]["ttl"], 1)

    def test_legacy_and_malformed_optional_metadata(self):
        self.fixture({"t": "news", "text": "legacy", "time": "10:00:00"},
                     {"t": "news", "key": "k", "text": "keyed legacy"},
                     {"t": "news", "key": "bad", "text": "bad metadata", "ep": self.now - 100,
                      "ttl": "x", "warn": "false"},
                     {"t": "news", "key": "missing", "text": "no epoch", "ttl": 1})
        self.assertEqual(self.alerts(), [])
        self.assertEqual(len(self.snapshot()["news"]), 4)

    def test_render_alerts_in_terminal_and_lark_card(self):
        self.run_cli("news", "--key", "health", "--warn", "worker exited")
        self.fixture({"t": "news", "key": "step", "text": "step 100", "ep": self.now - 120, "ttl": 60})
        rendered = self.run_cli("view", "--once").stdout
        self.assertIn("worker exited", rendered)
        self.assertIn("未刷新", rendered)
        env = dict(self.env, AWB=str(BIN))
        result = subprocess.run([str(ROOT / "awb-lark"), "sync", "--dry-run"], cwd=self.work,
                                env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        card = json.loads(result.stdout)
        # Assert the alerts are outside collapsed news panels.
        text = json.dumps([e for e in card["body"]["elements"] if e["tag"] != "collapsible_panel"], ensure_ascii=False)
        self.assertIn("worker exited", text)
        self.assertIn("未刷新", text)
        self.assertFalse((self.board / "lark.json").exists())
        self.assertFalse((self.work / "config").exists())

    def test_news_does_not_change_agent_fold(self):
        self.run_cli("start", "worker", "test worker")
        before = self.run_cli("_state").stdout
        self.run_cli("news", "--key", "health", "--ttl", "60", "--warn", "worker check failed")
        self.assertEqual(self.run_cli("_state").stdout, before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
