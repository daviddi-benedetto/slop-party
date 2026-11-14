extends Control
## Per-viewport HUD. One instance lives inside each player's SubViewport (on a
## CanvasLayer) and is drawn entirely with immediate-mode _draw() calls, scaled
## from the viewport height so it works at any splitscreen cell size.
##
## With `player == null` it is a spectator cell and only shows the scoreboard.
## The powerup card picker is drawn here; the input for it is in player.gd.

const Cards = preload("res://scripts/cards.gd")

var player = null
var game
var font: Font
var s := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _text(pos: Vector2, text: String, px: float, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var fs := maxi(8, int(px * s))
	draw_string_outline(font, pos, text, align, width, fs, maxi(2, fs / 5), Color(0, 0, 0, 0.8))
	draw_string(font, pos, text, align, width, fs, color)


func _draw() -> void:
	var w := size.x
	var h := size.y
	s = clampf(h / 540.0, 0.55, 2.5)
	if player == null:
		_text(Vector2(0, 40 * s), "FRAGDECK", 26, Color(1, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, w)
		_draw_scoreboard(Vector2(w * 0.5 - 150 * s, 70 * s), 300 * s)
		return

	if player.alive:
		_draw_alive(w, h)
	else:
		_draw_dead(w, h)

	# Name + score, always visible.
	_text(Vector2(14 * s, 28 * s), player.pname, 20, player.color.lerp(Color.WHITE, 0.25))
	_text(Vector2(0, 28 * s), "%d / %d" % [player.kills, game.kill_target], 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)
	var lead = game.leader()
	if lead != null and lead != player:
		_text(Vector2(0, 46 * s), "%s leads with %d" % [lead.pname, lead.kills], 12, lead.color.lerp(Color.WHITE, 0.4), HORIZONTAL_ALIGNMENT_CENTER, w)
	elif lead == player and player.kills > 0:
		_text(Vector2(0, 46 * s), "YOU LEAD", 12, Color(1, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, w)

	# Kill feed.
	var fy := 26 * s
	for entry in game.feed:
		var age: float = game.time - entry.t
		if age > 6.0:
			continue
		var c: Color = entry.color
		c.a = clampf(6.0 - age, 0.0, 1.0)
		_text(Vector2(0, fy), entry.text, 13, c, HORIZONTAL_ALIGNMENT_RIGHT, w - 12 * s)
		fy += 17 * s

	# Cards owned.
	var cy := 64 * s
	var counts := {}
	for n in player.cards:
		counts[n] = counts.get(n, 0) + 1
	for n in counts:
		var label: String = n if counts[n] == 1 else "%s x%d" % [n, counts[n]]
		_text(Vector2(14 * s, cy), label, 11, Color(0.9, 0.9, 0.9, 0.75))
		cy += 14 * s
		if cy > h * 0.7:
			break

	if player.kill_flash > 0.0:
		var kc := Color(1, 0.85, 0.3, clampf(player.kill_flash * 2.0, 0.0, 1.0))
		_text(Vector2(0, h * 0.34), "FRAG!", 30, kc, HORIZONTAL_ALIGNMENT_CENTER, w)

	if game.match_over and game.winner != null:
		draw_rect(Rect2(0, h * 0.3, w, h * 0.26), Color(0, 0, 0, 0.6))
		var won: bool = game.winner == player
		_text(Vector2(0, h * 0.42), "VICTORY!" if won else "%s WINS" % game.winner.pname, 44,
			Color(1, 0.85, 0.3) if won else game.winner.color.lerp(Color.WHITE, 0.3), HORIZONTAL_ALIGNMENT_CENTER, w)
		_text(Vector2(0, h * 0.5), "%d kills / %d deaths" % [player.kills, player.deaths], 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_alive(w: float, h: float) -> void:
	var c := Vector2(w, h) * 0.5
	if player.hurt_flash > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.9, 0.05, 0.05, 0.3 * player.hurt_flash))
	if player.slow_left > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.3, 0.6, 1.0, 0.12))
	if player.poison_left > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.3, 0.9, 0.2, 0.1))

	# Crosshair (spreads with recoil) and hit marker.
	var gap: float = (5.0 + player.recoil * 5.0) * s
	var ln := 7.0 * s
	var col := Color(1, 1, 1, 0.9)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * gap, c + d * (gap + ln), Color(0, 0, 0, 0.6), 4.0 * s)
		draw_line(c + d * gap, c + d * (gap + ln), col, 2.0 * s)
	draw_circle(c, 1.5 * s, col)
	if player.hit_marker > 0.0:
		var hc := Color(1, 0.3, 0.2, player.hit_marker)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 6 * s, c + d * 13 * s, hc, 3.0 * s)

	# Health.
	var bw := 190.0 * s
	var bh := 18.0 * s
	var bx := 14.0 * s
	var by := h - 14.0 * s - bh
	var frac: float = clampf(player.health / player.stats.max_health, 0.0, 1.0)
	draw_rect(Rect2(bx - 2, by - 2, bw + 4, bh + 4), Color(0, 0, 0, 0.65))
	draw_rect(Rect2(bx, by, bw * frac, bh), Color(0.9, 0.2, 0.15).lerp(Color(0.3, 0.85, 0.3), frac))
	_text(Vector2(bx + 6 * s, by + bh - 4 * s), "%d" % ceili(player.health), 14, Color.WHITE)
	if player.spawn_protect > 0.0:
		_text(Vector2(bx, by - 8 * s), "PROTECTED", 12, Color(0.6, 0.9, 1.0))

	# Ammo / reload.
	var ax := w - 14.0 * s
	if player.reload_left > 0.0:
		var rf: float = 1.0 - player.reload_left / player.stats.reload_time
		_text(Vector2(0, h - 34 * s), "RELOADING", 14, Color(1, 0.8, 0.3), HORIZONTAL_ALIGNMENT_RIGHT, ax)
		draw_rect(Rect2(ax - 120 * s, h - 28 * s, 120 * s, 6 * s), Color(0, 0, 0, 0.65))
		draw_rect(Rect2(ax - 120 * s, h - 28 * s, 120 * s * rf, 6 * s), Color(1, 0.8, 0.3))
	else:
		_text(Vector2(0, h - 26 * s), "%d / %d" % [player.ammo, player.stats.mag_size], 24, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, ax)
	# Dash meter.
	var df: float = 1.0 - clampf(player.dash_cd / player.stats.dash_cooldown, 0.0, 1.0)
	draw_rect(Rect2(ax - 120 * s, h - 16 * s, 120 * s, 5 * s), Color(0, 0, 0, 0.65))
	draw_rect(Rect2(ax - 120 * s, h - 16 * s, 120 * s * df, 5 * s), Color(0.3, 0.8, 1.0) if df >= 1.0 else Color(0.4, 0.5, 0.6))


func _draw_dead(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.03, 0.06, 0.72))
	if game.match_over:
		return
	var title := "FRAGGED BY %s" % player.killer_name if player.killer_name != "" else "YOU DIED"
	_text(Vector2(0, h * 0.16), title, 24, Color(1, 0.4, 0.35), HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(0, h * 0.16 + 26 * s), "CHOOSE A POWERUP", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)

	var n: int = player.card_choices.size()
	if n == 0:
		return
	var cw := minf(w * 0.28, 210.0 * s)
	var ch := cw * 1.25
	var gap := cw * 0.08
	var x0 := (w - (cw * n + gap * (n - 1))) * 0.5
	var y0 := h * 0.55 - ch * 0.5
	for i in n:
		var card: Dictionary = player.card_choices[i]
		var selected: bool = i == player.card_sel
		var rc: Color = Cards.RARITY_COLORS[card.rarity]
		var r := Rect2(x0 + i * (cw + gap), y0 - (10.0 * s if selected else 0.0), cw, ch)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.13, 0.14, 0.19) if selected else Color(0.08, 0.09, 0.12)
		sb.border_color = Color.WHITE if selected else rc.darkened(0.3)
		sb.set_border_width_all(int((4.0 if selected else 2.0) * s))
		sb.set_corner_radius_all(int(9 * s))
		draw_style_box(sb, r)
		var band := Rect2(r.position + Vector2(6 * s, 6 * s), Vector2(cw - 12 * s, 20 * s))
		draw_rect(band, rc if selected else rc.darkened(0.35))
		var dim := 1.0 if selected else 0.6
		_text(band.position + Vector2(0, 15 * s), Cards.RARITY_NAMES[card.rarity], 11, Color(0, 0, 0, 0.0).lerp(Color.WHITE, dim), HORIZONTAL_ALIGNMENT_CENTER, band.size.x)
		_text(r.position + Vector2(0, 58 * s), card.name, 17, Color(1, 1, 1, dim), HORIZONTAL_ALIGNMENT_CENTER, cw)
		var fs := maxi(8, int(12 * s))
		draw_multiline_string(font, r.position + Vector2(8 * s, 86 * s), card.desc, HORIZONTAL_ALIGNMENT_CENTER, cw - 16 * s, fs, -1, Color(0.85, 0.88, 0.95, dim))
	if player.respawn_pending:
		_text(Vector2(0, y0 + ch + 34 * s), "Respawning...", 14, Color(0.7, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER, w)
	elif not player.is_bot:
		var hint := "A / D to choose   -   SPACE to confirm" if player.brain.device < 0 else "LEFT / RIGHT to choose   -   (A) to confirm"
		_text(Vector2(0, y0 + ch + 34 * s), hint, 13, Color(0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_scoreboard(pos: Vector2, width: float) -> void:
	var y := pos.y
	for p in game.ranked():
		draw_rect(Rect2(pos.x, y, width, 24 * s), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(pos.x, y, 6 * s, 24 * s), p.color)
		_text(Vector2(pos.x + 14 * s, y + 18 * s), p.pname, 15, Color.WHITE)
		_text(Vector2(pos.x, y + 18 * s), "%d" % p.kills, 15, Color(1, 0.85, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, width - 10 * s)
		y += 27 * s
