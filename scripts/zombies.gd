extends Node
## Zombies mode rules: everyone (humans and CPU allies) on team 0 against
## endless waves of zombies (zombie.gd). Added under game.world by game.gd,
## which calls the hooks below.
##
## Wave n: 6 + 4n zombies (more with more players), released a few at a time
## with at most MAX_ALIVE on the map. Runners join from wave 3, brutes from
## wave 5, and every fifth wave adds a boss. Health, speed and damage grow
## every wave with no upper wave limit, so it goes on until the whole squad
## is down at once.
## Between waves (INTERMISSION seconds): fallen players come back, everyone
## alive picks a powerup card (player.offer_cards) and health refills.
## Dying during a wave = spectating until the wave is cleared.

const Zombie = preload("res://scripts/zombie.gd")
const UiKit = preload("res://scripts/ui_kit.gd")

const INTERMISSION := 9.0
const MAX_ALIVE := 26

var game
var wave := 0
var state := "start"         # start -> wave -> break -> wave ...
var to_spawn := 0
var alive_count := 0
var best_wave := 0
var banner := ""
var banner_t := 9.0
var _timer := 1.5
var _spawn_t := 0.0
var _boss_due := false


func prepare(parts: Array) -> Array:
	var out: Array = []
	for p in parts:
		var q: Dictionary = p.duplicate()
		q.team = 0
		out.append(q)
	return out


func start() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wave="):
			wave = int(a.substr(7)) - 1
	var spots: Array = game.map.spawn_points.duplicate()
	# Start together, above ground, near the middle of the map.
	spots = spots.filter(func(s): return s.y > -1.0 and s.y < 1.0)
	if spots.is_empty():
		spots = game.map.spawn_points.duplicate()
	spots.sort_custom(func(a, b): return a.length() < b.length())
	for i in game.players.size():
		var pos: Vector3 = spots[i % mini(spots.size(), maxi(4, game.players.size()))]
		game.players[i].spawn(pos, atan2(pos.x, pos.z))


func cards_on_death() -> bool:
	return false


func results_title() -> String:
	return "SURVIVED %d WAVE%s" % [best_wave, "" if best_wave == 1 else "S"]


func _physics_process(delta: float) -> void:
	banner_t += delta
	if game.frozen:
		return
	_timer -= delta
	match state:
		"start":
			if _timer <= 0.0:
				_next_wave()
		"wave":
			_spawn_t -= delta
			if to_spawn > 0 and _spawn_t <= 0.0 and alive_count < MAX_ALIVE + game.players.size() * 2:
				_spawn_t = maxf(0.35, 1.4 - wave * 0.06)
				var n := mini(to_spawn, 2 + wave / 4)
				for i in n:
					_spawn_one()
			if to_spawn <= 0 and alive_count <= 0:
				_wave_cleared()
		"break":
			var picking := false
			for p in game.players:
				if p.picking:
					picking = true
			if _timer <= 0.0 or (not picking and _timer < INTERMISSION - 4.0):
				_next_wave()


func _next_wave() -> void:
	wave += 1
	state = "wave"
	for p in game.players:
		if p.alive and p.picking:
			p._pick_card(p.card_sel)
	var squad: int = game.players.size()
	to_spawn = int((6 + wave * 4) * (0.7 + 0.3 * squad))
	_boss_due = wave % 5 == 0
	_spawn_t = 0.5
	_say("WAVE %d" % wave)
	Sfx.play("wave", -2.0)


func _wave_cleared() -> void:
	best_wave = wave
	state = "break"
	_timer = INTERMISSION
	_say("WAVE %d CLEARED!" % wave)
	Sfx.play("win", -6.0)
	for p in game.players:
		if not p.alive:
			respawn(p)
		p.offer_cards()


func _say(text: String) -> void:
	banner = text
	banner_t = 0.0


func _spawn_one() -> void:
	var kind := "walker"
	if _boss_due:
		kind = "boss"
		_boss_due = false
		_say("WAVE %d  -  ABOMINATION!" % wave)
	else:
		var r := randf()
		if wave >= 5 and r < minf(0.08 + wave * 0.01, 0.22):
			kind = "brute"
		elif wave >= 3 and r < minf(0.3 + wave * 0.02, 0.5):
			kind = "runner"
	var z = Zombie.new()
	z.game = game
	z.setup(kind, wave)
	var pos := _spawn_point()
	game.world.add_child(z)
	z.global_position = pos
	z.rotation.y = randf() * TAU
	z.reset_physics_interpolation()
	_rise(pos)
	to_spawn -= 1
	alive_count += 1


## A dust puff where a zombie claws its way out.
func _rise(pos: Vector3) -> void:
	var Fx = preload("res://scripts/fx.gd")
	Fx.puff(game.world, pos + Vector3(0, 0.2, 0), Color(0.35, 0.3, 0.25, 0.7), 8, 0.8)


## Somewhere on the nav graph, out of sight range of every player if possible.
func _spawn_point() -> Vector3:
	var best := Vector3.ZERO
	var best_d := -1.0
	for i in 10:
		var p: Vector3 = game.map.random_nav_point()
		var nearest := 1e9
		for pl in game.players:
			if pl.alive:
				nearest = minf(nearest, pl.global_position.distance_to(p))
		if nearest > 15.0 and nearest < 45.0:
			return p + Vector3(0, 0.1, 0)
		if nearest > best_d:
			best_d = nearest
			best = p
	return best + Vector3(0, 0.1, 0)


func on_zombie_died(_z, _attacker) -> void:
	alive_count -= 1


func on_died(_victim, _attacker) -> void:
	for p in game.players:
		if p.alive:
			return
	best_wave = wave - 1
	_say("OVERRUN!")
	game.end_match(null)


## Back in the fight next to a living teammate (or a spawn point).
func respawn(p) -> void:
	var pos: Vector3 = game.map.spawn_points[randi() % game.map.spawn_points.size()]
	for o in game.players:
		if o != p and o.alive and o.is_on_floor():
			pos = o.global_position + Vector3(randf_range(-1.5, 1.5), 0.3, randf_range(-1.5, 1.5))
			break
	p.spawn(pos, atan2(pos.x, pos.z))


## CPU allies stick near the humans when nothing is attacking.
func bot_goal(p):
	for o in game.players:
		if o != p and o.alive and not o.is_bot:
			if o.global_position.distance_to(p.global_position) > 8.0:
				return o.global_position
			return null
	return null


## Top-of-screen strip for hud.gd: wave, zombies left, squad.
func draw_strip(hud, ci: Control, s: float) -> void:
	var w: float = ci.size.x
	var left: int = to_spawn + alive_count
	var bw := 230.0 * s
	var r := Rect2((w - bw) * 0.5, 6 * s, bw, 40 * s)
	UiKit.card(ci, r, UiKit.PANEL, 20 * s, s)
	hud._t(Vector2(r.position.x + 16 * s, r.position.y + 28 * s), "WAVE %d" % maxi(wave, 1), 20, UiKit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, ci)
	var info := ""
	if state == "break":
		info = "NEXT IN %d" % ceili(maxf(_timer, 0.0))
	else:
		info = "%d LEFT" % left
	UiKit.icon(ci, "skull", Vector2(r.end.x - 98 * s, r.position.y + 20 * s), 7 * s, Color(0.7, 1.0, 0.5))
	hud._t(Vector2(r.end.x - 86 * s, r.position.y + 27 * s), info, 15, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, ci)


## Signature for the HUD's cached strip layer.
func strip_sig() -> Array:
	return [wave, to_spawn + alive_count, state, ceili(maxf(_timer, 0.0)) if state == "break" else 0]
