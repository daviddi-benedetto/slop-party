extends RefCounted
## Short-lived physics chunks for things that break: door planks, prop
## splinters, wall bricks. They collide with the world only (never with
## characters), tumble for a few seconds, shrink and free themselves.
## A global cap keeps a big explosion from flooding the physics engine.

const MAX_ALIVE := 140

const Voxel = preload("res://scripts/voxel.gd")
const Voxelizer = preload("res://scripts/voxelizer.gd")
const LAYER := 4096            # debris only (collision layer 13)

static var _alive := 0
static var _phys: PhysicsMaterial
static var _meshes := {}
static var _mats := {}


## `count` chunks of roughly `chunk` size, starting inside the box `area`
## centred on `xf`, thrown along `push` (world space).
static func burst(parent: Node, xf: Transform3D, area: Vector3, chunk: Vector3, color: Color, count: int, push := Vector3.ZERO, life := 4.0) -> void:
	if _alive > MAX_ALIVE:
		count = mini(count, 3)
	var vox: bool = Settings.v("voxel")
	if vox:
		# Whole voxels, so chunks match the world.
		chunk = (chunk / Voxel.SIZE).round().max(Vector3.ONE) * Voxel.SIZE
	var key := "%.2f,%.2f,%.2f" % [chunk.x, chunk.y, chunk.z]
	if not _meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = chunk
		var sh := BoxShape3D.new()
		sh.size = chunk
		_meshes[key] = [bm, sh]
	var ck := color.to_html()
	if not _mats.has(ck):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.85
		_mats[ck] = m
	if _phys == null:
		_phys = PhysicsMaterial.new()
		_phys.friction = 0.85
		_phys.bounce = 0.12
	var vol := chunk.x * chunk.y * chunk.z
	for i in count:
		var body := RigidBody3D.new()
		# Their own layer: chunks land on each other and pile up instead of
		# sinking into one another; still never in a character's way.
		body.collision_layer = LAYER
		body.collision_mask = 1 | 4 | LAYER
		body.mass = clampf(vol * 650.0, 0.3, 25.0)
		body.physics_material_override = _phys
		body.linear_damp = 0.05
		body.angular_damp = 0.8
		body.continuous_cd = vol < 0.002
		body.can_sleep = true
		var mi := MeshInstance3D.new()
		mi.mesh = _meshes[key][0]
		mi.material_override = _mats[ck]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if vol > 0.004 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
		if vox:
			Voxelizer.voxelize_node(mi, minf(Voxel.SIZE, chunk[chunk.min_axis_index()]) * 0.5)
		var cs := CollisionShape3D.new()
		cs.shape = _meshes[key][1]
		body.add_child(cs)
		parent.add_child(body)
		body.global_transform = xf * Transform3D(Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU),
			Vector3(randf_range(-0.5, 0.5) * area.x, randf_range(-0.5, 0.5) * area.y, randf_range(-0.5, 0.5) * area.z))
		body.reset_physics_interpolation()
		body.linear_velocity = push * randf_range(0.5, 1.0) + Vector3(randf_range(-1, 1), randf_range(0.4, 2.2), randf_range(-1, 1)) * 1.3
		# A gentle tumble (it used to spin like a top).
		body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 2.5
		_alive += 1
		var tw := body.create_tween()
		tw.tween_interval(life * 2.0 * randf_range(0.8, 1.1))
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.6)
		tw.tween_callback(_done.bind(body))


static func _done(body: Node) -> void:
	_alive -= 1
	body.queue_free()
