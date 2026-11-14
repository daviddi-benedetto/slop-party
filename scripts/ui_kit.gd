extends RefCounted
## Shared look-and-feel for every 2D screen (HUD, lobby, pause, results).
## Everything is immediate-mode: pass the CanvasItem that is currently inside
## its _draw() as `ci`. Sizes are in final pixels (callers multiply by their
## own scale factor).
##
## Style: chunky rounded "sticker" UI - thick dark outlines, drop shadows,
## saturated candy colours, Fredoka font.

const INK := Color(0.17, 0.12, 0.24)
const CREAM := Color(1.0, 0.97, 0.9)
const GOLD := Color(1.0, 0.8, 0.22)
const PANEL := Color(0.2, 0.16, 0.3, 0.88)
const PLAYER_COLORS := [
	Color(1.0, 0.36, 0.38), Color(0.28, 0.6, 1.0), Color(0.3, 0.84, 0.45),
	Color(1.0, 0.8, 0.2), Color(0.72, 0.48, 1.0), Color(1.0, 0.56, 0.22),
]
const KIND_NAMES := ["BEAR", "BUNNY", "CAT", "DOG", "FOX", "FROG"]

static var _fonts := {}
static var _sb: StyleBoxFlat
static var _vignette: GradientTexture2D


static func font(weight := 700) -> Font:
	if not _fonts.has(weight):
		var f: Font = ThemeDB.fallback_font
		if ResourceLoader.exists("res://fonts/Fredoka.ttf"):
			var fv := FontVariation.new()
			fv.base_font = load("res://fonts/Fredoka.ttf")
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
			f = fv
		_fonts[weight] = f
	return _fonts[weight]


## Chunky outlined text with a hard drop shadow.
static func text(ci: CanvasItem, pos: Vector2, s: String, px: float, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, weight := 700, outline := 0.2) -> void:
	var f := font(weight)
	var fs := maxi(8, int(px))
	var ink := Color(INK, color.a)
	if outline > 0.0:
		var o := maxi(2, int(fs * outline))
		ci.draw_string_outline(f, pos + Vector2(0, fs * 0.09), s, align, width, fs, o, ink)
		ci.draw_string_outline(f, pos, s, align, width, fs, o, ink)
	ci.draw_string(f, pos, s, align, width, fs, color)


static func text_width(s: String, px: float, weight := 700) -> float:
	return font(weight).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, int(px))).x


## Rounded panel. `shadow` is the drop distance in pixels (0 = none).
static func panel(ci: CanvasItem, rect: Rect2, color: Color, radius: float,
		border := Color(0, 0, 0, 0), border_w := 0.0, shadow := 0.0) -> void:
	if _sb == null:
		_sb = StyleBoxFlat.new()
		_sb.anti_aliasing = true
	_sb.bg_color = color
	_sb.set_corner_radius_all(int(minf(radius, minf(rect.size.x, rect.size.y) * 0.5)))
	_sb.corner_detail = 8
	_sb.border_color = border
	_sb.set_border_width_all(int(border_w))
	_sb.shadow_size = 1 if shadow > 0.0 else 0
	_sb.shadow_color = Color(0.08, 0.05, 0.12, 0.45 * color.a)
	_sb.shadow_offset = Vector2(0, shadow)
	ci.draw_style_box(_sb, rect)


## Sticker-style panel: ink border plus drop shadow.
static func card(ci: CanvasItem, rect: Rect2, color: Color, radius: float, s: float) -> void:
	panel(ci, rect, color, radius, Color(INK, color.a), maxf(2.0, 3.0 * s), 4.0 * s)


## Progress bar with ink frame.
static func bar(ci: CanvasItem, rect: Rect2, frac: float, fill: Color, s: float, ghost := -1.0) -> void:
	var r := rect.size.y * 0.5
	panel(ci, rect.grow(3.0 * s), INK, r + 3.0 * s, Color(0, 0, 0, 0), 0.0, 3.0 * s)
	panel(ci, rect, Color(0.32, 0.27, 0.42), r)
	if ghost > frac:
		panel(ci, Rect2(rect.position, Vector2(maxf(rect.size.y, rect.size.x * ghost), rect.size.y)), Color(1, 1, 1, 0.85), r)
	if frac > 0.001:
		var fr := Rect2(rect.position, Vector2(maxf(rect.size.y, rect.size.x * frac), rect.size.y))
		panel(ci, fr, fill, r)
		panel(ci, Rect2(fr.position + Vector2(r * 0.6, rect.size.y * 0.16), Vector2(maxf(0.0, fr.size.x - r * 1.2), rect.size.y * 0.22)), Color(1, 1, 1, 0.35), r)


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, color: Color, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	ci.draw_colored_polygon(pts, color)


static func poly(ci: CanvasItem, c: Vector2, r: float, pts: Array, color: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + p * r)
	ci.draw_colored_polygon(out, color)


## 2D face badge for a character: same species and colour as the 3D model.
static func portrait(ci: CanvasItem, c: Vector2, r: float, color: Color, kind: int, dead := false) -> void:
	var ink := Color(INK, color.a)
	var light := color.lerp(Color.WHITE, 0.6)
	var o := r * 0.13
	# Ears (ink silhouette first, then fill).
	for pass_i in 2:
		var col := ink if pass_i == 0 else color
		var g := o if pass_i == 0 else 0.0
		for sx in [-1.0, 1.0]:
			match kind:
				0:
					ci.draw_circle(c + Vector2(sx * 0.7, -0.68) * r, r * 0.36 + g, col)
				1:
					ellipse(ci, c + Vector2(sx * 0.42, -1.15) * r, r * 0.24 + g, r * 0.62 + g, col, sx * 0.18)
				2:
					poly(ci, c, r + g, [Vector2(sx * 0.95, -0.2), Vector2(sx * 0.82, -1.25), Vector2(sx * 0.15, -0.8)], col)
				3:
					ellipse(ci, c + Vector2(sx * 0.98, -0.1) * r, r * 0.3 + g, r * 0.6 + g, col.darkened(0.25) if pass_i == 1 else col, sx * -0.25)
				4:
					poly(ci, c, r + g, [Vector2(sx * 1.0, -0.1), Vector2(sx * 0.95, -1.4), Vector2(sx * 0.1, -0.8)], col)
				5:
					ci.draw_circle(c + Vector2(sx * 0.48, -0.82) * r, r * 0.4 + g, col)
	ci.draw_circle(c, r + o, ink)
	ci.draw_circle(c, r, color)
	if kind == 5:
		for sx in [-1.0, 1.0]:
			ci.draw_circle(c + Vector2(sx * 0.48, -0.82) * r, r * 0.26, Color(1, 1, 1, color.a))
			ci.draw_circle(c + Vector2(sx * 0.48, -0.82) * r, r * 0.13, ink)
		ci.draw_arc(c + Vector2(0, 0.05) * r, r * 0.5, 0.35, PI - 0.35, 10, ink, maxf(1.5, r * 0.1))
		return
	ellipse(ci, c + Vector2(0, 0.38) * r, r * 0.5, r * 0.38, light)
	ci.draw_circle(c + Vector2(0, 0.24) * r, r * 0.13, ink)
	for sx in [-1.0, 1.0]:
		var e := c + Vector2(sx * 0.4, -0.12) * r
		if dead:
			var d := r * 0.14
			ci.draw_line(e + Vector2(-d, -d), e + Vector2(d, d), ink, maxf(1.5, r * 0.1))
			ci.draw_line(e + Vector2(-d, d), e + Vector2(d, -d), ink, maxf(1.5, r * 0.1))
		else:
			ci.draw_circle(e, r * 0.15, ink)
			ci.draw_circle(e + Vector2(-0.04, -0.05) * r, r * 0.05, Color(1, 1, 1, color.a))


## Controller button / key prompt. Returns the width it used.
static func prompt(ci: CanvasItem, pos: Vector2, label: String, px: float) -> float:
	var colors := {"A": Color(0.35, 0.82, 0.4), "B": Color(1.0, 0.4, 0.4), "X": Color(0.3, 0.6, 1.0), "Y": Color(1.0, 0.8, 0.2)}
	var h := px * 1.25
	if colors.has(label):
		var c := pos + Vector2(h * 0.5, -px * 0.36)
		ci.draw_circle(c, h * 0.5 + maxf(2.0, px * 0.1), INK)
		ci.draw_circle(c, h * 0.5, colors[label])
		text(ci, Vector2(pos.x, pos.y), label, px * 0.9, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, h, 700, 0.14)
		return h
	var w := text_width(label, px * 0.8) + px * 0.8
	var r := Rect2(pos.x, pos.y - px * 0.98, w, h)
	panel(ci, r, CREAM, px * 0.3, INK, maxf(2.0, px * 0.1), px * 0.12)
	ci.draw_string(font(700), Vector2(pos.x, pos.y - px * 0.08), label, HORIZONTAL_ALIGNMENT_CENTER, w, maxi(8, int(px * 0.8)), INK)
	return w


## Small pictograms used on cards and the HUD. `r` is the half-size.
static func icon(ci: CanvasItem, name: String, c: Vector2, r: float, color: Color) -> void:
	match name:
		"heart":
			ci.draw_circle(c + Vector2(-0.45, -0.3) * r, r * 0.52, color)
			ci.draw_circle(c + Vector2(0.45, -0.3) * r, r * 0.52, color)
			poly(ci, c, r, [Vector2(-0.94, -0.08), Vector2(0.94, -0.08), Vector2(0, 0.95)], color)
		"bolt":
			poly(ci, c, r, [Vector2(0.25, -1.0), Vector2(-0.6, 0.15), Vector2(-0.05, 0.15), Vector2(-0.3, 1.0), Vector2(0.6, -0.2), Vector2(0.05, -0.2)], color)
		"star":
			var pts: Array = []
			for i in 10:
				var a := -PI / 2 + TAU * i / 10.0
				pts.append(Vector2(cos(a), sin(a)) * (1.0 if i % 2 == 0 else 0.45))
			poly(ci, c, r, pts, color)
		"boom":
			var pts2: Array = []
			for i in 16:
				var a2 := TAU * i / 16.0
				pts2.append(Vector2(cos(a2), sin(a2)) * (1.0 if i % 2 == 0 else 0.55))
			poly(ci, c, r, pts2, color)
			ci.draw_circle(c, r * 0.3, Color(1, 1, 1, 0.8 * color.a))
		"ammo":
			for i in 3:
				var x := (i - 1) * 0.62
				ci.draw_circle(c + Vector2(x, -0.45) * r, r * 0.24, color)
				ci.draw_rect(Rect2(c + Vector2(x - 0.24, -0.45) * r, Vector2(0.48, 1.3) * r), color)
		"speed":
			for i in 2:
				var x2 := (i - 0.5) * 0.8
				poly(ci, c, r, [Vector2(x2 - 0.45, -0.8), Vector2(x2 + 0.35, 0), Vector2(x2 - 0.45, 0.8), Vector2(x2 - 0.05, 0), ], color)
		"shield":
			poly(ci, c, r, [Vector2(0, -1.0), Vector2(0.85, -0.65), Vector2(0.8, 0.2), Vector2(0, 1.0), Vector2(-0.8, 0.2), Vector2(-0.85, -0.65)], color)
		"jump":
			poly(ci, c, r, [Vector2(0, -1.0), Vector2(0.85, 0.0), Vector2(0.35, 0.0), Vector2(0.35, 0.9), Vector2(-0.35, 0.9), Vector2(-0.35, 0.0), Vector2(-0.85, 0.0)], color)
		"drop":
			ci.draw_circle(c + Vector2(0, 0.3) * r, r * 0.65, color)
			poly(ci, c, r, [Vector2(0, -1.0), Vector2(0.56, 0.0), Vector2(-0.56, 0.0)], color)
		"target":
			ci.draw_arc(c, r * 0.8, 0, TAU, 24, color, r * 0.22)
			ci.draw_circle(c, r * 0.3, color)
		"bounce":
			ci.draw_circle(c + Vector2(0.35, -0.35) * r, r * 0.42, color)
			ci.draw_arc(c + Vector2(-0.2, 0.9) * r, r * 0.95, -PI * 0.95, -PI * 0.45, 12, color, r * 0.2)
		"crown":
			poly(ci, c, r, [Vector2(-1.0, 0.6), Vector2(-1.0, -0.5), Vector2(-0.45, 0.0), Vector2(0, -0.8), Vector2(0.45, 0.0), Vector2(1.0, -0.5), Vector2(1.0, 0.6)], color)
		"skull":
			ci.draw_circle(c + Vector2(0, -0.15) * r, r * 0.8, color)
			ci.draw_rect(Rect2(c + Vector2(-0.45, 0.3) * r, Vector2(0.9, 0.6) * r), color)
			ci.draw_circle(c + Vector2(-0.32, -0.15) * r, r * 0.22, INK)
			ci.draw_circle(c + Vector2(0.32, -0.15) * r, r * 0.22, INK)
		_:
			ci.draw_circle(c, r * 0.7, color)


## Soft dark-edge vignette texture (white centre alpha 0 -> edge alpha 1).
static func vignette() -> GradientTexture2D:
	if _vignette == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0))
		g.set_color(1, Color(1, 1, 1, 1))
		g.set_offset(0, 0.45)
		_vignette = GradientTexture2D.new()
		_vignette.gradient = g
		_vignette.fill = GradientTexture2D.FILL_RADIAL
		_vignette.fill_from = Vector2(0.5, 0.5)
		_vignette.fill_to = Vector2(1.0, 0.5)
		_vignette.width = 128
		_vignette.height = 128
	return _vignette


static func back_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + t * t * (2.7 * t + 1.7)


static func elastic_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if t <= 0.0 or t >= 1.0:
		return t
	return pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * TAU / 3.0) + 1.0
