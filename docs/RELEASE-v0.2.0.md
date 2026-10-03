Canvas is an open annotation framework created by **[born-lucky](https://github.com/born-lucky)**.
Draw what you mean and give your AI a specific note, location, and object to work on.

This release adds mouse-drawn 3D loops, arrows, sketches, surface strokes,
ink selection, drawing depth, stroke undo, and object/source references.
Each note has a permanent ID and its own project-owned JSON file.

## Downloads

- **canvas-godot-v0.2.0.zip:** ready-to-install Godot addon. Extract `addons/canvas`
  into your project and enable Canvas in Project Settings > Plugins. Press F8
  while playing. Python and an AI account are optional.
- **canvas-framework-v0.2.0.zip:** full framework, CLI worker, note schema,
  protocol, demo, tests, and AI integration brief for adapting other tools.

## Other Engines

Give your AI the integration prompt in the [README](https://github.com/born-lucky/canvas#use-it-in-your-project).
The protocol and worker are engine-independent. Godot is the included adapter;
other engines require a native integration and testing.

## Verification and Boundaries

Python persistence/queue tests, input-driven Godot drawing, source references,
surface strokes, undo, camera/pause restoration, schema validation, Feitoria
scope checks, and a real OpenGL screenshot were exercised locally on Windows.

The optional AI worker requires a configured CLI account and returns changes
for human review. Its local live check was blocked by Windows sandbox access
to the temporary fixture; AI editing is not verified end to end on that setup.
Drawing identifies a requested change; it does not itself
repair geometry. Live scene editing, asset hot reload, other engine adapters,
and cloud workers are not implemented yet.

Free for personal and commercial use under the MIT license. Credit and follow
[born-lucky](https://github.com/born-lucky) for more AI-built creative tools.
