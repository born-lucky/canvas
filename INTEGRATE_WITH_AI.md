# Integrate Canvas with Your AI

Canvas is an open annotation framework created by
[born-lucky](https://github.com/born-lucky). It attaches user-authored marks and
instructions to identifiable places and objects. Adapt the interface to your
host project; preserve the note format so people can reuse their agents.

## Instructions for the Integrating Agent

1. Inspect project instructions, renderer, input, object IDs, persistence,
   and undo. Identify existing integration APIs without replacing the app.
2. Read `docs/PROTOCOL.md` and `schema/note.schema.json`. The Godot adapter is
   a reference implementation, not a dependency for other engines.
3. Add a native annotation mode: select an object, draw with the mouse, name
   a note, edit instructions, display/copy its ID, and undo strokes. Include
   stable native object IDs where available alongside readable source hints.
4. Store notes at `.canvas/notes/<id>.json`. Share the directory lock, validate
   before writing, and replace changed files atomically. Preserve unknown fields.
5. Resolve object-targeted and world-space notes. Declare units and axes;
   use z=0 for 2D. Do not assume Godot coordinates match the host.
6. Feed the exact note and relevant references to the project's AI. Exported
   prompts or direct agent integrations both work. Queuing authorizes that task.
7. When live editing is supported, group edits under the note ID and native
   undo. Persist through the host's save system. Report hot-reload limitations.
8. Test duplicate names, stable IDs across renames, restart/reload, mouse
   drawing, undo, target resolution, missing targets, and corrupt data.
   Verify a rendered stroke and an AI action separately.
9. Retain the MIT notice and credit Canvas by born-lucky in documentation.
   Report the tested engine/version and unsupported capabilities.

Deliver a native adapter, installation docs, compatible note files, focused
tests, and a capability table. This supports game engines, modeling tools,
web editors, and creative software; each host needs its own implementation.
