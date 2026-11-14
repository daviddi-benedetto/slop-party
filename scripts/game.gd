extends Node
## One deathmatch, from first spawn to the victory screen.
##
## Owns: the 3D world (map + players + bullets), the splitscreen layout, the
## rules (scoring, respawns, win condition) and area damage.
##
## Splitscreen: all gameplay nodes live under `world`, in the root viewport's
## World3D. Each human gets a SubViewportContainer > SubViewport holding only a
## Camera3D (+ first-person gun) and a CanvasLayer with hud.gd. SubViewports
## share the parent World3D by default, so every camera sees the same match.
## Cameras are moved here in _process() from each player's yaw/pitch.
##
## Visibility layers (VisualInstance3D.layers / Camera3D.cull_mask):
##   bit 0        world geometry, bullets, effects
##   bit 1 + i    player i's third-person body (hidden from player i's camera)
##   bit 8 + i    player i's first-person gun (visible only to player i)
##
## config = { "participants": [ { "device": int, "bot": bool, "view": bool } ],
##            "kill_target": int }

signal finished

const Player = preload("res://scripts/player.gd")
const Map = preload("res://scripts/map.gd")
const Hud = preload("res://scripts/hud.gd")
const InputSource = preload("res://scripts/input_source.gd")
const BotBrain = preload("res://scripts/bot_brain.gd")
const Fx = preload("res://scripts/fx.gd")

const COLORS := [
	Color(0.86, 0.22, 0.2), Color(0.2, 0.47, 0.9), Color(0.25, 0.75, 0.3),
	Color(0.95, 0.78, 0.15), Color(0.7, 0.35, 0.85), Color(0.95, 0.5, 0.15),
]

var config := {}
var world: Node3D
var map
var players: Array = []
var kill_target := 15
var match_over := false
var winner = null
var time := 0.0
var feed: Array = []          # [{text, color, t}] newest first

var _ui: Control
var _views: Array = []        # [{container, viewport, camera, gun, player}]
var _kb_brain = null
var _end_time := 0.0
var _quit_hold := 0.0


func _ready() -> void:
	kill_target = config.get("kill_target", 15)
	world = Node3D.new()
	add_child(world)
	map = Map.new()
	world.add_child(map)
	map.build()

	var parts: Array = config.participants
	var bot_n := 0
	for i in parts.size():
		var part: Dictionary = parts[i]
		var p = Player.new()
		p.index = i
		p.color = COLORS[i % COLORS.size()]
		p.game = self
		p.is_bot = part.bot
		if part.bot:
			bot_n += 1
			p.pname = "BOT %d" % bot_n
			p.brain = BotBrain.new()
			p.brain.skill = randf_range(0.35, 0.75)
		else:
			p.pname = "P%d" % (i + 1)
			p.brain = InputSource.new(part.device)
			if part.device == InputSource.KEYBOARD:
				_kb_brain = p.brain
		players.append(p)
		world.add_child(p)

	_build_views()
	get_viewport().size_changed.connect(_layout)
	if _kb_brain != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var spots: Array = map.spawn_points.duplicate()
	spots.shuffle()
	for i in players.size():
		var pos: Vector3 = spots[i % spots.size()]
		players[i].spawn(pos, _yaw_to_centre(pos))
	map.build_nav()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _kb_brain != null:
		_kb_brain.mouse_accum += event.relative


# --------------------------------------------------------------------------
# Splitscreen
# --------------------------------------------------------------------------

func _build_views() -> void:
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)

	var viewers: Array = []
	for i in players.size():
		if config.participants[i].get("view", not players[i].is_bot):
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
	_ui.add_child(container)
	var vp := SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(vp)

	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.near = 0.08
	cam.far = 250.0
	var all_bodies := 0
	for p in players:
		all_bodies |= p.body_layer_bit()
	var gun: Node3D = null
	if player != null:
		cam.cull_mask = 1 | (all_bodies & ~player.body_layer_bit()) | player.viewmodel_layer_bit()
		gun = _make_viewmodel(player)
		cam.add_child(gun)
	else:
		cam.cull_mask = 1 | all_bodies
	vp.add_child(cam)
	cam.current = true

	var layer := CanvasLayer.new()
	vp.add_child(layer)
	var hud = Hud.new()
	hud.player = player
	hud.game = self
	layer.add_child(hud)
	_views.append({"container": container, "viewport": vp, "camera": cam, "gun": gun, "player": player})


func _make_viewmodel(player) -> Node3D:
	var root := Node3D.new()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.22, 0.26)
	metal.roughness = 0.4
	metal.metallic = 0.5
	var accent := StandardMaterial3D.new()
	accent.albedo_color = player.color
	accent.roughness = 0.7
	var parts := [
		[Vector3(0.07, 0.09, 0.42), Vector3(0, 0, 0), metal],
		[Vector3(0.05, 0.05, 0.2), Vector3(0, 0.015, -0.3), metal],
		[Vector3(0.06, 0.16, 0.08), Vector3(0, -0.11, 0.12), accent],
		[Vector3(0.075, 0.03, 0.3), Vector3(0, 0.055, 0.02), accent],
	]
	for part in parts:
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = part[1]
		mi.material_override = part[2]
		mi.layers = player.viewmodel_layer_bit()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		root.add_child(mi)
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	return root


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
		var gap := 2.0 if _views.size() > 1 else 0.0
		v.container.position = Vector2(gx, gy) * cell + Vector2(gap, gap) * 0.5
		v.container.size = cell - Vector2(gap, gap)
		# Aim for ~100 deg horizontal FOV whatever the cell's aspect ratio.
		var aspect := cell.x / cell.y
		var vfov := rad_to_deg(2.0 * atan(tan(deg_to_rad(50.0)) / aspect))
		v.camera.fov = clampf(vfov, 52.0, 75.0)


func _process(delta: float) -> void:
	time += delta
	for v in _views:
		var p = v.player
		var cam: Camera3D = v.camera
		if p == null:
			var a := time * 0.12
			cam.global_position = Vector3(cos(a) * 40.0, 24.0, sin(a) * 34.0)
			cam.look_at(Vector3(0, 1, 0))
			continue
		if p.alive:
			var eye: Vector3 = p.get_global_transform_interpolated().origin + Vector3(0, p.EYE_HEIGHT, 0)
			cam.global_transform = Transform3D(Basis.from_euler(Vector3(p.pitch + p.recoil * 0.012, p.yaw, 0.0)), eye)
		else:
			# Death cam: drift upward a little from where we fell.
			cam.global_position += Vector3(0, delta * 0.35, 0)
		v.gun.visible = p.alive
		var sway: float = sin(time * 9.0) * 0.004 * clampf(p.velocity.length() / 7.0, 0.0, 1.0)
		v.gun.position = Vector3(0.2, -0.19 + sway, -0.42 + p.recoil * 0.06)
		v.gun.rotation.x = p.recoil * 0.12

	# Leaving the match: Esc, or hold Start + Back/Select on any pad.
	var quit_now := Input.is_physical_key_pressed(KEY_ESCAPE)
	var holding := false
	for d in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(d, JOY_BUTTON_START) and Input.is_joy_button_pressed(d, JOY_BUTTON_BACK):
			holding = true
	_quit_hold = _quit_hold + delta if holding else 0.0
	if quit_now or _quit_hold > 0.6:
		_finish()
		return

	if match_over:
		_end_time += delta
		var skip := false
		if _end_time > 3.0:
			skip = Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE)
			for d in Input.get_connected_joypads():
				if Input.is_joy_button_pressed(d, JOY_BUTTON_A) or Input.is_joy_button_pressed(d, JOY_BUTTON_START):
					skip = true
		if skip or _end_time > 14.0:
			_finish()


func _finish() -> void:
	set_process(false)
	finished.emit()


# --------------------------------------------------------------------------
# Rules
# --------------------------------------------------------------------------

func _yaw_to_centre(pos: Vector3) -> float:
	return atan2(pos.x, pos.z)


func on_player_died(victim, killer) -> void:
	var credited: bool = killer != null and is_instance_valid(killer) and killer != victim
	if credited:
		killer.kills += 1
		killer.kill_flash = 1.0
		_feed("%s  >  %s" % [killer.pname, victim.pname], killer.color.lerp(Color.WHITE, 0.35))
		if killer.kills >= kill_target:
			match_over = true
			winner = killer
			Sfx.play("win", -2.0)
	else:
		# Falling out of the world or blowing yourself up costs a point.
		victim.kills = maxi(0, victim.kills - 1)
		_feed("%s self-destructed" % victim.pname, Color(0.8, 0.8, 0.8))


func _feed(text: String, color: Color) -> void:
	feed.push_front({"text": text, "color": color, "t": time})
	if feed.size() > 5:
		feed.pop_back()


func respawn_later(p, delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(func():
		if not match_over and is_instance_valid(p) and not p.alive:
			respawn(p))


## Spawn as far from living enemies as possible (random among the best three).
func respawn(p) -> void:
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
	Fx.flash(world, pos, Color(1.0, 0.55, 0.15, 0.85), radius * 0.25, radius, 0.3)
	Fx.flash(world, pos, Color(1.0, 0.9, 0.6, 0.9), radius * 0.1, radius * 0.5, 0.18)
	Sfx.play("boom", -4.0)
	for p in players:
		if not p.alive or p == direct_victim:
			continue
		var to_p: Vector3 = p.chest_position() - pos
		var d := to_p.length()
		if d > radius + 0.5:
			continue
		var f := 1.0 - 0.6 * clampf(d / radius, 0.0, 1.0)
		p.velocity += (to_p.normalized() + Vector3(0, 0.4, 0)) * 9.0 * f
		p.take_damage(damage * f * (0.5 if p == shooter else 1.0), shooter)


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
	for p in players:
		if p == player or not p.alive:
			continue
		var to_p: Vector3 = p.chest_position() - eye
		var d := to_p.length()
		if d < 1.0 or d > 60.0:
			continue
		if fwd.angle_to(to_p) < atan(0.9 / d) + 0.015:
			return 0.45
	return 1.0
