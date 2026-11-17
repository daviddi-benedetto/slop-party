extends RefCounted
## First-person plush arms (viewmodel.gd): the same animal you play as, seen
## from behind your own eyes. Fur and paw colours come from plush.gd SPEC
## (limb / paw), the wrist band is your player colour (the bandana), and the
## materials are the character's felt + fuzzy fur shell + dark outline,
## scaled down for the camera's close range.
##
## Local space of the returned node: the paw's centre at the origin, fingers
## towards -Z, the forearm running back along +Z (off the bottom of the
## screen). `side` is 1 for a right paw, -1 for a left one (thumb side).
## Poses:
##   "fist"  closed round a grip: knuckle nubs over the top, thumb on the side
##   "open"  a flat mitten with four stubby fingers and pink toe beans on the
##           palm (+Y), for spell casting

const Plush = preload("res://scripts/plush.gd")

static var _mats := {}
static var _sphere: SphereMesh
static var _fuzz_tex: ImageTexture
static var _felt_tex: NoiseTexture2D


static func build(kind: int, band: Color, layer: int, side := 1.0, pose := "fist", arm_len := 0.5) -> Node3D:
	var spec: Dictionary = Plush.SPEC[posmod(kind, Plush.SPEC.size())]
	var limb := plush(spec.limb, true)
	var paw := plush(spec.paw, true)
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if pose == "open":
		_ball(root, paw, Vector3(0, 0, 0), Vector3(0.056, 0.03, 0.062), layer)
		for f in 4:
			var fx := (f - 1.5) * 0.024
			var fz := -0.058 + absf(f - 1.5) * 0.006
			var fing := _ball(root, paw, Vector3(fx, 0.006, fz), Vector3(0.0145, 0.014, 0.024), layer)
			fing.rotation.y = -fx * 4.0
		_ball(root, paw, Vector3(-side * 0.05, 0.002, -0.006), Vector3(0.018, 0.016, 0.026), layer).rotation.y = side * 0.8
		# Toe beans on the palm.
		var bean := plush(_bean_color(spec.paw), false)
		_ball(root, bean, Vector3(0, 0.024, 0.01), Vector3(0.026, 0.008, 0.022), layer)
		for f in 4:
			var bx := (f - 1.5) * 0.022
			_ball(root, bean, Vector3(bx, 0.019, -0.054 + absf(f - 1.5) * 0.006), Vector3(0.008, 0.006, 0.009), layer)
	else:
		_ball(root, paw, Vector3(0, 0, 0), Vector3(0.05, 0.046, 0.056), layer)
		for f in 4:
			var kx := (f - 1.5) * 0.021
			_ball(root, paw, Vector3(kx, 0.024, -0.036 + absf(f - 1.5) * 0.005), Vector3(0.0165, 0.0165, 0.018), layer)
		_ball(root, paw, Vector3(-side * 0.043, 0.02, -0.012), Vector3(0.019, 0.018, 0.026), layer)
	# Wrist band in the player's colour, then the furry forearm.
	var cuff_mat := plush(band.lerp(Color.WHITE, 0.08), false)
	var cuff := TorusMesh.new()
	cuff.inner_radius = 0.034
	cuff.outer_radius = 0.054
	cuff.rings = 20
	cuff.ring_segments = 8
	var c := _mesh(root, cuff, cuff_mat, Vector3(0, -0.004, 0.066), layer)
	c.rotation.x = PI / 2
	var fore := CylinderMesh.new()
	fore.top_radius = 0.037
	fore.bottom_radius = 0.047
	fore.height = arm_len
	fore.radial_segments = 16
	fore.rings = 2
	var f2 := _mesh(root, fore, limb, Vector3(0, -0.004, 0.066 + arm_len * 0.5), layer)
	f2.rotation.x = -PI / 2
	_ball(root, limb, Vector3(0, -0.004, 0.06), Vector3(0.037, 0.037, 0.03), layer)
	return root


## The character's plush material, scaled for first person (cached).
static func plush(col: Color, furry: bool) -> StandardMaterial3D:
	var key := "%s_%s" % [col.to_html(), furry]
	if _mats.has(key):
		return _mats[key]
	# A touch darker and less rim than the full-size character: this close to
	# the camera, light fur would bloom into a white blur.
	col = Color(col.r * 0.86, col.g * 0.86, col.b * 0.86)
	var outline := StandardMaterial3D.new()
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = 0.0032
	outline.albedo_color = col.darkened(0.68)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.rim_enabled = true
	m.rim = 0.2
	m.rim_tint = 0.5
	m.normal_enabled = true
	m.normal_texture = _felt()
	m.normal_scale = 0.4
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 5.0
	if furry:
		var fur := StandardMaterial3D.new()
		fur.albedo_color = col.lerp(Color.WHITE, 0.06)
		fur.albedo_texture = _fuzz()
		fur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		fur.alpha_scissor_threshold = 0.5
		fur.roughness = 1.0
		fur.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		fur.grow = true
		fur.grow_amount = 0.0035
		fur.uv1_triplanar = true
		fur.uv1_scale = Vector3.ONE * 9.0
		fur.next_pass = outline
		m.next_pass = fur
	else:
		m.next_pass = outline
	_mats[key] = m
	return m


## Pink pads, or a deeper pink on paws that are pink already.
static func _bean_color(paw: Color) -> Color:
	var pink := Color(1.0, 0.6, 0.68)
	return pink.darkened(0.25) if paw.r > 0.9 and paw.g < 0.85 and paw.b > 0.7 else pink


static func _ball(parent: Node3D, mat: Material, pos: Vector3, radii: Vector3, layer: int) -> MeshInstance3D:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 20
		_sphere.rings = 10
	var mi := _mesh(parent, _sphere, mat, pos, layer)
	mi.scale = radii
	return mi


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, layer: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.layers = layer
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(mi)
	return mi


static func _fuzz() -> ImageTexture:
	if _fuzz_tex == null:
		var img := Image.create(96, 96, true, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for y in 96:
			for x in 96:
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if rng.randf() < 0.3 else 0.0))
		img.generate_mipmaps()
		_fuzz_tex = ImageTexture.create_from_image(img)
	return _fuzz_tex


static func _felt() -> NoiseTexture2D:
	if _felt_tex == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.09
		_felt_tex = NoiseTexture2D.new()
		_felt_tex.noise = n
		_felt_tex.width = 256
		_felt_tex.height = 256
		_felt_tex.seamless = true
		_felt_tex.as_normal_map = true
		_felt_tex.bump_strength = 5.0
		_felt_tex.generate_mipmaps = true
	return _felt_tex
