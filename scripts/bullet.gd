extends Node3D
## A projectile. Not a physics body: each tick it ray-casts along the segment
## it is about to travel (cheap, and never tunnels). All behaviour comes from
## a snapshot of the shooter's stats taken when it was fired.

const Fx = preload("res://scripts/fx.gd")

const WORLD_MASK := 1
const PLAYER_MASK := 2

static var _mesh: SphereMesh

var shooter
var game
var vel := Vector3.ZERO
var damage := 10.0
var gravity := 0.0
var bounces := 0
var explosive := 0.0
var homing := 0.0
var poison := 0.0
var frost := 0.0
var knockback := 0.0
var radius := 0.07
var life := 4.0
var can_hit_owner := false
var color := Color.WHITE


func setup(p, _origin: Vector3, dir: Vector3) -> void:
	shooter = p
	game = p.game
	var s = p.stats
	vel = dir * s.bullet_speed
	damage = s.damage
	gravity = s.bullet_gravity
	bounces = s.bounces
	explosive = s.explosive
	homing = s.homing
	poison = s.poison
	frost = s.frost
	knockback = s.knockback
	radius = 0.07 * s.bullet_size
	color = p.color
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 1.0
		_mesh.height = 2.0
		_mesh.radial_segments = 8
		_mesh.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = p.bullet_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(radius, radius, radius * 7.0)
	add_child(mi)


func orient() -> void:
	if vel.length_squared() > 0.01:
		var up := Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.RIGHT
		look_at(global_position + vel, up)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if not is_instance_valid(shooter):
		queue_free()
		return

	if homing > 0.0:
		_steer(delta)
	vel.y -= gravity * delta

	var from := global_position
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK | PLAYER_MASK)
	if not can_hit_owner:
		q.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit.position if hit else to

	# Fat bullets get a swept-sphere test against player chests.
	var victim = hit.collider if (hit and hit.collider.has_method("take_damage")) else null
	if victim == null and radius > 0.12:
		for p in game.players:
			if not p.alive or (p == shooter and not can_hit_owner):
				continue
			var c: Vector3 = p.chest_position()
			var closest := Geometry3D.get_closest_point_to_segment(c, from, end)
			if closest.distance_to(c) < radius + 0.5:
				victim = p
				end = closest
				break

	if victim != null:
		_hit_player(victim, end)
		return
	if hit:
		if bounces > 0:
			bounces -= 1
			can_hit_owner = true
			vel = vel.bounce(hit.normal) * 0.92
			global_position = hit.position + hit.normal * 0.03
			orient()
			Sfx.play_at("bounce", global_position, -10.0)
			return
		_impact(hit.position + hit.normal * 0.05, null)
		return
	global_position = to
	orient()


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


func _hit_player(p, pos: Vector3) -> void:
	var dmg := damage
	# The head is the big sphere above the shoulders (see character.gd).
	var headshot: bool = pos.y - p.global_position.y > 1.12
	if headshot:
		dmg *= 1.5
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
	_impact(pos, p)


func _impact(pos: Vector3, direct_victim) -> void:
	if explosive > 0.0:
		game.explode(pos, explosive, damage * 0.8, shooter, direct_victim)
	else:
		Fx.flash(game.world, pos, Color(color.lerp(Color.WHITE, 0.5), 0.9), radius * 1.5, radius * 4.0 + 0.12, 0.12)
		Fx.burst(game.world, pos, color.lerp(Color.WHITE, 0.4), 6, 5.0, 0.16, 0.3, -9.0)
	queue_free()
