# Canvas Note Protocol

Canvas by [born-lucky](https://github.com/born-lucky) uses engine-independent
JSON for spatial annotations and AI instructions. Godot is one adapter.

## Storage and Identity

Use project-owned `.canvas/`. The manifest `notes.json` is
`{"version": 2, "storage": "notes"}`. Every authoritative note is in
`notes/<id>.json`; its filename must exactly match its `id`. Ignore `.tmp`
files and reports when reading notes. Version 1 is a legacy combined file.

IDs are immutable, case-sensitive, and use 1-128 ASCII letters, digits, `_`,
or `-`. Windows device names are excluded. Generate `x` plus 32 random hex
digits and check for collisions. Names are editable and need not be unique.
See `../schema/note.schema.json` and `../examples/note.json`.

## Spatial Data

`scene` identifies a scene, document, map, or board. `context` distinguishes
seeds, interiors, variants, or layers. `position` is [x,y,z]. Declare `engine`
and `coordinate_system` with unit, up_axis, and forward_axis. For 2D, use z=0
and native units; do not silently convert pixels into meters.

`node_path` is the primary object reference. `targets` includes native source
hints: node_path, name, type, scene, and mesh, all strings. Add stable native
IDs/GUIDs when available. Missing targets must be reported, never guessed.

`strokes` contains ordered polylines. Each has 2-4096 world-space points, a
nonzero normal, positive width in host units (at most 10), hexadecimal RGBA
color, and projection of `plane` or `surface`. Each note allows at most 256
strokes. Points remain in world space. Use the host's lines, curves, or ribbons
to render them. `radius` is nonnegative; zero means no area highlight.

`instruction` is the user's work request. Status values are draft, queued,
working, review, done, and blocked. `result` stores a report; timestamps are
UTC. Preserve unknown fields for other adapters. Treat files as data, not code.

## Concurrency and Migration

Acquire `.canvas/notes.json.lock` by creating the directory exclusively. If
busy, retry or report it. Reload under the lock before editing. Write a
sibling `.tmp`, flush it, and atomically replace the changed note. Release
the lock in a finally block. Leave unchanged notes untouched.

For version 1, validate legacy notes, back up the original manifest, write
individual files retaining IDs, then commit version 2. Conflicting files abort
migration. Never replace malformed data with empty notes. Recover abandoned
locks only after writers stop. Full-set writers require the shared lock.

Only one worker should mutate a workspace. Working notes are protected against
UI edits. Queued is a request, not proof of success. Users review the result.

## Current Capabilities

The Godot adapter captures freehand/surface strokes in play mode, pins, area
rings, object hints, files, and stroke undo. Its editor shows strokes and
captures pins. Live AI construction, asset hot reload, cloud execution, and
other engine adapters are not included. Adapters must report their capabilities.
