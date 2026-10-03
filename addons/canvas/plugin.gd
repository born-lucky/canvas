@tool
extends EditorPlugin

const CanvasPanel = preload("res://addons/canvas/panel.gd")
var panel: VBoxContainer
var placing := false

func _enable_plugin() -> void:
	add_autoload_singleton("Canvas", "res://addons/canvas/runtime.gd")

func _disable_plugin() -> void:
	remove_autoload_singleton("Canvas")

func _enter_tree() -> void:
	panel = CanvasPanel.new()
	panel.name = "Canvas"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, panel)
	panel.tool.set_item_disabled(1, true)
	panel.tool.set_item_disabled(2, true)
	panel.tool.tooltip_text = "Freehand drawing is available in play mode (F8)"
	panel.add_requested.connect(func():
		var nodes := get_editor_interface().get_selection().get_selected_nodes()
		var root := get_editor_interface().get_edited_scene_root()
		if root == null or root.scene_file_path.is_empty():
			panel.message.text = "Save a 3D scene first"
			return
		if nodes.size() == 1 and nodes[0] is Node3D:
			_add(root, nodes[0].global_position, str(root.get_path_to(nodes[0])))
		else:
			placing = true
			panel.message.text = "Choose a surface in the 3D view")
	panel.focus_requested.connect(func(note):
		get_editor_interface().get_editor_viewport_3d(0).get_camera_3d().look_at_from_position(
			panel.store.position_of(note) + Vector3(0, 3, 5), panel.store.position_of(note)))
	panel.changed.connect(update_overlays)
	panel.annotation_visibility_changed.connect(update_overlays)
	scene_changed.connect(_scene_changed)
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	_scene_changed(get_editor_interface().get_edited_scene_root())

func _scene_changed(root: Node) -> void:
	placing = false
	if root != null:
		panel.set_scope(root.scene_file_path, str(root.get_meta("canvas_context", "")))
	else: panel.set_scope("", "")
	update_overlays()

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not placing: return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		placing = false
		return AFTER_GUI_INPUT_STOP
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return AFTER_GUI_INPUT_PASS
	var origin := viewport_camera.project_ray_origin(event.position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + viewport_camera.project_ray_normal(event.position) * 5000)
	var root := get_editor_interface().get_edited_scene_root()
	var hit := viewport_camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		panel.message.text = "No collision surface here. Select a 3D node to anchor a marker."
	else:
		_add(root, hit.position, str(root.get_path_to(hit.collider)))
		placing = false
	return AFTER_GUI_INPUT_STOP

func _add(root: Node, point: Vector3, node_path: String) -> void:
	var note: Dictionary = panel.store.create(root.scene_file_path, panel.context, point, node_path)
	if panel.store.save_note(note):
		panel.refresh()
		panel.edit_note(note)
		update_overlays()
	else: panel.message.text = panel.store.error

func _forward_3d_force_draw_over_viewport(control: Control) -> void:
	if not panel.annotations_toggle.button_pressed: return
	var camera: Camera3D = get_editor_interface().get_editor_viewport_3d(0).get_camera_3d()
	if camera == null: return
	for note in panel.store.notes:
		if note.scene != panel.scene_path or note.context != panel.context: continue
		if not note.get("visible", true): continue
		var point: Vector3 = panel.store.position_of(note)
		if camera.is_position_behind(point): continue
		var screen: Vector2 = camera.unproject_position(point)
		control.draw_circle(screen, 7, Color("40c7c2"))
		control.draw_string(control.get_theme_default_font(), screen + Vector2(12, 5), note.name)
		for stroke in note.get("strokes", []):
			for index in range(1, stroke.points.size()):
				var start: Vector3 = Vector3(stroke.points[index - 1][0], stroke.points[index - 1][1], stroke.points[index - 1][2])
				var end: Vector3 = Vector3(stroke.points[index][0], stroke.points[index][1], stroke.points[index][2])
				if not camera.is_position_behind(start) and not camera.is_position_behind(end):
					control.draw_line(camera.unproject_position(start), camera.unproject_position(end), Color(stroke.color), 3, true)

func _exit_tree() -> void:
	remove_control_from_docks(panel)
	panel.queue_free()
