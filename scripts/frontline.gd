extends Node
## Frontline mode rules (Battlefield-inspired conquest) on the FRONTLINE map
## (map_front.gd). Added under game.world by game.gd, which calls the hooks.
##
## Teams: 0 = BLUE (west base), 1 = ORANGE (east base). config.teams
## "versus" splits the humans between the teams (P1 blue, P2 orange, ...);
## "coop" puts every human on blue. CPU soldiers fill both teams to
## TEAM_SIZE each.
## Tickets: each team starts with config.kill_target tickets. Every death
## costs one; holding more flags than the enemy drains them by one per flag
## of difference every BLEED_TIME seconds. A team at 0 tickets loses.
## Flags A / B / C: stand within FLAG_RADIUS with no living enemy there to
## swing the flag towards your team (faster with more people). A flag first
## goes neutral, then turns.
## Spawning: everyone starts by parachute over their base. A respawn (after
## the usual card pick) drops in by parachute over the team's most forward
## flag, or lands on the base if the team holds none.
## Vehicles: 2 buggies, a tank and a helicopter per base (vehicle.gd). A
## destroyed vehicle comes back at its home spot after VEHICLE_RESPAWN s.

const Vehicle = preload("res://scripts/vehicle.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Fx = preload("res://scripts/fx.gd")

const TEAM_SIZE := 6
const FLAG_RADIUS := 9.0
const BLEED_TIME := 4.0
const VEHICLE_RESPAWN := 30.0
const TEAM_NAMES := ["BLUE", "ORANGE"]
const TEAM_COLORS := [Color(0.25, 0.55, 1.0), Color(1.0, 0.5, 0.18)]
const LETTERS := ["A", "B", "C"]

var game
var tickets := [100, 100]
var flag_owner := [-1, -1, -1]      # -1 neutral, else team
var flag_progress := [0.0, 0.0, 0.0] # 0..1 towards flag_side
var flag_side := [-1, -1, -1]       # team currently filling the flag
var banner := ""
var banner_t := 9.0
var winner_team := -1
var _bleed := BLEED_TIME
var _flag_nodes: Array = []          # [{cloth_mat, ring_mat, light, pole}]
var _goals := {}                     # bot -> [goal, time]


func prepare(parts: Array) -> Array:
	tickets = [game.kill_target, game.kill_target]
	var versus: bool = game.config.get("teams", "versus") == "versus"
	var out: Array = []
	var counts := [0, 0]
	var h := 0
	for p in parts:
		var q: Dictionary = p.duplicate()
		if not q.bot:
			q.team = (h % 2) if versus else 0
			h += 1
			counts[q.team] += 1
			out.append(q)
	for p in parts:
		if p.bot:
			var q: Dictionary = p.duplicate()
			q.team = 0 if counts[0] <= counts[1] else 1
			counts[q.team] += 1
			out.append(q)
	# Fill both teams with CPU soldiers.
	for team in 2:
		while counts[team] < TEAM_SIZE:
			counts[team] += 1
			out.append({"device": -2, "bot": true, "view": false, "team": team, "kind": randi() % 7,
				"color": TEAM_COLORS[team].lerp(Color(randf(), randf(), randf()), 0.15), "hat": randi() % 6, "face": randi() % 4})
	# CPU soldiers wear their team colour.
	for q in out:
		if q.bot:
			q.color = TEAM_COLORS[q.team].lerp(q.get("color", Color.WHITE), 0.15)
	return out


func start() -> void:
	for p in game.players:
		p.name_label.modulate = TEAM_COLORS[p.team].lerp(Color.WHITE, 0.35)
		var base: Vector3 = game.map.bases[p.team]
		_drop(p, base + Vector3(randf_range(-10, 10), 0, randf_range(-14, 14)), randf_range(55.0, 80.0))
	for spot in game.map.vehicle_spots:
		_spawn_vehicle(spot[0], spot[1], spot[2])
	for i in 3:
		_build_flag(i)
	# Dev flag --drive=type: player 1 starts in their team's vehicle of that type.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--drive="):
			var p = game.players[0]
			for v in game.vehicles:
				if v.type == a.substr(8) and v.home_team == p.team:
					p.spawn(v.global_position + Vector3(3, 0.5, 0), p.yaw)
					v.enter(p)
					if v.type == "heli":
						v.global_position.y += 25.0
					break


func cards_on_death() -> bool:
	return true


func results_title() -> String:
	if winner_team < 0:
		return "DRAW"
	return "%s WINS!" % TEAM_NAMES[winner_team]


func _say(text: String) -> void:
	banner = text
	banner_t = 0.0


# --------------------------------------------------------------------------
# Spawning
# --------------------------------------------------------------------------

## Put `p` in the sky above `pos` with a parachute ready.
func _drop(p, pos: Vector3, height: float) -> void:
	var enemy_base: Vector3 = game.map.bases[1 - p.team]
	p.spawn(pos + Vector3(0, height, 0), atan2(-(enemy_base.x - pos.x), -(enemy_base.z - pos.z)))
	p.skydive = height > 6.0
	p.spawn_protect = 3.0


func respawn(p) -> void:
	var best := -1
	var best_d := 1e9
	var enemy_base: Vector3 = game.map.bases[1 - p.team]
	for i in 3:
		if flag_owner[i] == p.team and not _contested(i):
			var d: float = game.map.flags[i].distance_to(enemy_base)
			if d < best_d:
				best_d = d
				best = i
	if best >= 0 and randf() < 0.8:
		var f: Vector3 = game.map.flags[best]
		_drop(p, f + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12)), randf_range(40.0, 55.0))
	else:
		var base: Vector3 = game.map.bases[p.team]
		_drop(p, base + Vector3(randf_range(-6, 6), 0.2, randf_range(-12, 12)), 0.2)


func _spawn_vehicle(type: String, xf: Transform3D, team: int) -> void:
	var v = Vehicle.new()
	v.game = game
	v.setup(type, xf, team, TEAM_COLORS[team])
	game.world.add_child(v)
	v.global_transform = xf


func vehicle_destroyed(type: String, home: Transform3D, team: int) -> void:
	get_tree().create_timer(VEHICLE_RESPAWN, false).timeout.connect(func():
		if not game.match_over:
			_spawn_vehicle(type, home, team))


# --------------------------------------------------------------------------
# Flags and tickets
# --------------------------------------------------------------------------

func _build_flag(i: int) -> void:
	var pos: Vector3 = game.map.flags[i]
	var root := Node3D.new()
	root.position = pos
	game.world.add_child(root)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.75, 0.76, 0.8)
	metal.metallic = 0.8
	metal.roughness = 0.3
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.09
	pole.height = 9.0
	var pm := MeshInstance3D.new()
	pm.mesh = pole
	pm.material_override = metal
	pm.position.y = 4.5
	root.add_child(pm)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.9, 0.9, 0.9)
	cloth.emission_enabled = true
	cloth.emission = Color(0.6, 0.6, 0.6)
	cloth.emission_energy_multiplier = 0.4
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flag := BoxMesh.new()
	flag.size = Vector3(2.2, 1.3, 0.05)
	var fm := MeshInstance3D.new()
	fm.mesh = flag
	fm.material_override = cloth
	fm.position = Vector3(1.15, 8.2, 0)
	root.add_child(fm)
	var lab := Label3D.new()
	lab.text = LETTERS[i]
	lab.font = UiKit.font(700)
	lab.font_size = 160
	lab.pixel_size = 0.01
	lab.outline_size = 12
	lab.outline_modulate = Color(0, 0, 0.02, 0.55)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position.y = 10.5
	root.add_child(lab)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(1, 1, 1, 0.5)
	var torus := TorusMesh.new()
	torus.inner_radius = FLAG_RADIUS - 0.25
	torus.outer_radius = FLAG_RADIUS
	torus.rings = 64
	torus.ring_segments = 4
	var rm := MeshInstance3D.new()
	rm.mesh = torus
	rm.material_override = ring_mat
	rm.scale = Vector3(1, 0.2, 1)
	rm.position.y = 0.1
	rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rm)
	var light := OmniLight3D.new()
	light.position.y = 6.0
	light.omni_range = 12.0
	light.light_energy = 1.2
	root.add_child(light)
	_flag_nodes.append({"cloth": cloth, "ring": ring_mat, "light": light, "flag": fm, "label": lab})
	_paint_flag(i)


func _paint_flag(i: int) -> void:
	var n: Dictionary = _flag_nodes[i]
	var col: Color = Color(0.85, 0.85, 0.85) if flag_owner[i] < 0 else TEAM_COLORS[flag_owner[i]]
	n.cloth.albedo_color = col
	n.cloth.emission = col
	n.ring.albedo_color = Color(col, 0.55)
	n.light.light_color = col
	n.label.modulate = col.lerp(Color.WHITE, 0.3)


func _contested(i: int) -> bool:
	var c := _counts(i)
	return c[0] > 0 and c[1] > 0


## Living soldiers of each team inside flag i's circle (drivers count).
func _counts(i: int) -> Array:
	var f: Vector3 = game.map.flags[i]
	var c := [0, 0]
	for p in game.players:
		if not p.alive or p.team < 0:
			continue
		var d: Vector3 = p.global_position - f
		if Vector2(d.x, d.z).length() < FLAG_RADIUS and absf(d.y) < 7.0:
			c[p.team] += 1
	return c


func _physics_process(delta: float) -> void:
	banner_t += delta
	if game.frozen:
		return
	for i in 3:
		var c := _counts(i)
		var team := -1
		if c[0] > 0 and c[1] == 0:
			team = 0
		elif c[1] > 0 and c[0] == 0:
			team = 1
		if team < 0:
			continue
		var rate := 0.12 * sqrt(float(c[team]))
		if flag_owner[i] == team:
			flag_progress[i] = minf(1.0, flag_progress[i] + rate * delta)
			flag_side[i] = team
		elif flag_side[i] != team and flag_progress[i] > 0.0:
			# Pull the enemy's (or the previous owner's) progress down first.
			flag_progress[i] -= rate * delta
			if flag_progress[i] <= 0.0:
				flag_progress[i] = 0.0
				flag_side[i] = team
				if flag_owner[i] >= 0:
					_say("%s LOST FLAG %s" % [TEAM_NAMES[flag_owner[i]], LETTERS[i]])
					_notify(flag_owner[i], "lost")
					flag_owner[i] = -1
					_paint_flag(i)
		else:
			flag_side[i] = team
			flag_progress[i] += rate * delta
			if flag_progress[i] >= 1.0:
				flag_progress[i] = 1.0
				flag_owner[i] = team
				_paint_flag(i)
				_say("%s CAPTURED FLAG %s" % [TEAM_NAMES[team], LETTERS[i]])
				_notify(team, "capture")
				Fx.ring(game.world, game.map.flags[i] + Vector3(0, 0.3, 0), Color(TEAM_COLORS[team], 0.9), 1.0, FLAG_RADIUS, 0.6)
		# Flag cloth height shows the progress.
		_flag_nodes[i].flag.position.y = 2.0 + 6.2 * (flag_progress[i] if flag_owner[i] >= 0 or flag_side[i] >= 0 else 0.0)
		if flag_owner[i] < 0 and flag_side[i] >= 0:
			var n: Dictionary = _flag_nodes[i]
			n.cloth.albedo_color = Color(0.85, 0.85, 0.85).lerp(TEAM_COLORS[flag_side[i]], flag_progress[i])
	# Ticket bleed for holding more flags.
	_bleed -= delta
	if _bleed <= 0.0:
		_bleed = BLEED_TIME
		var held := [0, 0]
		for o in flag_owner:
			if o >= 0:
				held[o] += 1
		if held[0] != held[1]:
			var loser := 0 if held[0] < held[1] else 1
			tickets[loser] = maxi(0, tickets[loser] - absi(held[0] - held[1]))
			_check_end()


func _notify(team: int, sound: String) -> void:
	for p in game.players:
		if p.has_view:
			Sfx.play("capture" if (p.team == team) == (sound == "capture") else "lost", -4.0)
			return


func on_died(victim, _attacker) -> void:
	if victim.team >= 0:
		tickets[victim.team] = maxi(0, tickets[victim.team] - 1)
	_check_end()


func _check_end() -> void:
	if game.match_over:
		return
	for team in 2:
		if tickets[team] <= 0:
			winner_team = 1 - team
			_say("%s WINS!" % TEAM_NAMES[winner_team])
			game.end_match(null)
			return


# --------------------------------------------------------------------------
# Bots: head for the nearest flag the team does not hold (or defend one)
# --------------------------------------------------------------------------

func bot_goal(p):
	var now: float = game.time
	if _goals.has(p) and now - _goals[p][1] < 6.0:
		var g: Vector3 = _goals[p][0]
		if p.global_position.distance_to(g) > 5.0:
			return g
	var best := -1
	var best_d := 1e9
	for i in 3:
		if flag_owner[i] == p.team and flag_progress[i] >= 1.0:
			continue
		var d: float = game.map.flags[i].distance_to(p.global_position) * randf_range(0.8, 1.2)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		best = randi() % 3
	var goal: Vector3 = game.map.flags[best] + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
	_goals[p] = [goal, now]
	return goal


# --------------------------------------------------------------------------
# HUD (hud.gd calls these)
# --------------------------------------------------------------------------

func strip_sig() -> Array:
	var sig: Array = [tickets[0], tickets[1]]
	for i in 3:
		sig.append(flag_owner[i])
		sig.append(flag_side[i])
		sig.append(int(flag_progress[i] * 20.0))
	return sig


## Ticket counters and the three flags, top centre.
func draw_strip(hud, ci: Control, s: float) -> void:
	var w: float = ci.size.x
	var bw := 330.0 * s
	var r := Rect2((w - bw) * 0.5, 6 * s, bw, 42 * s)
	UiKit.card(ci, r, UiKit.PANEL, 21 * s, s)
	var my_team: int = hud.player.team if hud.player != null else 0
	for team in 2:
		var x: float = r.position.x + 12 * s if team == 0 else r.end.x - 12 * s
		hud._t(Vector2(x - (0.0 if team == 0 else 60 * s), r.position.y + 29 * s), "%d" % tickets[team], 21, TEAM_COLORS[team].lerp(Color.WHITE, 0.3),
			HORIZONTAL_ALIGNMENT_LEFT if team == 0 else HORIZONTAL_ALIGNMENT_RIGHT, 60 * s, 700, ci)
	for i in 3:
		var c := Vector2(r.get_center().x + (i - 1) * 44 * s, r.position.y + 21 * s)
		var col: Color = Color(0.7, 0.7, 0.7) if flag_owner[i] < 0 else TEAM_COLORS[flag_owner[i]]
		ci.draw_circle(c, 15 * s, UiKit.INK)
		ci.draw_circle(c, 13 * s, col.darkened(0.35))
		if flag_side[i] >= 0 and flag_progress[i] < 1.0:
			ci.draw_arc(c, 13 * s, -PI * 0.5, -PI * 0.5 + TAU * flag_progress[i], 24, TEAM_COLORS[flag_side[i]], 3.5 * s)
		elif flag_owner[i] >= 0:
			ci.draw_arc(c, 13 * s, 0, TAU, 24, col.lerp(Color.WHITE, 0.2), 3.0 * s)
		hud._t(Vector2(c.x - 20 * s, c.y + 7 * s), LETTERS[i], 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 40 * s, 700, ci)
	var label := "YOU ARE %s" % TEAM_NAMES[my_team]
	hud._t(Vector2(0, r.end.y + 14 * s), label, 10, TEAM_COLORS[my_team].lerp(Color.WHITE, 0.4), HORIZONTAL_ALIGNMENT_CENTER, w, 700, ci)


## Flag letters on screen (live, every frame) so they are easy to find.
func draw_markers(hud, s: float) -> void:
	var cam: Camera3D = hud.get_viewport().get_camera_3d()
	if cam == null or hud.player == null:
		return
	for i in 3:
		var pos: Vector3 = game.map.flags[i] + Vector3(0, 6.0, 0)
		if cam.is_position_behind(pos):
			continue
		var sp: Vector2 = cam.unproject_position(pos)
		var col: Color = Color(0.85, 0.85, 0.85) if flag_owner[i] < 0 else TEAM_COLORS[flag_owner[i]]
		var d: float = hud.player.global_position.distance_to(game.map.flags[i])
		var mine: bool = flag_owner[i] == hud.player.team
		hud.draw_circle(sp, 13 * s, Color(UiKit.INK, 0.7))
		hud.draw_arc(sp, 13 * s, 0, TAU, 20, col, 2.5 * s)
		hud._t(Vector2(sp.x - 20 * s, sp.y + 6 * s), LETTERS[i], 15, col.lerp(Color.WHITE, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 40 * s)
		hud._t(Vector2(sp.x - 40 * s, sp.y + 28 * s), ("DEFEND %dm" if mine else "%dm") % int(d), 9, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 80 * s)
	# Inside a flag circle: capture progress.
	for i in 3:
		var f: Vector3 = game.map.flags[i]
		var dd: Vector3 = hud.player.global_position - f
		if Vector2(dd.x, dd.z).length() < FLAG_RADIUS and absf(dd.y) < 7.0 and hud.player.alive:
			var txt := ""
			if _contested(i):
				txt = "FLAG %s CONTESTED" % LETTERS[i]
			elif flag_owner[i] == hud.player.team and flag_progress[i] >= 1.0:
				txt = "FLAG %s SECURE" % LETTERS[i]
			else:
				txt = "CAPTURING %s  %d%%" % [LETTERS[i], int((flag_progress[i] if flag_side[i] == hud.player.team else 1.0 - flag_progress[i]) * 100.0)]
			var size: Vector2 = hud.size
			hud._t(Vector2(0, size.y * 0.2), txt, 16, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, size.x)
