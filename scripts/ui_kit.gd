extends RefCounted
## Shared look-and-feel for every 2D screen (HUD, lobby, pause, results).
## Everything is immediate-mode: pass the CanvasItem that is currently inside
## its _draw() as `ci`. Sizes are in final pixels (callers multiply by their
## own scale factor).
##
## Style: chunky rounded "sticker" UI - thick dark outlines, drop shadows,
## saturated candy colours, Fredoka font.

# Palette after ROUNDS: near-black navy surfaces, off-white text, a hot orange
# highlight, and saturated neon player colours. GOLD (the highlight), PANEL
# and ACCENT follow the visual theme (use_theme: looks.gd "ui"), so the HUD
# and menus are pink and cyan in Cyberpunk, pastel in Toy, and so on.
const INK := Color(0.035, 0.04, 0.075)
const CREAM := Color(0.93, 0.95, 1.0)
const BASE_GOLD := Color(1.0, 0.62, 0.2)
const BASE_PANEL := Color(0.075, 0.085, 0.14, 0.92)
static var GOLD := BASE_GOLD
static var PANEL := BASE_PANEL
static var ACCENT := Color(0.3, 0.75, 1.0)
const PLAYER_COLORS := [
	Color(1.0, 0.45, 0.18), Color(0.22, 0.6, 1.0), Color(0.3, 0.9, 0.45), Color(1.0, 0.84, 0.2),
	Color(0.72, 0.45, 1.0), Color(1.0, 0.36, 0.66), Color(0.18, 0.9, 0.92), Color(1.0, 0.28, 0.3),
	Color(0.7, 0.95, 0.25), Color(0.9, 0.93, 1.0),
]
const COLOR_NAMES := ["ORANGE", "BLUE", "GREEN", "YELLOW", "PURPLE", "PINK", "CYAN", "RED", "LIME", "WHITE"]
const KIND_NAMES := ["BUNNY", "KITTY", "PUP", "BEAR", "FOX", "PANDA", "DUCK"]
## Which 2D face ui_kit.portrait() draws for each kind (bear, bunny, cat, dog,
## fox, -, panda, duck).
const PORTRAIT := [1, 2, 3, 0, 4, 6, 7]
const HAT_NAMES := ["NONE", "CAP", "CROWN", "TOP HAT", "PARTY HAT", "HORNS", "HALO", "HEADPHONES", "BOW", "ANTENNA", "MOHAWK",
	"COWBOY", "WIZARD", "CHEF", "VIKING", "PROPELLER"]
const BACK_NAMES := ["NONE", "CAPE", "BACKPACK", "WINGS", "BALLOON", "KATANA", "FLAG"]
const FACE_NAMES := ["NORMAL", "ANGRY", "SHADES", "EYE PATCH", "SLEEPY", "MONOCLE", "MUSTACHE"]

static var _fonts := {}
static var _num_font: Font
static var _sb: StyleBoxFlat
static var _vignette: GradientTexture2D
static var _ps := {}           # joypad device -> true when it is a PlayStation pad

## Which silhouette weapon_icon() draws for each weapon (weapons.gd names).
const WEAPON_SHAPE := {"Blaster": "ak", "Scatter": "shotgun", "Zapper": "smg", "Boomer": "launcher", "Rail": "sniper",
	"Lobber": "drum", "Bubbler": "orb", "Tripler": "rifle", "Magnum": "revolver", "Spinner": "minigun", "Pinball": "drum",
	"Flamer": "tank", "Twins": "twins", "Tesla": "orb", "Cluster": "launcher", "Vortex": "orb", "Ripper": "disc",
	"Sticky": "launcher", "Longshot": "sniper", "Frostbite": "tank", "Fire Hands": "hand", "Storm Staff": "staff",
	"Frost Hands": "hand", "Arcane Staff": "staff", "Sword": "sword", "Throwing Knives": "knives", "Longbow": "bow",
	"Crossbow": "crossbow", "Battle Axe": "axe", "Spear": "spear", "Powder Bomb": "bomb", "Knife": "knife"}
## Silhouettes in a box x -1..1 (stock to muzzle), y about -0.6..0.6.
## ["r", x0, y0, x1, y1] rectangle, ["c", x, y, radius] circle,
## ["p", x, y, x, y, ...] polygon.
const SHAPES := {
	"pistol": [["r", -0.55, -0.3, 0.7, -0.02], ["p", -0.5, -0.02, -0.12, -0.02, -0.24, 0.5, -0.62, 0.5], ["r", 0.55, -0.4, 0.66, -0.3]],
	"ak": [["r", -0.45, -0.22, 0.98, -0.09], ["r", -0.5, -0.27, 0.32, 0.04], ["p", -0.5, -0.22, -0.98, -0.04, -0.98, 0.28, -0.5, 0.04],
		["p", -0.08, 0.04, 0.1, 0.04, 0.26, 0.48, 0.08, 0.52], ["p", -0.42, 0.04, -0.22, 0.04, -0.3, 0.38, -0.5, 0.38], ["r", 0.86, -0.33, 0.92, -0.22]],
	"smg": [["r", -0.6, -0.28, 0.75, 0.0], ["r", 0.75, -0.19, 0.97, -0.09], ["p", -0.45, 0.0, -0.15, 0.0, -0.22, 0.45, -0.52, 0.45],
		["r", 0.08, 0.0, 0.26, 0.55], ["p", -0.6, -0.26, -0.97, -0.12, -0.97, 0.22, -0.6, 0.02]],
	"shotgun": [["r", -0.35, -0.26, 0.97, -0.08], ["r", 0.1, -0.08, 0.62, 0.08], ["p", -0.35, -0.26, -0.35, 0.06, -0.97, 0.32, -0.97, 0.04],
		["p", -0.42, 0.0, -0.2, 0.0, -0.3, 0.36, -0.52, 0.36]],
	"rifle": [["r", -0.45, -0.2, 0.98, -0.07], ["r", -0.5, -0.25, 0.3, 0.06], ["p", -0.5, -0.2, -0.98, -0.02, -0.98, 0.3, -0.5, 0.06],
		["r", -0.14, 0.06, 0.03, 0.46], ["r", -0.25, -0.43, 0.2, -0.31], ["r", -0.06, -0.31, 0.02, -0.25]],
	"sniper": [["r", -0.45, -0.17, 0.99, -0.08], ["r", -0.5, -0.24, 0.25, 0.06], ["p", -0.5, -0.2, -0.99, -0.02, -0.99, 0.3, -0.5, 0.06],
		["r", -0.36, -0.47, 0.32, -0.31], ["r", -0.04, -0.31, 0.04, -0.24], ["p", 0.55, -0.08, 0.62, -0.08, 0.72, 0.4, 0.64, 0.4]],
	"launcher": [["r", -0.9, -0.32, 0.9, 0.06], ["r", 0.74, -0.38, 0.99, 0.12], ["p", -0.2, 0.06, 0.06, 0.06, 0.0, 0.46, -0.26, 0.46],
		["r", -0.1, -0.47, 0.16, -0.32]],
	"drum": [["r", -0.2, -0.32, 0.96, -0.06], ["c", -0.04, 0.08, 0.3], ["p", -0.7, -0.26, -0.3, -0.26, -0.3, 0.0, -0.9, 0.26, -0.97, 0.1]],
	"minigun": [["r", -0.25, -0.36, 0.98, -0.25], ["r", -0.25, -0.19, 0.98, -0.08], ["r", -0.25, -0.02, 0.98, 0.09],
		["r", -0.75, -0.44, -0.15, 0.2], ["r", 0.42, -0.44, 0.52, 0.17], ["p", -0.65, 0.2, -0.4, 0.2, -0.45, 0.5, -0.7, 0.5]],
	"revolver": [["r", -0.2, -0.28, 0.86, -0.12], ["c", -0.12, -0.12, 0.21], ["p", -0.45, -0.24, -0.2, -0.24, -0.3, 0.5, -0.72, 0.45]],
	"tank": [["r", -0.3, -0.26, 0.85, -0.08], ["p", 0.85, -0.32, 0.99, -0.38, 0.99, 0.04, 0.85, -0.02], ["c", -0.56, 0.06, 0.32],
		["p", 0.0, -0.08, 0.2, -0.08, 0.15, 0.42, -0.05, 0.42]],
	"orb": [["r", -0.62, -0.21, 0.45, 0.01], ["c", 0.66, -0.1, 0.3], ["p", -0.45, 0.0, -0.15, 0.0, -0.22, 0.46, -0.52, 0.46],
		["r", -0.92, -0.26, -0.6, 0.06]],
	"disc": [["c", 0.5, -0.06, 0.42], ["r", -0.82, -0.16, 0.2, 0.04], ["p", -0.5, 0.04, -0.22, 0.04, -0.3, 0.46, -0.58, 0.46]],
	"hand": [["c", 0.0, 0.14, 0.42], ["r", -0.42, -0.5, -0.24, 0.06], ["r", -0.18, -0.66, 0.0, 0.0], ["r", 0.06, -0.62, 0.24, 0.0],
		["r", 0.28, -0.46, 0.44, 0.06], ["p", 0.3, 0.12, 0.76, -0.14, 0.82, 0.02, 0.42, 0.38]],
	"staff": [["p", -0.98, 0.42, -0.9, 0.52, 0.52, -0.18, 0.44, -0.28], ["c", 0.66, -0.34, 0.26]],
	"sword": [["p", -0.28, -0.07, 0.84, -0.07, 0.99, 0.0, 0.84, 0.07, -0.28, 0.07], ["r", -0.38, -0.32, -0.28, 0.32],
		["r", -0.8, -0.055, -0.38, 0.055], ["c", -0.86, 0.0, 0.1]],
	"knife": [["p", -0.1, -0.1, 0.7, -0.1, 0.98, 0.04, 0.7, 0.1, -0.1, 0.1], ["r", -0.2, -0.22, -0.1, 0.22], ["r", -0.75, -0.08, -0.2, 0.08]],
	"knives": [["p", -0.1, -0.4, 0.78, -0.4, 0.92, -0.33, 0.78, -0.26, -0.1, -0.26], ["r", -0.55, -0.38, -0.1, -0.28],
		["p", -0.2, 0.18, 0.68, 0.18, 0.82, 0.25, 0.68, 0.32, -0.2, 0.32], ["r", -0.65, 0.2, -0.2, 0.3]],
	"crossbow": [["r", -0.92, -0.08, 0.72, 0.08], ["p", 0.36, -0.05, 0.56, -0.05, 0.76, -0.62, 0.6, -0.64],
		["p", 0.36, 0.05, 0.56, 0.05, 0.76, 0.62, 0.6, 0.64], ["p", -0.4, 0.08, -0.2, 0.08, -0.3, 0.46, -0.5, 0.46]],
	"axe": [["r", -0.97, -0.05, 0.62, 0.05], ["p", 0.3, -0.07, 0.74, -0.56, 0.96, -0.46, 0.96, 0.46, 0.74, 0.56, 0.3, 0.07]],
	"spear": [["r", -0.98, -0.035, 0.56, 0.035], ["p", 0.5, -0.13, 0.99, 0.0, 0.5, 0.13, 0.6, 0.0]],
	"bomb": [["c", -0.05, 0.12, 0.46], ["r", 0.18, -0.46, 0.3, -0.24], ["c", 0.3, -0.56, 0.11]],
}


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


## Theme colours for the HUD and menus (a looks.gd entry; {} = defaults).
static func use_theme(look: Dictionary) -> void:
	var ui: Dictionary = look.get("ui", {})
	GOLD = ui.get("value", BASE_GOLD)
	var p: Color = ui.get("panel", BASE_PANEL)
	# Keep panels dark enough for white text whatever the theme.
	PANEL = Color(p.r * 0.75, p.g * 0.75, p.b * 0.75, maxf(p.a, 0.9)) if p.get_luminance() > 0.2 else p
	ACCENT = ui.get("logo_b", Color(0.3, 0.75, 1.0))


## The chunky display font for numbers (scores, ammo, health, countdown).
static func num_font() -> Font:
	if _num_font == null:
		_num_font = load("res://fonts/LilitaOne.ttf") if ResourceLoader.exists("res://fonts/LilitaOne.ttf") else font(700)
	return _num_font


## Outlined number in the display font.
static func num(ci: CanvasItem, pos: Vector2, s: String, px: float, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 0.2) -> void:
	var f := num_font()
	var fs := maxi(8, int(px))
	var ink := Color(INK, color.a)
	if outline > 0.0:
		var o := maxi(2, int(fs * outline))
		ci.draw_string_outline(f, pos + Vector2(0, fs * 0.08), s, align, width, fs, o, ink)
		ci.draw_string_outline(f, pos, s, align, width, fs, o, ink)
	ci.draw_string(f, pos, s, align, width, fs, color)


static func num_width(s: String, px: float) -> float:
	return num_font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, int(px))).x


## A weapon silhouette (weapons.gd name, or "Knife") with an ink outline.
## `r` is the half-width; the icon is about 1.2 r tall.
static func weapon_icon(ci: CanvasItem, wname: String, c: Vector2, r: float, color: Color, outline := true) -> void:
	var shape: String = WEAPON_SHAPE.get(wname, "pistol")
	if shape == "twins":
		weapon_icon(ci, "Blaster", c + Vector2(-0.22, -0.16) * r, r * 0.72, color, outline)
		weapon_icon(ci, "Blaster", c + Vector2(0.22, 0.18) * r, r * 0.72, color, outline)
		return
	var ink := Color(INK, color.a)
	var o := maxf(1.5, r * 0.09)
	var passes: Array = [[ink, o], [color, 0.0]] if outline else [[color, 0.0]]
	for pass_i in passes:
		var col: Color = pass_i[0]
		var grow: float = pass_i[1]
		if shape == "bow":
			ci.draw_arc(c + Vector2(-0.35, 0) * r, r * 0.95, -1.15, 1.15, 18, col, r * 0.16 + grow * 2.0)
			ci.draw_line(c + Vector2(-0.35 + cos(1.15) * 0.95, -sin(1.15) * 0.95) * r, c + Vector2(-0.35 + cos(1.15) * 0.95, sin(1.15) * 0.95) * r, col, maxf(1.0, r * 0.05) + grow * 2.0)
			ci.draw_line(c + Vector2(-0.8, 0) * r, c + Vector2(0.95, 0) * r, col, r * 0.07 + grow * 2.0)
			poly(ci, c, r, [Vector2(0.75, -0.14), Vector2(1.02, 0), Vector2(0.75, 0.14)], col)
			continue
		for part in SHAPES.get(shape, SHAPES.pistol):
			match part[0]:
				"r":
					var rr := Rect2(c + Vector2(part[1], part[2]) * r, Vector2(part[3] - part[1], part[4] - part[2]) * r).grow(grow)
					ci.draw_rect(rr, col)
				"c":
					ci.draw_circle(c + Vector2(part[1], part[2]) * r, part[3] * r + grow, col)
				"p":
					var pts := PackedVector2Array()
					var centre := Vector2.ZERO
					var n: int = (part.size() - 1) / 2
					for i in n:
						centre += Vector2(part[1 + i * 2], part[2 + i * 2])
					centre /= n
					for i in n:
						var v := Vector2(part[1 + i * 2], part[2 + i * 2])
						pts.append(c + v * r + (v - centre).normalized() * grow)
					ci.draw_colored_polygon(pts, col)
	if outline:
		# A small highlight along the top edge reads as a sticker.
		pass


## True when a joypad is a PlayStation controller (shows the shape glyphs).
static func is_ps(device: int) -> bool:
	if device < 0:
		return false
	if not _ps.has(device):
		var n := Input.get_joy_name(device).to_lower()
		_ps[device] = n.contains("ps3") or n.contains("ps4") or n.contains("ps5") or n.contains("playstation") or n.contains("dualsense") or n.contains("dualshock") or n.contains("sony") or n.begins_with("wireless controller")
	return _ps[device]


## Forget cached controller types (a pad was plugged in or out).
static func reset_pads() -> void:
	_ps.clear()


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
	_sb.shadow_color = Color(0.0, 0.0, 0.02, 0.55 * color.a)
	_sb.shadow_offset = Vector2(0, shadow)
	ci.draw_style_box(_sb, rect)


## Sticker-style panel: ink border plus drop shadow.
static func card(ci: CanvasItem, rect: Rect2, color: Color, radius: float, s: float) -> void:
	panel(ci, rect, color, radius, Color(INK, color.a), maxf(2.0, 3.0 * s), 4.0 * s)


## Progress bar with ink frame.
static func bar(ci: CanvasItem, rect: Rect2, frac: float, fill: Color, s: float, ghost := -1.0) -> void:
	var r := rect.size.y * 0.5
	panel(ci, rect.grow(3.0 * s), INK, r + 3.0 * s, Color(0, 0, 0, 0), 0.0, 3.0 * s)
	panel(ci, rect, Color(0.14, 0.15, 0.23), r)
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
	var real_kind := kind
	kind = PORTRAIT[posmod(kind, PORTRAIT.size())]
	# Ears (ink silhouette first, then fill).
	for pass_i in 2:
		var col := ink if pass_i == 0 else color
		var g := o if pass_i == 0 else 0.0
		for sx in [-1.0, 1.0]:
			match kind:
				0, 6:
					ci.draw_circle(c + Vector2(sx * 0.7, -0.68) * r, r * 0.36 + g, ink if kind == 6 else col)
				1:
					ellipse(ci, c + Vector2(sx * 0.42, -1.15) * r, r * 0.24 + g, r * 0.62 + g, col, sx * 0.18)
				2:
					poly(ci, c, r + g, [Vector2(sx * 0.95, -0.2), Vector2(sx * 0.82, -1.25), Vector2(sx * 0.15, -0.8)], col)
				3:
					ellipse(ci, c + Vector2(sx * 0.98, -0.1) * r, r * 0.3 + g, r * 0.6 + g, col.darkened(0.25) if pass_i == 1 else col, sx * -0.25)
				4:
					poly(ci, c, r + g, [Vector2(sx * 1.0, -0.1), Vector2(sx * 0.95, -1.4), Vector2(sx * 0.1, -0.8)], col)
				7:
					if sx > 0.0:
						poly(ci, c, r + g, [Vector2(-0.12, -0.9), Vector2(0.05, -1.35), Vector2(0.18, -0.88)], col)
	ci.draw_circle(c, r + o, ink)
	ci.draw_circle(c, r, color)
	if kind == 6:
		for sx in [-1.0, 1.0]:
			ellipse(ci, c + Vector2(sx * 0.4, -0.1) * r, r * 0.27, r * 0.33, Color(ink, color.a * 0.85), sx * -0.5)
	if kind == 7:
		ellipse(ci, c + Vector2(0, 0.42) * r, r * 0.58, r * 0.24, Color(1.0, 0.6, 0.2, color.a))
	else:
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


## Controller button / key prompt. Returns the width it used. Pad labels are
## Xbox names (A B X Y LB RB LT RT); on a PlayStation pad (`device`, or the
## first connected pad when -99) they become the shapes and L1 / R2 names.
static func prompt(ci: CanvasItem, pos: Vector2, label: String, px: float, is_key := false, device := -99) -> float:
	var colors := {"A": Color(0.35, 0.82, 0.4), "B": Color(1.0, 0.4, 0.4), "X": Color(0.3, 0.6, 1.0), "Y": Color(1.0, 0.8, 0.2)}
	var h := px * 1.25
	if not is_key:
		var dev := device
		if dev == -99:
			var pads := Input.get_connected_joypads()
			dev = pads[0] if not pads.is_empty() else -1
		if is_ps(dev):
			if colors.has(label):
				var c2 := pos + Vector2(h * 0.5, -px * 0.36)
				ci.draw_circle(c2, h * 0.5 + maxf(2.0, px * 0.1), INK)
				ci.draw_circle(c2, h * 0.5, Color(0.16, 0.17, 0.24))
				var gr := h * 0.24
				var lw := maxf(1.5, px * 0.13)
				match label:
					"A":
						var col := Color(0.45, 0.7, 1.0)
						ci.draw_line(c2 + Vector2(-gr, -gr), c2 + Vector2(gr, gr), col, lw)
						ci.draw_line(c2 + Vector2(-gr, gr), c2 + Vector2(gr, -gr), col, lw)
					"B":
						ci.draw_arc(c2, gr, 0, TAU, 20, Color(1.0, 0.4, 0.45), lw)
					"X":
						ci.draw_rect(Rect2(c2 - Vector2(gr, gr) * 0.9, Vector2(gr, gr) * 1.8), Color(1.0, 0.5, 0.8), false, lw)
					"Y":
						var tri := PackedVector2Array([c2 + Vector2(0, -gr * 1.05), c2 + Vector2(gr, gr * 0.75), c2 + Vector2(-gr, gr * 0.75), c2 + Vector2(0, -gr * 1.05)])
						ci.draw_polyline(tri, Color(0.35, 0.95, 0.7), lw)
				return h
			label = {"LB": "L1", "RB": "R1", "LT": "L2", "RT": "R2", "START": "OPTIONS", "BACK": "SHARE"}.get(label, label)
	if colors.has(label) and not is_key:
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
