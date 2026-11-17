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
const Looks = preload("res://scripts/looks.gd")

static var _scenes := {}
static var _parts := {}
static var _bounds := {}
static var _toys := {}
## The visual theme in play (looks.gd entry), set by map.gd / stage.gd so
## toy() grades imported colours like the generated ones.
static var look := {}


## An imported model's material restyled to match the generated surfaces
## (map._mat): matte, wrapped soft lighting, a faint rim sheen, and its
## colour run through the theme's grade. Cached per material and theme, so
## batching by material still works.
static func toy(m: Material) -> Material:
	if not (m is BaseMaterial3D):
		return m
	var key := "%d|%s" % [m.get_instance_id(), look.get("key", "")]
	if _toys.has(key):
		return _toys[key]
	var t: BaseMaterial3D = m.duplicate()
	t.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	t.rim_enabled = true
	t.rim = 0.22
	t.rim_tint = 0.6
	if t.metallic < 0.5:
		t.roughness = maxf(t.roughness, 0.62)
	t.metallic *= 0.6
	t.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	t.albedo_color = Looks.grade(look, t.albedo_color)
	_toys[key] = t
	return t


## toy() on every surface of every MeshInstance3D under `n` (instanced
## models: props, doors, pets, vehicles, zombies, pickups).
static func toy_node(n: Node) -> void:
	for mi in mesh_instances(n):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var src: Material = mi.get_surface_override_material(si)
			if src == null:
				src = mesh.surface_get_material(si)
			if src != null:
				mi.set_surface_override_material(si, toy(src))


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
