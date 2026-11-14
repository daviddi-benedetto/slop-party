extends Control
## Join screen. Polls every gamepad and the keyboard directly; whoever presses
## their join button takes the next free seat. Seats persist between matches
## (main.gd keeps this node alive and just hides it during a match).
##
## Emits start(config) with the dictionary game.gd expects.

signal start(config)

const MAX_PLAYERS := 6
const KEYBOARD := -1
const KILL_TARGETS := [5, 10, 15, 20, 30]
const COLORS := [
	Color(0.86, 0.22, 0.2), Color(0.2, 0.47, 0.9), Color(0.25, 0.75, 0.3),
	Color(0.95, 0.78, 0.15), Color(0.7, 0.35, 0.85), Color(0.95, 0.5, 0.15),
]

var seats: Array = []        # device ids, in join order
var bots := 0
var target_i := 2
var message := ""
var _prev := {}
var _t := 0.0
var _armed := false          # ignore buttons still held from the previous screen


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.joy_connection_changed.connect(_on_joy_changed)


func activate() -> void:
	_armed = false
	_prev.clear()
	message = ""
	visible = true


func _on_joy_changed(device: int, connected: bool) -> void:
	if not connected and seats.has(device):
		seats.erase(device)
		_clamp_bots()


func _clamp_bots() -> void:
	bots = clampi(bots, 0, MAX_PLAYERS - seats.size())


func _edge(key: String, now: bool) -> bool:
	var was: bool = _prev.get(key, true)
	_prev[key] = now
	return now and not was


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()

	var want_start := false
	var bot_delta := 0
	var target_delta := 0

	# Keyboard seat.
	if _edge("k_join", Input.is_physical_key_pressed(KEY_SPACE)) and not seats.has(KEYBOARD):
		_join(KEYBOARD)
	if _edge("k_leave", Input.is_physical_key_pressed(KEY_BACKSPACE)) and seats.has(KEYBOARD):
		seats.erase(KEYBOARD)
	if _edge("k_start", Input.is_physical_key_pressed(KEY_ENTER)):
		want_start = true
	if _edge("k_up", Input.is_physical_key_pressed(KEY_UP)): bot_delta += 1
	if _edge("k_down", Input.is_physical_key_pressed(KEY_DOWN)): bot_delta -= 1
	if _edge("k_right", Input.is_physical_key_pressed(KEY_RIGHT)): target_delta += 1
	if _edge("k_left", Input.is_physical_key_pressed(KEY_LEFT)): target_delta -= 1
	if _edge("k_quit", Input.is_physical_key_pressed(KEY_ESCAPE)) and _armed:
		get_tree().quit()
	if _edge("k_full", Input.is_physical_key_pressed(KEY_F11)):
		var win := get_window()
		win.mode = Window.MODE_WINDOWED if win.mode != Window.MODE_WINDOWED else Window.MODE_FULLSCREEN

	# Gamepad seats.
	for d in Input.get_connected_joypads():
		var k := "j%d_" % d
		if _edge(k + "a", Input.is_joy_button_pressed(d, JOY_BUTTON_A)) and not seats.has(d):
			_join(d)
		if _edge(k + "b", Input.is_joy_button_pressed(d, JOY_BUTTON_B)) and seats.has(d):
			seats.erase(d)
		if _edge(k + "start", Input.is_joy_button_pressed(d, JOY_BUTTON_START)):
			want_start = true
		if _edge(k + "up", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP)): bot_delta += 1
		if _edge(k + "down", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN)): bot_delta -= 1
		if _edge(k + "right", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT)): target_delta += 1
		if _edge(k + "left", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT)): target_delta -= 1
	_armed = true

	if bot_delta != 0:
		bots += bot_delta
		_clamp_bots()
		Sfx.play("tick", -8.0)
	if target_delta != 0:
		target_i = clampi(target_i + target_delta, 0, KILL_TARGETS.size() - 1)
		Sfx.play("tick", -8.0)
	if want_start:
		if seats.is_empty():
			message = "At least one player has to join first"
		elif seats.size() + bots < 2:
			message = "Need 2 or more fighters - join another player or add bots"
		else:
			_start()


func _join(device: int) -> void:
	if seats.size() >= MAX_PLAYERS:
		return
	seats.append(device)
	_clamp_bots()
	message = ""
	Sfx.play("join", -6.0)


func _start() -> void:
	var parts: Array = []
	for d in seats:
		parts.append({"device": d, "bot": false, "view": true})
	for i in bots:
		parts.append({"device": -2, "bot": true, "view": false})
	start.emit({"participants": parts, "kill_target": KILL_TARGETS[target_i]})


func _text(pos: Vector2, text: String, px: float, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var font := ThemeDB.fallback_font
	var s := size.y / 1080.0
	var fs := maxi(8, int(px * s))
	draw_string_outline(font, pos, text, align, width, fs, maxi(2, fs / 6), Color(0, 0, 0, 0.8))
	draw_string(font, pos, text, align, width, fs, color)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var s := h / 1080.0
	draw_rect(Rect2(0, 0, w, h), Color(0.09, 0.08, 0.1))
	draw_rect(Rect2(0, 0, w, 210 * s), Color(0.55, 0.2, 0.14))
	draw_rect(Rect2(0, 206 * s, w, 8 * s), Color(0.95, 0.75, 0.3))
	_text(Vector2(0, 130 * s), "FRAGDECK", 110, Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(0, 180 * s), "splitscreen deathmatch  -  every death deals you a powerup", 28, Color(1, 0.85, 0.6), HORIZONTAL_ALIGNMENT_CENTER, w)

	# Seats, 3 x 2.
	var sw := 520.0 * s
	var sh := 190.0 * s
	var gap := 30.0 * s
	var x0 := (w - (sw * 3 + gap * 2)) * 0.5
	var y0 := 270.0 * s
	for i in MAX_PLAYERS:
		var r := Rect2(x0 + (i % 3) * (sw + gap), y0 + (i / 3) * (sh + gap), sw, sh)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(int(14 * s))
		sb.set_border_width_all(int(4 * s))
		var col: Color = COLORS[i]
		if i < seats.size():
			sb.bg_color = col.darkened(0.55)
			sb.border_color = col
			draw_style_box(sb, r)
			_text(r.position + Vector2(24 * s, 78 * s), "P%d" % (i + 1), 64, col.lerp(Color.WHITE, 0.35))
			var dev: int = seats[i]
			var dev_name := "Keyboard + Mouse" if dev == KEYBOARD else "Gamepad %d" % (dev + 1)
			_text(r.position + Vector2(24 * s, 124 * s), dev_name, 28, Color.WHITE)
			_text(r.position + Vector2(24 * s, 162 * s), "READY   (%s to leave)" % ("Backspace" if dev == KEYBOARD else "B"), 22, Color(0.75, 0.95, 0.75))
		elif i < seats.size() + bots:
			sb.bg_color = Color(0.16, 0.16, 0.2)
			sb.border_color = col.darkened(0.3)
			draw_style_box(sb, r)
			_text(r.position + Vector2(24 * s, 78 * s), "BOT", 64, col.lerp(Color.WHITE, 0.2))
			_text(r.position + Vector2(24 * s, 124 * s), "Computer controlled", 28, Color(0.8, 0.8, 0.8))
		else:
			sb.bg_color = Color(0.12, 0.12, 0.15)
			sb.border_color = Color(0.3, 0.3, 0.35)
			draw_style_box(sb, r)
			var pulse := 0.55 + 0.35 * sin(_t * 3.0)
			_text(r.position + Vector2(0, 90 * s), "PRESS (A) TO JOIN", 34, Color(1, 1, 1, pulse), HORIZONTAL_ALIGNMENT_CENTER, sw)
			_text(r.position + Vector2(0, 130 * s), "or SPACE for keyboard + mouse", 22, Color(0.7, 0.7, 0.7, pulse), HORIZONTAL_ALIGNMENT_CENTER, sw)

	var y := y0 + sh * 2 + gap + 70 * s
	_text(Vector2(0, y), "BOTS:  %d      (D-pad / arrows  UP  DOWN)" % bots, 32, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(0, y + 50 * s), "FIRST TO:  %d KILLS      (D-pad / arrows  LEFT  RIGHT)" % KILL_TARGETS[target_i], 32, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)
	var ready := not seats.is_empty() and seats.size() + bots >= 2
	_text(Vector2(0, y + 120 * s), "PRESS START / ENTER TO FIGHT" if ready else "waiting for players...", 40,
		Color(1, 0.85, 0.3, 0.7 + 0.3 * sin(_t * 4.0)) if ready else Color(0.6, 0.6, 0.6), HORIZONTAL_ALIGNMENT_CENTER, w)
	if message != "":
		_text(Vector2(0, y + 165 * s), message, 26, Color(1, 0.5, 0.4), HORIZONTAL_ALIGNMENT_CENTER, w)

	var fy := h - 78 * s
	_text(Vector2(0, fy), "GAMEPAD:  L-stick move   R-stick aim   RT fire   A / LT jump   B / LB dash   X reload   Start+Back quit match", 22, Color(0.75, 0.75, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(0, fy + 32 * s), "KEYBOARD:  WASD move   mouse aim   LMB fire   Space jump   Shift / RMB dash   R reload   Esc quit   F11 fullscreen", 22, Color(0.75, 0.75, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(0, fy + 60 * s), "%d gamepad(s) detected" % Input.get_connected_joypads().size(), 18, Color(0.5, 0.5, 0.55), HORIZONTAL_ALIGNMENT_CENTER, w)
