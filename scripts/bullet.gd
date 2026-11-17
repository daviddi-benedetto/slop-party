extends Node3D
## A projectile. Not a physics body: each tick it ray-casts along the segment
## it is about to travel (cheap, and never tunnels). All behaviour comes from
## a snapshot of the shooter's stats taken when it was fired, so later card
## picks do not change bullets already in the air.
##
## Behaviours: gravity, homing, bouncing (optionally gaining damage), piercing
## through players, exploding on impact, grenades (fuse > 0: bounce until the
## fuse runs out, or explode on touching a player), smoke trails, flame puffs,
## the on-hit effects (poison, frost, knockback), and being reflected by a
## player who is blocking (it then belongs to the blocker).
##
## Looks: a glowing core plus an additive tapered trail whose length follows
## the speed, both in the owner's colour.

const Fx = preload("res://scripts/fx.gd")

const WORLD_MASK := 1
const PLAYER_MASK := 2
const PROP_MASK := 4             # loose props and glass (prop.gd, glass.gd)
const DOOR_MASK := 8             # doors (door.gd)
const Models = preload("res://scripts/models.gd")
## stats.projectile -> [model, length in metres, spin (rad/s)]; the models
## are modelled along +Y and get turned to fly point first.
const PROJECTILES := {
	"arrow": ["medieval/Skeleton_Arrow", 0.95, 0.0],
	"bolt": ["medieval/Skeleton_Arrow", 0.6, 0.0],
	"knife": ["medieval/Dagger", 0.42, -22.0],
	"bomb": ["medieval/Bomb", 0.34, -7.0],
}

static var _mesh: SphereMesh
static var _cone: CylinderMesh
const BLOCK_RADIUS := 1.1   # how close to a blocker's chest a projectile gets caught
static var _flame_mat: StandardMaterial3D

var shooter
var game
var vel := Vector3.ZERO
var damage := 10.0
var gravity := 0.0
var bounces := 0
var bounce_bonus := 0.0
var pierce := 0
var explosive := 0.0
var fuse := 0.0
var smoke := false
var flame := false
var homing := 0.0
var poison := 0.0
var frost := 0.0
var knockback := 0.0
var giant_slayer := 0.0
var chain := 0
var cluster := 0
var vortex := 0.0
var sticky := false
var range_bonus := 0.0
var frag := 0
var _src                        # the stats this bullet was made from (for bomblets)
var _travel := 0.0
var _stuck := false
var _stuck_to = null
var _stuck_off := Vector3.ZERO
var radius := 0.07
var life := 4.0
var age := 0.0
var can_hit_owner := false
var color := Color.WHITE
var _ignore: Array = []        # RIDs of players already pierced
var _smoke_t := 0.0
var _direct = null             # player hit directly (skipped by our own explosion)
var _core: MeshInstance3D
var _trail: MeshInstance3D
var _model: Node3D             # thrown / shot model (arrow, knife, bomb)
var _spin := 0.0
var projectile := ""


## `damage_mult` carries per-shot bonuses (last round, rampage).
func setup(p, dir: Vector3, damage_mult := 1.0) -> void:
	setup_stats(p, p.stats, dir, damage_mult)


## Same, with a stats object other than the shooter's own (vehicle weapons).
## `ignore` = RIDs this bullet never hits (the vehicle that fired it).
func setup_stats(p, s, dir: Vector3, damage_mult := 1.0, ignore: Array = []) -> void:
	shooter = p
	game = p.game
	_ignore = ignore.duplicate()
	vel = dir * s.bullet_speed
	damage = s.damage * damage_mult
	gravity = s.bullet_gravity
	bounces = s.bounces
	bounce_bonus = s.bounce_bonus
	pierce = s.pierce
	explosive = s.explosive
	fuse = s.fuse
	smoke = s.smoke
	flame = s.flame
	homing = s.homing
	poison = s.poison
	frost = s.frost
	knockback = s.knockback
	giant_slayer = s.giant_slayer
	chain = s.chain
	cluster = s.cluster
	vortex = s.vortex
	sticky = s.sticky
	range_bonus = s.range_bonus
	frag = s.frag
	_src = s
	radius = 0.07 * s.bullet_size
	life = s.fuse if s.fuse > 0.0 else s.bullet_life
	color = p.color
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 1.0
		_mesh.height = 2.0
		_mesh.radial_segments = 10
		_mesh.rings = 5
		_cone = CylinderMesh.new()
		_cone.top_radius = 0.0
		_cone.bottom_radius = 1.0
		_cone.height = 1.0
		_cone.radial_segments = 6
		_cone.rings = 1
		_flame_mat = StandardMaterial3D.new()
		_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flame_mat.albedo_color = Color(1.4, 0.5, 0.1, 0.22)
	_core = MeshInstance3D.new()
	_core.mesh = _mesh
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	if flame:
		_core.material_override = _flame_mat
		_core.scale = Vector3.ONE * radius
		return
	projectile = s.projectile
	if PROJECTILES.has(projectile):
		# A real arrow / knife / bomb instead of the glowing bullet.
		var spec: Array = PROJECTILES[projectile]
		var b: AABB = Models.bounds(spec[0])
		var k: float = float(spec[1]) / b.size.y * clampf(s.bullet_size / 1.5, 0.8, 2.0)
		_model = Node3D.new()
		add_child(_model)
		var inner: Node3D = Models.scene(spec[0]).instantiate()
		inner.scale = Vector3.ONE * k
		inner.position = -b.get_center() * k
		var turn := Node3D.new()
		turn.rotation.x = -PI * 0.5
		turn.add_child(inner)
		_model.add_child(turn)
		for mi in Models.mesh_instances(inner):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spin = spec[2]
		_core.visible = false
	_core.material_override = p.bullet_material
	# Fast bullets are streaks; slow, fat ones (rockets, grenades, bubbles) are round.
	var speed: float = s.bullet_speed
	var stretch := clampf(speed / 14.0, 1.0, 5.0)
	_core.scale = Vector3(radius, radius, radius * stretch)
	if speed > 28.0:
		var length := clampf(speed * 0.04, 0.5, 5.0)
		_trail = MeshInstance3D.new()
		_trail.mesh = _cone
		_trail.material_override = p.trail_material
		_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trail.rotation.x = PI / 2
		_trail.position.z = length * 0.5
		_trail.scale = Vector3(radius * 0.85, length, radius * 0.85)
		add_child(_trail)


func orient() -> void:
	if vel.length_squared() > 0.01:
		var up := Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.RIGHT
		look_at(global_position + vel, up)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(shooter):
		queue_free()
		return
	life -= delta
	age += delta
	if life <= 0.0:
		if fuse > 0.0:
			_impact(global_position, null)
		else:
			queue_free()
		return

	if _stuck:
		# Sticky bomb waiting for its fuse (handled above via life / fuse).
		if _stuck_to != null and is_instance_valid(_stuck_to) and _stuck_to.alive:
			global_position = _stuck_to.global_position + _stuck_off
		return
	if flame:
		_core.scale = Vector3.ONE * radius * (0.6 + age * 5.0)
	if homing > 0.0:
		_steer(delta)
	if vortex > 0.0:
		# Drag enemies towards the orb.
		for d in game.hostiles(shooter):
			var to_me: Vector3 = global_position - d.chest_position()
			var dist := to_me.length()
			if dist < 8.0 and dist > 0.6 and not d.has_method("seat_count"):
				d.velocity += to_me / dist * vortex * (1.0 - dist / 8.0) * delta * 3.0
		_core.rotation.z += delta * 9.0
	if _model != null and _spin != 0.0:
		_model.rotation.x += _spin * delta
	_travel += vel.length() * delta
	vel.y -= gravity * delta
	if smoke:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.035
			Fx.puff(game.world, global_position, Color(0.9, 0.9, 1.0, 0.45), 1, radius * 3.5)

	var from := global_position
	var to := from + vel * delta
	# A guard catches anything that passes close to the blocker, not only
	# direct hits: bullets, rockets, grenades, bubbles and flames all bounce.
	for b in game.damageables():
		if b == shooter or not b.alive or not b.is_blocking():
			continue
		var c: Vector3 = b.chest_position()
		if Geometry3D.get_closest_point_to_segment(c, from, to).distance_to(c) < BLOCK_RADIUS + radius:
			_reflect(b)
			return
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK | PLAYER_MASK | PROP_MASK | DOOR_MASK)
	var exclude: Array = _ignore.duplicate()
	if not can_hit_owner:
		exclude.append(shooter.get_rid())
	q.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	# Props get knocked about (and stop ordinary bullets); glass shatters and
	# the bullet flies on.
	if hit and hit.collider.has_method("knock"):
		var prop = hit.collider
		if prop.has_method("hurt"):
			prop.hurt(damage, shooter)
		prop.knock(vel.normalized() * clampf(damage * 0.35, 2.0, 40.0), hit.position)
		if prop.is_glass or flame or (pierce > 0 and not prop.has_method("swing_open")):
			_ignore.append(prop.get_rid())
			global_position = hit.position
			return
		if explosive <= 0.0 and bounces <= 0 and fuse <= 0.0:
			_impact(hit.position, hit.normal)
			return
	var end: Vector3 = hit.position if hit else to

	# Fat bullets get a swept-sphere test against player chests.
	var victim = hit.collider if (hit and hit.collider.has_method("take_damage")) else null
	if victim == null and radius > 0.12:
		for p in game.damageables():
			if not p.alive or (p == shooter and not can_hit_owner) or _ignore.has(p.get_rid()):
				continue
			var c: Vector3 = p.chest_position()
			var closest := Geometry3D.get_closest_point_to_segment(c, from, end)
			if closest.distance_to(c) < radius + (p.hit_radius() if p.has_method("hit_radius") else 0.5):
				victim = p
				end = closest
				break

	if victim != null:
		if victim.is_blocking():
			_reflect(victim)
			return
		if sticky and victim != shooter:
			_stick(end, victim)
			return
		if _hit_player(victim, end):
			return
		# Pierced: carry on along the same path this tick.
		global_position = to
		return
	if hit:
		# Crumbling walls and other breakable world pieces.
		if hit.collider.has_method("hurt"):
			hit.collider.hurt(damage, shooter)
		if sticky:
			_stick(hit.position + hit.normal * 0.08, null)
			return
		if bounces > 0 or fuse > 0.0:
			if fuse <= 0.0:
				bounces -= 1
				damage *= 1.0 + bounce_bonus
			can_hit_owner = true
			vel = vel.bounce(hit.normal) * (0.55 if fuse > 0.0 else 0.92)
			global_position = hit.position + hit.normal * (radius + 0.03)
			orient()
			Fx.sparks(game.world, hit.position, color.lerp(Color.WHITE, 0.4), 4, 4.0, hit.normal)
			Sfx.play_at("bounce", global_position, -10.0, 0.7 if fuse > 0.0 else 1.0)
			return
		_impact(hit.position + hit.normal * 0.05, hit.normal)
		return
	global_position = to
	orient()


## A blocking player bats the bullet back at whoever fired it.
func _reflect(p) -> void:
	var old = shooter
	p._blocked(old)
	var speed := vel.length() * 1.15
	var dir := -vel.normalized()
	if is_instance_valid(old) and old.alive and old.has_method("chest_position"):
		dir = (old.chest_position() - p.chest_position()).normalized()
	if flame:
		age = 0.0
		speed = minf(speed, 22.0)
	shooter = p
	color = p.color
	vel = dir * speed
	can_hit_owner = false
	_ignore.clear()
	life = maxf(life, 1.5)
	if not flame:
		_core.material_override = p.bullet_material
	if _trail != null:
		_trail.material_override = p.trail_material
	global_position = p.chest_position() + dir * (BLOCK_RADIUS + radius + 0.1)
	orient()
	reset_physics_interpolation()


func _steer(delta: float) -> void:
	var best = null
	var best_score := 0.5   # require the target to be roughly ahead
	var dir := vel.normalized()
	for p in game.damageables():
		if not p.alive or p == shooter or not game.is_enemy(shooter, p):
			continue
		var to_p: Vector3 = p.chest_position() - global_position
		var d := to_p.length()
		if d > 30.0 or d < 0.1:
			continue
		var score := dir.dot(to_p / d) - d * 0.004
		if score > best_score:
			best_score = score
			best = p
	if best != null:
		var want: Vector3 = (best.chest_position() - global_position).normalized()
		var speed := vel.length()
		vel = dir.slerp(want, clampf(homing * delta, 0.0, 1.0)).normalized() * speed


## Returns true when the bullet is spent, false when it pierced and flies on.
func _hit_player(p, pos: Vector3) -> bool:
	var dmg := damage
	# The head is the big sphere above the shoulders (see character.gd).
	var headshot: bool = pos.y - p.global_position.y > (p.head_height() if p.has_method("head_height") else 1.12)
	if headshot:
		dmg *= 1.5
	if giant_slayer > 0.0 and p == game.leader() and p.kills > 0:
		dmg *= 1.0 + giant_slayer
	if range_bonus > 0.0:
		dmg *= 1.0 + range_bonus * clampf(_travel / 40.0, 0.0, 1.0)
	var dealt: float = p.take_damage(dmg, shooter, false, headshot)
	if chain > 0 and dealt > 0.0:
		_chain_from(p, dmg * 0.5)
	if dealt > 0.0 and p.alive:
		if poison > 0.0:
			p.apply_poison(dealt * poison, shooter)
		if frost > 0.0:
			p.apply_slow(frost)
		if knockback > 0.0:
			var push := vel.normalized()
			push.y = 0.35
			p.velocity += push * knockback
	if pierce > 0 and explosive <= 0.0:
		pierce -= 1
		_ignore.append(p.get_rid())
		Fx.sparks(game.world, pos, color.lerp(Color.WHITE, 0.4), 6, 6.0, -vel.normalized())
		return false
	_direct = p
	_impact(pos, -vel.normalized())
	return true


## `normal` is the surface normal (or the direction sparks should fly), or null.
func _impact(pos: Vector3, normal) -> void:
	if cluster > 0:
		# Bomblets scatter up and outwards, then explode on their own.
		for i in cluster:
			var a := TAU * i / cluster + randf() * 0.5
			_spawn_child(pos + Vector3(0, 0.3, 0), Vector3(cos(a) * 5.0, randf_range(6.0, 9.0), sin(a) * 5.0), 0.6, {"explosive": explosive * 0.75, "gravity": 18.0, "fuse": randf_range(0.7, 1.1), "radius": radius * 0.6})
	elif frag > 0 and normal is Vector3 and _direct == null:
		for i in frag:
			var dir: Vector3 = ((normal as Vector3) + Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)) * 0.9).normalized()
			_spawn_child(pos + (normal as Vector3) * 0.1, dir * maxf(vel.length() * 0.6, 25.0), 0.4, {"life": 0.45, "explosive": 0.0, "radius": radius * 0.7})
	if explosive > 0.0:
		game.explode(pos, explosive, damage * 0.8, shooter, _direct)
	elif not flame:
		if _model != null and _direct == null and normal is Vector3 and _spin > -10.0 and projectile != "bomb":
			# Arrows and bolts stay stuck in what they hit for a while.
			var stuck := _model
			var xf := stuck.global_transform
			remove_child(stuck)
			game.world.add_child(stuck)
			stuck.global_transform = xf
			stuck.global_position = pos - vel.normalized() * 0.2
			stuck.reset_physics_interpolation()
			var tw := stuck.create_tween()
			tw.tween_interval(6.0)
			tw.tween_callback(stuck.queue_free)
			_model = null
		var n: Vector3 = normal if normal is Vector3 else Vector3.UP
		Fx.flash(game.world, pos, Color(color.lerp(Color.WHITE, 0.5), 0.9), radius * 1.5, radius * 4.0 + 0.14, 0.1)
		Fx.sparks(game.world, pos, color.lerp(Color.WHITE, 0.4), 7, 7.0, n)
	queue_free()


## Sticky bomb: stop here (or ride along on `victim`) and blow up in a second.
func _stick(pos: Vector3, victim) -> void:
	_stuck = true
	_stuck_to = victim
	global_position = pos
	if victim != null:
		_stuck_off = pos - victim.global_position
		_direct = null
	vel = Vector3.ZERO
	fuse = 1.0
	life = 1.0
	if _trail != null:
		_trail.visible = false
	Sfx.play_at("tick", pos, -4.0, 0.7)
	create_tween().set_loops(5).tween_property(_core, "scale", _core.scale * 1.5, 0.1).set_trans(Tween.TRANS_SINE)


## A secondary projectile (bomblet / fragment) flying off with `velocity`.
func _spawn_child(pos: Vector3, velocity: Vector3, dmg_mult: float, over: Dictionary) -> void:
	if not is_instance_valid(shooter):
		return
	var b = get_script().new()
	b.setup_stats(shooter, _src, velocity.normalized(), 1.0, _ignore)
	b.vel = velocity
	b.damage = damage * dmg_mult
	b.cluster = 0
	b.frag = 0
	b.chain = 0
	b.vortex = 0.0
	b.sticky = false
	b.bounces = 0
	b.homing = 0.0
	b.can_hit_owner = false
	for k in over:
		b.set(k, over[k])
	if over.has("fuse"):
		b.life = over.fuse
	game.world.add_child(b)
	b.global_position = pos
	b.orient()
	b.reset_physics_interpolation()


## Lightning arcs from `from_target` to nearby enemies of the shooter.
func _chain_from(from_target, dmg: float) -> void:
	var left := chain
	var src: Vector3 = from_target.chest_position()
	for d in game.hostiles(shooter):
		if left <= 0:
			break
		if d == from_target or not d.alive:
			continue
		var p: Vector3 = d.chest_position()
		if p.distance_to(src) > 9.0:
			continue
		left -= 1
		d.take_damage(dmg, shooter, false, false)
		_bolt(src, p)
	if left < chain:
		Sfx.play_at("zap", src, -5.0)


func _bolt(a: Vector3, b: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.lerp(Color(0.7, 0.9, 1.0), 0.6) * 2.0, 1.0)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.04
	mesh.height = 1.0
	mesh.radial_segments = 5
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y * d.length(), x.cross(y)), (a + b) * 0.5)
	game.world.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(mi.queue_free)
	Fx.sparks(game.world, b, Color(0.7, 0.9, 1.0), 6, 5.0, Vector3.UP, 180.0, 0.3)
