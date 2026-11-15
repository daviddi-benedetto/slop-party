extends Control
## Join screen: a 3D stage (stage.gd) with six podiums and a 2D overlay.
## Polls every gamepad and the keyboard directly; whoever presses their join
## button takes the next free seat and their animal pops onto a podium.
## Players pick their animal with left/right. Seats persist between matches.
##
## main.gd calls activate() to show it and deactivate() before a match (the
## stage shares the root World3D with the match, so it has to be freed).
## Emits start(config) with the dictionary game.gd expects.

signal start(config)

const Stage = preload("res://scripts/stage.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Fx = preload("res://scripts/fx.gd")
const SettingsMenu = preload("res://scripts/settings_menu.gd")

const MAX_PLAYERS := 6
const KEYBOARD := -1
const KILL_TARGETS := [5, 10, 15, 20, 30]
const KIND_COUNT := 6

var seats: Array = []        # [{device, kind}] in join order
var bots := 0
var target_i := 2
var message := ""
var message_t := 0.0

var _stage = null
var _slot_sig: Array = []
var _slot_char: Array = []
var _slot_bump: Array = []   # per-slot UI pop animation timers
var _prev := {}
var _t := 0.0
var _armed := false          # ignore buttons still held from the previous screen
var _options


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.joy_connection_changed.connect(_on_joy_changed)
	for i in MAX_PLAYERS:
		_slot_sig.append("")
		_slot_char.append(null)
		_slot_bump.append(1.0)
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
		_stage = Stage.new()
		add_child(_stage)
		_stage.build(Vector3(0, 2.7, 11.6), Vector3(0, 1.45, 0), 36.0)
		for i in MAX_PLAYERS:
			_stage.add_podium(_slot_pos(i), 0.5, UiKit.PLAYER_COLORS[i])
			_slot_sig[i] = ""
			_slot_char[i] = null


func deactivate() -> void:
	visible = false
	if _stage != null:
		_stage.queue_free()
		_stage = null


func _slot_pos(i: int) -> Vector3:
	var off := i - (MAX_PLAYERS - 1) * 0.5
	return Vector3(off * 2.3, 0.0, absf(off) * -0.28)


func demo_fill(humans: int, cpu: int) -> void:
	for i in humans:
		seats.append({"device": 100 + i if i > 0 else KEYBOARD, "kind": i % KIND_COUNT})
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

	# Keyboard seat.
	var k_seat := _seat_of(KEYBOARD)
	if _edge("k_join", Input.is_physical_key_pressed(KEY_SPACE)) and k_seat < 0:
		_join(KEYBOARD)
	if _edge("k_leave", Input.is_physical_key_pressed(KEY_BACKSPACE)) and k_seat >= 0:
		_leave(KEYBOARD)
	var k_l := _edge("k_l", Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var k_r := _edge("k_r", Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
	if k_seat >= 0 and (k_l or k_r):
		_cycle(k_seat, 1 if k_r else -1)
	if _edge("k_start", Input.is_physical_key_pressed(KEY_ENTER)):
		want_start = true
	if _edge("k_bots", Input.is_physical_key_pressed(KEY_B)): bot_step = true
	if _edge("k_target", Input.is_physical_key_pressed(KEY_K)): target_step = true
	if _edge("k_quit", Input.is_physical_key_pressed(KEY_ESCAPE)) and _armed:
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
		var left := _edge(k + "l", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT) or sx < -0.6)
		var right := _edge(k + "r", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT) or sx > 0.6)
		if seat >= 0 and (left or right):
			_cycle(seat, 1 if right else -1)
		if _edge(k + "start", Input.is_joy_button_pressed(d, JOY_BUTTON_START)):
			want_start = true
		if _edge(k + "y", Input.is_joy_button_pressed(d, JOY_BUTTON_Y)): bot_step = true
		if _edge(k + "x", Input.is_joy_button_pressed(d, JOY_BUTTON_X)): target_step = true
		if _edge(k + "back", Input.is_joy_button_pressed(d, JOY_BUTTON_BACK)): want_options = true
	var was_armed := _armed
	_armed = true
	if want_options and was_armed:
		_options.open()
		return

	if bot_step:
		var room := MAX_PLAYERS - seats.size()
		bots = 0 if bots >= room else bots + 1
		Sfx.play("tick", -8.0)
	if target_step:
		target_i = (target_i + 1) % KILL_TARGETS.size()
		Sfx.play("tick", -8.0)
	if want_start:
		if seats.is_empty():
			_say("Someone has to join first!")
		elif seats.size() + bots < 2:
			_say("Need 2 or more fighters - add a player or a bot")
		else:
			_start()
	_sync_stage()


func _say(text: String) -> void:
	message = text
	message_t = 3.0
	Sfx.play("hurt", -12.0)


func _join(device: int) -> void:
	if seats.size() >= MAX_PLAYERS:
		return
	var used := {}
	for s in seats:
		used[s.kind] = true
	var kind := 0
	while used.has(kind) and kind < KIND_COUNT - 1:
		kind += 1
	seats.append({"device": device, "kind": kind})
	_clamp_bots()
	Sfx.play("join", -6.0)


func _leave(device: int) -> void:
	seats = seats.filter(func(s): return s.device != device)
	Sfx.play("tick", -8.0, 0.7)


func _cycle(seat: int, step: int) -> void:
	seats[seat].kind = posmod(seats[seat].kind + step, KIND_COUNT)
	Sfx.play("tick", -8.0)


func _bot_kind(slot: int) -> int:
	return (slot * 5 + 3) % KIND_COUNT


## Make the 3D podiums match seats/bots.
func _sync_stage() -> void:
	if _stage == null:
		return
	for i in MAX_PLAYERS:
		var sig := ""
		var kind := 0
		if i < seats.size():
			kind = seats[i].kind
			sig = "p%d" % kind
		elif i < seats.size() + bots:
			kind = _bot_kind(i)
			sig = "b%d" % kind
		if sig == _slot_sig[i]:
			continue
		_slot_sig[i] = sig
		_slot_bump[i] = 0.0
		if _slot_char[i] != null:
			_stage.remove_character(_slot_char[i])
			_slot_char[i] = null
		if sig != "":
			var pos := _slot_pos(i) + Vector3(0, 0.56, 0)
			_slot_char[i] = _stage.add_character(kind, UiKit.PLAYER_COLORS[i], pos)
			Fx.confetti(_stage, pos + Vector3(0, 1.0, 0), 22, 4.5, 1.2)
			Fx.puff(_stage, pos + Vector3(0, 0.3, 0), Color(1, 1, 1, 0.8), 8, 0.6)


func _start() -> void:
	var parts: Array = []
	for i in seats.size():
		parts.append({"device": seats[i].device, "bot": false, "view": true, "kind": seats[i].kind})
	for i in bots:
		parts.append({"device": -2, "bot": true, "view": false, "kind": _bot_kind(seats.size() + i)})
	start.emit({"participants": parts, "kill_target": KILL_TARGETS[target_i]})


# --------------------------------------------------------------------------
# Drawing
# --------------------------------------------------------------------------

func _draw() -> void:
	var w := size.x
	var h := size.y
	var s := h / 1080.0
	draw_texture_rect(UiKit.vignette(), Rect2(0, 0, w, h), false, Color(0.12, 0.06, 0.25, 0.22))

	# Bouncing logo.
	var title := "FRAGDECK"
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
		var pos := Vector2(x + widths[i] * 0.5, 165 * s - maxf(0.0, bounce) * 16 * s)
		draw_set_transform(pos, bounce * 0.045, Vector2.ONE)
		var col := UiKit.GOLD.lerp(Color(1.0, 0.55, 0.3), 0.5 + 0.5 * sin(i * 0.9))
		UiKit.text(self, Vector2(-widths[i] * 0.5, 0), title[i], px, col, HORIZONTAL_ALIGNMENT_CENTER, widths[i], 700, 0.14)
		x += widths[i]
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tag := "SPLITSCREEN PARTY SHOOTER  -  EVERY KO DEALS YOU A POWERUP"
	var tw := UiKit.text_width(tag, 26 * s) + 60 * s
	UiKit.card(self, Rect2((w - tw) * 0.5, 196 * s, tw, 46 * s), UiKit.PANEL, 23 * s, s)
	UiKit.text(self, Vector2(0, 228 * s), tag, 26 * s, UiKit.CREAM, HORIZONTAL_ALIGNMENT_CENTER, w, 600, 0.0)

	# Seat plates, positioned under the 3D podiums.
	if _stage != null and _stage.camera != null and not _options.visible:
		for i in MAX_PLAYERS:
			var base: Vector2 = _stage.camera.unproject_position(_slot_pos(i) + Vector3(0, 0.0, 0.9))
			var head: Vector2 = _stage.camera.unproject_position(_slot_pos(i) + Vector3(0, 3.05, 0))
			_draw_seat(i, base, head, s)

	# Settings + start.
	var by := h - 168 * s
	var pad: bool = not Input.get_connected_joypads().is_empty()
	var chips := [
		["Y" if pad else "B", "BOTS", str(bots)],
		["X" if pad else "K", "FIRST TO", "%d KOs" % KILL_TARGETS[target_i]],
		["BACK" if pad else "O", "OPTIONS", ""],
	]
	var cx := w * 0.5 - 500 * s
	for chip in chips:
		var r := Rect2(cx, by, 320 * s, 60 * s)
		UiKit.card(self, r, UiKit.PANEL, 30 * s, s)
		var ox := r.position.x + 18 * s
		ox += UiKit.prompt(self, Vector2(ox, by + 42 * s), chip[0], 28 * s, not pad) + 14 * s
		UiKit.text(self, Vector2(ox, by + 41 * s), chip[1], 26 * s, UiKit.CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1, 600, 0.0)
		UiKit.text(self, Vector2(r.position.x, by + 42 * s), chip[2], 30 * s, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 24 * s)
		cx += 340 * s

	var ready := not seats.is_empty() and seats.size() + bots >= 2
	var sy := h - 62 * s
	if ready:
		var pulse := 1.0 + sin(_t * 5.0) * 0.04
		draw_set_transform(Vector2(w * 0.5, sy - 14 * s), 0.0, Vector2(pulse, pulse))
		var label := "PRESS  START  TO FIGHT!" if pad else "PRESS  ENTER  TO FIGHT!"
		UiKit.text(self, Vector2(-w * 0.5, 16 * s), label, 46 * s, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, w, 700, 0.16)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		UiKit.text(self, Vector2(0, sy), "WAITING FOR PLAYERS...", 36 * s, Color(1, 1, 1, 0.7 + 0.3 * sin(_t * 3.0)), HORIZONTAL_ALIGNMENT_CENTER, w, 700, 0.16)
	if message_t > 0.0:
		var mw := UiKit.text_width(message, 26 * s) + 50 * s
		var bump := UiKit.back_out(clampf((3.0 - message_t) * 5.0, 0.0, 1.0))
		draw_set_transform(Vector2(w * 0.5, by - 44 * s), 0.0, Vector2(bump, bump))
		UiKit.card(self, Rect2(-mw * 0.5, -24 * s, mw, 48 * s), Color(1.0, 0.4, 0.42), 24 * s, s)
		UiKit.text(self, Vector2(-mw * 0.5, 9 * s), message, 26 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, mw, 700, 0.12)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	UiKit.text(self, Vector2(0, h - 14 * s), "GAMEPAD   L-stick move  -  R-stick aim  -  RT fire  -  A jump  -  B dash  -  X reload          KEYBOARD   WASD  -  mouse  -  LMB  -  Space  -  Shift  -  R          F11 fullscreen  -  Esc quit",
		16 * s, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, w, 500, 0.12)


func _draw_seat(i: int, base: Vector2, head: Vector2, s: float) -> void:
	var col: Color = UiKit.PLAYER_COLORS[i]
	var pw := 268.0 * s
	var bump := UiKit.back_out(_slot_bump[i])
	var is_player := i < seats.size()
	var is_bot := not is_player and i < seats.size() + bots
	draw_set_transform(base, 0.0, Vector2(0.85 + 0.15 * bump, 0.85 + 0.15 * bump))
	var r := Rect2(-pw * 0.5, 0, pw, 92 * s)
	if is_player:
		var seat: Dictionary = seats[i]
		UiKit.card(self, r, col.darkened(0.35), 22 * s, s)
		UiKit.panel(self, Rect2(r.position + Vector2(5, 5) * s, Vector2(pw - 10 * s, 34 * s)), Color(1, 1, 1, 0.14), 17 * s)
		var dev := "KEYBOARD" if seat.device == KEYBOARD else "GAMEPAD %d" % (seat.device + 1)
		UiKit.text(self, Vector2(r.position.x, 33 * s), dev, 22 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, pw, 600, 0.12)
		var wob := sin(_t * 6.0) * 3 * s
		UiKit.text(self, Vector2(r.position.x + 22 * s - wob, 76 * s), "<", 30 * s, UiKit.GOLD)
		UiKit.text(self, Vector2(r.position.x, 76 * s), ">", 30 * s, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, pw - 22 * s - wob)
		UiKit.text(self, Vector2(r.position.x, 76 * s), UiKit.KIND_NAMES[seat.kind], 32 * s, UiKit.CREAM, HORIZONTAL_ALIGNMENT_CENTER, pw)
	elif is_bot:
		UiKit.card(self, r, Color(0.3, 0.26, 0.42, 0.92), 22 * s, s)
		UiKit.text(self, Vector2(r.position.x, 40 * s), "CPU", 30 * s, col.lerp(Color.WHITE, 0.4), HORIZONTAL_ALIGNMENT_CENTER, pw)
		UiKit.text(self, Vector2(r.position.x, 74 * s), UiKit.KIND_NAMES[_bot_kind(i)], 22 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, pw, 600, 0.0)
	else:
		var a := 0.6 + 0.3 * sin(_t * 3.0 + i)
		UiKit.panel(self, r, Color(0.2, 0.16, 0.3, 0.55), 22 * s, Color(1, 1, 1, 0.35), 3 * s)
		var jw := UiKit.text_width("JOIN", 28 * s) + 48 * s
		var jx := -jw * 0.5
		jx += UiKit.prompt(self, Vector2(jx, 44 * s), "A", 26 * s) + 12 * s
		UiKit.text(self, Vector2(jx, 44 * s), "JOIN", 28 * s, Color(1, 1, 1, a))
		UiKit.text(self, Vector2(r.position.x, 76 * s), "or SPACE on keyboard", 17 * s, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, pw, 500, 0.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if is_player or is_bot:
		var label := "P%d" % (i + 1) if is_player else "CPU"
		var lw := UiKit.text_width(label, 30 * s) + 36 * s
		draw_set_transform(head, sin(_t * 2.0 + i) * 0.04, Vector2(bump, bump))
		UiKit.card(self, Rect2(-lw * 0.5, -22 * s, lw, 44 * s), col, 22 * s, s)
		UiKit.text(self, Vector2(-lw * 0.5, 10 * s), label, 30 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, lw, 700, 0.14)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
