extends RigidBody3D
## A loose physics prop (chair, table, book, box, cone...) built from an
## imported model. Props are solid rigid bodies on collision layer 4: they
## collide with the world, with each other and with characters (who cannot
## walk through them, only shove them). Their mass comes from their size
## (DENSITY x bounding-box volume), so the same shove sends a bottle flying
## and barely moves a fridge. The bot nav graph ignores them. They move by:
##   - anything walking or driving through them (player.gd / vehicle.gd call
##     Prop.kick_near() which finds props in a small sphere),
##   - bullets (bullet.gd ray-casts layer 4 and calls knock()),
##   - explosions (game.explode -> group "props").
## They start asleep exactly where the map put them, so stacks (books on a
## table) hold until disturbed. glass.gd shares the knock() interface.

const Models = preload("res://scripts/models.gd")

const LAYER := 4
const DENSITY := 70.0         # kg per cubic metre of bounding box (furniture is mostly air)
const MAX_SPEED_GAIN := 8.0   # no single shove adds more than this (m/s)
const Debris = preload("res://scripts/debris.gd")
const Fx = preload("res://scripts/fx.gd")
## Models that blow up when they break.
const EXPLOSIVE := ["toon/Prop/Exploding_Barrel", "toon/Prop/Gas_Can", "toon/Prop/Gas_Tank"]

var is_glass := false
var _path := ""
var _scl := 1.0
var hp := 40.0                # damage it takes before it breaks (hurt())
var _size := Vector3.ONE
var _tint := Color(0.55, 0.42, 0.3)
var _dead := false
var awake := false            # true: settle under physics at start (scattered clutter)


func setup(path: String, scl: float, weight: float) -> void:
	_path = path
	_scl = scl
	mass = weight             # replaced by the size-based mass in _ready



func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1 | 2 | LAYER
	add_to_group("props")
	# The model is re-centred: node origin = middle of its footprint, on the floor.
	var b: AABB = Models.bounds(_path)
	var inst: Node3D = Models.scene(_path).instantiate()
	inst.scale = Vector3.ONE * _scl
	inst.position = -Vector3(b.get_center().x, b.position.y, b.get_center().z) * _scl
	add_child(inst)
	# Small things are not drawn from far away (and never cast long shadows).
	var far := clampf(b.size.length() * _scl * 16.0, 22.0, 48.0)
	for mi in Models.mesh_instances(inst):
		mi.visibility_range_end = far
		mi.visibility_range_end_margin = 4.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if b.size.length() * _scl < 2.6:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_size = b.size * _scl
	mass = clampf(_size.x * _size.y * _size.z * DENSITY, 0.25, 400.0)
	hp = clampf(14.0 + mass * 2.2, 16.0, 220.0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	physics_material_override = pm
	for part in Models.parts(_path):
		var m0: Material = (part[0] as Mesh).surface_get_material(0)
		if m0 is StandardMaterial3D and (m0 as StandardMaterial3D).albedo_texture == null:
			_tint = (m0 as StandardMaterial3D).albedo_color
			break
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
	sleeping = not awake


## Push the prop: `impulse` in kg*m/s applied at world position `at`.
func knock(impulse: Vector3, at: Vector3) -> void:
	sleeping = false
	var limit := mass * MAX_SPEED_GAIN
	if impulse.length() > limit:
		impulse = impulse.normalized() * limit
	apply_impulse(impulse, at - global_position)


## Damage from bullets, melee and explosions. At 0 the prop breaks into
## splinters; fuel barrels and gas cans go off like a bomb a moment later.
func hurt(amount: float, who = null) -> void:
	if _dead:
		return
	hp -= amount
	if hp > 0.0:
		return
	_dead = true
	var world := get_parent()
	var centre := global_transform * Vector3(0, _size.y * 0.5, 0)
	var chunk := (_size * 0.3).clamp(Vector3.ONE * 0.06, Vector3.ONE * 0.35)
	Debris.burst(world, Transform3D(global_transform.basis.orthonormalized(), centre), _size * 0.8, chunk, _tint, clampi(int(_size.length() * 5.0), 3, 9), linear_velocity * 0.5, 3.0)
	Fx.puff(world, centre, Color(_tint.lightened(0.4), 0.6), 5, _size.length() * 0.4)
	Sfx.play_at("wood", global_position, -5.0, randf_range(0.9, 1.3))
	if _path in EXPLOSIVE:
		var game = get_tree().get_first_node_in_group("game")
		if game != null:
			game.explode_later(centre, 4.2, 75.0, who if who != null and is_instance_valid(who) else null)
	queue_free()


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
			var dir := (velocity.normalized() + away.normalized() * 0.6 + Vector3(0, 0.15, 0)).normalized()
			# A fixed shove (about 8 kg of moving body): a bottle skitters away,
			# a chair scrapes along, a fridge barely budges.
			c.knock(dir * minf(velocity.length(), 12.0) * 8.0 * strength, pos)
