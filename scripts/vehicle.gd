extends CharacterBody3D
## Frontline vehicles: "buggy" (fast, mounted machine gun, rams), "tank"
## (slow, armoured, turret cannon + coaxial MG) and "heli" (flies, nose gun +
## rocket salvos). One seat each.
##
## Getting in: player.gd shows "GET IN ..." near a free vehicle (game.vehicle_near)
## and calls enter(). The player is hidden and stops colliding; game.gd
## switches that view to a chase camera (_vehicle_camera). The vehicle reads
## the driver's brain every physics tick:
##   move stick     drive / fly (forward, turn or strafe)
##   look           camera; turret and guns follow where the camera looks
##   fire (RT/LMB)  main weapon         aim (LT/RMB)  second weapon / zoom
##   jump / crouch  climb / descend (heli)            interact  get out
## Damage: on the player collision layer, so bullets hit it; also in
## game.actors for explosions. Friendly fire is ignored. At 0 health it
## explodes, throws the driver out (hurt) and frontline.gd respawns a new one
## at its home spot later.

const Fx = preload("res://scripts/fx.gd")
const Bullet = preload("res://scripts/bullet.gd")
const Stats = preload("res://scripts/stats.gd")

const GRAVITY := 22.0
const SPECS := {
	"buggy": {"label": "BUGGY", "hp": 450.0, "speed": 24.0, "accel": 18.0, "turn": 2.2, "size": Vector3(2.2, 1.1, 3.8),
		"cam_h": 2.4, "cam_d": 7.5, "enter": 2.4},
	"tank": {"label": "TANK", "hp": 1600.0, "speed": 10.0, "accel": 6.0, "turn": 1.0, "size": Vector3(3.4, 1.6, 5.6),
		"cam_h": 3.6, "cam_d": 11.0, "enter": 3.2},
	"heli": {"label": "HELICOPTER", "hp": 750.0, "speed": 26.0, "accel": 14.0, "turn": 2.0, "size": Vector3(2.4, 2.0, 4.6),
		"cam_h": 3.0, "cam_d": 13.0, "enter": 3.0},
}

var game
var type := "buggy"
var label := "BUGGY"
var team := -5                   # the driver's team while occupied
var home_team := 0
var pname := "BUGGY"
var color := Color.WHITE
var kind := 0
var alive := true
var health := 450.0
var max_health := 450.0
var driver = null
var home := Transform3D()
var enter_radius := 2.4
var cam_height := 2.4
var cam_dist := 7.5
var can_zoom := false
var hurt_flash := 0.0
var main_cd := 0.0               # seconds until the main weapon is ready
var alt_cd := 0.0
var rockets := 4
var throttle := 0.0
var last_attacker = null

var _spec: Dictionary
var _speed := 0.0
var _turret: Node3D
var _gun: Node3D
var _muzzles: Array = []         # Node3D markers (main, alt)
var _rotor: Node3D
var _wheels: Array = []
var _visual: Node3D
var _mats: Array = []
var _engine_t := 0.0
var _mg_stats
var _main_stats


func setup(kind_name: String, xf: Transform3D, team_id: int, team_color: Color) -> void:
	type = kind_name
	_spec = SPECS[type]
	label = _spec.label
	pname = label
	home = xf
	home_team = team_id
	color = team_color
	max_health = _spec.hp
	health = max_health
	enter_radius = _spec.enter
	cam_height = _spec.cam_h
	cam_dist = _spec.cam_d
	can_zoom = type == "buggy"


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(42.0)
	floor_snap_length = 0.0 if type == "heli" else 0.7
	var size: Vector3 = _spec.size
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = size.y * 0.5 + (0.35 if type != "tank" else 0.1)
	add_child(cs)
	global_transform = home
	_visual = Node3D.new()
	add_child(_visual)
	match type:
		"tank": _build_tank()
		"heli": _build_heli()
		_: _build_buggy()
	_merge_tree(_visual)
	_mg_stats = _weapon_stats(10.0, 0.0, 160.0, 0.0, 0.03)
	_main_stats = _weapon_stats(130.0, 4.5, 85.0, 7.0, 0.0) if type == "tank" else _weapon_stats(75.0, 3.5, 60.0, 0.0, 0.02)
	game.actors.append(self)
	game.vehicles.append(self)


func _exit_tree() -> void:
	game.actors.erase(self)
	game.vehicles.erase(self)


func _weapon_stats(damage: float, explosive: float, speed: float, grav: float, spread: float):
	var s = Stats.new()
	s.damage = damage
	s.explosive = explosive
	s.bullet_speed = speed
	s.bullet_gravity = grav
	s.bullet_life = 4.0
	s.bullet_size = 2.4 if explosive > 0.0 else 1.2
	s.spread = spread
	s.smoke = explosive > 0.0
	return s


func seat_count() -> int:
	return 1


func chest_position() -> Vector3:
	return global_position + Vector3(0, _spec.size.y * 0.6 + 0.3, 0)


func hit_radius() -> float:
	return maxf(_spec.size.x, _spec.size.z) * 0.5


func head_height() -> float:
	return 999.0


func is_blocking() -> bool:
	return false


func apply_poison(_total: float, _src) -> void:
	pass


func apply_slow(_amount: float) -> void:
	pass


# --------------------------------------------------------------------------
# Seat
# --------------------------------------------------------------------------

func enter(p) -> void:
	if driver != null or not alive:
		return
	driver = p
	team = p.team
	p.enter_vehicle(self)
	Sfx.play_at("engine", global_position, -2.0, 0.7)


## Put the driver back on foot beside the vehicle (or on top if blocked).
func eject(p) -> void:
	if p != driver:
		return
	driver = null
	team = -5
	var side: Vector3 = global_transform.basis.x * (_spec.size.x * 0.5 + 1.2)
	var spots := [global_position + side, global_position - side, global_position + Vector3(0, _spec.size.y + 0.6, 0)]
	var pos: Vector3 = spots[2]
	for s in spots:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.2, 0), s + Vector3(0, 1.2, 0), 1)
		if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			pos = s + Vector3(0, 0.3, 0)
			break
	p.exit_vehicle(pos)
	if type == "heli" and global_position.y > 8.0:
		p.skydive = true         # bailing out of a helicopter: parachute down


## Called from the driver's player._physics_process (after its brain update).
func control(p, _delta: float) -> void:
	p.global_position = global_position + Vector3(0, 0.6, 0)
	if p.brain.interact:
		eject(p)


# --------------------------------------------------------------------------
# Simulation
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive:
		return
	hurt_flash = maxf(0.0, hurt_flash - delta * 4.0)
	main_cd = maxf(0.0, main_cd - delta)
	alt_cd = maxf(0.0, alt_cd - delta)
	if driver != null and (not is_instance_valid(driver) or not driver.alive or driver.vehicle != self):
		driver = null
		team = -5
	var b = driver.brain if driver != null and not game.frozen else null
	match type:
		"heli": _fly(delta, b)
		_: _drive(delta, b)
	if b != null:
		_aim_and_fire(delta, b)
	if global_position.y < -25.0:
		take_damage(99999.0, null)
	# Engine sound pulses faster with speed.
	if driver != null:
		_engine_t -= delta
		if _engine_t <= 0.0:
			_engine_t = 0.28 if type == "heli" else clampf(0.4 - absf(_speed) * 0.012, 0.12, 0.4)
			Sfx.play_at("rotor" if type == "heli" else "engine", global_position, -9.0, (0.6 if type == "tank" else 1.0) + absf(_speed) * 0.02)


func _drive(delta: float, b) -> void:
	var move: Vector2 = b.move if b != null else Vector2.ZERO
	throttle = move.y
	var top: float = _spec.speed
	var want: float = move.y * top * (0.5 if move.y < 0.0 else 1.0)
	_speed = move_toward(_speed, want, _spec.accel * delta * (1.6 if signf(want) != signf(_speed) else 1.0))
	if absf(move.y) < 0.05:
		_speed = move_toward(_speed, 0.0, _spec.accel * 0.6 * delta)
	var steer: float = -move.x * _spec.turn
	if type == "buggy":
		steer *= clampf(absf(_speed) / 6.0, 0.0, 1.0) * signf(_speed if absf(_speed) > 0.1 else 1.0)
	rotate_y(steer * delta)
	var fwd := -global_transform.basis.z
	var v := fwd * _speed
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	velocity.x = v.x
	velocity.z = v.z
	var before := velocity
	move_and_slide()
	# Hitting a wall kills speed; hitting a hostile at speed rams it.
	if get_slide_collision_count() > 0 and absf(_speed) > 2.0:
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			var other = c.get_collider()
			if other != null and other.has_method("take_damage") and other != self and absf(_speed) > 7.0:
				if game.is_enemy(driver, other) and other.alive:
					other.take_damage(absf(_speed) * (3.0 if type == "buggy" else 6.0), driver)
					if "velocity" in other and not other.has_method("seat_count"):
						other.velocity += before.normalized() * 10.0 + Vector3(0, 5.0, 0)
					Fx.sparks(game.world, c.get_position(), Color(1, 0.8, 0.5), 10, 6.0)
			elif c.get_normal().y < 0.5:
				_speed *= 0.6
	# Visual tilt to the ground and wheel spin.
	if is_on_floor():
		var n := get_floor_normal()
		var local := global_transform.basis.inverse() * n
		_visual.rotation.x = lerpf(_visual.rotation.x, atan2(-local.z, local.y), clampf(delta * 8.0, 0.0, 1.0))
		_visual.rotation.z = lerpf(_visual.rotation.z, atan2(local.x, local.y), clampf(delta * 8.0, 0.0, 1.0))
	for w in _wheels:
		w.rotation.x -= _speed * delta / 0.45
	if type == "buggy" and _wheels.size() >= 2:
		for i in 2:
			_wheels[i].get_parent().rotation.y = move.x * -0.45


func _fly(delta: float, b) -> void:
	var move: Vector2 = b.move if b != null else Vector2.ZERO
	var up := 0.0
	if b != null:
		up = (1.0 if b.jump_held else 0.0) - (1.0 if b.crouch else 0.0)
		# The helicopter turns to face where the pilot looks.
		rotation.y = lerp_angle(rotation.y, driver.yaw, clampf(delta * _spec.turn, 0.0, 1.0))
	var basis := Basis(Vector3.UP, rotation.y)
	var want: Vector3 = basis * Vector3(move.x, 0, -move.y) * _spec.speed
	var horiz := Vector3(velocity.x, 0, velocity.z).move_toward(want, _spec.accel * delta)
	var vy := velocity.y
	if driver == null:
		vy -= GRAVITY * 0.6 * delta          # unmanned: settles to the ground
	else:
		vy = move_toward(vy, up * 9.0, 18.0 * delta)
		if global_position.y > 70.0:
			vy = minf(vy, 0.0)
	velocity = Vector3(horiz.x, vy, horiz.z)
	move_and_slide()
	if is_on_floor() and driver == null:
		velocity = Vector3.ZERO
	_speed = horiz.length()
	var local := basis.inverse() * horiz
	_visual.rotation.x = lerpf(_visual.rotation.x, clampf(-local.z / _spec.speed, -1.0, 1.0) * -0.25, clampf(delta * 3.0, 0.0, 1.0))
	_visual.rotation.z = lerpf(_visual.rotation.z, clampf(local.x / _spec.speed, -1.0, 1.0) * -0.3, clampf(delta * 3.0, 0.0, 1.0))
	if _rotor != null:
		_rotor.rotation.y += delta * (28.0 if driver != null or not is_on_floor() else 4.0)


## Where the driver's crosshair points (same maths as game._vehicle_camera).
func _aim_point() -> Vector3:
	var pitch: float = driver.pitch * 0.85 - 0.12
	var basis := Basis.from_euler(Vector3(pitch, driver.yaw, 0.0))
	var pivot := global_position + Vector3(0, cam_height, 0)
	var origin := pivot + basis * Vector3(0, 0.4, cam_dist)
	var dir := -basis.z
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 300.0, 1 | 2)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if hit else origin + dir * 300.0


func _aim_and_fire(delta: float, b) -> void:
	var target := _aim_point()
	# Turret / gun follow the crosshair (the tank's turret turns slowly).
	if _turret != null:
		var to := target - _turret.global_position
		var want_yaw := atan2(-to.x, -to.z) - global_rotation.y
		var rate := 1.4 if type == "tank" else 8.0
		_turret.rotation.y = rotate_toward(_turret.rotation.y, wrapf(want_yaw, -PI, PI), rate * delta)
		if _gun != null:
			var flat := Vector2(to.x, to.z).length()
			if type == "heli":
				_gun.rotation.x = clampf(atan2(to.y, flat) - _visual.rotation.x, -1.3, 0.3)
			else:
				_gun.rotation.x = clampf(atan2(to.y, flat), -0.15, 0.5)
	if b.fire:
		_fire_main(target)
	if b.aim and type != "buggy":
		_fire_alt(target)


func _fire_main(target: Vector3) -> void:
	match type:
		"tank":
			if main_cd > 0.0:
				return
			main_cd = 2.6
			_shoot(_muzzles[0], target, _main_stats, 1)
			Sfx.play_at("cannon", global_position, 2.0)
			driver.shake = maxf(driver.shake, 0.6)
			if _gun != null:
				var tw := create_tween()
				tw.tween_property(_gun, "position:z", 0.5, 0.05)
				tw.tween_property(_gun, "position:z", 0.0, 0.5)
		_:
			if main_cd > 0.0:
				return
			main_cd = 0.085
			_shoot(_muzzles[0], target, _mg_stats, 1)
			Sfx.play_at("shot_burst", global_position, -2.0, 0.8)


func _fire_alt(target: Vector3) -> void:
	if alt_cd > 0.0:
		return
	if type == "tank":
		alt_cd = 0.1
		_shoot(_muzzles[1], target, _mg_stats, 1)
		Sfx.play_at("shot_burst", global_position, -4.0, 0.9)
	elif type == "heli":
		rockets -= 1
		alt_cd = 0.22
		if rockets <= 0:
			rockets = 4
			alt_cd = 3.0
		_shoot(_muzzles[1 + rockets % 2], target, _main_stats, 1)
		Sfx.play_at("shot_boomer", global_position, -1.0)


func _shoot(muzzle: Node3D, target: Vector3, s, count: int) -> void:
	var from := muzzle.global_position
	for i in count:
		var dir := (target - from).normalized()
		if s.spread > 0.0:
			dir = (dir + Vector3(randf_range(-s.spread, s.spread), randf_range(-s.spread, s.spread), randf_range(-s.spread, s.spread))).normalized()
		var bl = Bullet.new()
		bl.setup_stats(driver, s, dir, 1.0, [get_rid()])
		game.world.add_child(bl)
		bl.global_position = from
		bl.orient()
		bl.reset_physics_interpolation()
	Fx.flash(game.world, from, Color(1.0, 0.85, 0.5, 0.9), 0.1, 0.5 if s.explosive > 0.0 else 0.25, 0.07)
	driver.recoil = 1.0


# --------------------------------------------------------------------------
# Damage
# --------------------------------------------------------------------------

func take_damage(amount: float, attacker, _silent := false, _crit := false) -> float:
	if not alive:
		return 0.0
	if attacker != null and is_instance_valid(attacker) and driver != null and not game.is_enemy(attacker, driver):
		return 0.0
	if attacker != null and is_instance_valid(attacker) and attacker == driver:
		return 0.0
	health -= amount
	hurt_flash = 1.0
	if attacker != null and is_instance_valid(attacker):
		last_attacker = attacker
		if game.is_player(attacker):
			attacker.hit_marker = 0.8
			if attacker.has_view and Settings.v("numbers"):
				Fx.damage_number(game.world, chest_position() + Vector3(0, 1.0, 0), amount, false, attacker.viewmodel_layer_bit())
	if driver != null:
		driver.shake = maxf(driver.shake, clampf(amount / 120.0, 0.15, 0.7))
		driver.hurt_flash = 0.6
	for m in _mats:
		m.emission = Color(1.0, 0.5, 0.3) * 0.6
	if health <= 0.0:
		_destroy()
	return amount


func _destroy() -> void:
	alive = false
	var pos := chest_position()
	var d = driver
	if d != null:
		eject(d)
		d.take_damage(60.0, last_attacker)
	collision_layer = 0
	game.actors.erase(self)
	game.vehicles.erase(self)
	game.explode(pos, 6.0, 70.0, last_attacker if last_attacker != null and is_instance_valid(last_attacker) else null, null)
	Fx.puff(game.world, pos, Color(0.15, 0.13, 0.13, 0.9), 24, 2.5)
	Fx.burst(game.world, pos, Color(1.0, 0.6, 0.2), 24, 10.0, 0.6, 0.8, -8.0)
	Sfx.play_at("cannon", pos, 4.0, 0.6)
	# A charred wreck that lingers, then disappears.
	var char_mat := StandardMaterial3D.new()
	char_mat.albedo_color = Color(0.08, 0.07, 0.07)
	char_mat.roughness = 1.0
	_set_override(_visual, char_mat)
	if game.rules != null and game.rules.has_method("vehicle_destroyed"):
		game.rules.vehicle_destroyed(type, home, home_team)
	var tw := create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(self, "scale", Vector3(1, 0.01, 1), 0.6)
	tw.tween_callback(queue_free)
	if type == "heli":
		velocity = Vector3(0, -6.0, 0)


func _set_override(n: Node, m: Material) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			c.material_override = m
		_set_override(c, m)


func _process(delta: float) -> void:
	if not alive:
		if type == "heli" and not is_on_floor():
			velocity.y -= GRAVITY * delta
			move_and_slide()
		return
	for m in _mats:
		m.emission = m.emission.lerp(Color.BLACK, clampf(delta * 6.0, 0.0, 1.0))


# --------------------------------------------------------------------------
# Models (boxes and cylinders; the team colour is the paint)
# --------------------------------------------------------------------------

## Merge the static parts under every node of the model (each pivot keeps
## its own merged mesh so turrets, guns, rotors and wheels still move):
## ~40 parts become a handful of draw calls per view.
func _merge_tree(n: Node3D) -> void:
	for c in n.get_children():
		if c is Node3D and not c is MeshInstance3D:
			_merge_tree(c)
	var groups := {}
	var order: Array = []
	for c in n.get_children():
		if c is MeshInstance3D:
			var m: Material = c.material_override
			if not groups.has(m):
				groups[m] = []
				order.append(m)
			groups[m].append(c)
	if order.size() == 0 or n.get_child_count() <= 1:
		return
	var am := ArrayMesh.new()
	for m in order:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mi in groups[m]:
			st.append_from(mi.mesh, 0, mi.transform)
			n.remove_child(mi)
			mi.queue_free()
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, m)
	var merged := MeshInstance3D.new()
	merged.mesh = am
	n.add_child(merged)


func _mat(col: Color, rough := 0.6, metal := 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.emission_enabled = true
	m.emission = Color.BLACK
	_mats.append(m)
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _bx(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _part(parent, b, mat, pos, rot)


func _cy(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot := Vector3.ZERO, r_top := -1.0) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r if r_top < 0.0 else r_top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 14
	c.rings = 1
	return _part(parent, c, mat, pos, rot)


func _marker(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	_muzzles.append(n)
	return n


func _wheel(pos: Vector3, r: float, w: float, tyre: Material, hub: Material, steer := false) -> void:
	var holder := Node3D.new()
	holder.position = pos
	_visual.add_child(holder)
	var spin := Node3D.new()
	holder.add_child(spin)
	_cy(spin, r, w, tyre, Vector3.ZERO, Vector3(0, 0, PI * 0.5))
	_cy(spin, r * 0.5, w + 0.04, hub, Vector3.ZERO, Vector3(0, 0, PI * 0.5))
	_bx(spin, Vector3(w + 0.06, r * 0.25, r * 1.1), hub, Vector3.ZERO)
	if steer:
		_wheels.push_front(spin)
	else:
		_wheels.append(spin)


func _build_buggy() -> void:
	var paint := _mat(color, 0.4, 0.4)
	var dark := _mat(Color(0.08, 0.08, 0.1), 0.6, 0.4)
	var metal := _mat(Color(0.5, 0.52, 0.55), 0.3, 0.9)
	var tyre := _mat(Color(0.05, 0.05, 0.06), 0.9, 0.0)
	_bx(_visual, Vector3(1.6, 0.35, 3.4), dark, Vector3(0, 0.6, 0))
	_bx(_visual, Vector3(1.7, 0.3, 1.3), paint, Vector3(0, 0.85, -1.15), Vector3(0.12, 0, 0))
	_bx(_visual, Vector3(1.7, 0.4, 0.9), paint, Vector3(0, 0.9, 1.3))
	_bx(_visual, Vector3(0.5, 0.3, 0.5), metal, Vector3(0, 0.85, 1.0))
	for sx in [-0.55, 0.55]:
		_bx(_visual, Vector3(0.5, 0.15, 0.6), dark, Vector3(sx, 0.85, 0.2))
		_bx(_visual, Vector3(0.45, 0.6, 0.12), dark, Vector3(sx, 1.1, 0.5))
	# Roll cage.
	for sx in [-0.75, 0.75]:
		_cy(_visual, 0.05, 1.3, metal, Vector3(sx, 1.4, -0.5), Vector3(0.35, 0, 0))
		_cy(_visual, 0.05, 1.1, metal, Vector3(sx, 1.35, 0.95), Vector3(-0.3, 0, 0))
		_cy(_visual, 0.05, 1.5, metal, Vector3(sx, 1.95, 0.25), Vector3(PI * 0.5, 0, 0))
	_cy(_visual, 0.05, 1.5, metal, Vector3(0, 1.95, 0.95), Vector3(0, 0, PI * 0.5))
	_cy(_visual, 0.05, 1.5, metal, Vector3(0, 1.95, -0.45), Vector3(0, 0, PI * 0.5))
	_bx(_visual, Vector3(1.5, 0.12, 0.12), _mat(Color(1.0, 0.9, 0.6) * 2.0), Vector3(0, 0.8, -1.82))
	for sx in [-0.95, 0.95]:
		_wheel(Vector3(sx, 0.45, -1.2), 0.45, 0.35, tyre, metal, true)
	for sx in [-0.95, 0.95]:
		_wheel(Vector3(sx, 0.45, 1.25), 0.48, 0.4, tyre, metal)
	# Mounted machine gun on a pintle behind the seats.
	_turret = Node3D.new()
	_turret.position = Vector3(0, 2.05, 0.95)
	_visual.add_child(_turret)
	_cy(_turret, 0.06, 0.3, dark, Vector3(0, -0.1, 0))
	_gun = Node3D.new()
	_turret.add_child(_gun)
	_bx(_gun, Vector3(0.18, 0.2, 0.55), dark, Vector3(0, 0.05, -0.1))
	_cy(_gun, 0.035, 0.7, metal, Vector3(0, 0.07, -0.7), Vector3(PI * 0.5, 0, 0))
	_bx(_gun, Vector3(0.12, 0.18, 0.2), paint, Vector3(0.15, 0.0, -0.05))
	_marker(_gun, Vector3(0, 0.07, -1.1))


func _build_tank() -> void:
	var paint := _mat(color.darkened(0.25), 0.7, 0.3)
	var stripe := _mat(color, 0.5, 0.3)
	var dark := _mat(Color(0.12, 0.13, 0.12), 0.8, 0.3)
	var metal := _mat(Color(0.35, 0.36, 0.38), 0.4, 0.8)
	var tread := _mat(Color(0.06, 0.06, 0.06), 0.95, 0.1)
	_bx(_visual, Vector3(3.0, 0.9, 5.4), paint, Vector3(0, 0.95, 0))
	_bx(_visual, Vector3(2.6, 0.5, 1.2), paint, Vector3(0, 0.7, -2.7), Vector3(-0.5, 0, 0))
	_bx(_visual, Vector3(3.05, 0.08, 5.0), stripe, Vector3(0, 1.38, 0))
	for sx in [-1.55, 1.55]:
		_bx(_visual, Vector3(0.7, 0.9, 5.8), tread, Vector3(sx, 0.5, 0))
		_bx(_visual, Vector3(0.8, 0.1, 5.6), dark, Vector3(sx, 1.0, 0))
		for i in 6:
			# Road wheels are static (the treads hide them), so they merge.
			_cy(_visual, 0.36, 0.25, dark, Vector3(sx * 1.02, 0.42, -2.2 + i * 0.88), Vector3(0, 0, PI * 0.5))
			_cy(_visual, 0.18, 0.29, metal, Vector3(sx * 1.02, 0.42, -2.2 + i * 0.88), Vector3(0, 0, PI * 0.5))
	_turret = Node3D.new()
	_turret.position = Vector3(0, 1.4, 0.3)
	_visual.add_child(_turret)
	_bx(_turret, Vector3(2.2, 0.75, 2.6), paint, Vector3(0, 0.4, 0))
	_bx(_turret, Vector3(1.8, 0.4, 0.8), paint, Vector3(0, 0.35, -1.5), Vector3(-0.3, 0, 0))
	_cy(_turret, 0.4, 0.3, dark, Vector3(0.55, 0.9, 0.4))
	_bx(_turret, Vector3(0.8, 0.5, 0.7), dark, Vector3(0, 0.45, 1.5))
	_bx(_turret, Vector3(2.25, 0.08, 0.2), stripe, Vector3(0, 0.6, 0.9))
	_gun = Node3D.new()
	_gun.position = Vector3(0, 0.45, -1.3)
	_turret.add_child(_gun)
	_cy(_gun, 0.13, 3.4, metal, Vector3(0, 0, -1.7), Vector3(PI * 0.5, 0, 0))
	_cy(_gun, 0.2, 0.5, dark, Vector3(0, 0, -3.3), Vector3(PI * 0.5, 0, 0))
	_cy(_gun, 0.25, 0.6, paint, Vector3(0, 0, -0.1), Vector3(PI * 0.5, 0, 0))
	_marker(_gun, Vector3(0, 0, -3.65))
	_cy(_gun, 0.04, 0.6, dark, Vector3(0.4, 0.05, -0.5), Vector3(PI * 0.5, 0, 0))
	_marker(_gun, Vector3(0.4, 0.05, -0.85))


func _build_heli() -> void:
	var paint := _mat(color, 0.45, 0.4)
	var dark := _mat(Color(0.1, 0.1, 0.12), 0.6, 0.4)
	var metal := _mat(Color(0.45, 0.46, 0.5), 0.35, 0.8)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.25, 0.4, 0.5, 0.6)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.5
	var body := SphereMesh.new()
	body.radius = 1.0
	body.height = 2.0
	body.radial_segments = 16
	body.rings = 8
	_part(_visual, body, paint, Vector3(0, 1.45, 0.2)).scale = Vector3(1.15, 1.0, 2.2)
	_part(_visual, body, glass, Vector3(0, 1.75, -1.15)).scale = Vector3(0.9, 0.7, 1.0)
	_cy(_visual, 0.35, 4.6, paint, Vector3(0, 1.75, 3.6), Vector3(PI * 0.5, 0, 0), 0.15)
	_bx(_visual, Vector3(0.12, 1.3, 0.8), paint, Vector3(0, 2.3, 5.7))
	_bx(_visual, Vector3(1.6, 0.1, 0.5), paint, Vector3(0, 1.8, 5.2))
	var tail := Node3D.new()
	tail.position = Vector3(0.15, 2.4, 5.8)
	_visual.add_child(tail)
	_bx(tail, Vector3(0.05, 1.2, 0.12), dark, Vector3.ZERO)
	for sx in [-0.8, 0.8]:
		_cy(_visual, 0.06, 3.2, metal, Vector3(sx, 0.15, 0.1), Vector3(PI * 0.5, 0, 0))
		_cy(_visual, 0.05, 0.6, metal, Vector3(sx, 0.4, -0.7), Vector3(0, 0, sx * 0.4))
		_cy(_visual, 0.05, 0.6, metal, Vector3(sx, 0.4, 0.9), Vector3(0, 0, sx * 0.4))
		# Stub wings with rocket pods.
		_bx(_visual, Vector3(0.9, 0.1, 0.6), dark, Vector3(sx * 1.4, 1.3, 0.2))
		_cy(_visual, 0.16, 0.9, dark, Vector3(sx * 1.75, 1.15, 0.1), Vector3(PI * 0.5, 0, 0))
	_bx(_visual, Vector3(0.5, 0.35, 1.2), dark, Vector3(0, 2.55, 0.3))
	_cy(_visual, 0.08, 0.5, metal, Vector3(0, 2.85, 0.2))
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 3.1, 0.2)
	_visual.add_child(_rotor)
	for a in 4:
		var ang := a * PI * 0.5
		_bx(_rotor, Vector3(0.28, 0.04, 4.6), dark, Basis(Vector3.UP, ang) * Vector3(0, 0, 2.3), Vector3(0, ang, 0))
	# Nose gun turret.
	_turret = Node3D.new()
	_turret.position = Vector3(0, 0.75, -1.6)
	_visual.add_child(_turret)
	_part(_turret, body, dark, Vector3.ZERO).scale = Vector3.ONE * 0.22
	_gun = Node3D.new()
	_turret.add_child(_gun)
	_cy(_gun, 0.04, 0.8, metal, Vector3(0, 0, -0.45), Vector3(PI * 0.5, 0, 0))
	_marker(_gun, Vector3(0, 0, -0.9))
	for sx in [-1.75, 1.75]:
		_marker(_visual, Vector3(sx, 1.15, -0.5))
