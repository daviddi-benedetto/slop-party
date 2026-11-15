extends RefCounted
## AI "input device". Exposes the same fields as input_source.gd, so player.gd
## treats bots and humans identically.
##
## Behaviour: pick the nearest living enemy. With line of sight -> aim (with
## lead, turn-rate limit and wobble), strafe and shoot. Without -> follow an
## A* path over the map's auto-generated nav graph (map.gd: find_path).

var device := -2

var move := Vector2.ZERO
var fire := false
var jump := false
var dash := false
var reload := false
var ui_left := false
var ui_right := false
var ui_accept := false

var skill := 0.6            # 0..1, scales turn speed and accuracy

var _target = null
var _has_los := false
var _los_time := 0.0
var _think := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _wobble := Vector2.ZERO
var _wobble_t := 0.0
var _stuck := 0.0


func label() -> String:
	return "Bot"


func update_look(_player, _delta: float) -> void:
	pass


func update_buttons(player, delta: float) -> void:
	move = Vector2.ZERO
	fire = false
	jump = false
	dash = false
	reload = false
	if not player.alive:
		_path = PackedVector3Array()
		_target = null
		return
	var game = player.game

	_think -= delta
	if _think <= 0.0:
		_think = 0.2
		_pick_target(player, game)

	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(0.5, 1.6)
		_strafe = 1.0 if randf() < 0.5 else -1.0
	_wobble_t -= delta
	if _wobble_t <= 0.0:
		_wobble_t = 0.35
		var err := lerpf(0.09, 0.02, skill)
		_wobble = Vector2(randf_range(-err, err), randf_range(-err, err))

	var world_move := Vector3.ZERO
	if _target != null and _has_los:
		_los_time += delta
		var eye: Vector3 = player.eye_position()
		var tpos: Vector3 = _target.chest_position()
		var dist := eye.distance_to(tpos)
		var t: float = dist / player.stats.bullet_speed
		var aim: Vector3 = tpos + _target.velocity * t * 0.8 + Vector3.UP * 0.5 * player.stats.bullet_gravity * t * t
		var err := _turn_toward(player, aim - eye, delta, lerpf(3.0, 7.0, skill), _wobble)
		if err < 0.12 and _los_time > lerpf(0.55, 0.2, skill) and dist < 55.0:
			fire = true
		var to_t := (tpos - eye)
		to_t.y = 0.0
		to_t = to_t.normalized()
		var side := to_t.cross(Vector3.UP) * _strafe
		var fwd := 0.0
		# Short-range weapons (Scatter) have to get close.
		var reach: float = player.stats.bullet_speed * player.stats.bullet_life
		if dist > minf(16.0, reach * 0.45):
			fwd = 1.0
		elif dist < 6.0:
			fwd = -1.0
		world_move = (side + to_t * fwd).normalized()
		if randf() < 0.006:
			jump = true
		if randf() < 0.004:
			dash = true
		_repath = 0.0
	else:
		_los_time = 0.0
		_repath -= delta
		if _repath <= 0.0 or _path_i >= _path.size():
			_repath = 1.2
			var goal: Vector3 = _target.global_position if _target != null else game.map.random_nav_point()
			_path = game.map.find_path(player.global_position, goal)
			_path_i = 0
		if _path_i < _path.size():
			var wp := _path[_path_i]
			var d: Vector3 = wp - player.global_position
			var flat := Vector3(d.x, 0.0, d.z)
			if flat.length() < 0.9 and absf(d.y) < 1.6:
				_path_i += 1
			else:
				world_move = flat.normalized()
		elif _target != null:
			var d2: Vector3 = _target.global_position - player.global_position
			world_move = Vector3(d2.x, 0.0, d2.z).normalized()
		if world_move.length() > 0.1:
			_turn_toward(player, world_move, delta, 6.0, Vector2.ZERO)
		if player.ammo < player.stats.mag_size / 2:
			reload = true

	# Unstick: if we want to move but aren't, hop and shuffle.
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	if world_move.length() > 0.1 and hspeed < 1.0:
		_stuck += delta
		if _stuck > 0.35:
			jump = player.is_on_floor()
			world_move = (world_move + world_move.cross(Vector3.UP) * _strafe).normalized()
		if _stuck > 2.0:
			_stuck = 0.0
			_path = game.map.find_path(player.global_position, game.map.random_nav_point())
			_path_i = 0
			_repath = 3.0
	else:
		_stuck = 0.0

	# World-space wish direction -> stick input relative to our facing.
	var local := Basis(Vector3.UP, player.yaw).inverse() * world_move
	move = Vector2(local.x, -local.z)


func _pick_target(player, game) -> void:
	var best = null
	var best_d := 1e9
	for p in game.players:
		if p == player or not p.alive:
			continue
		var d: float = p.global_position.distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			best = p
	if best != _target:
		_los_time = 0.0
	_target = best
	_has_los = false
	if best != null:
		var q := PhysicsRayQueryParameters3D.create(player.eye_position(), best.chest_position(), 1)
		_has_los = player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Rotate the player's view toward `dir`. Returns the remaining angular error.
func _turn_toward(player, dir: Vector3, delta: float, rate: float, wobble: Vector2) -> float:
	if dir.length_squared() < 0.0001:
		return 0.0
	dir = dir.normalized()
	var want_yaw := atan2(-dir.x, -dir.z) + wobble.x
	var want_pitch := asin(clampf(dir.y, -1.0, 1.0)) + wobble.y
	var dy := wrapf(want_yaw - player.yaw, -PI, PI)
	var dp: float = want_pitch - player.pitch
	var step := rate * delta
	player.yaw += clampf(dy, -step, step)
	player.pitch = clampf(player.pitch + clampf(dp, -step, step), -1.4, 1.4)
	return absf(dy) - minf(absf(dy), step) + absf(dp) - minf(absf(dp), step)
