extends CanvasLayer

const CanvasPanel = preload("res://addons/canvas/panel.gd")
const Markers = preload("res://addons/canvas/markers.gd")
const Strokes = preload("res://addons/canvas/strokes.gd")
var panel: VBoxContainer
var frame: PanelContainer
var markers: Node3D
var camera: Camera3D
var original_camera: Camera3D
var was_paused := false
var mouse_mode := Input.MOUSE_MODE_VISIBLE
var active := false
var placing := false
var scope := ""
var suspended_nodes: Array = []
var was_3d_disabled := false
var drawing := false
var stroke: Dictionary = {}
var stroke_note: Dictionary = {}
var drawing_plane: Plane
var last_cursor := Vector2.ZERO
var stroke_screen_points: Array[Vector2] = []
var preview: MeshInstance3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	# Canvas is a development tool; exported games omit it unless explicitly enabled.
	if OS.has_feature("release") and not ProjectSettings.get_setting("canvas/enable_in_release", false):
		queue_free()
		return
	frame = PanelContainer.new()
	var background := StyleBoxFlat.new()
	background.bg_color = Color("26282a")
	background.border_color = Color("55595b")
	background.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", background)
	frame.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	frame.offset_left = -360
	frame.offset_top = 16
	frame.offset_right = -16
	frame.offset_bottom = -16
	var padding := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + edge, 12)
	frame.add_child(padding)
	panel = CanvasPanel.new()
	padding.add_child(panel)
	add_child(frame)
	frame.hide()
	panel.add_requested.connect(func():
		if panel.tool.selected == 0:
			placing = true
			panel.message.text = "Choose a surface"
		else:
			panel.selected = {}
			panel.refresh())
	panel.tool_changed.connect(func():
		_cancel_drawing()
		placing = false
		Input.set_default_cursor_shape(Input.CURSOR_CROSS if panel.tool.selected > 0 and active else Input.CURSOR_ARROW))
	panel.undo_stroke_requested.connect(_undo_stroke)
	panel.changed.connect(_refresh_markers)
	panel.focus_requested.connect(func(note):
		if is_instance_valid(camera):
			var target: Vector3 = panel.store.position_of(note)
			camera.global_position = target + Vector3(0, 3, 5)
			camera.look_at(target + Vector3.UP * 0.5))
	markers = Markers.new()
	get_tree().root.add_child.call_deferred(markers)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8:
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if not active: return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and drawing:
		_cancel_drawing()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and drawing:
		_finish_drawing()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and drawing:
		if not frame.get_global_rect().has_point(event.position): _sample_drawing(event.position)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if not frame.get_global_rect().has_point(event.position): get_viewport().gui_release_focus()
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		if placing:
			placing = false
			panel.message.text = "Placement cancelled"
		else: _toggle()
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera.rotation.y -= event.relative.x * 0.003
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.003, -1.5, 1.5)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if frame.get_global_rect().has_point(event.position): return
		if panel.tool.selected > 0: _begin_drawing(event.position)
		elif placing: _place(event.position)
		else: _select_pin(event.position)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not active or not is_instance_valid(camera): return
	var current_scope := _context()
	if current_scope != scope:
		scope = current_scope
		panel.set_scope(get_tree().current_scene.scene_file_path, scope)
		_refresh_markers()
	if drawing: return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit: return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT): return
	var motion := Vector3(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	camera.position += camera.basis * motion.normalized() * delta * (50.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 12.0)

func _context() -> String:
	var scene := get_tree().current_scene
	if scene == null: return ""
	if scene.has_method("canvas_context"): return str(scene.call("canvas_context"))
	return str(scene.get_meta("canvas_context", ""))

func _toggle() -> void:
	if active:
		active = false
		_cancel_drawing()
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		frame.hide()
		markers.hide()
		placing = false
		if is_instance_valid(original_camera): original_camera.make_current()
		if is_instance_valid(camera): camera.queue_free()
		_restore_scene()
		get_tree().paused = was_paused
		get_viewport().disable_3d = was_3d_disabled
		Input.mouse_mode = mouse_mode
		return
	original_camera = get_viewport().get_camera_3d()
	if original_camera == null or get_tree().current_scene == null: return
	was_paused = get_tree().paused
	was_3d_disabled = get_viewport().disable_3d
	mouse_mode = Input.mouse_mode
	camera = Camera3D.new()
	get_tree().root.add_child(camera)
	camera.global_transform = original_camera.global_transform
	camera.fov = original_camera.fov
	camera.near = original_camera.near
	camera.far = maxf(original_camera.far, 4000)
	camera.cull_mask = original_camera.cull_mask
	camera.environment = original_camera.environment
	camera.make_current()
	_suspend_scene(get_tree().current_scene)
	get_tree().paused = true
	get_viewport().disable_3d = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	active = true
	scope = _context()
	panel.set_scope(get_tree().current_scene.scene_file_path, scope)
	frame.show()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if panel.tool.selected > 0 else Input.CURSOR_ARROW)
	markers.show()
	_refresh_markers()

func _suspend_scene(scene: Node) -> void:
	# Games may have ALWAYS controllers that recompute pause state every frame.
	# Explicit descendant modes override the root, so suspend them as well.
	suspended_nodes = []
	var nodes: Array[Node] = [scene]
	nodes.append_array(scene.find_children("*", "", true, false))
	for node in nodes:
		if node == scene or node.process_mode != Node.PROCESS_MODE_INHERIT:
			suspended_nodes.append({"node": weakref(node), "mode": node.process_mode})
			node.process_mode = Node.PROCESS_MODE_PAUSABLE

func _restore_scene() -> void:
	for saved in suspended_nodes:
		var node: Node = saved.node.get_ref()
		if is_instance_valid(node): node.process_mode = saved.mode
	suspended_nodes = []

func _refresh_markers() -> void:
	if not is_instance_valid(markers) or not is_instance_valid(get_tree().current_scene): return
	markers.rebuild(panel.store.notes, get_tree().current_scene.scene_file_path, scope)

func _place(point: Vector2) -> void:
	var origin := camera.project_ray_origin(point)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(point) * 5000)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		panel.message.text = "No surface under cursor"
		return
	var node: Node = hit.collider
	var scene := get_tree().current_scene
	var node_path := str(scene.get_path_to(node)) if scene.is_ancestor_of(node) else ""
	var note: Dictionary = panel.store.create(scene.scene_file_path, scope, hit.position, node_path)
	note.targets = [_target(node)]
	if panel.store.save_note(note):
		panel.refresh()
		panel.edit_note(note)
		placing = false
		_refresh_markers()
	else: panel.message.text = panel.store.error

func _hit(point: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(point)
	return camera.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(point) * 5000))

func _target(node: Node) -> Dictionary:
	var scene := get_tree().current_scene
	var mesh_path := ""
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node == null: mesh_node = node.find_child("*", true, false) as MeshInstance3D
	if mesh_node == null:
		for child in node.find_children("*", "MeshInstance3D", true, false):
			mesh_node = child
			break
	if mesh_node != null and mesh_node.mesh != null: mesh_path = mesh_node.mesh.resource_path
	var source := node
	while source != null and source.scene_file_path.is_empty(): source = source.get_parent()
	return {"node_path": str(scene.get_path_to(node)) if node == scene or scene.is_ancestor_of(node) else "",
		"name": str(node.name), "type": node.get_class(),
		"scene": source.scene_file_path if source != null else "", "mesh": mesh_path}

func _begin_drawing(point: Vector2) -> void:
	if not panel.selected.is_empty() and panel.selected.status == "working":
		panel.message.text = "Wait for the worker before editing this note"
		return
	var hit := _hit(point)
	if panel.tool.selected == 2 and hit.is_empty():
		panel.message.text = "Choose a collision surface"
		return
	var origin: Vector3 = hit.position if not hit.is_empty() else camera.project_ray_origin(point) + camera.project_ray_normal(point) * panel.depth.value
	drawing_plane = Plane(camera.global_basis.z.normalized(), origin)
	stroke_note = panel.selected.duplicate(true)
	if stroke_note.is_empty():
		stroke_note = panel.store.create(panel.scene_path, scope, origin)
		stroke_note.name = "Drawing note"
	else:
		stroke_note.name = panel.title.text.strip_edges()
		stroke_note.instruction = panel.instruction.text
	if not stroke_note.has("strokes"): stroke_note.strokes = []
	if not stroke_note.has("targets"): stroke_note.targets = []
	if stroke_note.strokes.size() >= 256:
		panel.message.text = "This note has reached its stroke limit"
		return
	if not hit.is_empty(): _add_target(hit.collider)
	stroke = {"points": [], "normal": Strokes.point(drawing_plane.normal), "color": panel.ink.color.to_html(),
		"width": clampf(camera.global_position.distance_to(origin) * 0.003, 0.01, 10),
		"projection": "surface" if panel.tool.selected == 2 else "plane"}
	stroke_screen_points = []
	last_cursor = point - Vector2(100, 100)
	drawing = true
	_sample_drawing(point)

func _add_target(node: Node) -> void:
	var target := _target(node)
	for existing in stroke_note.targets:
		if existing.node_path == target.node_path: return
	stroke_note.targets.append(target)
	if stroke_note.node_path.is_empty(): stroke_note.node_path = target.node_path

func _sample_drawing(point: Vector2) -> void:
	if point.distance_to(last_cursor) < 3 or stroke.points.size() >= 4096: return
	var position: Variant
	if stroke.projection == "surface":
		var hit := _hit(point)
		if hit.is_empty(): return
		position = hit.position + hit.normal * 0.02
		_add_target(hit.collider)
	else:
		position = drawing_plane.intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))
		if position == null: return
	stroke.points.append(Strokes.point(position))
	stroke_screen_points.append(point)
	last_cursor = point
	if stroke.points.size() < 2: return
	if not is_instance_valid(preview):
		preview = MeshInstance3D.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.no_depth_test = true
		material.albedo_color = panel.ink.color
		preview.material_override = material
		get_tree().root.add_child(preview)
	preview.mesh = Strokes.mesh_for(stroke)

func _finish_drawing() -> void:
	if stroke.points.size() >= 2:
		# A loop may start in empty space; its center identifies the enclosed model.
		var center := Vector2.ZERO
		for point in stroke_screen_points: center += point
		center /= stroke_screen_points.size()
		var hit := _hit(center)
		if not hit.is_empty():
			if panel.selected.is_empty() and stroke.projection == "plane":
				stroke_note.targets = []
				stroke_note.node_path = ""
			_add_target(hit.collider)
			if panel.selected.is_empty(): stroke_note.position = Strokes.point(hit.position)
		stroke_note.strokes.append(stroke.duplicate(true))
		if panel.store.save_note(stroke_note):
			panel.refresh()
			panel.edit_note(stroke_note)
			_refresh_markers()
		else: panel.message.text = panel.store.error
	_cancel_drawing()

func _cancel_drawing() -> void:
	drawing = false
	stroke = {}
	stroke_note = {}
	stroke_screen_points = []
	if is_instance_valid(preview): preview.queue_free()
	preview = null

func _undo_stroke() -> void:
	if drawing:
		_cancel_drawing()
		return
	if panel.selected.is_empty(): return
	var note: Dictionary = panel.selected.duplicate(true)
	if note.get("strokes", []).is_empty(): return
	note.strokes.pop_back()
	note.name = panel.title.text.strip_edges()
	note.instruction = panel.instruction.text
	if panel.store.save_note(note):
		panel.refresh()
		_refresh_markers()
	else: panel.message.text = panel.store.error

func _select_pin(point: Vector2) -> void:
	var best := 28.0
	var selected: Dictionary = {}
	for note in panel.store.notes:
		if note.scene != panel.scene_path or note.context != scope: continue
		var position: Vector3 = panel.store.position_of(note) + Vector3.UP * 0.6
		if camera.is_position_behind(position): continue
		var distance := point.distance_to(camera.unproject_position(position))
		if distance < best:
			best = distance
			selected = note
	if not selected.is_empty(): panel.edit_note(selected)

func _exit_tree() -> void:
	_cancel_drawing()
	if active:
		_restore_scene()
		get_tree().paused = was_paused
		get_viewport().disable_3d = was_3d_disabled
		Input.mouse_mode = mouse_mode
	if is_instance_valid(camera): camera.queue_free()
	if is_instance_valid(markers): markers.queue_free()
