extends Node
## Racing mode: everyone starts on the grid of the RACEWAY (map_race.gd) in
## their own race car (vehicle.gd "racer", in their colour) and races LAPS
## laps (the lobby's X / K chip). CPU racers fill the grid up to six.
##
## Progress: each car remembers the last sample of map.race_path it reached
## (searching a few samples ahead, so cutting across the infield gains
## nothing); crossing index 0 counts a lap. Place = laps, then sample, then
## distance to the next sample. Off the asphalt the car's top speed drops
## (vehicle.top_scale). Stuck for 4 s, upside down, off the map, or the
## driver presses interact (Y / E): the car is put back on the track at its
## last sample, facing the right way.
##
## The race ends when every human has finished, or 30 s after the winner
## crosses the line; places for the rest come from their progress.
## CPU drivers: RaceBrain below steers towards a point a little way down
## the path (further at speed) and lifts off for sharp bends.

const Vehicle = preload("res://scripts/vehicle.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Fx = preload("res://scripts/fx.gd")
const RaceMap = preload("res://scripts/map_race.gd")
const BotBrain = preload("res://scripts/bot_brain.gd")
const MAX_RACERS := 6

var game
var banner := ""
var banner_t := 9.0
var laps := 3
var path: Array = []
var n := 1
var cars := {}                   # player -> vehicle
var st := {}                     # player -> {idx, lap, moved_t, lap_t, best, finish}
var finished: Array = []         # players in finishing order
var first_finish := -1.0
var t0 := -1.0                   # game.time at the green light (race clock zero)


## The CPU driver.
class RaceBrain extends "res://scripts/bot_brain.gd":
	var race                     # the racing.gd node
	var pace := 1.0              # top-speed share (skill)

	func update_look(player, _delta: float) -> void:
		if player.vehicle != null:
			player.yaw = player.vehicle.global_rotation.y
			player.pitch = -0.15

	func update_buttons(player, _delta: float) -> void:
		move = Vector2.ZERO
		interact = false
		melee = false
		var v = player.vehicle
		if v == null or race == null or not race.st.has(player):
			return
		var s: Dictionary = race.st[player]
		var speed: float = absf(v._speed)
		var ahead := 3 + int(speed / 7.0)
		var target: Vector3 = race.path[(int(s.idx) + ahead) % race.n]
		var to: Vector3 = target - v.global_position
		var want := atan2(-to.x, -to.z)
		var diff := wrapf(want - v.global_rotation.y, -PI, PI)
		move.x = clampf(-diff * 2.6, -1.0, 1.0)
		# Lift off for the sharp ones.
		var far: Vector3 = race.path[(int(s.idx) + ahead + 6) % race.n]
		var corner := absf(wrapf(atan2(-(far.x - target.x), -(far.z - target.z)) - want, -PI, PI))
		move.y = 1.0
		if speed > 24.0 and (absf(diff) > 0.45 or corner > 0.9):
			move.y = 0.2
		v.top_scale = minf(v.top_scale, pace)


func prepare(parts: Array) -> Array:
	laps = clampi(int(game.kill_target), 1, 20)
	# Fill the grid with CPU racers.
	var out: Array = parts.duplicate()
	var kinds_used: Array = out.map(func(p): return p.get("kind", 0))
	var i := 0
	while out.size() < MAX_RACERS:
		i += 1
		out.append({"device": -2, "bot": true, "view": false, "kind": (i * 3) % 7, "color": Color.from_hsv(fmod(0.13 * i + 0.05, 1.0), 0.7, 0.95),
			"hat": i % 5, "face": i % 3, "back": 0})
	return out


func start() -> void:
	path = game.map.race_path
	n = path.size()
	game.kill_target = laps
	for i in game.players.size():
		var p = game.players[i]
		var slot: Array = RaceMap.grid_slot(path, i)
		var xf := Transform3D(Basis(Vector3.UP, slot[1]), slot[0] + Vector3(0, 0.3, 0))
		var v = Vehicle.new()
		v.game = game
		v.setup("racer", xf, -1, p.color)
		v.disarm()
		v.racing = true
		v.max_health = 1000000.0
		v.health = v.max_health
		game.world.add_child(v)
		v.global_transform = xf
		p.spawn(slot[0] + Vector3(2.5, 0.5, 0), slot[1])
		v.enter(p)
		cars[p] = v
		var k: int = posmod(-int(round((9.0 + (i / 2) * 8.0 + (i % 2) * 3.5) / RaceMap.STEP)), n)
		st[p] = {"idx": k, "lap": 0, "moved_t": 0.0, "lap_t": 0.0, "best": -1.0, "finish": -1.0}
		if p.is_bot:
			var b := RaceBrain.new()
			b.race = self
			b.skill = p.brain.skill
			b.pace = lerpf(0.86, 0.99, b.skill)
			p.brain = b
	banner = "%d LAP%s - GO!" % [laps, "" if laps == 1 else "S"]
	banner_t = -3.6


func cards_on_death() -> bool:
	return false


func weapon_pads() -> bool:
	return false


func vehicle_destroyed(_type: String, _home: Transform3D, _team: int) -> void:
	pass


func results_title() -> String:
	return "%s WINS THE RACE!" % finished[0].pname if not finished.is_empty() else "RACE OVER"


func bot_goal(_p):
	return null


func on_died(victim, _attacker) -> void:
	game.respawn_later(victim, 0.5)


func respawn(p) -> void:
	_reset(p)


# --------------------------------------------------------------------------
# Race tick
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	banner_t += delta
	if game == null or game.match_over or n < 2:
		return
	var racing: bool = game.countdown <= 0.0
	if racing and t0 < 0.0:
		t0 = game.time
		for p in st:
			st[p].lap_t = t0
	for p in st:
		var v = cars.get(p)
		if v == null or not is_instance_valid(v):
			continue
		var s: Dictionary = st[p]
		if v.driver != p and p.alive:
			v.enter(p)
		if s.finish >= 0.0:
			v.top_scale = 0.35          # cruise after the flag
			continue
		_progress(p, v, s)
		# Off the asphalt: slower.
		var d := _dist_to_path(v.global_position, int(s.idx))
		v.top_scale = 0.55 if d > RaceMap.W * 0.5 + 1.2 else 1.0
		if not racing:
			s.moved_t = game.time
			continue
		var flipped: bool = v.global_transform.basis.y.y < 0.3
		if p.brain.interact or game.time - s.moved_t > 4.0 or flipped or v.global_position.y < -2.0:
			_reset(p)
	_ranks()
	if first_finish >= 0.0:
		var humans_done := true
		for p in st:
			if not p.is_bot and st[p].finish < 0.0:
				humans_done = false
		if humans_done or game.time - first_finish > 30.0:
			_finish_race()


func _progress(p, v, s: Dictionary) -> void:
	var idx: int = s.idx
	var best := idx
	var best_d := _flat(path[idx], v.global_position)
	for k in range(1, 12):
		var j := (idx + k) % n
		var dd := _flat(path[j], v.global_position)
		if dd < best_d and dd < RaceMap.W * 1.3:
			best_d = dd
			best = j
	if best == idx:
		return
	s.moved_t = game.time
	if best < idx and idx - best > n / 2:
		# Crossed the line.
		s.lap += 1
		if s.lap >= 2:
			var lt: float = game.time - s.lap_t
			if s.best < 0.0 or lt < s.best:
				s.best = lt
		s.lap_t = game.time
		if s.lap > laps:
			s.finish = game.time
			finished.append(p)
			var place := finished.size()
			p.say("FINISHED %s!" % _ordinal(place))
			if place == 1:
				first_finish = game.time
				banner = "%s WINS!" % p.pname
				banner_t = 0.0
				Sfx.play("go", -2.0, 1.2)
		elif s.lap == laps and laps > 1:
			p.say("FINAL LAP!")
		elif s.lap > 1:
			p.say("LAP %d" % s.lap)
	s.idx = best


func _reset(p) -> void:
	var v = cars.get(p)
	if v == null or not is_instance_valid(v) or not st.has(p):
		return
	var s: Dictionary = st[p]
	var i: int = s.idx
	var a: Vector3 = path[i]
	var b: Vector3 = path[(i + 2) % n]
	var yaw := atan2(-(b.x - a.x), -(b.z - a.z))
	v.global_transform = Transform3D(Basis(Vector3.UP, yaw), a + Vector3(0, 0.6, 0))
	v.velocity = Vector3.ZERO
	v._speed = 0.0
	v.reset_physics_interpolation()
	if not p.alive:
		p.spawn(a + Vector3(0, 1.0, 0), yaw)
	if v.driver != p:
		v.enter(p)
	p.yaw = yaw
	s.moved_t = game.time
	Fx.ring(game.world, a + Vector3(0, 0.3, 0), Color(1, 1, 1, 0.8), 0.3, 2.5, 0.4)


## Progress score: laps, then samples, then closeness to the next sample.
func _score(p) -> float:
	var s: Dictionary = st[p]
	if s.finish >= 0.0:
		return 1e9 - s.finish
	var idx: int = s.idx
	var lap: int = s.lap
	if lap == 0 and idx > n / 2:
		lap = 0                          # on the grid, behind the line
		return float(idx - n) - _flat(path[(idx + 1) % n], cars[p].global_position) * 0.01
	return float(lap - 1) * n + idx + (1.0 - clampf(_flat(path[(idx + 1) % n], cars[p].global_position) / RaceMap.STEP, 0.0, 1.0))


## Store each player's place in `kills` (higher = better, for game.ranked)
## and remember the order for the HUD.
var order: Array = []

func _ranks() -> void:
	order = st.keys()
	order.sort_custom(func(a, b): return _score(a) > _score(b))
	for i in order.size():
		order[i].kills = MAX_RACERS - i
		order[i].deaths = 0


func _finish_race() -> void:
	_ranks()
	game.end_match(order[0])


## Results table: place, best lap, finishing time.
func result_stats(p) -> Array:
	var s: Dictionary = st.get(p, {})
	var place: int = order.find(p) + 1
	return [["PLACE", _ordinal(place)], ["BEST LAP", _clock(s.get("best", -1.0))],
		["TIME", _clock(s.finish - maxf(t0, 0.0)) if s.get("finish", -1.0) >= 0.0 else "DNF"]]


func ranked() -> Array:
	_ranks()
	return order.duplicate()


# --------------------------------------------------------------------------
# HUD
# --------------------------------------------------------------------------

func strip_sig() -> Array:
	var sig: Array = [int(game.time * 10.0)]
	for p in order:
		sig.append(st[p].lap)
	return sig


## Top centre: LAP x / N, your place, the race clock.
func draw_strip(hud, ci: Control, s: float) -> void:
	var w: float = ci.size.x
	var bw := 360.0 * s
	var r := Rect2((w - bw) * 0.5, 6 * s, bw, 46 * s)
	UiKit.card(ci, r, UiKit.PANEL, 23 * s, s)
	var p = hud.player
	if p == null or not st.has(p):
		return
	var sd: Dictionary = st[p]
	var lap := clampi(int(sd.lap), 1, laps)
	var place: int = order.find(p) + 1
	hud._t(Vector2(r.position.x + 16 * s, r.position.y + 31 * s), "LAP %d/%d" % [lap, laps], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 700, ci)
	hud._t(Vector2(r.position.x, r.position.y + 34 * s), "%s / %d" % [_ordinal(place), order.size()], 26, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, bw, 700, ci)
	var t: float = (sd.finish if sd.finish >= 0.0 else game.time) - (t0 if t0 >= 0.0 else game.time)
	hud._t(Vector2(r.position.x, r.position.y + 31 * s), _clock(maxf(0.0, t)), 18, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, bw - 16 * s, 700, ci)
	if sd.best > 0.0:
		hud._t(Vector2(0, r.end.y + 14 * s), "BEST LAP %s" % _clock(sd.best), 10, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, w, 700, ci)


## Places over the other cars.
func draw_markers(hud, s: float) -> void:
	var cam: Camera3D = hud.get_viewport().get_camera_3d()
	if cam == null:
		return
	for p in order:
		if p == hud.player or not cars.has(p):
			continue
		var pos: Vector3 = cars[p].global_position + Vector3(0, 2.2, 0)
		if cam.is_position_behind(pos) or cam.global_position.distance_to(pos) > 90.0:
			continue
		var sp: Vector2 = cam.unproject_position(pos)
		hud._t(Vector2(sp.x - 30 * s, sp.y), _ordinal(order.find(p) + 1), 14, p.color.lerp(Color.WHITE, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 60 * s)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _dist_to_path(pos: Vector3, idx: int) -> float:
	var best := 1e9
	for k in range(-2, 4):
		best = minf(best, _flat(path[posmod(idx + k, n)], pos))
	return best


static func _ordinal(i: int) -> String:
	if i <= 0:
		return "-"
	var suf := "TH"
	if i % 100 < 11 or i % 100 > 13:
		suf = ["TH", "ST", "ND", "RD", "TH", "TH", "TH", "TH", "TH", "TH"][i % 10]
	return "%d%s" % [i, suf]


static func _clock(t: float) -> String:
	if t < 0.0:
		return "-"
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]
