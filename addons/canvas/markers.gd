@tool
extends Node3D

const Store = preload("res://addons/canvas/store.gd")
const Strokes = preload("res://addons/canvas/strokes.gd")
const COLORS := {"draft": Color("f2b84b"), "queued": Color("40c7c2"),
	"working": Color("f28155"), "review": Color("c98ced"), "done": Color("77ca8b"), "blocked": Color("ec6671")}

func rebuild(notes: Array, scene: String, context: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for note in notes:
		if note.scene != scene or note.context != context: continue
		if not note.get("visible", true): continue
		var anchor := Node3D.new()
		add_child(anchor)
		anchor.position = Store.position_of(note)
		var color: Color = COLORS.get(note.status, Color.WHITE)
		for stroke in note.get("strokes", []):
			var drawing := MeshInstance3D.new()
			drawing.mesh = Strokes.mesh_for(stroke)
			var ink := StandardMaterial3D.new()
			ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ink.albedo_color = Color(stroke.color)
			ink.cull_mode = BaseMaterial3D.CULL_DISABLED
			ink.no_depth_test = true
			drawing.material_override = ink
			add_child(drawing)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		var pin := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.18
		mesh.height = 0.36
		pin.mesh = mesh
		pin.material_override = material
		pin.position.y = 0.6
		anchor.add_child(pin)
		var label := Label3D.new()
		label.text = note.name
		label.font_size = 48
		label.pixel_size = 0.006
		label.modulate = color
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position.y = 1.2
		anchor.add_child(label)
		if note.radius > 0:
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = maxf(0.05, note.radius - 0.045)
			torus.outer_radius = note.radius + 0.045
			ring.mesh = torus
			ring.material_override = material
			ring.position.y = 0.08
			anchor.add_child(ring)
