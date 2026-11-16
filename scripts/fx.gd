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
