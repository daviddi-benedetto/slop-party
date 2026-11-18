extends Node
## Entry point (main.tscn). Switches between the lobby and a match with a
## quick fade.
##
## Developer flags, passed after "--" on the command line:
##   --autotest            skip the lobby: start a match of 6 bots
##   --views=N             in autotest, give the first N bots a splitscreen view
##   --kb                  in autotest, make player 1 a keyboard/mouse human
##   --solo                in autotest, player 1 is the only participant
##   --target=<kills>      kill target for the autotest match
##   --map=<index>         which arena the autotest match uses (0-5)
##   --mode=rounds|zombies|frontline, --teams=versus|coop   game mode
##   --wave=N              zombies: start at wave N
##   --drive=buggy|tank|heli   frontline: player 1 starts in that vehicle
##   --theme=classic|toy|warm|cyberpunk|synthwave|spooky|moonlit|random
##                         visual theme (match and lobby; default random in
##                         autotest; --time=day|sunset|night still works)
##   --lobby-demo=H,B      show the lobby with H fake humans and B bots seated
##   --shot=<file.png>     save a screenshot, print stats, then quit
##   --shot-time=<sec>     when to take it (default 6)
##   --pause-at=<sec>      open the pause menu after that many seconds
##   --options-demo        open the Options screen in the lobby after 1 second
##   --ram-at=sec [--ram-speed=m/s]  with --drive: launch the ride at player 2
##   --fp                  player 1 drives in first person (vehicles)
##   --heights-at=s1,s2    print every player's height at those times
##   --check-spawns        print spawn points that are blocked (after the build)
##   --click=x,y@sec[;...] fake mouse moves + left clicks (x, y as 0-1 of the
##                         window; "r" after sec = right click) to test menus
##   --options-page=N      ...on its Nth page (0 = DISPLAY)
##   --melee-at=<sec>      player 1 swings their melee then
##   --box-at=<sec>        player 1 opens a mystery box then
##   --perch-at=<sec>[--roof=N]  player 1 is put on top of a roof
##   --boom-at=<sec>       an explosion 7 m in front of player 1
##   --gore-at=<sec>[,how] a body comes apart 4 m in front of player 1
##                         (how: normal, head, blast, slice)
##   --start-after=<sec>   with --lobby-demo: start the match after that long
##                         (shows the loading card)
##   --uncapped            ignore the v-sync / frame-limit settings (benchmarking)
##   --debug               extra bot info in the --shot printout
##   --eye=x,y,z,tx,ty,tz  with --views=0: a fixed camera at x,y,z looking at t
##   --cards=A,B / --weapon=N   give every player these cards / this weapon
##   --force-aim           everyone aims down sights
## Example:
##   godot --path . -w --resolution 1920x1080 -- --autotest --views=6 --shot=out.png

const Lobby = preload("res://scripts/lobby.gd")
const Game = preload("res://scripts/game.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Help = preload("res://scripts/help.gd")
const Looks = preload("res://scripts/looks.gd")
const MapScript = preload("res://scripts/map.gd")

var lobby
var game = null
var _args := {}
var _fade        # wipe.gd: a theme-coloured curtain driven like a fade (color:a)
var _card: Control            # the loading card drawn over the black fade
var _card_info := {}          # {mode, map, theme, tip} while it shows


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("sheet"):
		# Dev: --sheet=out.png --ids=20,21 renders weapon models and quits.
		var sheet = load("res://tools/weapon_sheet.gd").new()
		add_child(sheet)
		var ids: Array = []
		for s in str(_args.get("ids", "0")).split(","):
			ids.append(int(s))
		sheet.run(str(_args.sheet), ids)
		return
	if _args.has("kit-test"):
		# Dev: the building-kit showcase (tools/kit_test.gd, with --shot).
		var kt = load("res://tools/kit_test.gd").new()
		add_child(kt)
		kt.run(str(_args["kit-test"]), str(_args.get("kit-cam", "")))
		if _args.has("shot"):
			_screenshot_later(float(_args.get("shot-time", "4")), _args["shot"])
		return
	if _args.has("fx-test"):
		# Dev: particle effects alone in an empty scene (with --shot).
		var r3 := Node3D.new()
		add_child(r3)
		var we := WorldEnvironment.new()
		we.environment = Environment.new()
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = Color(0.3, 0.4, 0.6)
		we.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		we.environment.glow_enabled = true
		r3.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 30, 0)
		r3.add_child(sun)
		var cam := Camera3D.new()
		r3.add_child(cam)
		cam.look_at_from_position(Vector3(0, 2, 9), Vector3(0, 1.5, 0))
		var FxS = preload("res://scripts/fx.gd")
		get_tree().create_timer(float(_args.get("fx-at", "1.0"))).timeout.connect(func():
			FxS.fireball(r3, Vector3(-2.5, 1, 0), 1.0)
			FxS.embers(r3, Vector3(-2.5, 1, 0), 1.0)
			FxS.smoke_column(r3, Vector3(0, 0.5, 0), 1.0)
			FxS.fire_patch(r3, Vector3(2.5, 0, 0), 0.6, 0.0))
		if _args.has("shot"):
			_screenshot_later(float(_args.get("shot-time", "2")), _args["shot"])
		return
	lobby = Lobby.new()
	add_child(lobby)
	lobby.start.connect(_start_match)

	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_fade = preload("res://scripts/wipe.gd").new()
	_fade.color = Color(UiKit.INK, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_card = Control.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	_card.draw.connect(_draw_card)
	layer.add_child(_card)

	if _args.has("autotest"):
		seed(int(_args.get("seed", "1")))
		var views := int(_args.get("views", "6"))
		var parts: Array = []
		for i in 6:
			parts.append({"device": -2, "bot": true, "view": i < views, "kind": i + int(_args.get("kinds", "0")), "hat": i + 1, "face": i, "back": i + 1})
		if _args.has("kb"):
			parts[0] = {"device": -1, "bot": false, "view": true, "kind": 0}
		if _args.has("solo"):
			parts = [parts[0]]      # dev: player 1 alone (zombie tests)
		lobby.visible = false
		_begin({"participants": parts, "kill_target": int(_args.get("target", "15")), "map": int(_args.get("map", "0")), "theme": str(_args.get("theme", _args.get("time", "random"))),
			"mode": str(_args.get("mode", "rounds")), "teams": str(_args.get("teams", "versus"))})
	else:
		if _args.has("lobby-demo"):
			var hb := str(_args["lobby-demo"]).split(",")
			lobby.demo_fill(int(hb[0]), int(hb[1]) if hb.size() > 1 else 0)
		if _args.has("theme"):
			lobby.pick_theme(str(_args.theme))
		lobby.activate()
		create_tween().tween_property(_fade, "color:a", 0.0, 0.5)
	if _args.has("options-demo"):
		get_tree().create_timer(1.0).timeout.connect(func():
			lobby._options.open()
			for i in int(_args.get("options-page", "0")):
				lobby._options._turn(1))
	if _args.has("check-spawns"):
		get_tree().create_timer(10.0, true, false, true).timeout.connect(func():
			if game == null:
				print("[spawns] no match running")
				return
			var space: PhysicsDirectSpaceState3D = game.map.get_world_3d().direct_space_state
			var cap := CapsuleShape3D.new()
			cap.radius = 0.45
			cap.height = 1.7
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.collision_mask = 1 | 4
			var bad := 0
			for sp in game.map.spawn_points:
				q.transform = Transform3D(Basis(), sp + Vector3(0, 1.0, 0))
				var hits := space.intersect_shape(q, 4)
				var down := PhysicsRayQueryParameters3D.create(sp + Vector3(0, 0.5, 0), sp + Vector3(0, -3.0, 0), 1)
				var floor_hit := space.intersect_ray(down)
				if not hits.is_empty() or floor_hit.is_empty():
					bad += 1
					print("[spawns] BLOCKED %s %s" % [sp, "no floor" if floor_hit.is_empty() else str(hits[0].collider)])
			print("[spawns] %d points, %d blocked" % [game.map.spawn_points.size(), bad])
			# Rides (Rounds on Frontline): a box the vehicle's size must be clear.
			for vs in game.map.ffa_vehicle_spots:
				var box := BoxShape3D.new()
				box.size = preload("res://scripts/vehicle.gd").SPECS[vs[0]].size
				var vq := PhysicsShapeQueryParameters3D.new()
				vq.shape = box
				vq.collision_mask = 1 | 4
				var xf: Transform3D = vs[1]
				vq.transform = Transform3D(xf.basis, xf.origin + Vector3(0, box.size.y * 0.5 + 0.45, 0))
				var vh := space.intersect_shape(vq, 4)
				print("[spawns] ride %s at %s %s" % [vs[0], xf.origin, "BLOCKED by " + str(vh[0].collider) if not vh.is_empty() else "clear"]))
	if _args.has("click"):
		for c in str(_args["click"]).split(";"):
			var xy_t := c.split("@")
			var xy := xy_t[0].split(",")
			var right := xy_t[1].ends_with("r")
			var at := Vector2(float(xy[0]), float(xy[1]))
			get_tree().create_timer(float(xy_t[1].trim_suffix("r")), true, false, true).timeout.connect(func():
				var pos: Vector2 = at * get_viewport().get_visible_rect().size
				var mv := InputEventMouseMotion.new()
				mv.position = pos
				Input.parse_input_event(mv)
				for down in [true, false]:
					var mb := InputEventMouseButton.new()
					mb.position = pos
					mb.button_index = MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
					mb.pressed = down
					Input.parse_input_event(mb)
				print("[click] ", pos, " right" if right else ""))
	if _args.has("ram-at"):
		# Dev (with --drive): put player 2 a few metres in front of player 1's
		# ride, launch it at them, report the damage and how far they flew.
		get_tree().create_timer(float(_args["ram-at"]), true, false, true).timeout.connect(func():
			if game == null or game.players.size() < 2 or game.players[0].vehicle == null:
				print("[ram] no ride")
				return
			var v = game.players[0].vehicle
			var victim = game.players[1]
			var fwd: Vector3 = -v.global_transform.basis.z
			victim.spawn(v.global_position + fwd * 4.5 + Vector3(0, 0.2, 0), victim.yaw)
			victim.spawn_protect = 0.0
			var hp0: float = victim.health
			var p0: Vector3 = victim.global_position
			var v0: Vector3 = v.global_position
			print("[ram] ride at %s, victim at %s (alive %s, frozen %s)" % [v0, p0, victim.alive, game.frozen])
			var spd := float(_args.get("ram-speed", "24"))
			var hold := func(): v._speed = spd       # hold the throttle for the test
			get_tree().physics_frame.connect(hold)
			get_tree().create_timer(0.6).timeout.connect(func(): get_tree().physics_frame.disconnect(hold))
			get_tree().create_timer(1.2).timeout.connect(func():
				print("[ram] ride moved %.1f m" % v.global_position.distance_to(v0))
				print("[ram] %s at %s m/s: victim health %d -> %d, moved %.1f m, peak? alive %s" % [v.type, _args.get("ram-speed", "24"), hp0, victim.health, victim.global_position.distance_to(p0), victim.alive])))
	if _args.has("fp"):
		# Dev: player 1 drives in first person.
		get_tree().create_timer(1.0, true, false, true).timeout.connect(func():
			if game != null and not game.players.is_empty():
				game.players[0].fp_drive = true)
	if _args.has("heights-at"):
		# Dev: print every player's height (are bots using the upper floors?).
		for ts in str(_args["heights-at"]).split(","):
			get_tree().create_timer(float(ts), true, false, true).timeout.connect(func():
				if game != null:
					var hs: Array = []
					for p in game.players:
						hs.append("%.1f" % p.global_position.y)
					print("[heights] t=%s %s" % [ts, " ".join(hs)]))
	if _args.has("melee-at"):
		# Dev: player 1 swings their melee at that time (knife screenshots).
		get_tree().create_timer(float(_args["melee-at"]), true, false, true).timeout.connect(func():
			if game != null and not game.players.is_empty():
				game.players[0]._melee_start())
	if _args.has("box-at"):
		# Dev: player 1 stands in front of a mystery box and opens it.
		get_tree().create_timer(float(_args["box-at"]), true, false, true).timeout.connect(func():
			if game == null or game.players.is_empty():
				return
			for pk in game.world.get_children():
				if pk.get_script() != null and pk.get_script().resource_path.ends_with("pickup.gd") and str(pk.kind) == "weapon":
					var p = game.players[0]
					p.global_position = pk.global_position + Vector3(0, 0.1, 2.4)
					p.yaw = 0.0
					p.pitch = -0.25
					pk.take(p)
					print("[box] at ", pk.global_position)
					break)
	if _args.has("perch-at"):
		# Dev: put player 1 on top of a roof (zombie climbing tests).
		get_tree().create_timer(float(_args["perch-at"]), true, false, true).timeout.connect(func():
			if game == null or game.players.is_empty() or game.map.roofs.is_empty():
				return
			var r: Rect2 = game.map.roofs[int(_args.get("roof", "0")) % game.map.roofs.size()]
			var c := Vector3(r.get_center().x, 60.0, r.get_center().y)
			var q := PhysicsRayQueryParameters3D.create(c, c - Vector3(0, 80, 0), 1)
			var hit: Dictionary = game.world.get_world_3d().direct_space_state.intersect_ray(q)
			if hit:
				var p = game.players[0]
				p.global_position = hit.position + Vector3(0, 0.2, 0)
				p.velocity = Vector3.ZERO
				print("[perch] player 1 on a roof at ", hit.position)
				var tm := Timer.new()
				tm.wait_time = 3.0
				tm.autostart = true
				add_child(tm)
				tm.timeout.connect(func():
					if game == null or game.players.is_empty():
						return
					var p0 = game.players[0]
					var near := 1e9
					var hz := 0.0
					var zz = null
					for z in game.actors:
						if is_instance_valid(z) and z.has_method("chest_position") and z.alive:
							var dd: float = z.global_position.distance_to(p0.global_position)
							if dd < near:
								near = dd
								hz = z.global_position.y
								zz = z
					if zz != null and "_wall_spot" in zz:
						print("        zombie at %s spot %s force %.1f climb %.1f path %d/%d wall %s" % [zz.global_position.snapped(Vector3.ONE * 0.1), zz._wall_spot, zz._force_climb, zz._climb, zz._path_i, zz._path.size(), zz.is_on_wall()])
					print("[perch] t=%.0f health %d deaths %d nearest zombie %.1f m (at height %.1f)" % [game.time, p0.health, p0.deaths, near, hz])))
	if _args.has("boom-at"):
		get_tree().create_timer(float(_args["boom-at"]), true, false, true).timeout.connect(func():
			if game != null and not game.players.is_empty():
				var p = game.players[0]
				var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
				game.explode(p.global_position + fwd * 7.0 + Vector3(0, 0.6, 0), 3.5, 0.0, null, null))
	if _args.has("gore-at"):
		var ga := str(_args["gore-at"]).split(",")
		get_tree().create_timer(float(ga[0]), true, false, true).timeout.connect(func():
			if game != null and not game.players.is_empty():
				var p = game.players[0]
				var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
				preload("res://scripts/gore.gd").death(game.world, p.global_position + fwd * 4.0, fwd, preload("res://scripts/plush.gd").SPEC[1], ga[1] if ga.size() > 1 else "normal"))
	if _args.has("start-after"):
		get_tree().create_timer(float(_args["start-after"])).timeout.connect(func(): lobby._start())
	if _args.has("pause-at"):
		get_tree().create_timer(float(_args["pause-at"]), true, false, true).timeout.connect(func():
			if game != null:
				game._set_paused(true))
	if _args.has("shot"):
		_screenshot_later(float(_args.get("shot-time", "6")), _args["shot"])


func _start_match(config: Dictionary) -> void:
	if game != null or _fade.color.a > 0.01:
		return
	Sfx.play("go", -4.0)
	_card_info = _card_for(config)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	# The loading card: mode, map, theme and a tip, held long enough to read
	# before the (blocking) map build starts.
	tw.tween_callback(func():
		_card.visible = true
		_card.queue_redraw())
	tw.tween_interval(1.8)
	tw.tween_callback(_begin.bind(config))
	tw.tween_callback(func(): _card.visible = false)


func _begin(config: Dictionary) -> void:
	lobby.deactivate()
	game = Game.new()
	game.config = config
	game.finished.connect(_end_match)
	add_child(game)
	move_child(game, 1)
	_fade.color.a = 0.0      # the match has its own fade-in


## What the loading card says for a match config.
func _card_for(config: Dictionary) -> Dictionary:
	var mode: String = config.get("mode", "rounds")
	var mi: int = {"zombies": MapScript.ZOMBIE, "medieval": MapScript.CASTLE, "racing": MapScript.RACEWAY}.get(mode, int(config.get("map", 0)))
	if mode == "frontline" and not mi in MapScript.FRONT_MAPS:
		mi = MapScript.FRONTLINE
	var tk := str(config.get("theme", "classic"))
	return {"mode": {"gungame": "GUN GAME"}.get(mode, mode.to_upper()), "line": Help.mode_line(mode),
		"map": MapScript.MAPS[clampi(mi, 0, MapScript.MAPS.size() - 1)].name, "theme": Looks.label(tk), "tip": Help.tip(),
		"ui": Looks.LOOKS.get(tk, Looks.LOOKS.classic).ui}


func _draw_card() -> void:
	if _card_info.is_empty():
		return
	var w := _card.size.x
	var h := _card.size.y
	var s := h / 1080.0
	var ui: Dictionary = _card_info.ui
	UiKit.text(_card, Vector2(0, 330 * s), _card_info.mode, 110 * s, ui.logo_a, HORIZONTAL_ALIGNMENT_CENTER, w, 700, 0.12)
	UiKit.text(_card, Vector2(0, 400 * s), "%s   -   %s" % [_card_info.map, _card_info.theme], 36 * s, ui.logo_b, HORIZONTAL_ALIGNMENT_CENTER, w, 700, 0.1)
	var lw := minf(1100.0 * s, w - 80 * s)
	_card.draw_multiline_string(UiKit.font(600), Vector2((w - lw) * 0.5, 470 * s), _card_info.line, HORIZONTAL_ALIGNMENT_CENTER, lw, int(28 * s), 3, Color(UiKit.CREAM, 0.9))
	var tw := minf(1200.0 * s, w - 80 * s)
	var r := Rect2((w - tw) * 0.5, 700 * s, tw, 150 * s)
	UiKit.card(_card, r, ui.panel, 30 * s, s)
	UiKit.text(_card, Vector2(r.position.x, r.position.y + 46 * s), "TIP", 26 * s, ui.value, HORIZONTAL_ALIGNMENT_CENTER, tw, 700, 0.0)
	_card.draw_multiline_string(UiKit.font(600), Vector2(r.position.x + 40 * s, r.position.y + 92 * s), _card_info.tip, HORIZONTAL_ALIGNMENT_CENTER, tw - 80 * s, int(28 * s), 2, UiKit.CREAM)
	UiKit.text(_card, Vector2(0, h - 60 * s), "LOADING...", 26 * s, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, w, 700, 0.0)


func _end_match() -> void:
	if game == null:
		return
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	tw.tween_callback(func():
		game.queue_free()
		game = null
		lobby.activate())
	tw.tween_property(_fade, "color:a", 0.0, 0.4)


var _fr_n := 0
var _fr_sum := 0.0
var _fr_slow := 0
var _fr_worst := 0.0
var _fr_last := 0

## Dev: frame-time statistics for the --shot report (hitches, not averages).
func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _fr_last != 0 and now > 8000000:
		var dt := (now - _fr_last) / 1000000.0
		_fr_n += 1
		_fr_sum += dt
		_fr_worst = maxf(_fr_worst, dt)
		if dt > 0.025:
			_fr_slow += 1
	_fr_last = now


func _screenshot_later(delay: float, path: String) -> void:
	await get_tree().create_timer(delay, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[shot] screen %s @ %.0f Hz, window %s, gpu %s, vsync %d, max_fps %d" % [DisplayServer.screen_get_size(), DisplayServer.screen_get_refresh_rate(),
		get_window().size, RenderingServer.get_video_adapter_name(), DisplayServer.window_get_vsync_mode(), Engine.max_fps])
	print("[shot] saved %s  fps=%d  draw_calls=%d" % [path, Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	print("[shot] nodes=%d objects=%d process_ms=%.2f physics_ms=%.2f" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	print("[shot] frames %d, avg %.1f ms, slow (>25 ms) %d, worst %.0f ms (after the first 8 s)" % [_fr_n, _fr_sum / maxf(_fr_n, 1) * 1000.0, _fr_slow, _fr_worst * 1000.0])
	print("[shot] physics active=%d pairs=%d islands=%d  render scale=%.2f" % [Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT), Settings.res_factor])
	if game != null and _args.has("perch-at") and not game.players.is_empty():
		var p0 = game.players[0]
		var nearest := 1e9
		for z in game.actors:
			if is_instance_valid(z) and z.has_method("chest_position"):
				nearest = minf(nearest, z.global_position.distance_to(p0.global_position))
		print("[perch] player 1 at %s, health %d, deaths %d, nearest zombie %.1f m" % [p0.global_position.snapped(Vector3.ONE * 0.1), p0.health, p0.deaths, nearest])
	if game != null:
		for p in game.players:
			print("[shot] %s kills=%d deaths=%d cards=%s" % [p.pname, p.kills, p.deaths, str(p.cards)])
			if _args.has("debug"):
				print("        pos=%s vel=%s alive=%s" % [p.global_position.snapped(Vector3.ONE * 0.1), p.velocity.snapped(Vector3.ONE * 0.1), p.alive])
				if p.is_bot:
					print("        los=%s path=%d/%d target=%s" % [p.brain._has_los, p.brain._path_i, p.brain._path.size(), p.brain._target.pname if p.brain._target else "-"])
	if game != null and _args.has("debug") and not game.players.is_empty():
		# What is drawn within arm's reach of player 1's eyes (stray meshes).
		var eye: Vector3 = game.players[0].eye_position()
		for n in game.world.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			if mi.is_visible_in_tree() and mi.global_position.distance_to(eye) < 1.6:
				print("        near eye: %s layers=%d path=%s" % [mi.name, mi.layers, str(game.world.get_path_to(mi)).right(90)])
	get_tree().quit()
