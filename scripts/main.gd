extends Node
## Entry point (main.tscn). Switches between the lobby and a match.
##
## Developer flags, passed after "--" on the command line:
##   --autotest            skip the lobby: start a match of 6 bots
##   --views=N             in autotest, give the first N bots a splitscreen view
##   --kb                  in autotest, make player 1 a keyboard/mouse human
##   --shot=<file.png>     save a screenshot, print stats, then quit
##   --shot-time=<sec>     when to take it (default 6)
##   --target=<kills>      kill target for the autotest match
## Example:
##   godot --path . -w --resolution 1920x1080 -- --autotest --views=6 --shot=out.png

const Lobby = preload("res://scripts/lobby.gd")
const Game = preload("res://scripts/game.gd")

var lobby
var game = null
var _args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	lobby = Lobby.new()
	add_child(lobby)
	lobby.start.connect(_start_match)

	if _args.has("autotest"):
		var views := int(_args.get("views", "6"))
		var parts: Array = []
		for i in 6:
			parts.append({"device": -2, "bot": true, "view": i < views})
		if _args.has("kb"):
			parts[0] = {"device": -1, "bot": false, "view": true}
		_start_match({"participants": parts, "kill_target": int(_args.get("target", "15"))})
	if _args.has("shot"):
		_screenshot_later(float(_args.get("shot-time", "6")), _args["shot"])


func _start_match(config: Dictionary) -> void:
	lobby.visible = false
	game = Game.new()
	game.config = config
	game.finished.connect(_end_match)
	add_child(game)


func _end_match() -> void:
	if game != null:
		game.queue_free()
		game = null
	lobby.activate()


func _screenshot_later(delay: float, path: String) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[shot] screen refresh=%.0f Hz" % DisplayServer.screen_get_refresh_rate())
	print("[shot] saved %s  fps=%d  draw_calls=%d" % [path, Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	if game != null:
		for p in game.players:
			print("[shot] %s kills=%d deaths=%d cards=%s" % [p.pname, p.kills, p.deaths, str(p.cards)])
			if _args.has("debug"):
				var near: Vector3 = game.map.nav.get_point_position(game.map.nav.get_closest_point(p.global_position))
				print("        pos=%s yaw=%.2f vel=%s alive=%s near_node=%s" % [p.global_position.snapped(Vector3.ONE * 0.1), p.yaw, p.velocity.snapped(Vector3.ONE * 0.1), p.alive, near])
				if p.is_bot:
					print("        los=%s path=%d/%d target=%s" % [p.brain._has_los, p.brain._path_i, p.brain._path.size(), p.brain._target.pname if p.brain._target else "-"])
	get_tree().quit()
