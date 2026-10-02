#!/usr/bin/env python3
"""Canvas queue and supervised Codex worker. Python standard library only."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

STATES = {"draft", "queued", "working", "review", "done", "blocked"}


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def read_notes(path):
    if not path.exists():
        return {"version": 1, "notes": []}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("version") != 1 or not isinstance(data.get("notes"), list):
        raise ValueError("Unsupported Canvas notes format")
    ids = set()
    for note in data["notes"]:
        if not isinstance(note, dict):
            raise ValueError("Invalid marker")
        for key in ("id", "name", "instruction", "scene", "context", "node_path", "status"):
            if not isinstance(note.get(key), str):
                raise ValueError(f"Invalid marker {key}")
        if not note["id"] or note["id"] in ids or not note["name"].strip() or note["status"] not in STATES:
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
    temporary = Path(str(path) + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as output:
        json.dump(data, output, indent=2, ensure_ascii=False)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, path)


def prompt_for(note):
    return (
        "Work on this Canvas development instruction in the current game repository.\n"
        "Read and follow AGENTS.md and relevant project workflows. Other work may be present; "
        "preserve existing changes. Make the requested game change and verify it. Do not push, "
        "publish, deploy, or mark the task done. Do not edit .canvas/notes.json. "
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


def run_one(project, path, timeout, workspace=None):
    executable = shutil.which("codex")
    if executable is None:
        raise RuntimeError("Codex CLI is not installed or on PATH")
    note = claim(path)
    if note is None:
        return False
    # Filenames use a new generated token, never untrusted marker IDs.
    import uuid
    run_dir = path.parent / "runs" / uuid.uuid4().hex
    run_dir.mkdir(parents=True)
    report_path = run_dir / "report.txt"
    (run_dir / "task.json").write_text(json.dumps(note, indent=2), encoding="utf-8")
    workspace = workspace or project
    command = [executable, "exec", "--cd", str(workspace), "--sandbox", "workspace-write",
               "--color", "never", "--output-last-message", str(report_path), "-"]
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
    parser.add_argument("--project", type=Path, required=True, help="Godot project directory")
    parser.add_argument("--workspace", type=Path, help="Game repository root writable by the worker; defaults to --project")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("install")
    sub.add_parser("list")
    export = sub.add_parser("export")
    export.add_argument("--id")
    worker = sub.add_parser("work")
    worker.add_argument("--watch", action="store_true")
    worker.add_argument("--interval", type=float, default=15)
    worker.add_argument("--timeout", type=int, default=1800)
    recover = sub.add_parser("recover")
    recover.add_argument("id")
    args = parser.parse_args()
    project = args.project.resolve()
    workspace = args.workspace.resolve() if args.workspace else project
    if not (project / "project.godot").is_file():
        parser.error("--project must contain project.godot")
    path = project / ".canvas" / "notes.json"
    try:
        if args.command == "install":
            install(project)
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
                worked = run_one(project, path, args.timeout, workspace)
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
