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
##
## Party-kart extras (all ours): rows of GIFT BOXES across the road give an
## item (fire / RT uses it): TURBO, TRIPLE TURBO, BONK BOMB (rolls ahead along
## the track and spins out the first car it reaches), GOO (dropped behind,
## spins out whoever drives through), BUBBLE SHIELD (blocks one hit). Two
## PERKS apply at once and last the race: STICKY TYRES (+30 % steering) and
## BIG TANK (turbos last half as long again). Cars further back roll better
## items. BOOST PADS on the straights give a short turbo; COINS add 1.5 %
## top speed each (up to 10; a spin-out drops 2).

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
var boxes: Array = []            # [Node3D, position, cooldown]
var pads: Array = []             # [position, forward]
var coins_on_track: Array = []   # [Node3D, position, cooldown]
var bombs: Array = []            # {node, along, lat, owner, life}
var goos: Array = []             # {node, pos, owner, life, armed}
var _deco_t := 0.0

const ITEM_NAMES := {"turbo": "TURBO", "turbo3": "TRIPLE TURBO", "bomb": "BONK BOMB", "goo": "GOO", "shield": "BUBBLE SHIELD"}
const ITEM_COLORS := {"turbo": Color(1.0, 0.55, 0.15), "turbo3": Color(1.0, 0.35, 0.1), "bomb": Color(0.95, 0.3, 0.6), "goo": Color(0.45, 0.9, 0.3), "shield": Color(0.45, 0.8, 1.0)}
const PERK_NAMES := {"grip": "STICKY TYRES", "tank": "BIG TANK"}


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
		st[p] = {"idx": k, "lap": 0, "moved_t": 0.0, "lap_t": 0.0, "best": -1.0, "finish": -1.0,
			"item": "", "uses": 0, "fire_prev": false, "coins": 0, "perks": [], "hold": 0.0, "pad_t": 0.0}
		v.add_driver_hands(p.kind, p.color)
		if p.is_bot:
			var b := RaceBrain.new()
			b.race = self
			b.skill = p.brain.skill
			b.pace = lerpf(0.86, 0.99, b.skill)
			p.brain = b
	banner = "%d LAP%s - GO!" % [laps, "" if laps == 1 else "S"]
	banner_t = -3.6
	_lay_track_toys()


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
		if racing:
			_items_tick(p, v, s, delta)
		if not racing:
			s.moved_t = game.time
			continue
		var flipped: bool = v.global_transform.basis.y.y < 0.3
		if p.brain.interact or game.time - s.moved_t > 4.0 or flipped or v.global_position.y < -2.0:
			_reset(p)
	if racing:
		_toys_tick(delta)
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
		sig.append(st[p].item)
		sig.append(st[p].uses)
		sig.append(st[p].coins)
		sig.append(st[p].perks.size())
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
	# Item slot (top right): what you hold, how many, fire to use.
	var ir := Rect2(w - 150 * s, 8 * s, 140 * s, 64 * s)
	UiKit.card(ci, ir, UiKit.PANEL, 18 * s, s)
	if sd.item != "":
		var col: Color = ITEM_COLORS[sd.item]
		ci.draw_circle(ir.position + Vector2(30 * s, 32 * s), 20 * s, col)
		ci.draw_circle(ir.position + Vector2(30 * s, 32 * s), 13 * s, col.lerp(Color.WHITE, 0.5))
		var label: String = ITEM_NAMES[sd.item] + (" x%d" % sd.uses if sd.uses > 1 else "")
		hud._t(Vector2(ir.position.x + 56 * s, ir.position.y + 30 * s), label, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, ir.size.x - 60 * s, 700, ci)
		var pad: bool = p.brain.device >= 0
		hud._t(Vector2(ir.position.x + 56 * s, ir.position.y + 50 * s), ("RT" if pad else "CLICK") + " TO USE", 9, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_LEFT, -1, 700, ci)
	else:
		hud._t(Vector2(ir.position.x, ir.position.y + 38 * s), "NO ITEM", 11, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER, ir.size.x, 700, ci)
	# Coins and perks under it.
	var cy := ir.end.y + 18 * s
	ci.draw_circle(Vector2(ir.position.x + 14 * s, cy - 5 * s), 8 * s, Color(1.0, 0.8, 0.2))
	hud._t(Vector2(ir.position.x + 28 * s, cy), "%d / 10" % sd.coins, 12, Color(1.0, 0.85, 0.35), HORIZONTAL_ALIGNMENT_LEFT, -1, 700, ci)
	for i in sd.perks.size():
		hud._t(Vector2(ir.position.x, cy + (i + 1) * 16 * s), PERK_NAMES[sd.perks[i]], 10, Color(0.7, 1.0, 0.7), HORIZONTAL_ALIGNMENT_LEFT, -1, 700, ci)


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


# --------------------------------------------------------------------------
# Party-kart toys: gift boxes, boost pads, coins, bombs, goo
# --------------------------------------------------------------------------

func _frac_idx(f: float) -> int:
	return int(f * n) % n


## Sample index near `i` where the track runs straight (for pads).
func _straight_near(i: int) -> int:
	for k in 14:
		var j := (i + k) % n
		if RaceMap._bend(path, j) < 0.02 and RaceMap._bend(path, (j + 3) % n) < 0.02:
			return j
	return i


func _lay_track_toys() -> void:
	# Gift box rows across the road.
	for f in [0.12, 0.4, 0.68, 0.9]:
		var i := _frac_idx(f)
		var nrm := RaceMap._normal(path, i)
		for lat in [-4.8, -1.6, 1.6, 4.8]:
			var pos: Vector3 = path[i] + nrm * lat + Vector3(0, 1.0, 0)
			var node := _gift_node(boxes.size())
			node.position = pos
			game.world.add_child(node)
			boxes.append([node, pos, 0.0])
	# Boost pads on straights.
	for f in [0.03, 0.27, 0.55, 0.8]:
		var i := _straight_near(_frac_idx(f))
		var fwd: Vector3 = (path[(i + 1) % n] - path[i]).normalized()
		var lat_side := 3.0 if pads.size() % 2 == 0 else -3.0
		var pos: Vector3 = path[i] + RaceMap._normal(path, i) * lat_side
		pads.append([pos, fwd])
		game.world.add_child(_pad_node(pos, fwd))
	# Coin lines.
	for f in [0.2, 0.33, 0.5, 0.62, 0.77, 0.95]:
		var i := _frac_idx(f)
		var lat := 3.5 if coins_on_track.size() % 2 == 0 else -3.5
		for c in 5:
			var j := (i + c) % n
			var pos: Vector3 = path[j] + RaceMap._normal(path, j) * lat + Vector3(0, 0.9, 0)
			var node := _coin_node()
			node.position = pos
			game.world.add_child(node)
			coins_on_track.append([node, pos, 0.0])


## Pickups, items and pads for one car.
func _items_tick(p, v, s: Dictionary, delta: float) -> void:
	var pos: Vector3 = v.global_position
	s.pad_t = maxf(0.0, s.pad_t - delta)
	for b in boxes:
		if b[2] <= 0.0 and _flat(b[1], pos) < 2.3:
			b[2] = 3.0
			b[0].visible = false
			Fx.sparks(game.world, b[1], Color(1.0, 0.8, 0.4), 16, 6.0)
			if s.item == "":
				_give_item(p, v, s)
	for c in coins_on_track:
		if c[2] <= 0.0 and _flat(c[1], pos) < 1.9:
			c[2] = 8.0
			c[0].visible = false
			if s.coins < 10:
				s.coins += 1
				v.coin_bonus = s.coins * 0.015
			Sfx.play_at("tick", c[1], -6.0, 1.6)
	for pd in pads:
		if s.pad_t <= 0.0:
			var rel: Vector3 = pos - pd[0]
			var along: float = rel.dot(pd[1])
			var side: float = rel.dot(Vector3(-pd[1].z, 0, pd[1].x))
			if absf(along) < 2.4 and absf(side) < 2.2:
				s.pad_t = 1.0
				v.boost(1.1 * (1.5 if "tank" in s.perks else 1.0))
	# Use the item: fire (edge).
	var fire: bool = p.brain.fire
	var pressed: bool = fire and not s.fire_prev
	s.fire_prev = fire
	if p.is_bot and s.item != "":
		s.hold += delta
		pressed = s.hold > _bot_wait(p, v, s)
	if pressed and s.item != "":
		_use_item(p, v, s)


## When a CPU racer fires its item.
func _bot_wait(p, v, s: Dictionary) -> float:
	match s.item:
		"turbo", "turbo3":
			return 0.6 if RaceMap._bend(path, (int(s.idx) + 5) % n) < 0.03 else 99.0
		"bomb":
			return 0.8 if _car_ahead(p, 45.0) != null else 6.0
		"shield":
			return 0.4
		_:
			return 1.5


func _give_item(p, v, s: Dictionary) -> void:
	# Further back = better luck (more turbos and bombs, no goo).
	var place: int = maxi(1, order.find(p) + 1)
	var back: float = float(place - 1) / maxf(1.0, order.size() - 1)
	var bag: Array = ["goo", "goo", "shield", "bomb", "turbo", "grip", "tank"]
	if back > 0.3:
		bag = ["turbo", "bomb", "bomb", "shield", "turbo3", "grip", "tank"]
	if back > 0.7:
		bag = ["turbo3", "turbo3", "bomb", "turbo", "shield", "tank", "grip"]
	var pick: String = bag[randi() % bag.size()]
	if pick in PERK_NAMES:
		if pick in s.perks:
			pick = "turbo"
		else:
			s.perks.append(pick)
			if pick == "grip":
				v.grip = 1.3
			p.say("PERK: %s!" % PERK_NAMES[pick])
			Sfx.play_at("card", v.global_position, -4.0, 1.2)
			return
	s.item = pick
	s.uses = 3 if pick == "turbo3" else 1
	s.hold = 0.0
	Sfx.play_at("join", v.global_position, -6.0, 1.3)


func _use_item(p, v, s: Dictionary) -> void:
	var tank := 1.5 if "tank" in s.perks else 1.0
	match s.item:
		"turbo", "turbo3":
			v.boost(1.6 * tank)
		"bomb":
			var nrm := RaceMap._normal(path, int(s.idx))
			var lat: float = (v.global_position - path[int(s.idx)]).dot(nrm)
			var node := _bomb_node()
			game.world.add_child(node)
			bombs.append({"node": node, "along": float((int(s.idx) + 2) % n), "lat": lat, "owner": p, "life": 7.0})
			Sfx.play_at("shot_bomb", v.global_position, -2.0, 1.2)
		"goo":
			var back: Vector3 = v.global_transform * Vector3(0, 0.05, 3.6)
			back.y = 0.06
			var node := _goo_node()
			node.position = back
			game.world.add_child(node)
			goos.append({"node": node, "pos": back, "owner": p, "life": 30.0, "armed": 0.5})
			Sfx.play_at("pop", back, -4.0, 0.7)
		"shield":
			v.shield(8.0)
	s.uses -= 1
	s.hold = 0.0
	if s.uses <= 0:
		s.item = ""


func _car_ahead(p, within: float):
	var mine: float = _score(p)
	var best = null
	var best_gap := 1e9
	for o in st:
		if o == p:
			continue
		var gap: float = _score(o) - mine
		if gap > 0.0 and gap * RaceMap.STEP < within and gap < best_gap:
			best_gap = gap
			best = o
	return best


## Spin a car out (bomb / goo); it drops two coins unless shielded.
func _hit(p) -> void:
	var v = cars.get(p)
	if v == null:
		return
	if v.spin_out():
		var s: Dictionary = st[p]
		s.coins = maxi(0, int(s.coins) - 2)
		v.coin_bonus = s.coins * 0.015
		p.say("SPUN OUT!")


## Moving / timed toys (once per tick, all cars).
func _toys_tick(delta: float) -> void:
	for b in boxes:
		if b[2] > 0.0:
			b[2] -= delta
			if b[2] <= 0.0:
				b[0].visible = true
				b[0].scale = Vector3.ONE * 0.2
				create_tween().tween_property(b[0], "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for c in coins_on_track:
		if c[2] > 0.0:
			c[2] -= delta
			if c[2] <= 0.0:
				c[0].visible = true
	# Bombs roll along the track, a little above it.
	for b in bombs.duplicate():
		b.life -= delta
		b.along = fmod(b.along + 52.0 * delta / RaceMap.STEP, float(n))
		var i := int(b.along)
		var f: float = b.along - i
		var a: Vector3 = path[i]
		var c: Vector3 = path[(i + 1) % n]
		var pos: Vector3 = a.lerp(c, f) + RaceMap._normal(path, i) * b.lat * 0.9 + Vector3(0, 0.55, 0)
		b.lat *= 1.0 - delta * 0.8       # drifts towards the racing line
		b.node.position = pos
		b.node.rotation.x -= delta * 14.0
		var hit_car = null
		for o in cars:
			if o != b.owner and _flat(cars[o].global_position, pos) < 2.4:
				hit_car = o
				break
		if hit_car != null or b.life <= 0.0:
			if hit_car != null:
				_hit(hit_car)
			Fx.puff(game.world, pos, Color(1.0, 0.6, 0.8, 0.9), 14, 1.4)
			Fx.sparks(game.world, pos, Color(1.0, 0.7, 0.3), 22, 8.0)
			Sfx.play_at("boom", pos, -6.0, 1.4)
			b.node.queue_free()
			bombs.erase(b)
	for g in goos.duplicate():
		g.life -= delta
		g.armed -= delta
		var gone: bool = g.life <= 0.0
		for o in cars:
			if gone:
				break
			if (g.armed <= 0.0 or o != g.owner) and _flat(cars[o].global_position, g.pos) < 2.3:
				_hit(o)
				gone = true
		if gone:
			g.node.queue_free()
			goos.erase(g)
	# Spin and bob the pickups.
	_deco_t += delta
	for b in boxes:
		b[0].rotation.y = _deco_t * 1.4
		b[0].position.y = b[1].y + sin(_deco_t * 2.5 + b[1].x) * 0.15
	for c in coins_on_track:
		c[0].rotation.y = _deco_t * 4.0


func _mat(col: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.45
	m.rim_enabled = true
	m.rim = 0.3
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	return m


func _cube(parent: Node3D, size: Vector3, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## A wrapped party gift: pastel paper, a contrasting ribbon cross and a bow.
func _gift_node(i: int) -> Node3D:
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var papers := [Color(1.0, 0.45, 0.6), Color(0.4, 0.75, 1.0), Color(0.6, 0.9, 0.4), Color(1.0, 0.8, 0.3), Color(0.75, 0.55, 1.0)]
	var paper: Color = papers[i % papers.size()]
	var ribbon := Color(1, 1, 1) if i % 2 == 0 else Color(1.0, 0.85, 0.3)
	_cube(root, Vector3(1.1, 1.1, 1.1), _mat(paper, 0.25))
	var rm := _mat(ribbon, 0.4)
	_cube(root, Vector3(1.14, 1.14, 0.2), rm)
	_cube(root, Vector3(0.2, 1.14, 1.14), rm)
	for k in 2:
		var loop := _cube(root, Vector3(0.4, 0.25, 0.14), rm, Vector3(0, 0.68, 0))
		loop.rotation = Vector3(0, k * PI * 0.5, 0.5 if k == 0 else -0.5)
	return root


func _coin_node() -> Node3D:
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = _mat(Color(1.0, 0.78, 0.2), 0.6)
	mi.rotation.x = PI * 0.5
	root.add_child(mi)
	var star := Label3D.new()
	star.text = "*"
	star.font_size = 64
	star.pixel_size = 0.008
	star.modulate = Color(1, 1, 0.8)
	star.position = Vector3(0, 0, 0.06)
	root.add_child(star)
	return root


## A boost pad: glowing orange chevrons pointing down the track.
func _pad_node(pos: Vector3, fwd: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos + Vector3(0, 0.075, 0)
	root.rotation.y = atan2(-fwd.x, -fwd.z)
	_cube(root, Vector3(4.2, 0.03, 4.6), _mat(Color(0.15, 0.1, 0.25)))
	var glow := _mat(Color(1.0, 0.55, 0.15), 1.6)
	for k in 3:
		var z := 1.4 - k * 1.4
		for sgn in [-1.0, 1.0]:
			var bar := _cube(root, Vector3(1.6, 0.04, 0.32), glow, Vector3(sgn * 0.62, 0.02, z))
			bar.rotation.y = sgn * 0.6
	return root


func _bomb_node() -> Node3D:
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = _mat(Color(0.18, 0.12, 0.25))
	root.add_child(mi)
	_cube(root, Vector3(1.14, 0.18, 0.18), _mat(Color(0.95, 0.3, 0.6), 0.8))
	_cube(root, Vector3(0.12, 0.3, 0.12), _mat(Color(1.0, 0.8, 0.3), 1.5), Vector3(0, 0.6, 0))
	return root


func _goo_node() -> Node3D:
	var root := Node3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.6
	cm.bottom_radius = 1.9
	cm.height = 0.12
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = _mat(Color(0.45, 0.9, 0.3), 0.3)
	root.add_child(mi)
	for k in 4:
		var blob := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 0.4
		blob.mesh = sm
		blob.material_override = mi.material_override
		blob.position = Vector3(cos(k * 1.7) * 0.9, 0.1, sin(k * 1.7) * 0.9)
		root.add_child(blob)
	return root
