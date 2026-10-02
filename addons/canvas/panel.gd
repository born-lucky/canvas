@tool
extends VBoxContainer

signal add_requested
signal focus_requested(note: Dictionary)
signal changed
const Store = preload("res://addons/canvas/store.gd")
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
var delete_dialog: ConfirmationDialog

func _ready() -> void:
	custom_minimum_size = Vector2(280, 0)
	add_theme_constant_override("separation", 8)
	var heading := Label.new()
	heading.text = "Canvas"
	heading.add_theme_font_size_override("font_size", 22)
	add_child(heading)
	var row := HBoxContainer.new()
	add_child(row)
	add_button = _button(row, "+", "Place marker", func(): add_requested.emit())
	_button(row, "@", "Focus selected marker", func():
		if not selected.is_empty(): focus_requested.emit(selected))
	_button(row, "R", "Refresh notes", refresh)
	search = LineEdit.new()
	search.placeholder_text = "Search markers"
	search.text_changed.connect(func(_text): _fill_list())
	add_child(search)
	list = ItemList.new()
	list.custom_minimum_size.y = 130
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(_select_index)
	add_child(list)
	title = LineEdit.new()
	title.placeholder_text = "Marker name"
	add_child(title)
	instruction = TextEdit.new()
	instruction.placeholder_text = "Instruction"
	instruction.custom_minimum_size.y = 130
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
	_button(actions, "X", "Delete marker", func():
		if not selected.is_empty(): delete_dialog.popup_centered())
	result = TextEdit.new()
	result.editable = false
	result.placeholder_text = "Work report"
	result.custom_minimum_size.y = 80
	result.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(result)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.dialog_text = "Delete this marker and its instruction?"
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
		instruction.text = ""
		result.text = ""
	message.text = "%d markers" % visible_notes.size()

func _fill_list() -> void:
	list.clear()
	visible_notes = []
	for note in store.notes:
		if note.scene != scene_path or note.context != context: continue
		if not search.text.is_empty() and not search.text.to_lower() in (note.name + " " + note.instruction).to_lower(): continue
		visible_notes.append(note)
		list.add_item("%s  [%s]" % [note.name, note.status])
		list.set_item_tooltip(list.item_count - 1, note.instruction)

func _select_index(index: int) -> void:
	edit_note(visible_notes[index])

func edit_note(note: Dictionary) -> void:
	selected = note.duplicate(true)
	title.text = selected.name
	instruction.text = selected.instruction
	radius.value = float(selected.radius)
	status.select(Store.STATES.find(selected.status))
	result.text = str(selected.get("result", ""))
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
