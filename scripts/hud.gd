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
const Weapons = preload("res://scripts/weapons.gd")

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, amount * 3.2).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(g), amount * 0.5);
	COLOR = vec4(mix(c, vec3(0.02, 0.025, 0.06), amount * 0.72), 1.0);
}
"""

var player = null
var game
var s := 1.0
## Small cells (5-6 way split, or a small window): fewer words, bigger
## numbers and icons, so the essentials stay readable.
var compact := false
var _last_kill_flash := 0.0
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
	if player != null and (not player.alive or player.picking) and not game.match_over:
		want = 1.0
	_blur_amount = move_toward(_blur_amount, want, delta * 3.5)
	_blur.visible = _blur_amount > 0.01
	if _blur.visible:
		_blur.material.set_shader_parameter("amount", _blur_amount)
	compact = size.y < 420.0
	s = clampf(size.y / 540.0 * (1.2 if compact else 1.0), 0.55, 2.5)
	# Ultrawide option: health, ammo, score and kill feed sit inside a 16:9
	# area in the middle instead of the far corners.
	var pad := 0.0
	if Settings.v("hud_width") == 1 and size.x > size.y * 16.0 / 9.0 * 1.05:
		pad = (size.x - size.y * 16.0 / 9.0) * 0.5
	for l in _layers:
		if l[0].offset_left != pad:
			l[0].offset_left = pad
			l[0].offset_right = -pad
	for l in _layers:
		var sig = l[1].call()
		if sig != l[2]:
			l[2] = sig
			l[0].queue_redraw()
	queue_redraw()


func _sig_status():
	if not player.alive or player.vehicle != null or player.picking:
		return [0]
	var anim := -1
	if player.spawn_protect > 0.0 or player.hurt_flash > 0.0 or player.heal_flash > 0.0 or player.health < player.stats.max_health * 0.3:
		anim = int(game.time * 30.0)      # shaking, pulsing or glowing: animate
	return [size, ceili(player.health), roundi(player.health_ghost), player.stats.max_health, player.card_icons.size(), anim, UiKit.GOLD]


func _sig_ammo():
	if not player.alive or player.vehicle != null or player.picking:
		return [0]
	var reloading: bool = player.reload_left > 0.0
	return [size, player.ammo, player.stats.mag_size, player.weapon, player.shield_ready(), UiKit.GOLD,
		int(player.reload_left / player.stats.reload_time * 50.0) if reloading else -1,
		int(player.dash_cd / player.stats.dash_cooldown * 40.0),
		int(player.block_cd / player.stats.block_cooldown * 40.0)]


func _sig_strip():
	if game.rules != null:
		if game.rules.has_method("strip_sig"):
			return [size, game.rules.strip_sig()]
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
	if player.alive and not player.picking:
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
	if game.rules != null and game.rules.has_method("draw_markers"):
		game.rules.draw_markers(self, s)
	if player.vehicle != null:
		_draw_vehicle(w, h)
		return

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
		draw_arc(c, 74 * s, a - 0.28, a + 0.28, 16, Color(1.0, 0.3, 0.32, 0.85 * alpha), 3.5 * s, true)

	# Crosshair (spreads with recoil).
	var aim: float = player.aim_amount
	var scoped: bool = player.stats.zoom < 0.5 and aim > 0.5
	if scoped:
		# Scope: black out everything outside a big ring.
		var sa := clampf((aim - 0.5) * 2.5, 0.0, 1.0)
		var rr := h * 0.44
		draw_rect(Rect2(0, 0, w * 0.5 - rr, h), Color(0, 0, 0, sa))
		draw_rect(Rect2(w * 0.5 + rr, 0, w * 0.5 - rr, h), Color(0, 0, 0, sa))
		draw_arc(c, rr + h * 0.18, 0, TAU, 64, Color(0, 0, 0, sa), h * 0.36)
		draw_arc(c, rr, 0, TAU, 64, Color(player.color, sa * 0.9), 3 * s)
		draw_line(c - Vector2(rr, 0), c + Vector2(rr, 0), Color(0, 0, 0, sa * 0.8), 1.5 * s)
		draw_line(c - Vector2(0, rr), c + Vector2(0, rr), Color(0, 0, 0, sa * 0.8), 1.5 * s)
	if player.block_left > 0.0 or player.block_flash > 0.0:
		draw_texture_rect(UiKit.vignette(), Rect2(0, 0, w, h), false, Color(player.color.lerp(Color.WHITE, 0.3 + 0.6 * player.block_flash), 0.75))
	# Crosshair: a small circle whose radius is the weapon's current spread.
	var cam := get_viewport().get_camera_3d()
	var vfov := deg_to_rad(cam.fov if cam != null else 70.0)
	var spread: float = (player.stats.spread + (0.02 if player.stats.pellets > 1 else 0.0)) * lerpf(1.0, player.stats.ads_spread, aim)
	spread += player.recoil * 0.01 * player.stats.recoil_kick
	var rad: float = maxf(6.0 * s, tan(spread) / tan(vfov * 0.5) * h * 0.5)
	var lens: bool = player.stats.scope > 1.0 and player.stats.zoom >= 0.5 and aim > 0.6
	if not scoped and not lens:
		var ca: float = 1.0 - (aim if player.stats.red_dot else 0.5 * aim)
		# A thin light-grey ring, no centre dot; a faint dark halo keeps it
		# visible against a bright sky.
		var lw := maxf(1.2, 1.3 * s)
		draw_arc(c, rad, 0.0, TAU, 64, Color(0, 0, 0.02, 0.22 * ca), lw + maxf(1.5, 1.4 * s), true)
		draw_arc(c, rad, 0.0, TAU, 64, Color(0.86, 0.87, 0.9, 0.9 * ca), lw, true)
	# Reload: a ring that fills around the crosshair.
	if player.reload_left > 0.0 and not scoped:
		var rf: float = 1.0 - player.reload_left / player.stats.reload_time
		var rr2 := 24.0 * s
		draw_arc(c, rr2, 0, TAU, 48, Color(0, 0, 0.02, 0.3), 3.0 * s, true)
		draw_arc(c, rr2, -PI / 2, -PI / 2 + TAU * rf, 48, Color(0.92, 0.93, 0.96), 2.0 * s, true)
	elif not player.stats.melee_weapon and player.stats.mag_size > 1 and player.ammo <= maxi(1, player.stats.mag_size / 4) and not scoped:
		# Low ammo: a red tick under the crosshair.
		var la := 0.6 + 0.4 * sin(game.time * 9.0)
		draw_arc(c, 24.0 * s, PI * 0.32, PI * 0.68, 16, Color(1.0, 0.35, 0.35, la), 2.0 * s, true)
	# Jetpack fuel: an arc left of the crosshair.
	if player.stats.jetpack > 0.0:
		var ff: float = clampf(player.jet_fuel / player.stats.jetpack, 0.0, 1.0)
		draw_arc(c, 40 * s, PI * 0.7, PI * 1.3, 32, Color(0, 0, 0.02, 0.3), 3.0 * s, true)
		if ff > 0.01:
			draw_arc(c, 40 * s, PI * 1.3 - PI * 0.6 * ff, PI * 1.3, 32, Color(1.0, 0.65, 0.3, 0.95), 2.0 * s, true)
	if player.kill_flash > 0.7:
		# KO: a big red cross that snaps in and fades.
		var kt: float = (player.kill_flash - 0.7) / 0.3
		var kr := (12.0 + (1.0 - kt) * 8.0) * s
		var kc := Color(1.0, 0.25, 0.25, clampf(kt * 1.5, 0.0, 1.0))
		for d4 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn: Vector2 = d4.normalized()
			draw_line(c + dn * kr, c + dn * (kr + 14 * s), kc, 2.5 * s, true)
	elif player.hit_marker > 0.0:
		var hm: float = player.hit_marker
		var hc := UiKit.GOLD if player.hit_crit else Color.WHITE
		hc.a = clampf(hm * 2.0, 0.0, 1.0)
		var r0 := (9.0 + (1.0 - hm) * 5.0) * s
		for d4 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn: Vector2 = d4.normalized()
			draw_line(c + dn * r0, c + dn * (r0 + 8 * s), hc, 2.0 * s, true)


func _draw_status(ci: Control) -> void:
	if not player.alive or player.vehicle != null or player.picking:
		return
	var h := size.y
	var w := ci.size.x
	var frac: float = clampf(player.health / player.stats.max_health, 0.0, 1.0)
	# --- bottom left: portrait, name, health, owned cards ---
	# Hit: the whole block shakes for a moment.
	var jolt: Vector2 = Vector2(sin(game.time * 71.0), cos(game.time * 63.0)) * player.hurt_flash * player.hurt_flash * 4.0 * s
	var px: float = 40.0 * s + jolt.x
	var py: float = h - 42.0 * s + jolt.y
	ci.draw_circle(Vector2(px, py), 27 * s, Color(0.03, 0.035, 0.06, 0.55))
	ci.draw_arc(Vector2(px, py), 27 * s, 0, TAU, 48, Color(player.color, 0.9), 1.5 * s, true)
	UiKit.portrait(ci, Vector2(px, py + 3 * s), 15 * s, player.color, player.kind)
	var hp_text := "%d" % ceili(player.health)
	# The bar starts after the widest health number, so it never moves.
	var bx: float = 78 * s + UiKit.num_width("100", 30 * s) + 12 * s
	var bar := Rect2(bx + jolt.x, h - 38 * s + jolt.y, 150 * s, 9 * s)
	var low: bool = frac < 0.3
	var fill := Color(1.0, 0.32, 0.36).lerp(Color(0.36, 0.86, 0.42), clampf(frac * 1.4 - 0.2, 0.0, 1.0))
	if low:
		# Near death the bar pulses and glows red.
		var pulse := 0.5 + 0.5 * sin(game.time * 8.0)
		UiKit.panel(ci, bar.grow((3.0 + 2.0 * pulse) * s), Color(1.0, 0.2, 0.25, 0.2 + 0.25 * pulse), 8 * s)
		fill = fill.lerp(Color(1.0, 0.75, 0.75), pulse * 0.35)
	if player.heal_flash > 0.0:
		UiKit.panel(ci, bar.grow(5.0 * s * player.heal_flash), Color(0.4, 1.0, 0.55, 0.4 * player.heal_flash), 8 * s)
	UiKit.bar(ci, bar, frac, fill, s, clampf(player.health_ghost / player.stats.max_health, 0.0, 1.0))
	# Chunks: a hairline gap every 25 health.
	var chunks: int = int(player.stats.max_health / 25.0)
	for i in range(1, chunks):
		var nx: float = bar.position.x + bar.size.x * (i * 25.0 / player.stats.max_health)
		ci.draw_line(Vector2(nx, bar.position.y), Vector2(nx, bar.end.y), Color(0.02, 0.025, 0.05, 0.7), maxf(1.0, 1.5 * s))
	# Health number to the left of the bar.
	UiKit.num(ci, Vector2(78 * s + jolt.x, h - 24 * s + jolt.y), hp_text, 30 * s, Color(1.0, 0.5, 0.5) if low else Color.WHITE)
	if not compact:
		_t(Vector2(bx, h - 50 * s), player.pname.to_upper(), 12, player.color.lerp(Color.WHITE, 0.45), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, ci)
	if player.spawn_protect > 0.0 and not compact:
		var sx := bx + UiKit.text_width(player.pname.to_upper(), 12 * s) + 14 * s
		UiKit.icon(ci, "shield", Vector2(sx, h - 54 * s), 6 * s, Color(0.5, 0.85, 1.0, 0.6 + 0.4 * sin(game.time * 12.0)))
	# Owned cards as little rarity-coloured tiles (not in compact cells).
	if compact:
		return
	var tile := 19.0 * s
	var max_tiles := int((w * 0.42) / (tile + 4 * s))
	var total: int = player.card_icons.size()
	var first := maxi(0, total - max_tiles)
	for i in range(first, total):
		var info: Array = player.card_icons[i]
		var r := Rect2(78 * s + (i - first) * (tile + 4 * s), h - 92 * s, tile, tile)
		UiKit.panel(ci, r, Color(Cards.RARITY_COLORS[info[1]], 0.85), 4 * s)
		UiKit.icon(ci, info[0], r.get_center(), tile * 0.3, Color.WHITE)
	if first > 0:
		_t(Vector2(78 * s + (total - first) * (tile + 4 * s), h - 77 * s), "+%d" % first, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, ci)


func _draw_ammo(ci: Control) -> void:
	if not player.alive or player.vehicle != null or player.picking:
		return
	var w := ci.size.x
	var h := size.y
	# Weapon: its silhouette on a badge (name underneath when there is room),
	# and the bubble shield status beside it.
	var wname: String = player.weapon_name()
	var tag := Rect2(w - 20 * s - 92 * s, h - (128 if not compact else 112) * s, 92 * s, 40 * s)
	UiKit.card(ci, tag, Color(UiKit.PANEL, 0.6), 10 * s, s)
	UiKit.weapon_icon(ci, wname, tag.get_center(), 34 * s, Cards.RARITY_COLORS[Cards.WEAPON].lerp(Color.WHITE, 0.55))
	if not compact:
		UiKit.text(ci, Vector2(tag.position.x - 40 * s, tag.position.y - 7 * s), wname.to_upper(), 11 * s, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, tag.size.x + 40 * s, 700, 0.18)
	if player.stats.shield_cd > 0.0:
		var ready_col := Color(0.45, 0.9, 1.0) if player.shield_ready() else Color(0.36, 0.3, 0.46)
		ci.draw_circle(Vector2(tag.position.x - 16 * s, tag.get_center().y), 11 * s, Color(0.03, 0.035, 0.06, 0.55))
		UiKit.icon(ci, "shield", Vector2(tag.position.x - 16 * s, tag.get_center().y), 7 * s, ready_col)
	# --- bottom right: ammo, reload, dash ---
	var ax := w - 20.0 * s
	if player.reload_left > 0.0:
		var rf: float = 1.0 - player.reload_left / player.stats.reload_time
		_t(Vector2(0, h - 44 * s), "RELOADING", 15, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, ax, 700, ci)
		UiKit.bar(ci, Rect2(ax - 130 * s, h - 36 * s, 130 * s, 12 * s), rf, UiKit.GOLD, s)
	elif player.stats.melee_weapon:
		# Blades need no ammunition: show the swing recharging instead.
		var sf: float = 1.0 - clampf(player.melee_cd / maxf(player.stats.fire_interval, 0.05), 0.0, 1.0)
		UiKit.bar(ci, Rect2(ax - 130 * s, h - 36 * s, 130 * s, 12 * s), sf, UiKit.GOLD if sf >= 1.0 else Color(0.8, 0.8, 0.9), s)
	else:
		var mag := "/%d" % player.stats.mag_size
		var mw := UiKit.num_width(mag, 22 * s)
		UiKit.num(ci, Vector2(ax - mw, h - 24 * s), mag, 22 * s, Color(1, 1, 1, 0.75))
		var low: bool = player.ammo <= maxi(1, player.stats.mag_size / 4)
		UiKit.num(ci, Vector2(0, h - 22 * s), "%d" % player.ammo, 50 * s, Color(1.0, 0.45, 0.4) if low else Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, ax - mw - 4 * s)
		# Bullet pips; the last quarter of the magazine is red.
		var n: int = player.stats.mag_size
		if n <= 16 and not compact:
			var pw := 4.0 * s
			var pg := 3.0 * s
			var x0 := ax - n * (pw + pg) + pg
			for i in n:
				var pr := Rect2(x0 + i * (pw + pg), h - 76 * s, pw, 11 * s)
				var pc: Color = (Color(1.0, 0.42, 0.4) if i < maxi(1, n / 4) else Color(0.95, 0.96, 1.0)) if i < player.ammo else Color(1, 1, 1, 0.18)
				UiKit.panel(ci, pr, pc, 1.5 * s)
	# Dash gauge.
	var dc := Vector2(ax - 168 * s, h - 34 * s)
	var df: float = 1.0 - clampf(player.dash_cd / player.stats.dash_cooldown, 0.0, 1.0)
	var ready: bool = df >= 1.0
	var dr := 17.0 * s
	var dcol := Color(0.4, 0.85, 1.0)
	ci.draw_circle(dc, dr, Color(0.03, 0.035, 0.06, 0.55))
	ci.draw_arc(dc, dr, -PI / 2, -PI / 2 + TAU * df, 48, dcol if ready else Color(dcol, 0.7), 2.0 * s, true)
	UiKit.icon(ci, "bolt", dc, 8 * s, dcol.lerp(Color.WHITE, 0.4) if ready else Color(1, 1, 1, 0.35))
	# Block gauge.
	var bc := dc - Vector2(44 * s, 0)
	var bf: float = 1.0 - clampf(player.block_cd / player.stats.block_cooldown, 0.0, 1.0)
	var bready: bool = bf >= 1.0
	var bcol: Color = player.color.lerp(Color.WHITE, 0.25)
	ci.draw_circle(bc, dr, Color(0.03, 0.035, 0.06, 0.55))
	ci.draw_arc(bc, dr, -PI / 2, -PI / 2 + TAU * bf, 48, bcol if bready else Color(bcol, 0.7), 2.0 * s, true)
	UiKit.icon(ci, "shield", bc, 8 * s, bcol.lerp(Color.WHITE, 0.4) if bready else Color(1, 1, 1, 0.35))


# --------------------------------------------------------------------------
# Dead: the card picker
# --------------------------------------------------------------------------

func _draw_dead(w: float, h: float) -> void:
	if game.match_over:
		return
	var dt: float = player.dead_time
	var a := clampf(dt * 3.0, 0.0, 1.0)

	# Header: who got you.
	var head_y := h * 0.185 - (1.0 - UiKit.back_out(a)) * 60 * s
	if player.picking:
		_t(Vector2(0, head_y), "WAVE CLEARED!", 26, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, w)
	elif player.card_choices.is_empty() and not player.respawn_pending:
		# Zombies: no card while down; back when the wave is cleared.
		_t(Vector2(0, head_y), "YOU'RE DOWN!", 30, Color(1.0, 0.5, 0.5, a), HORIZONTAL_ALIGNMENT_CENTER, w)
		_t(Vector2(0, head_y + 34 * s), "BACK IN THE FIGHT WHEN THE WAVE IS CLEARED", 15, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, w)
		return
	elif player.killer != null and is_instance_valid(player.killer):
		var label := "FRAGGED BY"
		var lw := UiKit.text_width(label, 20 * s)
		var nw := UiKit.text_width(player.killer.pname, 20 * s)
		var total := lw + 46 * s + nw
		var x := (w - total) * 0.5
		UiKit.card(self, Rect2(x - 16 * s, head_y - 26 * s, total + 32 * s, 38 * s), Color(UiKit.PANEL, a), 19 * s, s)
		_t(Vector2(x, head_y), label, 20, Color(1.0, 0.5, 0.5, a))
		UiKit.portrait(self, Vector2(x + lw + 23 * s, head_y - 5 * s), 10 * s, Color(player.killer.color, a), player.killer.kind)
		_t(Vector2(x + lw + 46 * s, head_y), player.killer.pname, 20, Color(player.killer.color.lerp(Color.WHITE, 0.4), a))
		if player.killer_hp > 0.0:
			# How close it was.
			_t(Vector2(0, head_y + 30 * s), "THEY HAD %d HP LEFT" % ceili(player.killer_hp), 14, Color(1, 1, 1, 0.75 * a), HORIZONTAL_ALIGNMENT_CENTER, w)
	else:
		_t(Vector2(0, head_y), "OOPS!", 26, Color(1.0, 0.5, 0.5, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	# (Skipped under "they had N HP left", which sits in the same place.)
	if player.killer == null or not is_instance_valid(player.killer) or player.killer_hp <= 0.0:
		_t(Vector2(0, h * 0.185 + 54 * s), "PICK A POWERUP", 20, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, w)

	var n: int = player.card_choices.size()
	if n == 0:
		return
	var cw := minf(minf(w * 0.95 / n - 8 * s, 260.0 * s), h * 0.56 / 1.45)
	var ch := cw * 1.45
	var gap := cw * 0.1
	var x0 := (w - (cw * n + gap * (n - 1))) * 0.5 + cw * 0.5
	var cy := h * 0.6
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
		var py := cy + ch * 0.5 + 34 * s
		var pad: bool = player.brain.device >= 0
		var l1 := "D-PAD" if pad else "A / D"
		var l2 := "A" if pad else "SPACE"
		var tw := UiKit.text_width(l1, 13 * s) + UiKit.text_width(l2, 13 * s) + UiKit.text_width("CHOOSE", 15 * s) + UiKit.text_width("PICK", 15 * s) + 90 * s
		var x := (w - tw) * 0.5
		x += UiKit.prompt(self, Vector2(x, py), l1, 16 * s, not pad, player.brain.device) + 8 * s
		_t(Vector2(x, py), "CHOOSE", 15, Color.WHITE)
		x += UiKit.text_width("CHOOSE", 15 * s) + 26 * s
		x += UiKit.prompt(self, Vector2(x, py), l2, 16 * s, not pad, player.brain.device) + 8 * s
		_t(Vector2(x, py), "PICK", 15, Color.WHITE)


## In a vehicle: crosshair, armour bar, weapon status and the exit prompt.
func _draw_vehicle(w: float, h: float) -> void:
	var v = player.vehicle
	var c := Vector2(w, h) * 0.5
	draw_texture_rect(UiKit.vignette(), Rect2(0, 0, w, h), false, Color(0.05, 0.05, 0.1, 0.3))
	if player.hurt_flash > 0.0:
		draw_texture_rect(UiKit.vignette(), Rect2(0, 0, w, h), false, Color(1.0, 0.2, 0.1, player.hurt_flash * 0.5))
	draw_arc(c, 14 * s, 0, TAU, 64, Color(0, 0, 0.02, 0.22), maxf(2.7, 2.7 * s), true)
	draw_arc(c, 14 * s, 0, TAU, 64, Color(0.86, 0.87, 0.9, 0.9), maxf(1.2, 1.3 * s), true)
	if player.hit_marker > 0.0:
		var hm: float = player.hit_marker
		for k in 4:
			var a := PI * 0.25 + k * PI * 0.5
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * 10 * s, c + d * 18 * s, Color(1, 1, 1, hm), 2 * s, true)
	var bw := 300.0 * s
	var r := Rect2(16 * s, h - 66 * s, bw, 50 * s)
	UiKit.card(self, r, UiKit.PANEL, 20 * s, s)
	_t(Vector2(r.position.x + 16 * s, r.position.y + 22 * s), v.label, 15, UiKit.GOLD)
	var frac: float = clampf(v.health / v.max_health, 0.0, 1.0)
	var bar := Rect2(r.position.x + 16 * s, r.position.y + 30 * s, bw - 32 * s, 10 * s)
	UiKit.panel(self, bar, Color(0, 0, 0, 0.5), 5 * s)
	if v.racing:
		# Race car: a speedometer instead of armour.
		var sp: float = absf(v._speed)
		frac = clampf(sp / v._spec.speed, 0.0, 1.0)
		UiKit.panel(self, Rect2(bar.position, Vector2(maxf(bar.size.y, bar.size.x * frac), bar.size.y)), Color(0.4, 0.8, 1.0).lerp(Color(1.0, 0.45, 0.3), frac), 5 * s)
		_t(Vector2(r.position.x, r.position.y + 22 * s), "%d KM/H" % int(sp * 3.6), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, bw - 16 * s)
	else:
		UiKit.panel(self, Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(1.0, 0.35, 0.3).lerp(Color(0.4, 0.95, 0.5), frac), 5 * s)
	var pad: bool = player.brain.device >= 0
	var lines: Array = []
	match v.type:
		"tank":
			lines = [["RT" if pad else "LMB", "CANNON" if v.main_cd <= 0.0 else "RELOADING"], ["LT" if pad else "RMB", "MACHINE GUN"]]
		"heli":
			lines = [["RT" if pad else "LMB", "NOSE GUN"], ["LT" if pad else "RMB", "ROCKETS %d" % v.rockets if v.alt_cd < 0.5 else "RELOADING"],
				["A" if pad else "SPACE", "UP"], ["B" if pad else "C", "DOWN"]]
		_:
			lines = [["RT" if pad else "LMB", "MACHINE GUN"], ["LT" if pad else "RMB", "ZOOM"]]
	if not v.armed:
		lines = [["A" if pad else "SPACE", "UP"], ["B" if pad else "C", "DOWN"]] if v.type == "heli" else []
	lines.append(["R3" if pad else "F", "1ST PERSON" if not player.fp_drive else "3RD PERSON"])
	lines.append(["Y" if pad else "E", "RESET CAR" if v.racing else "GET OUT"])
	var y := h - 26 * s
	var x := w - 16 * s
	for i in range(lines.size() - 1, -1, -1):
		var ln: Array = lines[i]
		var tw := UiKit.text_width(ln[1], 13 * s)
		x -= tw
		_t(Vector2(x, y), ln[1], 13, Color.WHITE)
		# Room for the button glyph: "SPACE" is much wider than "A".
		x -= maxf(30.0 * s, UiKit.text_width(ln[0], 12 * s) + 12 * s) + 10 * s
		UiKit.prompt(self, Vector2(x, y), ln[0], 15 * s, not pad, player.brain.device)
		x -= 24 * s


func _draw_card(card: Dictionary, centre: Vector2, sz: Vector2, rot: float, scl: float, selected: bool, alpha: float) -> void:
	# Everything inside the card is laid out in "card units" (u), so text grows
	# with the card rather than with the HUD scale.
	var u := sz.x / 176.0
	draw_set_transform(centre, rot, Vector2(scl, scl))
	var rc: Color = Cards.RARITY_COLORS[card.rarity]
	var r := Rect2(-sz * 0.5, sz)
	if selected:
		var glow := 0.55 + 0.35 * sin(game.time * 6.0)
		UiKit.panel(self, r.grow(10 * u), Color(rc, glow * 0.18 * alpha), 20 * u)
	var body := Color(0.1, 0.11, 0.17) if selected else Color(0.07, 0.075, 0.12)
	UiKit.panel(self, r, Color(body, 0.96 * alpha), 13 * u, Color(rc.lerp(Color.WHITE, 0.2) if selected else Color(rc.darkened(0.3), 0.6), alpha), (2.0 if selected else 1.2) * u, 6 * u)
	# Art band.
	var band := Rect2(r.position + Vector2(7, 7) * u, Vector2(sz.x - 14 * u, sz.y * 0.4))
	UiKit.panel(self, band, Color(rc.darkened(0.25) if selected else rc.darkened(0.6), alpha), 9 * u)
	var ic := band.get_center() + Vector2(0, 2 * u)
	var ir := band.size.y * 0.3
	draw_circle(ic, ir * 1.4, Color(rc.lerp(Color.WHITE, 0.2), (0.45 if selected else 0.2) * alpha))
	UiKit.icon(self, card.icon, ic, ir, Color(1, 1, 1, (1.0 if selected else 0.7) * alpha))
	# Rarity tag.
	var tag: String = Cards.RARITY_NAMES[card.rarity]
	var tw := UiKit.text_width(tag, 10 * u) + 16 * u
	var tr := Rect2(Vector2(-tw * 0.5, band.end.y - 9 * u), Vector2(tw, 18 * u))
	UiKit.panel(self, tr, Color(UiKit.INK, alpha), 9 * u, Color(rc, alpha), 1.5 * u)
	draw_string(UiKit.font(700), tr.position + Vector2(0, 13.5 * u), tag, HORIZONTAL_ALIGNMENT_CENTER, tw, maxi(8, int(10 * u)), Color(rc.lerp(Color.WHITE, 0.3), alpha))
	# Name and description: large and high-contrast.
	var dim := 1.0 if selected else 0.72
	var name_px := 20.0 if card.name.length() < 12 else (17.0 if card.name.length() < 15 else 14.5)
	draw_string(UiKit.font(700), Vector2(r.position.x, band.end.y + 36 * u), card.name, HORIZONTAL_ALIGNMENT_CENTER, sz.x, maxi(8, int(name_px * u)), Color(1, 1, 1, dim * alpha))
	draw_multiline_string(UiKit.font(600), Vector2(r.position.x + 9 * u, band.end.y + 62 * u), card.desc, HORIZONTAL_ALIGNMENT_CENTER, sz.x - 18 * u, maxi(8, int(14.5 * u)), -1, Color(0.8, 0.86, 1.0, dim * alpha))


# --------------------------------------------------------------------------
# Shared pieces
# --------------------------------------------------------------------------

func _draw_score_strip(ci: Control) -> void:
	if game.rules != null and game.rules.has_method("draw_strip"):
		game.rules.draw_strip(self, ci, s)
		return
	var w := ci.size.x
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
		UiKit.num(ci, Vector2(cx + 12 * s, cy + 7 * s), "%d" % p.kills, 19 * s, Color.WHITE if p != player else UiKit.GOLD)
	if not compact:
		_t(Vector2(0, 54 * s), "FIRST TO %d" % game.kill_target, 10, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w, 700, ci)


func _draw_feed(ci: Control) -> void:
	var w := ci.size.x
	var y := 62.0 * s
	var shown := 0
	for entry in game.feed:
		var age: float = game.time - entry.t
		if age > 5.5 or (compact and shown >= 3):
			continue
		shown += 1
		var wpn: String = entry.get("weapon", "")
		var alpha := clampf(5.5 - age, 0.0, 1.0)
		var slide := (1.0 - UiKit.back_out(clampf(age / 0.3, 0.0, 1.0))) * 120 * s
		var vn: String = entry.victim.pname
		var kn: String = entry.killer.pname if entry.killer != null else ""
		var vw := UiKit.text_width(vn, 12 * s)
		var kw := UiKit.text_width(kn, 12 * s) if kn != "" else 0.0
		var total := vw + kw + ((80 * s if wpn != "" else 62 * s) if kn != "" else 40 * s)
		var x := w - 10 * s - total + slide
		UiKit.panel(ci, Rect2(x, y, total, 22 * s), Color(UiKit.PANEL, 0.6 * alpha), 5 * s)
		var cx := x + 8 * s
		if kn != "":
			_t(Vector2(cx, y + 16 * s), kn, 12, Color(entry.killer.color.lerp(Color.WHITE, 0.45), alpha), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700, ci)
			cx += kw + 12 * s
			if wpn != "":
				# What did it: the weapon's silhouette.
				UiKit.weapon_icon(ci, wpn, Vector2(cx + 9 * s, y + 11 * s), 13 * s, Color(1.0, 0.85, 0.6, alpha))
				cx += 30 * s
			else:
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
	# Weapon pad prompt.
	if player.pickup_prompt != "" and player.alive and not player.is_bot:
		var key: String = player.prompt_key if player.prompt_key != "" else ("Y" if player.brain.device >= 0 else "E")
		var tw := UiKit.text_width(player.pickup_prompt, 17 * s) + 44 * s
		var px := (w - tw) * 0.5
		var py := h * 0.74
		UiKit.card(self, Rect2(px - 12 * s, py - 24 * s, tw + 24 * s, 36 * s), UiKit.PANEL, 18 * s, s)
		px += UiKit.prompt(self, Vector2(px, py), key, 18 * s, player.brain.device < 0, player.brain.device) + 10 * s
		_t(Vector2(px, py), player.pickup_prompt, 17, Color.WHITE)
	# Short notices (weapon pickup, second wind).
	if player.notice_t > 0.0 and player.alive:
		var nt: float = 1.6 - player.notice_t
		var na := clampf(player.notice_t * 4.0, 0.0, 1.0)
		var npop := UiKit.back_out(clampf(nt * 7.0, 0.0, 1.0))
		_big(Vector2(w * 0.5, h * 0.66), player.notice, 20, Color(0.8, 0.95, 1.0, na), npop)
		if player.notice_weapon >= 0:
			# The weapon you just got, spinning up into place.
			var ic := Vector2(w * 0.5, h * 0.66 - 44 * s)
			draw_set_transform(ic, (1.0 - npop) * 1.5, Vector2(npop, npop))
			UiKit.panel(self, Rect2(-56 * s, -30 * s, 112 * s, 60 * s), Color(UiKit.PANEL, 0.9 * na), 18 * s, Color(UiKit.GOLD, na), 3 * s)
			UiKit.weapon_icon(self, Weapons.LIST[player.notice_weapon].name, Vector2.ZERO, 42 * s, Color(1, 1, 1, na))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Kill confirmation.
	if player.kill_flash > 0.0 and player.alive:
		var t: float = 1.0 - player.kill_flash
		var a := clampf(player.kill_flash * 5.0, 0.0, 1.0)
		# Stamped in: big, then slammed down to size with a starburst behind.
		var stamp := clampf(t * 8.0, 0.0, 1.0)
		var scl := lerpf(1.9, 1.0, stamp * stamp) if stamp < 1.0 else 1.0 + maxf(0.0, 0.08 - (t - 0.125) * 0.6)
		var kc := Vector2(w * 0.5, h * 0.27)
		if t < 0.5:
			var ba := (1.0 - t * 2.0) * a
			for i in 12:
				var ang := TAU * i / 12.0 + 0.2
				var r0 := (30.0 + t * 260.0) * s
				draw_line(kc + Vector2(cos(ang), sin(ang) * 0.45) * r0, kc + Vector2(cos(ang), sin(ang) * 0.45) * (r0 + 26 * s), Color(UiKit.GOLD, ba), 4.0 * s)
		_big(kc, "FRAGGED %s!" % player.kill_name, 24, Color(UiKit.GOLD, a), scl, -0.03 + sin(t * 20.0) * 0.015)
		if player.multi_kill >= 2:
			var words := ["", "", "DOUBLE KO!", "TRIPLE KO!", "QUAD KO!"]
			var mk: String = words[player.multi_kill] if player.multi_kill < words.size() else "%dx KO!" % player.multi_kill
			var mpop := UiKit.elastic_out(clampf((t - 0.08) * 3.0, 0.0, 1.0))
			_big(kc + Vector2(0, 40 * s), mk, 30, Color(UiKit.ACCENT.lerp(Color.WHITE, 0.2), a), mpop, 0.04)
	# Mode announcements (wave start, flag captured...).
	if game.rules != null and game.rules.banner_t < 3.0 and game.countdown <= 0.0:
		var bt: float = game.rules.banner_t
		var ba := clampf((3.0 - bt) * 2.0, 0.0, 1.0)
		_big(Vector2(w * 0.5, h * 0.3), game.rules.banner, 30, Color(UiKit.GOLD, ba), UiKit.back_out(clampf(bt * 5.0, 0.0, 1.0)))
	# 3-2-1.
	if game.countdown > 0.0:
		var num := ceili(game.countdown)
		if num <= 3:
			var f: float = game.countdown - floorf(game.countdown)
			var cs := 0.8 + f * 0.6
			draw_set_transform(c, 0.0, Vector2(cs, cs))
			UiKit.num(self, Vector2(-size.x * 0.5, 110 * s * 0.35), str(num), 130 * s, Color(UiKit.GOLD.lerp(Color.WHITE, 0.5), clampf(f * 3.0, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, size.x, 0.12)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			_big(c, "GET READY", 40, Color.WHITE, 1.0 + sin(game.time * 6.0) * 0.03)
		_big(c + Vector2(0, 52 * s), (game.map.label() if game.mode == "frontline" else game.MODE_NAMES[game.mode] + "  -  " + game.map.label()), 15, Color(1, 1, 1, 0.85), 1.0)
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
	var rw := minf(w * 0.45, 250 * s)
	var x := 16.0 * s
	var y := 40.0 * s
	_t(Vector2(x, y), "SCOREBOARD", 22, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, rw)
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
