extends Area3D
## A pickup pad placed by game.gd at the spots map.gd lists.
##
## kind "weapon": holds a random non-default weapon; walking over it swaps your
##                weapon (cards are kept). Re-rolls 16 s after being taken.
## kind "health": restores 50 health if you are hurt. Returns after 12 s.
##
## The floating item spins and bobs per rendered frame; the pad itself has no
## collision, only this Area3D (mask = players).

const Viewmodel = preload("res://scripts/viewmodel.gd")
const Weapons = preload("res://scripts/weapons.gd")
const Fx = preload("res://scripts/fx.gd")

var kind := "weapon"
var game
var weapon_id := 1
var _holder: Node3D
var _ring_mat: StandardMaterial3D
var _active := true
var _timer := 0.0
var _t := 0.0
var _tint := Color.WHITE


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	_tint = Color(0.74, 0.46, 1.0) if kind == "weapon" else Color(1.0, 0.4, 0.5)
	var shape := SphereShape3D.new()
	shape.radius = 1.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)

	var base := CylinderMesh.new()
	base.top_radius = 0.75
	base.bottom_radius = 0.9
	base.height = 0.1
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.24, 0.2, 0.36)
	_mesh(self, base, base_mat, Vector3(0, 0.05, 0))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.56
	ring.outer_radius = 0.7
	ring.rings = 28
	ring.ring_segments = 8
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = _tint
	_ring_mat.emission_enabled = true
	_ring_mat.emission = _tint
	_ring_mat.emission_energy_multiplier = 1.8
	_mesh(self, ring, _ring_mat, Vector3(0, 0.1, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_holder = Node3D.new()
	_holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_holder.position.y = 1.0
	add_child(_holder)
	_fill()


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(mi)
	return mi


## (Re)create the floating item.
func _fill() -> void:
	for c in _holder.get_children():
		c.queue_free()
	if kind == "weapon":
		weapon_id = 1 + randi() % (Weapons.LIST.size() - 1)
		var model = Viewmodel.new()
		_holder.add_child(model)
		model.build(Color(1.0, 0.8, 0.25), 1, weapon_id, false)
		model.position = Vector3(0, 0.05, 0.1)
		model.scale = Vector3.ONE * 2.2
	else:
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(1.0, 0.3, 0.42)
		red.roughness = 0.35
		red.rim_enabled = true
		red.emission_enabled = true
		red.emission = Color(1.0, 0.2, 0.3)
		red.emission_energy_multiplier = 0.35
		var ball := SphereMesh.new()
		ball.radius = 0.2
		ball.height = 0.4
		_mesh(_holder, ball, red, Vector3(-0.15, 0.1, 0))
		_mesh(_holder, ball, red, Vector3(0.15, 0.1, 0))
		var tip := CylinderMesh.new()
		tip.top_radius = 0.33
		tip.bottom_radius = 0.0
		tip.height = 0.42
		tip.radial_segments = 20
		_mesh(_holder, tip, red, Vector3(0, -0.14, 0)).scale = Vector3(1.0, 1.0, 0.6)
	_holder.visible = true
	_active = true
	_ring_mat.emission_energy_multiplier = 1.8


func _process(delta: float) -> void:
	_t += delta
	_holder.rotation.y = _t * 1.6
	_holder.position.y = 1.0 + sin(_t * 2.2) * 0.1


func _physics_process(delta: float) -> void:
	if not _active:
		_timer -= delta
		if _timer <= 0.0:
			_fill()
			Fx.ring(game.world, global_position + Vector3(0, 0.2, 0), Color(_tint, 0.9), 0.3, 1.4, 0.4)
		return
	for body in get_overlapping_bodies():
		if not body.has_method("pick_weapon") or not body.alive:
			continue
		if kind == "weapon":
			if body.weapon == weapon_id:
				continue
			body.pick_weapon(weapon_id)
			Sfx.play_at("card", global_position, -6.0)
			_take(16.0)
		else:
			if body.health >= body.stats.max_health - 1.0:
				continue
			body.heal(50.0)
			body.say("+50 HEALTH")
			Sfx.play_at("join", global_position, -4.0)
			_take(12.0)
		return


func _take(respawn: float) -> void:
	_active = false
	_timer = respawn
	_holder.visible = false
	_ring_mat.emission_energy_multiplier = 0.15
	Fx.burst(game.world, global_position + Vector3(0, 1.0, 0), _tint.lerp(Color.WHITE, 0.4), 14, 5.0, 0.22, 0.45, -3.0)
	Fx.ring(game.world, global_position + Vector3(0, 0.2, 0), Color(_tint, 0.9), 0.4, 1.8, 0.35)
