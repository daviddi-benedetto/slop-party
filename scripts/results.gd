extends Control
## Victory screen shown by game.gd after the match world has been freed:
## a 3D podium (stage.gd) with the top three, confetti, and a results table.
##
## `rows` is a snapshot, best first: [{name, color, kind, kills, deaths, cards,
## knife, boxes, damage, streak}]. The last four feed the awards: up to four
## fun titles (most melee KOs, most mystery boxes, fewest deaths, longest
## streak, most damage) that slide in down the right side. Every number
## counts up as its card arrives.
## Emits done() when someone presses a confirm button (or after a timeout).

signal done

const Stage = preload("res://scripts/stage.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Fx = preload("res://scripts/fx.gd")

var _clicked := false        # mouse click (continue)
var rows: Array = []
var look := {}               # the match's visual theme (looks.gd), set by game.gd
var title := ""              # set by game.gd for team / co-op modes; default "<winner> WINS!"
var _stage
var _t := 0.0
var _finished := false
var _awards: Array = []      # [title, line, icon, row index, value]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage = Stage.new()
	add_child(_stage)
	_stage.build(Vector3(0, 3.3, 12.5), Vector3(0, 2.1, 0), 34.0, look)

	var spots := [
		[Vector3(0, 0, 0), 1.7], [Vector3(-2.3, 0, 0.2), 1.15], [Vector3(2.3, 0, 0.2), 0.8],
		[Vector3(-4.7, 0, 0.9), 0.25], [Vector3(4.7, 0, 0.9), 0.25], [Vector3(-6.6, 0, 1.6), 0.25],
	]
	for i in mini(rows.size(), spots.size()):
		var row: Dictionary = rows[i]
		var top: float = _stage.add_podium(spots[i][0], spots[i][1], row.color)
		var look := {"kind": row.kind, "color": row.color, "hat": row.get("hat", 0), "face": row.get("face", 0), "back": row.get("back", 0)}
		if i == 0:
			look.hat = 2      # the winner always wears the crown
		var c = _stage.add_character(look, Vector3(spots[i][0].x, top, spots[i][0].z))
		if i == 0:
			c.emote = "cheer"
		elif i >= 3:
			c.emote = "sad"
	_awards = _pick_awards()
	Fx.confetti_rain(_stage, Vector3(0, 9.0, 0), Vector3(8.0, 0.5, 2.0))
	Fx.confetti(_stage, Vector3(-3, 1.5, 2), 60, 9.0, 2.2)
	Fx.confetti(_stage, Vector3(3, 1.5, 2), 60, 9.0, 2.2)
	Sfx.play("win", -2.0)
	Sfx.music("lobby")


## The fun titles: each goes to the best player for it, preferring players
## who have not won one yet, and only when it means something.
func _pick_awards() -> Array:
	if not rows.is_empty() and not (rows[0].get("stats", []) as Array).is_empty():
		return []                 # a mode with its own columns (Racing): no KO awards
	var defs := [
		["knife", "UP CLOSE", "%d melee KOs", "skull", 1, true],
		["boxes", "BOX ADDICT", "opened %d mystery boxes", "star", 2, true],
		["streak", "ON A ROLL", "%d KOs without dying", "bolt", 3, true],
		["damage", "HEAVY HITTER", "%d damage dealt", "boom", 1, true],
		["deaths", "SURVIVOR", "only %d deaths", "shield", 0, false],
	]
	var out: Array = []
	var used := {}
	for d in defs:
		if rows.size() < 2 or out.size() >= 4:
			break
		var best := -1
		for i in rows.size():
			var v: int = int(rows[i].get(d[0], 0))
			if best < 0:
				best = i
				continue
			var bv: int = int(rows[best].get(d[0], 0))
			var better: bool = v > bv if d[5] else v < bv
			if better or (v == bv and used.has(best) and not used.has(i)):
				best = i
		var val: int = int(rows[best].get(d[0], 0))
		if (d[5] and val < d[4]) or (not d[5] and used.has(best)):
			continue
		used[best] = true
		out.append([d[1], d[2], d[3], best, val])
	return out


## A number counting up from 0 once its card has arrived.
func _count(value: int, start: float) -> String:
	var k := clampf((_t - start) / 0.9, 0.0, 1.0)
	k = 1.0 - pow(1.0 - k, 3.0)
	return str(roundi(value * k))


## A click anywhere continues too (once the table is up).
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _t > 2.0:
		_clicked = true


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _stage != null and _stage.camera != null:
		# Slow push-in.
		var k := 1.0 - pow(0.5, _t * 0.6)
		_stage.camera.look_at_from_position(Vector3(sin(_t * 0.2) * 0.8, 3.3 - k * 0.3, 12.5 - k * 2.6), Vector3(0, 2.1, 0))
	if _finished:
		return
	var go := _t > 25.0
	if _t > 2.0:
		go = go or Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE) or _clicked
		for d in Input.get_connected_joypads():
			if Input.is_joy_button_pressed(d, JOY_BUTTON_A) or Input.is_joy_button_pressed(d, JOY_BUTTON_START):
				go = true
	if go:
		_finished = true
		done.emit()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var s := h / 1080.0
	draw_texture_rect(UiKit.vignette(), Rect2(0, 0, w, h), false, Color(0.12, 0.06, 0.25, 0.25))
	if rows.is_empty():
		return
	var win: Dictionary = rows[0]

	# Winner banner.
	var pop := UiKit.elastic_out(clampf(_t * 0.9, 0.0, 1.0))
	draw_set_transform(Vector2(w * 0.5, 120 * s), -0.03 + sin(_t * 2.0) * 0.01, Vector2(pop, pop))
	var heading: String = title if title != "" else "%s WINS!" % win.name
	var bw := UiKit.text_width(heading, 110 * s) + 140 * s
	UiKit.card(self, Rect2(-bw * 0.5, -78 * s, bw, 150 * s), win.color.darkened(0.15), 40 * s, s * 1.6)
	UiKit.panel(self, Rect2(-bw * 0.5 + 10 * s, -68 * s, bw - 20 * s, 50 * s), Color(1, 1, 1, 0.16), 30 * s)
	UiKit.text(self, Vector2(-bw * 0.5, 36 * s), heading, 110 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bw, 700, 0.14)
	UiKit.icon(self, "crown", Vector2(-bw * 0.5 + 8 * s, -74 * s), 44 * s, UiKit.INK)
	UiKit.icon(self, "crown", Vector2(-bw * 0.5 + 8 * s, -80 * s), 40 * s, UiKit.GOLD)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Results table along the bottom.
	var n := rows.size()
	var cw := minf(292.0 * s, (w - 60 * s) / n - 12 * s)
	var gap := 12.0 * s
	var x0 := (w - (cw * n + gap * (n - 1))) * 0.5
	for i in n:
		var row: Dictionary = rows[i]
		var slide := UiKit.back_out(clampf((_t - 0.6 - i * 0.1) / 0.45, 0.0, 1.0))
		var r := Rect2(x0 + i * (cw + gap), h - 232 * s + (1.0 - slide) * 320 * s, cw, 150 * s)
		UiKit.card(self, r, UiKit.PANEL if i > 0 else Color(0.2, 0.12, 0.05, 0.94), 26 * s, s)
		UiKit.panel(self, Rect2(r.position, Vector2(cw, 58 * s)).grow(-5 * s), Color(row.color, 0.9), 20 * s)
		draw_circle(Vector2(r.position.x + 36 * s, r.position.y + 30 * s), 23 * s, UiKit.INK)
		draw_circle(Vector2(r.position.x + 36 * s, r.position.y + 30 * s), 20 * s, UiKit.CREAM)
		UiKit.portrait(self, Vector2(r.position.x + 36 * s, r.position.y + 32 * s), 12 * s, row.color, row.kind)
		UiKit.text(self, Vector2(r.position.x + 66 * s, r.position.y + 42 * s), row.name, 30 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 700, 0.14)
		var place: String = ["1ST", "2ND", "3RD", "4TH", "5TH", "6TH"][i]
		UiKit.text(self, Vector2(r.position.x, r.position.y + 42 * s), place, 26 * s, UiKit.GOLD if i == 0 else UiKit.CREAM, HORIZONTAL_ALIGNMENT_RIGHT, cw - 18 * s, 700, 0.14)
		var t0 := 0.9 + i * 0.1
		var stats := [["KOs", _count(row.kills, t0)], ["DEATHS", _count(row.deaths, t0)], ["CARDS", _count(row.cards, t0)]]
		if not (row.get("stats", []) as Array).is_empty():
			stats = row.stats              # a mode's own columns (Racing: place, best lap, time)
		for j in 3:
			var sx := r.position.x + cw * (j + 0.5) / 3.0
			var vtxt: String = str(stats[j][1])
			UiKit.num(self, Vector2(sx - 60 * s, r.position.y + 106 * s), vtxt, (44.0 if vtxt.length() <= 4 else 26.0) * s, UiKit.GOLD if j == 0 else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 120 * s, 0.14)
			UiKit.text(self, Vector2(sx - 60 * s, r.position.y + 132 * s), stats[j][0], 16 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 120 * s, 600, 0.0)

	# Awards down the right side, one after another.
	for k in _awards.size():
		var aw: Array = _awards[k]
		var t1 := 2.2 + k * 0.45
		var sl := UiKit.back_out(clampf((_t - t1) / 0.45, 0.0, 1.0))
		if sl <= 0.0:
			continue
		var row2: Dictionary = rows[aw[3]]
		var ar := Rect2(w - 420 * s + (1.0 - sl) * 480 * s, 250 * s + k * 104 * s, 390 * s, 88 * s)
		UiKit.card(self, ar, UiKit.PANEL, 24 * s, s)
		var ic := ar.position + Vector2(46 * s, 44 * s)
		draw_circle(ic, 32 * s, UiKit.INK)
		draw_circle(ic, 29 * s, UiKit.GOLD)
		UiKit.icon(self, aw[2], ic, 17 * s, UiKit.INK)
		UiKit.text(self, ar.position + Vector2(90 * s, 38 * s), aw[0], 30 * s, UiKit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, -1, 700, 0.14)
		UiKit.portrait(self, ar.position + Vector2(ar.size.x - 34 * s, 30 * s), 13 * s, row2.color, row2.kind)
		var line: String = "%s  -  %s" % [row2.name, aw[1] % int(_count(aw[4], t1 + 0.2))]
		UiKit.text(self, ar.position + Vector2(90 * s, 72 * s), line, 20 * s, row2.color.lerp(Color.WHITE, 0.5), HORIZONTAL_ALIGNMENT_LEFT, ar.size.x - 100 * s, 600, 0.12)
	if _t > 2.0:
		var pad: bool = not Input.get_connected_joypads().is_empty()
		var label := "CONTINUE"
		var key := "A" if pad else "ENTER"
		var tw := UiKit.text_width(label, 30 * s) + UiKit.text_width(key, 24 * s) + 60 * s
		var x := (w - tw) * 0.5
		var y := h - 30 * s
		x += UiKit.prompt(self, Vector2(x, y), key, 30 * s) + 14 * s
		UiKit.text(self, Vector2(x, y), label, 30 * s, Color(1, 1, 1, 0.75 + 0.25 * sin(_t * 5.0)))
