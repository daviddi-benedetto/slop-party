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

const CLIMB_SPEED := 3.6         # m/s up a wall
const Fx = preload("res://scripts/fx.gd")
const Gore = preload("res://scripts/gore.gd")
var _last_crit := false
var _wall_spot := Vector3.INF     # outside foot of the wall to climb towards a target on a roof
var _wall_in := Vector3.ZERO
var _scale_from := Vector3.ZERO    # scripted wall scramble: start, top, progress
var _scale_to := Vector3.ZERO
var _scale_t := -1.0
var _scale_dur := 1.0
var _best_d := 1e9               # closest we have got to the target (progress check)
var _no_gain := 0.0               # seconds without getting closer
var _force_climb := 0.0           # seconds left of climbing the outside regardless of the nav route
var _climb := 0.0                 # seconds left of wall climbing (scaling up to a target above)
var _last_dir := Vector3.UP
const Models = preload("res://scripts/models.gd")
const Prop = preload("res://scripts/prop.gd")
const Voxel = preload("res://scripts/voxel.gd")
const Voxelizer = preload("res://scripts/voxelizer.gd")
const VOX_CELL := 0.04           # voxel size on a zombie, metres

const GRAVITY := 22.0
const TYPES := {
	"walker": {"name": "WALKER", "hp": 70.0, "speed": 2.8, "damage": 12.0, "scale": 1.0, "color": Color(0.42, 0.6, 0.36), "kind": 4, "points": 1},
	"runner": {"name": "RUNNER", "hp": 45.0, "speed": 5.4, "damage": 9.0, "scale": 0.9, "color": Color(0.75, 0.6, 0.42), "kind": 1, "points": 1},
	"brute": {"name": "BRUTE", "hp": 300.0, "speed": 2.1, "damage": 28.0, "scale": 1.45, "color": Color(0.5, 0.36, 0.62), "kind": 3, "points": 3},
	"boss": {"name": "ABOMINATION", "hp": 1600.0, "speed": 2.9, "damage": 40.0, "scale": 2.3, "color": Color(0.75, 0.2, 0.22), "kind": 3, "points": 10},
}

## type -> [model path, model height in its own units, height factor]
const MODELS := {
	"walker": ["zombie/Character/Zombie_Basic", 1.36, 1.0],
	"runner": ["zombie/Character/Zombie_Ribcage", 1.06, 0.92],
	"brute": ["zombie/Character/Zombie_Chubby", 1.64, 1.0],
	"boss": ["zombie/Character/Zombie_Arm", 1.57, 1.0],
}

static var _flash_mat: StandardMaterial3D

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
var _anim: AnimationPlayer
var _meshes_inst: Array = []
var _flashing := false
var _action_t := 0.0             # > 0 while a one-shot animation (punch, hit) plays
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
	collision_mask = 1 | 2 | 4      # world, bodies, loose props (doors swing out of the way)
	add_to_group("door_users")
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


## The animated model for this type (Zombie Apocalypse kit, see models.gd),
## turned to face -Z and scaled to the type's height, plus the health bar.
## Animations used: Walk / Run (by speed), Punch (or Idle_Attack) on a swing,
## HitReact when hurt, Death. The hit flash is a white overlay material.
func _build_model() -> void:
	var spec: Array = MODELS[type]
	_body = Node3D.new()
	add_child(_body)
	var inst := model_for(type)
	_body.add_child(inst)
	Models.toy_node(inst, false)
	_meshes_inst = Models.mesh_instances(inst)
	if Voxel.on:
		# Voxel rig: rigid voxel pieces per bone (baked by --voxel-bake).
		_meshes_inst.append_array(voxelize_model(inst, type))
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_mat.albedo_color = Color(1.0, 0.9, 0.8, 0.55)
	for c in inst.find_children("*", "AnimationPlayer", true, false):
		_anim = c
	if _anim != null:
		for a in ["Walk", "Run", "Idle", "Crawl"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		_anim.playback_default_blend_time = 0.15
		_play("Idle")
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.1)
	_bar = MeshInstance3D.new()
	_bar.mesh = quad
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.albedo_color = Color(1.0, 0.3, 0.25)
	_bar.material_override = bm
	_bar.position.y = 2.15 * _scale
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.visible = false
	add_child(_bar)


## The type's model, scaled to its height and turned to face -Z.
static func model_for(type_name: String) -> Node3D:
	var spec: Array = MODELS[type_name]
	var inst: Node3D = Models.scene(spec[0]).instantiate()
	var k: float = 1.8 * float(TYPES[type_name].scale) * float(spec[2]) / float(spec[1])
	inst.scale = Vector3.ONE * k
	inst.rotation.y = PI
	return inst


## Voxelizes a model_for() instance that is in the tree.
static func voxelize_model(inst: Node3D, type_name: String) -> Array:
	return Voxelizer.voxelize_skinned(inst, MODELS[type_name][0], VOX_CELL)


func _play(anim: String, speed := 1.0) -> void:
	if _anim == null:
		return
	if not _anim.has_animation(anim):
		anim = "Walk" if _anim.has_animation("Walk") else "Idle"
	if _anim.current_animation != anim:
		_anim.play(anim)
	_anim.speed_scale = speed


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
		var spray := Vector3.UP
		if attacker != null and is_instance_valid(attacker):
			spray = (global_position - attacker.global_position + Vector3(0, 0.4, 0)).normalized()
		Gore.hit(game.world, chest_position(), spray, amount * (0.6 if type == "boss" else 1.0))
		_last_crit = crit
		_last_dir = spray
	if not silent:
		_stagger = maxf(_stagger, 0.12 if type != "boss" else 0.0)
		if amount > max_health * 0.12 and _action_t <= 0.0 and health > amount:
			_play("HitReact", 1.5)
			_action_t = 0.35
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
	var how := "normal"
	if has_meta("blast_t") and game.time - float(get_meta("blast_t")) < 0.15:
		how = "blast"
	elif game.melee_strike:
		how = "slice"
	elif _last_crit:
		how = "head"
	Gore.death(game.world, global_position, _last_dir, {"fur": color, "limb": color, "paw": color.darkened(0.2)}, how, _scale)
	if type == "boss":
		Gore.death(game.world, global_position + Vector3(0, 0.8 * _scale, 0), Vector3.UP, {"fur": color, "limb": color, "paw": color.darkened(0.2)}, "blast", _scale)
	Sfx.play_at("pop", global_position, -4.0, 0.7 if type != "runner" else 1.0)
	if type == "boss":
		game.explode(c, 5.0, 0.0, null, null)
	game.on_actor_killed(self, attacker)
	if game.rules != null:
		game.rules.on_zombie_died(self, attacker)
	# Fall over (Death animation), sink into the ground, then go.
	_set_flash(false)
	_bar.visible = false
	_play("Death")
	if how == "blast":
		_body.visible = false      # blown to bits: only the gibs remain
	var tw := create_tween()
	tw.tween_interval(1.3)
	tw.tween_property(_body, "position:y", -1.6 * _scale, 0.7)
	tw.tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	hurt_flash = maxf(0.0, hurt_flash - delta * 5.0)
	_set_flash(hurt_flash > 0.45)
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

	if _scale_t >= 0.0:
		_update_scale(delta)
		return

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
				# On a roof no path reaches: walk round to the outside wall
				# nearest us instead, and climb it from there.
				var reach_ok: bool = not _path.is_empty() and absf(_path[_path.size() - 1].y - _target.global_position.y) < 1.5 and _force_climb <= 0.0
				if to.y > 1.5 and not reach_ok:
					if _wall_spot == Vector3.INF:
						_wall_spot = _climb_spot(_target.global_position)
					if _wall_spot != Vector3.INF:
						_path = game.map.find_path(global_position, _wall_spot)
						_path_i = 0
				else:
					_wall_spot = Vector3.INF
			if _wall_spot != Vector3.INF and Vector2(global_position.x - _wall_spot.x, global_position.z - _wall_spot.z).length() < 1.6:
				# At the foot of the wall: scramble up it onto the roof.
				_path = PackedVector3Array()
				move = _wall_in
				_start_scale()
			while _path_i < _path.size():
				var d: Vector3 = _path[_path_i] - global_position
				if Vector2(d.x, d.z).length() < 1.0:
					_path_i += 1
				else:
					move = Vector3(d.x, 0, d.z).normalized()
					break
			# An empty route usually means a wall or a disconnected floor. Don't
			# steer directly through it; keep position and request a fresh route.
			if move == Vector3.ZERO and _clear(_target):
				move = flat.normalized()
			# Nothing else to go on (a ledge the nav graph cannot reach): head
			# straight for them and climb whatever is in the way.
			if move == Vector3.ZERO:
				move = flat.normalized()
		# Progress check: a route that never gets us closer (stuck on stairs or
		# in a stairwell) gives way to climbing the outside for a while.
		var dist: float = to.length()
		if dist < _best_d - 0.5:
			_best_d = dist
			_no_gain = 0.0
		else:
			_no_gain += delta
		_force_climb = maxf(0.0, _force_climb - delta)
		if _no_gain > 5.0 and to.y > 1.5:
			_no_gain = 0.0
			_best_d = dist
			_force_climb = 12.0
			_repath = 0.0
		var reach := 1.35 * _scale + 0.4
		if flat.length() < reach and absf(to.y) < 1.8 * _scale and _attack_cd <= 0.0:
			_attack(_target)
		if flat.length() < reach * 0.7 and absf(to.y) < 1.8 * _scale:
			move = Vector3.ZERO
		if flat.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), clampf(delta * 8.0, 0.0, 1.0))

	var spd := speed * (1.0 - (_slow if _slow_left > 0.0 else 0.0))
	if _stagger > 0.0:
		spd *= 0.2
	var horiz := Vector3(velocity.x, 0, velocity.z).move_toward(move * spd, 30.0 * delta)
	if _climb > 0.0:
		# Scaling a wall: up the face, then on over the top.
		_climb -= delta
		velocity.y = CLIMB_SPEED * clampf(spd / 3.0, 0.8, 1.5)
		horiz = move * spd * 0.7
	elif is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()
	# Pressing into a wall while the target is higher up: climb it. Zombies
	# follow you anywhere: onto roofs, up walls, over ledges.
	if move != Vector3.ZERO and is_on_wall() and _target != null and is_instance_valid(_target) and _target.global_position.y - global_position.y > 0.4:
		if move.dot(-get_wall_normal()) > 0.2:
			_climb = 0.3
	# Unstick: wanting to move but not getting anywhere -> hop, skip the
	# waypoint, and after a while repath with a sideways shuffle.
	var got := Vector2(velocity.x, velocity.z).length()
	if move != Vector3.ZERO and got < spd * 0.25 and _stagger <= 0.0 and _climb <= 0.0:
		_stuck += delta
		if _stuck > 0.5 and is_on_floor():
			velocity.y = 7.5
			_path_i += 1
		if _stuck > 1.8:
			_stuck = 0.0
			_repath = 0.0
			_path = PackedVector3Array()
			_path_i = 0
			# A small grounded sidestep breaks door-frame jams without snapping
			# the actor to another position (which looked like teleporting).
			var side := Vector3(-move.z, 0, move.x)
			velocity.x += side.x * minf(spd * 0.8, 2.0)
			velocity.z += side.z * minf(spd * 0.8, 2.0)
	else:
		_stuck = maxf(0.0, _stuck - delta)
	if global_position.y < -25.0:
		take_damage(99999.0, null, true)
		return

	# Shamble: legs swing, body sways, a lunge when attacking.
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs > 1.0 and Engine.get_physics_frames() % 6 == 0:
		Prop.kick_near(get_world_3d().direct_space_state, global_position + Vector3(0, 0.7, 0), 0.7 * _scale, velocity)
	_action_t = maxf(0.0, _action_t - delta)
	if _action_t <= 0.0:
		if hs < 0.3:
			_play("Idle")
		elif hs > 4.0:
			_play("Run", clampf(hs / 5.0, 0.8, 1.6))
		else:
			_play("Walk", clampf(hs / (1.6 * _scale), 0.7, 1.8))
	_body.rotation.x = -_lunge * 0.25 - (0.45 if _climb > 0.0 else 0.0)
	_groan -= delta
	if _groan <= 0.0:
		_groan = randf_range(4.0, 10.0)
		Sfx.play_at("zombie", global_position, -10.0, (0.7 if type == "brute" or type == "boss" else 1.0) * randf_range(0.9, 1.1))


func _pick_target() -> void:
	var old = _target
	var best = null
	var best_d := 1e9
	for p in game.hostiles(self):
		var d: float = p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	_target = best
	if _target != old:
		_best_d = 1e9
		_no_gain = 0.0
		_wall_spot = Vector3.INF


## Start scrambling up the wall in front of us: find the top of the wall
## (the roof edge just inside it) and climb straight up the face to it.
func _start_scale() -> void:
	if _scale_t >= 0.0:
		return
	var inner := global_position + _wall_in * 1.2
	var q := PhysicsRayQueryParameters3D.create(Vector3(inner.x, global_position.y + 30.0, inner.z), Vector3(inner.x, global_position.y + 0.5, inner.z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.position.y - global_position.y < 1.0:
		return
	_scale_from = global_position
	_scale_to = hit.position + Vector3(0, 0.15, 0)
	_scale_t = 0.0
	_scale_dur = clampf((_scale_to.y - _scale_from.y) / CLIMB_SPEED, 0.6, 4.5)
	collision_mask = 0
	velocity = Vector3.ZERO
	_wall_spot = Vector3.INF
	Sfx.play_at("zombie", global_position, -8.0, 1.2)


## Up the face (close against the wall), then over the edge onto the top.
func _update_scale(delta: float) -> void:
	_scale_t += delta / _scale_dur
	var f := clampf(_scale_t, 0.0, 1.0)
	var up := 0.85
	if f < up:
		var k := f / up
		var p := _scale_from.lerp(Vector3(_scale_from.x, _scale_to.y + 0.4, _scale_from.z), k)
		global_position = p + _wall_in * 0.25
	else:
		var k2 := (f - up) / (1.0 - up)
		global_position = Vector3(_scale_from.x, _scale_to.y + 0.4, _scale_from.z).lerp(_scale_to, k2) + _wall_in * 0.25 * (1.0 - k2)
	rotation.y = atan2(-_wall_in.x, -_wall_in.z)
	_body.rotation.x = -0.6 * (1.0 - smoothstep(0.8, 1.0, f))
	if Engine.get_physics_frames() % 10 == 0:
		_play("Walk", 1.4)
	if _scale_t >= 1.0:
		_scale_t = -1.0
		collision_mask = 1 | 2 | 4
		velocity = Vector3.ZERO
		_body.rotation.x = 0.0
		_repath = 0.0
		_best_d = 1e9


## The point just outside the wall of the building whose roof `target` is on,
## on the side nearest this zombie (Vector3.INF if it is not on a roof).
## _wall_in is set to the direction into that wall.
func _climb_spot(target: Vector3) -> Vector3:
	for r in game.map.roofs:
		var rr: Rect2 = r
		if not rr.has_point(Vector2(target.x, target.z)):
			continue
		var p := Vector2(clampf(global_position.x, rr.position.x, rr.end.x), clampf(global_position.z, rr.position.y, rr.end.y))
		var d := [p.x - rr.position.x, rr.end.x - p.x, p.y - rr.position.y, rr.end.y - p.y]
		var i: int = d.find(d.min())
		var out := [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)][i] as Vector2
		var edge := p
		match i:
			0: edge.x = rr.position.x
			1: edge.x = rr.end.x
			2: edge.y = rr.position.y
			3: edge.y = rr.end.y
		var spot := edge + out * 0.9
		_wall_in = Vector3(-out.x, 0, -out.y)
		return Vector3(spot.x, 0.0, spot.y)
	return Vector3.INF


func _clear(t) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), t.chest_position(), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _attack(t) -> void:
	_attack_cd = 1.1 if type != "runner" else 0.8
	_lunge = 1.0
	_play("Punch" if _anim != null and _anim.has_animation("Punch") else "Idle_Attack", 1.6)
	if _anim != null:
		_anim.seek(0.0)
	_action_t = 0.55
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



func _set_flash(on: bool) -> void:
	if on == _flashing:
		return
	_flashing = on
	for mi in _meshes_inst:
		mi.material_overlay = _flash_mat if on else null
