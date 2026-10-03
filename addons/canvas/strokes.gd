@tool
extends RefCounted

static func point(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func valid_vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for coordinate in value:
		if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)): return false
	return true

static func valid(strokes: Variant) -> bool:
	if not strokes is Array or strokes.size() > 256: return false
	for stroke in strokes:
		if not stroke is Dictionary: return false
		if not stroke.get("points") is Array or stroke.points.size() < 2 or stroke.points.size() > 4096: return false
		for sample in stroke.points:
			if not valid_vector(sample): return false
		if not valid_vector(stroke.get("normal")) or vector(stroke.normal).length() < 0.01: return false
		if not stroke.get("color") is String or not Color.html_is_valid(stroke.color): return false
		if not stroke.color.trim_prefix("#").length() in [6, 8]: return false
		if not (stroke.get("width") is float or stroke.get("width") is int) or not is_finite(float(stroke.width)) or stroke.width <= 0 or stroke.width > 10: return false
		if not stroke.get("projection") in ["plane", "surface"]: return false
	return true

static func mesh_for(stroke: Dictionary) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var normal := vector(stroke.normal).normalized()
	var vertices: Array[Vector3] = []
	for index in range(1, stroke.points.size()):
		var start := vector(stroke.points[index - 1])
		var end := vector(stroke.points[index])
		var direction := end - start
		if direction.length_squared() < 0.000001: continue
		var side := direction.cross(normal)
		if side.length_squared() < 0.000001: side = direction.cross(Vector3.UP)
		if side.length_squared() < 0.000001: side = direction.cross(Vector3.RIGHT)
		side = side.normalized() * float(stroke.width) * 0.5
		vertices.append_array([start + side, start - side, end + side, end + side, start - side, end - side])
	if vertices.is_empty(): return mesh
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in vertices: mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	return mesh
