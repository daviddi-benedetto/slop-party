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
static var _sways := {}
static var _sway_shader: Shader

## Foliage that moves in the wind: the toy() look on a shader that bends the
## mesh more the higher it is above the ground (trees, bushes, plants in
## map.gd). Transparent materials keep toy() unchanged.
const SWAY_CODE := """
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx, cull_disabled;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform bool use_vcol = false;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float rough = 0.8;
uniform float amp = 1.0;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(w.y - 0.4, 0.0, 7.0);
	float s = sin(TIME * 1.25 + w.x * 0.31 + w.z * 0.23) + 0.35 * sin(TIME * 3.1 + w.x * 1.7 + w.z * 1.3);
	vec3 off = vec3(s, 0.0, s * 0.55) * amp * h * h * 0.0035;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}
void fragment() {
	vec3 c = albedo.rgb;
	if (use_tex) {
		c *= texture(tex, UV * uv_scale.xy + uv_offset.xy).rgb;
	}
	if (use_vcol) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	RIM = 0.22;
	RIM_TINT = 0.6;
}
"""
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


## The swaying version of toy(m) (cached).
static func sway(m: Material) -> Material:
	var t := toy(m)
	if not (t is BaseMaterial3D) or (t as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return t
	var key := t.get_instance_id()
	if _sways.has(key):
		return _sways[key]
	if _sway_shader == null:
		_sway_shader = Shader.new()
		_sway_shader.code = SWAY_CODE
	var b: BaseMaterial3D = t
	var s := ShaderMaterial.new()
	s.shader = _sway_shader
	s.set_shader_parameter("albedo", b.albedo_color)
	if b.albedo_texture != null:
		s.set_shader_parameter("tex", b.albedo_texture)
		s.set_shader_parameter("use_tex", true)
	s.set_shader_parameter("use_vcol", b.vertex_color_use_as_albedo)
	s.set_shader_parameter("uv_scale", b.uv1_scale)
	s.set_shader_parameter("uv_offset", b.uv1_offset)
	s.set_shader_parameter("rough", b.roughness)
	_sways[key] = s
	return s


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
		# Most packs ship .glb; the building kits (kit_*) ship .gltf + .bin.
		_scenes[path] = load(ROOT + path + ".glb") if ResourceLoader.exists(ROOT + path + ".glb") else load(ROOT + path + ".gltf")
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
