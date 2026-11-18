extends Control
## The Options screen, in pages: one per Settings section (DISPLAY,
## GRAPHICS, AUDIO, CONTROLS, GAMEPLAY) plus two reference pages, HOW TO PLAY
## (every button, help.gd CONTROLS) and MODES (help.gd MODES). Drawn with
## ui_kit.gd. Used from the lobby (Back/Select button or O key) and from the
## pause menu. Any gamepad or the keyboard can drive it:
##   LB / RB or Q / E change page, up/down choose (or scroll a reference
##   page), left/right change, A/Enter also steps forward, B/Esc closes.
## The mouse works too: hover picks a row, click a tab / row (left or right
## half of a value steps it back or on, a slider jumps to where you click),
## the wheel scrolls, right-click or the corner X closes.
##
## Runs with PROCESS_MODE_ALWAYS so it works while the tree is paused. The
## screen that opened it must ignore its own input while `visible` is true.

signal closed

const UiKit = preload("res://scripts/ui_kit.gd")
const Help = preload("res://scripts/help.gd")
const VISIBLE_ROWS := 11

var _pages: Array = []       # [{title, rows}] or [{title, info: "controls" | "modes"}]
var _page := 0
var _sel := 0
var _scroll := 0.0
var _info_scroll := 0.0
var _prev := {}
var _t := 0.0
var _bump := 0.0
var _slide := 0.0           # page change animation (-1..1 -> 0)
var _hits: Array = []       # [Rect2, id, extra] clickable areas from the last _draw
var _hover := ""            # id under the mouse


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var cur: Dictionary = {}
	for row in Settings.rows:
		if row.has("section"):
			cur = {"title": row.section, "rows": []}
			_pages.append(cur)
		elif not cur.is_empty():
			cur.rows.append(row)
	for p in _pages:
		p.rows.append({"action": "reset", "label": "Reset to defaults"})
		p.rows.append({"action": "back", "label": "Back"})
	_pages.append({"title": "HOW TO PLAY", "info": "controls"})
	_pages.append({"title": "MODES", "info": "modes"})


func open() -> void:
	_prev.clear()
	_sel = 0
	_scroll = 0.0
	_info_scroll = 0.0
	visible = true


func _edge(key: String, now: bool) -> bool:
	var was: bool = _prev.get(key, true)
	_prev[key] = now
	return now and not was


func _rows() -> Array:
	return _pages[_page].get("rows", [])


func _turn(dir: int) -> void:
	_page = posmod(_page + dir, _pages.size())
	_sel = 0
	_scroll = 0.0
	_info_scroll = 0.0
	_slide = float(dir)
	Sfx.play("tick", -6.0, 1.1)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_bump = maxf(0.0, _bump - delta * 5.0)
	_slide = move_toward(_slide, 0.0, delta * 6.0)
	queue_redraw()
	var up := _edge("k_up", Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W))
	var down := _edge("k_down", Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S))
	var left := _edge("k_left", Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A))
	var right := _edge("k_right", Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D))
	var accept := _edge("k_ok", Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE))
	var back := _edge("k_back", Input.is_physical_key_pressed(KEY_ESCAPE) or Input.is_physical_key_pressed(KEY_BACKSPACE))
	var prev_page := _edge("k_pp", Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_PAGEUP))
	var next_page := _edge("k_np", Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_PAGEDOWN) or Input.is_physical_key_pressed(KEY_TAB))
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
		prev_page = _edge(k + "lb", Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER)) or prev_page
		next_page = _edge(k + "rb", Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER)) or next_page

	if back:
		_close()
		return
	if prev_page:
		_turn(-1)
	if next_page:
		_turn(1)
	var rows := _rows()
	if rows.is_empty():
		# A reference page: up / down scroll it.
		if up:
			_info_scroll = maxf(0.0, _info_scroll - 3.0)
		if down:
			_info_scroll += 3.0
		return
	if up:
		_sel = posmod(_sel - 1, rows.size())
		Sfx.play("tick", -8.0)
	if down:
		_sel = posmod(_sel + 1, rows.size())
		Sfx.play("tick", -8.0)
	var row: Dictionary = rows[_sel]
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
	var target := clampf(_sel - VISIBLE_ROWS * 0.5 + 0.5, 0.0, maxf(0.0, rows.size() - VISIBLE_ROWS))
	_scroll = lerpf(_scroll, target, clampf(delta * 14.0, 0.0, 1.0))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var h: Array = _hit_at(event.position)
		_hover = "" if h.is_empty() else String(h[1])
		Input.set_default_cursor_shape(Input.CURSOR_ARROW if h.is_empty() else Input.CURSOR_POINTING_HAND)
		if not h.is_empty() and String(h[1]).begins_with("row:"):
			var i := int(String(h[1]).substr(4))
			if i != _sel:
				_sel = i
				Sfx.play("tick", -12.0)
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	get_viewport().set_input_as_handled()
	var rows := _rows()
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			var d := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
			if rows.is_empty():
				_info_scroll = maxf(0.0, _info_scroll + d * 2.0)
			else:
				_sel = clampi(_sel + d, 0, rows.size() - 1)
		MOUSE_BUTTON_RIGHT:
			_close()
		MOUSE_BUTTON_LEFT:
			var h: Array = _hit_at(event.position)
			if h.is_empty():
				return
			var id := String(h[1])
			if id == "close":
				_close()
			elif id.begins_with("tab:"):
				var to := int(id.substr(4))
				if to != _page:
					_turn(to - _page)
			elif id.begins_with("row:"):
				_sel = int(id.substr(4))
				var row: Dictionary = rows[_sel]
				if row.has("action"):
					if row.action == "reset":
						Settings.reset()
						_bump = 1.0
						Sfx.play("card", -8.0)
					else:
						_close()
					return
				var val: Rect2 = h[2]
				var x: float = event.position.x
				var dir := 1
				if row.has("slider") and x >= val.position.x and x <= val.end.x:
					# A slider jumps to where you click.
					var n: int = row.opts.size() - 1
					var want := clampi(int(round((x - val.position.x) / val.size.x * n)), 0, n)
					dir = want - int(Settings.idx[row.key])
					while dir != 0:
						Settings.step(row.key, signi(dir))
						dir -= signi(dir)
				else:
					if x >= val.position.x and x < val.get_center().x:
						dir = -1
					Settings.step(row.key, dir)
				_bump = 1.0
				Sfx.play("tick", -6.0, 1.0 + 0.15 * dir)


func _hit_at(p: Vector2) -> Array:
	for i in range(_hits.size() - 1, -1, -1):
		if (_hits[i][0] as Rect2).has_point(p):
			return _hits[i]
	return []


func _close() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_hover = ""
	visible = false
	Sfx.play("tick", -6.0, 0.8)
	closed.emit()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var s := h / 1080.0
	_hits.clear()
	draw_rect(Rect2(0, 0, w, h), Color(0.1, 0.06, 0.2, 0.72))
	var pw := minf(1180.0 * s, w - 40 * s)
	var panel := Rect2((w - pw) * 0.5, 60 * s, pw, 960 * s)
	UiKit.card(self, panel, Color(UiKit.PANEL, 0.97), 46 * s, s * 2.0)
	# Close button (for the mouse) in the panel's corner.
	var xc := Vector2(panel.end.x - 56 * s, panel.position.y + 56 * s)
	var xr := Rect2(xc - Vector2(26, 26) * s, Vector2(52, 52) * s)
	draw_circle(xc, 26 * s, Color(1, 1, 1, 0.22 if _hover == "close" else 0.1))
	draw_line(xc + Vector2(-10, -10) * s, xc + Vector2(10, 10) * s, UiKit.CREAM, 4 * s, true)
	draw_line(xc + Vector2(10, -10) * s, xc + Vector2(-10, 10) * s, UiKit.CREAM, 4 * s, true)
	_hits.append([xr, "close", null])
	UiKit.text(self, Vector2(panel.position.x, panel.position.y + 78 * s), "OPTIONS", 64 * s, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, pw, 700, 0.14)
	_draw_tabs(panel, s)

	var top := panel.position.y + 176 * s
	var ox := _slide * 60.0 * s
	var fade_all := 1.0 - absf(_slide)
	if _rows().is_empty():
		if _pages[_page].info == "controls":
			_draw_controls(Rect2(panel.position.x + 40 * s + ox, top, pw - 80 * s, panel.end.y - 70 * s - top), s, fade_all)
		else:
			_draw_modes(Rect2(panel.position.x + 40 * s + ox, top, pw - 80 * s, panel.end.y - 70 * s - top), s, fade_all)
	else:
		_draw_rows(panel, top, ox, s, fade_all)
	var help := "LB / RB  page        UP / DOWN  choose        LEFT / RIGHT  change        B  back"
	if not Input.get_connected_joypads().size():
		help = "Q / E  page        UP / DOWN  choose        LEFT / RIGHT  change        ESC  back"
	UiKit.text(self, Vector2(panel.position.x, panel.end.y - 28 * s), help, 21 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, pw, 500, 0.0)


## The page tabs, with LB / RB (or Q / E) prompts at the ends.
func _draw_tabs(panel: Rect2, s: float) -> void:
	var pad: bool = not Input.get_connected_joypads().is_empty()
	var px := 20.0 * s
	var widths: Array = []
	var total := 0.0
	for p in _pages:
		var tw := UiKit.text_width(p.title, px) + 30 * s
		widths.append(tw)
		total += tw + 8 * s
	total -= 8 * s
	var lw := UiKit.text_width("LB" if pad else "Q", 22 * s * 0.8) + 22 * s * 0.8
	var avail := panel.size.x - 80 * s - 2 * (lw + 16 * s)
	var k := minf(1.0, avail / total)
	var y := panel.position.y + 104 * s
	var x := panel.position.x + (panel.size.x - total * k) * 0.5
	UiKit.prompt(self, Vector2(x - lw - 14 * s, y + 31 * s), "LB" if pad else "Q", 22 * s, not pad)
	for i in _pages.size():
		var r := Rect2(x, y, widths[i] * k, 42 * s)
		var on := i == _page
		_hits.append([r, "tab:%d" % i, null])
		if on:
			UiKit.card(self, r, UiKit.GOLD, 21 * s, s)
		else:
			UiKit.panel(self, r, Color(1, 1, 1, 0.16 if _hover == "tab:%d" % i else 0.08), 21 * s)
		draw_string(UiKit.font(700), Vector2(r.position.x, r.position.y + 29 * s), _pages[i].title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(px * k), UiKit.INK if on else Color(1, 1, 1, 0.75))
		x += (widths[i] + 8 * s) * k
	UiKit.prompt(self, Vector2(x + 6 * s, y + 31 * s), "RB" if pad else "E", 22 * s, not pad)


func _draw_rows(panel: Rect2, list_top: float, ox: float, s: float, fade_all: float) -> void:
	var rows := _rows()
	var pw := panel.size.x
	var row_h := 64.0 * s
	var first := int(floor(_scroll))
	for i in range(first, mini(rows.size(), first + VISIBLE_ROWS + 1)):
		var y := list_top + (i - _scroll) * row_h
		var fade := clampf(minf((y - list_top + row_h * 0.6) / (row_h * 0.6), (list_top + VISIBLE_ROWS * row_h - y) / (row_h * 0.6)), 0.0, 1.0) * fade_all
		if fade <= 0.0:
			continue
		var row: Dictionary = rows[i]
		var r := Rect2(panel.position.x + 60 * s + ox, y + 4 * s, pw - 120 * s, row_h - 10 * s)
		var sel := i == _sel
		if fade > 0.5:
			var vr := Rect2(r.end.x - 360 * s, r.position.y, 336 * s, r.size.y)
			if row_has_slider(rows[i]):
				vr = Rect2(r.end.x - 340 * s, r.position.y, 336 * s - 110 * s, r.size.y)
			_hits.append([r, "row:%d" % i, vr])
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
	if rows.size() > VISIBLE_ROWS:
		var track := Rect2(panel.end.x - 34 * s, list_top + 8 * s, 8 * s, VISIBLE_ROWS * row_h - 16 * s)
		UiKit.panel(self, track, Color(1, 1, 1, 0.12), 4 * s)
		var frac2 := float(VISIBLE_ROWS) / rows.size()
		var pos := _scroll / maxf(1.0, rows.size() - VISIBLE_ROWS)
		UiKit.panel(self, Rect2(track.position.x, track.position.y + (track.size.y * (1.0 - frac2)) * pos, track.size.x, track.size.y * frac2), UiKit.GOLD, 4 * s)


func row_has_slider(row: Dictionary) -> bool:
	return row.has("slider")


## HOW TO PLAY: three columns (action, gamepad, keyboard), scrollable.
func _draw_controls(area: Rect2, s: float, fade: float) -> void:
	var row_h := 34.0 * s
	var lines: Array = Help.CONTROLS
	var fit := int(area.size.y / row_h) - 1
	_info_scroll = minf(_info_scroll, maxf(0.0, lines.size() - fit))
	var c1 := area.position.x + 10 * s
	var c2 := area.position.x + area.size.x * 0.45
	var c3 := area.position.x + area.size.x * 0.73
	var y := area.position.y + 20 * s
	draw_string(UiKit.font(700), Vector2(c2, y), "GAMEPAD", HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * s), Color(UiKit.GOLD, fade))
	draw_string(UiKit.font(700), Vector2(c3, y), "KEYBOARD + MOUSE", HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * s), Color(UiKit.GOLD, fade))
	y += row_h
	var start := int(_info_scroll)
	for i in range(start, mini(lines.size(), start + fit)):
		var l: Array = lines[i]
		if l.size() == 1:
			draw_string(UiKit.font(700), Vector2(c1, y + 4 * s), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * s), Color(UiKit.GOLD, fade))
			draw_rect(Rect2(c1, y + 12 * s, area.size.x - 20 * s, 2 * s), Color(UiKit.GOLD, 0.35 * fade))
		else:
			if i % 2 == 0:
				UiKit.panel(self, Rect2(c1 - 8 * s, y - 24 * s, area.size.x - 4 * s, row_h - 2 * s), Color(1, 1, 1, 0.05 * fade), 8 * s)
			draw_string(UiKit.font(600), Vector2(c1, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, c2 - c1 - 10 * s, int(22 * s), Color(UiKit.CREAM, fade))
			draw_string(UiKit.font(700), Vector2(c2, y), l[1], HORIZONTAL_ALIGNMENT_LEFT, c3 - c2 - 10 * s, int(22 * s), Color(1, 1, 1, 0.9 * fade))
			draw_string(UiKit.font(700), Vector2(c3, y), l[2], HORIZONTAL_ALIGNMENT_LEFT, area.end.x - c3, int(22 * s), Color(1, 1, 1, 0.9 * fade))
		y += row_h
	if lines.size() > fit:
		var more := "DOWN for more" if _info_scroll < lines.size() - fit else "UP to go back"
		draw_string(UiKit.font(600), Vector2(area.position.x, area.end.y + 6 * s), more, HORIZONTAL_ALIGNMENT_RIGHT, area.size.x, int(18 * s), Color(1, 1, 1, 0.55 * fade))


## MODES: each mode's name and a short description.
func _draw_modes(area: Rect2, s: float, fade: float) -> void:
	var y := area.position.y + 10 * s
	var tw := area.size.x - 40 * s
	for m in Help.MODES:
		var card := Rect2(area.position.x, y, area.size.x, 132 * s)
		UiKit.panel(self, card, Color(1, 1, 1, 0.06 * fade), 22 * s)
		draw_string(UiKit.font(700), Vector2(card.position.x + 20 * s, y + 38 * s), m[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * s), Color(UiKit.GOLD, fade))
		draw_multiline_string(UiKit.font(600), Vector2(card.position.x + 20 * s, y + 72 * s), m[1], HORIZONTAL_ALIGNMENT_LEFT, tw, int(21 * s), 3, Color(UiKit.CREAM, fade))
		y += 146 * s
