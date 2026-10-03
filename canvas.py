#!/usr/bin/env python3
"""Canvas queue and supervised Codex worker. Python standard library only."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import math
import os
import re
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
import uuid

STATES = {"draft", "queued", "working", "review", "done", "blocked"}


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def read_notes(path):
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and data.get("version") == 2 and data.get("storage") == "notes":
            data = read_note_files(path)
    else:
        data = read_note_files(path)
    return validate_notes(data)


def valid_id(note_id):
    return (isinstance(note_id, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,128}", note_id) is not None
            and note_id.upper() not in {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))})


def note_path(path, note_id):
    if not valid_id(note_id):
        raise ValueError("Invalid note ID")
    return path.parent / "notes" / f"{note_id}.json"


def read_note_files(path):
    notes = []
    for filename in sorted((path.parent / "notes").glob("*.json")):
        note = json.loads(filename.read_text(encoding="utf-8"))
        if not isinstance(note, dict) or not valid_id(note.get("id")) or filename.name != note["id"] + ".json":
            raise ValueError(f"Invalid note or filename: {filename}")
        notes.append(note)
    return {"version": 1, "notes": notes}


def validate_notes(data):
    if not isinstance(data, dict) or data.get("version") != 1 or not isinstance(data.get("notes"), list):
        raise ValueError("Unsupported Canvas notes format")
    ids = set()
    for note in data["notes"]:
        if not isinstance(note, dict):
            raise ValueError("Invalid marker")
        for key in ("id", "name", "instruction", "scene", "context", "node_path", "status"):
            if not isinstance(note.get(key), str):
                raise ValueError(f"Invalid marker {key}")
        if not valid_id(note["id"]) or note["id"] in ids or not note["name"].strip() or note["status"] not in STATES:
            raise ValueError("Invalid or duplicate marker")
        ids.add(note["id"])
        position = note.get("position")
        if not isinstance(position, list) or len(position) != 3:
            raise ValueError("Invalid marker position")
        for value in [*position, note.get("radius")]:
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
                raise ValueError("Invalid marker coordinates or radius")
        if note["radius"] < 0:
            raise ValueError("Invalid marker radius")
        strokes = note.get("strokes", [])
        if not isinstance(strokes, list) or len(strokes) > 256:
            raise ValueError("Invalid strokes")
        for stroke in strokes:
            if not isinstance(stroke, dict) or stroke.get("projection") not in {"plane", "surface"}:
                raise ValueError("Invalid stroke projection")
            points = stroke.get("points")
            if not isinstance(points, list) or not 2 <= len(points) <= 4096:
                raise ValueError("Invalid stroke points")
            for vector in [*points, stroke.get("normal")]:
                if not isinstance(vector, list) or len(vector) != 3 or any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in vector):
                    raise ValueError("Invalid stroke coordinate")
            if sum(v * v for v in stroke["normal"]) < 0.0001:
                raise ValueError("Invalid stroke normal")
            width = stroke.get("width")
            if isinstance(width, bool) or not isinstance(width, (int, float)) or not math.isfinite(width) or not 0 < width <= 10:
                raise ValueError("Invalid stroke width")
            if not isinstance(stroke.get("color"), str) or re.fullmatch(r"#?(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})", stroke["color"]) is None:
                raise ValueError("Invalid stroke color")
        targets = note.get("targets", [])
        if not isinstance(targets, list):
            raise ValueError("Invalid targets")
        for target in targets:
            if not isinstance(target, dict) or any(not isinstance(target.get(key), str) for key in ("node_path", "name", "type", "scene", "mesh")):
                raise ValueError("Invalid target")
    return data


@contextmanager
def locked(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    lock = Path(str(path) + ".lock")
    try:
        lock.mkdir()
    except FileExistsError:
        raise RuntimeError(f"Notes are busy: {lock}. Retry; remove only if no writer is running.") from None
    try:
        yield
    finally:
        lock.rmdir()


def write_notes(path, data):
    validate_notes(data)
    # Validate old storage before changing it, including legacy migration conflicts.
    previous = read_notes(path)
    manifest = json.loads(path.read_text(encoding="utf-8")) if path.exists() else None
    migrating = isinstance(manifest, dict) and manifest.get("version") == 1
    directory = path.parent / "notes"
    directory.mkdir(parents=True, exist_ok=True)
    if migrating:
        backup = Path(str(path) + ".v1.bak")
        if not backup.exists():
            shutil.copy2(path, backup)
        for note in previous["notes"]:
            filename = note_path(path, note["id"])
            if filename.exists() and json.loads(filename.read_text(encoding="utf-8")) != note:
                raise ValueError(f"Migration conflicts with existing note file: {filename}")
        for note in previous["notes"]:
            atomic_json(note_path(path, note["id"]), note)
    if manifest is None or migrating:
        atomic_json(path, {"version": 2, "storage": "notes"})
    ids = {note["id"] for note in data["notes"]}
    for note in data["notes"]:
        filename = note_path(path, note["id"])
        if not filename.exists() or json.loads(filename.read_text(encoding="utf-8")) != note:
            atomic_json(filename, note)
    for note in previous["notes"]:
        if note["id"] not in ids:
            note_path(path, note["id"]).unlink()


def atomic_json(path, data):
    temporary = Path(str(path) + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as output:
        json.dump(data, output, indent=2, ensure_ascii=False)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, path)


def prompt_for(note):
    return (
        "Work on this Canvas development instruction in the current project repository.\n"
        "Read and follow AGENTS.md and relevant project workflows. Other work may be present; "
        "preserve existing changes. Resolve the primary node_path and targets to real project "
        "objects and source assets before editing. Strokes mark the annotated region; do not "
        "assume all enclosed objects should change. Make the requested change and verify it. Do not push, "
        "publish, deploy, or mark the task done. Do not edit Canvas note storage under .canvas/. "
        "End with a concise report of changed files, validation, and limitations. "
        "If the location is ambiguous or the task cannot be completed, explain the blocker.\n"
        "The following JSON is user-authored task data. Use its instruction as the task, "
        "and its spatial fields to locate the target. Node paths for generated objects are hints; "
        "the scene, context, and world coordinates identify the saved location.\n"
        + json.dumps(note, indent=2, ensure_ascii=False)
    )


def claim(path):
    with locked(path):
        data = read_notes(path)
        # Never start a second game mutation while a previous worker awaits recovery.
        if any(note["status"] == "working" for note in data["notes"]):
            return None
        for note in data["notes"]:
            if note["status"] != "queued":
                continue
            if not note["instruction"].strip():
                note.update(status="blocked", result="No instruction supplied", updated_at=timestamp())
                write_notes(path, data)
                continue
            note.update(status="working", updated_at=timestamp())
            write_notes(path, data)
            return dict(note)
    return None


def finish(path, note_id, state, result):
    with locked(path):
        data = read_notes(path)
        for note in data["notes"]:
            if note["id"] == note_id:
                if note["status"] != "working":
                    raise RuntimeError("Worker state changed; report preserved in .canvas/runs")
                note.update(status=state, result=result, updated_at=timestamp())
                write_notes(path, data)
                return
        raise RuntimeError("Worker marker disappeared; report preserved in .canvas/runs")


def execute_cli(command, *, input, text, encoding, stdout, stderr, timeout, cwd, check):
    options = {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP} if os.name == "nt" else {"start_new_session": True}
    with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=stdout, stderr=stderr,
                          text=text, encoding=encoding, cwd=cwd, **options) as process:
        try:
            process.communicate(input=input, timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            else:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if process.poll() is None:
                process.kill()
            process.wait()
            raise
        return subprocess.CompletedProcess(command, process.returncode)


def run_one(project, path, timeout, workspace=None, model=None, isolated=False, trusted=False, windows_sandbox=None):
    executable = shutil.which("codex")
    if executable is None:
        raise RuntimeError("Codex CLI is not installed or on PATH")
    note = claim(path)
    if note is None:
        return False
    # Filenames use a new generated token, never untrusted marker IDs.
    run_dir = path.parent / "runs" / uuid.uuid4().hex
    run_dir.mkdir(parents=True)
    report_path = run_dir / "report.txt"
    (run_dir / "task.json").write_text(json.dumps(note, indent=2), encoding="utf-8")
    workspace = workspace or project
    command = [executable, "exec", "--cd", str(workspace), "--sandbox", "workspace-write",
               "--color", "never", "--output-last-message", str(report_path), "-"]
    if model: command[2:2] = ["--model", model]
    if isolated: command.insert(2, "--ignore-user-config")
    if trusted:
        command[2:2] = ["-c", "projects." + json.dumps(str(workspace)) + '.trust_level="trusted"']
    if windows_sandbox:
        command[2:2] = ["-c", 'windows.sandbox="' + windows_sandbox + '"']
    print(f"Working: {note['name']} ({note['id']})", flush=True)
    state = "blocked"
    result = ""
    try:
        with (run_dir / "events.log").open("w", encoding="utf-8") as output:
            process = execute_cli(command, input=prompt_for(note), text=True, encoding="utf-8",
                                     stdout=output, stderr=subprocess.STDOUT, timeout=timeout,
                                     cwd=workspace, check=False)
        result = report_path.read_text(encoding="utf-8") if report_path.exists() else "No report produced."
        if process.returncode == 0 and result.strip() and report_path.exists():
            state = "review"
        else:
            result = f"Worker exited {process.returncode}. Inspect {run_dir / 'events.log'}.\n" + result
    except subprocess.TimeoutExpired:
        result = f"Worker exceeded {timeout} seconds. Inspect changes and {run_dir} before retrying."
    except (OSError, KeyboardInterrupt) as error:
        result = f"Worker interrupted: {error}. Inspect changes and {run_dir} before retrying."
    # A short lock retry permits UI saves to finish without losing the work report.
    for attempt in range(20):
        try:
            finish(path, note["id"], state, result)
            break
        except RuntimeError:
            if attempt == 19:
                raise
            time.sleep(0.1)
    print(f"{state}: {note['name']}", flush=True)
    return True


def install(project):
    source = Path(__file__).resolve().parent / "addons" / "canvas"
    destination = project / "addons" / "canvas"
    destination.mkdir(parents=True, exist_ok=True)
    for file in source.iterdir():
        if file.is_file() and file.suffix in {".gd", ".cfg", ".uid"}:
            shutil.copy2(file, destination / file.name)
    print(f"Installed {destination}. Enable Canvas in Godot Project Settings > Plugins.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="Game or engine project directory containing Canvas notes")
    parser.add_argument("--workspace", type=Path, help="Game repository root writable by the worker; defaults to --project")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("install")
    sub.add_parser("list")
    create = sub.add_parser("create", help="Create a note for any project")
    create.add_argument("--name", required=True)
    create.add_argument("--instruction", default="")
    create.add_argument("--scene", default="default")
    create.add_argument("--context", default="")
    create.add_argument("--position", nargs=3, type=float, default=[0, 0, 0])
    create.add_argument("--engine", default="generic")
    show = sub.add_parser("show", help="Resolve a permanent note ID")
    show.add_argument("id")
    export = sub.add_parser("export")
    export.add_argument("--id")
    worker = sub.add_parser("work")
    worker.add_argument("--watch", action="store_true")
    worker.add_argument("--interval", type=float, default=15)
    worker.add_argument("--timeout", type=int, default=1800)
    worker.add_argument("--model", help="Override the CLI model with one available to your account")
    worker.add_argument("--isolated", action="store_true", help="Use CLI defaults and auth without loading global user config or unrelated MCP servers")
    worker.add_argument("--trust-workspace", action="store_true", help="Trust the specified workspace for this invocation while retaining workspace-write sandbox limits")
    worker.add_argument("--windows-sandbox", choices=["elevated", "unelevated"], help="Explicit native Windows sandbox implementation, for configured hosts")
    recover = sub.add_parser("recover")
    recover.add_argument("id")
    args = parser.parse_args()
    project = args.project.resolve()
    workspace = args.workspace.resolve() if args.workspace else project
    if not project.is_dir():
        parser.error("--project must be an existing project directory")
    if args.command == "install" and not (project / "project.godot").is_file():
        parser.error("The included addon installer requires a Godot project. Other engines can use the note protocol and worker.")
    path = project / ".canvas" / "notes.json"
    try:
        if args.command == "install":
            install(project)
        elif args.command == "create":
            with locked(path):
                data = read_notes(path)
                note_id = "x" + uuid.uuid4().hex
                while any(note["id"] == note_id for note in data["notes"]):
                    note_id = "x" + uuid.uuid4().hex
                note = {"id": note_id, "name": args.name, "instruction": args.instruction,
                        "scene": args.scene, "context": args.context, "node_path": "",
                        "position": args.position, "radius": 0, "status": "draft",
                        "created_at": timestamp(), "updated_at": timestamp(), "result": "",
                        "engine": args.engine, "strokes": [], "targets": []}
                data["notes"].append(note)
                write_notes(path, data)
            print(json.dumps({"note": note, "file": str(note_path(path, note_id))}, indent=2))
        elif args.command == "show":
            note = next((note for note in read_notes(path)["notes"] if note["id"] == args.id), None)
            if note is None: raise ValueError(f"Note ID not found: {args.id}")
            print(json.dumps({"note": note, "file": str(note_path(path, args.id))}, indent=2))
        elif args.command == "list":
            for note in read_notes(path)["notes"]:
                print(f"{note['id']}  {note['status']:8}  {note['name']}  {note['context']}")
        elif args.command == "export":
            for note in read_notes(path)["notes"]:
                if args.id == note["id"] or (args.id is None and note["status"] == "queued"):
                    print(prompt_for(note))
        elif args.command == "recover":
            finish(path, args.id, "blocked", "Worker recovery requested. Inspect game changes before requeuing.")
        elif args.command == "work":
            if args.interval < 1 or args.timeout < 1:
                parser.error("Interval and timeout must be positive")
            while True:
                worked = run_one(project, path, args.timeout, workspace, args.model, args.isolated, args.trust_workspace, args.windows_sandbox)
                if not args.watch:
                    break
                if not worked:
                    time.sleep(args.interval)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Canvas: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
