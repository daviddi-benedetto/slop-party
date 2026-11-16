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

static var _mesh: SphereMesh
static var _cone: CylinderMesh
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


## `damage_mult` carries per-shot bonuses (last round, rampage).
func setup(p, dir: Vector3, damage_mult := 1.0) -> void:
	shooter = p
	game = p.game
	var s = p.stats
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

	if flame:
		_core.scale = Vector3.ONE * radius * (0.6 + age * 5.0)
	if homing > 0.0:
		_steer(delta)
	vel.y -= gravity * delta
	if smoke:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.035
			Fx.puff(game.world, global_position, Color(0.9, 0.9, 1.0, 0.45), 1, radius * 3.5)

	var from := global_position
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK | PLAYER_MASK)
	var exclude: Array = _ignore.duplicate()
	if not can_hit_owner:
		exclude.append(shooter.get_rid())
	q.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit.position if hit else to

	# Fat bullets get a swept-sphere test against player chests.
	var victim = hit.collider if (hit and hit.collider.has_method("take_damage")) else null
	if victim == null and radius > 0.12:
		for p in game.players:
			if not p.alive or (p == shooter and not can_hit_owner) or _ignore.has(p.get_rid()):
				continue
			var c: Vector3 = p.chest_position()
			var closest := Geometry3D.get_closest_point_to_segment(c, from, end)
			if closest.distance_to(c) < radius + 0.5:
				victim = p
				end = closest
				break

	if victim != null:
		if victim.is_blocking() and not flame:
			_reflect(victim)
			return
		if _hit_player(victim, end):
			return
		# Pierced: carry on along the same path this tick.
		global_position = to
		return
	if hit:
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
	if is_instance_valid(old) and old.alive:
		dir = (old.chest_position() - p.chest_position()).normalized()
	shooter = p
	color = p.color
	vel = dir * speed
	can_hit_owner = false
	_ignore.clear()
	life = maxf(life, 1.5)
	_core.material_override = p.bullet_material
	if _trail != null:
		_trail.material_override = p.trail_material
	global_position = p.chest_position() + dir * 0.9
	orient()
	reset_physics_interpolation()


func _steer(delta: float) -> void:
	var best = null
	var best_score := 0.5   # require the target to be roughly ahead
	var dir := vel.normalized()
	for p in game.players:
		if not p.alive or p == shooter:
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
	var headshot: bool = pos.y - p.global_position.y > 1.12
	if headshot:
		dmg *= 1.5
	if giant_slayer > 0.0 and p == game.leader() and p.kills > 0:
		dmg *= 1.0 + giant_slayer
	var dealt: float = p.take_damage(dmg, shooter, false, headshot)
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
	if explosive > 0.0:
		game.explode(pos, explosive, damage * 0.8, shooter, _direct)
	elif not flame:
		var n: Vector3 = normal if normal is Vector3 else Vector3.UP
		Fx.flash(game.world, pos, Color(color.lerp(Color.WHITE, 0.5), 0.9), radius * 1.5, radius * 4.0 + 0.14, 0.1)
		Fx.sparks(game.world, pos, color.lerp(Color.WHITE, 0.4), 7, 7.0, n)
	queue_free()
