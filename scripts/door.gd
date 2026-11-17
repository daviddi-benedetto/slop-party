extends AnimatableBody3D
## A hinged door that opens, closes and breaks.
##
## It sits in a doorway on its own collision layer (8): characters and
## vehicles are stopped by it, bullets hit it, but the bot nav graph ignores
## it (so paths run through doorways) and it opens by itself for bots and
## zombies. Humans open and close it with the interact button
## (player.gd -> game.door_near), and sliding or dashing into it barges it
## open. Shooting, melee and explosions damage it; at 0 hp it splinters
## (debris.gd) and is gone for the rest of the match.
##
## The node origin is the hinge at floor level; the leaf extends along local
## +X. map.gd places them with _door().

const Models = preload("res://scripts/models.gd")
const Debris = preload("res://scripts/debris.gd")
const Fx = preload("res://scripts/fx.gd")

const LAYER := 8

var is_glass := false
var mass := 18.0
var width := 1.7
var height := 2.45
var model := "doors/Door_Brown"
var hp := 110.0
var label := "DOOR"
var is_open := false
var _angle := 0.0
var _want := 0.0
var _auto_close := 0.0
var _scan := 0.0
var _wood := Color(0.45, 0.28, 0.16)


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	sync_to_physics = false
	add_to_group("props")
	add_to_group("doors")
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


func prompt() -> String:
	return ("CLOSE " if is_open else "OPEN ") + label


## World position of the middle of the doorway.
func centre() -> Vector3:
	return global_position + Basis(Vector3.UP, rotation.y - _angle).x * width * 0.5 + Vector3(0, 1.0, 0)


## Toggle; opens away from whoever is asking.
func interact(who) -> void:
	if is_open:
		_want = 0.0
		is_open = false
		Sfx.play_at("door", global_position, -4.0, randf_range(0.9, 1.1))
	else:
		swing_open(who.global_position if who != null else global_position + global_transform.basis.z)
	_auto_close = 0.0


func swing_open(from: Vector3) -> void:
	if is_open:
		return
	var closed := Basis(Vector3.UP, rotation.y - _angle)
	var side := closed.z.dot(from - global_position)
	# A positive angle swings the leaf towards the closed frame's -Z.
	_want = 1.75 if side > 0.0 else -1.75
	is_open = true
	Sfx.play_at("door", global_position, -6.0, randf_range(0.9, 1.1))


func _physics_process(delta: float) -> void:
	if not is_equal_approx(_angle, _want):
		var base := rotation.y - _angle
		_angle = move_toward(_angle, _want, delta * 5.5)
		rotation.y = base + _angle
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = 0.2
	# Bots, zombies and anyone barging in at speed open it; it swings shut
	# again a few seconds after the last one has gone through.
	var c := centre()
	var near := false
	for body in get_tree().get_nodes_in_group("door_users"):
		var d: Vector3 = body.global_position - c
		if absf(d.y) > 2.2 or d.x * d.x + d.z * d.z > 3.4:
			continue
		near = true
		var fast: bool = body.velocity.length() > 10.5
		if not is_open and (body.get("is_bot") != false or fast):
			swing_open(body.global_position)
			_auto_close = 3.0
	if is_open and _auto_close > 0.0 and not near:
		_auto_close -= 0.2
		if _auto_close <= 0.0:
			_want = 0.0
			is_open = false
			Sfx.play_at("door", global_position, -9.0, 0.8)


func knock(impulse: Vector3, at: Vector3) -> void:
	# A solid shove (explosion, vehicle) throws it open.
	if impulse.length() > 30.0 and not is_open:
		swing_open(at)


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
