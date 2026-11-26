extends Control
## Join screen: a 3D stage (stage.gd) with six podiums in two rows of three
## and a 2D overlay (each seat's plate sits beside its character).
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
## tickets), RB / M next map (Frontline: FRONTLINE or HIGHTOWN), LB / T visual theme
## (looks.gd: the stage behind the lobby and its colours change with it),
## Back / O options, Start / Enter to begin.
##
## The mouse works too: click a chip to step it (right-click steps back), an
## empty plate to join as the keyboard player, a plate's category line or
## its < > halves to customise, the X to leave, FIGHT to start.
##
## Controllers: every pad Godot sees is listed along the bottom (name, and
## "unmapped" when SDL has no layout for it). An unmapped pad can join with
## any button, and the list is printed to the log on start and on connect,
## to help when a pad seems dead (macOS Bluetooth pads).
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
const STAGE_COL := 4.6          # metres between podium columns (front row)
const BACK_TIER := 3.4          # podium height of the back row
const KEYBOARD := -1
const KILL_TARGETS := [5, 10, 15, 20, 30]
const CATEGORIES := ["ANIMAL", "COLOR", "HAT", "BACK"]
const KEYS := ["kind", "color", "hat", "back"]
const SENS_STEPS := 10          # LOOK: this player's own look speed, 1-10
const MODES := ["rounds", "zombies", "frontline", "gungame", "medieval", "racing"]
const MODE_LABELS := ["ROUNDS", "ZOMBIES", "FRONTLINE", "GUN GAME", "MEDIEVAL", "RACING"]
const RACE_LAPS := [2, 3, 5, 8, 12]   # ~15 s a lap at full speed
const TICKETS := [50, 100, 150, 200, 300]

var seats: Array = []        # [{device, kind, color, hat, face, row}] in join order
var bots := 0
var target_i := 2
var map_i := 0
var theme_i := 0             # index into Looks.options()
var mode_i := 0
var versus := true           # Frontline: humans split between the teams
var front_i := 0             # Frontline: index into Map.FRONT_MAPS
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
var _hits: Array = []        # [Rect2, id] clickable areas from the last _draw (mouse)
var _hover := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.joy_connection_changed.connect(_on_joy_changed)
	_log_pads("start")
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
	front_i = clampi(int(Settings.lobby.get("front_map", 0)), 0, Map.FRONT_MAPS.size() - 1)
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
	UiKit.use_theme(_look_now)
	_stage = Stage.new()
	add_child(_stage)
	move_child(_stage, 0)
	_stage.build(Vector3(0, 4.9, 18.5), Vector3(0, 3.0, 0), 34.0, _look_now)
	# The back row stands on a wooden deck, the front row on tree stumps.
	_stage.add_deck(_slot_pos(0).x - 2.0, _slot_pos(2).x + 3.2, -3.8, 0.4, BACK_TIER)
	for i in MAX_PLAYERS:
		_stage.add_podium(_slot_pos(i), _slot_h(i), UiKit.PLAYER_COLORS[i], "rug" if i < 3 else "stump")
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


## Seats are two rows of three: P1-P3 on a raised back tier, P4-P6 in
## front. Each character stands left of centre in its cell so its plate
## fits beside it (_draw_seat). Returns the podium's base on the floor.
func _slot_pos(i: int) -> Vector3:
	var c := (i % 3) - 1
	if i < 3:
		return Vector3(c * STAGE_COL * 1.05 - 1.2, 0.0, -1.6)
	return Vector3(c * STAGE_COL - 1.15, 0.0, 2.6)


## Podium height: the back tier stands taller so it shows over the front.
func _slot_h(i: int) -> float:
	return BACK_TIER if i < 3 else 0.4


func demo_fill(humans: int, cpu: int) -> void:
	for i in humans:
		_join(100 + i if i > 0 else KEYBOARD, true)
		seats[i].hat = 1 + i * 2
		seats[i].face = i
	bots = cpu
	_clamp_bots()


func _on_joy_changed(device: int, connected: bool) -> void:
	UiKit.reset_pads()
	_log_pads("%s %d" % ["connected" if connected else "disconnected", device])
	if connected and visible:
		_say("Controller connected: %s" % Input.get_joy_name(device))
	if not connected:
		seats = seats.filter(func(s): return s.device != device)
		_clamp_bots()


## Print every controller Godot can see (goes to the log file too).
func _log_pads(why: String) -> void:
	var pads := Input.get_connected_joypads()
	print("[pads] %s: %d connected" % [why, pads.size()])
	for d in pads:
		print("[pads]   %d: %s  known=%s  guid=%s" % [d, Input.get_joy_name(d), Input.is_joy_known(d), Input.get_joy_guid(d)])


## Any button at all on this pad (for pads SDL has no layout for).
func _any_button(d: int) -> bool:
	for b in 21:
		if Input.is_joy_button_pressed(d, b):
			return true
	return false


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
		Settings.toggle_fullscreen()

	# Gamepad seats.
	for d in Input.get_connected_joypads():
		var k := "j%d_" % d
		var seat := _seat_of(d)
		var join_btn := Input.is_joy_button_pressed(d, JOY_BUTTON_A) if Input.is_joy_known(d) else _any_button(d)
		if _edge(k + "a", join_btn) and seat < 0:
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

	if mode_step:
		_shared("mode", 1)
	if bot_step:
		_shared("bots", 1)
	if target_step:
		_shared("target", 1)
	if time_step:
		_shared("theme", 1)
	if map_step:
		_shared("map", 1)
	if want_start:
		_try_start()
	_sync_stage()


## Step one of the shared settings (the chips along the bottom) by dir.
func _shared(what: String, dir: int) -> void:
	var mode: String = MODES[mode_i]
	match what:
		"mode":
			mode_i = posmod(mode_i + dir, MODES.size())
			Sfx.play("tick", -6.0, 0.9)
		"bots":
			if mode == "frontline":
				versus = not versus
			else:
				var room := MAX_PLAYERS - seats.size()
				bots = posmod(bots + dir, room + 1)
			Sfx.play("tick", -8.0)
		"target":
			if mode != "zombies" and mode != "gungame":
				target_i = posmod(target_i + dir, KILL_TARGETS.size())
				Sfx.play("tick", -8.0)
		"theme":
			theme_i = posmod(theme_i + dir, Looks.options().size())
			Settings.lobby["theme"] = theme_i
			Sfx.play("tick", -6.0, 1.1)
			_build_stage()
		"map":
			if mode == "frontline":
				front_i = posmod(front_i + dir, Map.FRONT_MAPS.size())
				Sfx.play("tick", -6.0, 1.2)
			elif mode == "zombies":
				_say("Zombies is played in the Quarantine zone")
			elif mode == "medieval":
				_say("Medieval is fought in the Castle")
			elif mode == "racing":
				_say("Racing is on the Raceway")
			else:
				map_i = posmod(map_i + dir, Map.ARENAS.size())
				Sfx.play("tick", -6.0, 1.2)
		"options":
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			_options.open()


func _try_start() -> void:
	var mode: String = MODES[mode_i]
	if seats.is_empty():
		_say("Someone has to join first!")
	elif mode in ["rounds", "gungame", "medieval"] and seats.size() + bots < 2:
		_say("Need 2 or more fighters - add a player or a bot")
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		_start()


func _input(event: InputEvent) -> void:
	if not visible or _options.visible or not (event is InputEventMouse):
		return
	var id := ""
	for i in range(_hits.size() - 1, -1, -1):
		if (_hits[i][0] as Rect2).has_point(event.position):
			id = _hits[i][1]
			break
	_hover = id
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if id != "" else Input.CURSOR_ARROW)
	if not (event is InputEventMouseButton and event.pressed) or id == "":
		return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var dir := 1 if event.button_index == MOUSE_BUTTON_LEFT else -1
	var parts := id.split(":")
	match parts[0]:
		"chip":
			_shared(parts[1], dir)
		"start":
			_try_start()
		"join":
			if _seat_of(KEYBOARD) < 0:
				_join(KEYBOARD)
			else:
				_say("Gamepad players press A on their own pad to join")
		"leave":
			var si := int(parts[1])
			if si < seats.size():
				_leave(seats[si].device)
		"cat":
			_edit(int(parts[1]), 0, dir)
		"val":
			_edit(int(parts[1]), int(parts[2]), 0)
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
	var seat := {"device": device, "kind": i % UiKit.KIND_NAMES.size(), "color": i, "hat": 0, "face": 0, "back": 0, "sens": 4, "inv": 0, "row": 0}
	if saved.size() >= 7:
		seat.inv = 1 if int(saved[6]) != 0 else 0
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
	var count: int = [UiKit.KIND_NAMES.size(), UiKit.PLAYER_COLORS.size(), UiKit.HAT_NAMES.size(), UiKit.BACK_NAMES.size()][seat.row]
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
			var pos := _slot_pos(i) + Vector3(0, _slot_h(i) + 0.05, 0)
			_slot_char[i] = _stage.add_character(look, pos)
			if was_empty:
				_slot_bump[i] = 0.0
				Fx.sparks(_stage, pos + Vector3(0, 1.0, 0), look.color, 24, 6.0, Vector3.UP, 180.0, 0.6)
			else:
				# Just a tweak: no pop-in, so cycling options feels instant.
				_slot_char[i]._pop = 1.0


func _remember() -> void:
	for i in seats.size():
		Settings.lobby["seat%d" % i] = [seats[i].kind, seats[i].color, seats[i].hat, seats[i].face, seats[i].back, seats[i].sens, seats[i].inv]
	Settings.lobby["bots"] = bots
	Settings.lobby["target"] = target_i
	Settings.lobby["map"] = map_i
	Settings.lobby["theme"] = theme_i
	Settings.lobby["mode"] = mode_i
	Settings.lobby["versus"] = versus
	Settings.lobby["front_map"] = front_i
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
			"pnum": i + 1})
	var target: int = TICKETS[target_i] if mode == "frontline" else (RACE_LAPS[target_i] if mode == "racing" else KILL_TARGETS[target_i])
	start.emit({"participants": parts, "kill_target": target, "map": Map.FRONT_MAPS[front_i] if mode == "frontline" else Map.ARENAS[map_i], "theme": _look_now.get("key", "classic"), "mode": mode,
		"teams": "versus" if versus else "coop"})


# --------------------------------------------------------------------------
# Drawing
# --------------------------------------------------------------------------

func _draw() -> void:
	var w := size.x
	var h := size.y
	var s := h / 1080.0
	var ui: Dictionary = _look_now.get("ui", Looks.LOOKS.classic.ui)
	_hits.clear()
	var panel: Color = ui.panel
	var value: Color = ui.value
	draw_texture_rect(UiKit.vignette(), Rect2(0, 0, w, h), false, ui.vignette)

	# Bouncing logo.
	var title := "SLOP PARTY"
	var px := 120.0 * s
	var total := 0.0
	var widths: Array = []
	for ch in title:
		var cw := UiKit.text_width(ch, px) + 4 * s
		widths.append(cw)
		total += cw
	var x := (w - total) * 0.5
	for i in title.length():
		var bounce := sin(_t * 2.6 - i * 0.55)
		var pos := Vector2(x + widths[i] * 0.5, 124 * s - maxf(0.0, bounce) * 10 * s)
		draw_set_transform(pos, bounce * 0.04, Vector2.ONE)
		var la: Color = ui.logo_a
		var lb: Color = ui.logo_b
		var col := la.lerp(la.darkened(0.15).lerp(Color(1, 0.3, 0.2), 0.25), 0.5 + 0.5 * sin(i * 0.9)) if i < 4 else lb.lerp(lb.lerp(Color.WHITE, 0.4), 0.5 + 0.5 * sin(i * 0.9))
		UiKit.text(self, Vector2(-widths[i] * 0.5, 0), title[i], px, col, HORIZONTAL_ALIGNMENT_CENTER, widths[i], 700, 0.12)
		x += widths[i]
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# A screen running below 50 Hz (a 4K TV left in a 30 Hz mode) can never
	# show a smooth game, whatever we render: say so.
	var hz := DisplayServer.screen_get_refresh_rate()
	if hz > 1.0 and hz < 50.0:
		var fix := "WINDOWS: SETTINGS > DISPLAY > ADVANCED DISPLAY > REFRESH RATE 60 Hz"
		if Settings.is_steam_deck():
			fix = "STEAM DECK: QUICK ACCESS (...) > PERFORMANCE > REFRESH RATE 60 Hz"
		elif OS.get_name() == "Linux":
			fix = "SET 60 Hz IN YOUR DESKTOP'S DISPLAY SETTINGS"
		elif OS.get_name() == "macOS":
			fix = "SYSTEM SETTINGS > DISPLAYS > REFRESH RATE 60 Hz"
		var warn := "YOUR SCREEN IS SET TO %d Hz - THE GAME CAN ONLY SHOW %d FPS.  %s" % [int(round(hz)), int(round(hz)), fix]
		var ww := UiKit.text_width(warn, 19 * s) + 50 * s
		UiKit.card(self, Rect2((w - ww) * 0.5, 242 * s, ww, 36 * s), Color(0.75, 0.16, 0.14), 18 * s, s)
		UiKit.text(self, Vector2(0, 267 * s), warn, 19 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w, 700, 0.0)

	# Seat plates, positioned under the 3D podiums.
	if _stage != null and _stage.camera != null and not _options.visible:
		for i in MAX_PLAYERS:
			var top := _slot_pos(i) + Vector3(0, _slot_h(i), 0)
			var base: Vector2 = _stage.camera.unproject_position(top + Vector3(0, 1.0, 0))
			var head: Vector2 = _stage.camera.unproject_position(top + Vector3(0, 2.75, 0))
			_draw_seat(i, base, head, s)

	# Shared settings + start.
	var by := h - 140 * s
	var pad: bool = not Input.get_connected_joypads().is_empty()
	var mode: String = MODES[mode_i]
	var map_info: Dictionary = Map.MAPS[{"frontline": Map.FRONT_MAPS[front_i], "zombies": Map.ZOMBIE, "medieval": Map.CASTLE, "racing": Map.RACEWAY}.get(mode, Map.ARENAS[map_i])]
	var bot_chip := ["Y" if pad else "B", "BOTS", str(bots)]
	var goal_chip := ["X" if pad else "K", "FIRST TO", "%d" % KILL_TARGETS[target_i]]
	if mode == "frontline":
		bot_chip = ["Y" if pad else "B", "TEAMS", "VERSUS" if versus else "CO-OP"]
		goal_chip = ["X" if pad else "K", "TICKETS", "%d" % TICKETS[target_i]]
	elif mode == "zombies":
		bot_chip = ["Y" if pad else "B", "ALLIES", str(bots)]
		goal_chip = ["X" if pad else "K", "WAVES", "ENDLESS"]
	elif mode == "gungame":
		goal_chip = ["X" if pad else "K", "LADDER", "ALL WEAPONS"]
	elif mode == "racing":
		bot_chip = ["Y" if pad else "B", "GRID", "6 CARS"]
		goal_chip = ["X" if pad else "K", "LAPS", "%d" % RACE_LAPS[target_i]]
	var chips := [
		["RT" if pad else "G", "MODE", MODE_LABELS[mode_i]],
		bot_chip,
		goal_chip,
		["RB" if pad else "M", "MAP", "%s" % map_info.name],
		["LB" if pad else "T", "THEME", Looks.label(Looks.options()[theme_i])],
		["BACK" if pad else "O", "OPTIONS", ""],
	]
	var chip_ids := ["mode", "bots", "target", "map", "theme", "options"]
	# Each chip is as wide as its own button, label and value plus fixed
	# gaps; if the row is wider than the screen, everything shrinks to fit.
	var k := 1.0
	for attempt in 2:
		var total_w := -14.0 * s * k
		for chip in chips:
			total_w += _chip_w(chip, s * k, pad) + 14.0 * s * k
		if attempt == 0 and total_w > w - 40 * s:
			k = (w - 40 * s) / total_w
			continue
		var cx := (w - total_w) * 0.5
		var sk := s * k
		for ci in chips.size():
			var chip: Array = chips[ci]
			var cw := _chip_w(chip, sk, pad)
			var r := Rect2(cx, by, cw, 58 * sk)
			var cid: String = "chip:" + chip_ids[ci]
			_hits.append([r, cid])
			UiKit.card(self, r, panel.lerp(Color.WHITE, 0.18) if _hover == cid else panel, 29 * sk, sk)
			var ox := r.position.x + 18 * sk
			ox += UiKit.prompt(self, Vector2(ox, by + 41 * sk), chip[0], 26 * sk, not pad) + 12 * sk
			UiKit.text(self, Vector2(ox, by + 40 * sk), chip[1], 24 * sk, UiKit.CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1, 600, 0.0)
			if chip[2] != "":
				UiKit.text(self, Vector2(r.position.x, by + 41 * sk), chip[2], 28 * sk, value, HORIZONTAL_ALIGNMENT_RIGHT, cw - 20 * sk)
			cx += cw + 14 * sk
		break

	var ready := not seats.is_empty() and (seats.size() + bots >= 2 or mode != "rounds")
	var sy := h - 36 * s
	if ready:
		# A quiet reminder, not a shout: small, gently breathing.
		var label := "PRESS START TO FIGHT" if pad else "PRESS ENTER TO FIGHT"
		# Also a button for the mouse: it lights up under the pointer.
		var lw := UiKit.text_width(label, 24 * s) + 48 * s
		var lr := Rect2((w - lw) * 0.5, sy - 22 * s, lw, 40 * s)
		_hits.append([lr, "start"])
		if _hover == "start":
			UiKit.card(self, lr, Color(value, 0.9), 20 * s, s)
		UiKit.text(self, Vector2(0, sy + 6 * s), label, 24 * s, UiKit.INK if _hover == "start" else Color(value.lerp(Color.WHITE, 0.3), 0.55 + 0.2 * sin(_t * 2.0)), HORIZONTAL_ALIGNMENT_CENTER, w, 700, 0.12)
	else:
		UiKit.text(self, Vector2(0, sy), "WAITING FOR PLAYERS...", 36 * s, Color(1, 1, 1, 0.7 + 0.3 * sin(_t * 3.0)), HORIZONTAL_ALIGNMENT_CENTER, w, 700, 0.16)
	# Every controller the game can see, bottom left (or a hint when none).
	var pads := Input.get_connected_joypads()
	var pad_line := "NO CONTROLLERS DETECTED - pair one, then restart the game if it does not show up here"
	if not pads.is_empty():
		var names: Array = []
		for d in pads:
			names.append("%d: %s%s" % [d + 1, Input.get_joy_name(d), "" if Input.is_joy_known(d) else " (unmapped: any button joins)"])
		pad_line = "CONTROLLERS  " + "   ".join(names)
	UiKit.text(self, Vector2(18 * s, h - 10 * s), pad_line, 15 * s, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_LEFT, -1, 600, 0.0)
	if message_t > 0.0:
		var mw := UiKit.text_width(message, 26 * s) + 50 * s
		var bump := UiKit.back_out(clampf((3.0 - message_t) * 5.0, 0.0, 1.0))
		draw_set_transform(Vector2(w * 0.5, by - 44 * s), 0.0, Vector2(bump, bump))
		UiKit.card(self, Rect2(-mw * 0.5, -24 * s, mw, 48 * s), Color(1.0, 0.3, 0.32), 24 * s, s)
		UiKit.text(self, Vector2(-mw * 0.5, 9 * s), message, 26 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, mw, 700, 0.12)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)



## Width of one option chip at scale s: padding, button, gap, label, gap,
## value, padding.
func _chip_w(chip: Array, s: float, pad: bool) -> float:
	var btn: String = chip[0]
	var bw := 26 * s * 1.25 if (pad and btn in ["A", "B", "X", "Y"]) else UiKit.text_width(btn, 26 * s * 0.8) + 26 * s * 0.8
	var w := 18 * s + bw + 12 * s + UiKit.text_width(chip[1], 24 * s, 600) + 20 * s
	if chip[2] != "":
		w += 22 * s + UiKit.text_width(chip[2], 28 * s)
	return w


## Text size px, shrunk so the string fits within max_w.
func _fit(txt: String, px: float, max_w: float) -> float:
	var tw := UiKit.text_width(txt, px)
	return px if tw <= max_w else px * max_w / tw


func _draw_seat(i: int, base: Vector2, head: Vector2, s: float) -> void:
	var pw := 250.0 * s
	var ph := 124.0 * s
	var bump := UiKit.back_out(_slot_bump[i])
	var is_player := i < seats.size()
	var is_bot := not is_player and i < seats.size() + bots
	var look := _look(i)
	var col: Color = look.color if not look.is_empty() else Color(0.4, 0.45, 0.6)
	# The plate sits to the right of the character, centred on its middle.
	var org := base + Vector2(78 * s, -ph * 0.5)
	var sc := 0.85 + 0.15 * bump
	draw_set_transform(org, 0.0, Vector2(sc, sc))
	var r := Rect2(0, 0, pw, ph)
	# Plate-local rect -> screen rect, for mouse hits.
	var to_screen := func(lr: Rect2) -> Rect2: return Rect2(org + lr.position * sc, lr.size * sc)
	if is_player:
		var seat: Dictionary = seats[i]
		UiKit.panel(self, r, _ui().panel, 22 * s, col, 3 * s, 5 * s)
		var dev := "KEYBOARD" if seat.device == KEYBOARD else "GAMEPAD %d" % (seat.device + 1)
		UiKit.text(self, Vector2(0, 26 * s), dev, 16 * s, Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_CENTER, pw, 600, 0.0)
		# Which category up / down is on: its name and a row of dots.
		UiKit.text(self, Vector2(0, 54 * s), CATEGORIES[seat.row], 20 * s, col.lerp(Color.WHITE, 0.35), HORIZONTAL_ALIGNMENT_CENTER, pw, 700, 0.12)
		var n := CATEGORIES.size()
		for c in n:
			var dp := Vector2(pw * 0.5 + (c - (n - 1) * 0.5) * 14 * s, 66 * s)
			draw_circle(dp, (4.0 if c == seat.row else 2.6) * s, col if c == seat.row else Color(1, 1, 1, 0.3))
		var val: String = [UiKit.KIND_NAMES[seat.kind], UiKit.COLOR_NAMES[seat.color], UiKit.HAT_NAMES[seat.hat], UiKit.BACK_NAMES[seat.back]][seat.row]
		var wob := sin(_t * 6.0) * 3 * s
		UiKit.text(self, Vector2(14 * s - wob, 108 * s), "<", 28 * s, _ui().value)
		UiKit.text(self, Vector2(0, 108 * s), ">", 28 * s, _ui().value, HORIZONTAL_ALIGNMENT_RIGHT, pw - 14 * s + wob)
		UiKit.text(self, Vector2(0, 107 * s), val, _fit(val, 28 * s, pw - 76 * s), UiKit.CREAM, HORIZONTAL_ALIGNMENT_CENTER, pw)
		# Mouse: category line, the two halves of the value line, a leave X.
		var zones := [[Rect2(0, 34 * s, pw, 40 * s), "cat:%d" % i], [Rect2(0, 76 * s, pw * 0.5, 44 * s), "val:%d:-1" % i],
			[Rect2(pw * 0.5, 76 * s, pw * 0.5, 44 * s), "val:%d:1" % i]]
		for z in zones:
			_hits.append([to_screen.call(z[0]), z[1]])
			if _hover == z[1]:
				UiKit.panel(self, (z[0] as Rect2).grow(-5 * s), Color(1, 1, 1, 0.1), 14 * s)
		var xc := Vector2(pw - 18 * s, 18 * s)
		var xa := 0.8 if _hover == "leave:%d" % i else 0.35
		draw_line(xc + Vector2(-6, -6) * s, xc + Vector2(6, 6) * s, Color(1, 1, 1, xa), 3 * s, true)
		draw_line(xc + Vector2(6, -6) * s, xc + Vector2(-6, 6) * s, Color(1, 1, 1, xa), 3 * s, true)
		_hits.append([to_screen.call(Rect2(xc - Vector2(16, 16) * s, Vector2(32, 32) * s)), "leave:%d" % i])
	elif is_bot:
		UiKit.panel(self, r, _ui().panel, 22 * s, col.darkened(0.3), 3 * s, 5 * s)
		UiKit.text(self, Vector2(0, 62 * s), "CPU", 34 * s, col.lerp(Color.WHITE, 0.3), HORIZONTAL_ALIGNMENT_CENTER, pw)
		UiKit.text(self, Vector2(0, 98 * s), UiKit.KIND_NAMES[look.kind], 22 * s, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, pw, 600, 0.0)
	else:
		var a := 0.6 + 0.3 * sin(_t * 3.0 + i)
		_hits.append([to_screen.call(r), "join:%d" % i])
		var hov := _hover == "join:%d" % i
		UiKit.panel(self, r, Color(0.05, 0.06, 0.1, 0.6).lerp(Color(1, 1, 1, 0.7), 0.25 if hov else 0.0), 22 * s, Color(1, 1, 1, 0.6 if hov else 0.25), 3 * s)
		var jw := UiKit.text_width("JOIN", 28 * s) + 48 * s
		var jx := (pw - jw) * 0.5
		jx += UiKit.prompt(self, Vector2(jx, 62 * s), "A", 26 * s) + 12 * s
		UiKit.text(self, Vector2(jx, 62 * s), "JOIN", 28 * s, Color(1, 1, 1, a))
		UiKit.text(self, Vector2(0, 96 * s), "or SPACE / click for keyboard", 17 * s, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_CENTER, pw, 500, 0.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if is_player or is_bot:
		var label := "P%d" % (i + 1) if is_player else "CPU"
		var lw := UiKit.text_width(label, 30 * s) + 36 * s
		draw_set_transform(head, sin(_t * 2.0 + i) * 0.04, Vector2(bump, bump))
		UiKit.card(self, Rect2(-lw * 0.5, -22 * s, lw, 44 * s), col, 22 * s, s)
		UiKit.text(self, Vector2(-lw * 0.5, 10 * s), label, 30 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, lw, 700, 0.14)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
