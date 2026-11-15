extends CharacterBody3D
## One combatant (human or bot).
##
## The player never reads devices itself: it asks its `brain` (input_source.gd
## for humans, bot_brain.gd for bots) for move/fire/jump/etc. each physics tick.
## View angles (yaw/pitch) are plain floats so they can be updated every
## rendered frame, independent of the physics rate; game.gd builds the camera
## transform from them.
##
## Visuals are a character.gd model (animated from _physics_process), a name
## tag and a small health bar, all on this player's private visual layer so the
## owner's own camera does not see them.
##
## Life cycle:  spawn() -> alive -> _die() -> card pick (HUD draws it, input is
## handled here in _dead_tick) -> game.respawn() -> spawn() ...
## Nothing moves while game.frozen is true (countdown, match over).

const Stats = preload("res://scripts/stats.gd")
const Cards = preload("res://scripts/cards.gd")
const Bullet = preload("res://scripts/bullet.gd")
const Fx = preload("res://scripts/fx.gd")
const Character = preload("res://scripts/character.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Weapons = preload("res://scripts/weapons.gd")

const EYE_HEIGHT := 1.6
const GRAVITY := 22.0
const WORLD_MASK := 1
const PLAYER_MASK := 2

const BAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
instance uniform float fill = 1.0;
instance uniform vec4 tint : source_color = vec4(0.3, 0.9, 0.4, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec2 uv = UV;
	float inside = step(0.035, uv.x) * step(uv.x, 0.965) * step(0.2, uv.y) * step(uv.y, 0.8);
	float f = (uv.x - 0.035) / 0.93;
	vec3 bar = f < fill ? tint.rgb * (uv.y < 0.45 ? 1.25 : 1.0) : vec3(0.3, 0.26, 0.38);
	ALBEDO = mix(vec3(0.17, 0.12, 0.24), bar, inside);
}
"""

static var _bar_material: ShaderMaterial

# Identity (set by game.gd before add_child)
var index := 0
var pname := "P1"
var color := Color.WHITE
var kind := 0
var brain
var is_bot := false
var has_view := false      # true when a splitscreen cell follows this player
var game

# State
var stats = Stats.new()
var weapon := 0                  # index into weapons.gd LIST
var picked: Array = []           # stat cards picked so far (card dictionaries)
var cards: Array = []            # names of every card picked so far (incl. weapons)
var card_icons: Array = []       # [icon, rarity] per picked card, for the HUD
var health := 100.0
var health_ghost := 100.0        # trails behind health for the HUD bar
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
var shield_timer := 0.0           # > 0 while the bubble shield recharges
var second_wind_left := 0
var kills_life := 0
var notice := ""                 # short HUD message ("GOT SCATTER!")
var notice_t := 0.0

# Card selection while dead
var card_choices: Array = []
var card_sel := 1
var dead_time := 0.0
var killer = null
var respawn_pending := false
var pick_time := 0.0             # seconds since the card was confirmed

# Feedback values read by hud.gd / game.gd (all decay over time)
var hit_marker := 0.0
var hit_crit := false
var hurt_flash := 0.0
var recoil := 0.0
var kill_flash := 0.0
var kill_name := ""
var shake := 0.0
var fov_kick := 0.0
var land_dip := 0.0
var muzzle_flash := 0.0
var damage_dirs: Array = []      # [[world_pos, time_left], ...]
var spawn_time := 0.0

var character
var name_label: Label3D
var health_bar: MeshInstance3D
var bullet_material: StandardMaterial3D
var _shape: CollisionShape3D
var _was_floor := true
var _fall_speed := 0.0
var _step_dist := 0.0
var _shield_mesh: MeshInstance3D


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

	# Bullets glow in the owner's colour (emission > 1 feeds the bloom).
	bullet_material = StandardMaterial3D.new()
	bullet_material.albedo_color = Color.BLACK
	bullet_material.emission_enabled = true
	bullet_material.emission = color.lerp(Color.WHITE, 0.35)
	bullet_material.emission_energy_multiplier = 3.2

	character = Character.new()
	add_child(character)
	character.build(kind, color, body_layer_bit())

	name_label = Label3D.new()
	name_label.text = pname
	name_label.font = UiKit.font(700)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 56
	name_label.pixel_size = 0.0042
	name_label.outline_size = 16
	name_label.outline_modulate = UiKit.INK
	name_label.modulate = color.lerp(Color.WHITE, 0.45)
	name_label.position.y = 2.52
	name_label.layers = body_layer_bit()
	add_child(name_label)

	if _bar_material == null:
		var sh := Shader.new()
		sh.code = BAR_SHADER
		_bar_material = ShaderMaterial.new()
		_bar_material.shader = sh
	var quad := QuadMesh.new()
	quad.size = Vector2(0.95, 0.15)
	health_bar = MeshInstance3D.new()
	health_bar.mesh = quad
	health_bar.material_override = _bar_material
	health_bar.position.y = 2.24
	health_bar.layers = body_layer_bit()
	health_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(health_bar)

	# Bubble shield (only shown when a card grants one and it is charged).
	var bubble := SphereMesh.new()
	bubble.radius = 1.2
	bubble.height = 2.4
	var bmat := StandardMaterial3D.new()
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(0.5, 0.9, 1.0, 0.16)
	bmat.rim_enabled = true
	bmat.rim = 1.0
	bmat.roughness = 0.1
	bmat.emission_enabled = true
	bmat.emission = Color(0.4, 0.8, 1.0)
	bmat.emission_energy_multiplier = 0.35
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_mesh = MeshInstance3D.new()
	_shield_mesh.mesh = bubble
	_shield_mesh.material_override = bmat
	_shield_mesh.position.y = 0.95
	_shield_mesh.layers = body_layer_bit()
	_shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield_mesh.visible = false
	add_child(_shield_mesh)

	_set_alive_visuals(false)


## Defaults -> weapon -> every picked card. Call after anything that changes
## the weapon or the card list.
func rebuild_stats() -> void:
	var s = Stats.new()
	Weapons.apply(weapon, s)
	for card in picked:
		card.apply.call(s)
	stats = s
	ammo = mini(ammo, stats.mag_size)
	character.set_weapon(weapon)


func weapon_name() -> String:
	return Weapons.LIST[weapon].name


## Swap weapon mid-life (pickup pads). Cards are kept.
func pick_weapon(id: int) -> void:
	weapon = id
	rebuild_stats()
	ammo = stats.mag_size
	reload_left = 0.0
	fire_cd = 0.25
	say("GOT %s!" % weapon_name().to_upper())


func say(text: String) -> void:
	notice = text
	notice_t = 1.6


func shield_ready() -> bool:
	return stats.shield_cd > 0.0 and shield_timer <= 0.0


## Called by game.gd for every credited KO.
func on_kill() -> void:
	kills_life += 1
	if stats.kill_heal > 0.0:
		heal(stats.kill_heal)
	if stats.kill_reload and alive:
		ammo = stats.mag_size
		reload_left = 0.0


func _set_alive_visuals(on: bool) -> void:
	character.visible = on
	if not on:
		_shield_mesh.visible = false
	name_label.visible = on
	health_bar.visible = on
	collision_layer = PLAYER_MASK if on else 0
	_shape.set_deferred("disabled", not on)


func spawn(pos: Vector3, facing_yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = facing_yaw
	pitch = 0.0
	rotation.y = yaw
	health = stats.max_health
	health_ghost = health
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
	damage_dirs.clear()
	respawn_pending = false
	shield_timer = 0.0
	second_wind_left = stats.second_wind
	kills_life = 0
	alive = true
	spawn_time = 0.0
	_was_floor = true
	_set_alive_visuals(true)
	character.pop_in()
	reset_physics_interpolation()
	Fx.ring(game.world, pos + Vector3(0, 0.1, 0), Color(color.lerp(Color.WHITE, 0.4), 0.9), 0.3, 1.8, 0.5)


func eye_position() -> Vector3:
	return global_position + Vector3(0, EYE_HEIGHT, 0)


func chest_position() -> Vector3:
	return global_position + Vector3(0, 1.0, 0)


func aim_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


func _process(delta: float) -> void:
	hit_marker = maxf(0.0, hit_marker - delta * 3.5)
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.2)
	recoil = maxf(0.0, recoil - delta * 9.0)
	kill_flash = maxf(0.0, kill_flash - delta * 0.55)
	shake = maxf(0.0, shake - delta * 2.8)
	fov_kick = maxf(0.0, fov_kick - delta * 3.5)
	land_dip = maxf(0.0, land_dip - delta * 5.0)
	muzzle_flash = maxf(0.0, muzzle_flash - delta * 16.0)
	notice_t = maxf(0.0, notice_t - delta)
	spawn_time += delta
	if health_ghost > health:
		health_ghost = maxf(health, health_ghost - delta * stats.max_health * 0.7)
	else:
		health_ghost = health
	for d in damage_dirs:
		d[1] -= delta
	damage_dirs = damage_dirs.filter(func(d): return d[1] > 0.0)
	if respawn_pending:
		pick_time += delta
	if alive and not game.match_over:
		brain.update_look(self, delta)


func _physics_process(delta: float) -> void:
	if game.frozen:
		if alive:
			character.animate(delta, 0.0, true, 0.0, pitch)
			rotation.y = yaw
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
	shield_timer = maxf(0.0, shield_timer - delta)
	_shield_mesh.visible = shield_ready()
	var rush: float = stats.adrenaline if health < stats.max_health * 0.4 else 0.0
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
	var speed: float = stats.move_speed * (1.0 + rush) * (1.0 - (slow_amount if slow_left > 0.0 else 0.0))
	var on_floor := is_on_floor()
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	horiz = horiz.move_toward(wish * speed, (70.0 if on_floor else 22.0) * delta)
	if on_floor:
		air_jumps = stats.max_jumps - 1
		if not _was_floor and _fall_speed > 6.0:
			land_dip = clampf(_fall_speed / 16.0, 0.3, 1.0)
			Fx.puff(game.world, global_position + Vector3(0, 0.1, 0), Color(1, 1, 1, 0.6), 6, 0.45)
			Sfx.play_at("land", global_position, -12.0)
	else:
		velocity.y -= GRAVITY * stats.gravity_mult * delta
		_fall_speed = -velocity.y
	_was_floor = on_floor
	if brain.jump:
		if on_floor:
			velocity.y = stats.jump_velocity
			Sfx.play_at("jump", global_position, -12.0)
		elif air_jumps > 0:
			air_jumps -= 1
			velocity.y = stats.jump_velocity
			Sfx.play_at("jump", global_position, -10.0, 1.3)
			Fx.ring(game.world, global_position, Color(1, 1, 1, 0.8), 0.2, 0.9, 0.3)
	if brain.dash and dash_cd <= 0.0:
		dash_dir = wish.normalized() if wish.length() > 0.1 else Basis(Vector3.UP, yaw) * Vector3.FORWARD
		dash_left = 0.16
		dash_cd = stats.dash_cooldown
		fov_kick = 1.0
		Sfx.play_at("dash", global_position, -6.0)
		Fx.puff(game.world, global_position + Vector3(0, 0.4, 0) - dash_dir * 0.9, Color(1, 1, 1, 0.6), 8, 0.4)
	if dash_left > 0.0:
		dash_left -= delta
		horiz = dash_dir * maxf(22.0, speed * 2.4)
	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()
	rotation.y = yaw

	var hspeed := Vector2(velocity.x, velocity.z).length()
	var strafe: float = (Basis(Vector3.UP, yaw).inverse() * velocity).x / stats.move_speed
	character.animate(delta, hspeed / stats.move_speed, is_on_floor(), velocity.y, pitch, recoil, clampf(strafe, -1.0, 1.0))
	if is_on_floor():
		_step_dist += hspeed * delta
		if _step_dist > 2.3:
			_step_dist = 0.0
			Sfx.play_at("step", global_position, -9.0)
	var frac: float = clampf(health / stats.max_health, 0.0, 1.0)
	health_bar.set_instance_shader_parameter("fill", frac)
	health_bar.set_instance_shader_parameter("tint", Color(1.0, 0.3, 0.3).lerp(Color(0.35, 0.9, 0.4), frac))

	if global_position.y < -25.0:
		take_damage(99999.0, null, true)
		return

	# --- weapon ---
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			ammo = stats.mag_size
			Sfx.play_at("tick", global_position, -8.0, 1.5)
	elif ammo <= 0 or (brain.reload and ammo < stats.mag_size):
		reload_left = stats.reload_time
		Sfx.play_at("reload", global_position, -6.0)
	elif brain.fire and fire_cd <= 0.0:
		_shoot()
		fire_cd = stats.fire_interval / (1.0 + rush)


func _shoot() -> void:
	# Per-shot damage bonuses.
	var mult: float = 1.0 + minf(kills_life, 5) * stats.rampage
	if ammo == 1 and stats.overcharge > 0.0 and stats.mag_size > 1:
		mult *= 1.0 + stats.overcharge
	ammo -= 1
	fire_cd = stats.fire_interval
	recoil = 1.0
	muzzle_flash = 1.0
	shake = maxf(shake, 0.1 * stats.recoil_kick)
	Sfx.play_at("shoot", global_position, -5.0 + (2.0 if stats.recoil_kick > 1.5 else 0.0), stats.shoot_pitch)

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
	Fx.flash(game.world, character.muzzle_position(), Color(1.0, 0.95, 0.7, 0.9), 0.08, 0.3, 0.07)

	for i in stats.pellets:
		var s: float = stats.spread + (0.02 if i > 0 else 0.0)
		var dir := (target - muzzle).normalized()
		dir = (dir + basis.x * randf_range(-s, s) + basis.y * randf_range(-s, s)).normalized()
		var b = Bullet.new()
		b.setup(self, dir, mult)
		game.world.add_child(b)
		b.global_position = muzzle
		b.orient()
		b.reset_physics_interpolation()


func launch(v: Vector3) -> void:
	velocity = v
	dash_left = 0.0
	fov_kick = 0.6
	Fx.ring(game.world, global_position + Vector3(0, 0.2, 0), Color(0.4, 1.0, 0.9, 0.9), 0.5, 1.8, 0.35)


func heal(amount: float) -> void:
	if alive:
		health = minf(stats.max_health, health + amount)


## Returns the damage actually dealt. `silent` skips hit feedback (poison ticks).
func take_damage(amount: float, attacker, silent := false, crit := false) -> float:
	if not alive or game.frozen:
		return 0.0
	var lethal_zone: bool = amount >= 9999.0      # falling out of the world
	if spawn_protect > 0.0 and not lethal_zone:
		return 0.0
	if stats.dash_invuln and dash_left > 0.0 and not lethal_zone:
		return 0.0
	if not silent and not lethal_zone and shield_ready():
		# The bubble eats this hit and starts recharging.
		shield_timer = stats.shield_cd
		Fx.ring(game.world, chest_position(), Color(0.5, 0.9, 1.0, 0.9), 0.4, 1.8, 0.3)
		Fx.burst(game.world, chest_position(), Color(0.6, 0.9, 1.0), 10, 5.0, 0.2, 0.35, -2.0)
		Sfx.play_at("bounce", global_position, -4.0, 0.6)
		if attacker != null and is_instance_valid(attacker):
			attacker.hit_marker = 0.6
		return 0.0
	amount *= stats.damage_taken
	health -= amount
	since_damage = 0.0
	var has_attacker: bool = attacker != null and is_instance_valid(attacker) and attacker != self
	if not silent:
		hurt_flash = 1.0
		shake = maxf(shake, clampf(amount / 60.0, 0.25, 0.9))
		character.hit_flash()
		Sfx.play_at("hurt", global_position, -8.0)
		if not is_bot and brain.device >= 0 and Settings.v("rumble"):
			Input.start_joy_vibration(brain.device, 0.4, 0.7, 0.18)
		if has_attacker:
			damage_dirs.append([attacker.global_position, 1.2])
			if stats.thorns > 0.0:
				attacker.take_damage(amount * stats.thorns, self, true)
	if has_attacker:
		if not silent:
			attacker.hit_marker = 1.0
			attacker.hit_crit = crit
			if attacker.has_view:
				Sfx.play("hit", -8.0, 1.3 if crit else 1.0)
				if Settings.v("numbers"):
					Fx.damage_number(game.world, global_position + Vector3(0, 2.0, 0), amount, crit, attacker.viewmodel_layer_bit())
		if attacker.stats.lifesteal > 0.0:
			attacker.heal(amount * attacker.stats.lifesteal)
	if health <= 0.0:
		if second_wind_left > 0 and not lethal_zone:
			second_wind_left -= 1
			health = 1.0
			spawn_protect = 1.0
			say("SECOND WIND!")
			Fx.ring(game.world, chest_position(), Color(1.0, 0.85, 0.3, 0.9), 0.3, 2.0, 0.4)
			Sfx.play_at("join", global_position, -4.0)
		else:
			_die(attacker)
	return amount


func apply_poison(total: float, src) -> void:
	poison_dps = (poison_dps * maxf(poison_left, 0.0) + total) / 3.0
	poison_left = 3.0
	poison_src = src


func apply_slow(amount: float) -> void:
	slow_amount = maxf(amount, slow_amount if slow_left > 0.0 else 0.0)
	slow_left = 2.0


func _die(attacker) -> void:
	alive = false
	deaths += 1
	health = 0.0
	_set_alive_visuals(false)
	velocity = Vector3.ZERO
	killer = attacker if (attacker != null and is_instance_valid(attacker) and attacker != self) else null
	card_choices = Cards.draw(stats.card_draw, weapon)
	card_sel = mini(1, card_choices.size() - 1)
	dead_time = 0.0
	pick_time = 0.0
	respawn_pending = false
	shake = 1.0
	Sfx.play_at("pop", global_position, -2.0)
	# Party-popper death: confetti and a puff, no gore.
	var c := chest_position()
	Fx.confetti(game.world, c, 46)
	Fx.puff(game.world, c, Color(color.lerp(Color.WHITE, 0.5), 0.85), 14, 0.9)
	Fx.flash(game.world, c, Color(1, 1, 1, 0.8), 0.3, 1.5, 0.2)
	game.on_player_died(self, attacker)


## While dead: choose one of the offered cards, then respawn.
func _dead_tick(delta: float) -> void:
	if respawn_pending or card_choices.is_empty():
		return
	dead_time += delta
	if is_bot:
		if dead_time > 1.9:
			_pick_card(randi() % card_choices.size())
		return
	if dead_time < 0.85:
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
	if card.has("weapon"):
		weapon = card.weapon
	else:
		picked.append(card)
	rebuild_stats()
	cards.append(card.name)
	card_icons.append([card.icon, card.rarity])
	card_sel = i
	respawn_pending = true
	pick_time = 0.0
	if not is_bot:
		Sfx.play("card", -6.0)
	game.respawn_later(self, 0.7)
