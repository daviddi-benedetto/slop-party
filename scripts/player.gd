extends CharacterBody3D
## One combatant (human or bot).
##
## The player never reads devices itself: it asks its `brain` (input_source.gd
## for humans, bot_brain.gd for bots) for move/fire/aim/jump/dash/block/etc.
## each physics tick. View angles (yaw/pitch) are plain floats so they can be
## updated every rendered frame, independent of the physics rate; game.gd
## builds the camera transform from them.
##
## Abilities: jump (+ air jumps from cards), dash, block (a short window that
## negates damage and reflects bullets, on a cooldown), aim down sights (zoom,
## tighter spread, slower movement), interact (pick up the weapon you are
## standing next to).
##
## Stats are rebuilt, never edited: rebuild_stats() = defaults -> weapon ->
## picked cards.
##
## Visuals are a character.gd model (animated from _physics_process), a name
## tag, a health bar and shield meshes, all on this player's private visual
## layer so the owner's own camera does not see them.
##
## Life cycle:  spawn() -> alive -> _die() -> card pick (HUD draws it, input is
## handled here in _dead_tick) -> game.respawn() -> spawn() ...
## Nothing moves while game.frozen is true (countdown, match over).
##
## Everything here is written per-second (multiplied by delta), so it does not
## depend on the physics tick rate.

const Stats = preload("res://scripts/stats.gd")
const Cards = preload("res://scripts/cards.gd")
const Bullet = preload("res://scripts/bullet.gd")
const Fx = preload("res://scripts/fx.gd")
const Character = preload("res://scripts/character.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Weapons = preload("res://scripts/weapons.gd")
const Prop = preload("res://scripts/prop.gd")

const EYE_HEIGHT := 1.6
const GRAVITY := 22.0
const WORLD_MASK := 1
const PLAYER_MASK := 2
const BLOCK_TIME := 0.38

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
	vec3 bar = f < fill ? tint.rgb * (uv.y < 0.45 ? 1.25 : 1.0) : vec3(0.14, 0.14, 0.2);
	ALBEDO = mix(vec3(0.03, 0.03, 0.06), bar, inside);
}
"""

static var _bar_material: ShaderMaterial

# Identity (set by game.gd before add_child)
var index := 0
var pname := "P1"
var color := Color.WHITE
var kind := 0
var hat := 0
var face := 0
var back := 0
var brain
var is_bot := false
var has_view := false      # true when a splitscreen cell follows this player
var wants_view := false    # set by game.gd from the participant entry
var team := -1             # -1 free-for-all; 0/1 in team modes (see game.is_enemy)
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
var melee_cd := 0.0
var burst_left := 0
var burst_t := 0.0
var dash_cd := 0.0
var dash_left := 0.0
var dash_dir := Vector3.ZERO
var block_cd := 0.0
var block_left := 0.0
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
var near_pickup = null            # pickup.gd pad we are standing on (set by the pad)
var crouching := false
var crouch_amount := 0.0          # smoothed 0..1, lowers the camera
var sliding := 0.0                # seconds of slide left
var wallrun := 0.0                # seconds into the current wall run (0 = not running)
var wall_normal := Vector3.ZERO
var wall_side := 0.0              # -1..1, which side the wall is on (camera roll)
var wall_tilt := 0.0              # smoothed wall_side
var jet_fuel := 0.0
var jetting := false
var shot_t := 9.0                 # seconds since the last shot (weapon animation)
var _last_wall := Vector3.ZERO
var _since_wall := 9.0
var _wall_cd := 0.0
var _mantle_cd := 0.0
var _jump_held_t := 0.0
var _jet_t := 0.0
var pickup_prompt := ""           # what the HUD offers to pick up
var prompt_key := ""              # button shown with the prompt ("" = interact)
var vehicle = null                # vehicle.gd we are driving / flying (or null)
var picking := false              # choosing a card while alive (zombies intermission)
var skydive := false              # dropped from the sky (Frontline spawn)
var chute_open := false
var _chute: Node3D
var _empower := 0.0               # seconds left of the Empower block perk
var _echo_t := 0.0                # Echo Guard: time until the free repeat block
var _slamming := false            # diving for a Ground Slam
var _drone_t := 1.0
var _drone: MeshInstance3D

# Card selection while dead
var card_choices: Array = []
var card_sel := 1
var dead_time := 0.0
var killer = null
var respawn_pending := false
var pick_time := 0.0             # seconds since the card was confirmed

# Feedback values read by hud.gd / game.gd / viewmodel.gd (smoothed or decaying)
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
var block_flash := 0.0           # 1 right after a successful block
var aim_amount := 0.0            # 0 hip .. 1 fully aimed down sights
var bob_phase := 0.0
var bob_amount := 0.0            # 0 standing .. ~1 running
var strafe_amount := 0.0         # -1 left .. 1 right
var fall_amount := 0.0           # smoothed vertical speed, for weapon inertia
var damage_dirs: Array = []      # [[world_pos, time_left], ...]
var notice := ""                 # short HUD message ("GOT SCATTER!")
var notice_t := 0.0
var spawn_time := 0.0

var character
var viewmodel
var name_label: Label3D
var health_bar: MeshInstance3D
var bullet_material: StandardMaterial3D
var attr_color := Color.WHITE
var trail_material: StandardMaterial3D
var _shape: CollisionShape3D
var _was_floor := true
var _fall_speed := 0.0
var _step_dist := 0.0
var _shield_mesh: MeshInstance3D
var _block_mesh: MeshInstance3D
var _block_mat: StandardMaterial3D
var _flash_light: OmniLight3D
var _aura: OmniLight3D


## Players 0-5 each get a private layer; extra bots (Frontline fills teams
## to 12) share bit 7, since only the first six can have a camera.
func body_layer_bit() -> int:
	return 1 << (index + 1) if index < 6 else 1 << 7


func viewmodel_layer_bit() -> int:
	return 1 << (index + 8) if index < 6 else 1 << 14


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

	# Bullets and their trails glow in the owner's colour (emission > 1 feeds the bloom).
	bullet_material = StandardMaterial3D.new()
	bullet_material.albedo_color = Color.BLACK
	bullet_material.emission_enabled = true
	bullet_material.emission = color.lerp(Color.WHITE, 0.45)
	bullet_material.emission_energy_multiplier = 3.5
	trail_material = StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	trail_material.albedo_color = Color(color.lerp(Color.WHITE, 0.2), 0.7)
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	character = Character.new()
	add_child(character)
	character.build(kind, color, body_layer_bit(), true, hat, face, back)

	name_label = Label3D.new()
	name_label.text = pname
	name_label.font = UiKit.font(700)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 56
	name_label.pixel_size = 0.0042
	name_label.outline_size = 16
	name_label.outline_modulate = UiKit.INK
	name_label.modulate = color.lerp(Color.WHITE, 0.45)
	name_label.position.y = 2.62
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
	health_bar.position.y = 2.34
	health_bar.layers = body_layer_bit()
	health_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(health_bar)

	# Bubble shield (card) and block flash (ability): two shells around the body.
	var bubble := SphereMesh.new()
	bubble.radius = 1.2
	bubble.height = 2.4
	_shield_mesh = _shell(bubble, Color(0.5, 0.9, 1.0, 0.14), Color(0.4, 0.8, 1.0), 0.5)
	_block_mesh = _shell(bubble, Color(color, 0.1), color.lerp(Color.WHITE, 0.3), 0.6)
	_block_mesh.scale = Vector3.ONE * 1.08
	_block_mat = _block_mesh.material_override

	# Muzzle flash light: makes every shot light up the surroundings.
	_flash_light = OmniLight3D.new()
	_flash_light.position = Vector3(0.25, 1.45, -0.9)
	_flash_light.light_color = color.lerp(Color(1.0, 0.9, 0.7), 0.55)
	_flash_light.omni_range = 7.0
	_flash_light.light_energy = 0.0
	_flash_light.visible = false
	add_child(_flash_light)

	# A soft glow in the player's colour: keeps everyone readable in the dark.
	_aura = OmniLight3D.new()
	_aura.position = Vector3(0, 1.1, 0)
	_aura.light_color = color
	_aura.light_energy = 0.3
	_aura.omni_range = 4.0
	add_child(_aura)

	_build_chute()
	# Buddy drone (card): a little glowing ball that hovers over the shoulder.
	var orb := SphereMesh.new()
	orb.radius = 0.13
	orb.height = 0.26
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(0.1, 0.1, 0.12)
	om.emission_enabled = true
	om.emission = color.lerp(Color.WHITE, 0.3)
	om.emission_energy_multiplier = 2.5
	_drone = MeshInstance3D.new()
	_drone.mesh = orb
	_drone.material_override = om
	_drone.visible = false
	_drone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_drone)
	_set_alive_visuals(false)


## Parachute canopy above the player (world layer: everyone sees it).
func _build_chute() -> void:
	_chute = Node3D.new()
	_chute.position.y = 4.4
	_chute.visible = false
	add_child(_chute)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = color.lerp(Color.WHITE, 0.15)
	cloth.roughness = 0.8
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dome := SphereMesh.new()
	dome.radius = 1.0
	dome.height = 1.0
	dome.is_hemisphere = true
	dome.radial_segments = 16
	dome.rings = 6
	var canopy := MeshInstance3D.new()
	canopy.mesh = dome
	canopy.material_override = cloth
	canopy.scale = Vector3(2.4, 1.0, 1.8)
	_chute.add_child(canopy)
	var cord := StandardMaterial3D.new()
	cord.albedo_color = Color(0.1, 0.1, 0.12)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var line := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.015
			cm.bottom_radius = 0.015
			cm.height = 1.0
			line.mesh = cm
			line.material_override = cord
			var a := Vector3(sx * 2.1, 0.05, sz * 1.5)
			var b := Vector3(sx * 0.25, -2.9, sz * 0.15)
			var d := b - a
			var y := d.normalized()
			var x := y.cross(Vector3.FORWARD).normalized()
			line.transform = Transform3D(Basis(x, y * d.length(), x.cross(y)), (a + b) * 0.5)
			line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_chute.add_child(line)


func _shell(mesh: Mesh, albedo: Color, glow: Color, energy: float) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = albedo
	m.rim_enabled = true
	m.rim = 1.0
	m.roughness = 0.1
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position.y = 0.95
	mi.layers = body_layer_bit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


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
	character.set_jetpack(stats.jetpack > 0.0)
	jet_fuel = minf(jet_fuel, stats.jetpack)
	# Body size (Tiny / Giant): model, hit capsule, eye and tag heights.
	character.scale = Vector3.ONE * stats.size
	var cap: CapsuleShape3D = _shape.shape
	cap.radius = 0.4 * stats.size
	cap.height = (1.15 if crouching else 1.8) * stats.size
	_shape.position.y = cap.height * 0.5
	name_label.position.y = 2.62 * stats.size
	health_bar.position.y = 2.34 * stats.size
	# Bullets, trails and muzzle flashes take on the colour of their effect.
	attr_color = color
	if stats.frost > 0.0:
		attr_color = Color(0.5, 0.85, 1.0)
	elif stats.poison > 0.0 and not stats.flame:
		attr_color = Color(0.45, 1.0, 0.3)
	elif stats.explosive > 0.0:
		attr_color = Color(1.0, 0.55, 0.15)
	elif stats.homing > 0.0:
		attr_color = Color(1.0, 0.4, 0.85)
	var mix := attr_color.lerp(color, 0.35) if attr_color != color else color
	bullet_material.emission = mix.lerp(Color.WHITE, 0.4)
	trail_material.albedo_color = Color(mix.lerp(Color.WHITE, 0.15), 0.7)


func weapon_name() -> String:
	return Weapons.LIST[weapon].name


## Swap weapon mid-life (pickup pads). Cards are kept.
func pick_weapon(id: int) -> void:
	weapon = id
	rebuild_stats()
	ammo = stats.mag_size
	reload_left = 0.0
	burst_left = 0
	fire_cd = 0.25
	say("GOT %s!" % weapon_name().to_upper())


func say(text: String) -> void:
	notice = text
	notice_t = 1.6


func shield_ready() -> bool:
	return stats.shield_cd > 0.0 and shield_timer <= 0.0


func is_blocking() -> bool:
	return alive and block_left > 0.0


## How much the view is zoomed (1 = hip fire). Also scales look sensitivity.
func zoom_factor() -> float:
	return lerpf(1.0, stats.zoom, aim_amount)


func _set_crouch(on: bool) -> void:
	if on == crouching:
		return
	crouching = on
	var cap: CapsuleShape3D = _shape.shape
	cap.height = (1.15 if on else 1.8) * stats.size
	_shape.position.y = cap.height * 0.5


func _ceiling_low() -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), global_position + Vector3(0, 1.9, 0), WORLD_MASK)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Normal of a runnable wall beside the player, or ZERO.
func _find_wall(flat: Basis) -> Vector3:
	var space := get_world_3d().direct_space_state
	var chest := global_position + Vector3(0, 1.0, 0)
	var best := Vector3.ZERO
	var best_d := 9.0
	for side in [flat.x, -flat.x]:
		var q := PhysicsRayQueryParameters3D.create(chest, chest + side * 0.85, WORLD_MASK)
		var hit := space.intersect_ray(q)
		if hit and absf(hit.normal.y) < 0.3:
			var d: float = chest.distance_to(hit.position)
			if d < best_d:
				best_d = d
				best = hit.normal
	return best


func _end_wallrun() -> void:
	_last_wall = wall_normal
	_since_wall = 0.0
	wallrun = 0.0
	_wall_cd = 0.25


## Height of a ledge just ahead that can be mantled (0.4-2.0 m), or 0.
func _find_ledge(fwd: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var chest := global_position + Vector3(0, 0.9, 0)
	var q := PhysicsRayQueryParameters3D.create(chest, chest + fwd * 0.75, WORLD_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or absf(hit.normal.y) > 0.4:
		return 0.0
	var top_from: Vector3 = hit.position + fwd * 0.35 + Vector3(0, 1.4, 0)
	var q2 := PhysicsRayQueryParameters3D.create(top_from, top_from - Vector3(0, 1.8, 0), WORLD_MASK)
	var down := space.intersect_ray(q2)
	if down.is_empty() or down.normal.y < 0.7:
		return 0.0
	var h: float = down.position.y - global_position.y
	if h < 0.4 or h > 2.0:
		return 0.0
	var q3 := PhysicsRayQueryParameters3D.create(down.position + Vector3(0, 0.1, 0), down.position + Vector3(0, 1.7, 0), WORLD_MASK)
	q3.hit_from_inside = true
	if not space.intersect_ray(q3).is_empty():
		return 0.0
	return h


## An extra sound layer for the bullet's special effect, if it has one.
func _attribute_sound(style: String) -> String:
	if stats.explosive > 0.0 and not style in ["boomer", "lobber"]:
		return "mod_boom"
	if stats.frost > 0.0:
		return "mod_ice"
	if stats.poison > 0.0 and style != "flamer":
		return "mod_toxic"
	if stats.homing > 0.0 and style != "bubbler":
		return "mod_seek"
	if stats.pierce > 0 and style != "rail":
		return "mod_pierce"
	return ""


## Called by game.gd for every credited KO.
func on_kill(victim = null) -> void:
	kills_life += 1
	if stats.corpse_bomb > 0.0 and victim != null and is_instance_valid(victim):
		# Chain Reaction (card): whoever we KO goes off like a bomb.
		var at: Vector3 = victim.chest_position()
		get_tree().create_timer(0.12, false).timeout.connect(func():
			if is_instance_valid(self):
				game.explode(at, stats.corpse_bomb, 55.0, self, self))
	if stats.kill_heal > 0.0:
		heal(stats.kill_heal)
	if stats.kill_reload and alive:
		ammo = stats.mag_size
		reload_left = 0.0


func _set_alive_visuals(on: bool) -> void:
	character.visible = on
	if not on:
		_shield_mesh.visible = false
		_block_mesh.visible = false
		_flash_light.visible = false
	name_label.visible = on
	_aura.visible = on
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
	burst_left = 0
	dash_cd = 0.0
	dash_left = 0.0
	block_cd = 0.0
	block_left = 0.0
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
	near_pickup = null
	pickup_prompt = ""
	aim_amount = 0.0
	sliding = 0.0
	wallrun = 0.0
	jet_fuel = stats.jetpack
	_set_crouch(false)
	picking = false
	skydive = false
	chute_open = false
	_chute.visible = false
	if vehicle != null and is_instance_valid(vehicle):
		vehicle.eject(self)
	vehicle = null
	alive = true
	spawn_time = 0.0
	_was_floor = true
	_set_alive_visuals(true)
	character.pop_in()
	reset_physics_interpolation()
	Fx.ring(game.world, pos + Vector3(0, 0.1, 0), Color(color.lerp(Color.WHITE, 0.4), 0.9), 0.3, 1.8, 0.5)


func eye_position() -> Vector3:
	return global_position + Vector3(0, eye_height() - 0.6 * crouch_amount * stats.size, 0)


func eye_height() -> float:
	return EYE_HEIGHT * stats.size


func head_height() -> float:
	return 1.12 * stats.size


func chest_position() -> Vector3:
	return global_position + Vector3(0, 1.0 * stats.size, 0)


func aim_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


# --------------------------------------------------------------------------
# Per rendered frame: look, and the smoothed values that drive camera/HUD
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	hit_marker = maxf(0.0, hit_marker - delta * 3.5)
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.2)
	recoil = maxf(0.0, recoil - delta * 9.0)
	kill_flash = maxf(0.0, kill_flash - delta * 0.55)
	shake = maxf(0.0, shake - delta * 2.8)
	fov_kick = maxf(0.0, fov_kick - delta * 3.5)
	land_dip = maxf(0.0, land_dip - delta * 5.0)
	muzzle_flash = maxf(0.0, muzzle_flash - delta * 16.0)
	block_flash = maxf(0.0, block_flash - delta * 3.0)
	notice_t = maxf(0.0, notice_t - delta)
	spawn_time += delta
	shot_t += delta
	crouch_amount = move_toward(crouch_amount, 1.0 if crouching else 0.0, delta * 7.0)
	wall_tilt = lerpf(wall_tilt, wall_side, clampf(delta * 8.0, 0.0, 1.0))
	if health_ghost > health:
		health_ghost = maxf(health, health_ghost - delta * stats.max_health * 0.7)
	else:
		health_ghost = health
	for d in damage_dirs:
		d[1] -= delta
	damage_dirs = damage_dirs.filter(func(d): return d[1] > 0.0)
	if respawn_pending:
		pick_time += delta

	var playing: bool = alive and not game.frozen
	var want_aim: bool = playing and (brain.aim or game.debug_aim) and reload_left <= 0.0 and dash_left <= 0.0
	aim_amount = move_toward(aim_amount, 1.0 if want_aim else 0.0, delta * 7.5)

	# Head bob / strafe lean / weapon inertia inputs.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var grounded: bool = playing and is_on_floor()
	var k := clampf(delta * 9.0, 0.0, 1.0)
	bob_amount = lerpf(bob_amount, clampf(hspeed / 7.5, 0.0, 1.4) if grounded else 0.0, k)
	if grounded and hspeed > 0.4:
		bob_phase += delta * (4.2 + hspeed * 0.95)
	var side: float = (Basis(Vector3.UP, yaw).inverse() * velocity).x / maxf(stats.move_speed, 0.1)
	strafe_amount = lerpf(strafe_amount, clampf(side, -1.0, 1.0) if playing else 0.0, k)
	fall_amount = lerpf(fall_amount, clampf(velocity.y, -14.0, 10.0) if playing else 0.0, k)

	_flash_light.visible = muzzle_flash > 0.02 and alive
	_flash_light.light_energy = muzzle_flash * 2.2 * clampf(stats.recoil_kick, 0.7, 2.0)
	_block_mesh.visible = block_left > 0.0 and alive
	if _block_mesh.visible:
		_block_mat.emission_energy_multiplier = 0.5 + block_flash * 2.5

	if alive and not game.match_over:
		brain.update_look(self, delta)


# --------------------------------------------------------------------------
# Per physics tick: everything that matters for the simulation
# --------------------------------------------------------------------------

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
	if picking:
		# Between zombie waves: stand still and choose a card.
		_dead_tick(delta)
		velocity = Vector3(0, minf(velocity.y, 0.0) - GRAVITY * delta, 0)
		move_and_slide()
		character.animate(delta, 0.0, is_on_floor(), 0.0, pitch)
		return
	if vehicle != null:
		pickup_prompt = ""
		vehicle.control(self, delta)
		return
	melee_cd = maxf(0.0, melee_cd - delta)
	if brain.melee and melee_cd <= 0.0:
		_melee_attack()

	# --- timers / status effects ---
	fire_cd = maxf(0.0, fire_cd - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	block_cd = maxf(0.0, block_cd - delta)
	block_left = maxf(0.0, block_left - delta)
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

	# --- interact: the pad we stood on last tick told us about itself ---
	prompt_key = ""
	if near_pickup != null and is_instance_valid(near_pickup):
		pickup_prompt = near_pickup.prompt()
		if brain.interact:
			near_pickup.take(self)
	else:
		pickup_prompt = ""
		var car = game.vehicle_near(self) if not game.vehicles.is_empty() else null
		if car != null:
			pickup_prompt = "GET IN " + car.label
			if brain.interact:
				car.enter(self)
				return
		elif not is_bot:
			var pet = game.pet_near(self)
			if pet != null:
				pickup_prompt = "PET THE " + pet.label
				if brain.interact:
					pet.pet(self)
	near_pickup = null

	# --- block ---
	if brain.block and block_cd <= 0.0:
		block_cd = stats.block_cooldown
		_start_block(true)
	if _echo_t > 0.0:
		_echo_t -= delta
		if _echo_t <= 0.0:
			_start_block(false)
	_empower = maxf(0.0, _empower - delta)
	_drone_tick(delta)

	# --- movement ---
	var input: Vector2 = brain.move
	var flat := Basis(Vector3.UP, yaw)
	var wish := flat * Vector3(input.x, 0.0, -input.y)
	if skydive:
		_skydive_tick(delta, wish)
		_weapon_tick(delta, rush)
		return
	var speed: float = stats.move_speed * (1.0 + rush) * (1.0 - 0.3 * aim_amount) * (1.0 - (slow_amount if slow_left > 0.0 else 0.0))
	var on_floor := is_on_floor()
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	_wall_cd = maxf(0.0, _wall_cd - delta)
	_since_wall += delta
	_mantle_cd = maxf(0.0, _mantle_cd - delta)
	_jump_held_t = _jump_held_t + delta if brain.jump_held else 0.0

	# Crouch and slide (slide = crouch while running on the ground).
	var want_crouch: bool = brain.crouch
	if on_floor and want_crouch and not crouching and horiz.length() > stats.move_speed * 0.75:
		sliding = 0.9
		var boost: float = maxf(horiz.length() * 1.2, stats.move_speed * 1.55) * stats.slide_boost
		horiz = horiz.normalized() * boost
		Sfx.play_at("slide", global_position, -6.0)
		Fx.puff(game.world, global_position + Vector3(0, 0.15, 0), Color(1, 1, 1, 0.5), 8, 0.5)
	if sliding > 0.0:
		sliding -= delta
		if not want_crouch or horiz.length() < stats.move_speed * 0.55:
			sliding = 0.0
	_set_crouch(want_crouch or sliding > 0.0 or (crouching and _ceiling_low()))

	# Ground and air movement. In the air, input steers without bleeding off
	# momentum (wall jumps, slide hops and pads keep their speed).
	if sliding > 0.0:
		horiz = horiz.move_toward(Vector3.ZERO, 5.5 * delta)
		horiz = horiz.rotated(Vector3.UP, clampf(input.x, -1.0, 1.0) * -0.9 * delta)
	elif on_floor:
		horiz = horiz.move_toward(wish * speed * (0.5 if crouching else 1.0), 70.0 * delta)
	else:
		var cur := horiz.length()
		horiz += wish * 24.0 * delta
		var cap := maxf(cur, speed)
		if horiz.length() > cap:
			horiz = horiz.normalized() * cap
		horiz *= 1.0 - 0.12 * delta

	# Wall running: airborne, moving forward, fast, next to a wall.
	if wallrun <= 0.0 and not on_floor and _wall_cd <= 0.0 and input.y > 0.3 and horiz.length() > 4.5 and velocity.y < 6.0:
		var n := _find_wall(flat)
		if n != Vector3.ZERO and not (n.dot(_last_wall) > 0.85 and _since_wall < 0.9):
			wallrun = 0.001
			wall_normal = n
			air_jumps = stats.max_jumps - 1
			velocity.y = maxf(velocity.y, 1.5)
			Sfx.play_at("step", global_position, -6.0, 1.3)
	if wallrun > 0.0:
		wallrun += delta
		var n2 := _find_wall(flat)
		if on_floor or n2 == Vector3.ZERO or wallrun > stats.wallrun_time or input.y < 0.1:
			_end_wallrun()
		else:
			wall_normal = n2
			var along := horiz - wall_normal * horiz.dot(wall_normal)
			along = along.normalized() * maxf(along.length(), stats.move_speed * 1.3)
			horiz = along - wall_normal * 1.5
			velocity.y = move_toward(velocity.y, -2.0 * wallrun / stats.wallrun_time, 22.0 * delta)
			_step_dist += along.length() * delta
	wall_side = -wall_normal.dot(flat.x) if wallrun > 0.0 else 0.0

	if on_floor:
		air_jumps = stats.max_jumps - 1
		if stats.jetpack > 0.0:
			jet_fuel = minf(stats.jetpack, jet_fuel + delta * 0.9)
		if not _was_floor and _fall_speed > 6.0:
			land_dip = clampf(_fall_speed / 16.0, 0.3, 1.0)
			Fx.puff(game.world, global_position + Vector3(0, 0.1, 0), Color(1, 1, 1, 0.5), 6, 0.45)
			Sfx.play_at("land", global_position, -12.0)
	elif wallrun <= 0.0:
		velocity.y -= GRAVITY * stats.gravity_mult * delta
		_fall_speed = -velocity.y
	_was_floor = on_floor

	if brain.jump:
		if wallrun > 0.0:
			# Wall jump: off the wall, keeping speed along it.
			var along2 := horiz - wall_normal * horiz.dot(wall_normal)
			horiz = along2 + wall_normal * 7.5
			velocity.y = stats.jump_velocity * 1.05
			_end_wallrun()
			Sfx.play_at("jump", global_position, -9.0, 1.15)
			Fx.ring(game.world, global_position + Vector3(0, 1.0, 0), Color(1, 1, 1, 0.7), 0.2, 1.0, 0.3)
		elif on_floor or (sliding > 0.0):
			velocity.y = stats.jump_velocity
			sliding = 0.0
			Sfx.play_at("jump", global_position, -12.0)
		elif air_jumps > 0:
			air_jumps -= 1
			velocity.y = stats.jump_velocity
			Sfx.play_at("jump", global_position, -10.0, 1.3)
			Fx.ring(game.world, global_position, Color(1, 1, 1, 0.8), 0.2, 0.9, 0.3)

	# Mantle: moving forward into a ledge up to 2 m above the feet vaults onto it.
	if not on_floor and _mantle_cd <= 0.0 and wallrun <= 0.0 and input.y > 0.3 and velocity.y < 4.0:
		var ledge := _find_ledge(flat * Vector3.FORWARD)
		if ledge > 0.0:
			velocity.y = sqrt(2.0 * GRAVITY * (ledge + 0.3))
			horiz = flat * Vector3.FORWARD * maxf(3.5, horiz.length() * 0.6)
			_mantle_cd = 0.5
			Sfx.play_at("jump", global_position, -11.0, 0.8)

	# Jetpack (card): hold jump in the air.
	jetting = false
	if stats.jetpack > 0.0 and not on_floor and wallrun <= 0.0 and brain.jump_held and jet_fuel > 0.0 and _jump_held_t > 0.18 and velocity.y < 3.5:
		jetting = true
		jet_fuel -= delta
		velocity.y = minf(velocity.y + (GRAVITY * stats.gravity_mult + 17.0) * delta, 6.5)
		_jet_t -= delta
		if _jet_t <= 0.0:
			_jet_t = 0.06
			var back := global_position + flat * Vector3(0, 0.9, 0.45)
			Fx.flash(game.world, back, Color(1.0, 0.6, 0.2, 0.85), 0.12, 0.38, 0.14)
			Fx.puff(game.world, back - Vector3(0, 0.4, 0), Color(0.8, 0.8, 0.85, 0.35), 1, 0.4)
			Sfx.play_at("jet", global_position, -12.0)

	if brain.dash and dash_cd <= 0.0:
		dash_dir = wish.normalized() if wish.length() > 0.1 else flat * Vector3.FORWARD
		dash_left = 0.16
		dash_cd = stats.dash_cooldown
		fov_kick = 1.0
		Sfx.play_at("dash", global_position, -6.0)
		Fx.puff(game.world, global_position + Vector3(0, 0.4, 0) - dash_dir * 0.9, Color(color.lerp(Color.WHITE, 0.5), 0.6), 8, 0.4)
	if dash_left > 0.0:
		dash_left -= delta
		horiz = dash_dir * maxf(22.0, speed * 2.4)
	# Ground Slam (card): crouch in the air to dive; shockwave on landing.
	if stats.slam > 0.0:
		if not on_floor and want_crouch and not _slamming and velocity.y < 9.0 and _fall_speed > -20.0 and not is_on_floor():
			var below := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3(0, -2.2, 0), WORLD_MASK)
			if get_world_3d().direct_space_state.intersect_ray(below).is_empty():
				_slamming = true
				Sfx.play_at("dash", global_position, -4.0, 0.6)
		if _slamming:
			velocity.y = -36.0
			horiz *= 0.3
	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()
	# Frontline parachutes also work after any high fall, including a roof or
	# tower jump. Give the player time to press Jump before the auto-open zone.
	if not is_on_floor() and velocity.y < -2.0 and not skydive:
		var height_ray := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3(0, -32.0, 0), WORLD_MASK)
		var ground_hit := get_world_3d().direct_space_state.intersect_ray(height_ray)
		if not ground_hit.is_empty() and global_position.y - ground_hit.position.y >= 7.0:
			skydive = true
			chute_open = false
	if _slamming and is_on_floor():
		_slamming = false
		land_dip = 1.0
		shake = maxf(shake, 0.7)
		game.explode(global_position + Vector3(0, 0.3, 0), 5.0, stats.slam, self, self)
	# Goomba Stomp (card): landing on an enemy hurts them and bounces us.
	if stats.stomp > 0.0 and _fall_speed > 2.5:
		for i in get_slide_collision_count():
			var col := get_slide_collision(i)
			var other = col.get_collider()
			if col.get_normal().y > 0.55 and other != null and other.has_method("take_damage") and other != self and game.is_enemy(self, other):
				other.take_damage(stats.stomp, self)
				velocity.y = stats.jump_velocity * 1.25
				air_jumps = stats.max_jumps - 1
				Fx.ring(game.world, global_position, Color(1, 1, 1, 0.9), 0.3, 1.6, 0.3)
				Sfx.play_at("bounce", global_position, -2.0, 0.7)
				break
	rotation.y = yaw
	character.crouch = crouch_amount
	character.jetting = jetting

	var hspeed := Vector2(velocity.x, velocity.z).length()
	# Barge through loose props and glass (they never block us).
	if hspeed > 1.5 and Engine.get_physics_frames() % 3 == index % 3:
		Prop.kick_near(get_world_3d().direct_space_state, global_position + Vector3(0, 0.7, 0), 0.75, velocity)
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
	_weapon_tick(delta, rush)


## Free fall, then a parachute (opened with jump, or automatically near the
## ground). The player can steer and shoot all the way down.
func _skydive_tick(delta: float, wish: Vector3) -> void:
	if is_on_floor():
		skydive = false
		chute_open = false
		_chute.visible = false
		pickup_prompt = ""
		land_dip = 0.8
		Fx.puff(game.world, global_position + Vector3(0, 0.1, 0), Color(1, 1, 1, 0.5), 10, 0.7)
		Sfx.play_at("land", global_position, -6.0)
		return
	if not chute_open:
		var ground := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3(0, -24.0, 0), WORLD_MASK)
		if brain.jump or not get_world_3d().direct_space_state.intersect_ray(ground).is_empty():
			chute_open = true
			_chute.visible = true
			_chute.scale = Vector3(0.2, 0.2, 0.2)
			create_tween().tween_property(_chute, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			Sfx.play_at("dash", global_position, -4.0, 0.6)
	pickup_prompt = "" if chute_open else "OPEN PARACHUTE"
	prompt_key = "A" if brain.device >= 0 else "SPACE"
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if chute_open:
		horiz = horiz.move_toward(wish * 9.0, 10.0 * delta)
		velocity.y = maxf(velocity.y - GRAVITY * delta, -4.5)
		_chute.rotation.z = lerpf(_chute.rotation.z, -wish.dot(Basis(Vector3.UP, yaw).x) * 0.25, clampf(delta * 3.0, 0.0, 1.0))
	else:
		horiz = horiz.move_toward(wish * 16.0, 14.0 * delta)
		velocity.y = maxf(velocity.y - GRAVITY * delta, -34.0)
	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()
	rotation.y = yaw
	fall_amount = clampf(velocity.y, -14.0, 10.0)
	character.animate(delta, 0.0, false, velocity.y, pitch, recoil)


func enter_vehicle(v) -> void:
	vehicle = v
	sliding = 0.0
	wallrun = 0.0
	aim_amount = 0.0
	character.visible = false
	name_label.visible = false
	health_bar.visible = false
	_aura.visible = false
	collision_layer = 0
	_shape.set_deferred("disabled", true)


func exit_vehicle(pos: Vector3) -> void:
	vehicle = null
	global_position = pos
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	if alive:
		_set_alive_visuals(true)


func _weapon_tick(delta: float, rush: float) -> void:
	if burst_left > 0:
		burst_t -= delta
		if ammo <= 0:
			burst_left = 0
		elif burst_t <= 0.0:
			burst_left -= 1
			burst_t = 0.075
			_fire_round()
	elif reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			ammo = stats.mag_size
			Sfx.play_at("tick", global_position, -8.0, 1.5)
	elif ammo <= 0 or (brain.reload and ammo < stats.mag_size):
		reload_left = stats.reload_time
		Sfx.play_at("reload", global_position, -6.0)
	elif brain.fire and fire_cd <= 0.0:
		_fire_round()
		fire_cd = stats.fire_interval / (1.0 + rush)
		burst_left = stats.burst - 1
		burst_t = 0.075


## One round: every pellet of a single shot, plus its feedback.
func _fire_round() -> void:
	# Per-shot damage bonuses.
	var mult: float = 1.0 + minf(kills_life, 5) * stats.rampage
	if _empower > 0.0:
		mult *= 1.0 + stats.block_empower
		_empower = 0.0
		Fx.ring(game.world, chest_position(), Color(1.0, 0.85, 0.3, 0.9), 0.2, 1.2, 0.2)
	if stats.speed_dmg > 0.0:
		mult *= 1.0 + stats.speed_dmg * clampf(Vector2(velocity.x, velocity.z).length() / (stats.move_speed * 1.5), 0.0, 1.0)
	if stats.air_dmg > 0.0 and not is_on_floor():
		mult *= 1.0 + stats.air_dmg
	if ammo == 1 and stats.overcharge > 0.0 and stats.mag_size > 1:
		mult *= 1.0 + stats.overcharge
	ammo -= 1
	recoil = 1.0
	muzzle_flash = 1.0
	shot_t = 0.0
	shake = maxf(shake, 0.1 * stats.recoil_kick)
	var style: String = Weapons.LIST[weapon].style
	Sfx.play_at("shot_" + style, global_position, -4.0 - (4.0 if stats.fire_interval < 0.06 else 0.0), clampf(stats.shoot_pitch * 0.3 + 0.7, 0.7, 1.3))
	var mod := _attribute_sound(style)
	if mod != "":
		Sfx.play_at(mod, global_position, -9.0)

	var eye := eye_position()
	var basis := aim_basis()
	var space := get_world_3d().direct_space_state
	# Converge on whatever the crosshair is pointing at.
	var far := eye - basis.z * 200.0
	var q := PhysicsRayQueryParameters3D.create(eye, far, WORLD_MASK | PLAYER_MASK)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var target: Vector3 = hit.position if hit else far
	var muzzle: Vector3 = viewmodel.muzzle_position() if viewmodel != null and is_instance_valid(viewmodel) and viewmodel.visible else character.muzzle_position()
	var block := PhysicsRayQueryParameters3D.create(eye, muzzle, WORLD_MASK)
	if space.intersect_ray(block) or target.distance_to(eye) < 1.2:
		muzzle = eye
	var flash_col := Color(attr_color.lerp(Color(1.0, 0.95, 0.7), 0.5), 0.9)
	Fx.flash(game.world, muzzle, flash_col, 0.08, 0.22 + 0.1 * stats.recoil_kick, 0.07, viewmodel_layer_bit() if has_view else body_layer_bit())
	if stats.recoil_kick > 1.5:
		Fx.sparks(game.world, muzzle, color.lerp(Color.WHITE, 0.5), 6, 6.0, -basis.z, 55.0, 0.4, viewmodel_layer_bit() if has_view else body_layer_bit())

	var aim_spread := lerpf(1.0, stats.ads_spread, aim_amount)
	for i in stats.pellets:
		var s: float = (stats.spread + (0.02 if i > 0 else 0.0)) * aim_spread
		var dir := (target - muzzle).normalized()
		dir = (dir + basis.x * randf_range(-s, s) + basis.y * randf_range(-s, s)).normalized()
		var b = Bullet.new()
		b.setup(self, dir, mult)
		game.world.add_child(b)
		b.global_position = muzzle
		b.orient()
		b.reset_physics_interpolation()


func _melee_attack() -> void:
	melee_cd = 0.62
	var origin := eye_position()
	var direction := -aim_basis().z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 2.15, WORLD_MASK | PLAYER_MASK)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var target = hit.collider
		if target != null and target.has_method("take_damage") and game.is_enemy(self, target):
			target.take_damage(58.0, self)
			Fx.sparks(game.world, hit.position, color.lerp(Color.WHITE, 0.55), 12, 4.5, direction, 75.0, 0.25)
			Sfx.play("hit", -5.0, 0.82)
			return
	Fx.puff(game.world, origin + direction * 1.7, Color(color.lerp(Color.WHITE, 0.5), 0.65), 5, 0.24)
	Sfx.play("dash", -9.0, 1.4)


func launch(v: Vector3) -> void:
	velocity = v
	dash_left = 0.0
	fov_kick = 0.6
	Fx.ring(game.world, global_position + Vector3(0, 0.2, 0), Color(0.4, 1.0, 0.9, 0.9), 0.5, 1.8, 0.35)


func heal(amount: float) -> void:
	if alive:
		health = minf(stats.max_health, health + amount)


## A hit landed while blocking. Returns nothing; the caller treats it as 0 damage.
func _blocked(attacker) -> void:
	block_flash = 1.0
	shake = maxf(shake, 0.3)
	Sfx.play_at("block", global_position, 0.0, 1.5)
	Fx.sparks(game.world, chest_position(), color.lerp(Color.WHITE, 0.5), 12, 7.0, Vector3.UP)
	if attacker != null and is_instance_valid(attacker) and attacker != self and game.is_player(attacker):
		attacker.hit_marker = 0.5
	if not is_bot and brain.device >= 0 and Settings.v("rumble"):
		Input.start_joy_vibration(brain.device, 0.6, 0.2, 0.12)
	if stats.block_heal > 0.0:
		heal(stats.block_heal)
	if stats.block_wave > 0.0:
		game.explode(chest_position(), 4.5, stats.block_wave, self, self)


## Returns the damage actually dealt. `silent` skips hit feedback (poison ticks).
func take_damage(amount: float, attacker, silent := false, crit := false) -> float:
	if not alive or game.frozen:
		return 0.0
	if attacker != null and is_instance_valid(attacker) and attacker != self and not game.is_enemy(attacker, self):
		return 0.0              # no friendly fire in team modes
	var lethal_zone: bool = amount >= 9999.0      # falling out of the world
	if spawn_protect > 0.0 and not lethal_zone:
		return 0.0
	if stats.dash_invuln and dash_left > 0.0 and not lethal_zone:
		return 0.0
	if block_left > 0.0 and not silent and not lethal_zone:
		_blocked(attacker)
		return 0.0
	if not silent and not lethal_zone and shield_ready():
		# The bubble eats this hit and starts recharging.
		shield_timer = stats.shield_cd
		Fx.ring(game.world, chest_position(), Color(0.5, 0.9, 1.0, 0.9), 0.4, 1.8, 0.3)
		Fx.sparks(game.world, chest_position(), Color(0.6, 0.9, 1.0), 10, 5.0, Vector3.UP)
		Sfx.play_at("bounce", global_position, -4.0, 0.6)
		if game.is_player(attacker):
			attacker.hit_marker = 0.6
		return 0.0
	amount *= stats.damage_taken
	health -= amount
	since_damage = 0.0
	var has_attacker: bool = attacker != null and is_instance_valid(attacker) and attacker != self
	var by_player: bool = has_attacker and game.is_player(attacker)
	if not silent:
		hurt_flash = 1.0
		shake = maxf(shake, clampf(amount / 60.0, 0.25, 0.9))
		character.hit_flash()
		var blood_dir := Vector3.UP
		if has_attacker:
			blood_dir = (global_position - attacker.global_position + Vector3(0, 0.5, 0)).normalized()
		Fx.blood_spray(game.world, chest_position(), blood_dir, 16)
		Sfx.play_at("hurt", global_position, -8.0)
		if not is_bot and brain.device >= 0 and Settings.v("rumble"):
			Input.start_joy_vibration(brain.device, 0.4, 0.7, 0.18)
		if has_attacker:
			damage_dirs.append([attacker.global_position, 1.2])
			if stats.thorns > 0.0:
				attacker.take_damage(amount * stats.thorns, self, true)
	if by_player:
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
	Fx.blood_spray(game.world, chest_position(), Vector3.UP, 52)
	Fx.blood_splat(game.world, global_position, 1.25)
	health = 0.0
	burst_left = 0
	_set_alive_visuals(false)
	velocity = Vector3.ZERO
	killer = attacker if (attacker != null and is_instance_valid(attacker) and attacker != self) else null
	if stats.martyr > 0.0 and not game.match_over:
		game.explode(chest_position(), stats.martyr, 70.0, self, self)
	_slamming = false
	_echo_t = 0.0
	_drone.visible = false
	card_choices = Cards.draw(stats.card_draw, weapon) if (game.rules == null or game.rules.cards_on_death()) else []
	skydive = false
	chute_open = false
	_chute.visible = false
	card_sel = mini(1, card_choices.size() - 1)
	dead_time = 0.0
	pick_time = 0.0
	respawn_pending = false
	pickup_prompt = ""
	shake = 1.0
	Sfx.play_at("pop", global_position, -2.0)
	# A burst of glowing shards in the player's colour: flashy, no gore.
	var c := chest_position()
	Fx.sparks(game.world, c, color.lerp(Color.WHITE, 0.3), 40, 11.0, Vector3.UP, 180.0, 0.9)
	Fx.confetti(game.world, c, 30)
	Fx.puff(game.world, c, Color(color.lerp(Color.WHITE, 0.4), 0.8), 12, 0.9)
	Fx.flash(game.world, c, Color(color.lerp(Color.WHITE, 0.6), 0.9), 0.3, 1.8, 0.22)
	Fx.ring(game.world, c, Color(color.lerp(Color.WHITE, 0.5), 0.9), 0.3, 3.2, 0.4)
	Fx.light(game.world, c, color.lerp(Color.WHITE, 0.4), 5.0, 9.0, 0.35)
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
	if not is_bot:
		Sfx.play("card", -6.0)
	if picking:
		picking = false
		card_choices = []
		health = stats.max_health
		ammo = stats.mag_size
		jet_fuel = stats.jetpack
		return
	respawn_pending = true
	pick_time = 0.0
	game.respawn_later(self, 0.7)


## Offer a card while alive (zombies: after each wave).
func offer_cards() -> void:
	if not alive:
		return
	card_choices = Cards.draw(stats.card_draw, weapon)
	card_sel = mini(1, card_choices.size() - 1)
	dead_time = 0.0
	picking = true
	respawn_pending = false
	burst_left = 0
	aim_amount = 0.0


# --------------------------------------------------------------------------
# Block perks and the buddy drone
# --------------------------------------------------------------------------

## The block goes up. `first` is false for the free Echo Guard repeat.
## Every block card hooks in here, so the block doubles as a weapon.
func _start_block(first: bool) -> void:
	block_left = BLOCK_TIME * stats.block_time
	Sfx.play_at("block", global_position, -3.0, 1.0 if first else 1.25)
	Fx.ring(game.world, chest_position(), Color(color.lerp(Color.WHITE, 0.4), 0.9), 0.5, 1.6, 0.25)
	if stats.block_reload and ammo < stats.mag_size:
		ammo = stats.mag_size
		reload_left = 0.0
	if stats.block_empower > 0.0:
		_empower = 3.5
	if stats.block_echo and first:
		_echo_t = 0.8
	var flat := Basis(Vector3.UP, yaw)
	if stats.block_blink > 0.0:
		# Teleport the way we are moving (or forwards), stopping short of walls.
		var dir: Vector3 = flat * Vector3(brain.move.x, 0.0, -brain.move.y)
		dir = dir.normalized() if dir.length() > 0.2 else flat * Vector3.FORWARD
		var from := chest_position()
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * stats.block_blink, WORLD_MASK)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var dist: float = (from.distance_to(hit.position) - 0.6) if hit else stats.block_blink
		if dist > 0.5:
			Fx.puff(game.world, from, Color(color.lerp(Color.WHITE, 0.5), 0.7), 10, 0.6)
			global_position += dir * dist
			reset_physics_interpolation()
			Fx.ring(game.world, chest_position(), Color(color.lerp(Color.WHITE, 0.5), 0.9), 0.2, 1.8, 0.3)
			Sfx.play_at("dash", global_position, -3.0, 1.4)
	var me := chest_position()
	if stats.block_frost > 0.0:
		Fx.ring(game.world, me, Color(0.6, 0.9, 1.0, 0.9), 0.5, stats.block_frost, 0.4)
		Sfx.play_at("mod_ice", global_position, -2.0)
		for d in game.hostiles(self):
			if d.chest_position().distance_to(me) < stats.block_frost:
				d.apply_slow(0.8)
				d.take_damage(10.0, self, true)
	if stats.block_pull > 0.0:
		Fx.ring(game.world, me, Color(0.8, 0.6, 1.0, 0.9), stats.block_pull, 0.5, 0.35)
		for d in game.hostiles(self):
			var to_me: Vector3 = me - d.chest_position()
			if to_me.length() < stats.block_pull and to_me.length() > 1.5 and not d.has_method("seat_count"):
				d.velocity += to_me.normalized() * 15.0 + Vector3(0, 4.0, 0)
	if stats.block_burst > 0:
		for i in stats.block_burst:
			var a: float = TAU * i / float(stats.block_burst)
			var b = Bullet.new()
			b.setup(self, (flat * Vector3(sin(a), 0.04, cos(a))).normalized(), 0.6)
			game.world.add_child(b)
			b.global_position = me
			b.orient()
			b.reset_physics_interpolation()
		Sfx.play_at("shot_scatter", global_position, -3.0, 1.2)


## Buddy Drone (card): hovers by the shoulder and plinks at the nearest
## enemy it can see, once a second per drone.
func _drone_tick(delta: float) -> void:
	_drone.visible = stats.drone > 0 and vehicle == null
	if stats.drone <= 0:
		return
	var t: float = game.time * 2.0
	_drone.position = Vector3(cos(t) * 0.7, 2.1 * stats.size + sin(t * 1.7) * 0.12, sin(t) * 0.7)
	_drone_t -= delta
	if _drone_t > 0.0:
		return
	_drone_t = 1.0 / stats.drone
	var from: Vector3 = _drone.global_position
	var best = null
	var best_d := 26.0
	for d in game.hostiles(self):
		var dist: float = d.chest_position().distance_to(from)
		if dist < best_d:
			var q := PhysicsRayQueryParameters3D.create(from, d.chest_position(), WORLD_MASK)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				best_d = dist
				best = d
	if best == null:
		return
	var s = Stats.new()
	s.damage = 9.0
	s.bullet_speed = 90.0
	s.bullet_gravity = 0.0
	var b = Bullet.new()
	b.setup_stats(self, s, (best.chest_position() + best.velocity * (best_d / 90.0) - from).normalized())
	game.world.add_child(b)
	b.global_position = from
	b.orient()
	b.reset_physics_interpolation()
	Sfx.play_at("shot_zapper", from, -12.0, 1.6)
