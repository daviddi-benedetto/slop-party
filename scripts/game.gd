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
##            "map": int, "theme": String (looks.gd key or "random"), "teams": "versus" | "coop" }

signal finished

const Player = preload("res://scripts/player.gd")
const Map = preload("res://scripts/map.gd")
const Hud = preload("res://scripts/hud.gd")
const InputSource = preload("res://scripts/input_source.gd")
const BotBrain = preload("res://scripts/bot_brain.gd")
const Fx = preload("res://scripts/fx.gd")
const Gore = preload("res://scripts/gore.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Viewmodel = preload("res://scripts/viewmodel.gd")
const MotionBlur = preload("res://scripts/motion_blur.gd")
const SunRays = preload("res://scripts/sun_rays.gd")
const Results = preload("res://scripts/results.gd")
const SettingsMenu = preload("res://scripts/settings_menu.gd")
const Pickup = preload("res://scripts/pickup.gd")
const Cards = preload("res://scripts/cards.gd")
const Zombies = preload("res://scripts/zombies.gd")
const Frontline = preload("res://scripts/frontline.gd")
const Racing = preload("res://scripts/racing.gd")
const Pet = preload("res://scripts/pet.gd")

const GunGame = preload("res://scripts/gungame.gd")
const Medieval = preload("res://scripts/medieval.gd")

const MODES := ["rounds", "zombies", "frontline", "gungame", "medieval", "racing"]
const MODE_NAMES := {"rounds": "ROUNDS", "zombies": "ZOMBIES", "frontline": "FRONTLINE", "gungame": "GUN GAME", "medieval": "MEDIEVAL", "racing": "RACING"}

var config := {}
var world: Node3D
var map
var _look := {}               # the visual theme in play (looks.gd entry; for the results stage)
var players: Array = []
var kill_target := 15
var match_over := false
var _debug_top := false
var _balance = null           # dev flag --balance: tools/balance.gd
var _debug_eye: Array = []
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
var _pause_opened := 0         # Time.get_ticks_msec() when the pause menu opened (pop-in)
var _pause_hits: Array = []    # screen rects of the pause menu items (mouse)
var _options
var _fade        # wipe.gd: a theme-coloured curtain driven like a fade (color:a)
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
	_debug_top = "--top" in OS.get_cmdline_user_args()
	if "--balance" in OS.get_cmdline_user_args():
		# Dev: weapon / card statistics for tools/balance.py.
		_balance = load("res://tools/balance.gd").new()
		_balance.game = self
		add_child(_balance)
	for a in OS.get_cmdline_user_args():
		# Dev flag --eye=x,y,z,tx,ty,tz: a fixed spectator camera (interiors).
		if a.begins_with("--eye="):
			var v := a.trim_prefix("--eye=").split_floats(",")
			if v.size() == 6:
				_debug_eye = [Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5])]
	world = Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	map = Map.new()
	world.add_child(map)
	var map_i: int = config.get("map", 0)
	if mode == "zombies":
		map_i = Map.ZOMBIE
	elif mode == "frontline":
		map_i = map_i if map_i in Map.FRONT_MAPS else Map.FRONTLINE
	elif mode == "medieval":
		map_i = Map.CASTLE
	elif mode == "racing":
		map_i = Map.RACEWAY
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
	elif mode == "racing":
		rules = Racing.new()
	map.build(map_i, str(config.get("theme", config.get("time", "random"))))
	_look = map.look
	UiKit.use_theme(_look)

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
			# Each player's own look speed (Options > Controls: Player N look
			# speed, 5 = just the global gamepad / mouse speed).
			var pn: int = clampi(int(part.get("pnum", i + 1)), 1, 6)
			p.brain.sens = 0.4 + 0.12 * float(Settings.v("look_p%d" % pn))
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
	Settings.view_count = maxi(1, _views.size())
	map._on_settings()
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
		if mode == "rounds":
			_spawn_ffa_vehicles()
	map.nav_built.connect(_spawn_pets)
	var pads: bool = rules == null or not rules.has_method("weapon_pads") or rules.weapon_pads()
	if pads:
		map.nav_built.connect(_scatter_boxes)
	map.build_nav()
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
	Fx.smoke(world, p, 0.2)
	Fx.fireball(world, p, 0.2, 2)
	Fx.smoke_column(world, p, 0.2, Color(0.2, 0.2, 0.2), 2)
	Fx.embers(world, p, 0.2, 2)
	Fx.dust_ring(world, p, 0.2)
	Fx.fire_patch(world, p, 0.3, 0.5, false)
	Gore.spray(world, p, Vector3.UP, 4, 1.0)
	Gore.splat(world, p, Vector3.UP, 0.1)
	Gore.gib(world, p, "meat", {}, Vector3.UP, 0.0)
	Fx.decal(world, p, Vector3.UP, "hole", 0.2)
	Fx.decal(world, p, Vector3.UP, "scorch", 0.2)
	preload("res://scripts/debris.gd").burst(world, Transform3D(Basis(), p), Vector3.ONE, Vector3.ONE * 0.2, Color.GRAY, 1, Vector3.ZERO, 0.5)


func _exit_tree() -> void:
	Settings.res_factor = 1.0
	Settings.view_count = 1
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
	UiKit.reset_pads()
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
	# The pause menu answers the mouse: hover picks, click chooses.
	if _paused and not _options.visible and not match_over:
		var at := -1
		if event is InputEventMouse:
			for i in _pause_hits.size():
				if (_pause_hits[i] as Rect2).has_point(event.position):
					at = i
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if at >= 0 else Input.CURSOR_ARROW)
		if event is InputEventMouseMotion and at >= 0 and at != _pause_sel:
			_pause_sel = at
			Sfx.play("tick", -12.0)
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT and at >= 0:
				_pause_sel = at
				_pause_choose()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_set_paused(false)


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
	var best := _grid_169(n)
	# Wide screens (ultrawide 21:9, 32:9): pick the split whose cells come
	# closest to a 16:9 shape, e.g. two players side by side instead of two
	# letterbox strips. On a 16:9 screen this keeps the usual layouts.
	var total: Vector2 = get_viewport().get_visible_rect().size
	if n > 1 and total.y > 0.0:
		var score := func(g: Vector2i) -> float: return absf(log((total.x / g.x) / (total.y / g.y) / (16.0 / 9.0)))
		var best_s: float = score.call(best)
		for cols in range(1, n + 1):
			var rows := ceili(float(n) / cols)
			var g := Vector2i(cols, rows)
			if cols * rows - n >= mini(cols, rows):
				continue             # a whole empty row / column
			var sg: float = score.call(g)
			if sg < best_s - 0.05:
				best = g
				best_s = sg
	return best


func _grid_169(n: int) -> Vector2i:
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
	cam.far = 1200.0             # the horizon ring (map._horizon) is up to ~700 m away
	# Soft focus in the distance: the toy-diorama look (option "dof").
	var lens := CameraAttributesPractical.new()
	lens.dof_blur_far_enabled = Settings.v("dof")
	lens.dof_blur_far_distance = 40.0
	lens.dof_blur_far_transition = 30.0
	lens.dof_blur_amount = 0.085
	cam.attributes = lens
	var all_bodies := 0
	for p in players:
		all_bodies |= p.body_layer_bit()
	var gun = null
	if player != null:
		cam.cull_mask = 1 | (all_bodies & ~player.body_layer_bit()) | player.viewmodel_layer_bit()
		gun = Viewmodel.new()
		cam.add_child(gun)
		gun.kind = player.kind
		gun.build(player.color, player.viewmodel_layer_bit(), player.weapon)
		player.viewmodel = gun
	else:
		cam.cull_mask = 1 | all_bodies
	vp.add_child(cam)
	cam.current = true
	# Sun rays: a full-screen quad only this camera draws (its own layer).
	var rays = SunRays.new()
	rays.layers = 1 << (15 + _views.size())   # bits 15-20: one per view
	cam.cull_mask |= rays.layers
	cam.add_child(rays)
	var ink = preload("res://scripts/outline.gd").new()
	ink.layers = rays.layers
	cam.add_child(ink)

	var layer := CanvasLayer.new()
	layer.layer = 0
	vp.add_child(layer)
	var blur := MotionBlur.new()
	layer.add_child(blur)
	var sfx = preload("res://scripts/screen_fx.gd").new()
	layer.add_child(sfx)
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 1
	vp.add_child(hud_layer)
	if player != null:
		player.has_view = true
	var hud = Hud.new()
	hud.player = player
	hud.game = self
	hud_layer.add_child(hud)
	var view := {"container": container, "viewport": vp, "camera": cam, "gun": gun, "blur": blur, "rays": rays, "ink": ink, "sfx": sfx, "player": player, "fov": 70.0,
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
	c.far = 1200.0
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
		# Keep the chosen horizontal FOV whatever the cell's aspect ratio...
		var aspect := cell.x / cell.y
		var half_h: float = deg_to_rad(Settings.v("fov") * 0.5)
		# ...except on a screen wider than 16:9 (ultrawide), where the extra
		# width shows more to the sides instead of cropping the top and
		# bottom ("Hor+"), up to 125 degrees across.
		var screen_aspect := total.x / maxf(1.0, total.y)
		if screen_aspect > 16.0 / 9.0 + 0.01:
			half_h = minf(deg_to_rad(62.5), atan(tan(half_h) * screen_aspect / (16.0 / 9.0)))
		var vfov := rad_to_deg(2.0 * atan(tan(half_h) / aspect))
		v.fov = clampf(vfov, 50.0, 82.0)
		v.camera.fov = v.fov


func _update_cameras(delta: float) -> void:
	var ears: Array = []
	var ear_yaws: Array = []
	var shake_amount: float = Settings.v("shake")
	var to_sun: Vector3 = map.sun_direction()
	var ray_power: float = 0.0 if map.indoor else {"day": 0.55, "sunset": 0.95, "night": 0.3}.get(map.time, 0.5)
	for v in _views:
		v.rays.aim(v.camera, to_sun, map.sun_color(), ray_power, delta)
	var bob_scale: float = Settings.v("bob")
	for v in _views:
		var p = v.player
		var cam: Camera3D = v.camera
		if p == null:
			var a := time * 0.1
			if not _debug_eye.is_empty():
				cam.look_at_from_position(_debug_eye[0], _debug_eye[1])
				(cam.attributes as CameraAttributesPractical).dof_blur_far_enabled = false
			elif _debug_top:
				# Dev flag --top: a fixed overhead view of the whole map.
				cam.look_at_from_position(Vector3(0, maxf(map.half_x * 1.05, map.half_z * 1.75), map.half_z * 0.45), Vector3(0, 0, 0))
				cam.far = 900.0
				(cam.attributes as CameraAttributesPractical).dof_blur_far_enabled = false
			elif map.indoor:
				cam.look_at_from_position(Vector3(cos(a) * map.half_x * 0.6, 7.5, sin(a) * map.half_z * 0.6), Vector3(0, 2.0, 0))
			else:
				cam.look_at_from_position(Vector3(cos(a) * map.half_x * 1.2, map.half_x * 0.55, sin(a) * map.half_z * 1.35), Vector3(0, 1.5, 0))
			v.blur.track(cam)
			if not _debug_top and _debug_eye.is_empty():
				_focus(cam, delta)
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
				-p.strafe_amount * 0.028 * bob_scale - p.flinch * 0.045 * shake_amount + p.wall_tilt * 0.16 + (0.05 if p.sliding > 0.0 else 0.0) + cos(ph) * 0.005 * amt + sin(time * 53.0 + 2.1) * sh * 0.8)
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
			# A KO punches the view in a touch.
			var punch: float = maxf(0.0, p.kill_flash - 0.8) / 0.2 * 3.5 * shake_amount
			cam.fov = zoomed - punch + (p.fov_kick * 7.0 + p.sprint_amount * 5.0 + (6.0 if p.sliding > 0.0 else 0.0) + (4.0 if p.wallrun > 0.0 else 0.0)) * hip
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
			# Death cam: rise a little and turn to face whoever got you, so
			# you see where the shot came from; otherwise tilt down.
			cam.global_position += Vector3(0, delta * 0.4, 0)
			var kp = p.killer
			var target := Vector3.ZERO
			if kp != null and is_instance_valid(kp) and kp.alive:
				target = kp.get_global_transform_interpolated().origin + Vector3(0, 1.0, 0)
			if target != Vector3.ZERO and target.distance_to(cam.global_position) > 1.0:
				var face := Basis.looking_at(target - cam.global_position, Vector3.UP)
				cam.global_transform.basis = cam.global_transform.basis.orthonormalized().slerp(face.orthonormalized(), clampf(delta * 3.5, 0.0, 1.0)).orthonormalized()
			else:
				cam.rotation.x = lerpf(cam.rotation.x, -0.5, clampf(delta * 0.8, 0.0, 1.0))
		v.gun.update(delta, p)
		# Screen effects: speed blur, blast zoom, hurt fringing.
		var spd: float = 0.0
		if p.alive:
			spd = maxf(p.fov_kick, 1.0 if p.sliding > 0.0 else 0.0) * 0.8
		p.blast_blur = maxf(0.0, p.blast_blur - delta * 2.5)
		var hurt_fx: float = 0.0
		if p.alive and p.health < p.stats.max_health * 0.3:
			hurt_fx = 0.5 + 0.5 * sin(time * 5.0)
		v.sfx.set_fx(spd, p.blast_blur, maxf(hurt_fx, p.hurt_flash * 0.6) if p.alive else 0.0)
		v.blur.track(cam)
		_focus(cam, delta)
		if p.vehicle != null or p.picking or p.taunt_view > 0.05 or (_debug_third and p.index == 0):
			v.gun.visible = false
		ears.append(cam.global_position)
		ear_yaws.append(cam.global_rotation.y)
	Sfx.listeners = ears
	Sfx.listener_yaws = ear_yaws


## Third-person chase camera while driving or flying; the view direction is
## the player's yaw/pitch (the vehicle aims where the camera looks).
func _vehicle_camera(v: Dictionary, p, delta: float) -> void:
	var veh = p.vehicle
	var cam: Camera3D = v.camera
	var vyaw: float = veh.get_global_transform_interpolated().basis.get_euler().y
	# Unarmed ground vehicles (rides, race cars): the view swings round behind
	# the car on its own; with a gun the camera is also your aim, so it stays.
	if not veh.armed and veh.type != "heli":
		var follow := 6.0 if p.fp_drive else (2.2 if absf(veh._speed) > 3.0 else 0.4)
		p.yaw = lerp_angle(p.yaw, vyaw, clampf(delta * follow, 0.0, 1.0))
	if p.fp_drive:
		# First person from the seat; you can still look around.
		var seat: Vector3 = veh.get_global_transform_interpolated() * veh.SEATS.get(veh.type, Vector3(0, 1.6, 0))
		var fp_pitch: float = p.pitch * 0.85
		var sh2: float = p.shake * p.shake * 0.05 * Settings.v("shake")
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(fp_pitch + sin(time * 61.0) * sh2, p.yaw, 0.0)), seat)
		var zoom2: float = 0.55 if p.brain.aim and veh.can_zoom else 1.0
		cam.fov = lerpf(cam.fov, rad_to_deg(2.0 * atan(tan(deg_to_rad(v.fov + 4.0) * 0.5) * zoom2)), clampf(delta * 10.0, 0.0, 1.0))
		return
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

	_fade = preload("res://scripts/wipe.gd").new()
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
	# Real time: the match clock is stopped while paused.
	var rt := (Time.get_ticks_msec() - _pause_opened) / 1000.0
	var pop := UiKit.back_out(clampf(rt / 0.3, 0.0, 1.0))
	menu.draw_set_transform(Vector2(w, h) * 0.5, 0.0, Vector2.ONE * (0.85 + 0.15 * pop))
	var r := Rect2(-330 * s, -330 * s, 660 * s, 660 * s)
	UiKit.card(menu, r, Color(UiKit.PANEL, UiKit.PANEL.a * pop), 50 * s, s * 2.0)
	UiKit.panel(menu, Rect2(r.position + Vector2(14, 12) * s, Vector2(r.size.x - 28 * s, 120 * s)), Color(1, 1, 1, 0.06 * pop), 38 * s)
	UiKit.text(menu, Vector2(r.position.x, r.position.y + 112 * s), "PAUSED", 96 * s, Color(UiKit.GOLD, pop), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 700, 0.14)
	var info: String = (map.label() if mode == "frontline" else MODE_NAMES[mode] + "  -  " + map.label())
	UiKit.text(menu, Vector2(r.position.x, r.position.y + 160 * s), info, 24 * s, Color(UiKit.ACCENT.lerp(Color.WHITE, 0.4), pop), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 700, 0.1)
	if _pause_note != "":
		UiKit.text(menu, Vector2(r.position.x, r.position.y - 30 * s), _pause_note, 34 * s, Color(1.0, 0.55, 0.5), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 700, 0.16)
	var items := ["RESUME", "OPTIONS", "QUIT TO LOBBY"]
	_pause_hits.clear()
	var mscale := 0.85 + 0.15 * pop
	for i in items.size():
		var sel := i == _pause_sel
		var ia := UiKit.back_out(clampf((rt - 0.08 - i * 0.05) / 0.3, 0.0, 1.0))
		var ir := Rect2(r.position.x + 70 * s + (1.0 - ia) * 60 * s, r.position.y + 196 * s + i * 112 * s, r.size.x - 140 * s, 88 * s)
		_pause_hits.append(Rect2(Vector2(w, h) * 0.5 + ir.position * mscale, ir.size * mscale))
		if sel:
			ir = ir.grow(6 * s + sin(rt * 6.0) * 2 * s)
		var idle := UiKit.PANEL.lerp(Color(0.5, 0.5, 0.6), 0.25)
		UiKit.card(menu, ir, Color(UiKit.GOLD if sel else idle, ia), 44 * s, s * 1.5)
		UiKit.text(menu, Vector2(ir.position.x, ir.get_center().y + 17 * s), items[i], 46 * s, Color(UiKit.INK if sel else UiKit.CREAM, ia), HORIZONTAL_ALIGNMENT_CENTER, ir.size.x, 700, 0.0 if sel else 0.12)
	# Standings at a glance.
	var top: Array = ranked()
	var n := mini(top.size(), 6)
	var cw := 92.0 * s
	var x0 := -cw * n * 0.5
	for i in n:
		var p = top[i]
		var cx := x0 + (i + 0.5) * cw
		UiKit.portrait(menu, Vector2(cx - 14 * s, r.end.y - 88 * s), 14 * s, p.color, p.kind)
		UiKit.num(menu, Vector2(cx + 4 * s, r.end.y - 78 * s), str(p.kills), 30 * s, UiKit.GOLD if i == 0 else Color.WHITE)
	var pad: bool = not Input.get_connected_joypads().is_empty()
	var px := r.position.x + r.size.x * 0.5 - 170 * s
	var py := r.end.y - 26 * s
	px += UiKit.prompt(menu, Vector2(px, py), "A" if pad else "ENTER", 24 * s, not pad) + 10 * s
	UiKit.text(menu, Vector2(px, py), "CHOOSE", 22 * s, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, -1, 700, 0.0)
	px += UiKit.text_width("CHOOSE", 22 * s) + 30 * s
	px += UiKit.prompt(menu, Vector2(px, py), "B" if pad else "ESC", 24 * s, not pad) + 10 * s
	UiKit.text(menu, Vector2(px, py), "RESUME", 22 * s, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, -1, 700, 0.0)
	menu.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _set_paused(on: bool) -> void:
	_paused = on
	get_tree().paused = on
	_pause_ui.visible = on
	_pause_sel = 0
	_pause_opened = Time.get_ticks_msec()
	if not on:
		_pause_note = ""
	Sfx.duck(on)
	if _kb_brain != null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	Sfx.play("tick", -6.0, 0.8 if on else 1.2)


func _poll_pause() -> void:
	if _paused:
		_pause_ui.get_child(0).queue_redraw()     # the menu animates in real time
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
		_pause_choose()


func _pause_choose() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
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


## Depth of field that follows the arena: the focus limit sits where this
## camera's view leaves the map, so everything you can fight stays sharp
## and the scenery beyond the boundary melts into a soft, far-away
## backdrop, whichever way you look and however big the map is. Looking
## along a long street the limit moves out; facing a nearby wall it comes
## in (smoothed, so it never pops).
func _focus(cam: Camera3D, delta: float) -> void:
	var lens := cam.attributes as CameraAttributesPractical
	if lens == null or not lens.dof_blur_far_enabled:
		return
	var pos := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var reach := 400.0
	if absf(fwd.x) > 0.001:
		reach = minf(reach, ((map.half_x + 1.5) * signf(fwd.x) - pos.x) / fwd.x)
	if absf(fwd.z) > 0.001:
		reach = minf(reach, ((map.half_z + 1.5) * signf(fwd.z) - pos.z) / fwd.z)
	# Indoors there is nothing beyond the walls worth blurring.
	var want := 400.0 if map.indoor else clampf(reach + 3.0, 16.0, 220.0)
	var k := clampf(delta * 3.5, 0.0, 1.0)
	lens.dof_blur_far_distance = lerpf(lens.dof_blur_far_distance, want, k)
	lens.dof_blur_far_transition = lerpf(lens.dof_blur_far_transition, 10.0 + want * 0.3, k)


## Auto resolution (option "auto_res"): hold the frame rate by trading 3D
## resolution. It watches the GPU time of every splitscreen view (and the
## real frame time as a back-stop); when a frame is in danger of missing
## 60 FPS the internal resolution of the 3D views drops a step (FSR 1
## upscales it back; HUD and text stay sharp), and it climbs back when
## there is headroom again. Settings.res_factor carries the result.
func _auto_resolution(real_delta: float) -> void:
	var floor_f: float = Settings.v("auto_res")
	if floor_f >= 1.0:
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
		f = maxf(floor_f, f - (0.1 if _res_gpu > budget * 1.4 else 0.05))
	elif _res_gpu < budget * 0.62 and f < 1.0 or f < floor_f:
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
		rows.append({"name": p.pname, "color": p.color, "kind": p.kind, "hat": p.hat, "face": p.face, "back": p.back, "kills": p.kills, "deaths": p.deaths, "cards": p.cards.size(), "team": p.team,
			"knife": p.knife_kills, "boxes": p.boxes_opened, "damage": roundi(p.damage_dealt), "streak": p.best_streak,
			"stats": rules.result_stats(p) if rules != null and rules.has_method("result_stats") else []})
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
	_results.look = _look
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
	if _balance != null:
		_balance.kill(attacker, victim)
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
	var wname := ""
	if killer != null and is_instance_valid(killer):
		k = {"pname": killer.pname, "color": killer.color, "kind": killer.kind}
		if killer.has_method("weapon_name"):
			# A melee KO with a gun in hand was the knife.
			wname = "Knife" if melee_strike and not killer.stats.melee_weapon else killer.weapon_name()
	return {"killer": k, "victim": {"pname": victim.pname, "color": victim.color, "kind": victim.kind}, "t": time, "weapon": wname}


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
	if Map.MAPS[map.map_index].size == "HUGE":
		# Frontline in free-for-all: start on the battlefield, not at the bases.
		var mid: Array = spots.filter(func(sp): return absf(sp.x) < 75.0)
		if mid.size() >= players.size():
			spots = mid
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
## On a huge map (Frontline in free-for-all) "as far as possible" is the other
## end of the world, so there it aims for a spot 30-45 m from the nearest enemy.
func respawn_default(p) -> void:
	var huge: bool = Map.MAPS[map.map_index].size == "HUGE"
	var scored: Array = []
	for spot in map.spawn_points:
		var nearest := 1e9
		for o in players:
			if o != p and o.alive:
				nearest = minf(nearest, o.global_position.distance_to(spot))
		var score := nearest
		if huge:
			score = -absf(clampf(nearest, 0.0, 200.0) - 38.0) if nearest > 18.0 else -1000.0 + nearest
		scored.append([score, spot])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var pos: Vector3 = scored[randi() % mini(3, scored.size())][1]
	p.spawn(pos, _yaw_to_centre(pos))


func explode(pos: Vector3, radius: float, damage: float, shooter, direct_victim) -> void:
	# Something blew up: a blinding flash, a rolling fireball, embers flung
	# out in streaks, a shock ring and a ring of dust along the ground, and a
	# column of black smoke that hangs around for a few seconds. Big blasts
	# leave a fire burning.
	var sz := clampf(radius / 3.0, 0.5, 2.0)
	# Many blasts at once (a rocket fight): lighter effects so it holds 60.
	var load := Fx.blast_load()
	var k := 1.0 if load <= 2 else (0.55 if load <= 4 else 0.3)
	Fx.flash(world, pos, Color(1.0, 0.95, 0.8, 0.9), radius * 0.12, radius * 0.5, 0.09)
	Fx.fireball(world, pos, sz, int((18 + 10 * sz) * k))
	Fx.embers(world, pos, sz, int((20 + 14 * sz) * k))
	Fx.ring(world, pos, Color(1, 0.95, 0.85, 0.8), radius * 0.2, radius * 1.3, 0.3)
	if k > 0.5:
		Fx.dust_ring(world, Vector3(pos.x, pos.y - 0.4, pos.z), sz)
	Fx.smoke_column(world, pos + Vector3(0, 0.5, 0), sz * 1.2, Color(0.12, 0.11, 0.12), int((14 + 8 * sz) * k))
	Fx.light(world, pos, Color(1.0, 0.6, 0.25), 10.0, radius * 4.5, 0.55, k > 0.5)
	if radius >= 3.0 and k > 0.5 and Fx.can_add_fire() and randf() < 0.45:
		var down := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -3.0, 0), 1)
		var gh := world.get_world_3d().direct_space_state.intersect_ray(down)
		if gh:
			Fx.fire_patch(world, gh.position, clampf(radius * 0.18, 0.4, 0.9), randf_range(3.0, 5.0))
	Fx.decal(world, pos, Vector3.UP, "scorch", radius * 1.5)
	Sfx.play_at("boom", pos, -1.0)
	for p in players:
		if p.alive:
			var dp: float = p.global_position.distance_to(pos)
			p.shake = maxf(p.shake, clampf(1.2 - dp / (radius * 4.0), 0.0, 1.0))
			p.blast_blur = maxf(p.blast_blur, clampf(1.0 - dp / (radius * 3.0), 0.0, 1.0))
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
			prop.knock((away.normalized() + Vector3(0, 0.6, 0)) * (1.0 - away.length() / (radius * 1.6)) * 260.0, pos)
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
		p.set_meta("blast_t", time)
		p.take_damage(damage * f * (0.5 if p == shooter else 1.0), shooter)


## A blast a moment from now (fuel barrels: chains read as a chain).
func explode_later(pos: Vector3, radius: float, damage: float, shooter) -> void:
	get_tree().create_timer(0.1, false).timeout.connect(func():
		if true:
			explode(pos, radius, damage, shooter if shooter != null and is_instance_valid(shooter) else null, null))


func ranked() -> Array:
	if rules != null and rules.has_method("ranked"):
		return rules.ranked()
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
## Extra mystery boxes on top of the map's own pads, so nobody is ever far
## from a new weapon: spread by farthest-point sampling over the bot nav
## graph (ground and upper floors alike), away from spawns, other pickups,
## doorways and stairs. Same spots every match on a map (no randomness).
const EXTRA_BOXES := {"SMALL": 4, "MEDIUM": 6, "LARGE": 8, "HUGE": 18}

func _scatter_boxes() -> void:
	var want: int = EXTRA_BOXES.get(Map.MAPS[map.map_index].size, 6)
	var taken: Array = []
	for spot in map.pickup_spots:
		taken.append(spot[1])
	var avoid: Array = map.spawn_points.duplicate()
	var space: PhysicsDirectSpaceState3D = map.get_world_3d().direct_space_state
	var cand: Array = []
	for id in map.nav.get_point_ids():
		var p: Vector3 = map.nav.get_point_position(id)
		if absf(p.x) > map.half_x - 3.0 or absf(p.z) > map.half_z - 3.0 or map._blocked(p, 1.3):
			continue
		var near_spawn := false
		for s in avoid:
			if (s as Vector3).distance_to(p) < 6.0:
				near_spawn = true
				break
		if near_spawn:
			continue
		# Level, solid floor with room for the box (not a stair or a slope).
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0), p + Vector3(0, -0.6, 0), 1)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty() or hit.normal.y < 0.97 or absf(hit.position.y - p.y) > 0.2:
			continue
		var room := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, 1.6, 1.6)
		room.shape = box
		room.transform = Transform3D(Basis(), hit.position + Vector3(0, 1.0, 0))
		room.collision_mask = 1 | 4
		if not space.intersect_shape(room, 1).is_empty():
			continue
		cand.append(hit.position)
	var placed := 0
	while placed < want and not cand.is_empty():
		var best := -1
		var best_d := 0.0
		for i in cand.size():
			var c: Vector3 = cand[i]
			var dmin := 1e9
			for t in taken:
				dmin = minf(dmin, c.distance_to(t))
			if dmin > best_d:
				best_d = dmin
				best = i
		if best < 0 or best_d < 8.0:
			break
		var pos: Vector3 = cand[best]
		cand.remove_at(best)
		taken.append(pos)
		var pk = Pickup.new()
		pk.kind = "weapon"
		pk.game = self
		pk.position = pos
		world.add_child(pk)
		placed += 1
	print("[boxes] %d extra mystery boxes (%d pads in total)" % [placed, placed + map.pickup_spots.filter(func(s): return s[0] == "weapon").size()])


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
	# Wandering pets are gone (they got in the way); --pets-demo still works.
	var n := 0
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


## Rounds on a map with ffa_vehicle_spots (Frontline): unarmed buggies,
## bikes and helicopters for getting around; the fighting stays on foot.
func _spawn_ffa_vehicles() -> void:
	for spot in map.ffa_vehicle_spots:
		_spawn_ffa_vehicle(spot[0], spot[1])
	# Dev flag --drive=type: player 1 starts in the first ride of that type.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--drive=") and not players.is_empty():
			for v in vehicles:
				if v.type == arg.substr(8):
					players[0].spawn(v.global_position + Vector3(3, 0.5, 0), players[0].yaw)
					v.enter(players[0])
					break


func _spawn_ffa_vehicle(type: String, xf: Transform3D) -> void:
	var v = preload("res://scripts/vehicle.gd").new()
	v.game = self
	v.setup(type, xf, 0, Color(0.95, 0.78, 0.3) if type == "bike" else Color(0.55, 0.62, 0.7))
	v.disarm()
	world.add_child(v)
	v.global_transform = xf


## A destroyed unarmed ride comes back at its spot 20 s later.
func ffa_vehicle_destroyed(type: String, home: Transform3D) -> void:
	get_tree().create_timer(20.0, false).timeout.connect(func():
		if not match_over:
			_spawn_ffa_vehicle(type, home))


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
