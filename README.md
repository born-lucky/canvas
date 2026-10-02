# Canvas

Persistent spatial development notes for Godot 4.5+: walk or fly around a real
game scene, name places, highlight an area, and leave instructions for an AI.
Canvas is being built alongside [Feitoria: Lands Eternal](https://github.com/born-lucky/feitoria-lands-eternal).

## In the Game

Press **F8** to open or close Canvas. Gameplay pauses while Canvas is open;
scene controllers are suspended and their process modes restored on close.
Hold **right mouse** to look around; while holding it, **WASD** flies,
**Q/E** moves down/up, and **Shift** increases speed.

1. Press **+**, then click a collision surface in the scene.
2. Give the marker a name and an instruction. Press **Save**.
3. Set a radius above zero to highlight an area around the marker.
4. Press **Queue** to authorize that instruction for the worker.
5. Click a pin or select its entry to edit it. **@** focuses the camera on it.
6. Review the worker's report and game changes, then set the marker to **Done**.

**Esc** cancels placement or closes Canvas. **R** refreshes notes and reports.
Refresh replaces unsaved panel edits with the saved version.
**X** deletes the selected marker after confirmation.

## In the Editor

The Canvas dock uses the same notes file. Select a saved scene and a Node3D,
then press **+** to anchor a note at its current world position. With no single
3D node selected, **+** arms placement on collision surfaces in the 3D viewport.
Pins are drawn over the primary 3D editor viewport. Editor overlays are not
saved into the scene. Runtime-generated terrain is best annotated in play mode.

## Install

Python 3.10+ is required for installation and the worker, but not for the addon.

```powershell
python canvas.py --project "C:/path/to/game/Godot" install
```

Enable **Canvas** under Godot **Project Settings > Plugins**. This installs its
play-mode autoload. Disabling the plugin removes that autoload. A distributable
release skips the runtime tool unless `canvas/enable_in_release` is true.
Re-run installation after updating Canvas; the installed addon is a copy.

Open this repository's `project.godot` to try the small independent demo.

## Work While Away

The worker uses [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode).
Install and sign into the Codex CLI first. From the game repository root:

```powershell
python Tools/canvas/canvas.py --project Godot --workspace . list
python Tools/canvas/canvas.py --project Godot --workspace . export
python Tools/canvas/canvas.py --project Godot --workspace . work
python Tools/canvas/canvas.py --project Godot --workspace . work --watch
```

`work` processes one queued instruction. `--watch` waits for further queued
instructions and processes them one at a time. Keep the computer awake,
connected, and the worker running while you are away. This is a local worker;
the tool does not provision a cloud machine or GitHub Actions runner.

The worker is allowed to edit the specified workspace and uses the CLI's
`workspace-write` sandbox. It follows the project's AGENTS.md and workflows,
preserves existing changes, and is instructed to verify its work and leave a
report. It does not automatically commit or push changes. Instructions are
user-authored tasks: queue only work you intend to authorize.

State progression: **Draft -> Queued -> Working -> Review -> Done**.
A CLI failure or timeout becomes **Blocked**. A successful CLI exit becomes
**Review**, including reports that explain an incomplete task. A human verifies
the result before marking it Done. Reports and process logs are preserved under
`.canvas/runs/`. Stop the watch loop with Ctrl+C.

If a worker was killed or the computer restarted with a Working marker, inspect
the game changes, stop any surviving worker processes, and run:

```powershell
python Tools/canvas/canvas.py --project Godot recover MARKER_ID
```

Recovery marks the task Blocked; it never automatically retries interrupted
work. An abandoned `.canvas/notes.json.lock` directory must be removed manually
after verifying no writer is active.

## Persistence and Integration

`PROJECT/.canvas/notes.json` is versioned JSON, independent of campaign saves.
Each marker records its stable ID, name, instruction, scene path, context key,
world coordinates, radius in meters, node path hint, status, and report.
The addon and worker share an exclusive lock and atomic file replacement.
Invalid input is reported and preserved; it is not replaced with an empty file.

Implement `canvas_context() -> String` on the running scene to distinguish
procedural seeds, towns, map variants, or interiors within one scene file.
Otherwise Canvas uses the scene root's `canvas_context` metadata, defaulting to
an empty string. Use that metadata in the editor to match runtime contexts.
Feitoria supplies keys for its land-cell seed and size, and campaign location
and world seed, with a separate key for each building interior. Different keys
have separate marker sets.

Coordinates are fixed world-space snapshots, not moving object attachments.
Renaming a node does not delete its marker. Changing the scene path, terrain
generation, coordinate origin, or layout may require migrating old notes.
The area highlight is a horizontal ring; it does not drape over terrain.
Free flight surveys already-loaded geometry while the game is paused; it does
not drive a game's procedural streaming system. The first version has pins and
circular areas; arbitrary paint strokes and asset-placement tools are future work.

## Verify

```powershell
python -m unittest discover -s tests -v
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/runtime_test.gd
godot --path . --script res://tests/runtime_test.gd
```

The Godot test must print `CANVAS_TEST_OK`. The rendered run also writes
`test-output/canvas.png`. Worker tests use a simulated CLI; they do not send
paid AI requests or modify a game. The addon uses Godot's
[EditorPlugin API](https://docs.godotengine.org/en/stable/classes/class_editorplugin.html).
