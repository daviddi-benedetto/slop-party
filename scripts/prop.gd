extends RigidBody3D
## A loose physics prop (chair, table, book, box, cone...) built from an
## imported model. Props never block characters: they are on collision layer
## 4 ("props") which players, zombies and the nav graph ignore. They only
## collide with the world and each other, and get knocked around by:
##   - anything walking or driving through them (player.gd / vehicle.gd call
##     Prop.kick_near() which finds props in a small sphere),
##   - bullets (bullet.gd ray-casts layer 4 and calls knock()),
##   - explosions (game.explode -> group "props").
## They start asleep exactly where the map put them, so stacks (books on a
## table) hold until disturbed. glass.gd shares the knock() interface.

const Models = preload("res://scripts/models.gd")

const LAYER := 4

var is_glass := false
var _path := ""
var _scl := 1.0


func setup(path: String, scl: float, weight: float) -> void:
	_path = path
	_scl = scl
	mass = weight


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1 | LAYER
	add_to_group("props")
	# The model is re-centred: node origin = middle of its footprint, on the floor.
	var b: AABB = Models.bounds(_path)
	var inst: Node3D = Models.scene(_path).instantiate()
	inst.scale = Vector3.ONE * _scl
	inst.position = -Vector3(b.get_center().x, b.position.y, b.get_center().z) * _scl
	add_child(inst)
	var shape := BoxShape3D.new()
	shape.size = (b.size * _scl).max(Vector3(0.06, 0.06, 0.06))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, b.size.y * _scl * 0.5, 0)
	add_child(cs)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = cs.position
	angular_damp = 1.5
	linear_damp = 0.3
	sleeping = true


## Push the prop: `impulse` in kg*m/s applied at world position `at`.
func knock(impulse: Vector3, at: Vector3) -> void:
	sleeping = false
	var limit := mass * 14.0
	if impulse.length() > limit:
		impulse = impulse.normalized() * limit
	apply_impulse(impulse, at - global_position)


## Shove every prop (and break every glass pane) within `radius` of `pos`,
## as something moving with `velocity` barges through.
static func kick_near(space: PhysicsDirectSpaceState3D, pos: Vector3, radius: float, velocity: Vector3, strength := 1.0) -> void:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = LAYER
	for hit in space.intersect_shape(q, 6):
		var c = hit.collider
		if c != null and c.has_method("knock"):
			var away: Vector3 = (c.global_position - pos)
			away.y = 0.0
			var dir := (velocity.normalized() + away.normalized() * 0.6 + Vector3(0, 0.25, 0)).normalized()
			c.knock(dir * velocity.length() * minf(c.mass if "mass" in c else 1.0, 12.0) * 0.5 * strength, pos)
