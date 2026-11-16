extends CharacterBody3D
## One zombie (Zombies mode). Spawned and counted by zombies.gd.
##
## Behaves like a target for everything that hurts players: it is on the
## player collision layer (bit 2) so bullets hit it, it is in game.actors so
## explosions, homing bullets and aim assist see it, and it has the same
## damage interface as player.gd (take_damage, apply_poison, apply_slow,
## chest_position, is_blocking, alive, team, pname, color, kind).
##
## Brain: every 0.3 s pick the nearest living player. With a clear line and
## within 14 m, walk straight at them; otherwise follow the map's nav graph.
## In reach, swing (damage on a cooldown). A blocking player shoves it back.
##
## Types (TYPES): walker, runner, brute and the boss that comes every fifth
## wave. zombies.gd scales health and speed with the wave number.

const Fx = preload("res://scripts/fx.gd")

const GRAVITY := 22.0
const TYPES := {
	"walker": {"name": "WALKER", "hp": 70.0, "speed": 2.8, "damage": 12.0, "scale": 1.0, "color": Color(0.42, 0.6, 0.36), "kind": 4, "points": 1},
	"runner": {"name": "RUNNER", "hp": 45.0, "speed": 5.4, "damage": 9.0, "scale": 0.9, "color": Color(0.75, 0.6, 0.42), "kind": 1, "points": 1},
	"brute": {"name": "BRUTE", "hp": 300.0, "speed": 2.1, "damage": 28.0, "scale": 1.45, "color": Color(0.5, 0.36, 0.62), "kind": 3, "points": 3},
	"boss": {"name": "ABOMINATION", "hp": 1600.0, "speed": 2.9, "damage": 40.0, "scale": 2.3, "color": Color(0.75, 0.2, 0.22), "kind": 3, "points": 10},
}

static var _meshes := {}         # type -> [body ArrayMesh, leg Mesh]

var game
var type := "walker"
var team := 9                    # never 0: always an enemy of the players
var pname := "WALKER"
var color := Color.WHITE
var kind := 4
var alive := true
var health := 70.0
var max_health := 70.0
var speed := 2.8
var damage := 12.0
var hurt_flash := 0.0
var has_view := false
var is_bot := true

var _scale := 1.0
var _target = null
var _think := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _attack_cd := 0.8
var _lunge := 0.0
var _stagger := 0.0
var _slow_left := 0.0
var _slow := 0.0
var _poison_left := 0.0
var _poison_dps := 0.0
var _poison_src = null
var _stuck := 0.0
var _walk := 0.0
var _groan := 0.0
var _body: Node3D
var _legs: Array = []
var _mat: StandardMaterial3D
var _bar: MeshInstance3D


func setup(kind_name: String, wave: int) -> void:
	type = kind_name
	var d: Dictionary = TYPES[type]
	pname = d.name
	color = d.color
	kind = d.kind
	_scale = d.scale
	var hp_mult := 1.0 + 0.13 * (wave - 1) + 0.004 * pow(wave - 1, 2.0)
	max_health = d.hp * hp_mult
	health = max_health
	speed = d.speed * minf(1.0 + 0.025 * (wave - 1), 1.55) * randf_range(0.9, 1.1)
	damage = d.damage * (1.0 + 0.04 * (wave - 1))


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.3
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38 * _scale
	capsule.height = 1.8 * _scale
	var cs := CollisionShape3D.new()
	cs.shape = capsule
	cs.position.y = 0.9 * _scale
	add_child(cs)
	_build_model()
	_groan = randf_range(1.0, 6.0)
	game.actors.append(self)


func _exit_tree() -> void:
	if game != null:
		game.actors.erase(self)


## Shared meshes per type; one material per zombie (hit flash).
func _build_model() -> void:
	if not _meshes.has(type):
		_meshes[type] = _make_meshes()
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = color
	_mat.roughness = 0.9
	_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	_mat.rim_enabled = true
	_mat.rim = 0.4
	_mat.emission_enabled = true
	_mat.emission = Color.BLACK
	_body = Node3D.new()
	_body.scale = Vector3.ONE * _scale
	add_child(_body)
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[type][0]
	mi.material_override = null
	mi.set_surface_override_material(0, _mat)
	_body.add_child(mi)
	for sx in [-0.17, 0.17]:
		var hip := Node3D.new()
		hip.position = Vector3(sx, 0.8, 0)
		_body.add_child(hip)
		var leg := MeshInstance3D.new()
		leg.mesh = _meshes[type][1]
		leg.material_override = _mat
		leg.position.y = -0.4
		hip.add_child(leg)
		_legs.append(hip)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.1)
	_bar = MeshInstance3D.new()
	_bar.mesh = quad
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.albedo_color = Color(1.0, 0.3, 0.25)
	bm.no_depth_test = false
	_bar.material_override = bm
	_bar.position.y = 2.15 * _scale
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.visible = false
	add_child(_bar)


## Torso, head, arms reaching forward and glowing eyes in one mesh
## (surface 0 = skin/clothes, surface 1 = eyes); legs separately (animated).
func _make_meshes() -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cap := CapsuleMesh.new()
	cap.radius = 0.27
	cap.height = 0.95
	cap.radial_segments = 12
	cap.rings = 4
	st.append_from(cap, 0, Transform3D(Basis(Vector3.RIGHT, 0.22), Vector3(0, 1.2, -0.05)))
	var head := SphereMesh.new()
	head.radius = 0.24
	head.height = 0.46
	head.radial_segments = 12
	head.rings = 6
	st.append_from(head, 0, Transform3D(Basis(Vector3.FORWARD, 0.25), Vector3(0.03, 1.78, -0.2)))
	var arm := CapsuleMesh.new()
	arm.radius = 0.08
	arm.height = 0.75
	arm.radial_segments = 8
	arm.rings = 2
	for sx in [-0.3, 0.3]:
		var b := Basis(Vector3.RIGHT, PI * 0.5 - 0.15).rotated(Vector3.UP, -sx * 0.25)
		st.append_from(arm, 0, Transform3D(b, Vector3(sx, 1.42, -0.42)))
	var jaw := BoxMesh.new()
	jaw.size = Vector3(0.22, 0.08, 0.14)
	st.append_from(jaw, 0, Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(0.03, 1.6, -0.36)))
	var body := st.commit()
	var est := SurfaceTool.new()
	est.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eye := SphereMesh.new()
	eye.radius = 0.045
	eye.height = 0.09
	eye.radial_segments = 8
	eye.rings = 4
	for sx in [-0.08, 0.1]:
		est.append_from(eye, 0, Transform3D(Basis(), Vector3(sx, 1.82, -0.41)))
	est.commit(body)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.6, 1.2, 0.2) if type != "boss" else Color(2.0, 0.3, 0.2)
	body.surface_set_material(1, glow)
	var leg := CapsuleMesh.new()
	leg.radius = 0.1
	leg.height = 0.85
	leg.radial_segments = 8
	leg.rings = 2
	return [body, leg]


func chest_position() -> Vector3:
	return global_position + Vector3(0, 1.1 * _scale, 0)


func head_height() -> float:
	return 1.5 * _scale


func hit_radius() -> float:
	return 0.5 * _scale


func is_blocking() -> bool:
	return false


func apply_poison(total: float, src) -> void:
	_poison_dps = (_poison_dps * maxf(_poison_left, 0.0) + total) / 3.0
	_poison_left = 3.0
	_poison_src = src


func apply_slow(amount: float) -> void:
	_slow = maxf(amount, _slow if _slow_left > 0.0 else 0.0)
	_slow_left = 2.0


## Same contract as player.take_damage: returns the damage dealt.
func take_damage(amount: float, attacker, silent := false, crit := false) -> float:
	if not alive:
		return 0.0
	if attacker == self or (attacker != null and is_instance_valid(attacker) and "team" in attacker and attacker.team == team):
		return 0.0
	health -= amount
	hurt_flash = 1.0
	_bar.visible = true
	if not silent:
		_stagger = maxf(_stagger, 0.12 if type != "boss" else 0.0)
	if game.is_player(attacker):
		if not silent:
			attacker.hit_marker = 1.0
			attacker.hit_crit = crit
			if attacker.has_view:
				Sfx.play("hit", -8.0, 1.3 if crit else 1.0)
				if Settings.v("numbers"):
					Fx.damage_number(game.world, global_position + Vector3(0, 2.0 * _scale, 0), amount, crit, attacker.viewmodel_layer_bit())
		if attacker.stats.lifesteal > 0.0:
			attacker.heal(amount * attacker.stats.lifesteal)
	if health <= 0.0:
		_die(attacker)
	return amount


func _die(attacker) -> void:
	alive = false
	collision_layer = 0
	game.actors.erase(self)
	var c := chest_position()
	Fx.sparks(game.world, c, color.lerp(Color(0.6, 1.0, 0.3), 0.4), 26 if type != "boss" else 80, 9.0, Vector3.UP, 180.0, 0.8)
	Fx.puff(game.world, c, Color(color.lerp(Color(0.3, 0.4, 0.2), 0.5), 0.8), 10 if type != "boss" else 30, 0.9 * _scale)
	Fx.flash(game.world, c, Color(0.8, 1.0, 0.5, 0.7), 0.3, 1.4 * _scale, 0.2)
	Sfx.play_at("pop", global_position, -4.0, 0.7 if type != "runner" else 1.0)
	if type == "boss":
		game.explode(c, 5.0, 0.0, null, null)
	game.on_actor_killed(self, attacker)
	if game.rules != null:
		game.rules.on_zombie_died(self, attacker)
	# Sink into the ground, then go.
	var tw := create_tween()
	tw.tween_property(_body, "rotation:x", -1.4, 0.35)
	tw.parallel().tween_property(_body, "position:y", -0.4, 0.6)
	tw.tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	hurt_flash = maxf(0.0, hurt_flash - delta * 5.0)
	_mat.emission = Color(1.0, 0.9, 0.8) * hurt_flash * 0.8
	if _bar.visible:
		_bar.scale.x = clampf(health / max_health, 0.02, 1.0)
	if game.frozen:
		return
	if _poison_left > 0.0:
		_poison_left -= delta
		take_damage(_poison_dps * delta, _poison_src, true)
		if not alive:
			return
	_slow_left = maxf(0.0, _slow_left - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_stagger = maxf(0.0, _stagger - delta)
	_lunge = maxf(0.0, _lunge - delta * 3.0)

	_think -= delta
	if _think <= 0.0:
		_think = 0.3
		_pick_target()

	var move := Vector3.ZERO
	if _target != null and is_instance_valid(_target) and _target.alive:
		var to: Vector3 = _target.global_position - global_position
		var flat := Vector3(to.x, 0, to.z)
		var direct: bool = flat.length() < 14.0 and absf(to.y) < 2.5 and _clear(_target)
		if direct:
			move = flat.normalized()
			_path = PackedVector3Array()
		else:
			_repath -= delta
			if _repath <= 0.0 or _path_i >= _path.size():
				_repath = 1.0 + randf() * 0.5
				_path = game.map.find_path(global_position, _target.global_position)
				_path_i = 0
			while _path_i < _path.size():
				var d: Vector3 = _path[_path_i] - global_position
				if Vector2(d.x, d.z).length() < 1.0:
					_path_i += 1
				else:
					move = Vector3(d.x, 0, d.z).normalized()
					break
			if move == Vector3.ZERO:
				move = flat.normalized()
		var reach := 1.35 * _scale + 0.4
		if flat.length() < reach and absf(to.y) < 1.8 * _scale and _attack_cd <= 0.0:
			_attack(_target)
		if flat.length() < reach * 0.7:
			move = Vector3.ZERO
		if flat.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), clampf(delta * 8.0, 0.0, 1.0))

	var spd := speed * (1.0 - (_slow if _slow_left > 0.0 else 0.0))
	if _stagger > 0.0:
		spd *= 0.2
	var horiz := Vector3(velocity.x, 0, velocity.z).move_toward(move * spd, 30.0 * delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()
	# Unstick: wanting to move but not getting anywhere -> hop, skip the
	# waypoint, and after a while repath with a sideways shuffle.
	var got := Vector2(velocity.x, velocity.z).length()
	if move != Vector3.ZERO and got < spd * 0.25 and _stagger <= 0.0:
		_stuck += delta
		if _stuck > 0.5 and is_on_floor():
			velocity.y = 7.5
			_path_i += 1
		if _stuck > 2.5:
			_stuck = 0.0
			_repath = 0.0
			velocity += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * spd
	else:
		_stuck = maxf(0.0, _stuck - delta)
	if global_position.y < -25.0:
		take_damage(99999.0, null, true)
		return

	# Shamble: legs swing, body sways, a lunge when attacking.
	var hs := Vector2(velocity.x, velocity.z).length()
	_walk += delta * (2.0 + hs * 2.2)
	var swing := sin(_walk) * clampf(hs / 3.0, 0.0, 1.0) * 0.6
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	_body.rotation.z = sin(_walk * 0.5) * 0.08
	_body.rotation.x = -_lunge * 0.5
	_body.position.y = absf(sin(_walk)) * 0.04
	_groan -= delta
	if _groan <= 0.0:
		_groan = randf_range(4.0, 10.0)
		Sfx.play_at("zombie", global_position, -10.0, (0.7 if type == "brute" or type == "boss" else 1.0) * randf_range(0.9, 1.1))


func _pick_target() -> void:
	var best = null
	var best_d := 1e9
	for p in game.hostiles(self):
		var d: float = p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	_target = best


func _clear(t) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), t.chest_position(), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _attack(t) -> void:
	_attack_cd = 1.1 if type != "runner" else 0.8
	_lunge = 1.0
	if t.is_blocking():
		# Shoved back by the guard.
		t.take_damage(damage, self)
		var away: Vector3 = (global_position - t.global_position)
		away.y = 0.0
		velocity = away.normalized() * 9.0 + Vector3(0, 4.0, 0)
		_stagger = 0.8
		return
	t.take_damage(damage, self)
	Sfx.play_at("hurt", t.global_position, -6.0, 0.6)
	if type == "brute" or type == "boss":
		var push: Vector3 = t.global_position - global_position
		push.y = 0.0
		t.velocity += push.normalized() * 8.0 + Vector3(0, 4.0, 0)
