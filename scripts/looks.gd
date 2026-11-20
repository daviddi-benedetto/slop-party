extends RefCounted
## Visual themes: one setting that restyles every map and the lobby. A theme
## picks the time of day ("base": day / sunset / night) and then overrides
## the lighting, the sky, the neon colours, the colour of every generated
## surface ("grade") and the final colour grading ("post"). The lobby stage
## (stage.gd) and the lobby overlay (lobby.gd) take their colours from the
## same entry ("stage", "ui"), so the menu always matches the matches.
##
## Keys (all optional except name and base):
##   sky        sky.gd parameters (top, horizon, ground, sun, cloud_color,
##              clouds, stars, aurora); replaces the map's own sky colours
##   sun_color, sun_energy, sun_pitch, ambient, exposure, glow (bloom HDR
##              threshold), neon (emission scale), lights (point light
##              scale), fog, fog_mult: the same keys as map.DAY / SUNSET
##   ambient_color        mixed half-and-half with the sky's ambient light
##              (night themes: keeps shaded walls readable)
##   accent_a, accent_b   neon colours (strips, signs, skyline bands)
##   window, lamp         emission colour of lit windows / lamp heads
##   grade      {sat, val, tint, pastel}: applied to every generated
##              surface colour (map._mat, leaves, grass)
##   post       {saturation, contrast, brightness, shadows, highlights,
##              glow_intensity, glow_bloom}: Environment adjustments; shadows /
##              highlights become a colour-correction ramp (split toning)
##   shadow     sun shadow opacity
##   wet        0-1: rain-slick ground with puddles that reflect (surface.gd,
##              screen-space reflections when the option allows)
##   mist       height fog density: low mist pooling near the ground
##   ui         lobby overlay colours: logo_a, logo_b, panel, value, vignette
##   stage      lobby backyard (stage.gd): day, sky, ring_a / ring_b (party
##              lights), lawn, fence, hill, mountain, city (a neon skyline
##              instead of mountains: tower, band_a, band_b), sun_color,
##              sun_energy, sun_pitch, ambient, ambient_color, exposure, fog,
##              glow
##
## To add a theme: add an entry to LOOKS and its key to ORDER.

const ORDER := ["classic", "toy", "warm", "cyberpunk", "synthwave", "spooky", "moonlit"]
const RANDOM := "random"

const LOOKS := {
	# Each map's own colours in clear daylight.
	"classic": {"name": "CLASSIC", "base": "day",
		"ui": {"logo_a": Color(1.0, 0.62, 0.2), "logo_b": Color(0.3, 0.75, 1.0), "panel": Color(0.075, 0.085, 0.14, 0.92),
			"value": Color(1.0, 0.62, 0.2), "vignette": Color(0.0, 0.0, 0.03, 0.55)},
		"stage": {"day": true},
	},
	# A toy box: pastel paint, bright soft daylight, gentle shadows.
	"toy": {"name": "TOY", "base": "day",
		"sky": {"top": Color(0.42, 0.68, 1.0), "horizon": Color(1.0, 0.86, 0.93), "ground": Color(0.75, 0.7, 0.8),
			"sun": Color(1.0, 0.97, 0.88), "cloud_color": Color(1.0, 1.0, 1.0), "clouds": 0.7, "stars": 0.0, "aurora": 0.0},
		"sun_color": Color(1.0, 0.97, 0.92), "sun_energy": 2.0, "sun_pitch": -60.0, "ambient": 1.4, "exposure": 0.92,
		"glow": 1.6, "neon": 0.4, "lights": 0.2, "fog": Color(0.66, 0.76, 0.95), "fog_mult": 0.25,
		"accent_a": Color(1.0, 0.5, 0.74), "accent_b": Color(0.42, 0.95, 0.82),
		"grade": {"sat": 0.95, "val": 1.04, "pastel": 0.24},
		"post": {"saturation": 1.15, "contrast": 0.97, "brightness": 1.05, "shadows": Color(0.1, 0.07, 0.14), "highlights": Color(1.0, 1.0, 1.0)},
		"shadow": 0.45,
		"ui": {"logo_a": Color(1.0, 0.52, 0.72), "logo_b": Color(0.4, 0.86, 0.8), "panel": Color(0.36, 0.24, 0.46, 0.9),
			"value": Color(1.0, 0.84, 0.4), "vignette": Color(0.5, 0.3, 0.55, 0.3)},
		"stage": {"day": true,
			"sky": {"top": Color(0.42, 0.68, 1.0), "horizon": Color(1.0, 0.86, 0.93), "ground": Color(0.8, 0.72, 0.85),
				"sun": Color(1.0, 0.97, 0.88), "cloud_color": Color(1.0, 1.0, 1.0), "clouds": 0.75, "stars": 0.0, "aurora": 0.0},
			"floor": Color(0.86, 0.68, 0.8), "ring_a": Color(1.0, 0.5, 0.74), "ring_b": Color(0.42, 0.95, 0.82),
			"tower": [Color(0.74, 0.66, 1.0), Color(1.0, 0.78, 0.6), Color(0.6, 0.9, 0.84), Color(1.0, 0.92, 0.6)],
			"band_a": Color(1.0, 1.0, 1.0), "band_b": Color(1.0, 0.6, 0.8),
			"sun_color": Color(1.0, 0.97, 0.92), "sun_energy": 1.5, "ambient": 0.8, "exposure": 0.85, "fog": Color(0.8, 0.82, 1.0),
			"glow": 1.8},
	},
	# Golden hour: low amber sun, peach and lilac sky, soft contrast.
	"warm": {"name": "WARM", "base": "sunset",
		"sky": {"top": Color(0.34, 0.27, 0.5), "horizon": Color(1.0, 0.62, 0.38), "ground": Color(0.3, 0.17, 0.14),
			"sun": Color(1.0, 0.74, 0.45), "cloud_color": Color(0.96, 0.62, 0.52), "clouds": 0.6, "stars": 0.0, "aurora": 0.0},
		"sun_color": Color(1.0, 0.74, 0.5), "sun_energy": 2.0, "sun_pitch": -11.0, "ambient": 1.5, "exposure": 1.1,
		"glow": 1.2, "neon": 0.6, "lights": 0.8, "fog": Color(0.86, 0.56, 0.44), "fog_mult": 0.8,
		"accent_a": Color(1.0, 0.62, 0.3), "accent_b": Color(1.0, 0.84, 0.52), "window": Color(1.0, 0.72, 0.4),
		"grade": {"sat": 0.95, "tint": Color(1.05, 0.98, 0.9)},
		"post": {"saturation": 1.02, "contrast": 0.94, "brightness": 1.03, "shadows": Color(0.13, 0.05, 0.09), "highlights": Color(1.0, 0.95, 0.86),
			"glow_bloom": 0.1},
		"ui": {"logo_a": Color(1.0, 0.66, 0.32), "logo_b": Color(1.0, 0.86, 0.56), "panel": Color(0.22, 0.12, 0.16, 0.9),
			"value": Color(1.0, 0.76, 0.42), "vignette": Color(0.2, 0.06, 0.04, 0.45)},
		"stage": {"day": true,
			"sky": {"top": Color(0.34, 0.27, 0.5), "horizon": Color(1.0, 0.62, 0.38), "ground": Color(0.3, 0.17, 0.14),
				"sun": Color(1.0, 0.74, 0.45), "cloud_color": Color(0.96, 0.62, 0.52), "clouds": 0.6, "stars": 0.0, "aurora": 0.0},
			"floor": Color(0.42, 0.26, 0.2), "ring_a": Color(1.0, 0.6, 0.26), "ring_b": Color(1.0, 0.86, 0.5),
			"tower": [Color(0.4, 0.26, 0.3), Color(0.5, 0.3, 0.26), Color(0.34, 0.24, 0.32)],
			"band_a": Color(1.0, 0.72, 0.4), "band_b": Color(1.0, 0.86, 0.56),
			"sun_color": Color(1.0, 0.72, 0.48), "sun_energy": 1.8, "ambient": 1.5, "exposure": 1.1, "fog": Color(0.7, 0.42, 0.34),
			"sun_pitch": -12.0},
	},
	# Neon city at night: magenta haze, hot pink and cyan everything, big bloom.
	"cyberpunk": {"name": "CYBERPUNK", "base": "night",
		"sky": {"top": Color(0.03, 0.0, 0.08), "horizon": Color(0.42, 0.05, 0.4), "ground": Color(0.03, 0.0, 0.05),
			"sun": Color(0.55, 0.9, 1.0), "cloud_color": Color(0.24, 0.04, 0.3), "clouds": 0.6, "stars": 0.35, "aurora": 0.0},
		"sun_color": Color(0.6, 0.66, 1.0), "sun_energy": 1.2, "sun_pitch": -48.0, "ambient": 3.6, "exposure": 1.45,
		"glow": 1.0, "neon": 1.8, "lights": 1.25, "fog": Color(0.22, 0.03, 0.26), "fog_mult": 1.3,
		"ambient_color": Color(0.36, 0.22, 0.48), "wet": 1.0,
		"accent_a": Color(1.0, 0.12, 0.72), "accent_b": Color(0.08, 0.9, 1.0), "window": Color(0.2, 0.9, 1.0), "lamp": Color(1.0, 0.3, 0.85),
		"grade": {"sat": 0.8, "val": 1.0, "tint": Color(0.92, 0.88, 1.06)},
		"post": {"saturation": 1.25, "contrast": 1.0, "brightness": 1.03, "shadows": Color(0.11, 0.04, 0.19), "highlights": Color(1.0, 0.95, 1.0),
			"glow_intensity": 0.8, "glow_bloom": 0.05},
		"ui": {"logo_a": Color(1.0, 0.2, 0.75), "logo_b": Color(0.15, 0.92, 1.0), "panel": Color(0.07, 0.02, 0.12, 0.92),
			"value": Color(0.2, 0.95, 1.0), "vignette": Color(0.12, 0.0, 0.14, 0.6)},
		"stage": {"day": false, "city": true, "ambient_color": Color(0.42, 0.26, 0.56),
			"sky": {"top": Color(0.03, 0.0, 0.08), "horizon": Color(0.45, 0.05, 0.42), "ground": Color(0.03, 0.0, 0.05),
				"sun": Color(0.55, 0.9, 1.0), "cloud_color": Color(0.26, 0.04, 0.32), "clouds": 0.6, "stars": 0.4, "aurora": 0.0},
			"floor": Color(0.05, 0.02, 0.09), "ring_a": Color(1.0, 0.12, 0.72), "ring_b": Color(0.08, 0.9, 1.0),
			"tower": [Color(0.12, 0.08, 0.2)], "band_a": Color(1.0, 0.12, 0.72), "band_b": Color(0.08, 0.9, 1.0),
			"sun_color": Color(0.66, 0.6, 1.0), "sun_energy": 1.2, "ambient": 2.0, "exposure": 1.3, "fog": Color(0.2, 0.02, 0.24),
			"glow": 1.2},
	},
	# A retro synth sunset: a pink sun on a violet sky, teal and pink neon.
	"synthwave": {"name": "SYNTHWAVE", "base": "sunset",
		"sky": {"top": Color(0.12, 0.03, 0.3), "horizon": Color(1.0, 0.34, 0.6), "ground": Color(0.14, 0.03, 0.2),
			"sun": Color(1.0, 0.5, 0.7), "cloud_color": Color(0.5, 0.18, 0.5), "clouds": 0.4, "stars": 0.5, "aurora": 0.0},
		"sun_color": Color(1.0, 0.56, 0.76), "sun_energy": 1.8, "sun_pitch": -8.0, "ambient": 1.7, "exposure": 1.15, "wet": 0.7,
		"glow": 1.0, "neon": 1.5, "lights": 1.0, "fog": Color(0.5, 0.18, 0.46), "fog_mult": 0.9,
		"accent_a": Color(1.0, 0.28, 0.78), "accent_b": Color(0.2, 1.0, 0.92), "window": Color(1.0, 0.45, 0.8), "lamp": Color(0.3, 1.0, 0.95),
		"grade": {"sat": 0.9, "tint": Color(1.0, 0.9, 1.06)},
		"post": {"saturation": 1.2, "contrast": 1.0, "brightness": 1.03, "shadows": Color(0.1, 0.02, 0.17), "highlights": Color(1.0, 0.94, 1.0),
			"glow_intensity": 0.8},
		"ui": {"logo_a": Color(1.0, 0.36, 0.78), "logo_b": Color(0.3, 1.0, 0.92), "panel": Color(0.14, 0.04, 0.22, 0.92),
			"value": Color(1.0, 0.5, 0.85), "vignette": Color(0.16, 0.02, 0.2, 0.5)},
		"stage": {"day": true,
			"sky": {"top": Color(0.12, 0.03, 0.3), "horizon": Color(1.0, 0.34, 0.6), "ground": Color(0.14, 0.03, 0.2),
				"sun": Color(1.0, 0.5, 0.7), "cloud_color": Color(0.5, 0.18, 0.5), "clouds": 0.4, "stars": 0.6, "aurora": 0.0},
			"floor": Color(0.1, 0.03, 0.16), "ring_a": Color(1.0, 0.28, 0.78), "ring_b": Color(0.2, 1.0, 0.92),
			"tower": [Color(0.12, 0.04, 0.2)], "band_a": Color(1.0, 0.28, 0.78), "band_b": Color(0.2, 1.0, 0.92),
			"sun_color": Color(1.0, 0.56, 0.76), "sun_energy": 1.6, "ambient": 1.6, "exposure": 1.15, "fog": Color(0.4, 0.12, 0.4),
			"sun_pitch": -8.0},
	},
	# Halloween night: a big pale moon, green haze, pumpkin-orange lights.
	"spooky": {"name": "SPOOKY", "base": "night",
		"sky": {"top": Color(0.02, 0.03, 0.03), "horizon": Color(0.17, 0.27, 0.12), "ground": Color(0.02, 0.03, 0.02),
			"sun": Color(0.95, 1.0, 0.75), "cloud_color": Color(0.12, 0.15, 0.1), "clouds": 0.8, "stars": 0.6, "aurora": 0.0},
		"sun_color": Color(0.72, 0.88, 0.72), "sun_energy": 1.2, "sun_pitch": -40.0, "ambient": 4.0, "exposure": 1.5,
		"glow": 1.0, "neon": 1.3, "lights": 1.3, "fog": Color(0.12, 0.2, 0.1), "fog_mult": 1.6,
		"ambient_color": Color(0.18, 0.24, 0.17), "mist": 0.5,
		"accent_a": Color(1.0, 0.48, 0.06), "accent_b": Color(0.55, 1.0, 0.2), "window": Color(1.0, 0.55, 0.12), "lamp": Color(0.6, 1.0, 0.3),
		"grade": {"sat": 0.78, "val": 0.95, "tint": Color(0.95, 1.0, 0.92)},
		"post": {"saturation": 1.05, "contrast": 1.06, "brightness": 1.02, "shadows": Color(0.04, 0.08, 0.04), "highlights": Color(1.0, 0.98, 0.9)},
		"ui": {"logo_a": Color(1.0, 0.5, 0.08), "logo_b": Color(0.6, 1.0, 0.25), "panel": Color(0.06, 0.08, 0.05, 0.92),
			"value": Color(1.0, 0.55, 0.12), "vignette": Color(0.02, 0.06, 0.0, 0.6)},
		"stage": {"day": false,
			"sky": {"top": Color(0.02, 0.03, 0.03), "horizon": Color(0.17, 0.27, 0.12), "ground": Color(0.02, 0.03, 0.02),
				"sun": Color(0.95, 1.0, 0.75), "cloud_color": Color(0.12, 0.15, 0.1), "clouds": 0.8, "stars": 0.7, "aurora": 0.0},
			"floor": Color(0.06, 0.07, 0.05), "ring_a": Color(1.0, 0.48, 0.06), "ring_b": Color(0.55, 1.0, 0.2),
			"tower": [Color(0.04, 0.05, 0.04)], "band_a": Color(1.0, 0.48, 0.06), "band_b": Color(0.55, 1.0, 0.2),
			"sun_color": Color(0.72, 0.9, 0.72), "sun_energy": 1.1, "ambient": 1.8, "exposure": 1.3, "fog": Color(0.1, 0.18, 0.08)},
	},
	# A calm clear night: each map's own moonlight, stars and lit windows.
	"moonlit": {"name": "MOONLIT", "base": "night", "mist": 0.35,
		"ui": {"logo_a": Color(0.75, 0.85, 1.0), "logo_b": Color(0.45, 0.65, 1.0), "panel": Color(0.05, 0.07, 0.14, 0.92),
			"value": Color(0.75, 0.88, 1.0), "vignette": Color(0.0, 0.02, 0.08, 0.6)},
		"stage": {"day": false, "ring_a": Color(0.6, 0.75, 1.0), "ring_b": Color(1.0, 0.86, 0.6),
			"band_a": Color(1.0, 0.82, 0.55), "band_b": Color(0.6, 0.75, 1.0)},
	},
}


## The theme entry for a key ("random" picks one of ORDER).
static func get_look(key: String) -> Dictionary:
	if key == RANDOM or not LOOKS.has(key):
		key = ORDER[randi() % ORDER.size()]
	var d: Dictionary = LOOKS[key].duplicate()
	d["key"] = key
	return d


## The theme the lobby has selected (index into lobby options).
static func lobby_key() -> String:
	var opts := options()
	return opts[clampi(int(Settings.lobby.get("theme", 0)), 0, opts.size() - 1)]


## Lobby options: every theme, then RANDOM.
static func options() -> Array:
	return ORDER + [RANDOM]


static func label(key: String) -> String:
	return "RANDOM" if key == RANDOM else LOOKS.get(key, LOOKS.classic).name


## A surface colour pushed through a theme's grade.
static func grade(look: Dictionary, c: Color) -> Color:
	var g: Dictionary = look.get("grade", {})
	if g.is_empty():
		return c
	var o := Color.from_hsv(c.h, clampf(c.s * g.get("sat", 1.0), 0.0, 1.0), clampf(c.v * g.get("val", 1.0), 0.0, 1.0), c.a)
	var t: Color = g.get("tint", Color.WHITE)
	o = Color(minf(o.r * t.r, 1.0), minf(o.g * t.g, 1.0), minf(o.b * t.b, 1.0), c.a)
	o = o.lerp(Color(1, 1, 1, c.a), g.get("pastel", 0.0))
	return o


## Colour grading on an Environment: adjustments plus a split-toning ramp.
static func apply_post(look: Dictionary, env: Environment) -> void:
	var p: Dictionary = look.get("post", {})
	if p.has("saturation"):
		env.adjustment_saturation = p.saturation
	if p.has("contrast"):
		env.adjustment_contrast = p.contrast
	if p.has("brightness"):
		env.adjustment_brightness = p.brightness
	# (Themes' bloom scaled down: it was overbearing.)
	if p.has("glow_intensity"):
		env.glow_intensity = p.glow_intensity * 0.6
	if p.has("glow_bloom"):
		env.glow_bloom = p.glow_bloom * 0.35
	if p.has("shadows"):
		var g := Gradient.new()
		g.set_color(0, p.shadows)
		g.set_color(1, p.get("highlights", Color.WHITE))
		var tex := GradientTexture1D.new()
		tex.gradient = g
		tex.width = 256
		env.adjustment_color_correction = tex
