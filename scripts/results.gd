extends Control
## Victory screen shown by game.gd after the match world has been freed:
## a 3D podium (stage.gd) with the top three, confetti, and a results table.
##
## `rows` is a snapshot, best first: [{name, color, kind, kills, deaths, cards}].
## Emits done() when someone presses a confirm button (or after a timeout).

signal done

const Stage = preload("res://scripts/stage.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Fx = preload("res://scripts/fx.gd")

var rows: Array = []
var _stage
var _t := 0.0
var _finished := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage = Stage.new()
	add_child(_stage)
	_stage.build(Vector3(0, 3.3, 12.5), Vector3(0, 2.1, 0), 34.0)

	var spots := [
		[Vector3(0, 0, 0), 1.7], [Vector3(-2.3, 0, 0.2), 1.15], [Vector3(2.3, 0, 0.2), 0.8],
		[Vector3(-4.7, 0, 0.9), 0.25], [Vector3(4.7, 0, 0.9), 0.25], [Vector3(-6.6, 0, 1.6), 0.25],
	]
	for i in mini(rows.size(), spots.size()):
		var row: Dictionary = rows[i]
		var top: float = _stage.add_podium(spots[i][0], spots[i][1], row.color)
		var c = _stage.add_character(row.kind, row.color, Vector3(spots[i][0].x, top, spots[i][0].z))
		if i == 0:
			c.emote = "cheer"
			_add_crown(c)
		elif i >= 3:
			c.emote = "sad"
	Fx.confetti_rain(_stage, Vector3(0, 9.0, 0), Vector3(8.0, 0.5, 2.0))
	Fx.confetti(_stage, Vector3(-3, 1.5, 2), 60, 9.0, 2.2)
	Fx.confetti(_stage, Vector3(3, 1.5, 2), 60, 9.0, 2.2)
	Sfx.play("win", -2.0)


func _add_crown(c) -> void:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.8, 0.2)
	gold.metallic = 0.6
	gold.roughness = 0.25
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.7, 0.1)
	gold.emission_energy_multiplier = 0.35
	var crown := Node3D.new()
	crown.position = Vector3(0, 0.42, 0)
	crown.rotation.z = 0.12
	c.head.add_child(crown)
	var band := CylinderMesh.new()
	band.top_radius = 0.2
	band.bottom_radius = 0.18
	band.height = 0.1
	var bi := MeshInstance3D.new()
	bi.mesh = band
	bi.material_override = gold
	crown.add_child(bi)
	for i in 5:
		var a := TAU * i / 5.0
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 0.06
		spike.height = 0.16
		var si := MeshInstance3D.new()
		si.mesh = spike
		si.material_override = gold
		si.position = Vector3(cos(a) * 0.17, 0.12, sin(a) * 0.17)
		crown.add_child(si)


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
		go = go or Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE)
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
	var title := "%s WINS!" % win.name
	var bw := UiKit.text_width(title, 110 * s) + 140 * s
	UiKit.card(self, Rect2(-bw * 0.5, -78 * s, bw, 150 * s), win.color.darkened(0.15), 40 * s, s * 1.6)
	UiKit.panel(self, Rect2(-bw * 0.5 + 10 * s, -68 * s, bw - 20 * s, 50 * s), Color(1, 1, 1, 0.16), 30 * s)
	UiKit.text(self, Vector2(-bw * 0.5, 36 * s), title, 110 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bw, 700, 0.14)
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
		UiKit.card(self, r, UiKit.PANEL if i > 0 else Color(0.36, 0.26, 0.12, 0.92), 26 * s, s)
		UiKit.panel(self, Rect2(r.position, Vector2(cw, 58 * s)).grow(-5 * s), Color(row.color, 0.9), 20 * s)
		draw_circle(Vector2(r.position.x + 36 * s, r.position.y + 30 * s), 23 * s, UiKit.INK)
		draw_circle(Vector2(r.position.x + 36 * s, r.position.y + 30 * s), 20 * s, UiKit.CREAM)
		UiKit.portrait(self, Vector2(r.position.x + 36 * s, r.position.y + 32 * s), 12 * s, row.color, row.kind)
		UiKit.text(self, Vector2(r.position.x + 66 * s, r.position.y + 42 * s), row.name, 30 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 700, 0.14)
		var place: String = ["1ST", "2ND", "3RD", "4TH", "5TH", "6TH"][i]
		UiKit.text(self, Vector2(r.position.x, r.position.y + 42 * s), place, 26 * s, UiKit.GOLD if i == 0 else UiKit.CREAM, HORIZONTAL_ALIGNMENT_RIGHT, cw - 18 * s, 700, 0.14)
		var stats := [["KOs", str(row.kills)], ["DEATHS", str(row.deaths)], ["CARDS", str(row.cards)]]
		for j in 3:
			var sx := r.position.x + cw * (j + 0.5) / 3.0
			UiKit.text(self, Vector2(sx - 60 * s, r.position.y + 104 * s), stats[j][1], 38 * s, UiKit.GOLD if j == 0 else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 120 * s, 700, 0.14)
			UiKit.text(self, Vector2(sx - 60 * s, r.position.y + 132 * s), stats[j][0], 16 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 120 * s, 600, 0.0)

	if _t > 2.0:
		var pad: bool = not Input.get_connected_joypads().is_empty()
		var label := "CONTINUE"
		var key := "A" if pad else "ENTER"
		var tw := UiKit.text_width(label, 30 * s) + UiKit.text_width(key, 24 * s) + 60 * s
		var x := (w - tw) * 0.5
		var y := h - 30 * s
		x += UiKit.prompt(self, Vector2(x, y), key, 30 * s) + 14 * s
		UiKit.text(self, Vector2(x, y), label, 30 * s, Color(1, 1, 1, 0.75 + 0.25 * sin(_t * 5.0)))
