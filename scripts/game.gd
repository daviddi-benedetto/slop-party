extends Node
## One match in any mode, from the 3-2-1 countdown to the results screen.
##
## Modes (config.mode):
##   "rounds"    free-for-all deathmatch with a powerup pick after every
##               death; first to kill_target wins. Rules live in this file.
##   "zombies"   co-op survival against endless waves (zombies.gd).
##   "frontline" two teams, conquest flags, tickets, vehicles and parachute
##               drops on a large map (frontline.gd, vehicle.gd).
## A mode other than Rounds puts a rules node in `rules`; this file calls its
## hooks (prepare, start, on_died, respawn, bot_goal, draw_strip,
## results_title...) when present.
##
## Teams: every player has `team` (-1 = free-for-all). is_enemy() decides
## friendly fire; damageables() is everything a bullet or explosion can hurt
## (players on foot, zombies, vehicles); hostiles() what bots, homing bullets
## and aim assist go for.
##
## Owns: the 3D world (map + players + bullets), the splitscreen layout, the
## rules (scoring, respawns, win condition), area damage, the pause menu and
## the hand-over to results.gd.
##
## Flow:  countdown -> play -> (kill target reached) slow-motion "GAME!" ->
##        fade -> world freed, results.gd podium -> finished signal.
## `frozen` is true whenever players must not act (countdown / match over).
##
## Pausing uses SceneTree.paused. This node runs with PROCESS_MODE_ALWAYS so it
## can read the pause buttons; `world` is PROCESS_MODE_PAUSABLE.
##
## Splitscreen: all gameplay nodes live under `world`, in the root viewport's
## World3D. Each human gets a SubViewportContainer > SubViewport holding only a
## Camera3D (+ viewmodel.gd blaster) and a CanvasLayer with hud.gd.
## SubViewports share the parent World3D by default, so every camera sees the
## same match. Cameras are moved here in _process() from each player's
## yaw/pitch, plus screen shake, FOV kick and landing dip.
##
## Visibility layers (VisualInstance3D.layers / Camera3D.cull_mask):
##   bit 0        world geometry, bullets, effects
##   bit 1 + i    player i's third-person body (hidden from player i's camera)
##   bit 8 + i    player i's first-person gun and the damage numbers they cause
##
## config = { "participants": [ { "device": int, "bot": bool, "view": bool,
##            "kind": int, ... } ], "kill_target": int, "mode": String,
##            "map": int, "time": String, "teams": "versus" | "coop" }

signal finished

const Player = preload("res://scripts/player.gd")
const Map = preload("res://scripts/map.gd")
const Hud = preload("res://scripts/hud.gd")
const InputSource = preload("res://scripts/input_source.gd")
const BotBrain = preload("res://scripts/bot_brain.gd")
const Fx = preload("res://scripts/fx.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Viewmodel = preload("res://scripts/viewmodel.gd")
const MotionBlur = preload("res://scripts/motion_blur.gd")
const Results = preload("res://scripts/results.gd")
const SettingsMenu = preload("res://scripts/settings_menu.gd")
const Pickup = preload("res://scripts/pickup.gd")
const Cards = preload("res://scripts/cards.gd")
const Zombies = preload("res://scripts/zombies.gd")
const Frontline = preload("res://scripts/frontline.gd")
const Pet = preload("res://scripts/pet.gd")

const GunGame = preload("res://scripts/gungame.gd")
const Medieval = preload("res://scripts/medieval.gd")

const MODES := ["rounds", "zombies", "frontline", "gungame", "medieval"]
const MODE_NAMES := {"rounds": "ROUNDS", "zombies": "ZOMBIES", "frontline": "FRONTLINE", "gungame": "GUN GAME", "medieval": "MEDIEVAL"}

var config := {}
var world: Node3D
var map
var players: Array = []
var kill_target := 15
var match_over := false
var _debug_third := false    # dev flag --third: watch player 1 from the taunt camera
var debug_aim := false       # dev flag --force-aim: everyone aims down sights
var frozen := true
var winner = null
var time := 0.0
var countdown := 3.8
var go_flash := 0.0
var end_real_time := 0.0      # real seconds since the winning kill
var feed: Array = []          # [{killer, victim, t}] newest first
var mode := "rounds"
var rules = null              # zombies.gd / frontline.gd node (null in Rounds)
var actors: Array = []        # other damageable things: zombies, vehicles
var vehicles: Array = []
var pets: Array = []
var _res_measuring := false
var _res_gpu := 0.0           # smoothed GPU + CPU render time of all views (ms)
var _res_frame := 16.0        # smoothed real frame time (ms)
var _res_t := 2.0
var melee_strike := false     # true while a melee swing is dealing its damage
var _dmg_cache: Array = []
var _dmg_frame := -1

var _ui: Control
var _views: Array = []        # [{container, viewport, camera, gun, player, fov}]
var _kb_brain = null
var _last_usec := 0
var _prev := {}
var _paused := false
var _pause_ui: Control
var _pause_sel := 0
var _pause_note := ""
var _options
var _fade: ColorRect
var _results = null
var _last_count := 99


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game")
	kill_target = config.get("kill_target", 15)
	mode = config.get("mode", "rounds")
	if not mode in MODES:
		mode = "rounds"
	debug_aim = "--force-aim" in OS.get_cmdline_user_args()
	_debug_third = "--third" in OS.get_cmdline_user_args()
	world = Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	map = Map.new()
	world.add_child(map)
	var map_i: int = config.get("map", 0)
	if mode == "zombies":
		map_i = Map.ZOMBIE
	elif mode == "frontline":
		map_i = Map.FRONTLINE
	elif mode == "medieval":
		map_i = Map.CASTLE
	elif not map_i in Map.ARENAS:
		map_i = 0
	if mode == "zombies":
		rules = Zombies.new()
	elif mode == "frontline":
		rules = Frontline.new()
	elif mode == "gungame":
		rules = GunGame.new()
	elif mode == "medieval":
		rules = Medieval.new()
	var tod: String = config.get("time", "random")
	if not tod in Map.TIMES:
		tod = Map.TIMES[randi() % Map.TIMES.size()]
	map.build(map_i, tod)

	var parts: Array = config.participants
	if rules != null:
		rules.game = self
		world.add_child(rules)
		parts = rules.prepare(parts)
	var bot_n := 0
	for i in parts.size():
		var part: Dictionary = parts[i]
		var p = Player.new()
		p.index = i
		p.color = part.get("color", UiKit.PLAYER_COLORS[i % UiKit.PLAYER_COLORS.size()])
		p.kind = part.get("kind", i)
		p.hat = part.get("hat", 0)
		p.face = part.get("face", 0)
		p.back = part.get("back", 0)
		p.game = self
		p.is_bot = part.bot
		p.team = part.get("team", -1)
		if part.bot:
			bot_n += 1
			p.pname = "CPU %d" % bot_n
			p.brain = BotBrain.new()
			var tier: int = Settings.v("bots")
			p.brain.skill = [randf_range(0.1, 0.35), randf_range(0.35, 0.75), randf_range(0.8, 1.0)][tier]
		else:
			p.pname = "P%d" % (i + 1)
			p.brain = InputSource.new(part.device)
			# Each player's own look speed (lobby: LOOK 1-10, 5 = the global setting).
			p.brain.sens = 0.4 + 0.12 * float(part.get("sens", 5))
			if part.device == InputSource.KEYBOARD:
				_kb_brain = p.brain
		p.wants_view = part.get("view", not part.bot)
		players.append(p)
		world.add_child(p)

	# Dev flags: --cards=Name,Name gives every player those cards, --weapon=N a weapon.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cards="):
			for n in a.substr(8).split(","):
				for c in Cards.deck():
					if c.name == n:
						for p in players:
							if c.has("weapon"):
								p.weapon = c.weapon
							else:
								p.picked.append(c)
		elif a.begins_with("--weapon="):
			for p in players:
				p.weapon = int(a.substr(9))
	for p in players:
		p.rebuild_stats()
	_build_views()
	_build_overlays()
	get_viewport().size_changed.connect(_layout)
	Settings.changed.connect(_on_settings)
	Input.joy_connection_changed.connect(_on_joy_changed)
	Sfx.music("zombies" if mode == "zombies" else map.music_key())
	if _kb_brain != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if rules != null:
		rules.start()
	else:
		spawn_all_default()
	map.nav_built.connect(_spawn_pets)
	map.build_nav()
	var pads: bool = rules == null or not rules.has_method("weapon_pads") or rules.weapon_pads()
	for spot in map.pickup_spots:
		if spot[0] == "weapon" and not pads:
			continue
		var pk = Pickup.new()
		pk.kind = spot[0]
		pk.game = self
		pk.position = spot[1]
		world.add_child(pk)
	_prewarm()
	_last_usec = Time.get_ticks_usec()


## Play every effect once, out of sight, while the countdown runs, so the
## first real explosion or confetti burst does not hitch on shader setup.
func _prewarm() -> void:
	var p := Vector3(0, -60, 0)
	Fx.flash(world, p, Color.WHITE, 0.1, 0.5, 0.2)
	Fx.ring(world, p, Color.WHITE, 0.1, 0.5, 0.2)
	Fx.burst(world, p, Color.WHITE, 4, 1.0, 0.2, 0.3)
	Fx.confetti(world, p, 4)
	Fx.puff(world, p)
	Fx.sparks(world, p, Color.WHITE, 4, 1.0)
	Fx.light(world, p, Color.WHITE, 1.0, 2.0, 0.2)
	Fx.damage_number(world, p, 1.0, false, 0)
	Fx.blood_spray(world, p, Vector3.UP, 4)
	Fx.blood_splat(world, p, 0.2)
	Fx.bolt(world, p, p + Vector3(1, 0, 0), Color.WHITE)
	preload("res://scripts/debris.gd").burst(world, Transform3D(Basis(), p), Vector3.ONE, Vector3.ONE * 0.2, Color.GRAY, 1, Vector3.ZERO, 0.5)


func _exit_tree() -> void:
	Settings.res_factor = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.listeners = []
	Sfx.duck(false)
	Engine.time_scale = 1.0
	get_tree().paused = false


func _on_settings() -> void:
	for v in _views:
		Settings.apply_viewport(v.viewport)
		(v.camera.attributes as CameraAttributesPractical).dof_blur_far_enabled = Settings.v("dof")
	_layout()


## A controller in use was unplugged: pause so nobody is left helpless.
func _on_joy_changed(device: int, connected: bool) -> void:
	if connected or _results != null or match_over:
		return
	for p in players:
		if not p.is_bot and p.brain.device == device:
			_pause_note = "%s's controller disconnected" % p.pname
			if not _paused and countdown <= 0.0:
				_set_paused(true)
			return


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _kb_brain != null and not _paused:
		_kb_brain.mouse_accum += event.relative


func _edge(key: String, now: bool) -> bool:
	var was: bool = _prev.get(key, true)
	_prev[key] = now
	return now and not was


# --------------------------------------------------------------------------
# Splitscreen
# --------------------------------------------------------------------------

func _build_views() -> void:
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var bg := ColorRect.new()
	bg.color = UiKit.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)

	var viewers: Array = []
	for i in players.size():
		if players[i].wants_view:
			viewers.append(players[i])
	var cells := _grid(viewers.size()).x * _grid(viewers.size()).y
	for i in cells:
		_add_view(viewers[i] if i < viewers.size() else null)
	_layout()


func _grid(n: int) -> Vector2i:
	if n <= 1:
		return Vector2i(1, 1)
	if n == 2:
		return Vector2i(1, 2)
	if n <= 4:
		return Vector2i(2, 2)
	return Vector2i(3, 2)


func _add_view(player) -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Give the cell a real size before its viewport exists: post-processing
	# buffers (glow, blur) cannot be created for a 2x2 viewport.
	container.size = get_viewport().get_visible_rect().size / 3.0
	_ui.add_child(container)
	var vp := SubViewport.new()
	vp.size = Vector2i(container.size)
	Settings.apply_viewport(vp)
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(vp)

	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.near = 0.06
	cam.far = 400.0
	# Soft focus in the distance: the toy-diorama look (option "dof").
	var lens := CameraAttributesPractical.new()
	lens.dof_blur_far_enabled = Settings.v("dof")
	lens.dof_blur_far_distance = 34.0
	lens.dof_blur_far_transition = 70.0
	lens.dof_blur_amount = 0.045
	cam.attributes = lens
	var all_bodies := 0
	for p in players:
		all_bodies |= p.body_layer_bit()
	var gun = null
	if player != null:
		cam.cull_mask = 1 | (all_bodies & ~player.body_layer_bit()) | player.viewmodel_layer_bit()
		gun = Viewmodel.new()
		cam.add_child(gun)
		gun.build(player.color, player.viewmodel_layer_bit(), player.weapon)
		player.viewmodel = gun
	else:
		cam.cull_mask = 1 | all_bodies
	vp.add_child(cam)
	cam.current = true

	var layer := CanvasLayer.new()
	layer.layer = 0
	vp.add_child(layer)
	var blur := MotionBlur.new()
	layer.add_child(blur)
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 1
	vp.add_child(hud_layer)
	if player != null:
		player.has_view = true
	var hud = Hud.new()
	hud.player = player
	hud.game = self
	hud_layer.add_child(hud)
	var view := {"container": container, "viewport": vp, "camera": cam, "gun": gun, "blur": blur, "player": player, "fov": 70.0,
		"scope_vp": null, "scope_cam": null}
	_views.append(view)


## A second camera rendering a magnified view for a scope's lens.
func _ensure_scope(v: Dictionary) -> void:
	if v.scope_vp != null:
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(384, 384)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Settings.apply_viewport(vp)
	vp.scaling_3d_scale = 1.0
	add_child(vp)
	var c := Camera3D.new()
	c.near = 0.3
	c.far = 400.0
	c.cull_mask = v.camera.cull_mask & ~v.player.viewmodel_layer_bit()
	c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vp.add_child(c)
	c.current = true
	v.scope_vp = vp
	v.scope_cam = c
	v.gun.scope_texture = vp.get_texture()


func _layout() -> void:
	if _views.is_empty():
		return
	var total: Vector2 = get_viewport().get_visible_rect().size
	var grid := _grid(_views.size())
	var cell := Vector2(total.x / grid.x, total.y / grid.y)
	for i in _views.size():
		var v: Dictionary = _views[i]
		var gx := i % grid.x
		var gy := i / grid.x
		var gap := 4.0 if _views.size() > 1 else 0.0
		v.container.position = Vector2(gx, gy) * cell + Vector2(gap, gap) * 0.5
		v.container.size = cell - Vector2(gap, gap)
		# Keep the chosen horizontal FOV whatever the cell's aspect ratio.
		var aspect := cell.x / cell.y
		var half_h: float = deg_to_rad(Settings.v("fov") * 0.5)
		var vfov := rad_to_deg(2.0 * atan(tan(half_h) / aspect))
		v.fov = clampf(vfov, 50.0, 82.0)
		v.camera.fov = v.fov


func _update_cameras(delta: float) -> void:
	var ears: Array = []
	var shake_amount: float = Settings.v("shake")
	var bob_scale: float = Settings.v("bob")
	for v in _views:
		var p = v.player
		var cam: Camera3D = v.camera
		if p == null:
			var a := time * 0.1
			if map.indoor:
				cam.look_at_from_position(Vector3(cos(a) * map.half_x * 0.6, 7.5, sin(a) * map.half_z * 0.6), Vector3(0, 2.0, 0))
			else:
				cam.look_at_from_position(Vector3(cos(a) * map.half_x * 1.2, map.half_x * 0.55, sin(a) * map.half_z * 1.35), Vector3(0, 1.5, 0))
			v.blur.track(cam)
			continue
		if p.alive and p.vehicle != null:
			_vehicle_camera(v, p, delta)
		elif p.alive:
			# Head bob, strafe lean and recoil kick on top of the raw view.
			var hip: float = 1.0 - p.aim_amount
			var amt: float = p.bob_amount * bob_scale * (0.25 + 0.75 * hip)
			var ph: float = p.bob_phase
			var eye: Vector3 = p.get_global_transform_interpolated().origin + Vector3(0, p.eye_height() - 0.6 * p.crouch_amount * p.stats.size - p.land_dip * 0.16 + sin(ph * 2.0) * 0.024 * amt, 0)
			eye += Basis(Vector3.UP, p.yaw) * Vector3(cos(ph) * 0.02 * amt, 0, 0)
			var sh: float = p.shake * p.shake * 0.035 * shake_amount
			var kick: float = p.recoil * clampf(p.stats.recoil_kick, 0.4, 3.0) * 0.011
			var euler := Vector3(
				p.pitch + kick + sin(ph * 2.0) * 0.004 * amt + sin(time * 61.0) * sh,
				p.yaw + sin(time * 47.0 + 1.3) * sh,
				-p.strafe_amount * 0.028 * bob_scale + p.wall_tilt * 0.16 + (0.05 if p.sliding > 0.0 else 0.0) + cos(ph) * 0.005 * amt + sin(time * 53.0 + 2.1) * sh * 0.8)
			cam.global_transform = Transform3D(Basis.from_euler(euler), eye)
			# Taunting pulls the camera out in front of the character.
			var tv: float = 1.0 if (_debug_third and p.index == 0) else p.taunt_view
			var own_bit: int = p.body_layer_bit()
			if tv > 0.01:
				var feet: Vector3 = p.get_global_transform_interpolated().origin
				var look_at: Vector3 = feet + Vector3(0, 1.05 * p.stats.size, 0)
				var want: Vector3 = feet + Basis(Vector3.UP, p.yaw) * Vector3(0.9, 1.7, -3.3) * p.stats.size
				var tq := PhysicsRayQueryParameters3D.create(look_at, want, 1)
				var th := cam.get_world_3d().direct_space_state.intersect_ray(tq)
				if th:
					want = th.position + (look_at - want).normalized() * 0.3
				var third := Transform3D(Basis.looking_at(look_at - want), want)
				cam.global_transform = cam.global_transform.interpolate_with(third, smoothstep(0.0, 1.0, tv))
				cam.cull_mask |= own_bit
			elif cam.cull_mask & own_bit:
				cam.cull_mask &= ~own_bit
			# Aim-down-sights zoom narrows the FOV; dashing widens it briefly.
			var zoomed := rad_to_deg(2.0 * atan(tan(deg_to_rad(v.fov) * 0.5) * p.zoom_factor()))
			cam.fov = zoomed + (p.fov_kick * 7.0 + (6.0 if p.sliding > 0.0 else 0.0) + (4.0 if p.wallrun > 0.0 else 0.0)) * hip
			var need_scope: bool = p.stats.scope > 1.0 and p.stats.zoom >= 0.5
			if need_scope:
				_ensure_scope(v)
			if v.scope_vp != null:
				var active: bool = need_scope and p.aim_amount > 0.05
				v.scope_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
				if active:
					v.scope_cam.global_transform = cam.global_transform
					v.scope_cam.fov = cam.fov / p.stats.scope
		else:
			# Death cam: drift up and tilt away.
			cam.global_position += Vector3(0, delta * 0.5, 0)
			cam.rotation.x = lerpf(cam.rotation.x, -0.5, clampf(delta * 0.8, 0.0, 1.0))
		v.gun.update(delta, p)
		v.blur.track(cam)
		if p.vehicle != null or p.picking or p.taunt_view > 0.05 or (_debug_third and p.index == 0):
			v.gun.visible = false
		ears.append(cam.global_position)
	Sfx.listeners = ears


## Third-person chase camera while driving or flying; the view direction is
## the player's yaw/pitch (the vehicle aims where the camera looks).
func _vehicle_camera(v: Dictionary, p, delta: float) -> void:
	var veh = p.vehicle
	var cam: Camera3D = v.camera
	var pivot: Vector3 = veh.get_global_transform_interpolated().origin + Vector3(0, veh.cam_height, 0)
	var pitch: float = p.pitch * 0.85 - 0.12
	var basis := Basis.from_euler(Vector3(pitch, p.yaw, 0.0))
	var want: Vector3 = pivot + basis * Vector3(0, 0.4, veh.cam_dist)
	var q := PhysicsRayQueryParameters3D.create(pivot, want, 1)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		want = hit.position + (pivot - want).normalized() * 0.4
	var sh: float = p.shake * p.shake * 0.05 * Settings.v("shake")
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(pitch + sin(time * 61.0) * sh, p.yaw, 0.0)), want)
	var zoom: float = 0.55 if p.brain.aim and veh.can_zoom else 1.0
	cam.fov = lerpf(cam.fov, rad_to_deg(2.0 * atan(tan(deg_to_rad(v.fov + 6.0) * 0.5) * zoom)), clampf(delta * 10.0, 0.0, 1.0))


# --------------------------------------------------------------------------
# Overlays: pause menu and screen fade (drawn above the splitscreen cells)
# --------------------------------------------------------------------------

func _build_overlays() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var sh := Shader.new()
	sh.code = Hud.BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("amount", 1.0)
	_pause_ui = ColorRect.new()
	_pause_ui.material = mat
	_pause_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_ui.visible = false
	layer.add_child(_pause_ui)
	var menu := Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_ui.add_child(menu)
	menu.draw.connect(_draw_pause.bind(menu))
	_options = SettingsMenu.new()
	layer.add_child(_options)
	_options.closed.connect(func(): _prev.clear())

	_fade = ColorRect.new()
	_fade.color = Color(UiKit.INK, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.5)


func _draw_pause(menu: Control) -> void:
	var w := menu.size.x
	var h := menu.size.y
	var s := h / 1080.0
	if _options.visible:
		return
	var r := Rect2(w * 0.5 - 330 * s, h * 0.5 - 310 * s, 660 * s, 620 * s)
	UiKit.card(menu, r, UiKit.PANEL, 50 * s, s * 2.0)
	UiKit.text(menu, Vector2(r.position.x, r.position.y + 120 * s), "PAUSED", 96 * s, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 700, 0.14)
	if _pause_note != "":
		UiKit.text(menu, Vector2(r.position.x, r.position.y - 30 * s), _pause_note, 34 * s, Color(1.0, 0.55, 0.5), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 700, 0.16)
	var items := ["RESUME", "OPTIONS", "QUIT TO LOBBY"]
	for i in items.size():
		var sel := i == _pause_sel
		var ir := Rect2(r.position.x + 70 * s, r.position.y + 190 * s + i * 120 * s, r.size.x - 140 * s, 92 * s)
		if sel:
			ir = ir.grow(6 * s + sin(time * 6.0) * 2 * s)
		UiKit.card(menu, ir, UiKit.GOLD if sel else Color(0.36, 0.3, 0.5), 46 * s, s * 1.5)
		UiKit.text(menu, Vector2(ir.position.x, ir.get_center().y + 17 * s), items[i], 48 * s, UiKit.INK if sel else UiKit.CREAM, HORIZONTAL_ALIGNMENT_CENTER, ir.size.x, 700, 0.0 if sel else 0.12)
	UiKit.text(menu, Vector2(r.position.x, r.end.y - 30 * s), "UP / DOWN  choose     A / ENTER  confirm", 22 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 500, 0.0)


func _set_paused(on: bool) -> void:
	_paused = on
	get_tree().paused = on
	_pause_ui.visible = on
	_pause_sel = 0
	if not on:
		_pause_note = ""
	Sfx.duck(on)
	if _kb_brain != null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	Sfx.play("tick", -6.0, 0.8 if on else 1.2)


func _poll_pause() -> void:
	if _options.visible:
		_pause_ui.get_child(0).queue_redraw()
		return
	var toggle := _edge("esc", Input.is_physical_key_pressed(KEY_ESCAPE))
	var up := _edge("k_up", Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W))
	var down := _edge("k_down", Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S))
	var accept := _edge("k_ok", Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE))
	var back := false
	for d in Input.get_connected_joypads():
		var k := "j%d" % d
		toggle = _edge(k + "start", Input.is_joy_button_pressed(d, JOY_BUTTON_START)) or toggle
		var sy := Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)
		up = _edge(k + "up", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP) or sy < -0.6) or up
		down = _edge(k + "down", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN) or sy > 0.6) or down
		accept = _edge(k + "a", Input.is_joy_button_pressed(d, JOY_BUTTON_A)) or accept
		back = _edge(k + "b", Input.is_joy_button_pressed(d, JOY_BUTTON_B)) or back
	if match_over or countdown > 0.0:
		return
	if not _paused:
		if toggle:
			_set_paused(true)
		return
	_pause_ui.get_child(0).queue_redraw()
	if toggle or back:
		_set_paused(false)
		return
	if up or down:
		_pause_sel = posmod(_pause_sel + (1 if down else -1), 3)
		Sfx.play("tick", -8.0)
	if accept:
		if _pause_sel == 0:
			_set_paused(false)
		elif _pause_sel == 1:
			_options.open()
		else:
			_set_paused(false)
			_leave()


# --------------------------------------------------------------------------
# Main loop
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := (now - _last_usec) / 1000000.0
	_last_usec = now
	if _results != null:
		return
	_poll_pause()
	if _paused:
		return
	time += delta

	if countdown > 0.0:
		countdown -= delta
		var c := ceili(countdown)
		if c != _last_count and c <= 3 and c >= 1:
			Sfx.play("count", -4.0)
		_last_count = c
		if countdown <= 0.0:
			frozen = false
			go_flash = 1.0
			Sfx.play("go", -3.0)
	go_flash = maxf(0.0, go_flash - delta * 0.9)
	_update_cameras(delta)
	_auto_resolution(real_delta)

	if match_over:
		end_real_time += real_delta
		if end_real_time > 2.8 and _results == null and _fade.color.a <= 0.0:
			var tw := create_tween()
			tw.set_ignore_time_scale(true)
			tw.tween_property(_fade, "color:a", 1.0, 0.35)
			tw.tween_callback(_show_results)
			tw.tween_property(_fade, "color:a", 0.0, 0.4)


## Auto resolution (option "auto_res"): hold the frame rate by trading 3D
## resolution. It watches the GPU time of every splitscreen view (and the
## real frame time as a back-stop); when a frame is in danger of missing
## 60 FPS the internal resolution of the 3D views drops a step (FSR 1
## upscales it back; HUD and text stay sharp), and it climbs back when
## there is headroom again. Settings.res_factor carries the result.
func _auto_resolution(real_delta: float) -> void:
	if not Settings.v("auto_res"):
		if Settings.res_factor != 1.0:
			Settings.res_factor = 1.0
			_on_settings()
		return
	if not _res_measuring:
		_res_measuring = true
		for v in _views:
			RenderingServer.viewport_set_measure_render_time(v.viewport.get_viewport_rid(), true)
	var gpu := 0.0
	for v in _views:
		var rid: RID = v.viewport.get_viewport_rid()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_res_gpu = lerpf(_res_gpu, gpu, 0.12)
	_res_frame = lerpf(_res_frame, minf(real_delta, 0.1) * 1000.0, 0.12)
	_res_t -= real_delta
	if _res_t > 0.0 or _paused:
		return
	_res_t = 0.3
	# GPU budget for the 3D views: 14 of the 16.7 ms a 60 FPS frame has.
	var budget := 14.0
	var refresh := DisplayServer.screen_get_refresh_rate()
	var late: bool = _res_frame > 18.2 and (refresh <= 0.0 or refresh >= 55.0) and Engine.max_fps != 30
	var f: float = Settings.res_factor
	if _res_gpu > budget or late:
		f = maxf(0.5, f - (0.1 if _res_gpu > budget * 1.4 else 0.05))
	elif _res_gpu < budget * 0.62 and f < 1.0:
		f = minf(1.0, f + 0.05)
	if not is_equal_approx(f, Settings.res_factor):
		Settings.res_factor = f
		for v in _views:
			Settings.apply_viewport(v.viewport)


func _leave() -> void:
	set_process(false)
	finished.emit()


## Swap the match world for the podium screen.
func _show_results() -> void:
	Engine.time_scale = 1.0
	var rows: Array = []
	for p in ranked():
		if p.is_bot and p.index >= 6:
			continue
		rows.append({"name": p.pname, "color": p.color, "kind": p.kind, "hat": p.hat, "face": p.face, "back": p.back, "kills": p.kills, "deaths": p.deaths, "cards": p.cards.size(), "team": p.team})
	var title := ""
	if rules != null:
		title = rules.results_title()
	_views.clear()
	players.clear()
	_ui.queue_free()
	world.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.listeners = []
	_results = Results.new()
	_results.rows = rows
	_results.title = title
	add_child(_results)
	move_child(_results, 0)
	_results.done.connect(func(): finished.emit())


# --------------------------------------------------------------------------
# Rules
# --------------------------------------------------------------------------

func _yaw_to_centre(pos: Vector3) -> float:
	return atan2(pos.x, pos.z)


func on_player_died(victim, attacker) -> void:
	var credited: bool = attacker != null and is_instance_valid(attacker) and attacker != victim and is_player(attacker)
	if rules != null:
		if credited and is_enemy(attacker, victim):
			_credit(attacker, victim)
		else:
			var k = attacker if attacker != null and is_instance_valid(attacker) and attacker != victim else null
			feed.push_front(_feed_entry(k, victim))
			if feed.size() > 5:
				feed.pop_back()
		rules.on_died(victim, attacker)
		return
	if credited:
		attacker.kills += 1
		attacker.kill_flash = 1.0
		attacker.kill_name = victim.pname
		attacker.on_kill(victim)
		attacker.shake = maxf(attacker.shake, 0.4)
		if not attacker.is_bot and attacker.brain.device >= 0 and Settings.v("rumble"):
			Input.start_joy_vibration(attacker.brain.device, 0.2, 0.9, 0.25)
		feed.push_front(_feed_entry(attacker, victim))
		if attacker.kills >= kill_target:
			match_over = true
			frozen = true
			winner = attacker
			end_real_time = 0.0
			Engine.time_scale = 0.3
			Sfx.play("go", -2.0, 0.7)
	else:
		# Falling out of the world or blowing yourself up costs a point.
		victim.kills = maxi(0, victim.kills - 1)
		feed.push_front(_feed_entry(null, victim))
	if feed.size() > 5:
		feed.pop_back()


## Feed entries keep copies of the names/colours: zombies are freed soon after.
func _feed_entry(killer, victim) -> Dictionary:
	var k = null
	if killer != null and is_instance_valid(killer):
		k = {"pname": killer.pname, "color": killer.color, "kind": killer.kind}
	return {"killer": k, "victim": {"pname": victim.pname, "color": victim.color, "kind": victim.kind}, "t": time}


## Kill bookkeeping shared by the team modes (score, feed, rumble).
func _credit(attacker, victim) -> void:
	attacker.kills += 1
	attacker.kill_flash = 1.0
	attacker.kill_name = victim.pname
	attacker.on_kill(victim)
	attacker.shake = maxf(attacker.shake, 0.4)
	if not attacker.is_bot and attacker.brain.device >= 0 and Settings.v("rumble"):
		Input.start_joy_vibration(attacker.brain.device, 0.2, 0.9, 0.25)
	feed.push_front(_feed_entry(attacker, victim))
	if feed.size() > 5:
		feed.pop_back()


## A zombie (or any non-player actor) was destroyed by `attacker`.
func on_actor_killed(victim, attacker) -> void:
	if attacker != null and is_instance_valid(attacker) and is_player(attacker):
		_credit(attacker, victim)


## End the match now (rules call this): slow motion, then results.
func end_match(win = null) -> void:
	if match_over:
		return
	match_over = true
	frozen = true
	winner = win
	end_real_time = 0.0
	Engine.time_scale = 0.3
	Sfx.play("go", -2.0, 0.7)
	print("[match] over at %.0f s: %s" % [time, rules.results_title() if rules != null else "winner"])


func respawn_later(p, delay: float) -> void:
	get_tree().create_timer(delay, false).timeout.connect(func():
		if not match_over and is_instance_valid(p) and not p.alive:
			respawn(p))


## Everyone on a different spawn point (the free-for-all modes).
func spawn_all_default() -> void:
	var spots: Array = map.spawn_points.duplicate()
	spots.shuffle()
	for i in players.size():
		var pos: Vector3 = spots[i % spots.size()]
		players[i].spawn(pos, _yaw_to_centre(pos))


func respawn(p) -> void:
	if rules != null:
		rules.respawn(p)
		return
	respawn_default(p)


## Spawn as far from living enemies as possible (random among the best three).
func respawn_default(p) -> void:
	var scored: Array = []
	for spot in map.spawn_points:
		var nearest := 1e9
		for o in players:
			if o != p and o.alive:
				nearest = minf(nearest, o.global_position.distance_to(spot))
		scored.append([nearest, spot])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var pos: Vector3 = scored[randi() % mini(3, scored.size())][1]
	p.spawn(pos, _yaw_to_centre(pos))


func explode(pos: Vector3, radius: float, damage: float, shooter, direct_victim) -> void:
	Fx.flash(world, pos, Color(1.0, 0.6, 0.2, 0.85), radius * 0.25, radius, 0.3)
	Fx.flash(world, pos, Color(1.0, 0.95, 0.7, 0.95), radius * 0.1, radius * 0.55, 0.18)
	Fx.burst(world, pos, Color(1.0, 0.75, 0.3), 16, radius * 4.0, 0.4, 0.5, -6.0)
	Fx.puff(world, pos, Color(0.4, 0.36, 0.45, 0.7), 10, radius * 0.5)
	Fx.ring(world, pos, Color(1, 1, 1, 0.8), radius * 0.2, radius * 1.1, 0.3)
	Fx.sparks(world, pos, Color(1.0, 0.7, 0.3), 26, radius * 5.0, Vector3.UP, 180.0, 0.6)
	Fx.light(world, pos, Color(1.0, 0.65, 0.3), 8.0, radius * 4.0, 0.4)
	Sfx.play_at("boom", pos, -1.0)
	for p in players:
		if p.alive:
			var dp: float = p.global_position.distance_to(pos)
			p.shake = maxf(p.shake, clampf(1.2 - dp / (radius * 4.0), 0.0, 1.0))
	for prop in get_tree().get_nodes_in_group("props"):
		if not is_instance_valid(prop) or prop.is_queued_for_deletion():
			continue
		var away: Vector3 = prop.global_position - pos
		if away.length() < radius * 1.6:
			# Breakables take the blast (walls get theirs through knock()).
			if prop.has_method("hurt") and not prop.has_method("_collapse"):
				prop.hurt(damage * (1.0 - away.length() / (radius * 1.6)), shooter)
				if prop.is_queued_for_deletion():
					continue
			prop.knock((away.normalized() + Vector3(0, 0.6, 0)) * (1.0 - away.length() / (radius * 1.6)) * 14.0 * minf(prop.mass, 15.0), pos)
	for p in damageables():
		if not p.alive or p == direct_victim:
			continue
		var to_p: Vector3 = p.chest_position() - pos
		var d := to_p.length()
		if d > radius + (p.hit_radius() if p.has_method("hit_radius") else 0.5):
			continue
		var f := 1.0 - 0.6 * clampf(d / radius, 0.0, 1.0)
		if not p.has_method("seat_count"):
			p.velocity += (to_p.normalized() + Vector3(0, 0.4, 0)) * 9.0 * f
		p.take_damage(damage * f * (0.5 if p == shooter else 1.0), shooter)


## A blast a moment from now (fuel barrels: chains read as a chain).
func explode_later(pos: Vector3, radius: float, damage: float, shooter) -> void:
	get_tree().create_timer(0.1, false).timeout.connect(func():
		if true:
			explode(pos, radius, damage, shooter if shooter != null and is_instance_valid(shooter) else null, null))


func ranked() -> Array:
	var r: Array = players.duplicate()
	r.sort_custom(func(a, b): return a.kills > b.kills if a.kills != b.kills else a.deaths < b.deaths)
	return r


func leader():
	var best = null
	for p in players:
		if best == null or p.kills > best.kills:
			best = p
	return best


## Gamepad aim assist: slow the stick down while the crosshair is on an enemy.
func aim_friction(player) -> float:
	var eye: Vector3 = player.eye_position()
	var fwd: Vector3 = -player.aim_basis().z
	for p in hostiles(player):
		var to_p: Vector3 = p.chest_position() - eye
		var d := to_p.length()
		if d < 1.0 or d > 60.0:
			continue
		if fwd.angle_to(to_p) < atan(0.9 / d) + 0.015:
			return 0.45
	return 1.0


# --------------------------------------------------------------------------
# Teams and targets (used by bullets, explosions, bots, aim assist)
# --------------------------------------------------------------------------

func is_player(x) -> bool:
	return x != null and x.has_method("rebuild_stats")


## True when a and b may hurt each other. Team -1 is free-for-all.
func is_enemy(a, b) -> bool:
	if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
		return true
	if a == b:
		return false
	var ta: int = a.team
	var tb: int = b.team
	return ta < 0 or tb < 0 or ta != tb


## Everything bullets and explosions can hit: players on foot, zombies,
## vehicles. Cached for the physics frame.
func damageables() -> Array:
	var f := Engine.get_physics_frames()
	if f != _dmg_frame:
		_dmg_frame = f
		_dmg_cache = []
		for p in players:
			if p.vehicle == null:
				_dmg_cache.append(p)
		for a in actors:
			if is_instance_valid(a):
				_dmg_cache.append(a)
	return _dmg_cache


## Living things `who` should shoot at (empty vehicles are not threats).
func hostiles(who) -> Array:
	var out: Array = []
	for d in damageables():
		if d == who or not d.alive or not is_enemy(who, d):
			continue
		if d.has_method("seat_count") and d.driver == null:
			continue
		out.append(d)
	return out


## Weapon ids the current mode allows ([] = all of them).
func weapon_pool() -> Array:
	if rules != null and rules.has_method("weapon_pool"):
		return rules.weapon_pool()
	return []


## The hand of cards offered to `p` (after a KO, or between zombie waves).
func draw_cards(p) -> Array:
	var banned: Array = rules.banned_cards() if rules != null and rules.has_method("banned_cards") else []
	return Cards.draw(p.stats.card_draw, p.weapon, weapon_pool(), banned)


## Where a bot should head when it has nobody to fight (null = wander).
func bot_goal(p):
	if rules != null:
		return rules.bot_goal(p)
	return null


## A few dogs and cats wander every map (pet.gd); more on bigger maps.
func _spawn_pets() -> void:
	if "--pets-demo" in OS.get_cmdline_user_args():
		# Dev flag: one of each kind lined up in front of player 1.
		var p0 = players[0]
		for i in Pet.KINDS.size():
			var demo = Pet.new()
			demo.game = self
			demo.setup(i)
			world.add_child(demo)
			demo.global_position = p0.global_position + Basis(Vector3.UP, p0.yaw) * Vector3((i - 3.5) * 1.3, 0, -4.5)
			demo.rotation.y = p0.yaw
			pets.append(demo)
			if i % 2 == 0:
				demo.pet(p0)
		return
	var n := clampi(int(map.half_x * map.half_z / 300.0) + 2, 3, 9)
	for i in n:
		var pos: Vector3 = map.random_nav_point()
		if pos.y < -1.0:
			continue
		var pet = Pet.new()
		pet.game = self
		pet.setup(randi() % Pet.KINDS.size())
		world.add_child(pet)
		pet.global_position = pos
		pet.rotation.y = randf() * TAU
		pets.append(pet)


## The nearest pet within arm's reach of `p`, or null.
func pet_near(p):
	for pet in pets:
		if is_instance_valid(pet) and pet.global_position.distance_to(p.global_position) < 1.9:
			return pet
	return null


## A door within arm's reach of `p` (door.gd), or null.
func door_near(p):
	for d in get_tree().get_nodes_in_group("doors"):
		if not d.is_queued_for_deletion() and d.centre().distance_to(p.global_position + Vector3(0, 1.0, 0)) < 2.1:
			return d
	return null


## The closest free vehicle within reach of `p`, or null.
func vehicle_near(p):
	var best = null
	var best_d := 1.2
	for v in vehicles:
		if not is_instance_valid(v) or not v.alive or v.driver != null:
			continue
		var d: float = v.global_position.distance_to(p.global_position) - v.enter_radius
		if d < best_d:
			best_d = d
			best = v
	return best
