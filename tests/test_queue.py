import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("canvas", Path(__file__).parents[1] / "canvas.py")
canvas = importlib.util.module_from_spec(spec)
spec.loader.exec_module(canvas)


class QueueTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.project = Path(self.directory.name)
        self.path = self.project / ".canvas" / "notes.json"
        self.path.parent.mkdir()
        self.note = {"id": "marker-1", "name": "Gate", "instruction": "Add a gate",
                     "scene": "res://test.tscn", "context": "seed-42", "node_path": "Ground",
                     "position": [1, 2, 3], "radius": 5, "status": "queued"}
        canvas.write_notes(self.path, {"version": 1, "notes": [self.note]})

    def test_exclusive_claim_and_completion(self):
        self.assertEqual(canvas.claim(self.path)["status"], "working")
        self.assertIsNone(canvas.claim(self.path))
        canvas.finish(self.path, "marker-1", "review", "Tested gate")
        note = canvas.read_notes(self.path)["notes"][0]
        self.assertEqual(note["status"], "review")
        self.assertEqual(note["result"], "Tested gate")

    def test_blank_instruction_is_blocked(self):
        self.note["instruction"] = " "
        canvas.write_notes(self.path, {"version": 1, "notes": [self.note]})
        self.assertIsNone(canvas.claim(self.path))
        self.assertEqual(canvas.read_notes(self.path)["notes"][0]["status"], "blocked")

    def test_corrupt_input_preserved(self):
        self.path.write_text("bad JSON", encoding="utf-8")
        with self.assertRaises(ValueError):
            canvas.claim(self.path)
        self.assertEqual(self.path.read_text(), "bad JSON")
        self.assertFalse(Path(str(self.path) + ".lock").exists())

    def test_lock_exclusion(self):
        with canvas.locked(self.path):
            with self.assertRaises(RuntimeError):
                canvas.claim(self.path)

    def test_duplicate_ids_rejected(self):
        canvas.write_notes(self.path, {"version": 1, "notes": [self.note, self.note]})
        with self.assertRaises(ValueError):
            canvas.read_notes(self.path)

    def test_successful_worker_returns_review(self):
        def fake_run(command, **kwargs):
            report = Path(command[command.index("--output-last-message") + 1])
            report.write_text("Added gate; validation passed.", encoding="utf-8")
            self.assertEqual(kwargs["cwd"], self.project)
            self.assertIn("seed-42", kwargs["input"])
            self.assertIn("workspace-write", command)
            return type("Result", (), {"returncode": 0})()
        with patch.object(canvas.shutil, "which", return_value="codex"), patch.object(canvas, "execute_cli", side_effect=fake_run):
            self.assertTrue(canvas.run_one(self.project, self.path, 60))
        self.assertEqual(canvas.read_notes(self.path)["notes"][0]["status"], "review")

    def test_worker_failure_is_blocked(self):
        with patch.object(canvas.shutil, "which", return_value="codex"), patch.object(canvas, "execute_cli", return_value=type("Result", (), {"returncode": 1})()):
            canvas.run_one(self.project, self.path, 60)
        self.assertEqual(canvas.read_notes(self.path)["notes"][0]["status"], "blocked")

    def test_worker_timeout_is_blocked(self):
        with patch.object(canvas.shutil, "which", return_value="codex"), patch.object(canvas, "execute_cli", side_effect=canvas.subprocess.TimeoutExpired("codex", 60)):
            canvas.run_one(self.project, self.path, 60)
        self.assertEqual(canvas.read_notes(self.path)["notes"][0]["status"], "blocked")

    def test_root_array_is_invalid(self):
        self.path.write_text("[]", encoding="utf-8")
        with self.assertRaises(ValueError):
            canvas.read_notes(self.path)

    def test_install_only_addon_files(self):
        canvas.install(self.project)
        self.assertTrue((self.project / "addons/canvas/runtime.gd").is_file())
        self.assertFalse((self.project / "canvas.py").exists())


if __name__ == "__main__":
    unittest.main()
