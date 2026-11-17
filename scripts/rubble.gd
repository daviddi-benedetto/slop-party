extends StaticBody3D
## A wall section that falls apart. It is ordinary world collision (layer 1,
## so the nav graph treats it as a wall) until enough damage brings it down:
## bullets and melee chip at it (bullet.gd / player.gd call hurt()),
## explosions hit it hard (game.explode -> knock()). Below 55 % it loses
## bricks; at zero the collider goes, a few dozen bricks tumble out as
## physics debris and a low heap is left behind.
##
## Drawn as one MultiMesh of bricks. map.gd places them with _weak_wall().

const Debris = preload("res://scripts/debris.gd")
const Fx = preload("res://scripts/fx.gd")

var is_glass := false
var mass := 60.0
var size := Vector3(4.0, 3.0, 0.4)
var color := Color(0.6, 0.56, 0.5)
var hp := 150.0
var _max_hp := 150.0
var _mm: MultiMesh
var _brick := Vector3(0.8, 0.4, 0.4)
var _gone := 0
var _shape: CollisionShape3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("props")
	_max_hp = hp
	var nx := maxi(2, int(round(size.x / 0.8)))
	var ny := maxi(2, int(round(size.y / 0.42)))
	_brick = Vector3(size.x / nx, size.y / ny, size.z)
	var bm := BoxMesh.new()
	bm.size = _brick * Vector3(0.96, 0.93, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	bm.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = bm
	_mm.instance_count = nx * ny
	var i := 0
	for y in ny:
		for x in nx:
			# Running bond: every other course is shifted a quarter brick.
			var off := (0.25 if y % 2 == 0 else -0.25) * _brick.x
			var p := Vector3((x + 0.5) * _brick.x - size.x * 0.5 + off * (0.0 if x == 0 or x == nx - 1 else 1.0), (y + 0.5) * _brick.y, 0)
			_mm.set_instance_transform(i, Transform3D(Basis(), p))
			_mm.set_instance_color(i, color.darkened(randf() * 0.22).lightened(randf() * 0.08))
			i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	add_child(mmi)
	var shape := BoxShape3D.new()
	shape.size = size
	_shape = CollisionShape3D.new()
	_shape.shape = shape
	_shape.position.y = size.y * 0.5
	add_child(_shape)


## Only explosions reach us here (group "props"): they do the real damage.
func knock(impulse: Vector3, _at: Vector3) -> void:
	hurt(impulse.length() * 0.55)


func hurt(amount: float, _who = null) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	var world := get_parent()
	var frac := clampf(hp / _max_hp, 0.0, 1.0)
	if hp <= 0.0:
		_collapse()
		return
	# Knock out bricks as it weakens.
	var want := int((1.0 - frac) * _mm.instance_count * 0.3) if frac < 0.55 else 0
	while _gone < want:
		var i := randi() % _mm.instance_count
		var xf := _mm.get_instance_transform(i)
		if xf.basis.get_scale().x > 0.5:
			_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), xf.origin))
			Debris.burst(world, global_transform * Transform3D(Basis(), xf.origin), Vector3.ZERO, _brick * 0.9, color.darkened(0.1), 1, global_transform.basis.z * randf_range(-2.0, 2.0))
		_gone += 1
	Fx.puff(world, global_position + Vector3(0, size.y * 0.5, 0), Color(0.75, 0.72, 0.68, 0.5), 3, 0.6)


func _collapse() -> void:
	var world := get_parent()
	collision_layer = 0
	_shape.set_deferred("disabled", true)
	var centre := global_transform * Vector3(0, size.y * 0.5, 0)
	Debris.burst(world, Transform3D(global_transform.basis, centre), size, _brick * 0.9, color.darkened(0.1), clampi(int(size.x * size.y * 2.2), 10, 30), Vector3.ZERO, 6.0)
	Fx.puff(world, centre, Color(0.75, 0.72, 0.68, 0.7), 16, maxf(size.x, size.y) * 0.5)
	Sfx.play_at("crumble", global_position, 2.0, randf_range(0.85, 1.1))
	# Leave a low heap: the bottom course, jumbled.
	var nx := maxi(2, int(round(size.x / _brick.x)))
	for i in _mm.instance_count:
		var xf := _mm.get_instance_transform(i)
		if i < nx:
			_mm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(randf_range(-0.4, 0.4), randf() * TAU, randf_range(-0.4, 0.4))), Vector3(xf.origin.x, _brick.y * 0.35, randf_range(-0.5, 0.5))))
		else:
			_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), xf.origin))
