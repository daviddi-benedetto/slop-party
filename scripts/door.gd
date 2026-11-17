extends AnimatableBody3D
## A hinged door that you simply push through.
##
## There is nothing to press: the leaf swings on its hinge away from anyone
## who walks into it (players, bots, zombies: everything in the group
## "door_users") and falls shut again behind them with a little overshoot,
## like a saloon door. It is a damped spring on the hinge angle, pushed
## harder the faster the body comes at it. Characters do not collide with
## the leaf (it would only stop them for the instant before it yields), so
## the door never needs opening; bullets do hit it (collision layer 8), and
## shots, melee and explosions kick it open and damage it until it
## splinters (debris.gd) and is gone for the rest of the match.
##
## The node origin is the hinge at floor level; the leaf extends along local
## +X. map.gd places them with _door().

const Models = preload("res://scripts/models.gd")
const Debris = preload("res://scripts/debris.gd")
const Fx = preload("res://scripts/fx.gd")

const LAYER := 8
const MAX_ANGLE := 1.75

var is_glass := false
var mass := 30.0
var width := 1.7
var height := 2.45
var model := "doors/Door_Brown"
var hp := 110.0
var label := "DOOR"
var _angle := 0.0            # hinge angle; positive swings the leaf towards the closed frame's -Z
var _speed := 0.0            # rad / s
var _side := 0.0             # which way the people in the doorway are pushing it (latched)
var _closed_yaw := 0.0
var _scan := 0.0
var _users: Array = []
var _creak := 0.0
var _wood := Color(0.45, 0.28, 0.16)


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	sync_to_physics = false
	add_to_group("props")
	add_to_group("doors")
	_closed_yaw = rotation.y
	var b: AABB = Models.bounds(model)
	# The models are thin along X or Z; turn the long side along the leaf.
	var thin_x := b.size.x < b.size.z
	var w: float = b.size.z if thin_x else b.size.x
	var rot := Basis(Vector3.UP, PI * 0.5) if thin_x else Basis()
	var scl := Vector3(width / w, height / b.size.y, width / w)
	var holder := Node3D.new()
	add_child(holder)
	for part in Models.parts(model):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = Transform3D(rot * Basis.from_scale(scl), Vector3(width * 0.5, 0, 0) - rot * (Vector3(b.get_center().x, b.position.y, b.get_center().z) * scl)) * part[1]
		mi.visibility_range_end = 70.0
		holder.add_child(mi)
		Models.toy_node(mi)
		var mesh: Mesh = part[0]
		var mat := mesh.surface_get_material(0)
		if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture == null:
			_wood = (mat as StandardMaterial3D).albedo_color
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.14)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(width * 0.5, height * 0.5, 0)
	add_child(cs)


## World position of the middle of the doorway.
func centre() -> Vector3:
	return global_position + Basis(Vector3.UP, _closed_yaw).x * width * 0.5 + Vector3(0, 1.0, 0)


func _physics_process(delta: float) -> void:
	# Who is near? (refreshed a few times a second; cheap)
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.15
		_users.clear()
		var c := centre()
		for body in get_tree().get_nodes_in_group("door_users"):
			var d: Vector3 = body.global_position - c
			if absf(d.y) < 2.4 and d.x * d.x + d.z * d.z < 9.0:
				_users.append(body)
	# How hard the doorway is being pushed, and which way.
	var closed := Basis(Vector3.UP, _closed_yaw)
	var push := 0.0
	for body in _users:
		if not is_instance_valid(body) or body.get("alive") == false:
			continue
		var rel: Vector3 = body.global_position - global_position
		var lx := closed.x.dot(rel)
		var lz := closed.z.dot(rel)
		if lx < -0.3 or lx > width + 0.3 or absf(lz) > 1.15:
			continue
		if _side == 0.0:
			# A body on the +Z side swings the leaf towards -Z (positive angle).
			_side = 1.0 if lz > 0.0 else -1.0
		var v: Vector3 = body.velocity
		var near := 1.0 - clampf((absf(lz) - 0.35) / 0.8, 0.0, 1.0)
		push = maxf(push, near * (0.55 + minf(v.length(), 12.0) * 0.06))
	if push <= 0.0:
		_side = 0.0
	var target := _side * MAX_ANGLE * clampf(push, 0.0, 1.0)
	# Hinge as a damped spring: stiff while someone leans on it, loose (so it
	# swings back and settles) when let go.
	var k := 70.0 if push > 0.0 else 16.0
	var c2 := 11.0 if push > 0.0 else 2.6
	_speed += (k * (target - _angle) - c2 * _speed) * delta
	_angle += _speed * delta
	if absf(_angle) > MAX_ANGLE:
		_angle = signf(_angle) * MAX_ANGLE
		_speed *= -0.25
	if push <= 0.0 and absf(_angle) < 0.004 and absf(_speed) < 0.02:
		_angle = 0.0
		_speed = 0.0
	rotation.y = _closed_yaw + _angle
	_creak = maxf(0.0, _creak - delta)
	if absf(_speed) > 2.2 and _creak <= 0.0:
		_creak = 0.7
		Sfx.play_at("door", global_position, -8.0, randf_range(0.85, 1.15))


## A shove from a bullet, a blow or a blast swings the leaf away from it.
func knock(impulse: Vector3, at: Vector3) -> void:
	var closed := Basis(Vector3.UP, _closed_yaw)
	var from_side := closed.z.dot(at - global_position)
	var along := -closed.z.dot(impulse)
	var kick: float = along if absf(along) > 0.5 else (impulse.length() * (1.0 if from_side > 0.0 else -1.0))
	_speed += clampf(kick / mass * 2.2, -9.0, 9.0)


func hurt(amount: float, _who = null) -> void:
	hp -= amount
	var mid := centre() + Vector3(0, height * 0.5 - 1.0, 0)
	if hp > 0.0:
		Fx.sparks(get_parent(), mid, _wood.lightened(0.3), 5, 3.0, Vector3.UP, 120.0, 0.3)
		return
	var xf := Transform3D(Basis(Vector3.UP, rotation.y), global_position + global_transform.basis.x * width * 0.5 + Vector3(0, height * 0.5, 0))
	Debris.burst(get_parent(), xf, Vector3(width, height, 0.1), Vector3(0.22, 0.6, 0.06), _wood, 9)
	Fx.puff(get_parent(), xf.origin, Color(0.7, 0.6, 0.5, 0.6), 8, 0.8)
	Sfx.play_at("wood", global_position, 0.0, randf_range(0.85, 1.05))
	queue_free()
