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
        with self.assertRaises(ValueError):
            canvas.write_notes(self.path, {"version": 1, "notes": [self.note, self.note]})

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

    def test_worker_options_preserve_write_sandbox(self):
        def fake_run(command, **kwargs):
            self.assertIn("--ignore-user-config", command)
            self.assertEqual(command[command.index("--model") + 1], "fixture-model")
            self.assertEqual(command[command.index("--sandbox") + 1], "workspace-write")
            self.assertIn('windows.sandbox="unelevated"', command)
            self.assertIn("projects." + json.dumps(str(self.project)) + '.trust_level="trusted"', command)
            Path(command[command.index("--output-last-message") + 1]).write_text("Fixture report", encoding="utf-8")
            return type("Result", (), {"returncode": 0})()
        with patch.object(canvas.shutil, "which", return_value="codex"), patch.object(canvas, "execute_cli", side_effect=fake_run):
            canvas.run_one(self.project, self.path, 60, model="fixture-model", isolated=True,
                           trusted=True, windows_sandbox="unelevated")
        self.assertEqual(canvas.read_notes(self.path)["notes"][0]["status"], "review")

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

    def test_individual_file_and_rename_preserves_id(self):
        filename = self.path.parent / "notes" / "marker-1.json"
        self.assertEqual(json.loads(filename.read_text())["name"], "Gate")
        self.note["name"] = "North gate"
        canvas.write_notes(self.path, {"version": 1, "notes": [self.note]})
        self.assertEqual(json.loads(filename.read_text())["id"], "marker-1")
        self.assertEqual(json.loads(filename.read_text())["name"], "North gate")
        self.assertEqual(len(list(filename.parent.glob("*.json"))), 1)

    def test_legacy_migration_keeps_ids_and_backup(self):
        legacy_path = self.project / "legacy" / "notes.json"
        legacy_path.parent.mkdir()
        old = {"version": 1, "notes": [self.note]}
        legacy_path.write_text(json.dumps(old), encoding="utf-8")
        self.assertEqual(canvas.read_notes(legacy_path), old)
        canvas.write_notes(legacy_path, old)
        self.assertEqual(canvas.read_notes(legacy_path), old)
        self.assertEqual(json.loads(Path(str(legacy_path) + ".v1.bak").read_text()), old)
        self.assertEqual(json.loads(legacy_path.read_text())["version"], 2)

    def test_filename_mismatch_and_path_traversal_rejected(self):
        filename = canvas.note_path(self.path, self.note["id"])
        altered = dict(self.note, id="different-id")
        filename.write_text(json.dumps(altered), encoding="utf-8")
        with self.assertRaises(ValueError):
            canvas.read_notes(self.path)
        with self.assertRaises(ValueError):
            canvas.note_path(self.path, "../../escape")

    def test_unrelated_note_file_unchanged(self):
        second = dict(self.note, id="marker-2", name="Gate")
        canvas.write_notes(self.path, {"version": 1, "notes": [self.note, second]})
        filename = canvas.note_path(self.path, second["id"])
        original_time = filename.stat().st_mtime_ns
        canvas.claim(self.path)
        self.assertEqual(filename.stat().st_mtime_ns, original_time)

    def test_corrupt_individual_note_is_preserved(self):
        filename = canvas.note_path(self.path, self.note["id"])
        filename.write_text("bad JSON", encoding="utf-8")
        with self.assertRaises(ValueError):
            canvas.claim(self.path)
        self.assertEqual(filename.read_text(), "bad JSON")

    def test_stroke_and_object_metadata_round_trip(self):
        self.note["strokes"] = [{"points": [[1, 2, 3], [2, 3, 4]], "normal": [0, 0, 1],
                                  "color": "ffda67ff", "width": 0.03, "projection": "plane"}]
        self.note["targets"] = [{"node_path": "Gatehouse", "name": "Gatehouse", "type": "StaticBody3D",
                                 "scene": "res://test.tscn", "mesh": "res://gate.glb"}]
        canvas.write_notes(self.path, {"version": 1, "notes": [self.note]})
        self.assertEqual(canvas.read_notes(self.path)["notes"][0], self.note)
        self.assertIn("res://gate.glb", canvas.prompt_for(self.note))

    def test_invalid_stroke_cannot_replace_note(self):
        before = canvas.note_path(self.path, self.note["id"]).read_text()
        self.note["strokes"] = [{"points": [[1, 2, 3]], "normal": [0, 0, 1],
                                  "color": "ffda67ff", "width": 0.03, "projection": "plane"}]
        with self.assertRaises(ValueError):
            canvas.write_notes(self.path, {"version": 1, "notes": [self.note]})
        self.assertEqual(canvas.note_path(self.path, self.note["id"]).read_text(), before)

    def test_protocol_example_is_valid(self):
        example = json.loads((Path(__file__).parents[1] / "examples/note.json").read_text())
        canvas.validate_notes({"version": 1, "notes": [example]})

    def test_visibility_round_trip_and_validation(self):
        self.note["visible"] = False
        canvas.write_notes(self.path, {"version": 1, "notes": [self.note]})
        self.assertIs(canvas.read_notes(self.path)["notes"][0]["visible"], False)
        self.note["visible"] = "false"
        with self.assertRaises(ValueError):
            canvas.write_notes(self.path, {"version": 1, "notes": [self.note]})

    def test_create_and_resolve_without_godot(self):
        import io
        from contextlib import redirect_stdout
        argv = ["canvas", "--project", str(self.project), "create", "--name", "Other engine note", "--engine", "custom"]
        output = io.StringIO()
        with patch.object(canvas.sys, "argv", argv), redirect_stdout(output):
            self.assertEqual(canvas.main(), 0)
        created = json.loads(output.getvalue())
        self.assertEqual(created["note"]["engine"], "custom")
        output = io.StringIO()
        with patch.object(canvas.sys, "argv", ["canvas", "--project", str(self.project), "show", created["note"]["id"]]), redirect_stdout(output):
            self.assertEqual(canvas.main(), 0)
        self.assertEqual(json.loads(output.getvalue()), created)


if __name__ == "__main__":
    unittest.main()
