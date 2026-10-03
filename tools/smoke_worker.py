"""Optional live Codex worker test. Uses your account; edits only a temporary fixture."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--model", help="A model supported by your CLI account")
parser.add_argument("--windows-sandbox", choices=["elevated", "unelevated"])
args = parser.parse_args()

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("canvas", root / "canvas.py")
canvas = importlib.util.module_from_spec(spec)
spec.loader.exec_module(canvas)

with tempfile.TemporaryDirectory(prefix="canvas-worker-smoke-") as temporary:
    project = Path(temporary)
    subprocess.run(["git", "init", "-q", str(project)], check=True)
    fixture = project / "model.json"
    fixture.write_text(json.dumps({"objects": [{"id": "gatehouse", "bevel_m": 0},
                                             {"id": "roof", "bevel_m": 0}]}), encoding="utf-8")
    note = {"id": "x00000000000000000000000000000001", "name": "Gatehouse corner",
            "instruction": "Edit only model.json. Find the object with id gatehouse and set its bevel_m to 0.15. Keep the roof object unchanged. Validate the JSON and report the result. This is a small test fixture; do not edit any other file.",
            "scene": "model.json", "context": "test", "node_path": "gatehouse",
            "position": [0, 0, 0], "radius": 0, "status": "queued", "engine": "fixture",
            "targets": [{"node_path": "gatehouse", "name": "Gatehouse", "type": "model",
                         "scene": "model.json", "mesh": "model.json"}],
            "strokes": [{"points": [[0, 1, 0], [1, 1, 0]], "normal": [0, 0, 1],
                         "width": 0.03, "color": "ffda67ff", "projection": "plane"}]}
    path = project / ".canvas/notes.json"
    with canvas.locked(path): canvas.write_notes(path, {"version": 1, "notes": [note]})
    canvas.run_one(project, path, 120, model=args.model, isolated=True, trusted=True, windows_sandbox=args.windows_sandbox)
    finished = canvas.read_notes(path)["notes"][0]
    data = json.loads(fixture.read_text(encoding="utf-8"))
    if finished["status"] != "review" or data["objects"] != [{"id": "gatehouse", "bevel_m": 0.15}, {"id": "roof", "bevel_m": 0}]:
        print(finished.get("result", "No report"))
        for log in (path.parent / "runs").glob("*/events.log"):
            content = log.read_text(encoding="utf-8", errors="replace")
            print(content[:1000] + "\n...\n" + content[-2000:])
        raise SystemExit("CANVAS_LIVE_WORKER_FAILED")
    print("CANVAS_LIVE_WORKER_OK")
