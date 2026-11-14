extends CharacterBody3D
## One combatant (human or bot).
##
## The player never reads devices itself: it asks its `brain` (input_source.gd
## for humans, bot_brain.gd for bots) for move/fire/jump/etc. each physics tick.
## View angles (yaw/pitch) are plain floats so they can be updated every
## rendered frame, independent of the physics rate; game.gd builds the camera
## transform from them.
##
## Life cycle:  spawn() -> alive -> _die() -> card pick (HUD draws it, input is
## handled here in _dead_tick) -> game.respawn() -> spawn() ...

const Stats = preload("res://scripts/stats.gd")
const Cards = preload("res://scripts/cards.gd")
const Bullet = preload("res://scripts/bullet.gd")
const Fx = preload("res://scripts/fx.gd")

const EYE_HEIGHT := 1.6
const GRAVITY := 22.0
const WORLD_MASK := 1
const PLAYER_MASK := 2

# Identity (set by game.gd before add_child)
var index := 0
var pname := "P1"
var color := Color.WHITE
var brain
var is_bot := false
var game

# State
var stats = Stats.new()
var cards: Array = []            # names of every card picked so far
var health := 100.0
var alive := false
var kills := 0
var deaths := 0
var yaw := 0.0
var pitch := 0.0
var ammo := 8
var reload_left := 0.0
var fire_cd := 0.0
var dash_cd := 0.0
var dash_left := 0.0
var dash_dir := Vector3.ZERO
var air_jumps := 0
var spawn_protect := 0.0
var since_damage := 99.0
var poison_left := 0.0
var poison_dps := 0.0
var poison_src = null
var slow_left := 0.0
var slow_amount := 0.0

# Card selection while dead
var card_choices: Array = []
var card_sel := 1
var dead_time := 0.0
var killer_name := ""
var respawn_pending := false

# HUD feedback values (decay over time, read by hud.gd)
var hit_marker := 0.0
var hurt_flash := 0.0
var recoil := 0.0
var kill_flash := 0.0

var body_root: Node3D
var head_pivot: Node3D
var name_label: Label3D
var bullet_material: StandardMaterial3D
var _shape: CollisionShape3D


func body_layer_bit() -> int:
	return 1 << (index + 1)


func viewmodel_layer_bit() -> int:
	return 1 << (index + 8)


func _ready() -> void:
	collision_layer = 0
	collision_mask = WORLD_MASK | PLAYER_MASK
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.3

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	_shape = CollisionShape3D.new()
	_shape.shape = capsule
	_shape.position.y = 0.9
	add_child(_shape)

	bullet_material = StandardMaterial3D.new()
	bullet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bullet_material.albedo_color = color.lerp(Color.WHITE, 0.45)

	_build_body()
	_set_alive_visuals(false)


## Third-person model, built from primitives. Lives on this player's private
## visual layer so the owner's camera can cull it.
func _build_body() -> void:
	body_root = Node3D.new()
	add_child(body_root)
	var layer := body_layer_bit()

	var suit := StandardMaterial3D.new()
	suit.albedo_color = color
	suit.roughness = 0.8
	suit.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	suit.rim_enabled = true
	suit.rim = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = color.darkened(0.55)
	dark.roughness = 0.6
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.93, 0.76, 0.6)
	skin.roughness = 0.9
	skin.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.2, 0.2, 0.23)
	metal.roughness = 0.45
	metal.metallic = 0.5

	var torso := CapsuleMesh.new()
	torso.radius = 0.36
	torso.height = 1.0
	_part(body_root, torso, suit, Vector3(0, 0.95, 0), layer)
	var legs := CylinderMesh.new()
	legs.top_radius = 0.3
	legs.bottom_radius = 0.24
	legs.height = 0.6
	_part(body_root, legs, dark, Vector3(0, 0.3, 0), layer)
	var belt := CylinderMesh.new()
	belt.top_radius = 0.37
	belt.bottom_radius = 0.37
	belt.height = 0.1
	_part(body_root, belt, metal, Vector3(0, 0.62, 0), layer)

	head_pivot = Node3D.new()
	head_pivot.position.y = EYE_HEIGHT
	body_root.add_child(head_pivot)
	var head := SphereMesh.new()
	head.radius = 0.25
	head.height = 0.5
	_part(head_pivot, head, skin, Vector3(0, 0.02, 0), layer)
	var helmet := SphereMesh.new()
	helmet.radius = 0.27
	helmet.height = 0.3
	helmet.is_hemisphere = true
	_part(head_pivot, helmet, suit, Vector3(0, 0.06, 0), layer)
	var visor := BoxMesh.new()
	visor.size = Vector3(0.36, 0.09, 0.14)
	_part(head_pivot, visor, metal, Vector3(0, 0.03, -0.2), layer)
	var gun := BoxMesh.new()
	gun.size = Vector3(0.1, 0.14, 0.7)
	_part(head_pivot, gun, metal, Vector3(0.3, -0.32, -0.42), layer)
	var arm := BoxMesh.new()
	arm.size = Vector3(0.13, 0.13, 0.45)
	_part(head_pivot, arm, suit, Vector3(0.33, -0.36, -0.12), layer)

	name_label = Label3D.new()
	name_label.text = pname
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 64
	name_label.pixel_size = 0.005
	name_label.outline_size = 16
	name_label.modulate = color.lerp(Color.WHITE, 0.3)
	name_label.position.y = 2.2
	name_label.layers = layer
	body_root.add_child(name_label)


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, layer: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.layers = layer
	parent.add_child(mi)
	return mi


func _set_alive_visuals(on: bool) -> void:
	body_root.visible = on
	collision_layer = PLAYER_MASK if on else 0
	_shape.set_deferred("disabled", not on)


func spawn(pos: Vector3, facing_yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = facing_yaw
	pitch = 0.0
	rotation.y = yaw
	health = stats.max_health
	ammo = stats.mag_size
	reload_left = 0.0
	fire_cd = 0.2
	dash_cd = 0.0
	dash_left = 0.0
	poison_left = 0.0
	slow_left = 0.0
	spawn_protect = 1.5
	since_damage = 99.0
	card_choices = []
	respawn_pending = false
	alive = true
	_set_alive_visuals(true)
	reset_physics_interpolation()


func eye_position() -> Vector3:
	return global_position + Vector3(0, EYE_HEIGHT, 0)


func chest_position() -> Vector3:
	return global_position + Vector3(0, 1.0, 0)


func aim_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


func _process(delta: float) -> void:
	hit_marker = maxf(0.0, hit_marker - delta * 4.0)
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.5)
	recoil = maxf(0.0, recoil - delta * 9.0)
	kill_flash = maxf(0.0, kill_flash - delta * 0.7)
	if alive and not game.match_over:
		brain.update_look(self, delta)


func _physics_process(delta: float) -> void:
	if game.match_over:
		return
	brain.update_buttons(self, delta)
	if not alive:
		_dead_tick(delta)
		return

	# --- timers / status effects ---
	fire_cd = maxf(0.0, fire_cd - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	spawn_protect = maxf(0.0, spawn_protect - delta)
	since_damage += delta
	slow_left = maxf(0.0, slow_left - delta)
	if stats.regen > 0.0:
		health = minf(stats.max_health, health + stats.regen * delta)
	elif since_damage > 6.0:
		health = minf(stats.max_health, health + 4.0 * delta)
	if poison_left > 0.0:
		poison_left -= delta
		take_damage(poison_dps * delta, poison_src, true)
		if not alive:
			return

	# --- movement ---
	var input: Vector2 = brain.move
	var wish := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, -input.y)
	var speed: float = stats.move_speed * (1.0 - (slow_amount if slow_left > 0.0 else 0.0))
	var on_floor := is_on_floor()
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	horiz = horiz.move_toward(wish * speed, (70.0 if on_floor else 22.0) * delta)
	if on_floor:
		air_jumps = stats.max_jumps - 1
	else:
		velocity.y -= GRAVITY * delta
	if brain.jump:
		if on_floor:
			velocity.y = stats.jump_velocity
			Sfx.play("jump", -14.0)
		elif air_jumps > 0:
			air_jumps -= 1
			velocity.y = stats.jump_velocity
			Sfx.play("jump", -12.0, 1.3)
	if brain.dash and dash_cd <= 0.0:
		dash_dir = wish.normalized() if wish.length() > 0.1 else Basis(Vector3.UP, yaw) * Vector3.FORWARD
		dash_left = 0.16
		dash_cd = stats.dash_cooldown
		Sfx.play("dash", -8.0)
	if dash_left > 0.0:
		dash_left -= delta
		horiz = dash_dir * maxf(22.0, speed * 2.4)
	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()
	rotation.y = yaw
	head_pivot.rotation.x = pitch

	if global_position.y < -25.0:
		take_damage(99999.0, null, true)
		return

	# --- weapon ---
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			ammo = stats.mag_size
	elif ammo <= 0 or (brain.reload and ammo < stats.mag_size):
		reload_left = stats.reload_time
		Sfx.play("reload", -10.0)
	elif brain.fire and fire_cd <= 0.0:
		_shoot()


func _shoot() -> void:
	ammo -= 1
	fire_cd = stats.fire_interval
	recoil = 1.0
	Sfx.play("shoot", -7.0, clampf(1.15 - stats.damage / 160.0, 0.6, 1.2))

	var eye := eye_position()
	var basis := aim_basis()
	var space := get_world_3d().direct_space_state
	# Converge on whatever the crosshair is pointing at.
	var far := eye - basis.z * 200.0
	var q := PhysicsRayQueryParameters3D.create(eye, far, WORLD_MASK | PLAYER_MASK)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var target: Vector3 = hit.position if hit else far
	var muzzle := eye + basis * Vector3(0.2, -0.16, -0.55)
	var block := PhysicsRayQueryParameters3D.create(eye, muzzle, WORLD_MASK)
	if space.intersect_ray(block) or target.distance_to(eye) < 1.2:
		muzzle = eye

	for i in stats.pellets:
		var s: float = stats.spread + (0.02 if i > 0 else 0.0)
		var dir := (target - muzzle).normalized()
		dir = (dir + basis.x * randf_range(-s, s) + basis.y * randf_range(-s, s)).normalized()
		var b = Bullet.new()
		b.setup(self, muzzle, dir)
		game.world.add_child(b)
		b.global_position = muzzle
		b.orient()
		b.reset_physics_interpolation()


func launch(v: Vector3) -> void:
	velocity = v
	dash_left = 0.0


func heal(amount: float) -> void:
	if alive:
		health = minf(stats.max_health, health + amount)


## Returns the damage actually dealt. `silent` skips hit feedback (poison ticks).
func take_damage(amount: float, attacker, silent := false) -> float:
	if not alive or game.match_over:
		return 0.0
	if spawn_protect > 0.0 and amount < 9999.0:
		return 0.0
	amount *= stats.damage_taken
	health -= amount
	since_damage = 0.0
	if not silent:
		hurt_flash = 1.0
		Sfx.play("hurt", -12.0)
		if not is_bot and brain.device >= 0:
			Input.start_joy_vibration(brain.device, 0.4, 0.7, 0.18)
	if attacker != null and is_instance_valid(attacker) and attacker != self:
		if not silent:
			attacker.hit_marker = 1.0
			Sfx.play("hit", -9.0)
		if attacker.stats.lifesteal > 0.0:
			attacker.heal(amount * attacker.stats.lifesteal)
	if health <= 0.0:
		_die(attacker)
	return amount


func apply_poison(total: float, src) -> void:
	poison_dps = (poison_dps * maxf(poison_left, 0.0) + total) / 3.0
	poison_left = 3.0
	poison_src = src


func apply_slow(amount: float) -> void:
	slow_amount = maxf(amount, slow_amount if slow_left > 0.0 else 0.0)
	slow_left = 2.0


func _die(killer) -> void:
	alive = false
	deaths += 1
	health = 0.0
	_set_alive_visuals(false)
	velocity = Vector3.ZERO
	killer_name = killer.pname if (killer != null and is_instance_valid(killer) and killer != self) else ""
	card_choices = Cards.draw(3)
	card_sel = 1
	dead_time = 0.0
	respawn_pending = false
	Sfx.play("death", -6.0)
	Fx.flash(game.world, chest_position(), Color(color, 0.8), 0.3, 1.6, 0.45)
	game.on_player_died(self, killer)


## While dead: choose one of the offered cards, then respawn.
func _dead_tick(delta: float) -> void:
	if respawn_pending or card_choices.is_empty():
		return
	dead_time += delta
	if is_bot:
		if dead_time > 1.6:
			_pick_card(randi() % card_choices.size())
		return
	if dead_time < 0.6:
		return
	if brain.ui_left:
		card_sel = maxi(0, card_sel - 1)
		Sfx.play("tick", -8.0)
	if brain.ui_right:
		card_sel = mini(card_choices.size() - 1, card_sel + 1)
		Sfx.play("tick", -8.0)
	if brain.ui_accept:
		_pick_card(card_sel)


func _pick_card(i: int) -> void:
	var card: Dictionary = card_choices[i]
	card.apply.call(stats)
	cards.append(card.name)
	card_sel = i
	respawn_pending = true
	if not is_bot:
		Sfx.play("card", -6.0)
	game.respawn_later(self, 0.45)
