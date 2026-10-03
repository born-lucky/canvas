extends SceneTree

const Store = preload("res://addons/canvas/store.gd")
var failed := false

func check(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error("Canvas test: " + description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var store := Store.new()
	store.path = "user://canvas-tests/%s/notes.json" % str(Time.get_ticks_usec())
	var note := store.create("res://demo/demo.tscn", "seed-42", Vector3(2, 0, -3), "Ground")
	note.name = "North gate"
	note.instruction = "Add a ruined gatehouse."
	note.radius = 5.0
	check(store.save_note(note), "first save")
	check(FileAccess.file_exists(store.note_path(note.id)), "individual project note file")
	check(note.id.begins_with("x"), "copyable stable identifier")
	check(store.reload() and store.notes.size() == 1, "reload")
	check(store.position_of(store.notes[0]).is_equal_approx(Vector3(2, 0, -3)), "coordinates round trip")
	check(store.notes[0].context == "seed-42", "seed preserved")
	var other := Store.new()
	other.path = store.path
	var second := other.create("res://demo/demo.tscn", "seed-43", Vector3.ZERO)
	check(other.save_note(second), "second writer")
	note.name = "Old north gate"
	check(store.save_note(note) and store.notes.size() == 2, "preserve second writer's marker")
	check(FileAccess.file_exists(store.note_path(note.id)), "rename preserves note filename and ID")
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(store.path) + ".lock")
	check(not store.save_note(note), "lock prevents concurrent writes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path) + ".lock")
	check(store.delete_note(str(second.id)), "delete")
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	check(not store.save_note(note), "corrupt file cannot be overwritten")
	check(FileAccess.get_file_as_string(store.path) == "broken", "corrupt input preserved")
	cleanup(store.path)
	var legacy := Store.new()
	legacy.path = "user://canvas-tests/legacy-%s/notes.json" % str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(legacy.path).get_base_dir())
	legacy._atomic_json(ProjectSettings.globalize_path(legacy.path), {"version": 1, "notes": [note]})
	check(legacy.reload() and legacy.notes[0].id == note.id, "reads legacy notes")
	check(legacy.save_note(note), "migrates legacy notes")
	check(FileAccess.file_exists(legacy.note_path(note.id)), "legacy note gets individual file")
	check(FileAccess.file_exists(legacy.path + ".v1.bak"), "legacy notes backed up")
	cleanup(legacy.path)
	var scene: Node3D = load("res://demo/demo.tscn").instantiate()
	scene.set_script(load("res://tests/pause_host.gd"))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var canvas := root.get_node("Canvas")
	canvas.panel.store.path = "user://canvas-tests/runtime-%s/notes.json" % str(Time.get_ticks_usec())
	canvas._toggle()
	check(canvas.active and paused, "Canvas pauses gameplay")
	check(canvas.camera != null and canvas.camera.current, "free camera is current")
	var target := Vector3(0, 0, 0)
	await physics_frame
	check(paused and scene.process_mode == Node.PROCESS_MODE_PAUSABLE, "always-processing pause controller suspended")
	canvas._place(canvas.camera.unproject_position(target))
	check(canvas.panel.store.notes.size() == 1, "raycast places marker")
	if canvas.panel.store.notes.is_empty():
		quit(1)
		return
	canvas.panel.title.text = "Old north gate"
	canvas.panel.instruction.text = "Add a ruined gatehouse and a path through this area."
	canvas.panel.radius.value = 6
	canvas.panel._save()
	check(canvas.panel.store.notes[0].name == "Old north gate", "panel save")
	check(canvas.panel.identifier.text == canvas.panel.store.notes[0].id, "panel shows permanent note ID")
	canvas.panel.search.text = canvas.panel.identifier.text
	canvas.panel._fill_list()
	check(canvas.panel.visible_notes.size() == 1, "search resolves exact note ID")
	canvas.panel.search.text = ""
	canvas.panel.status.select(Store.STATES.find("queued"))
	canvas.panel._save()
	check(canvas.panel.store.notes[0].status == "queued", "queue instruction")
	var original_id: String = canvas.panel.store.notes[0].id
	canvas.panel.selected = {}
	canvas.panel.tool.select(1)
	canvas.camera.global_transform = scene.get_node("Camera").global_transform
	var drawing_center: Vector2 = canvas.camera.unproject_position(Vector3(-4, 2, 0))
	for index in range(65):
		var angle := TAU * index / 64.0
		var cursor := drawing_center + Vector2(cos(angle) * 150, sin(angle) * 105)
		if index == 0:
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = cursor
			canvas._input(press)
		else:
			var motion := InputEventMouseMotion.new()
			motion.position = cursor
			canvas._input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	canvas._input(release)
	check(canvas.panel.store.notes.size() == 2, "mouse drawing creates a separate note")
	var drawn_id: String = canvas.panel.selected.id
	check(canvas.panel.selected.strokes.size() == 1, "freehand stroke saved")
	check(canvas.panel.selected.strokes[0].points.size() > 30, "stroke stores actual 3D samples")
	var gate_target := false
	for record in canvas.panel.selected.targets:
		if record.name == "Gatehouse": gate_target = true
	check(gate_target, "circle resolves enclosed object target")
	canvas.panel.title.text = "Gatehouse corner"
	canvas.panel.instruction.text = "This upper corner is too sharp. Bevel it and preserve the doorway."
	canvas.panel._save()
	canvas.panel.store.reload()
	check(canvas.panel.store.find(drawn_id).strokes.size() == 1, "drawing survives disk reload")
	canvas.panel.ink.color = Color("ff716b")
	canvas._begin_drawing(drawing_center + Vector2(-120, -135))
	for offset in [Vector2(-80, -105), Vector2(-40, -75), Vector2(0, -45), Vector2(-30, -48), Vector2(0, -45), Vector2(-8, -78)]:
		canvas._sample_drawing(drawing_center + offset)
	canvas._finish_drawing()
	check(canvas.panel.selected.strokes.size() == 2, "freehand arrow added to same note")
	canvas.panel.tool.select(2)
	var surface_start: Vector2 = canvas.camera.unproject_position(Vector3(-4.5, 3, 1.51))
	canvas._begin_drawing(surface_start)
	for index in range(8):
		canvas._sample_drawing(surface_start + Vector2(index * 6, index * 2))
	canvas._finish_drawing()
	check(canvas.panel.selected.strokes.size() == 3, "surface stroke appended to same note")
	canvas._undo_stroke()
	check(canvas.panel.selected.strokes.size() == 2, "undo removes last persisted stroke")
	canvas.panel.tool.select(1)
	await process_frame
	await process_frame
	if not DisplayServer.get_name() == "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test-output"))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-output/canvas.png")
	canvas._toggle()
	check(not canvas.active and not paused, "close restores pause state")
	check(scene.get_node("Camera").current, "close restores game camera")
	check(scene.process_mode == Node.PROCESS_MODE_ALWAYS, "close restores controller process mode")
	canvas._toggle()
	check(canvas.panel.store.notes.size() == 2, "pins and drawings persist across Canvas sessions")
	check(canvas.panel.store.find(original_id).name == "Old north gate", "drawing preserves unrelated pin")
	canvas._toggle()
	cleanup(canvas.panel.store.path)
	if not failed: print("CANVAS_TEST_OK")
	quit(1 if failed else 0)

func cleanup(filename: String) -> void:
	var directory := ProjectSettings.globalize_path(filename).get_base_dir()
	var note_directory := directory.path_join("notes")
	for file in DirAccess.get_files_at(note_directory):
		DirAccess.remove_absolute(note_directory.path_join(file))
	DirAccess.remove_absolute(note_directory)
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
