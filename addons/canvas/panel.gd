@tool
extends VBoxContainer

signal add_requested
signal focus_requested(note: Dictionary)
signal changed
signal tool_changed
signal undo_stroke_requested
const Store = preload("res://addons/canvas/store.gd")
const Appearance = preload("res://addons/canvas/appearance.gd")
var store = Store.new()
var scene_path := ""
var context := ""
var selected: Dictionary = {}
var visible_notes: Array = []
var list: ItemList
var title: LineEdit
var instruction: TextEdit
var radius: SpinBox
var status: OptionButton
var result: TextEdit
var message: Label
var search: LineEdit
var add_button: Button
var identifier: LineEdit
var tool: OptionButton
var ink: ColorPickerButton
var depth: SpinBox
var target_label: Label
var delete_dialog: ConfirmationDialog
var report_toggle: Button

func _ready() -> void:
	theme = Appearance.create_theme()
	custom_minimum_size = Vector2(280, 0)
	add_theme_constant_override("separation", 6)
	var title_bar := PanelContainer.new()
	title_bar.add_theme_stylebox_override("panel", Appearance.box(Appearance.INK, Appearance.INK, 8))
	add_child(title_bar)
	var heading := Label.new()
	heading.text = "Canvas"
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Appearance.PAPER)
	title_bar.add_child(heading)
	var tool_row := HBoxContainer.new()
	add_child(tool_row)
	tool = OptionButton.new()
	for mode in ["Pin", "Draw", "Surface"]: tool.add_item(mode)
	tool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool.tooltip_text = "Pin, freehand in 3D, or draw on collision surfaces"
	tool.item_selected.connect(func(_index): tool_changed.emit())
	tool_row.add_child(tool)
	ink = ColorPickerButton.new()
	ink.color = Color("ffda67")
	ink.custom_minimum_size = Vector2(36, 32)
	ink.tooltip_text = "Ink color"
	tool_row.add_child(ink)
	_button(tool_row, "↶", "Undo last stroke on selected note", func(): undo_stroke_requested.emit())
	var depth_row := HBoxContainer.new()
	add_child(depth_row)
	var depth_label := Label.new()
	depth_label.text = "Depth (m)"
	depth_row.add_child(depth_label)
	depth = SpinBox.new()
	depth.min_value = 0.25
	depth.max_value = 5000
	depth.value = 10
	depth.step = 0.5
	depth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	depth.tooltip_text = "Drawing distance when the first point has no surface"
	depth_row.add_child(depth)
	var row := HBoxContainer.new()
	add_child(row)
	add_button = _button(row, "+", "Place marker", func(): add_requested.emit())
	_button(row, "⊙", "Focus selected note", func():
		if not selected.is_empty(): focus_requested.emit(selected))
	_button(row, "↻", "Refresh notes", refresh)
	search = LineEdit.new()
	search.placeholder_text = "Search notes"
	search.text_changed.connect(func(_text): _fill_list())
	add_child(search)
	list = ItemList.new()
	list.custom_minimum_size.y = 112
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(_select_index)
	add_child(list)
	title = LineEdit.new()
	title.placeholder_text = "Note name"
	add_child(title)
	var identity_row := HBoxContainer.new()
	add_child(identity_row)
	identifier = LineEdit.new()
	identifier.editable = false
	identifier.add_theme_font_size_override("font_size", 12)
	identifier.placeholder_text = "Note ID"
	identifier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identifier.tooltip_text = "Permanent note identifier"
	identity_row.add_child(identifier)
	_button(identity_row, "⧉", "Copy note ID", func():
		if not selected.is_empty(): DisplayServer.clipboard_set(str(selected.id)))
	target_label = Label.new()
	target_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	target_label.tooltip_text = "Primary object reference saved with this note"
	add_child(target_label)
	instruction = TextEdit.new()
	instruction.placeholder_text = "Instruction"
	instruction.custom_minimum_size.y = 112
	instruction.size_flags_vertical = Control.SIZE_EXPAND_FILL
	instruction.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(instruction)
	var settings := HBoxContainer.new()
	add_child(settings)
	var radius_label := Label.new()
	radius_label.text = "Radius (m)"
	settings.add_child(radius_label)
	radius = SpinBox.new()
	radius.min_value = 0
	radius.max_value = 10000
	radius.step = 0.5
	radius.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(radius)
	status = OptionButton.new()
	for state in Store.STATES: status.add_item(state.capitalize())
	status.set_item_disabled(Store.STATES.find("working"), true)
	add_child(status)
	var actions := HBoxContainer.new()
	add_child(actions)
	_button(actions, "Save", "Save marker", _save)
	_button(actions, "Queue", "Queue instruction for AI", func():
		status.select(Store.STATES.find("queued"))
		_save())
	_button(actions, "×", "Delete note", func():
		if not selected.is_empty(): delete_dialog.popup_centered())
	report_toggle = _button(self, "Work report", "Show or hide the AI work report", func():
		result.visible = not result.visible)
	report_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	result = TextEdit.new()
	result.editable = false
	result.placeholder_text = "Work report"
	result.custom_minimum_size.y = 60
	result.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(result)
	result.hide()
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.dialog_text = "Delete this note and its instruction?"
	delete_dialog.confirmed.connect(func():
		if store.delete_note(str(selected.id)):
			selected = {}
			refresh()
			changed.emit()
		else: message.text = store.error)
	add_child(delete_dialog)
	refresh()

func _button(parent: Node, text: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(36, 32)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func set_scope(path: String, key: String) -> void:
	scene_path = path
	context = key
	selected = {}
	if is_node_ready(): refresh()

func refresh() -> void:
	if not store.reload():
		message.text = store.error
		return
	_fill_list()
	if not selected.is_empty():
		var updated: Dictionary = store.find(str(selected.id))
		if not updated.is_empty(): edit_note(updated)
		else: selected = {}
	if selected.is_empty():
		title.text = ""
		identifier.text = ""
		target_label.text = ""
		instruction.text = ""
		result.text = ""
		result.hide()
		report_toggle.text = "Work report"
	message.text = "%d notes" % visible_notes.size()

func _fill_list() -> void:
	list.clear()
	visible_notes = []
	for note in store.notes:
		if note.scene != scene_path or note.context != context: continue
		if not search.text.is_empty() and not search.text.to_lower() in (note.id + " " + note.name + " " + note.instruction).to_lower(): continue
		visible_notes.append(note)
		list.add_item("%s  [%s]" % [note.name, note.status])
		list.set_item_tooltip(list.item_count - 1, note.id + "\n" + note.instruction)
		if not selected.is_empty() and note.id == selected.id:
			list.select(list.item_count - 1)

func _select_index(index: int) -> void:
	edit_note(visible_notes[index])

func edit_note(note: Dictionary) -> void:
	selected = note.duplicate(true)
	title.text = selected.name
	identifier.text = selected.id
	identifier.tooltip_text = store.note_path(str(selected.id))
	target_label.text = "Target: " + (selected.node_path if not selected.node_path.is_empty() else "World space")
	target_label.tooltip_text = selected.node_path
	instruction.text = selected.instruction
	radius.value = float(selected.radius)
	status.select(Store.STATES.find(selected.status))
	result.text = str(selected.get("result", ""))
	result.visible = not result.text.is_empty()
	report_toggle.text = "Work report" + (" •" if not result.text.is_empty() else "")
	message.text = "%s | %s" % [selected.node_path, str(selected.position)]

func _save() -> void:
	if selected.is_empty():
		message.text = "Select or place a marker."
		return
	selected.name = title.text.strip_edges()
	selected.instruction = instruction.text
	selected.radius = radius.value
	selected.status = Store.STATES[status.selected]
	if selected.status == "queued": selected.result = ""
	if store.save_note(selected):
		refresh()
		message.text = "Saved"
		changed.emit()
	else: message.text = store.error
