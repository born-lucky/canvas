@tool
extends RefCounted

const DEFAULT_PATH := "res://.canvas/notes.json"
const STATES := ["draft", "queued", "working", "review", "done", "blocked"]
var path := DEFAULT_PATH
var error := ""
var notes: Array = []

func reload() -> bool:
	error = ""
	var loaded: Array = []
	if FileAccess.file_exists(path):
		var data: Variant = _read_json(path)
		if not error.is_empty(): return false
		if not data is Dictionary:
			error = "Unsupported Canvas notes format."
			return false
		if data.get("version") == 1 and data.get("notes") is Array:
			loaded = data.notes
		elif data.get("version") != 2 or data.get("storage") != "notes":
			error = "Unsupported Canvas notes format."
			return false
		else:
			loaded = _read_note_files()
	else:
		loaded = _read_note_files()
	if not error.is_empty(): return false
	var ids := {}
	for note in loaded:
		if not valid_note(note) or ids.has(note.id):
			error = "Invalid or duplicate Canvas marker."
			return false
		ids[note.id] = true
	notes = loaded
	return true

func note_path(id: String) -> String:
	return path.get_base_dir().path_join("notes").path_join(id + ".json")

func _read_json(filename: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(filename)) != OK:
		error = "Cannot read %s: %s" % [filename, parser.get_error_message()]
		return null
	return parser.data

func _read_note_files() -> Array:
	var loaded: Array = []
	var directory := path.get_base_dir().path_join("notes")
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)): return loaded
	var files := DirAccess.get_files_at(directory)
	files.sort()
	for filename in files:
		if not filename.ends_with(".json"): continue
		var note: Variant = _read_json(directory.path_join(filename))
		if not error.is_empty(): return []
		if not valid_note(note) or filename != str(note.id) + ".json":
			error = "Invalid Canvas note or filename: " + filename
			return []
		loaded.append(note)
	return loaded

static func valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 128: return false
	for character in id:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	if id.to_upper() in ["CON", "PRN", "AUX", "NUL"]: return false
	for number in range(1, 10):
		if id.to_upper() in ["COM%d" % number, "LPT%d" % number]: return false
	return true

static func valid_note(note: Variant) -> bool:
	if not note is Dictionary: return false
	for key in ["id", "name", "instruction", "scene", "context", "node_path", "status"]:
		if not note.get(key) is String: return false
	if not valid_id(note.id) or note.name.strip_edges().is_empty() or not note.status in STATES: return false
	if not note.get("position") is Array or note.position.size() != 3: return false
	for value in note.position:
		if not (value is float or value is int) or not is_finite(float(value)): return false
	return (note.get("radius") is float or note.get("radius") is int) and is_finite(float(note.radius)) and note.radius >= 0

func find(id: String) -> Dictionary:
	for note in notes:
		if note.id == id: return note
	return {}

func create(scene: String, context: String, position: Vector3, node_path := "") -> Dictionary:
	var id := "x" + Crypto.new().generate_random_bytes(16).hex_encode()
	while not find(id).is_empty() or FileAccess.file_exists(note_path(id)):
		id = "x" + Crypto.new().generate_random_bytes(16).hex_encode()
	return {"id": id, "name": "New marker",
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
	if not valid_id(str(note.id)):
		error = "Invalid note ID."
		return false
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
	if not _ensure_note_files(absolute): return false
	var filename := ProjectSettings.globalize_path(note_path(str(note.id)))
	if deleting:
		if FileAccess.file_exists(filename) and DirAccess.remove_absolute(filename) != OK:
			error = "Cannot delete Canvas note."
			return false
	if not deleting:
		note.updated_at = Time.get_datetime_string_from_system(true)
		if not _atomic_json(filename, note): return false
	return reload()

func _ensure_note_files(absolute: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir().path_join("notes")) != OK:
		error = "Cannot create Canvas note files directory."
		return false
	if FileAccess.file_exists(path):
		var data: Variant = _read_json(path)
		if not error.is_empty(): return false
		if data.get("version") == 2: return true
		# Commit the new format only after every legacy note has been copied.
		var backup := absolute + ".v1.bak"
		if not FileAccess.file_exists(backup) and DirAccess.copy_absolute(absolute, backup) != OK:
			error = "Cannot back up legacy Canvas notes."
			return false
	for existing in notes:
		var filename := ProjectSettings.globalize_path(note_path(str(existing.id)))
		if FileAccess.file_exists(filename):
			var previous: Variant = _read_json(filename)
			if not error.is_empty(): return false
			if previous != existing:
				error = "Migration conflicts with existing note file: " + filename
				return false
		else:
			if not _atomic_json(filename, existing): return false
	return _atomic_json(absolute, {"version": 2, "storage": "notes"})

func _atomic_json(absolute: String, data: Dictionary) -> bool:
	var file := FileAccess.open(absolute + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "Cannot write Canvas notes."
		return false
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(absolute + ".tmp", absolute) != OK:
		error = "Cannot replace Canvas notes. Previous notes are intact."
		return false
	return true

static func position_of(note: Dictionary) -> Vector3:
	return Vector3(note.position[0], note.position[1], note.position[2])
