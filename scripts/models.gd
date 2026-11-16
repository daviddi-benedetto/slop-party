extends RefCounted
## Imported 3D models (assets/models, CC0 by Quaternius – see LICENSE.txt there).
##
## Static helpers shared by map.gd (static props, batched), viewmodel.gd (guns),
## zombie.gd (animated characters), vehicle.gd and pickup.gd:
##   scene(path)    the imported PackedScene (cached)
##   parts(path)    [[Mesh, Transform3D], ...] every mesh with its transform
##                  relative to the model root (cached; for static models)
##   bounds(path)   the model's AABB in its own space (cached)
## `path` is relative to res://assets/models/, e.g. "toon/Weapon/AK".

const ROOT := "res://assets/models/"

static var _scenes := {}
static var _parts := {}
static var _bounds := {}


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(ROOT + path + ".glb")
	return _scenes[path]


static func parts(path: String) -> Array:
	if not _parts.has(path):
		var n: Node = scene(path).instantiate()
		var out: Array = []
		_collect(n, Transform3D(), out)
		n.free()
		_parts[path] = out
	return _parts[path]


static func bounds(path: String) -> AABB:
	if not _bounds.has(path):
		var b := AABB()
		var first := true
		for p in parts(path):
			var a: AABB = p[1] * (p[0] as Mesh).get_aabb()
			b = a if first else b.merge(a)
			first = false
		_bounds[path] = b
	return _bounds[path]


static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var x := xf
	if n is Node3D:
		x = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([(n as MeshInstance3D).mesh, x])
	for c in n.get_children():
		_collect(c, x, out)


## Every MeshInstance3D below `n` (for overlays / layers on instanced models).
static func mesh_instances(n: Node, out: Array = []) -> Array:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		mesh_instances(c, out)
	return out
