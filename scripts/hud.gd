extends Control
## Per-viewport HUD. One instance lives inside each player's SubViewport (on a
## CanvasLayer) and is drawn entirely with immediate-mode _draw() calls via
## ui_kit.gd, scaled from the viewport height (`s`) so it works at any
## splitscreen cell size.
##
## With `player == null` it is a spectator cell and only shows the scoreboard.
## The powerup card picker is drawn here (animated from player.dead_time /
## player.pick_time); the input for it is handled in player.gd.
##
## A child ColorRect with a screen-reading shader blurs and tints the 3D view
## behind the card picker.
##
## PERFORMANCE: immediate-mode drawing in GDScript is the most expensive thing
## in the game when six HUDs redraw every frame. So the HUD is split into
## layers (child Controls). Each layer has a cheap "signature" of the data it
## shows and is only redrawn when that signature changes:
##   strip  - scores along the top          feed   - kill feed
##   status - portrait, health, owned cards  ammo  - ammo, reload, dash
## Only the crosshair/vignette/banners/card picker (this node) draw per frame.

const Cards = preload("res://scripts/cards.gd")
const UiKit = preload("res://scripts/ui_kit.gd")

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, amount * 3.2).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(g), amount * 0.5);
	COLOR = vec4(mix(c, vec3(0.16, 0.1, 0.26), amount * 0.55), 1.0);
}
"""

var player = null
var game
var s := 1.0
var _blur: ColorRect
var _blur_amount := 0.0
var _layers: Array = []      # [control, signature_callable, last_signature]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_blur = ColorRect.new()
	_blur.material = mat
	_blur.show_behind_parent = true
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur.visible = false
	add_child(_blur)
	if player != null:
		_add_layer(_draw_status, _sig_status)
		_add_layer(_draw_ammo, _sig_ammo)
		_add_layer(_draw_score_strip, _sig_strip)
		_add_layer(_draw_feed, _sig_feed)


func _add_layer(draw_fn: Callable, sig_fn: Callable) -> void:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	c.draw.connect(draw_fn.bind(c))
	_layers.append([c, sig_fn, null])


func _process(delta: float) -> void:
	var want := 0.0
	if player != null and not player.alive and not game.match_over:
		want = 1.0
	_blur_amount = move_toward(_blur_amount, want, delta * 3.5)
	_blur.visible = _blur_amount > 0.01
	if _blur.visible:
		_blur.material.set_shader_parameter("amount", _blur_amount)
	s = clampf(size.y / 540.0, 0.55, 2.5)
	for l in _layers:
		var sig = l[1].call()
		if sig != l[2]:
			l[2] = sig
			l[0].queue_redraw()
	queue_redraw()


func _sig_status():
	if not player.alive:
		return [0]
	return [size, ceili(player.health), roundi(player.health_ghost), player.stats.max_health, player.card_icons.size(),
		int(game.time * 10.0) if player.spawn_protect > 0.0 else -1]


func _sig_ammo():
	if not player.alive:
		return [0]
	var reloading: bool = player.reload_left > 0.0
	return [size, player.ammo, player.stats.mag_size,
		int(player.reload_left / player.stats.reload_time * 50.0) if reloading else -1,
		int(player.dash_cd / player.stats.dash_cooldown * 40.0)]


func _sig_strip():
	var sig: Array = [size, game.kill_target]
	for p in game.players:
		sig.append(p.kills)
		sig.append(p.alive)
	return sig


func _sig_feed():
	var sig: Array = [size, game.feed.size()]
	for entry in game.feed:
		var age: float = game.time - entry.t
		sig.append(entry.t)
		# Sliding in or fading out: animate at 30 Hz. Otherwise static.
		if age < 0.35 or (age > 4.4 and age < 5.6):
			sig.append(int(game.time * 30.0))
	return sig


func _t(pos: Vector2, text: String, px: float, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, weight := 700, ci: CanvasItem = null) -> void:
	UiKit.text(ci if ci != null else self, pos, text, px * s, color, align, width, weight)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if player == null:
		_draw_spectator(w, h)
		return
	if player.alive:
		_draw_alive(w, h)
	else:
		_draw_dead(w, h)
	_draw_banners(w, h)


# --------------------------------------------------------------------------
# Alive
# --------------------------------------------------------------------------

func _draw_alive(w: float, h: float) -> void:
	var c := Vector2(w, h) * 0.5
	var frac: float = clampf(player.health / player.stats.max_health, 0.0, 1.0)

	# Screen-edge feedback.
	draw_texture_rect(UiKit.vignette(), Rect2(0, 0, w, h), false, Color(0.1, 0.05, 0.2, 0.22))
	var danger := 0.0
	if frac < 0.35:
		danger = (0.35 - frac) / 0.35 * (0.45 + 0.2 * sin(game.time * 7.0))
	danger = maxf(danger, player.hurt_flash * 0.5)
	if danger > 0.0:
		draw_texture_rect(UiKit.vignette(), Rect2(0, 0, w, h), false, Color(1.0, 0.1, 0.2, danger))
	if player.slow_left > 0.0:
		draw_texture_rect(UiKit.vignette(), Rect2(0, 0, w, h), false, Color(0.4, 0.75, 1.0, 0.5))
	if player.poison_left > 0.0:
		draw_texture_rect(UiKit.vignette(), Rect2(0, 0, w, h), false, Color(0.4, 1.0, 0.3, 0.4))

	# Where damage came from.
	for d in player.damage_dirs:
		var to: Vector3 = d[0] - player.global_position
		var local := Basis(Vector3.UP, player.yaw).inverse() * to
		var a := atan2(local.x, -local.z) - PI / 2
		var alpha := clampf(d[1], 0.0, 1.0)
		draw_arc(c, 74 * s, a - 0.3, a + 0.3, 10, Color(UiKit.INK, alpha), 9 * s)
		draw_arc(c, 74 * s, a - 0.27, a + 0.27, 10, Color(1.0, 0.3, 0.35, alpha), 5 * s)

	# Crosshair (spreads with recoil).
	var gap: float = (6.0 + player.recoil * 7.0) * s
	var ln := 7.0 * s
	for d2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d2 * (gap - s), c + d2 * (gap + ln + s), UiKit.INK, 5.0 * s)
	for d3 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d3 * gap, c + d3 * (gap + ln), Color.WHITE, 2.4 * s)
	draw_circle(c, 3.2 * s, UiKit.INK)
	draw_circle(c, 1.8 * s, Color.WHITE)
	if player.hit_marker > 0.0:
		var hm: float = player.hit_marker
		var hc := UiKit.GOLD if player.hit_crit else Color.WHITE
		hc.a = clampf(hm * 2.0, 0.0, 1.0)
		var r0 := (9.0 + (1.0 - hm) * 5.0) * s
		for d4 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn: Vector2 = d4.normalized()
			draw_line(c + dn * (r0 - s), c + dn * (r0 + 10 * s), Color(UiKit.INK, hc.a), 6.0 * s)
			draw_line(c + dn * r0, c + dn * (r0 + 9 * s), hc, 3.0 * s)


func _draw_status(ci: Control) -> void:
	if not player.alive:
		return
	var h := size.y
	var w := size.x
	var frac: float = clampf(player.health / player.stats.max_health, 0.0, 1.0)
	# --- bottom left: portrait, name, health, owned cards ---
	var px := 40.0 * s
	var py := h - 42.0 * s
	ci.draw_circle(Vector2(px, py + 3 * s), 29 * s, Color(0.08, 0.05, 0.12, 0.4))
	ci.draw_circle(Vector2(px, py), 29 * s, UiKit.INK)
	ci.draw_circle(Vector2(px, py), 26 * s, UiKit.CREAM)
	UiKit.portrait(ci, Vector2(px, py + 3 * s), 16 * s, player.color, player.kind)
	var bar := Rect2(78 * s, h - 44 * s, 176 * s, 20 * s)
	var fill := Color(1.0, 0.32, 0.36).lerp(Color(0.36, 0.86, 0.42), clampf(frac * 1.4 - 0.2, 0.0, 1.0))
	UiKit.bar(ci, bar, frac, fill, s, clampf(player.health_ghost / player.stats.max_health, 0.0, 1.0))
	UiKit.icon(ci, "heart", bar.position + Vector2(13 * s, 10 * s), 7 * s, Color.WHITE)
	_t(bar.position + Vector2(26 * s, 16 * s), "%d" % ceili(player.health), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, ci)
	_t(Vector2(78 * s, h - 52 * s), player.pname, 14, player.color.lerp(Color.WHITE, 0.4), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, ci)
	if player.spawn_protect > 0.0:
		var sx := 78 * s + UiKit.text_width(player.pname, 14 * s) + 16 * s
		UiKit.icon(ci, "shield", Vector2(sx, h - 57 * s), 7 * s, Color(0.5, 0.85, 1.0, 0.6 + 0.4 * sin(game.time * 12.0)))
	# Owned cards as little rarity-coloured tiles.
	var tile := 19.0 * s
	var max_tiles := int((w * 0.42) / (tile + 4 * s))
	var total: int = player.card_icons.size()
	var first := maxi(0, total - max_tiles)
	for i in range(first, total):
		var info: Array = player.card_icons[i]
		var r := Rect2(78 * s + (i - first) * (tile + 4 * s), h - 92 * s, tile, tile)
		UiKit.panel(ci, r, Cards.RARITY_COLORS[info[1]], 5 * s, UiKit.INK, 2 * s)
		UiKit.icon(ci, info[0], r.get_center(), tile * 0.3, Color.WHITE)
	if first > 0:
		_t(Vector2(78 * s + (total - first) * (tile + 4 * s), h - 77 * s), "+%d" % first, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, ci)


func _draw_ammo(ci: Control) -> void:
	if not player.alive:
		return
	var w := size.x
	var h := size.y
	# --- bottom right: ammo, reload, dash ---
	var ax := w - 20.0 * s
	if player.reload_left > 0.0:
		var rf: float = 1.0 - player.reload_left / player.stats.reload_time
		_t(Vector2(0, h - 44 * s), "RELOADING", 15, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, ax, 700, ci)
		UiKit.bar(ci, Rect2(ax - 130 * s, h - 36 * s, 130 * s, 12 * s), rf, UiKit.GOLD, s)
	else:
		var mag := "/%d" % player.stats.mag_size
		var mw := UiKit.text_width(mag, 18 * s)
		_t(Vector2(ax - mw, h - 24 * s), mag, 18, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, ci)
		var low: bool = player.ammo <= maxi(1, player.stats.mag_size / 4)
		_t(Vector2(0, h - 24 * s), "%d" % player.ammo, 42, Color(1.0, 0.45, 0.4) if low else Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, ax - mw - 4 * s, 700, ci)
		# Bullet pips.
		var n: int = player.stats.mag_size
		if n <= 20:
			var pw := 6.0 * s
			var pg := 3.0 * s
			var x0 := ax - n * (pw + pg) + pg
			for i in n:
				var pr := Rect2(x0 + i * (pw + pg), h - 78 * s, pw, 13 * s)
				UiKit.panel(ci, pr.grow(1.5 * s), UiKit.INK, 4 * s)
				UiKit.panel(ci, pr, UiKit.GOLD if i < player.ammo else Color(0.36, 0.3, 0.46), 3 * s)
	# Dash gauge.
	var dc := Vector2(ax - 168 * s, h - 34 * s)
	var df: float = 1.0 - clampf(player.dash_cd / player.stats.dash_cooldown, 0.0, 1.0)
	var ready: bool = df >= 1.0
	var dr := 17.0 * s
	ci.draw_circle(dc + Vector2(0, 3 * s), dr + 3 * s, Color(0.08, 0.05, 0.12, 0.4))
	ci.draw_circle(dc, dr + 3 * s, UiKit.INK)
	ci.draw_circle(dc, dr, Color(0.3, 0.85, 1.0) if ready else Color(0.32, 0.27, 0.42))
	if not ready:
		ci.draw_arc(dc, dr - 3 * s, -PI / 2, -PI / 2 + TAU * df, 24, Color(0.3, 0.85, 1.0), 5 * s)
	UiKit.icon(ci, "bolt", dc, 9 * s, Color.WHITE if ready else Color(1, 1, 1, 0.5))


# --------------------------------------------------------------------------
# Dead: the card picker
# --------------------------------------------------------------------------

func _draw_dead(w: float, h: float) -> void:
	if game.match_over:
		return
	var dt: float = player.dead_time
	var a := clampf(dt * 3.0, 0.0, 1.0)

	# Header: who got you.
	var head_y := h * 0.15 - (1.0 - UiKit.back_out(a)) * 60 * s
	if player.killer != null and is_instance_valid(player.killer):
		var label := "FRAGGED BY"
		var lw := UiKit.text_width(label, 20 * s)
		var nw := UiKit.text_width(player.killer.pname, 20 * s)
		var total := lw + 46 * s + nw
		var x := (w - total) * 0.5
		UiKit.card(self, Rect2(x - 16 * s, head_y - 26 * s, total + 32 * s, 38 * s), Color(UiKit.PANEL, a), 19 * s, s)
		_t(Vector2(x, head_y), label, 20, Color(1.0, 0.5, 0.5, a))
		UiKit.portrait(self, Vector2(x + lw + 23 * s, head_y - 5 * s), 10 * s, Color(player.killer.color, a), player.killer.kind)
		_t(Vector2(x + lw + 46 * s, head_y), player.killer.pname, 20, Color(player.killer.color.lerp(Color.WHITE, 0.4), a))
	else:
		_t(Vector2(0, head_y), "OOPS!", 26, Color(1.0, 0.5, 0.5, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	_t(Vector2(0, h * 0.15 + 38 * s), "PICK A POWERUP", 24, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, w)

	var n: int = player.card_choices.size()
	if n == 0:
		return
	var cw := minf(w * 0.27, 176.0 * s)
	var ch := cw * 1.36
	var gap := cw * 0.1
	var x0 := (w - (cw * n + gap * (n - 1))) * 0.5 + cw * 0.5
	var cy := h * 0.58
	var picked: bool = player.respawn_pending
	# Draw the selected card last so it sits on top.
	var order: Array = []
	for i in n:
		if i != player.card_sel:
			order.append(i)
	order.append(player.card_sel)
	for i in order:
		var selected: bool = i == player.card_sel
		var deal := UiKit.back_out(clampf((dt - 0.2 - i * 0.09) / 0.4, 0.0, 1.0))
		var pos: Vector2 = Vector2(x0 + i * (cw + gap), cy + (1.0 - deal) * h * 0.75)
		var rot: float = (i - (n - 1) * 0.5) * 0.05
		var scl := 1.0
		var alpha := 1.0
		if selected:
			rot = sin(game.time * 2.4) * 0.025
			scl = 1.1 + sin(game.time * 4.0) * 0.012
			pos.y -= 14 * s
		if picked:
			var pt: float = clampf(player.pick_time / 0.45, 0.0, 1.0)
			if selected:
				scl = 1.1 + UiKit.back_out(pt) * 0.22
				pos.y -= pt * 20 * s
				alpha = clampf(2.5 - pt * 2.5, 0.0, 1.0) if pt > 0.6 else 1.0
			else:
				pos.y += pt * pt * h * 0.7
				rot += pt * 0.5 * signf(i - player.card_sel)
		_draw_card(player.card_choices[i], pos, Vector2(cw, ch), rot, scl, selected, alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Prompts.
	if not picked and not player.is_bot and dt > 0.85:
		var py := cy + ch * 0.5 + 44 * s
		var pad: bool = player.brain.device >= 0
		var l1 := "D-PAD" if pad else "A / D"
		var l2 := "A" if pad else "SPACE"
		var tw := UiKit.text_width(l1, 13 * s) + UiKit.text_width(l2, 13 * s) + UiKit.text_width("CHOOSE", 15 * s) + UiKit.text_width("PICK", 15 * s) + 90 * s
		var x := (w - tw) * 0.5
		x += UiKit.prompt(self, Vector2(x, py), l1, 16 * s) + 8 * s
		_t(Vector2(x, py), "CHOOSE", 15, Color.WHITE)
		x += UiKit.text_width("CHOOSE", 15 * s) + 26 * s
		x += UiKit.prompt(self, Vector2(x, py), l2, 16 * s) + 8 * s
		_t(Vector2(x, py), "PICK", 15, Color.WHITE)


func _draw_card(card: Dictionary, centre: Vector2, sz: Vector2, rot: float, scl: float, selected: bool, alpha: float) -> void:
	draw_set_transform(centre, rot, Vector2(scl, scl))
	var rc: Color = Cards.RARITY_COLORS[card.rarity]
	var r := Rect2(-sz * 0.5, sz)
	if selected:
		var glow := 0.55 + 0.35 * sin(game.time * 6.0)
		UiKit.panel(self, r.grow(9 * s), Color(rc.lerp(Color.WHITE, 0.3), glow * 0.55 * alpha), 20 * s)
		UiKit.panel(self, r.grow(5 * s), Color(1, 1, 1, alpha), 17 * s)
	var body := UiKit.CREAM if selected else UiKit.CREAM.darkened(0.22)
	UiKit.panel(self, r, Color(body, alpha), 13 * s, Color(UiKit.INK, alpha), 3 * s, 6 * s)
	# Art band.
	var band := Rect2(r.position + Vector2(7, 7) * s, Vector2(sz.x - 14 * s, sz.y * 0.44))
	UiKit.panel(self, band, Color(rc if selected else rc.darkened(0.2), alpha), 9 * s)
	UiKit.panel(self, Rect2(band.position + Vector2(5, 4) * s, Vector2(band.size.x - 10 * s, band.size.y * 0.3)), Color(1, 1, 1, 0.18 * alpha), 7 * s)
	var ic := band.get_center() + Vector2(0, 2 * s)
	var ir := band.size.y * 0.3
	draw_circle(ic, ir * 1.35, Color(1, 1, 1, 0.25 * alpha))
	UiKit.icon(self, card.icon, ic + Vector2(0, 2.5 * s), ir, Color(UiKit.INK, 0.5 * alpha))
	UiKit.icon(self, card.icon, ic, ir, Color(1, 1, 1, alpha))
	# Rarity tag.
	var tag: String = Cards.RARITY_NAMES[card.rarity]
	var tw := UiKit.text_width(tag, 9 * s) + 14 * s
	var tr := Rect2(Vector2(-tw * 0.5, band.end.y - 8 * s), Vector2(tw, 16 * s))
	UiKit.panel(self, tr, Color(UiKit.INK, alpha), 8 * s)
	draw_string(UiKit.font(700), tr.position + Vector2(0, 12 * s), tag, HORIZONTAL_ALIGNMENT_CENTER, tw, maxi(8, int(9 * s)), Color(rc.lerp(Color.WHITE, 0.3), alpha))
	# Name and description.
	var ink := Color(UiKit.INK, alpha)
	var name_px := 16.0 if card.name.length() < 14 else 13.5
	draw_string(UiKit.font(700), Vector2(r.position.x, band.end.y + 30 * s), card.name, HORIZONTAL_ALIGNMENT_CENTER, sz.x, maxi(8, int(name_px * s)), ink)
	draw_multiline_string(UiKit.font(500), Vector2(r.position.x + 8 * s, band.end.y + 48 * s), card.desc, HORIZONTAL_ALIGNMENT_CENTER, sz.x - 16 * s, maxi(8, int(11.5 * s)), -1, Color(0.32, 0.26, 0.4, alpha))


# --------------------------------------------------------------------------
# Shared pieces
# --------------------------------------------------------------------------

func _draw_score_strip(ci: Control) -> void:
	var w := size.x
	var n: int = game.players.size()
	var chip := 46.0 * s
	var total := n * chip + 10 * s
	var x0 := (w - total) * 0.5
	UiKit.card(ci, Rect2(x0, 6 * s, total, 34 * s), UiKit.PANEL, 17 * s, s)
	var lead = game.leader()
	for i in n:
		var p = game.players[i]
		var cx := x0 + 5 * s + i * chip + 14 * s
		var cy := 23.0 * s
		if p == player:
			UiKit.panel(ci, Rect2(cx - 13 * s, 9 * s, chip - 2 * s, 28 * s), Color(1, 1, 1, 0.2), 14 * s)
		UiKit.portrait(ci, Vector2(cx, cy + 1.5 * s), 8.5 * s, Color(p.color, 1.0 if p.alive else 0.45), p.kind, not p.alive)
		if p == lead and p.kills > 0:
			UiKit.icon(ci, "crown", Vector2(cx, cy - 15 * s), 6 * s, UiKit.INK)
			UiKit.icon(ci, "crown", Vector2(cx, cy - 16 * s), 5 * s, UiKit.GOLD)
		_t(Vector2(cx + 12 * s, cy + 6 * s), "%d" % p.kills, 16, Color.WHITE if p != player else UiKit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, ci)
	_t(Vector2(0, 54 * s), "FIRST TO %d" % game.kill_target, 10, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w, 700, ci)


func _draw_feed(ci: Control) -> void:
	var w := size.x
	var y := 62.0 * s
	for entry in game.feed:
		var age: float = game.time - entry.t
		if age > 5.5:
			continue
		var alpha := clampf(5.5 - age, 0.0, 1.0)
		var slide := (1.0 - UiKit.back_out(clampf(age / 0.3, 0.0, 1.0))) * 120 * s
		var vn: String = entry.victim.pname
		var kn: String = entry.killer.pname if entry.killer != null else ""
		var vw := UiKit.text_width(vn, 12 * s)
		var kw := UiKit.text_width(kn, 12 * s) if kn != "" else 0.0
		var total := vw + kw + (62 * s if kn != "" else 40 * s)
		var x := w - 10 * s - total + slide
		UiKit.panel(ci, Rect2(x, y, total, 22 * s), Color(UiKit.PANEL, 0.85 * alpha), 11 * s, Color(UiKit.INK, alpha), 2 * s)
		var cx := x + 8 * s
		if kn != "":
			_t(Vector2(cx, y + 16 * s), kn, 12, Color(entry.killer.color.lerp(Color.WHITE, 0.45), alpha), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, ci)
			cx += kw + 12 * s
			UiKit.icon(ci, "boom", Vector2(cx, y + 11 * s), 6.5 * s, Color(1.0, 0.75, 0.3, alpha))
			cx += 12 * s
		else:
			UiKit.icon(ci, "skull", Vector2(cx + 6 * s, y + 11 * s), 6 * s, Color(1, 1, 1, alpha))
			cx += 18 * s
		_t(Vector2(cx, y + 16 * s), vn, 12, Color(entry.victim.color.lerp(Color.WHITE, 0.45), alpha), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, ci)
		UiKit.portrait(ci, Vector2(x + total - 13 * s, y + 12 * s), 6 * s, Color(entry.victim.color, alpha), entry.victim.kind, true)
		y += 26 * s


func _big(centre: Vector2, text: String, px: float, color: Color, scl: float, rot := 0.0) -> void:
	draw_set_transform(centre, rot, Vector2(scl, scl))
	UiKit.text(self, Vector2(-size.x * 0.5, px * s * 0.35), text, px * s, color, HORIZONTAL_ALIGNMENT_CENTER, size.x, 700, 0.16)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_banners(w: float, h: float) -> void:
	var c := Vector2(w * 0.5, h * 0.36)
	# Kill confirmation.
	if player.kill_flash > 0.0 and player.alive:
		var t: float = 1.0 - player.kill_flash
		var a := clampf(player.kill_flash * 5.0, 0.0, 1.0)
		var scl := UiKit.back_out(clampf(t * 7.0, 0.0, 1.0))
		_big(Vector2(w * 0.5, h * 0.27), "FRAGGED %s!" % player.kill_name, 24, Color(UiKit.GOLD, a), scl, sin(t * 20.0) * 0.02)
	# 3-2-1.
	if game.countdown > 0.0:
		var num := ceili(game.countdown)
		if num <= 3:
			var f: float = game.countdown - floorf(game.countdown)
			_big(c, str(num), 110, Color(1, 1, 1, clampf(f * 3.0, 0.0, 1.0)), 0.8 + f * 0.6)
		else:
			_big(c, "GET READY", 40, Color.WHITE, 1.0 + sin(game.time * 6.0) * 0.03)
	elif game.go_flash > 0.0:
		var g: float = game.go_flash
		_big(c, "FIGHT!", 84, Color(UiKit.GOLD, clampf(g * 3.0, 0.0, 1.0)), 0.7 + UiKit.back_out(clampf((1.0 - g) * 4.0, 0.0, 1.0)) * 0.5, -0.04)
	# Final whistle.
	if game.match_over:
		var e: float = game.end_real_time
		draw_rect(Rect2(0, 0, w, h), Color(0.1, 0.06, 0.2, clampf(e * 0.6, 0.0, 0.35)))
		_big(c, "GAME!", 100, UiKit.GOLD, UiKit.elastic_out(clampf(e * 1.2, 0.0, 1.0)), -0.05)


func _draw_spectator(w: float, h: float) -> void:
	draw_texture_rect(UiKit.vignette(), Rect2(0, 0, w, h), false, Color(0.1, 0.05, 0.2, 0.35))
	var rows: Array = game.ranked()
	var rw := minf(w * 0.7, 300 * s)
	var x := (w - rw) * 0.5
	var y := h * 0.5 - (rows.size() * 32 * s + 40 * s) * 0.5
	_t(Vector2(0, y), "SCOREBOARD", 22, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, w)
	y += 16 * s
	for i in rows.size():
		var p = rows[i]
		var r := Rect2(x, y, rw, 28 * s)
		UiKit.card(self, r, UiKit.PANEL, 14 * s, s)
		UiKit.portrait(self, Vector2(x + 20 * s, y + 15.5 * s), 8.5 * s, p.color, p.kind)
		_t(Vector2(x + 40 * s, y + 20 * s), p.pname, 15, p.color.lerp(Color.WHITE, 0.45))
		_t(Vector2(x, y + 20 * s), "%d" % p.kills, 16, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, rw - 14 * s)
		y += 32 * s
	_draw_banners_spectator(w, h)


func _draw_banners_spectator(w: float, h: float) -> void:
	if game.match_over:
		_big(Vector2(w * 0.5, h * 0.2), "GAME!", 70, UiKit.GOLD, UiKit.elastic_out(clampf(game.end_real_time * 1.2, 0.0, 1.0)), -0.05)
