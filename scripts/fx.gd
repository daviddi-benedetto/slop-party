extends RefCounted
## Throwaway visual effects. All static; every effect frees itself.
##
## Particles use CPUParticles3D (no shader warm-up hitch, works everywhere).
## Effects are animated per rendered frame, so they opt out of physics
## interpolation.

const UiKit = preload("res://scripts/ui_kit.gd")

static var _sphere: SphereMesh
static var _quad: QuadMesh
static var _torus: TorusMesh
static var _mat_soft: StandardMaterial3D
static var _mat_flat: StandardMaterial3D
static var _mat_add: StandardMaterial3D
static var _shrink: Curve
static var _confetti_ramp: Gradient
static var _decal_tex := {}          # kind -> ImageTexture (generated once)
static var _decals: Array = []       # pooled bullet holes / scorch marks, oldest first
static var _prints: Array = []       # pooled paw prints (their own pool: they never push out bullet holes)
static var _smoke_img_tex: ImageTexture
static var _fire_img_tex: ImageTexture
static var _star_tex: ImageTexture
static var _fire_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D
static var _ember_mat: StandardMaterial3D
static var _ramps := {}
static var _blasts: Array = []       # recent explosion times (msec): load shedding
static var _fires := 0               # ground fires burning right now
static var _quads := {}
static var _gpool := {}              # pooled one-shot particle nodes per effect
static var _pms := {}                # cached ParticleProcessMaterials (building one is costly)
static var _curves := {}
static var _casing_mesh: CylinderMesh
static var _casing_mat: StandardMaterial3D
const MAX_DECALS := 48


## A quick stylised blood spray for combat hits; uses pooled particle meshes.
static func blood_spray(parent: Node, pos: Vector3, direction := Vector3.UP, amount := 14, layers := 1) -> void:
	var p := burst(parent, pos, Color(0.62, 0.015, 0.035, 1.0), amount, 7.0, 0.18, 0.58, -12.0, direction, 82.0)
	p.layers = layers
	p.material_override = _mat_flat


## A dark red ground stain that fades after the fight has moved on.
static func blood_splat(parent: Node, pos: Vector3, size := 1.0) -> void:
	_init_shared()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.18, 0.006, 0.016, 0.86)
	mat.roughness = 0.96
	var mi := MeshInstance3D.new()
	var puddle := SphereMesh.new()
	puddle.radial_segments = 12
	puddle.rings = 6
	mi.mesh = puddle
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.035, 0)
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3(size, 0.018, size * randf_range(0.55, 1.15))
	var tw := mi.create_tween()
	tw.tween_interval(10.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 5.0)
	tw.tween_callback(mi.queue_free)


static func _init_shared() -> void:
	if _sphere != null:
		return
	_sphere = SphereMesh.new()
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 16
	_sphere.rings = 8
	_quad = QuadMesh.new()
	_torus = TorusMesh.new()
	_torus.inner_radius = 0.82
	_torus.outer_radius = 1.0
	_torus.rings = 32
	_torus.ring_segments = 6

	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.set_offset(0, 0.55)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_mat_soft = _particle_mat()
	_mat_soft.albedo_texture = smoke_texture()
	_mat_flat = _particle_mat()
	_mat_add = _particle_mat()
	_mat_add.albedo_texture = tex
	_mat_add.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	_shrink = Curve.new()
	_shrink.add_point(Vector2(0, 1))
	_shrink.add_point(Vector2(0.6, 0.8))
	_shrink.add_point(Vector2(1, 0))
	_confetti_ramp = Gradient.new()
	_confetti_ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	_confetti_ramp.colors = PackedColorArray(UiKit.PLAYER_COLORS)


static func _particle_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _free_later(node: Node, parent: Node, time: float) -> void:
	parent.get_tree().create_timer(time, false).timeout.connect(node.queue_free)


## One-shot burst of soft round particles.
static func burst(parent: Node, pos: Vector3, color: Color, amount: int, speed: float, size: float,
		life: float, gravity := -9.0, dir := Vector3.UP, spread := 180.0, flat := false, start := true) -> CPUParticles3D:
	_init_shared()
	var p := CPUParticles3D.new()
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.mesh = _quad
	p.material_override = _mat_flat if flat else _mat_soft
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 1.0
	p.damping_max = 2.5
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	p.scale_amount_curve = _shrink
	p.color = color
	parent.add_child(p)
	p.global_position = pos
	p.emitting = start
	_free_later(p, parent, life + 0.4)
	return p


## Bright additive sparks that shoot out along `dir` and bloom.
static func sparks(parent: Node, pos: Vector3, color: Color, amount: int, speed: float,
		dir := Vector3.UP, spread := 55.0, life := 0.4, layers := 1) -> void:
	var p := burst(parent, pos, Color(color.r * 2.2, color.g * 2.2, color.b * 2.2, 1.0), amount, speed, 0.2, life, -9.0, dir, spread, false, false)
	p.material_override = _mat_add
	p.layers = layers
	p.damping_min = 3.0
	p.damping_max = 6.0
	p.emitting = true


## A mark left on the world: "hole" (bullet hole), "scorch" (blast) or
## "slash". Decals only project onto the level (layer 1), never on players.
## Pooled: the oldest mark is reused once MAX_DECALS are out.
static func decal(parent: Node, pos: Vector3, normal: Vector3, kind: String, size: float, tint := Color(1, 1, 1, 1)) -> void:
	if not Settings.v("decals"):
		return
	var d: Decal = null
	var pool: Array = _prints if kind == "paw" else _decals
	var cap := 40 if kind == "paw" else MAX_DECALS
	while not pool.is_empty() and not is_instance_valid(pool[0]):
		pool.pop_front()
	if pool.size() >= cap:
		d = pool.pop_front()
		if d.get_parent() != parent:
			d.get_parent().remove_child(d)
			parent.add_child(d)
	else:
		d = Decal.new()
		d.cull_mask = 1
		d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		d.distance_fade_enabled = true
		d.distance_fade_begin = 30.0
		d.distance_fade_length = 8.0
		parent.add_child(d)
	pool.append(d)
	d.texture_albedo = _decal_texture(kind)
	d.modulate = tint
	d.albedo_mix = 1.0
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	var depth := (0.5 if kind != "scorch" else size * 0.8) if kind != "paw" else 0.3
	d.size = Vector3(size, depth, size)
	# Decals project along their local -Y: point that into the surface.
	var up := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var b := Basis(side, up, side.cross(up)).rotated(up, randf() * TAU if kind != "paw" else 0.0)
	if kind == "paw" and normal.length() > 0.01:
		b = Basis.looking_at(-normal, Vector3.UP) if absf(normal.y) < 0.9 else b
	d.global_transform = Transform3D(b, pos)
	d.visible = true
	# Fade out after a while (bullet holes sooner than scorch marks).
	var life := 14.0 if kind == "hole" else (7.0 if kind == "paw" else 22.0)
	if d.has_meta("tween"):
		var old: Tween = d.get_meta("tween")
		if old != null and old.is_valid():
			old.kill()
	var tw := d.create_tween()
	tw.tween_interval(life)
	tw.tween_property(d, "modulate:a", 0.0, 3.0)
	tw.tween_callback(func(): d.visible = false)
	d.set_meta("tween", tw)


## Wall art for map._wall_art: "tag0".."tag2" (spray-paint graffiti blobs
## in bright colours with a dark outline) and "poster0".."poster2" (paper
## with colour blocks and a title bar).
static func art_texture(kind: String) -> Texture2D:
	if _decal_tex.has(kind):
		return _decal_tex[kind]
	var w := 256
	var h := 128 if kind.begins_with("tag") else 192
	if kind.begins_with("poster"):
		w = 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	var cols := [Color(1.0, 0.3, 0.55), Color(0.2, 0.85, 1.0), Color(1.0, 0.8, 0.15), Color(0.5, 1.0, 0.3), Color(0.75, 0.4, 1.0)]
	if kind.begins_with("tag"):
		# Fat letter blobs along a wavy baseline, outlined, with drips.
		var c1: Color = cols[rng.randi() % cols.size()]
		var c2: Color = cols[rng.randi() % cols.size()]
		var blobs: Array = []
		var x := 30.0
		while x < w - 30:
			blobs.append([Vector2(x, 64 + sin(x * 0.05) * 14 + rng.randf_range(-6, 6)), rng.randf_range(16, 28)])
			x += rng.randf_range(18, 30)
		for pass_i in 2:
			for b in blobs:
				var c: Vector2 = b[0]
				var r: float = b[1] + (6.0 if pass_i == 0 else 0.0)
				for yy in range(int(c.y - r), int(c.y + r) + 1):
					for xx in range(int(c.x - r * 0.8), int(c.x + r * 0.8) + 1):
						if xx < 0 or yy < 0 or xx >= w or yy >= h:
							continue
						var q := Vector2((xx - c.x) / 0.8, yy - c.y)
						if q.length() <= r:
							var col: Color = Color(0.05, 0.03, 0.08, 1.0) if pass_i == 0 else c1.lerp(c2, float(yy - (c.y - r)) / (2.0 * r))
							img.set_pixel(xx, yy, col)
		for i in 6:
			var dx := rng.randi_range(40, w - 40)
			var y0 := 80
			var len := rng.randi_range(10, 40)
			for yy in range(y0, mini(h - 1, y0 + len)):
				img.set_pixel(dx, yy, Color(c1, 0.9))
				img.set_pixel(dx + 1, yy, Color(c1, 0.9))
	else:
		var paper := Color(0.95, 0.92, 0.85)
		img.fill_rect(Rect2i(4, 4, w - 8, h - 8), paper)
		var c: Color = cols[rng.randi() % cols.size()]
		img.fill_rect(Rect2i(10, 10, w - 20, 34), c)
		for i in 3:
			img.fill_rect(Rect2i(14, 54 + i * 10, rng.randi_range(40, w - 28), 5), Color(0.25, 0.22, 0.3))
		var c3: Color = cols[rng.randi() % cols.size()]
		for yy in range(96, h - 14):
			for xx in range(14, w - 14):
				if Vector2(xx - w * 0.5, yy - 135).length() < 30:
					img.set_pixel(xx, yy, c3)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_decal_tex[kind] = tex
	return tex


static func grime_texture() -> Texture2D:
	return _decal_texture("grime")


static func crack_texture() -> Texture2D:
	return _decal_texture("crack")


## Procedural decal textures (white, shaped by alpha; tinted by modulate).
static func _decal_texture(kind: String) -> Texture2D:
	if _decal_tex.has(kind):
		return _decal_tex[kind]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = kind.hash()
	noise.frequency = 0.06
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var nz := noise.get_noise_2d(x, y)
			var c := Color(1, 1, 1, 0)
			match kind:
				"hole":
					# A dark centre, a ring of chipped paint, cracks fading out.
					var core := 1.0 - smoothstep(0.12, 0.2, r)
					var chip := (1.0 - smoothstep(0.2, 0.55 + nz * 0.2, r)) * 0.55
					var g := 0.05 if core > 0.5 else 0.25 + 0.2 * nz
					c = Color(g, g, g * 1.05, clampf(maxf(core, chip), 0.0, 1.0))
				"scorch":
					var a := (1.0 - smoothstep(0.25 + nz * 0.25, 0.95, r))
					var g2 := 0.04 + 0.08 * r
					c = Color(g2, g2 * 0.95, g2 * 0.9, clampf(a * 0.92, 0.0, 1.0))
				"grime":
					var a2 := (1.0 - smoothstep(0.2, 1.0, r + nz * 0.35)) * (0.6 + 0.4 * noise.get_noise_2d(x * 3.0, y * 3.0))
					c = Color(1, 1, 1, clampf(a2, 0.0, 1.0))
				"crack":
					c = Color(1, 1, 1, 0)
				"paw":
					# A pad and four toes.
					var a := 0.0
					if Vector2(u * 1.1, (v - 0.25) * 1.25).length() < 0.42:
						a = 1.0
					for tx in [-0.48, -0.17, 0.17, 0.48]:
						if Vector2(u - tx, v + 0.42 - absf(tx) * 0.35).length() < 0.15:
							a = 1.0
					c = Color(1, 1, 1, a * (0.7 + 0.3 * nz))
			img.set_pixel(x, y, c)
	if kind == "crack":
		# A few branching dark lines from the centre.
		for b in 5:
			var p := Vector2(n * 0.5, n * 0.5)
			var ang := TAU * b / 5.0 + rng.randf_range(-0.4, 0.4)
			for step in 40:
				ang += rng.randf_range(-0.35, 0.35)
				p += Vector2(cos(ang), sin(ang)) * 1.4
				if p.x < 1 or p.y < 1 or p.x > n - 2 or p.y > n - 2:
					break
				var a3 := 1.0 - step / 40.0
				for o in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)]:
					img.set_pixelv(Vector2i(p + o), Color(1, 1, 1, a3))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_decal_tex[kind] = tex
	return tex


## Bullet impact debris for a surface class (map.surface_kind).
static func impact(parent: Node, pos: Vector3, n: Vector3, cls: String) -> void:
	match cls:
		"wood":
			burst(parent, pos, Color(0.55, 0.36, 0.2), 7, 4.0, 0.12, 0.6, -12.0, n, 45.0, true)
			burst(parent, pos, Color(0.7, 0.6, 0.45, 0.45), 3, 1.5, 0.25, 0.5, -1.0, n, 40.0)
		"metal":
			sparks(parent, pos, Color(1.0, 0.85, 0.5), 12, 9.0, n, 50.0, 0.3)
			if randf() < 0.35:
				Sfx.play_at("block", pos, -16.0, randf_range(1.4, 1.9))
		"snow":
			burst(parent, pos, Color(0.95, 0.97, 1.0, 0.85), 8, 2.5, 0.35, 0.7, -3.0, n, 60.0)
		"dirt":
			burst(parent, pos, Color(0.42, 0.32, 0.22, 0.75), 6, 2.6, 0.3, 0.6, -6.0, n, 50.0)
			burst(parent, pos, Color(0.3, 0.55, 0.22), 4, 3.0, 0.1, 0.6, -10.0, n, 50.0, true)
		_:
			burst(parent, pos, Color(0.6, 0.6, 0.62), 6, 4.5, 0.1, 0.55, -12.0, n, 45.0, true)
			burst(parent, pos, Color(0.78, 0.76, 0.72, 0.5), 4, 2.0, 0.28, 0.6, -1.5, n, 40.0)


## A paw print where a player stepped (dir = their facing, flat on the floor).
static func paw_print(parent: Node, pos: Vector3, yaw: float, tint: Color) -> void:
	decal(parent, pos, Vector3.UP, "paw", 0.26, tint)
	var d: Decal = _prints.back()
	d.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)


## A brass shell casing flicked out of the ejection port.
static func casing(parent: Node, pos: Vector3, right: Vector3, layers := 1) -> void:
	if _casing_mesh == null:
		_casing_mesh = CylinderMesh.new()
		_casing_mesh.top_radius = 0.012
		_casing_mesh.bottom_radius = 0.012
		_casing_mesh.height = 0.04
		_casing_mesh.radial_segments = 6
		_casing_mesh.rings = 1
		_casing_mat = StandardMaterial3D.new()
		_casing_mat.albedo_color = Color(0.95, 0.72, 0.3)
		_casing_mat.metallic = 0.9
		_casing_mat.roughness = 0.3
		_casing_mesh.material = _casing_mat
	var p := CPUParticles3D.new()
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.mesh = _casing_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = layers
	p.amount = 1
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = (right + Vector3(0, 1.1, 0)).normalized()
	p.spread = 18.0
	p.initial_velocity_min = 2.2
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0, -12.0, 0)
	p.angle_max = 360.0
	p.angular_velocity_min = -900.0
	p.angular_velocity_max = 900.0
	p.particle_flag_rotate_y = true
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_later(p, parent, 0.9)


## A dark smoke column that rises and spreads after a blast.
static func smoke(parent: Node, pos: Vector3, size := 1.0) -> void:
	var p := burst(parent, pos + Vector3(0, 0.3, 0), Color(0.16, 0.15, 0.17, 0.55), 10, 2.4 * size, 1.4 * size, 2.2, 1.6, Vector3.UP, 40.0, false, false)
	p.damping_min = 1.5
	p.damping_max = 2.5
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(0.4, 1.0))
	grow.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.emitting = true


# --------------------------------------------------------------------------
# Fire, smoke, embers (GPU particles: cheap on the CPU, soft and dramatic)
# --------------------------------------------------------------------------

## A cloudy puff: soft round alpha broken up by noise (smoke, dust, fire).
static func smoke_texture() -> ImageTexture:
	if _smoke_img_tex == null:
		_smoke_img_tex = _puff_texture(41, 1.0)
	return _smoke_img_tex


static func fire_texture() -> ImageTexture:
	if _fire_img_tex == null:
		_fire_img_tex = _puff_texture(77, 1.6)
	return _fire_img_tex


static func _puff_texture(seed_i: int, core: float) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = seed_i
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var nz := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - r) * 1.4 - (1.0 - nz) * 0.55, 0.0, 1.0)
			a = pow(a, core)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Four-point star for muzzle flashes.
static func star_texture() -> ImageTexture:
	if _star_tex == null:
		var n := 64
		var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var u := absf((x + 0.5) / n * 2.0 - 1.0)
				var v := absf((y + 0.5) / n * 2.0 - 1.0)
				var a := maxf(1.0 - (u * 6.0 + v * 1.1), 1.0 - (v * 6.0 + u * 1.1))
				a = maxf(a, 1.0 - sqrt(u * u + v * v) * 2.2)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
		img.generate_mipmaps()
		_star_tex = ImageTexture.create_from_image(img)
	return _star_tex


static func _gpu_mats() -> void:
	if _fire_mat != null:
		return
	_fire_mat = StandardMaterial3D.new()
	_fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fire_mat.vertex_color_use_as_albedo = true
	_fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_fire_mat.billboard_keep_scale = true
	_fire_mat.albedo_texture = fire_texture()
	_fire_mat.disable_receive_shadows = true
	_smoke_mat = StandardMaterial3D.new()
	# Unshaded: overlapping lit smoke quads in six views cost too much.
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_smoke_mat.billboard_keep_scale = true
	_smoke_mat.albedo_texture = smoke_texture()
	_smoke_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	_smoke_mat.roughness = 1.0
	_smoke_mat.disable_receive_shadows = true
	_ember_mat = StandardMaterial3D.new()
	_ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ember_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ember_mat.vertex_color_use_as_albedo = true
	_ember_mat.albedo_texture = smoke_texture()


static func _ramp(key: String, stops: Array) -> GradientTexture1D:
	if not _ramps.has(key):
		var g := Gradient.new()
		var offs := PackedFloat32Array()
		var cols := PackedColorArray()
		for s in stops:
			offs.append(s[0])
			cols.append(s[1])
		g.offsets = offs
		g.colors = cols
		var t := GradientTexture1D.new()
		t.gradient = g
		t.use_hdr = true
		_ramps[key] = t
	return _ramps[key]


static func _curve(key: String, pts: Array) -> CurveTexture:
	if not _curves.has(key):
		var c := Curve.new()
		c.max_value = 4.0
		for p in pts:
			c.add_point(p)
		var t := CurveTexture.new()
		t.curve = c
		_curves[key] = t
	return _curves[key]


static func _gpu(parent: Node, pos: Vector3, amount: int, life: float, pm: ParticleProcessMaterial, mat: Material, quad: Vector2, one_shot := true, explosive := 0.9) -> GPUParticles3D:
	_gpu_mats()
	# One-shot bursts are pooled: making a particle node every blast costs
	# more than the blast itself.
	var pk := "%d_%d_%d_%.2f_%.2f" % [pm.get_instance_id(), mat.get_instance_id(), amount, life, quad.x]
	if one_shot and _gpool.has(pk):
		var list: Array = _gpool[pk]
		for n in list:
			if is_instance_valid(n) and n.get_meta("free", false) and n.get_parent() == parent:
				n.set_meta("free", false)
				n.global_position = pos
				n.restart()
				parent.get_tree().create_timer(life + 0.6, false).timeout.connect(func():
					if is_instance_valid(n):
						n.set_meta("free", true))
				return n
	var p := GPUParticles3D.new()
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = explosive if one_shot else 0.0
	p.randomness = 0.4
	p.process_material = pm
	var qk := "%d_%.2f_%.2f" % [mat.get_instance_id(), quad.x, quad.y]
	if not _quads.has(qk):
		var q := QuadMesh.new()
		q.size = quad
		q.material = mat
		_quads[qk] = q
	p.draw_pass_1 = _quads[qk]
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 24, 24))
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	if one_shot:
		if not _gpool.has(pk):
			_gpool[pk] = []
		var list2: Array = _gpool[pk]
		list2 = list2.filter(func(n): return is_instance_valid(n))
		_gpool[pk] = list2
		if list2.size() < 6:
			list2.append(p)
			p.set_meta("free", false)
			parent.get_tree().create_timer(life + 0.6, false).timeout.connect(func():
				if is_instance_valid(p):
					p.set_meta("free", true))
		else:
			_free_later(p, parent, life + 0.6)
	return p


## How busy the effects are: explosions in the last second (game.explode
## scales down its effects when several overlap).
static func blast_load() -> int:
	var now := Time.get_ticks_msec()
	while not _blasts.is_empty() and now - int(_blasts[0]) > 1000:
		_blasts.pop_front()
	_blasts.append(now)
	return _blasts.size()


## A cached process material: `key` names the effect and its parameters.
static func _pm(key: String) -> ParticleProcessMaterial:
	return _pms.get(key)


static func _keep(key: String, pm: ParticleProcessMaterial) -> ParticleProcessMaterial:
	_pms[key] = pm
	return pm


static func can_add_fire() -> bool:
	return _fires < 4


## A rolling fireball: hot white core, yellow and orange flame licking out
## and up, cooling to dark red before it vanishes.
static func fireball(parent: Node, pos: Vector3, size := 1.0, amount := 26) -> void:
	_gpu_mats()
	var key := "fireball_%d" % roundi(size * 4.0)
	var pm := _pm(key)
	if pm == null:
		pm = ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.35 * size
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = 1.5 * size
		pm.initial_velocity_max = 6.0 * size
		pm.gravity = Vector3(0, 3.5, 0)
		pm.damping_min = 3.0
		pm.damping_max = 6.0
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -90.0
		pm.angular_velocity_max = 90.0
		pm.scale_min = 0.7
		pm.scale_max = 1.3
		pm.scale_curve = _curve("fire", [Vector2(0, 0.5), Vector2(0.25, 1.4), Vector2(1, 0.4)])
		pm.color_ramp = _ramp("fire", [[0.0, Color(2.0, 1.7, 1.1, 1.0)], [0.15, Color(1.7, 0.85, 0.22, 1.0)], [0.45, Color(1.1, 0.3, 0.05, 0.85)], [0.75, Color(0.3, 0.07, 0.03, 0.5)], [1.0, Color(0.04, 0.02, 0.02, 0.0)]])
		_keep(key, pm)
	_gpu(parent, pos, amount, 0.9, pm, _fire_mat, Vector2.ONE * 1.9 * size)


## A billowing column of smoke that rises, spreads and drifts for seconds.
## `tint`: dark grey for fire, pale for dust.
static func smoke_column(parent: Node, pos: Vector3, size := 1.0, tint := Color(0.16, 0.15, 0.16), amount := 16, life := 3.6) -> void:
	_gpu_mats()
	var key := "smoke_%d" % roundi(size * 4.0) + tint.to_html()
	var pm := _pm(key)
	if pm == null:
		pm = ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.5 * size
		pm.direction = Vector3.UP
		pm.spread = 35.0
		pm.initial_velocity_min = 1.0 * size
		pm.initial_velocity_max = 3.2 * size
		pm.gravity = Vector3(0.25, 0.6, 0.1)
		pm.damping_min = 0.6
		pm.damping_max = 1.4
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -25.0
		pm.angular_velocity_max = 25.0
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 1.2
		pm.turbulence_noise_scale = 3.0
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.15
		pm.scale_min = 0.8
		pm.scale_max = 1.3
		pm.scale_curve = _curve("smoke", [Vector2(0, 0.45), Vector2(0.3, 1.1), Vector2(1, 1.9)])
		pm.color_ramp = _ramp("smoke_%s" % tint.to_html(), [[0.0, Color(tint, 0.0)], [0.08, Color(tint, 0.65)], [0.55, Color(tint.lerp(Color(0.5, 0.5, 0.52), 0.2), 0.45)], [1.0, Color(tint.lerp(Color(0.6, 0.6, 0.62), 0.4), 0.0)]])
		_keep(key, pm)
	var p := _gpu(parent, pos, amount, life, pm, _smoke_mat, Vector2.ONE * 1.7 * size, true, 0.75)
	p.sorting_offset = -1.0


## Glowing embers flung out in streaks, falling and fading.
static func embers(parent: Node, pos: Vector3, size := 1.0, amount := 30, col := Color(1.0, 0.55, 0.15)) -> void:
	_gpu_mats()
	var key := "embers_%d" % roundi(size * 4.0) + col.to_html()
	var pm := _pm(key)
	if pm == null:
		pm = ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.3 * size
		pm.direction = Vector3.UP
		pm.spread = 75.0
		pm.initial_velocity_min = 5.0 * size
		pm.initial_velocity_max = 13.0 * size
		pm.gravity = Vector3(0, -9.0, 0)
		pm.damping_min = 0.5
		pm.damping_max = 1.5
		pm.particle_flag_align_y = true
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		pm.scale_curve = _curve("ember", [Vector2(0, 1.0), Vector2(1, 0.0)])
		pm.color_ramp = _ramp("ember_%s" % col.to_html(), [[0.0, Color(col.r * 4.0, col.g * 4.0, col.b * 4.0, 1.0)], [0.6, Color(col.r * 2.0, col.g * 1.2, col.b, 1.0)], [1.0, Color(col.r, col.g * 0.4, 0.0, 0.0)]])
		_keep(key, pm)
	_gpu(parent, pos, amount, 1.4, pm, _ember_mat, Vector2(0.05, 0.45) * clampf(size, 0.6, 1.5))


## A ring of dust blasted outwards along the ground.
static func dust_ring(parent: Node, pos: Vector3, size := 1.0, tint := Color(0.62, 0.58, 0.52)) -> void:
	_gpu_mats()
	var key := "dust_%d" % roundi(size * 4.0) + tint.to_html()
	var pm := _pm(key)
	if pm == null:
		pm = ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = 0.6 * size
		pm.emission_ring_inner_radius = 0.3 * size
		pm.emission_ring_height = 0.1
		pm.direction = Vector3(1, 0, 0)
		pm.spread = 180.0
		pm.flatness = 1.0
		pm.initial_velocity_min = 6.0 * size
		pm.initial_velocity_max = 10.0 * size
		pm.gravity = Vector3(0, 0.4, 0)
		pm.damping_min = 6.0
		pm.damping_max = 9.0
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.scale_curve = _curve("dust", [Vector2(0, 0.5), Vector2(1, 1.8)])
		pm.color_ramp = _ramp("dust_%s" % tint.to_html(), [[0.0, Color(tint, 0.0)], [0.1, Color(tint, 0.55)], [1.0, Color(tint, 0.0)]])
		_keep(key, pm)
	_gpu(parent, pos + Vector3(0, 0.25, 0), 18, 1.6, pm, _smoke_mat, Vector2.ONE * 1.2 * size, true, 1.0)


## A fire that keeps burning where it is for `time` seconds (0 = for ever):
## licking flames, a little smoke, flickering light.
static func fire_patch(parent: Node, pos: Vector3, radius := 0.6, time := 4.0, light := true) -> Node3D:
	_gpu_mats()
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(root)
	root.global_position = pos
	if time > 0.0:
		_fires += 1
		root.tree_exiting.connect(func(): _fires -= 1)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3.UP
	pm.spread = 8.0
	pm.initial_velocity_min = 1.6
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, 2.5, 0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -60.0
	pm.angular_velocity_max = 60.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 2.0
	pm.scale_curve = _curve("flame", [Vector2(0, 0.7), Vector2(0.3, 1.0), Vector2(1, 0.15)])
	pm.color_ramp = _ramp("flame", [[0.0, Color(1.6, 1.1, 0.4, 0.0)], [0.1, Color(1.7, 0.95, 0.25, 0.9)], [0.45, Color(1.3, 0.38, 0.06, 0.7)], [1.0, Color(0.25, 0.04, 0.02, 0.0)]])
	var f := _gpu(root, pos, int(clampf(radius * 60.0, 18.0, 50.0)), 0.7, pm, _fire_mat, Vector2(0.55, 0.85) * (0.8 + radius * 0.7), false)
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = radius * 0.6
	sm.direction = Vector3.UP
	sm.spread = 15.0
	sm.initial_velocity_min = 1.2
	sm.initial_velocity_max = 2.2
	sm.gravity = Vector3(0.3, 0.5, 0.1)
	sm.angle_min = -180.0
	sm.angle_max = 180.0
	sm.scale_curve = _curve("smoke", [Vector2(0, 0.45), Vector2(0.3, 1.2), Vector2(1, 2.4)])
	sm.color_ramp = _ramp("firesmoke", [[0.0, Color(0.12, 0.11, 0.11, 0.0)], [0.25, Color(0.15, 0.14, 0.14, 0.4)], [1.0, Color(0.4, 0.4, 0.42, 0.0)]])
	var s := _gpu(root, pos + Vector3(0, 1.0, 0), 8, 2.6, sm, _smoke_mat, Vector2.ONE * 1.3, false)
	var l: OmniLight3D = null
	if light:
		l = OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.2)
		l.light_energy = 2.2
		l.omni_range = 4.0 + radius * 3.0
		l.position = Vector3(0, 0.8, 0)
		root.add_child(l)
		var tw := l.create_tween().set_loops()
		tw.tween_property(l, "light_energy", 1.4, 0.09)
		tw.tween_property(l, "light_energy", 2.6, 0.13)
		tw.tween_property(l, "light_energy", 1.9, 0.07)
	if time > 0.0:
		parent.get_tree().create_timer(time, false).timeout.connect(func():
			if is_instance_valid(root):
				f.emitting = false
				s.emitting = false
				if l != null:
					l.create_tween().tween_property(l, "light_energy", 0.0, 0.6)
				_free_later(root, root.get_parent(), 3.0))
	return root


## Embers drifting up off a hot surface (lava), for ever.
static func ember_field(parent: Node, centre: Vector3, extents: Vector3) -> void:
	_gpu_mats()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 0.5, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 2.5
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.scale_curve = _curve("ember", [Vector2(0, 1.0), Vector2(1, 0.0)])
	pm.color_ramp = _ramp("lava_ember", [[0.0, Color(4.0, 1.6, 0.3, 0.0)], [0.15, Color(4.0, 1.5, 0.3, 1.0)], [1.0, Color(1.5, 0.2, 0.0, 0.0)]])
	var p := _gpu(parent, centre, clampi(int(extents.x * extents.z * 6.0), 12, 60), 2.5, pm, _ember_mat, Vector2.ONE * 0.09, false)
	p.visibility_aabb = AABB(-extents - Vector3(1, 1, 1), extents * 2.0 + Vector3(2, 6, 2))
	p.preprocess = 2.5


## A continuous trail behind a projectile (child of it; world-space
## particles). Smoke for rockets; with `fire`, a fiery core and embers too.
static func trail(owner: Node3D, fire: bool, radius: float) -> GPUParticles3D:
	_gpu_mats()
	var key := "trail_%s_%d" % [fire, roundi(radius * 40.0)]
	var pm := _pm(key)
	if pm == null:
		pm = ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = radius * 0.8
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = 0.1
		pm.initial_velocity_max = 0.6
		pm.gravity = Vector3(0, 0.8, 0)
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.scale_curve = _curve("trail", [Vector2(0, 0.4), Vector2(1, 1.8)])
		if fire:
			pm.color_ramp = _ramp("fireball_trail", [[0.0, Color(1.8, 1.0, 0.3, 0.9)], [0.25, Color(1.2, 0.35, 0.06, 0.7)], [0.6, Color(0.2, 0.17, 0.17, 0.5)], [1.0, Color(0.3, 0.3, 0.32, 0.0)]])
		else:
			pm.color_ramp = _ramp("rocket_trail", [[0.0, Color(0.95, 0.95, 1.0, 0.0)], [0.08, Color(0.9, 0.9, 0.95, 0.6)], [1.0, Color(0.6, 0.6, 0.65, 0.0)]])
		_keep(key, pm)
	var mat: Material = _fire_mat if fire else _smoke_mat
	var qsize := Vector2.ONE * radius * (9.0 if fire else 7.0)
	var qk := "%d_%.2f_%.2f" % [mat.get_instance_id(), qsize.x, qsize.y]
	if not _quads.has(qk):
		var q := QuadMesh.new()
		q.size = qsize
		q.material = mat
		_quads[qk] = q
	var p := GPUParticles3D.new()
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.amount = 28 if fire else 18
	p.lifetime = 0.8 if fire else 1.1
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = _quads[qk]
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	owner.add_child(p)
	p.emitting = true
	return p


## A short flash of light that fades out (explosions, deaths).
static func light(parent: Node, pos: Vector3, color: Color, energy: float, radius: float, time: float, flicker := false) -> void:
	var l := OmniLight3D.new()
	l.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	if flicker:
		tw.tween_property(l, "light_energy", energy * 0.6, time * 0.15)
		tw.tween_property(l, "light_energy", energy * 0.9, time * 0.1)
		tw.tween_property(l, "light_energy", energy * 0.45, time * 0.15)
	tw.tween_property(l, "light_energy", 0.0, time * (0.6 if flicker else 1.0)).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


## Party-popper burst of spinning coloured squares.
static func confetti(parent: Node, pos: Vector3, amount := 40, speed := 7.0, life := 1.6) -> void:
	var p := burst(parent, pos, Color.WHITE, amount, speed, 0.16, life, -7.0, Vector3.UP, 70.0, true, false)
	p.color_initial_ramp = _confetti_ramp
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -500.0
	p.angular_velocity_max = 500.0
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.emitting = true


## Continuous confetti rain (victory screen). Caller owns the returned node.
static func confetti_rain(parent: Node, pos: Vector3, extents: Vector3) -> CPUParticles3D:
	_init_shared()
	var p := CPUParticles3D.new()
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.mesh = _quad
	p.material_override = _mat_flat
	p.amount = 220
	p.lifetime = 5.0
	p.preprocess = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.DOWN
	p.spread = 25.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0, -1.6, 0)
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.2
	p.color_initial_ramp = _confetti_ramp
	p.angle_max = 360.0
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	parent.add_child(p)
	p.position = pos
	return p


## Soft dust / smoke puff.
static func puff(parent: Node, pos: Vector3, color := Color(1, 1, 1, 0.7), amount := 8, size := 0.5) -> void:
	burst(parent, pos, color, amount, 2.2, size, 0.55, 1.0, Vector3.UP, 180.0)


## An unshaded sphere that grows from r0 to r1 and fades out.
static func flash(parent: Node, pos: Vector3, color: Color, r0: float, r1: float, time: float, layers := 1) -> void:
	_init_shared()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere
	mi.material_override = mat
	mi.layers = layers
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * r0
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * r1, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(mi.queue_free)


## Flat ring that expands along the ground (spawn, landing, jump pad).
static func ring(parent: Node, pos: Vector3, color: Color, r0: float, r1: float, time: float) -> void:
	_init_shared()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = _torus
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(r0, 0.4, r0)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(r1, 0.4, r1), time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(mat, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(mi.queue_free)


## Floating damage number, visible only to cameras whose cull mask has `layer_bit`.
static func damage_number(parent: Node, pos: Vector3, amount: float, crit: bool, layer_bit: int) -> void:
	var l := Label3D.new()
	l.text = "%d" % maxi(1, roundi(amount))
	l.font = UiKit.font(700)
	l.font_size = 72 if crit else 52
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0.02, 0.55)
	l.modulate = UiKit.GOLD if crit else Color.WHITE
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.no_depth_test = true
	l.render_priority = 5
	l.layers = layer_bit
	l.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3))
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.1, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.25).set_delay(0.45)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.25).set_delay(0.45)
	tw.chain().tween_callback(l.queue_free)


## A jagged lightning bolt from a to b that fades in a blink.
static func bolt(parent: Node, a: Vector3, b: Vector3, color: Color, width := 0.04) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.lerp(Color(0.7, 0.9, 1.0), 0.6) * 2.0, 1.0)
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(root)
	var mesh := CylinderMesh.new()
	mesh.top_radius = width
	mesh.bottom_radius = width
	mesh.height = 1.0
	mesh.radial_segments = 5
	mesh.rings = 1
	var n := clampi(int(a.distance_to(b) / 2.5), 2, 7)
	var prev := a
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / n)
		if i < n:
			p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * minf(0.45, a.distance_to(b) * 0.06)
		var d := p - prev
		if d.length() > 0.01:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var y := d.normalized()
			var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
			mi.transform = Transform3D(Basis(x, y * d.length(), x.cross(y)), (prev + p) * 0.5)
			root.add_child(mi)
		prev = p
	var tw := root.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tw.tween_callback(root.queue_free)
