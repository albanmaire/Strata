"""Tests for `setup.py --update` (#475; STRATA.bat / STRATA.sh --update run it): fetch_new_code pulls the
newest code, then the update refreshes what a start would - the Python packages, the engine, each model's
config and draft subset - and never starts the model.  Every outside effect is mocked: no
GPU, no downloads, nothing written outside a temp folder.

    python -m unittest tools.test_setup_update
"""
from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import setup  # noqa: E402


class Update(unittest.TestCase):
    def config(self, d: Path, **extra) -> Path:
        rt = d / "mtp" / "rt"
        rt.mkdir(parents=True)
        p = d / "strata-iq3_s.json"
        p.write_text(json.dumps({"model_name": "Qwen IQ3_S", "exe": str(d / "engine" / setup.EXE),
                                 "args": ["--native", "x", "--mtp", str(rt)], **extra}), encoding="utf-8")
        return p

    def run_update(self, have, argv=()):
        a = mock.Mock(**{"build": False, "prebuilt": "URL", **dict(argv)})
        out = io.StringIO()
        with mock.patch.object(setup, "pip_install") as pip, \
                mock.patch.object(setup, "update_installed_engine") as eng, \
                mock.patch.object(setup, "refresh_draft_vocab") as dv, \
                mock.patch.object(setup, "start") as start, \
                mock.patch("subprocess.call") as call, \
                contextlib.redirect_stdout(out):
            rc = setup.update_install(have, a)
        return rc, pip, eng, dv, start, call, out.getvalue()

    def test_refreshes_without_starting(self):
        with tempfile.TemporaryDirectory() as d:
            p = self.config(Path(d), draft_vocab="en")
            rc, pip, eng, dv, start, call, out = self.run_update([p])
        self.assertEqual(rc, 0)
        pip.assert_called_once()
        eng.assert_called_once_with("URL")
        dv.assert_called_once()
        self.assertEqual(dv.call_args[0][1], "en")                 # the model's own subset is kept
        start.assert_not_called()
        call.assert_not_called()
        self.assertIn("Strata is updated", out)

    def test_build_keeps_the_compiled_engine_path(self):
        with tempfile.TemporaryDirectory() as d:
            p = self.config(Path(d))
            rc, pip, eng, dv, *_ = self.run_update([p], {"build": True})
        self.assertEqual(rc, 0)
        eng.assert_not_called()
        self.assertEqual(dv.call_args[0][1], "cjk")

    def test_nothing_installed(self):
        rc, pip, eng, dv, start, call, out = self.run_update([])
        self.assertEqual(rc, 0)
        for m in (pip, eng, dv, start, call):
            m.assert_not_called()
        self.assertIn("STRATA.bat", out)

    def test_a_json_that_is_no_model_config_is_skipped(self):
        """#549: a strata-*.json without "args" (not written by setup) stopped update.sh with KeyError: 'args'."""
        with tempfile.TemporaryDirectory() as d:
            p = self.config(Path(d))
            other = Path(d) / "strata-notes.json"
            other.write_text(json.dumps({"note": "mine"}), encoding="utf-8")
            broken = Path(d) / "strata-cut.json"
            broken.write_text("{\"args\": [", encoding="utf-8")
            rc, pip, eng, dv, start, call, out = self.run_update([other, broken, p])
        self.assertEqual(rc, 0, out)
        self.assertIn('skipped strata-notes.json (no "exe" or "args"): it is not a Strata model config', out)
        self.assertIn("skipped strata-cut.json (not valid JSON)", out)
        dv.assert_called_once()                                     # the real model is still refreshed
        self.assertIn("Qwen IQ3_S: up to date", out)
        self.assertIn("Strata is updated", out)

    def test_installed_configs_lists_only_model_configs(self):
        with tempfile.TemporaryDirectory() as d:
            p = self.config(Path(d))
            (Path(d) / "strata-notes.json").write_text("{}", encoding="utf-8")
            with mock.patch.object(setup, "ROOT", Path(d)), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(setup.installed_configs(), [p])

    def test_main_update_never_starts(self):
        with tempfile.TemporaryDirectory() as d:
            p = self.config(Path(d))
            with mock.patch.object(sys, "argv", ["setup.py", "--update"]), \
                    mock.patch.object(setup, "data_folder", return_value=(Path(d), [])), \
                    mock.patch.object(setup, "installed_configs", return_value=[p]), \
                    mock.patch.object(setup, "fetch_new_code", return_value=0) as fetch, \
                    mock.patch.object(setup, "update_install", return_value=0) as up, \
                    mock.patch.object(setup, "start") as start, \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(setup.main(), 0)
        fetch.assert_called_once()                           # the code fetch happens first
        up.assert_called_once()
        start.assert_not_called()


class FetchNewCode(unittest.TestCase):
    """A6: --update fetches the code itself (the former UPDATE.bat / update.sh logic, now testable here).
    git present: git pull --ff-only; a failed pull stops the update; the #1276 old-history clone is moved
    over when nothing is lost; no git: the zip guidance, then go on."""

    def run_fetch(self, git_dir, calls, runs=()):
        """calls: what each subprocess.call returns (git --version, git pull, then the recovery probes);
        runs: what each subprocess.run returns (stdout text, in call order)."""
        def run_result(stdout=""):
            return mock.Mock(stdout=stdout)
        with mock.patch.object(setup, "ROOT", Path(git_dir)), \
                mock.patch.object(setup.subprocess, "call", side_effect=calls) as sc, \
                mock.patch.object(setup.subprocess, "run", side_effect=[run_result(r) for r in runs]) as sr, \
                contextlib.redirect_stdout(io.StringIO()) as out:
            rc = setup.fetch_new_code()
        return rc, sc, sr, out.getvalue()

    def test_git_clone_pulls(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / ".git").mkdir()
            rc, sc, _sr, out = self.run_fetch(d, [0, 0])
        self.assertEqual(rc, 0)
        self.assertEqual(sc.call_args_list[0][0][0], ["git", "--version"])
        self.assertEqual(sc.call_args_list[1][0][0], ["git", "pull", "--ff-only"])
        self.assertIn("Getting the newest Strata", out)

    def test_failed_pull_stops_the_update(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / ".git").mkdir()
            # pull fails, merge-base finds common history (a normal failure, not the #1276 case)
            rc, _sc, _sr, out = self.run_fetch(d, [0, 1, 0], runs=["false"])
        self.assertEqual(rc, 1)
        self.assertIn("git pull did not succeed", out)

    def test_old_history_moved_over(self):
        """#1276: a clone from before the 2026-10-06 history cleanup, nothing edited: backup branch + move."""
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / ".git").mkdir()
            # version 0, pull 1, merge-base 1 (no common commit), rev-parse backup 1 (none yet), branch 0, checkout 0
            rc, sc, _sr, out = self.run_fetch(d, [0, 1, 1, 1, 0, 0],
                                              runs=["false", "", "main"])
        self.assertEqual(rc, 0, out)
        self.assertIn("Moved to the new history", out)
        self.assertIn("pre-cleanup-backup", out)
        self.assertEqual(sc.call_args_list[4][0][0][:2], ["git", "branch"])
        self.assertEqual(sc.call_args_list[5][0][0][:3], ["git", "checkout", "-q"])

    def test_old_history_with_local_edits_stops(self):
        """#1276 with edited tracked files: nothing is touched, the two commands are printed instead."""
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / ".git").mkdir()
            rc, sc, _sr, out = self.run_fetch(d, [0, 1, 1], runs=["false", " M setup.py"])
        self.assertEqual(rc, 1)
        self.assertIn("git branch pre-cleanup-backup && git stash push", out)
        self.assertEqual(len(sc.call_args_list), 3)          # no branch/checkout attempted

    def test_git_missing_stops(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / ".git").mkdir()
            rc, sc, _sr, out = self.run_fetch(d, [1])
        self.assertEqual(rc, 1)
        self.assertIn("git is not on PATH", out)
        self.assertEqual(len(sc.call_args_list), 1)          # no pull attempted

    def test_no_git_gives_zip_guidance_and_continues(self):
        with tempfile.TemporaryDirectory() as d:
            rc, sc, _sr, out = self.run_fetch(d, [])
        self.assertEqual(rc, 0)
        sc.assert_not_called()
        self.assertIn("archive/refs/heads/main.zip", out)
        self.assertIn("Checking this copy's engine and settings meanwhile", out)

    def test_main_update_stops_when_pull_fails(self):
        with tempfile.TemporaryDirectory() as d:
            with mock.patch.object(sys, "argv", ["setup.py", "--update"]), \
                    mock.patch.object(setup, "data_folder", return_value=(Path(d), [])), \
                    mock.patch.object(setup, "installed_configs", return_value=[]), \
                    mock.patch.object(setup, "fetch_new_code", return_value=1), \
                    mock.patch.object(setup, "update_install") as up, \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(setup.main(), 1)
        up.assert_not_called()                               # nothing is touched after a failed pull


class SettingsLine(unittest.TestCase):
    """#564: a start prints the settings it uses (the engine options without the model's paths, and the server's
    fields), so a change made by hand to strata-<model>.json shows without reading the log."""

    CFG = {"exe": "x", "host": "0.0.0.0", "port": 8081, "api_key": "secret", "gpu": [0, 1], "fit_max_tokens": True,
           "args": ["--native", "E:\\Strata\\packs\\iq3_s", "--mtp", "/s/mtp/rt", "m.gguf", "--kv", "int8",
                    "--kv-resident", "32768", "--spec-min-p", "0.5", "--vram-reserve-mib", "2048", "--mmap-experts",
                    "--prefill", "auto"]}

    def test_summary(self):
        s = setup.settings_summary(self.CFG)
        self.assertEqual(s, "--kv int8 --kv-resident 32768 --spec-min-p 0.5 --vram-reserve-mib 2048 --mmap-experts "
                            "--prefill auto; server 0.0.0.0:8081, api key set, gpu 0,1, fit_max_tokens true")
        self.assertNotIn("secret", s)
        self.assertIn("127.0.0.1:9000", setup.settings_summary({"args": []}, 9000))

    def test_a_start_prints_it(self):
        with tempfile.TemporaryDirectory() as d:
            exe = Path(d) / "strata.exe"
            exe.write_bytes(b"")
            p = Path(d) / "strata-iq3_s.json"
            args = [x for x in self.CFG["args"] if x != "m.gguf"]           # no model file here
            p.write_text(json.dumps({**self.CFG, "exe": str(exe), "gpu": 0, "args": args}), encoding="utf-8")
            out = io.StringIO()
            with mock.patch.object(setup, "gpus", lambda: []), \
                    mock.patch.object(setup, "refresh_draft_vocab"), \
                    mock.patch.object(setup, "is_wsl", lambda: False), \
                    mock.patch.object(setup.subprocess, "call", return_value=0), \
                    contextlib.redirect_stdout(out):
                setup.start(p, None, open_browser=False, yes=True)
        text = " ".join(out.getvalue().split())
        self.assertIn("Settings (strata-iq3_s.json): --kv int8 --kv-resident 32768", text)
        self.assertIn("--vram-reserve-mib 2048", text)


if __name__ == "__main__":
    unittest.main()
