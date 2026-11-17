extends Control
## Join screen: a 3D stage (stage.gd) with six podiums and a 2D overlay.
## Polls every gamepad and the keyboard directly; whoever presses their join
## button takes the next free seat and their character pops onto a podium.
##
## Each seated player customises their character: up/down picks a category
## (ANIMAL, COLOR, HAT, FACE), left/right changes it. Loadouts, the chosen map,
## bot count and kill target are remembered in Settings.lobby (saved to the
## settings file), keyed by seat number.
##
## Shared controls: RT / G game mode (ROUNDS, ZOMBIES, FRONTLINE), Y / B-key
## bots (Frontline: teams versus / co-op), X / K kill target (Frontline:
## tickets), RB / M next map (Frontline has its own), LB / T visual theme
## (looks.gd: the stage behind the lobby and its colours change with it),
## Back / O options, Start / Enter to begin.
##
## main.gd calls activate() to show it and deactivate() before a match (the
## stage shares the root World3D with the match, so it has to be freed).
## Emits start(config) with the dictionary game.gd expects.

signal start(config)

const Stage = preload("res://scripts/stage.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Fx = preload("res://scripts/fx.gd")
const SettingsMenu = preload("res://scripts/settings_menu.gd")
const Map = preload("res://scripts/map.gd")
const Looks = preload("res://scripts/looks.gd")

const MAX_PLAYERS := 6
const KEYBOARD := -1
const KILL_TARGETS := [5, 10, 15, 20, 30]
const CATEGORIES := ["ANIMAL", "COLOR", "HAT", "BACK", "LOOK"]
const KEYS := ["kind", "color", "hat", "back", "sens"]
const SENS_STEPS := 10          # LOOK: this player's own look speed, 1-10
const MODES := ["rounds", "zombies", "frontline", "gungame", "medieval"]
const MODE_LABELS := ["ROUNDS", "ZOMBIES", "FRONTLINE", "GUN GAME", "MEDIEVAL"]
const TICKETS := [50, 100, 150, 200, 300]
const TAGLINES := ["FREE-FOR-ALL  -  EVERY KO DEALS YOU A POWERUP", "CO-OP SURVIVAL  -  ENDLESS WAVES OF ZOMBIES",
	"TEAM WAR  -  FLAGS, TANKS, HELICOPTERS, PARACHUTES", "EVERY KO HANDS YOU THE NEXT WEAPON  -  FINISH THE LADDER TO WIN",
	"SWORDS, BOWS, AXES AND SHIELDS  -  A FREE-FOR-ALL IN THE CASTLE"]

var seats: Array = []        # [{device, kind, color, hat, face, row}] in join order
var bots := 0
var target_i := 2
var map_i := 0
var theme_i := 0             # index into Looks.options()
var mode_i := 0
var versus := true           # Frontline: humans split between the teams
var message := ""
var message_t := 0.0

var _stage = null
var _slot_sig: Array = []
var _slot_char: Array = []
var _slot_bump: Array = []   # per-slot UI pop animation timers
var _bot_looks: Array = []   # random looks for the CPU seats
var _prev := {}
var _t := 0.0
var _armed := false          # ignore buttons still held from the previous screen
var _options
var _look_now := {}          # the theme the stage is showing (RANDOM resolved)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.joy_connection_changed.connect(_on_joy_changed)
	for i in MAX_PLAYERS:
		_slot_sig.append("")
		_slot_char.append(null)
		_slot_bump.append(1.0)
		_bot_looks.append({"kind": (i * 5 + 3) % UiKit.KIND_NAMES.size(), "hat": randi() % UiKit.HAT_NAMES.size(), "face": randi() % UiKit.FACE_NAMES.size(),
			"back": randi() % UiKit.BACK_NAMES.size()})
	bots = int(Settings.lobby.get("bots", 0))
	target_i = clampi(int(Settings.lobby.get("target", 2)), 0, KILL_TARGETS.size() - 1)
	map_i = clampi(int(Settings.lobby.get("map", 0)), 0, Map.ARENAS.size() - 1)
	theme_i = clampi(int(Settings.lobby.get("theme", 0)), 0, Looks.options().size() - 1)
	mode_i = clampi(int(Settings.lobby.get("mode", 0)), 0, MODES.size() - 1)
	versus = bool(Settings.lobby.get("versus", true))
	_options = SettingsMenu.new()
	add_child(_options)
	_options.closed.connect(func():
		_armed = false
		_prev.clear())


func activate() -> void:
	_armed = false
	_prev.clear()
	message = ""
	visible = true
	Sfx.music("lobby")
	if _stage == null:
		_build_stage()


## The 3D stage in the selected theme (RANDOM shows a different theme
## each time you land on it). Seated characters are re-added by _sync_stage.
func _build_stage() -> void:
	if _stage != null:
		remove_child(_stage)
		_stage.queue_free()
	var key: String = Looks.options()[theme_i]
	_look_now = Looks.get_look(key)
	_stage = Stage.new()
	add_child(_stage)
	move_child(_stage, 0)
	_stage.build(Vector3(0, 2.7, 11.6), Vector3(0, 1.5, 0), 36.0, _look_now)
	for i in MAX_PLAYERS:
		_stage.add_podium(_slot_pos(i), 0.5, UiKit.PLAYER_COLORS[i])
		_slot_sig[i] = ""
		_slot_char[i] = null


## Lobby overlay colours of the theme on show.
func _ui() -> Dictionary:
	return _look_now.get("ui", Looks.LOOKS.classic.ui)


## Dev / command line: select a theme by key.
func pick_theme(key: String) -> void:
	var i := Looks.options().find(key)
	if i >= 0:
		theme_i = i
		Settings.lobby["theme"] = i


func deactivate() -> void:
	visible = false
	_remember()
	if _stage != null:
		_stage.queue_free()
		_stage = null


func _slot_pos(i: int) -> Vector3:
	var off := i - (MAX_PLAYERS - 1) * 0.5
	return Vector3(off * 2.3, 0.0, absf(off) * -0.28)


func demo_fill(humans: int, cpu: int) -> void:
	for i in humans:
		_join(100 + i if i > 0 else KEYBOARD, true)
		seats[i].hat = 1 + i * 2
		seats[i].face = i
	bots = cpu
	_clamp_bots()


func _on_joy_changed(device: int, connected: bool) -> void:
	if not connected:
		seats = seats.filter(func(s): return s.device != device)
		_clamp_bots()


func _clamp_bots() -> void:
	bots = clampi(bots, 0, MAX_PLAYERS - seats.size())


func _seat_of(device: int) -> int:
	for i in seats.size():
		if seats[i].device == device:
			return i
	return -1


func _edge(key: String, now: bool) -> bool:
	var was: bool = _prev.get(key, true)
	_prev[key] = now
	return now and not was


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	message_t = maxf(0.0, message_t - delta)
	for i in MAX_PLAYERS:
		_slot_bump[i] = minf(1.0, _slot_bump[i] + delta * 3.0)
	queue_redraw()
	if _options.visible:
		_sync_stage()
		return

	var want_start := false
	var want_options := _edge("k_opt", Input.is_physical_key_pressed(KEY_O) or Input.is_physical_key_pressed(KEY_TAB))
	var bot_step := false
	var target_step := false
	var map_step := false
	var time_step := false
	var mode_step := false

	# Keyboard seat.
	var k_seat := _seat_of(KEYBOARD)
	if _edge("k_join", Input.is_physical_key_pressed(KEY_SPACE)) and k_seat < 0:
		_join(KEYBOARD)
	if _edge("k_leave", Input.is_physical_key_pressed(KEY_BACKSPACE)) and k_seat >= 0:
		_leave(KEYBOARD)
	var k_l := _edge("k_l", Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var k_r := _edge("k_r", Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
	var k_u := _edge("k_u", Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var k_d := _edge("k_d", Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
	if k_seat >= 0:
		_edit(k_seat, (1 if k_r else 0) - (1 if k_l else 0), (1 if k_d else 0) - (1 if k_u else 0))
	if _edge("k_start", Input.is_physical_key_pressed(KEY_ENTER)):
		want_start = true
	if _edge("k_bots", Input.is_physical_key_pressed(KEY_B)): bot_step = true
	if _edge("k_target", Input.is_physical_key_pressed(KEY_K)): target_step = true
	if _edge("k_map", Input.is_physical_key_pressed(KEY_M)): map_step = true
	if _edge("k_time", Input.is_physical_key_pressed(KEY_T)): time_step = true
	if _edge("k_mode", Input.is_physical_key_pressed(KEY_G)): mode_step = true
	if _edge("k_quit", Input.is_physical_key_pressed(KEY_ESCAPE)) and _armed:
		_remember()
		get_tree().quit()
	if _edge("k_full", Input.is_physical_key_pressed(KEY_F11)):
		Settings.step("fullscreen", 1)

	# Gamepad seats.
	for d in Input.get_connected_joypads():
		var k := "j%d_" % d
		var seat := _seat_of(d)
		if _edge(k + "a", Input.is_joy_button_pressed(d, JOY_BUTTON_A)) and seat < 0:
			_join(d)
		if _edge(k + "b", Input.is_joy_button_pressed(d, JOY_BUTTON_B)) and seat >= 0:
			_leave(d)
		var sx := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
		var sy := Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)
		var left := _edge(k + "l", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT) or sx < -0.6)
		var right := _edge(k + "r", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT) or sx > 0.6)
		var up := _edge(k + "u", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP) or sy < -0.6)
		var down := _edge(k + "d", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN) or sy > 0.6)
		if seat >= 0:
			_edit(seat, (1 if right else 0) - (1 if left else 0), (1 if down else 0) - (1 if up else 0))
		if _edge(k + "start", Input.is_joy_button_pressed(d, JOY_BUTTON_START)):
			want_start = true
		if _edge(k + "y", Input.is_joy_button_pressed(d, JOY_BUTTON_Y)): bot_step = true
		if _edge(k + "x", Input.is_joy_button_pressed(d, JOY_BUTTON_X)): target_step = true
		if _edge(k + "rb", Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER)): map_step = true
		if _edge(k + "lb", Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER)): time_step = true
		if _edge(k + "rt", Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.6): mode_step = true
		if _edge(k + "back", Input.is_joy_button_pressed(d, JOY_BUTTON_BACK)): want_options = true
	var was_armed := _armed
	_armed = true
	if want_options and was_armed:
		_options.open()
		return

	var mode: String = MODES[mode_i]
	if mode_step:
		mode_i = (mode_i + 1) % MODES.size()
		Sfx.play("tick", -6.0, 0.9)
	if bot_step:
		if mode == "frontline":
			versus = not versus
		else:
			var room := MAX_PLAYERS - seats.size()
			bots = 0 if bots >= room else bots + 1
		Sfx.play("tick", -8.0)
	if target_step and mode != "zombies" and mode != "gungame":
		target_i = (target_i + 1) % KILL_TARGETS.size()
		Sfx.play("tick", -8.0)
	if time_step:
		theme_i = (theme_i + 1) % Looks.options().size()
		Settings.lobby["theme"] = theme_i
		Sfx.play("tick", -6.0, 1.1)
		_build_stage()
	if map_step:
		if mode == "frontline":
			_say("Frontline is fought on its own huge map")
		elif mode == "zombies":
			_say("Zombies is played in the Quarantine zone")
		elif mode == "medieval":
			_say("Medieval is fought in the Castle")
		else:
			map_i = (map_i + 1) % Map.ARENAS.size()
			Sfx.play("tick", -6.0, 1.2)
	if want_start:
		if seats.is_empty():
			_say("Someone has to join first!")
		elif mode in ["rounds", "gungame", "medieval"] and seats.size() + bots < 2:
			_say("Need 2 or more fighters - add a player or a bot")
		else:
			_start()
	_sync_stage()


func _say(text: String) -> void:
	message = text
	message_t = 3.0
	Sfx.play("hurt", -12.0)


func _used_colors(except := -1) -> Dictionary:
	var used := {}
	for i in seats.size():
		if i != except:
			used[seats[i].color] = true
	return used


func _join(device: int, quiet := false) -> void:
	if seats.size() >= MAX_PLAYERS:
		return
	var i := seats.size()
	var saved: Array = Settings.lobby.get("seat%d" % i, [])
	var seat := {"device": device, "kind": i % UiKit.KIND_NAMES.size(), "color": i, "hat": 0, "face": 0, "back": 0, "sens": 4, "row": 0}
	if saved.size() >= 6:
		seat.sens = clampi(int(saved[5]), 0, SENS_STEPS - 1)
	if saved.size() >= 5:
		seat.back = posmod(int(saved[4]), UiKit.BACK_NAMES.size())
	if saved.size() >= 4:
		seat.kind = posmod(int(saved[0]), UiKit.KIND_NAMES.size())
		seat.color = posmod(int(saved[1]), UiKit.PLAYER_COLORS.size())
		seat.hat = posmod(int(saved[2]), UiKit.HAT_NAMES.size())
		seat.face = posmod(int(saved[3]), UiKit.FACE_NAMES.size())
	var used := _used_colors()
	while used.has(seat.color):
		seat.color = (seat.color + 1) % UiKit.PLAYER_COLORS.size()
	seats.append(seat)
	_clamp_bots()
	if not quiet:
		Sfx.play("join", -6.0)


func _leave(device: int) -> void:
	seats = seats.filter(func(s): return s.device != device)
	Sfx.play("tick", -8.0, 0.7)


## Change this seat's selected category (dv) or its value (dh).
func _edit(seat_i: int, dh: int, dv: int) -> void:
	var seat: Dictionary = seats[seat_i]
	if dv != 0:
		seat.row = posmod(seat.row + dv, CATEGORIES.size())
		Sfx.play("tick", -10.0, 0.9)
	if dh == 0:
		return
	var key: String = KEYS[seat.row]
	var count: int = [UiKit.KIND_NAMES.size(), UiKit.PLAYER_COLORS.size(), UiKit.HAT_NAMES.size(), UiKit.BACK_NAMES.size(), SENS_STEPS][seat.row]
	if key == "sens":
		seat.sens = clampi(seat.sens + dh, 0, SENS_STEPS - 1)
		Sfx.play("tick", -8.0, 0.8 + seat.sens * 0.06)
		return
	seat[key] = posmod(seat[key] + dh, count)
	if key == "color":
		# Two players never share a colour.
		var used := _used_colors(seat_i)
		while used.has(seat.color):
			seat.color = posmod(seat.color + dh, count)
	Sfx.play("tick", -8.0)


## What a slot shows: {} when empty, otherwise the character's look.
func _look(slot: int) -> Dictionary:
	if slot < seats.size():
		var s: Dictionary = seats[slot]
		return {"kind": s.kind, "color": UiKit.PLAYER_COLORS[s.color], "hat": s.hat, "face": s.face, "back": s.back}
	if slot < seats.size() + bots:
		# CPUs take whatever colours the humans left.
		var used := _used_colors()
		var c := 0
		var n := slot - seats.size()
		for ci in UiKit.PLAYER_COLORS.size():
			if not used.has(ci):
				if n == 0:
					c = ci
					break
				n -= 1
		var b: Dictionary = _bot_looks[slot]
		return {"kind": b.kind, "color": UiKit.PLAYER_COLORS[c], "hat": b.hat, "face": b.face, "back": b.back}
	return {}


## Make the 3D podiums match seats/bots.
func _sync_stage() -> void:
	if _stage == null:
		return
	for i in MAX_PLAYERS:
		var look := _look(i)
		var sig := str(look)
		if sig == _slot_sig[i]:
			continue
		var was_empty: bool = _slot_sig[i] == "" or _slot_sig[i] == "{}"
		_slot_sig[i] = sig
		if _slot_char[i] != null:
			_stage.remove_character(_slot_char[i])
			_slot_char[i] = null
		if not look.is_empty():
			var pos := _slot_pos(i) + Vector3(0, 0.55, 0)
			_slot_char[i] = _stage.add_character(look, pos)
			if was_empty:
				_slot_bump[i] = 0.0
				Fx.sparks(_stage, pos + Vector3(0, 1.0, 0), look.color, 24, 6.0, Vector3.UP, 180.0, 0.6)
			else:
				# Just a tweak: no pop-in, so cycling options feels instant.
				_slot_char[i]._pop = 1.0


func _remember() -> void:
	for i in seats.size():
		Settings.lobby["seat%d" % i] = [seats[i].kind, seats[i].color, seats[i].hat, seats[i].face, seats[i].back, seats[i].sens]
	Settings.lobby["bots"] = bots
	Settings.lobby["target"] = target_i
	Settings.lobby["map"] = map_i
	Settings.lobby["theme"] = theme_i
	Settings.lobby["mode"] = mode_i
	Settings.lobby["versus"] = versus
	Settings.save()


func _start() -> void:
	var parts: Array = []
	var mode: String = MODES[mode_i]
	var cpu := 0 if mode == "frontline" else bots
	for i in seats.size() + cpu:
		var look := _look(i)
		var human := i < seats.size()
		parts.append({"device": seats[i].device if human else -2, "bot": not human, "view": human,
			"kind": look.kind, "color": look.color, "hat": look.hat, "face": look.face, "back": look.back,
			"sens": (seats[i].sens + 1) if human else 5})
	var target: int = TICKETS[target_i] if mode == "frontline" else KILL_TARGETS[target_i]
	start.emit({"participants": parts, "kill_target": target, "map": Map.ARENAS[map_i], "theme": _look_now.get("key", "classic"), "mode": mode,
		"teams": "versus" if versus else "coop"})


# --------------------------------------------------------------------------
# Drawing
# --------------------------------------------------------------------------

func _draw() -> void:
	var w := size.x
	var h := size.y
	var s := h / 1080.0
	var ui: Dictionary = _look_now.get("ui", Looks.LOOKS.classic.ui)
	var panel: Color = ui.panel
	var value: Color = ui.value
	draw_texture_rect(UiKit.vignette(), Rect2(0, 0, w, h), false, ui.vignette)

	# Bouncing logo.
	var title := "SLOP GAME"
	var px := 150.0 * s
	var total := 0.0
	var widths: Array = []
	for ch in title:
		var cw := UiKit.text_width(ch, px) + 4 * s
		widths.append(cw)
		total += cw
	var x := (w - total) * 0.5
	for i in title.length():
		var bounce := sin(_t * 2.6 - i * 0.55)
		var pos := Vector2(x + widths[i] * 0.5, 160 * s - maxf(0.0, bounce) * 14 * s)
		draw_set_transform(pos, bounce * 0.04, Vector2.ONE)
		var la: Color = ui.logo_a
		var lb: Color = ui.logo_b
		var col := la.lerp(la.darkened(0.15).lerp(Color(1, 0.3, 0.2), 0.25), 0.5 + 0.5 * sin(i * 0.9)) if i < 4 else lb.lerp(lb.lerp(Color.WHITE, 0.4), 0.5 + 0.5 * sin(i * 0.9))
		UiKit.text(self, Vector2(-widths[i] * 0.5, 0), title[i], px, col, HORIZONTAL_ALIGNMENT_CENTER, widths[i], 700, 0.12)
		x += widths[i]
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tag: String = TAGLINES[mode_i]
	var tw := UiKit.text_width(tag, 24 * s) + 60 * s
	UiKit.card(self, Rect2((w - tw) * 0.5, 190 * s, tw, 44 * s), panel, 22 * s, s)
	UiKit.text(self, Vector2(0, 221 * s), tag, 24 * s, UiKit.CREAM, HORIZONTAL_ALIGNMENT_CENTER, w, 600, 0.0)
	# A screen running below 50 Hz (a 4K TV left in a 30 Hz mode) can never
	# show a smooth game, whatever we render: say so.
	var hz := DisplayServer.screen_get_refresh_rate()
	if hz > 1.0 and hz < 50.0:
		var warn := "YOUR SCREEN IS SET TO %d Hz - THE GAME CAN ONLY SHOW %d FPS.  WINDOWS: SETTINGS > DISPLAY > ADVANCED DISPLAY > REFRESH RATE 60 Hz" % [int(round(hz)), int(round(hz))]
		var ww := UiKit.text_width(warn, 19 * s) + 50 * s
		UiKit.card(self, Rect2((w - ww) * 0.5, 242 * s, ww, 36 * s), Color(0.75, 0.16, 0.14), 18 * s, s)
		UiKit.text(self, Vector2(0, 267 * s), warn, 19 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w, 700, 0.0)

	# Seat plates, positioned under the 3D podiums.
	if _stage != null and _stage.camera != null and not _options.visible:
		for i in MAX_PLAYERS:
			var base: Vector2 = _stage.camera.unproject_position(_slot_pos(i) + Vector3(0, 0.0, 0.9))
			var head: Vector2 = _stage.camera.unproject_position(_slot_pos(i) + Vector3(0, 3.2, 0))
			_draw_seat(i, base, head, s)

	# Shared settings + start.
	var by := h - 162 * s
	var pad: bool = not Input.get_connected_joypads().is_empty()
	var mode: String = MODES[mode_i]
	var map_info: Dictionary = Map.MAPS[{"frontline": Map.FRONTLINE, "zombies": Map.ZOMBIE, "medieval": Map.CASTLE}.get(mode, Map.ARENAS[map_i])]
	var bot_chip := ["Y" if pad else "B", "BOTS", str(bots), 200.0]
	var goal_chip := ["X" if pad else "K", "FIRST TO", "%d" % KILL_TARGETS[target_i], 230.0]
	if mode == "frontline":
		bot_chip = ["Y" if pad else "B", "TEAMS", "VERSUS" if versus else "CO-OP", 270.0]
		goal_chip = ["X" if pad else "K", "TICKETS", "%d" % TICKETS[target_i], 250.0]
	elif mode == "zombies":
		bot_chip = ["Y" if pad else "B", "ALLIES", str(bots), 210.0]
		goal_chip = ["X" if pad else "K", "WAVES", "ENDLESS", 250.0]
	elif mode == "gungame":
		goal_chip = ["X" if pad else "K", "LADDER", "ALL WEAPONS", 300.0]
	var chips := [
		["RT" if pad else "G", "MODE", MODE_LABELS[mode_i], 300.0],
		bot_chip,
		goal_chip,
		["RB" if pad else "M", "MAP", "%s" % map_info.name, 340.0],
		["LB" if pad else "T", "THEME", Looks.label(Looks.options()[theme_i]), 390.0],
		["BACK" if pad else "O", "OPTIONS", "", 210.0],
	]
	var total_w := -16.0 * s
	for chip in chips:
		total_w += chip[3] * s + 16 * s
	var cx := (w - total_w) * 0.5
	for chip in chips:
		var r := Rect2(cx, by, chip[3] * s, 58 * s)
		UiKit.card(self, r, panel, 29 * s, s)
		var ox := r.position.x + 16 * s
		ox += UiKit.prompt(self, Vector2(ox, by + 41 * s), chip[0], 26 * s, not pad) + 12 * s
		UiKit.text(self, Vector2(ox, by + 40 * s), chip[1], 24 * s, UiKit.CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1, 600, 0.0)
		UiKit.text(self, Vector2(r.position.x, by + 41 * s), chip[2], 28 * s, value, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 22 * s)
		cx += chip[3] * s + 16 * s

	var ready := not seats.is_empty() and (seats.size() + bots >= 2 or mode != "rounds")
	var sy := h - 58 * s
	if ready:
		var pulse := 1.0 + sin(_t * 5.0) * 0.04
		draw_set_transform(Vector2(w * 0.5, sy - 14 * s), 0.0, Vector2(pulse, pulse))
		var label := "PRESS  START  TO FIGHT!" if pad else "PRESS  ENTER  TO FIGHT!"
		UiKit.text(self, Vector2(-w * 0.5, 16 * s), label, 46 * s, value, HORIZONTAL_ALIGNMENT_CENTER, w, 700, 0.16)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		UiKit.text(self, Vector2(0, sy), "WAITING FOR PLAYERS...", 36 * s, Color(1, 1, 1, 0.7 + 0.3 * sin(_t * 3.0)), HORIZONTAL_ALIGNMENT_CENTER, w, 700, 0.16)
	if message_t > 0.0:
		var mw := UiKit.text_width(message, 26 * s) + 50 * s
		var bump := UiKit.back_out(clampf((3.0 - message_t) * 5.0, 0.0, 1.0))
		draw_set_transform(Vector2(w * 0.5, by - 44 * s), 0.0, Vector2(bump, bump))
		UiKit.card(self, Rect2(-mw * 0.5, -24 * s, mw, 48 * s), Color(1.0, 0.3, 0.32), 24 * s, s)
		UiKit.text(self, Vector2(-mw * 0.5, 9 * s), message, 26 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, mw, 700, 0.12)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	UiKit.text(self, Vector2(0, h - 12 * s), "GAMEPAD   RT fire  -  LT aim  -  A jump  -  B crouch  -  L3 sprint  -  R3 melee  -  RB dash  -  LB block  -  X reload  -  Y use  -  D-pad taunt          KEYBOARD   LMB  -  RMB  -  F melee  -  Space  -  Shift  -  C  -  Q  -  R  -  E          F11 fullscreen  -  Esc quit",
		16 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, w, 500, 0.12)


func _draw_seat(i: int, base: Vector2, head: Vector2, s: float) -> void:
	var pw := 276.0 * s
	var bump := UiKit.back_out(_slot_bump[i])
	var is_player := i < seats.size()
	var is_bot := not is_player and i < seats.size() + bots
	var look := _look(i)
	var col: Color = look.color if not look.is_empty() else Color(0.4, 0.45, 0.6)
	draw_set_transform(base, 0.0, Vector2(0.85 + 0.15 * bump, 0.85 + 0.15 * bump))
	var r := Rect2(-pw * 0.5, 0, pw, 118 * s)
	if is_player:
		var seat: Dictionary = seats[i]
		UiKit.panel(self, r, _ui().panel, 22 * s, col, 3 * s, 5 * s)
		var dev := "KEYBOARD" if seat.device == KEYBOARD else "GAMEPAD %d" % (seat.device + 1)
		UiKit.text(self, Vector2(r.position.x, 28 * s), dev, 18 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, pw, 600, 0.0)
		# Category tabs: the selected one is lit.
		var tab_w := (pw - 28 * s) / CATEGORIES.size()
		for c in CATEGORIES.size():
			var tr := Rect2(r.position.x + 14 * s + c * tab_w, 38 * s, tab_w - 4 * s, 24 * s)
			var on: bool = c == seat.row
			UiKit.panel(self, tr, col if on else Color(1, 1, 1, 0.08), 12 * s)
			draw_string(UiKit.font(700), tr.position + Vector2(0, 17 * s), CATEGORIES[c], HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, int(11 * s), UiKit.INK if on else Color(1, 1, 1, 0.6))
		var value: String = [UiKit.KIND_NAMES[seat.kind], UiKit.COLOR_NAMES[seat.color], UiKit.HAT_NAMES[seat.hat], UiKit.BACK_NAMES[seat.back], "SPEED %d" % (seat.sens + 1)][seat.row]
		var wob := sin(_t * 6.0) * 3 * s
		UiKit.text(self, Vector2(r.position.x + 20 * s - wob, 102 * s), "<", 30 * s, _ui().value)
		UiKit.text(self, Vector2(r.position.x, 102 * s), ">", 30 * s, _ui().value, HORIZONTAL_ALIGNMENT_RIGHT, pw - 20 * s - wob)
		UiKit.text(self, Vector2(r.position.x, 102 * s), value, 30 * s if value.length() < 10 else 24 * s, UiKit.CREAM, HORIZONTAL_ALIGNMENT_CENTER, pw)
	elif is_bot:
		UiKit.panel(self, r, _ui().panel, 22 * s, col.darkened(0.3), 3 * s, 5 * s)
		UiKit.text(self, Vector2(r.position.x, 56 * s), "CPU", 34 * s, col.lerp(Color.WHITE, 0.3), HORIZONTAL_ALIGNMENT_CENTER, pw)
		UiKit.text(self, Vector2(r.position.x, 92 * s), UiKit.KIND_NAMES[look.kind], 22 * s, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, pw, 600, 0.0)
	else:
		var a := 0.6 + 0.3 * sin(_t * 3.0 + i)
		UiKit.panel(self, r, Color(0.05, 0.06, 0.1, 0.6), 22 * s, Color(1, 1, 1, 0.25), 3 * s)
		var jw := UiKit.text_width("JOIN", 28 * s) + 48 * s
		var jx := -jw * 0.5
		jx += UiKit.prompt(self, Vector2(jx, 58 * s), "A", 26 * s) + 12 * s
		UiKit.text(self, Vector2(jx, 58 * s), "JOIN", 28 * s, Color(1, 1, 1, a))
		UiKit.text(self, Vector2(r.position.x, 92 * s), "or SPACE on keyboard", 17 * s, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_CENTER, pw, 500, 0.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if is_player or is_bot:
		var label := "P%d" % (i + 1) if is_player else "CPU"
		var lw := UiKit.text_width(label, 30 * s) + 36 * s
		draw_set_transform(head, sin(_t * 2.0 + i) * 0.04, Vector2(bump, bump))
		UiKit.card(self, Rect2(-lw * 0.5, -22 * s, lw, 44 * s), col, 22 * s, s)
		UiKit.text(self, Vector2(-lw * 0.5, 10 * s), label, 30 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, lw, 700, 0.14)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
