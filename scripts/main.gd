extends Node
## Entry point (main.tscn). Switches between the lobby and a match with a
## quick fade.
##
## Developer flags, passed after "--" on the command line:
##   --autotest            skip the lobby: start a match of 6 bots
##   --views=N             in autotest, give the first N bots a splitscreen view
##   --kb                  in autotest, make player 1 a keyboard/mouse human
##   --target=<kills>      kill target for the autotest match
##   --map=<index>         which arena the autotest match uses (0-5)
##   --mode=rounds|zombies|frontline, --teams=versus|coop   game mode
##   --wave=N              zombies: start at wave N
##   --drive=buggy|tank|heli   frontline: player 1 starts in that vehicle
##   --time=day|sunset|night   (default random)
##   --lobby-demo=H,B      show the lobby with H fake humans and B bots seated
##   --shot=<file.png>     save a screenshot, print stats, then quit
##   --shot-time=<sec>     when to take it (default 6)
##   --pause-at=<sec>      open the pause menu after that many seconds
##   --options-demo        open the Options screen in the lobby after 1 second
##   --uncapped            ignore the v-sync / frame-limit settings (benchmarking)
##   --debug               extra bot info in the --shot printout
##   --cards=A,B / --weapon=N   give every player these cards / this weapon
##   --force-aim           everyone aims down sights
## Example:
##   godot --path . -w --resolution 1920x1080 -- --autotest --views=6 --shot=out.png

const Lobby = preload("res://scripts/lobby.gd")
const Game = preload("res://scripts/game.gd")
const UiKit = preload("res://scripts/ui_kit.gd")

var lobby
var game = null
var _args := {}
var _fade: ColorRect


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
	lobby = Lobby.new()
	add_child(lobby)
	lobby.start.connect(_start_match)

	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(UiKit.INK, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)

	if _args.has("autotest"):
		seed(int(_args.get("seed", "1")))
		var views := int(_args.get("views", "6"))
		var parts: Array = []
		for i in 6:
			parts.append({"device": -2, "bot": true, "view": i < views, "kind": i + int(_args.get("kinds", "0")), "hat": i + 1, "face": i, "back": i + 1})
		if _args.has("kb"):
			parts[0] = {"device": -1, "bot": false, "view": true, "kind": 0}
		lobby.visible = false
		_begin({"participants": parts, "kill_target": int(_args.get("target", "15")), "map": int(_args.get("map", "0")), "time": str(_args.get("time", "random")),
			"mode": str(_args.get("mode", "rounds")), "teams": str(_args.get("teams", "versus"))})
	else:
		if _args.has("lobby-demo"):
			var hb := str(_args["lobby-demo"]).split(",")
			lobby.demo_fill(int(hb[0]), int(hb[1]) if hb.size() > 1 else 0)
		lobby.activate()
		create_tween().tween_property(_fade, "color:a", 0.0, 0.5)
	if _args.has("options-demo"):
		get_tree().create_timer(1.0).timeout.connect(func(): lobby._options.open())
	if _args.has("pause-at"):
		get_tree().create_timer(float(_args["pause-at"])).timeout.connect(func():
			if game != null:
				game._set_paused(true))
	if _args.has("shot"):
		_screenshot_later(float(_args.get("shot-time", "6")), _args["shot"])


func _start_match(config: Dictionary) -> void:
	if game != null or _fade.color.a > 0.01:
		return
	Sfx.play("go", -4.0)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	tw.tween_callback(_begin.bind(config))


func _begin(config: Dictionary) -> void:
	lobby.deactivate()
	game = Game.new()
	game.config = config
	game.finished.connect(_end_match)
	add_child(game)
	move_child(game, 1)
	_fade.color.a = 0.0      # the match has its own fade-in


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
