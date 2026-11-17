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
	_mat_soft.albedo_texture = tex
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
	while not _decals.is_empty() and not is_instance_valid(_decals[0]):
		_decals.pop_front()
	if _decals.size() >= MAX_DECALS:
		d = _decals.pop_front()
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
	_decals.append(d)
	d.texture_albedo = _decal_texture(kind)
	d.modulate = tint
	d.albedo_mix = 1.0
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	var depth := 0.5 if kind != "scorch" else size * 0.8
	d.size = Vector3(size, depth, size)
	# Decals project along their local -Y: point that into the surface.
	var up := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var b := Basis(side, up, side.cross(up)).rotated(up, randf() * TAU)
	d.global_transform = Transform3D(b, pos)
	d.visible = true
	# Fade out after a while (bullet holes sooner than scorch marks).
	var life := 14.0 if kind == "hole" else 22.0
	if d.has_meta("tween"):
		var old: Tween = d.get_meta("tween")
		if old != null and old.is_valid():
			old.kill()
	var tw := d.create_tween()
	tw.tween_interval(life)
	tw.tween_property(d, "modulate:a", 0.0, 3.0)
	tw.tween_callback(func(): d.visible = false)
	d.set_meta("tween", tw)


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


## A short flash of light that fades out (explosions, deaths).
static func light(parent: Node, pos: Vector3, color: Color, energy: float, radius: float, time: float) -> void:
	var l := OmniLight3D.new()
	l.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time).set_ease(Tween.EASE_OUT)
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
	l.outline_size = 18
	l.outline_modulate = UiKit.INK
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
