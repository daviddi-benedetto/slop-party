extends Control
## The Options screen. A scrolling list of everything in Settings.rows, drawn
## with ui_kit.gd. Used from the lobby (Back/Select button or O key) and from
## the pause menu. Any gamepad or the keyboard can drive it:
##   up/down choose, left/right change, A/Enter also steps forward, B/Esc closes.
##
## Runs with PROCESS_MODE_ALWAYS so it works while the tree is paused. The
## screen that opened it must ignore its own input while `visible` is true.

signal closed

const UiKit = preload("res://scripts/ui_kit.gd")
const VISIBLE_ROWS := 11

var _rows: Array = []        # Settings.rows + two action rows
var _sel := 1
var _scroll := 0.0
var _prev := {}
var _t := 0.0
var _bump := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_rows = Settings.rows.duplicate()
	_rows.append({"section": ""})
	_rows.append({"action": "reset", "label": "Reset to defaults"})
	_rows.append({"action": "back", "label": "Back"})


func open() -> void:
	_prev.clear()
	_sel = 1
	_scroll = 0.0
	visible = true


func _edge(key: String, now: bool) -> bool:
	var was: bool = _prev.get(key, true)
	_prev[key] = now
	return now and not was


func _selectable(i: int) -> bool:
	return not _rows[i].has("section")


func _move(dir: int) -> void:
	var i := _sel
	for n in _rows.size():
		i = posmod(i + dir, _rows.size())
		if _selectable(i):
			break
	_sel = i
	Sfx.play("tick", -8.0)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_bump = maxf(0.0, _bump - delta * 5.0)
	queue_redraw()
	var up := _edge("k_up", Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W))
	var down := _edge("k_down", Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S))
	var left := _edge("k_left", Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A))
	var right := _edge("k_right", Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D))
	var accept := _edge("k_ok", Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE))
	var back := _edge("k_back", Input.is_physical_key_pressed(KEY_ESCAPE) or Input.is_physical_key_pressed(KEY_BACKSPACE))
	for d in Input.get_connected_joypads():
		var k := "j%d" % d
		var sx := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
		var sy := Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)
		up = _edge(k + "u", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP) or sy < -0.6) or up
		down = _edge(k + "d", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN) or sy > 0.6) or down
		left = _edge(k + "l", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT) or sx < -0.6) or left
		right = _edge(k + "r", Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT) or sx > 0.6) or right
		accept = _edge(k + "a", Input.is_joy_button_pressed(d, JOY_BUTTON_A)) or accept
		back = _edge(k + "b", Input.is_joy_button_pressed(d, JOY_BUTTON_B) or Input.is_joy_button_pressed(d, JOY_BUTTON_BACK) or Input.is_joy_button_pressed(d, JOY_BUTTON_START)) or back

	if back:
		_close()
		return
	if up:
		_move(-1)
	if down:
		_move(1)
	var row: Dictionary = _rows[_sel]
	if row.has("key"):
		var dir := (1 if right or accept else 0) - (1 if left else 0)
		if dir != 0:
			Settings.step(row.key, dir)
			_bump = 1.0
			Sfx.play("tick", -6.0, 1.0 + 0.15 * dir)
	elif accept:
		if row.action == "reset":
			Settings.reset()
			_bump = 1.0
			Sfx.play("card", -8.0)
		else:
			_close()
	# Keep the selection in view.
	var target := clampf(_sel - VISIBLE_ROWS * 0.5 + 0.5, 0.0, maxf(0.0, _rows.size() - VISIBLE_ROWS))
	_scroll = lerpf(_scroll, target, clampf(delta * 14.0, 0.0, 1.0))


func _close() -> void:
	visible = false
	Sfx.play("tick", -6.0, 0.8)
	closed.emit()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var s := h / 1080.0
	draw_rect(Rect2(0, 0, w, h), Color(0.1, 0.06, 0.2, 0.72))
	var pw := 1040.0 * s
	var row_h := 62.0 * s
	var panel := Rect2((w - pw) * 0.5, 70 * s, pw, 940 * s)
	UiKit.card(self, panel, Color(UiKit.PANEL, 0.97), 46 * s, s * 2.0)
	UiKit.text(self, Vector2(panel.position.x, panel.position.y + 86 * s), "OPTIONS", 76 * s, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, pw, 700, 0.14)

	var list_top := panel.position.y + 122 * s
	var first := int(floor(_scroll))
	for i in range(first, mini(_rows.size(), first + VISIBLE_ROWS + 1)):
		var y := list_top + (i - _scroll) * row_h
		var fade := clampf(minf((y - list_top + row_h * 0.6) / (row_h * 0.6), (list_top + VISIBLE_ROWS * row_h - y) / (row_h * 0.6)), 0.0, 1.0)
		if fade <= 0.0:
			continue
		var row: Dictionary = _rows[i]
		var r := Rect2(panel.position.x + 44 * s, y + 4 * s, pw - 88 * s, row_h - 8 * s)
		if row.has("section"):
			UiKit.text(self, Vector2(r.position.x + 6 * s, r.end.y - 10 * s), row.section, 24 * s, Color(UiKit.GOLD, fade), HORIZONTAL_ALIGNMENT_LEFT, -1, 700, 0.0)
			if row.section != "":
				draw_rect(Rect2(r.position.x + 6 * s, r.end.y - 3 * s, r.size.x - 12 * s, 3 * s), Color(UiKit.GOLD, 0.4 * fade))
			continue
		var sel := i == _sel
		if sel:
			var g := 3.0 * s + sin(_t * 6.0) * 1.5 * s + _bump * 4.0 * s
			UiKit.card(self, r.grow(g), UiKit.GOLD, 27 * s, s)
		else:
			UiKit.panel(self, r, Color(1, 1, 1, 0.07 * fade), 27 * s)
		var ink := UiKit.INK if sel else Color(UiKit.CREAM, fade)
		var base := r.get_center().y + 11 * s
		if row.has("action"):
			draw_string(UiKit.font(700), Vector2(r.position.x, base), row.label.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(30 * s), ink)
			continue
		draw_string(UiKit.font(600), Vector2(r.position.x + 26 * s, base), row.label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * s), ink)
		var vx := r.end.x - 360 * s
		var vw := 336.0 * s
		if row.has("slider"):
			var n: int = row.opts.size() - 1
			var frac: float = float(Settings.idx[row.key]) / maxf(1.0, n)
			var bar := Rect2(vx + 20 * s, r.get_center().y - 8 * s, vw - 110 * s, 16 * s)
			UiKit.panel(self, bar, Color(0.17, 0.12, 0.24, fade) if sel else Color(1, 1, 1, 0.16 * fade), 8 * s)
			if frac > 0.0:
				UiKit.panel(self, Rect2(bar.position, Vector2(maxf(bar.size.y, bar.size.x * frac), bar.size.y)), Color(1.0, 0.45, 0.4, fade) if sel else Color(UiKit.GOLD, fade), 8 * s)
			draw_string(UiKit.font(700), Vector2(bar.end.x, base), Settings.label(row.key), HORIZONTAL_ALIGNMENT_RIGHT, 80 * s, int(30 * s), ink)
		else:
			if sel:
				draw_string(UiKit.font(700), Vector2(vx, base), "<", HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * s), ink)
				draw_string(UiKit.font(700), Vector2(vx, base), ">", HORIZONTAL_ALIGNMENT_RIGHT, vw, int(30 * s), ink)
			draw_string(UiKit.font(700), Vector2(vx, base), Settings.label(row.key), HORIZONTAL_ALIGNMENT_CENTER, vw, int(30 * s), ink)

	# Scroll bar and help line.
	var track := Rect2(panel.end.x - 28 * s, list_top + 8 * s, 8 * s, VISIBLE_ROWS * row_h - 16 * s)
	UiKit.panel(self, track, Color(1, 1, 1, 0.12), 4 * s)
	var frac2 := float(VISIBLE_ROWS) / _rows.size()
	var pos := _scroll / maxf(1.0, _rows.size() - VISIBLE_ROWS)
	UiKit.panel(self, Rect2(track.position.x, track.position.y + (track.size.y * (1.0 - frac2)) * pos, track.size.x, track.size.y * frac2), UiKit.GOLD, 4 * s)
	UiKit.text(self, Vector2(panel.position.x, panel.end.y - 34 * s), "UP / DOWN  choose        LEFT / RIGHT  change        B / ESC  back", 22 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, pw, 500, 0.0)
