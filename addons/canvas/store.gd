@tool
extends RefCounted

const DEFAULT_PATH := "res://.canvas/notes.json"
const STATES := ["draft", "queued", "working", "review", "done", "blocked"]
var path := DEFAULT_PATH
var error := ""
var notes: Array = []

func reload() -> bool:
	error = ""
	if not FileAccess.file_exists(path):
		notes = []
		return true
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		error = "Cannot read Canvas notes: " + parser.get_error_message()
		return false
	var data: Variant = parser.data
	if not data is Dictionary or data.get("version") != 1 or not data.get("notes") is Array:
		error = "Unsupported Canvas notes format."
		return false
	var ids := {}
	for note in data.notes:
		if not valid_note(note) or ids.has(note.id):
			error = "Invalid or duplicate Canvas marker."
			return false
		ids[note.id] = true
	notes = data.notes
	return true

static func valid_note(note: Variant) -> bool:
	if not note is Dictionary: return false
	for key in ["id", "name", "instruction", "scene", "context", "node_path", "status"]:
		if not note.get(key) is String: return false
	if note.id.is_empty() or note.name.strip_edges().is_empty() or not note.status in STATES: return false
	if not note.get("position") is Array or note.position.size() != 3: return false
	for value in note.position:
		if not (value is float or value is int) or not is_finite(float(value)): return false
	return (note.get("radius") is float or note.get("radius") is int) and is_finite(float(note.radius)) and note.radius >= 0

func find(id: String) -> Dictionary:
	for note in notes:
		if note.id == id: return note
	return {}

func create(scene: String, context: String, position: Vector3, node_path := "") -> Dictionary:
	return {"id": Crypto.new().generate_random_bytes(16).hex_encode(), "name": "New marker",
		"instruction": "", "scene": scene, "context": context, "node_path": node_path,
		"position": [position.x, position.y, position.z], "radius": 0.0,
		"status": "draft", "created_at": Time.get_datetime_string_from_system(true),
		"updated_at": Time.get_datetime_string_from_system(true), "result": ""}

func save_note(note: Dictionary) -> bool:
	return _write_change(note, false)

func delete_note(id: String) -> bool:
	return _write_change({"id": id}, true)

func _write_change(note: Dictionary, deleting: bool) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		error = "Cannot create Canvas notes directory."
		return false
	# The CLI uses the same exclusive directory lock and atomic file replacement.
	var lock := absolute + ".lock"
	if DirAccess.make_dir_absolute(lock) != OK:
		error = "Canvas notes are busy. Retry saving."
		return false
	var success := _write_locked(note, deleting, absolute)
	DirAccess.remove_absolute(lock)
	return success

func _write_locked(note: Dictionary, deleting: bool, absolute: String) -> bool:
	if not reload(): return false
	var old := find(str(note.id))
	if not old.is_empty() and old.status == "working":
		error = "This marker is being worked on. Wait for its report."
		return false
	if not deleting:
		if not valid_note(note):
			error = "A marker needs a name and valid position."
			return false
		if note.status == "queued" and note.instruction.strip_edges().is_empty():
			error = "Write an instruction before queuing this marker."
			return false
	var next: Array = []
	for existing in notes:
		if existing.id != note.id: next.append(existing)
	if not deleting:
		note.updated_at = Time.get_datetime_string_from_system(true)
		next.append(note.duplicate(true))
	var file := FileAccess.open(absolute + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "Cannot write Canvas notes."
		return false
	file.store_string(JSON.stringify({"version": 1, "notes": next}, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(absolute + ".tmp", absolute) != OK:
		error = "Cannot replace Canvas notes. Previous notes are intact."
		return false
	notes = next
	return true

static func position_of(note: Dictionary) -> Vector3:
	return Vector3(note.position[0], note.position[1], note.position[2])
