extends Node3D
## An arena. Everything is generated in code: geometry, materials, textures,
## lighting, sky, scenery, spawn points, pickup spots, jump pads, hazards and
## the bot nav graph.
##
## MAPS lists the arenas; build(index) makes one. Each map is a layout
## function (geometry) plus a THEMES entry (materials, sky, light, scenery):
##   0  NEON YARD   medium  64 x 48   night container yard: concrete, steel,
##                                    red brick, coloured shipping containers,
##                                    gantry cranes, neon signs
##   1  EMBER PIT   small   36 x 28   foundry: sandstone, basalt, iron, a round
##                                    forge with a chimney, stone arches, and
##                                    lava channels that burn
##   2  FROST LINE  large   88 x 64   polar outpost: snow, ice blocks, white
##                                    lab panels, orange supply crates, pines
##
## Materials: a theme's "mats" maps a material key to
## [colour, texture kind, tiles per metre, roughness, metallic]. Texture kinds
## are generated in _tex() (albedo + normal map, some with emission): concrete,
## plates, corrugated, planks, bricks, tiles, rock, lava, snow, ice, stripes.
## Every theme also gets accent_a / accent_b (emissive neon), rail, pad, dark.
##
## Layout conventions (metres, Y up): the floor is centred on the origin with
## half-extents half_x / half_z. Almost every piece is added with mirror=true,
## which also places a copy rotated 180 deg about Y ((x, z) -> (-x, -z)), so
## maps are point-symmetric and only half has to be described.
##
## Collision layers: 1 = world (this file), 2 = players.
##
## Nav graph: build_nav() samples a 2 m grid with downward ray-casts (several
## height layers, so space under decks counts too), links neighbours that are
## actually walkable, and keeps the largest connected component in an AStar3D.
## It needs no per-map data. Lava channels sit behind a kerb the link test
## rejects, so bots stay out of them.
##
## To add a map: write a _layout_xxx() function, add a THEMES entry, and
## append to MAPS (and a "mapN" track in sfx.gd if it should have its own song).

const SkyKit = preload("res://scripts/sky.gd")

const MAPS := [
	{"name": "NEON YARD", "size": "MEDIUM", "theme": "neon", "half": Vector2(32, 24), "wall": 4.5},
	{"name": "EMBER PIT", "size": "SMALL", "theme": "ember", "half": Vector2(18, 14), "wall": 4.0},
	{"name": "FROST LINE", "size": "LARGE", "theme": "frost", "half": Vector2(44, 32), "wall": 5.0},
]

const THEMES := {
	"neon": {
		"mats": {
			"ground": [Color(0.18, 0.2, 0.27), "concrete", 0.12, 0.45, 0.1],
			"path": [Color(0.27, 0.29, 0.38), "plates", 0.25, 0.35, 0.3],
			"wall": [Color(0.23, 0.28, 0.42), "plates", 0.25, 0.55, 0.2],
			"block_a": [Color(0.5, 0.54, 0.64), "concrete", 0.2, 0.6, 0.0],
			"block_b": [Color(0.62, 0.29, 0.23), "bricks", 0.4, 0.75, 0.0],
			"block_c": [Color(0.19, 0.22, 0.32), "corrugated", 0.5, 0.4, 0.5],
			"deck": [Color(0.36, 0.39, 0.47), "tiles", 0.5, 0.4, 0.5],
			"crate": [Color(0.58, 0.42, 0.25), "planks", 0.6, 0.7, 0.0],
			"c_red": [Color(0.7, 0.21, 0.17), "corrugated", 0.55, 0.5, 0.3],
			"c_blue": [Color(0.17, 0.4, 0.72), "corrugated", 0.55, 0.5, 0.3],
			"c_yellow": [Color(0.84, 0.65, 0.13), "corrugated", 0.55, 0.5, 0.3],
			"c_teal": [Color(0.1, 0.58, 0.52), "corrugated", 0.55, 0.5, 0.3],
		},
		"accent_a": Color(1.0, 0.42, 0.16), "accent_b": Color(0.15, 0.75, 1.0),
		"sky": {"top": Color(0.01, 0.015, 0.05), "horizon": Color(0.1, 0.1, 0.26), "ground": Color(0.02, 0.02, 0.05),
			"sun": Color(0.75, 0.82, 1.0), "cloud_color": Color(0.13, 0.13, 0.26), "clouds": 0.55, "stars": 1.0, "aurora": 0.0},
		"sun_color": Color(0.62, 0.72, 1.0), "sun_energy": 0.8, "sun_dir": Vector3(-50, 38, 0),
		"ambient": 0.6, "fog": Color(0.05, 0.06, 0.14), "fog_density": 0.006,
		"grass": [], "scenery": "city", "motes": [Color(0.4, 0.9, 1.0), Color(1.0, 0.6, 0.3)], "mote_rise": 0.05,
	},
	"ember": {
		"mats": {
			"ground": [Color(0.25, 0.2, 0.18), "rock", 0.1, 0.7, 0.0],
			"path": [Color(0.38, 0.27, 0.21), "tiles", 0.3, 0.55, 0.0],
			"wall": [Color(0.38, 0.25, 0.21), "bricks", 0.18, 0.8, 0.0],
			"block_a": [Color(0.66, 0.47, 0.3), "rock", 0.3, 0.75, 0.0],
			"block_b": [Color(0.32, 0.32, 0.36), "plates", 0.3, 0.4, 0.7],
			"block_c": [Color(0.17, 0.15, 0.16), "corrugated", 0.5, 0.4, 0.6],
			"deck": [Color(0.5, 0.33, 0.2), "planks", 0.5, 0.7, 0.0],
			"crate": [Color(0.6, 0.37, 0.17), "planks", 0.6, 0.7, 0.0],
			"lava": [Color(0.32, 0.11, 0.05), "lava", 0.18, 0.6, 0.0],
		},
		"accent_a": Color(1.0, 0.5, 0.1), "accent_b": Color(1.0, 0.85, 0.3),
		"sky": {"top": Color(0.03, 0.01, 0.02), "horizon": Color(0.42, 0.12, 0.05), "ground": Color(0.12, 0.03, 0.01),
			"sun": Color(1.0, 0.55, 0.25), "cloud_color": Color(0.2, 0.07, 0.05), "clouds": 0.8, "stars": 0.3, "aurora": 0.0},
		"sun_color": Color(1.0, 0.66, 0.45), "sun_energy": 0.85, "sun_dir": Vector3(-38, -60, 0),
		"ambient": 0.62, "fog": Color(0.2, 0.06, 0.03), "fog_density": 0.009,
		"grass": [], "scenery": "rocks", "motes": [Color(1.0, 0.6, 0.15), Color(1.0, 0.3, 0.1)], "mote_rise": 0.7,
	},
	"frost": {
		"mats": {
			"ground": [Color(0.56, 0.64, 0.76), "snow", 0.08, 0.85, 0.0],
			"path": [Color(0.27, 0.5, 0.64), "ice", 0.12, 0.12, 0.2],
			"wall": [Color(0.4, 0.5, 0.62), "plates", 0.25, 0.5, 0.3],
			"block_a": [Color(0.72, 0.76, 0.82), "plates", 0.3, 0.45, 0.2],
			"block_b": [Color(0.42, 0.72, 0.88), "ice", 0.25, 0.1, 0.1],
			"block_c": [Color(0.22, 0.28, 0.38), "corrugated", 0.5, 0.4, 0.5],
			"deck": [Color(0.36, 0.42, 0.5), "tiles", 0.5, 0.4, 0.5],
			"crate": [Color(0.88, 0.45, 0.12), "plates", 0.5, 0.5, 0.2],
			"pine": [Color(0.09, 0.3, 0.24), "", 1.0, 0.9, 0.0],
			"trunk": [Color(0.3, 0.2, 0.14), "", 1.0, 0.9, 0.0],
			"snowcap": [Color(0.8, 0.86, 0.95), "", 1.0, 0.9, 0.0],
		},
		"accent_a": Color(0.3, 1.0, 0.95), "accent_b": Color(0.45, 0.6, 1.0),
		"sky": {"top": Color(0.01, 0.03, 0.07), "horizon": Color(0.06, 0.2, 0.26), "ground": Color(0.02, 0.05, 0.07),
			"sun": Color(0.8, 0.95, 1.0), "cloud_color": Color(0.1, 0.18, 0.24), "clouds": 0.35, "stars": 1.0, "aurora": 1.0},
		"sun_color": Color(0.7, 0.86, 1.0), "sun_energy": 0.7, "sun_dir": Vector3(-46, 130, 0),
		"ambient": 0.42, "fog": Color(0.05, 0.12, 0.16), "fog_density": 0.005,
		"grass": [], "scenery": "ice", "motes": [Color(0.9, 0.97, 1.0), Color(0.7, 0.9, 1.0)], "mote_rise": -0.6,
	},
}

const NAV_STEP := 2.0
const LAVA_DPS := 26.0

static var _tex_cache := {}       # texture kind -> [albedo, normal, emission]

var map_index := 0
var theme := {}
var half_x := 32.0
var half_z := 24.0
var wall_h := 4.5

var spawn_points: Array = []      # Array of Vector3
var pickup_spots: Array = []      # [["weapon" | "health", Vector3], ...] read by game.gd
var nav := AStar3D.new()
var nav_ready := false
var _nav_ids := PackedInt64Array()
var _body: StaticBody3D
var _mats := {}
var _box_cache := {}
var _unit_sphere: SphereMesh
var _rng := RandomNumberGenerator.new()
var _env: Environment
var _sun: DirectionalLight3D
var _hazards: Array = []          # Area3D volumes that burn whoever stands in them

# Animated decorations.
var _pad_rings: Array = []        # [mesh_instance, material, phase]
var _time := 0.0


func build(index := 0) -> void:
	map_index = clampi(index, 0, MAPS.size() - 1)
	var info: Dictionary = MAPS[map_index]
	theme = THEMES[info.theme]
	half_x = info.half.x
	half_z = info.half.y
	wall_h = info.wall
	_rng.seed = 20240607 + map_index
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_unit_sphere = SphereMesh.new()
	_unit_sphere.radius = 1.0
	_unit_sphere.height = 2.0
	_unit_sphere.radial_segments = 20
	_unit_sphere.rings = 10
	_make_materials()
	_build_environment()
	_build_shell()
	match map_index:
		1: _layout_pit()
		2: _layout_frost()
		_: _layout_yard()
	_build_scenery()


func _process(delta: float) -> void:
	_time += delta
	for r in _pad_rings:
		var t := fmod(_time * 0.8 + r[2], 1.0)
		r[0].position.y = 0.15 + t * 1.6
		r[0].scale = Vector3.ONE * (1.0 - t * 0.35)
		r[1].albedo_color.a = (1.0 - t) * 0.8


func _physics_process(delta: float) -> void:
	for area in _hazards:
		for body in area.get_overlapping_bodies():
			if body.has_method("take_damage") and body.alive:
				body.take_damage(LAVA_DPS * delta, null, true)
				body.hurt_flash = maxf(body.hurt_flash, 0.6)


# --------------------------------------------------------------------------
# Materials / procedural textures
# --------------------------------------------------------------------------

func _make_materials() -> void:
	for key in theme.mats:
		var d: Array = theme.mats[key]
		_mats[key] = _mat(d[0], d[1], d[2], d[3], d[4])
		# Rotated props keep their pattern aligned to themselves.
		if key.begins_with("c_") or key == "crate":
			_mats[key].uv1_world_triplanar = false
	_mats["dark"] = _mat(Color(0.06, 0.06, 0.09), "", 1.0, 0.5, 0.3)
	_mats["accent_a"] = _neon(theme.accent_a, 1.7)
	_mats["accent_b"] = _neon(theme.accent_b, 1.7)
	_mats["rail"] = _neon(theme.accent_b, 0.9)
	_mats["pad"] = _neon(Color(0.3, 1.0, 0.85), 2.0)
	_mats["beacon"] = _neon(Color(1.0, 0.2, 0.2), 3.0)
	# Hazard stripes: dark with glowing bands in the theme's accent colour.
	var st: Array = _tex("stripes")
	var stripes := StandardMaterial3D.new()
	stripes.albedo_color = theme.accent_a.lerp(Color.WHITE, 0.15)
	stripes.albedo_texture = st[0]
	stripes.roughness = 0.5
	stripes.uv1_triplanar = true
	stripes.uv1_world_triplanar = true
	stripes.uv1_scale = Vector3.ONE * 0.7
	stripes.emission_enabled = true
	stripes.emission = theme.accent_a
	stripes.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	stripes.emission_texture = st[0]
	stripes.emission_energy_multiplier = 0.7
	_mats["stripes"] = stripes


func _mat(tint: Color, kind: String, uv_scale: float, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	if kind == "":
		return m
	var t: Array = _tex(kind)
	m.albedo_texture = t[0]
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * uv_scale
	if t[1] != null:
		m.normal_enabled = true
		m.normal_texture = t[1]
		m.normal_scale = 1.1
	if t[2] != null:
		m.emission_enabled = true
		m.emission_texture = t[2]
		m.emission_energy_multiplier = 2.4
	return m


## Emissive strip material: this is what the bloom picks up.
func _neon(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.3)
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


## Tileable 256x256 detail textures. Returns [albedo, normal, emission]; the
## albedo is greyscale and gets multiplied by the material colour. Cached for
## the whole session, so only the first match on a theme pays for them.
static func _tex(kind: String) -> Array:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	const N := 256
	const P := 16
	const G := 5
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var lattice := PackedFloat32Array()
	lattice.resize(P * P)
	for i in P * P:
		lattice[i] = rng.randf()
	var noise := func(u: float, v: float, freq: int) -> float:
		var x := u * freq
		var y := v * freq
		var x0 := int(floor(x))
		var y0 := int(floor(y))
		var fx := x - x0
		var fy := y - y0
		fx = fx * fx * (3.0 - 2.0 * fx)
		fy = fy * fy * (3.0 - 2.0 * fy)
		var a := lattice[(y0 % freq) * P + (x0 % freq)]
		var b := lattice[(y0 % freq) * P + ((x0 + 1) % freq)]
		var c := lattice[((y0 + 1) % freq) * P + (x0 % freq)]
		var d := lattice[((y0 + 1) % freq) * P + ((x0 + 1) % freq)]
		return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)
	# Cell centres for Voronoi patterns (rock, lava, ice cracks).
	var cellular := kind == "rock" or kind == "lava" or kind == "ice"
	var seeds := PackedVector2Array()
	for i in G * G:
		seeds.append(Vector2(rng.randf(), rng.randf()))

	var img := Image.create(N, N, true, Image.FORMAT_RGB8)
	var himg := Image.create(N, N, false, Image.FORMAT_RGB8)
	var eimg: Image = null
	if kind == "lava":
		eimg = Image.create(N, N, true, Image.FORMAT_RGB8)
	for py in N:
		for px in N:
			var u := float(px) / N
			var v := float(py) / N
			var n: float = noise.call(u, v, 4) * 0.65 + noise.call(u, v, 8) * 0.35
			var val := 0.82 + n * 0.18
			var hgt := 0.6 + n * 0.4
			var edge := 1.0
			var cell_id := 0
			if cellular:
				var gx := u * G
				var gy := v * G
				var d1 := 9.0
				var d2 := 9.0
				for oy in [-1, 0, 1]:
					for ox in [-1, 0, 1]:
						var cx: int = int(floor(gx)) + ox
						var cy: int = int(floor(gy)) + oy
						var id := posmod(cy, G) * G + posmod(cx, G)
						var d := Vector2(gx, gy).distance_to(Vector2(cx, cy) + seeds[id])
						if d < d1:
							d2 = d1
							d1 = d
							cell_id = id
						elif d < d2:
							d2 = d
				edge = d2 - d1
			match kind:
				"concrete":
					val = 0.76 + n * 0.24 - 0.07 * noise.call(u, v, 16)
					if px % 128 < 2 or py % 128 < 2:
						val *= 0.75
						hgt = 0.0
				"plates":
					var lx := px % 128
					var ly := py % 128
					if lx < 3 or ly < 3:
						val *= 0.55
						hgt = 0.0
					else:
						hgt = 0.7
						for corner in [Vector2(14, 14), Vector2(114, 14), Vector2(14, 114), Vector2(114, 114)]:
							if Vector2(lx, ly).distance_to(corner) < 4.5:
								val *= 1.25
								hgt = 1.0
				"corrugated":
					var ridge := 0.5 + 0.5 * sin(u * TAU * 16.0)
					val = 0.6 + 0.4 * ridge + n * 0.06
					hgt = ridge
					if py % 128 < 3:
						val *= 0.6
						hgt = 0.0
				"planks":
					var plank := py / 32
					val *= 0.82 + 0.18 * lattice[plank % (P * P)]
					hgt = 0.7 + 0.3 * n
					if py % 32 < 3 or (px + plank * 67) % 128 < 3:
						val *= 0.55
						hgt = 0.0
				"bricks":
					var row := py / 32
					var bx := (px + (row % 2) * 32) % 64
					val *= 0.8 + 0.2 * lattice[(row * 5 + ((px + (row % 2) * 32) / 64) * 3) % (P * P)]
					hgt = 0.75 + 0.25 * n
					if py % 32 < 3 or bx < 3:
						val *= 0.5
						hgt = 0.0
				"tiles":
					var tx := px % 64
					var ty := py % 64
					val = 0.78 + 0.16 * lattice[((py / 64) * 7 + (px / 64) * 3) % (P * P)] + 0.06 * ((px / 64 + py / 64) % 2)
					hgt = 0.8
					if tx < 3 or ty < 3:
						val *= 0.5
						hgt = 0.0
				"rock":
					val = 0.6 + 0.3 * lattice[cell_id % (P * P)] + n * 0.14
					hgt = clampf(edge * 3.0, 0.0, 1.0)
					if edge < 0.05:
						val *= 0.5
				"lava":
					var glow := 1.0 - smoothstep(0.0, 0.16, edge)
					val = 0.5 + 0.3 * n
					hgt = clampf(edge * 3.0, 0.0, 1.0)
					eimg.set_pixel(px, py, Color(1.0, 0.42 + 0.3 * glow, 0.08) * (glow + 0.06))
				"snow":
					val = 0.86 + n * 0.14
					hgt = n
				"ice":
					val = 0.8 + 0.14 * n
					hgt = 0.8
					if edge < 0.03:
						val = 1.0
						hgt = 0.0
				"stripes":
					val = 1.0 if ((px + py) % 128) < 52 else 0.05
			val = clampf(val, 0.0, 1.0)
			img.set_pixel(px, py, Color(val, val, val))
			himg.set_pixel(px, py, Color(hgt, hgt, hgt))
	img.generate_mipmaps()
	var normal: ImageTexture = null
	if kind != "stripes":
		himg.bump_map_to_normal_map(2.5 if kind == "snow" or kind == "concrete" else 5.0)
		himg.generate_mipmaps(true)
		normal = ImageTexture.create_from_image(himg)
	var emission: ImageTexture = null
	if eimg != null:
		eimg.generate_mipmaps()
		emission = ImageTexture.create_from_image(eimg)
	var out := [ImageTexture.create_from_image(img), normal, emission]
	_tex_cache[kind] = out
	return out


# --------------------------------------------------------------------------
# Lighting
# --------------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = SkyKit.make(theme.sky)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = theme.ambient * 7.2
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.55
	env.tonemap_white = 4.0
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(2, 1.0)
	env.set_glow_level(4, 0.7)
	env.set_glow_level(6, 0.25)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.06
	env.fog_enabled = true
	env.fog_light_color = theme.fog
	env.fog_density = theme.fog_density
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = theme.sun_dir
	sun.light_color = theme.sun_color
	sun.light_energy = theme.sun_energy * 1.7
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.06
	add_child(sun)
	_env = env
	_sun = sun
	_on_settings()
	Settings.changed.connect(_on_settings)


func _on_settings() -> void:
	Settings.apply_environment(_env, _sun)


## A coloured point light with no shadows: cheap, and it is what sells the
## neon. Mirrored like geometry.
func _glow(pos: Vector3, col: Color, radius := 8.0, energy := 1.6, mirror := true) -> void:
	var spots := [pos]
	if mirror:
		spots.append(Vector3(-pos.x, pos.y, -pos.z))
	for s in spots:
		var l := OmniLight3D.new()
		l.position = s
		l.light_color = col
		l.light_energy = energy * 0.8
		l.omni_range = radius
		l.omni_attenuation = 1.6
		add_child(l)


# --------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------

## Floor, paths and perimeter. The visible wall is low; its collider is tall
## so nobody can jump out.
func _build_shell() -> void:
	var w := half_x * 2.0
	var d := half_z * 2.0
	_collider(Vector3(0, -0.5, 0), Vector3(w + 2, 1, d + 2))
	_visual(Vector3(0, -0.5, 0), Vector3(w + 2, 1, d + 2), "ground")
	_visual(Vector3(0, 0.006, 0), Vector3(w, 0.012, 7), "path")
	_visual(Vector3(0, 0.008, 0), Vector3(7, 0.012, d), "path")
	for sgn in [1.0, -1.0]:
		_collider(Vector3(0, 8, sgn * (half_z + 0.5)), Vector3(w + 2, 16, 1))
		_collider(Vector3(sgn * (half_x + 0.5), 8, 0), Vector3(1, 16, d + 2))
	_box(Vector3(0, wall_h * 0.5, half_z + 0.5), Vector3(w + 2, wall_h, 1), "wall", true, 0.0, false)
	_box(Vector3(half_x + 0.5, wall_h * 0.5, 0), Vector3(1, wall_h, d + 2), "wall", true, 0.0, false)
	_box(Vector3(0, wall_h + 0.04, half_z + 0.08), Vector3(w + 0.3, 0.1, 0.16), "accent_a", true, 0.0, false)
	_box(Vector3(half_x + 0.08, wall_h + 0.04, 0), Vector3(0.16, 0.1, d + 0.3), "accent_a", true, 0.0, false)
	_box(Vector3(0, 0.12, half_z + 0.02), Vector3(w, 0.16, 0.14), "accent_b", true, 0.0, false)
	_box(Vector3(half_x + 0.02, 0.12, 0), Vector3(0.14, 0.16, d), "accent_b", true, 0.0, false)
	# Path edge lines.
	for off in [3.5, -3.5]:
		_visual(Vector3(0, 0.02, off), Vector3(w, 0.03, 0.08), "rail")
		_visual(Vector3(off, 0.02, 0), Vector3(0.08, 0.03, d), "rail")


func _collider(pos: Vector3, size: Vector3, yaw := 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	_body.add_child(cs)


func _visual(pos: Vector3, size: Vector3, mat: String, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _rounded_box(size)
	mi.material_override = _mats[mat]
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	if mat.begins_with("accent") or mat == "rail" or mat == "pad":
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _box(pos: Vector3, size: Vector3, mat: String, mirror := true, yaw := 0.0, collide := true) -> void:
	var copies := [[pos, yaw]]
	if mirror:
		copies.append([Vector3(-pos.x, pos.y, -pos.z), yaw + PI])
	for c in copies:
		if collide:
			_collider(c[0], size, c[1])
		_visual(c[0], size, mat, c[1])
		if mat == "crate":
			# A glowing band around each crate.
			_visual(c[0], Vector3(size.x + 0.04, 0.1, size.z + 0.04), "accent_a", c[1])


## An upright cylinder standing on `base`.
func _cyl(base: Vector3, radius: float, height: float, mat: String, mirror := true, collide := true) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 32
	var spots := [base]
	if mirror:
		spots.append(Vector3(-base.x, base.y, -base.z))
	for s in spots:
		if collide:
			var shape := CylinderShape3D.new()
			shape.radius = radius
			shape.height = height
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.position = s + Vector3(0, height * 0.5, 0)
			_body.add_child(cs)
		var mi := _prop(mesh, mat, s + Vector3(0, height * 0.5, 0))
		if mat.begins_with("accent") or mat == "lava":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A shipping container resting on `base` (its floor centre), with dark end frames.
func _container(base: Vector3, yaw: float, mat: String, length := 6.0, mirror := true) -> void:
	var c := base + Vector3(0, 1.3, 0)
	_box(c, Vector3(length, 2.6, 2.5), mat, mirror, yaw)
	for sgn in [1.0, -1.0]:
		var off := Basis(Vector3.UP, yaw) * Vector3(sgn * (length * 0.5 - 0.06), 0, 0)
		_box(c + off, Vector3(0.18, 2.66, 2.56), "dark", mirror, yaw, false)


## A glowing wall sign (visual only) with a matching light.
func _sign(pos: Vector3, size: Vector3, mat: String, mirror := true) -> void:
	_box(pos, size + Vector3(0.3, 0.3, 0.3) * Vector3(1.0 if size.x > 0.2 else 0.0, 1.0, 1.0 if size.z > 0.2 else 0.0), "dark", mirror, 0.0, false)
	var inward := Vector3(-signf(pos.x) if size.x <= 0.2 else 0.0, 0, -signf(pos.z) if size.z <= 0.2 else 0.0)
	_box(pos + inward * 0.06, size, mat, mirror, 0.0, false)
	_glow(pos + inward * 1.5, theme.accent_a if mat == "accent_a" else theme.accent_b, 9.0, 1.4, mirror)


## Box mesh with slightly rounded edges, built at its real size so the bevel
## radius is not distorted by scaling. Cached per size.
func _rounded_box(size: Vector3) -> ArrayMesh:
	var key := "%.3f,%.3f,%.3f" % [size.x, size.y, size.z]
	if _box_cache.has(key):
		return _box_cache[key]
	const SEG := 2
	var h := size * 0.5
	var r := minf(0.07, minf(size.x, minf(size.y, size.z)) * 0.3)
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.BACK, Vector3.UP],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := (h - Vector3.ONE * r)
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var hn := absf(n.dot(h))
		var cu := _edge_coords(absf(u.dot(h)), r, SEG)
		var cv := _edge_coords(absf(v.dot(h)), r, SEG)
		var grid: Array = []
		var norms: Array = []
		for a in cu:
			for b in cv:
				var p: Vector3 = n * hn + u * a + v * b
				var core := Vector3(clampf(p.x, -inner.x, inner.x), clampf(p.y, -inner.y, inner.y), clampf(p.z, -inner.z, inner.z))
				var d := (p - core).normalized()
				grid.append(core + d * r)
				norms.append(d)
		var w := cv.size()
		for i in cu.size() - 1:
			for j in w - 1:
				# u x v = n, so (00, 10, 11) is counter-clockwise from outside;
				# Godot front faces are clockwise.
				for idx in [i * w + j, (i + 1) * w + j + 1, (i + 1) * w + j, i * w + j, i * w + j + 1, (i + 1) * w + j + 1]:
					st.set_normal(norms[idx])
					st.add_vertex(grid[idx])
	var mesh := st.commit()
	_box_cache[key] = mesh
	return mesh


func _edge_coords(hh: float, r: float, seg: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in seg + 1:
		out.append(-hh + r * i / seg)
	for i in seg + 1:
		out.append(hh - r + r * i / seg)
	return out


## A solid ramp. `size` = (run, rise, width); it rises toward local +X, then is
## rotated by `yaw` about Y. `base` is the centre of its footprint.
func _wedge(base: Vector3, size: Vector3, yaw: float, mat: String, mirror := true) -> void:
	var r := size.x * 0.5
	var h := size.y
	var w := size.z * 0.5
	var a0 := Vector3(-r, 0, -w)
	var a1 := Vector3(-r, 0, w)
	var b0 := Vector3(r, 0, -w)
	var b1 := Vector3(r, 0, w)
	var c0 := Vector3(r, h, -w)
	var c1 := Vector3(r, h, w)
	var tris := [
		[a0, a1, c1], [a0, c1, c0],      # slope
		[b0, c0, c1], [b0, c1, b1],      # back
		[a0, c0, b0], [a1, b1, c1],      # sides
		[a0, b0, b1], [a0, b1, a1],      # bottom
	]
	var centroid := Vector3(r / 3.0, h / 3.0, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		var n := (p1 - p0).cross(p2 - p0).normalized()
		var outward := ((p0 + p1 + p2) / 3.0 - centroid)
		if n.dot(outward) > 0.0:
			# Counter-clockwise seen from outside; Godot wants clockwise.
			var tmp := p1
			p1 = p2
			p2 = tmp
		else:
			n = -n
		for p in [p0, p1, p2]:
			st.set_normal(n)
			st.add_vertex(p)
	var mesh := st.commit()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a0, a1, b0, b1, c0, c1])
	var copies := [Transform3D(Basis(Vector3.UP, yaw), base)]
	if mirror:
		copies.append(Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(-base.x, base.y, -base.z)))
	for xf in copies:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = xf
		_body.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mats[mat]
		mi.transform = xf
		add_child(mi)
		# Glowing side rails.
		for side in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var length := sqrt(size.x * size.x + size.y * size.y)
			rail.mesh = _rounded_box(Vector3(length, 0.12, 0.12))
			rail.material_override = _mats["accent_a"]
			rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rail.transform = xf * Transform3D(Basis(Vector3.BACK, atan2(size.y, size.x)), Vector3(0, h * 0.5 + 0.04, side * (w - 0.05)))
			add_child(rail)


func _barrel(pos: Vector3, mirror := true) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.42
	mesh.height = 1.2
	mesh.radial_segments = 18
	var band := CylinderMesh.new()
	band.top_radius = 0.45
	band.bottom_radius = 0.45
	band.height = 0.08
	band.radial_segments = 18
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = 1.2
	var spots := [pos]
	if mirror:
		spots.append(Vector3(-pos.x, pos.y, -pos.z))
	for s in spots:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = s + Vector3(0, 0.6, 0)
		_body.add_child(cs)
		_prop(mesh, "block_c", s + Vector3(0, 0.6, 0))
		_prop(band, "accent_b", s + Vector3(0, 0.95, 0))
		_prop(band, "accent_b", s + Vector3(0, 0.25, 0))


func _prop(mesh: Mesh, mat, pos: Vector3, scl := Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[mat] if mat is String else mat
	mi.position = pos
	mi.scale = scl
	(parent if parent != null else self).add_child(mi)
	return mi


## Launches any player that steps on it straight up.
func _jump_pad(pos: Vector3, power: float) -> void:
	for s in [pos, Vector3(-pos.x, pos.y, -pos.z)]:
		var base := CylinderMesh.new()
		base.top_radius = 1.15
		base.bottom_radius = 1.3
		base.height = 0.14
		_prop(base, "dark", s + Vector3(0, 0.07, 0))
		var top := CylinderMesh.new()
		top.top_radius = 0.9
		top.bottom_radius = 0.9
		top.height = 0.06
		_prop(top, "pad", s + Vector3(0, 0.16, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glow(s + Vector3(0, 1.2, 0), Color(0.3, 1.0, 0.85), 6.0, 1.6, false)
		var torus := TorusMesh.new()
		torus.inner_radius = 0.78
		torus.outer_radius = 0.9
		torus.rings = 28
		torus.ring_segments = 6
		for i in 3:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(0.4, 1.4, 1.2, 0.8)
			var holder := Node3D.new()
			holder.position = s
			add_child(holder)
			var ring := _prop(torus, m, Vector3.ZERO, Vector3.ONE, holder)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			_pad_rings.append([ring, m, i / 3.0])
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		var shape := CylinderShape3D.new()
		shape.radius = 1.0
		shape.height = 0.8
		var cs := CollisionShape3D.new()
		cs.shape = shape
		area.add_child(cs)
		area.position = s + Vector3(0, 0.4, 0)
		add_child(area)
		area.body_entered.connect(func(body):
			if body.has_method("launch"):
				body.launch(Vector3(body.velocity.x, power, body.velocity.z))
				Sfx.play_at("pad", body.global_position, -5.0))


## A glowing lava channel that burns anyone standing in it, behind a low kerb
## (the kerb is `inner` metres toward the arena centre along Z).
func _lava(center: Vector3, size: Vector3) -> void:
	for sgn in [1.0, -1.0]:
		var c := Vector3(center.x * sgn, center.y, center.z * sgn)
		_visual(c + Vector3(0, 0.03, 0), Vector3(size.x, 0.06, size.z), "lava").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var kerb := c + Vector3(0, 0.3, -sgn * (size.z * 0.5 + 0.15))
		_collider(kerb, Vector3(size.x + 0.6, 0.6, 0.3))
		_visual(kerb, Vector3(size.x + 0.6, 0.6, 0.3), "block_b")
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, 1.0, size.z)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		area.add_child(cs)
		area.position = c + Vector3(0, 0.5, 0)
		add_child(area)
		_hazards.append(area)
		for i in 3:
			_glow(c + Vector3((i - 1) * size.x * 0.33, 1.0, -sgn * 0.5), Color(1.0, 0.4, 0.1), 8.0, 1.5, false)


## A snowy pine: collidable trunk, visual branches.
func _pine(pos: Vector3, scl := 1.0) -> void:
	for s in [pos, Vector3(-pos.x, pos.y, -pos.z)]:
		var shape := CylinderShape3D.new()
		shape.radius = 0.35
		shape.height = 4.0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = s + Vector3(0, 2.0, 0)
		_body.add_child(cs)
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.18 * scl
		trunk.bottom_radius = 0.3 * scl
		trunk.height = 2.0 * scl
		_prop(trunk, "trunk", s + Vector3(0, 1.0 * scl, 0))
		for i in 3:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = (1.9 - i * 0.45) * scl
			cone.height = 2.2 * scl
			cone.radial_segments = 10
			var y := (2.3 + i * 1.25) * scl
			_prop(cone, "pine", s + Vector3(0, y, 0))
			var cap := CylinderMesh.new()
			cap.top_radius = 0.0
			cap.bottom_radius = (1.0 - i * 0.24) * scl
			cap.height = 1.15 * scl
			cap.radial_segments = 10
			_prop(cap, "snowcap", s + Vector3(0, y + 0.56 * scl, 0))


func _spawns(points: Array) -> void:
	for p in points:
		spawn_points.append(p)
		spawn_points.append(Vector3(-p.x, p.y, -p.z))


func _pickups(spots: Array) -> void:
	for spot in spots:
		pickup_spots.append(spot)
		pickup_spots.append([spot[0], Vector3(-spot[1].x, spot[1].y, -spot[1].z)])


## A small building: walls with door gaps and a flat roof. `c` is the centre of
## its floor; doors face +X and -Z.
func _hut(c: Vector3, mat: String) -> void:
	_box(c + Vector3(-4.3, 1.6, 0), Vector3(0.4, 3.2, 9), mat)
	_box(c + Vector3(0, 1.6, 4.3), Vector3(9, 3.2, 0.4), mat)
	_box(c + Vector3(4.3, 1.6, -2.85), Vector3(0.4, 3.2, 3.3), mat)
	_box(c + Vector3(4.3, 1.6, 2.85), Vector3(0.4, 3.2, 3.3), mat)
	_box(c + Vector3(4.3, 2.8, 0), Vector3(0.4, 0.8, 2.4), mat)
	_box(c + Vector3(-2.85, 1.6, -4.3), Vector3(3.3, 3.2, 0.4), mat)
	_box(c + Vector3(2.85, 1.6, -4.3), Vector3(3.3, 3.2, 0.4), mat)
	_box(c + Vector3(0, 2.8, -4.3), Vector3(2.4, 0.8, 0.4), mat)
	_box(c + Vector3(0, 3.4, 0), Vector3(9.8, 0.4, 9.8), "block_c")
	_box(c + Vector3(0, 3.4, 0), Vector3(9.9, 0.12, 9.9), "accent_b", true, 0.0, false)
	_glow(c + Vector3(0, 2.6, 0), theme.accent_a, 8.0, 1.8)


# --------------------------------------------------------------------------
# Layout 0: NEON YARD (medium) - a container yard at night
# --------------------------------------------------------------------------

func _layout_yard() -> void:
	# Concrete loading platform with steel ramps.
	_box(Vector3(0, 1.5, 0), Vector3(12, 3, 12), "block_a", false)
	_box(Vector3(0, 2.6, 0), Vector3(12.1, 0.14, 12.1), "accent_b", false, 0.0, false)
	_wedge(Vector3(10, 0, 0), Vector3(8, 3, 5), PI, "deck")
	_box(Vector3(0, 3.65, 0), Vector3(2.4, 1.3, 2.4), "crate", false, 0.5)
	_box(Vector3(4.6, 3.5, -4.2), Vector3(0.5, 1.0, 3.0), "stripes")
	_glow(Vector3(0, 5.2, 0), theme.accent_b, 13.0, 2.2, false)

	# Steel catwalk from the platform to the north deck (mirrored: south deck).
	_box(Vector3(0, 2.8, 10), Vector3(3, 0.4, 8), "deck")
	_box(Vector3(1.55, 3.45, 10), Vector3(0.15, 0.9, 8), "rail")
	_box(Vector3(-1.55, 3.45, 10), Vector3(0.15, 0.9, 8), "rail")
	_box(Vector3(0, 2.8, 18), Vector3(16, 0.4, 8), "deck")
	for px in [-7.0, 7.0]:
		for pz in [15.0, 21.0]:
			_box(Vector3(px, 1.3, pz), Vector3(0.8, 2.6, 0.8), "block_c")
			_box(Vector3(px, 1.3, pz), Vector3(0.86, 0.12, 0.86), "accent_a", true, 0.0, false)
	_wedge(Vector3(-12, 0, 18), Vector3(8, 3, 4), 0.0, "deck")
	_box(Vector3(-4.75, 3.45, 14.1), Vector3(6.5, 0.9, 0.2), "rail")
	_box(Vector3(4.75, 3.45, 14.1), Vector3(6.5, 0.9, 0.2), "rail")
	_box(Vector3(4, 3.6, 20.5), Vector3(3, 1.2, 0.5), "stripes")
	_jump_pad(Vector3(9.6, 0, 18), 14.5)
	_glow(Vector3(0, 1.6, 18), theme.accent_a, 10.0, 1.6)

	# Brick warehouse with a gantry crane standing over it.
	_hut(Vector3(-23, 0, 13), "block_b")
	_box(Vector3(-26.2, 0.6, 16.2), Vector3(1.2, 1.2, 1.2), "crate", true, 0.2)
	_box(Vector3(-26.5, 4.5, 7.6), Vector3(0.9, 9, 0.9), "c_yellow")
	_box(Vector3(-26.5, 4.5, 19.0), Vector3(0.9, 9, 0.9), "c_yellow")
	_box(Vector3(-26.5, 9.2, 13.3), Vector3(1.1, 0.9, 12.6), "c_yellow", true, 0.0, false)
	_box(Vector3(-26.5, 8.1, 13.3), Vector3(0.1, 1.4, 0.1), "dark", true, 0.0, false)
	_box(Vector3(-26.5, 6.2, 13.3), Vector3(2.5, 2.4, 5.0), "c_teal", true, 0.0, false)
	_box(Vector3(-26.5, 9.75, 13.3), Vector3(0.3, 0.2, 0.3), "beacon", true, 0.0, false)

	# Shipping containers: stacks to fight around and climb.
	_container(Vector3(21, 0, 13), 0.1, "c_red")
	_container(Vector3(21.4, 2.6, 13.2), 0.1, "c_blue", 4.5)
	_box(Vector3(17.1, 0.65, 13.0), Vector3(1.3, 1.3, 1.3), "crate", true, 0.3)
	_container(Vector3(25.6, 0, 17.6), PI / 2 + 0.08, "c_yellow")
	_container(Vector3(-27.5, 0, -3), PI / 2, "c_teal")
	_container(Vector3(12.5, 0, 21.2), 0.0, "c_blue", 4.5)

	# Concrete blast wall, barriers, barrels.
	_box(Vector3(16, 2, -5), Vector3(1, 4, 9), "block_a")
	_box(Vector3(16, 4.1, -5), Vector3(1.2, 0.16, 9.2), "accent_a", true, 0.0, false)
	_box(Vector3(9, 0.6, -9.5), Vector3(5, 1.2, 0.6), "stripes")
	_box(Vector3(-12, 0.6, -11), Vector3(0.6, 1.2, 5), "stripes")
	_barrel(Vector3(20, 0, -20.5))
	_barrel(Vector3(21.3, 0, -19.8))
	_barrel(Vector3(-3, 0, 22.6))
	_barrel(Vector3(30.5, 0, 9))
	# Neon signs on the perimeter.
	_sign(Vector3(-10, 3.0, half_z - 0.08), Vector3(7, 1.6, 0.1), "accent_a")
	_sign(Vector3(half_x - 0.08, 3.0, -12), Vector3(0.1, 1.4, 6), "accent_b")
	_glow(Vector3(24, 3.5, -4), theme.accent_b, 12.0, 1.5)

	_spawns([Vector3(28, 0.1, 21.5), Vector3(29.5, 0.1, -6), Vector3(-18, 0.1, 21.5),
		Vector3(24, 0.1, -21.5), Vector3(-23, 0.1, 13)])
	_pickups([["weapon", Vector3(0, 3.0, 3.9)], ["weapon", Vector3(-5.0, 3.0, 19.6)],
		["health", Vector3(-25.6, 0.0, 10.4)], ["health", Vector3(20.0, 0.0, 2.0)]])


# --------------------------------------------------------------------------
# Layout 1: EMBER PIT (small) - a foundry in a volcano
# --------------------------------------------------------------------------

func _layout_pit() -> void:
	# Round sandstone forge with ramps and a glowing iron chimney.
	_cyl(Vector3(0, 0, 0), 3.4, 2.0, "block_a", false)
	_cyl(Vector3(0, 1.7, 0), 3.46, 0.14, "accent_a", false, false)
	_wedge(Vector3(5.4, 0, 0), Vector3(5.6, 2, 3.5), PI, "deck")
	_cyl(Vector3(0, 2.0, 0), 0.9, 3.4, "block_b", false)
	_cyl(Vector3(0, 3.0, 0), 0.95, 0.16, "lava", false, false)
	_cyl(Vector3(0, 4.3, 0), 0.95, 0.16, "lava", false, false)
	_cyl(Vector3(0, 5.4, 0), 1.1, 0.3, "block_c", false, false)
	_glow(Vector3(0, 6.2, 0), theme.accent_a, 13.0, 2.6, false)

	# Raised sandstone ledges along the east and west walls, each with a ramp.
	_box(Vector3(15.5, 1.25, -8), Vector3(5, 2.5, 8), "block_a")
	_box(Vector3(15.5, 2.2, -8), Vector3(5.1, 0.14, 8.1), "accent_b", true, 0.0, false)
	_wedge(Vector3(15.5, 0, -0.75), Vector3(6.5, 2.5, 5), PI / 2, "deck")
	_box(Vector3(13.2, 3.0, -8), Vector3(0.3, 1.0, 5), "stripes")

	# Stone arches over the north and south lanes.
	_box(Vector3(2.8, 1.8, 9.2), Vector3(1.0, 3.6, 1.0), "block_a")
	_box(Vector3(-2.8, 1.8, 9.2), Vector3(1.0, 3.6, 1.0), "block_a")
	_box(Vector3(0, 4.0, 9.2), Vector3(7.0, 0.8, 1.2), "block_a")
	_box(Vector3(0, 3.56, 9.2), Vector3(4.4, 0.1, 1.24), "accent_a", true, 0.0, false)

	# Iron plates as corner cover, a round column, crates.
	_box(Vector3(10, 1, 8), Vector3(4, 2, 0.6), "block_b")
	_box(Vector3(11.7, 1, 6.3), Vector3(0.6, 2, 4), "block_b")
	_box(Vector3(-8, 1, 8.5), Vector3(4, 2, 0.6), "block_b")
	_box(Vector3(-9.7, 1, 6.8), Vector3(0.6, 2, 4), "block_b")
	_cyl(Vector3(10.2, 0, -2.8), 0.65, 3.4, "block_a")
	_box(Vector3(7.5, 0.6, -8), Vector3(0.6, 1.2, 4), "stripes")
	_box(Vector3(-4.2, 0.75, 10.4), Vector3(1.5, 1.5, 1.5), "crate", true, 0.3)
	_barrel(Vector3(16.5, 0, 11.0))
	_barrel(Vector3(-16.6, 0, -6.5))
	_jump_pad(Vector3(0, 0, 5.2), 10.5)

	# Lava channels along the north and south walls.
	_lava(Vector3(0, 0, 13.2), Vector3(26.0, 0.1, 1.6))

	_spawns([Vector3(15, 0.1, 10.5), Vector3(0, 0.1, 11.2), Vector3(-9, 0.1, 11), Vector3(15.5, 2.6, -9)])
	_pickups([["weapon", Vector3(2.2, 2.0, 2.2)], ["health", Vector3(15.5, 2.5, -5.5)]])


# --------------------------------------------------------------------------
# Layout 2: FROST LINE (large) - a polar research outpost
# --------------------------------------------------------------------------

func _layout_frost() -> void:
	# Central lab tower with long ramps, a second tier and a radio mast.
	_box(Vector3(0, 2, 0), Vector3(10, 4, 10), "block_a", false)
	_box(Vector3(0, 3.6, 0), Vector3(10.1, 0.14, 10.1), "accent_a", false, 0.0, false)
	_box(Vector3(0, 1.0, 0), Vector3(10.08, 0.5, 10.08), "crate", false, 0.0, false)
	_wedge(Vector3(10, 0, 0), Vector3(10, 4, 5), PI, "deck")
	_box(Vector3(0, 5, 0), Vector3(3.6, 2, 3.6), "block_c", false)
	_box(Vector3(0, 5.6, 0), Vector3(3.7, 0.12, 3.7), "accent_b", false, 0.0, false)
	_cyl(Vector3(0, 6, 0), 0.1, 5.5, "dark", false, false)
	_prop(_unit_sphere, "beacon", Vector3(0, 11.6, 0), Vector3.ONE * 0.22)
	_glow(Vector3(0, 7.5, 0), theme.accent_a, 18.0, 2.6, false)

	# Steel bridges to the north/south decks; each deck has a ramp at both ends.
	_box(Vector3(0, 3.8, 11), Vector3(4, 0.4, 12), "deck")
	_box(Vector3(2.05, 4.45, 11), Vector3(0.15, 0.9, 12), "rail")
	_box(Vector3(-2.05, 4.45, 11), Vector3(0.15, 0.9, 12), "rail")
	_box(Vector3(0, 3.8, 21), Vector3(20, 0.4, 8), "deck")
	for px in [-9.0, 9.0]:
		for pz in [18.0, 24.0]:
			_box(Vector3(px, 1.8, pz), Vector3(0.9, 3.6, 0.9), "block_c")
			_box(Vector3(px, 1.8, pz), Vector3(0.96, 0.12, 0.96), "accent_a", true, 0.0, false)
	_wedge(Vector3(15, 0, 21), Vector3(10, 4, 4), PI, "deck")
	_wedge(Vector3(-15, 0, 21), Vector3(10, 4, 4), 0.0, "deck")
	_box(Vector3(-6.2, 4.45, 17.1), Vector3(8, 0.9, 0.2), "rail")
	_box(Vector3(6.2, 4.45, 17.1), Vector3(8, 0.9, 0.2), "rail")
	_box(Vector3(-5, 4.6, 23.5), Vector3(3, 1.2, 0.5), "stripes")
	_glow(Vector3(0, 2.0, 21), theme.accent_b, 12.0, 1.6)

	# East/west lab modules: white panels with an orange band, walkable roof.
	_box(Vector3(28.2, 1.6, -6.25), Vector3(0.4, 3.2, 3.5), "block_a")
	_box(Vector3(28.2, 1.6, 0), Vector3(0.4, 3.2, 4), "block_a")
	_box(Vector3(28.2, 1.6, 6.25), Vector3(0.4, 3.2, 3.5), "block_a")
	_box(Vector3(28.2, 2.85, -3.25), Vector3(0.4, 0.7, 2.5), "block_a")
	_box(Vector3(28.2, 2.85, 3.25), Vector3(0.4, 0.7, 2.5), "block_a")
	_box(Vector3(32, 1.6, 7.8), Vector3(8, 3.2, 0.4), "block_a")
	_box(Vector3(32, 1.6, -7.8), Vector3(8, 3.2, 0.4), "block_a")
	_box(Vector3(32, 1.0, 7.8), Vector3(8.04, 0.5, 0.46), "crate", true, 0.0, false)
	_box(Vector3(32, 1.0, -7.8), Vector3(8.04, 0.5, 0.46), "crate", true, 0.0, false)
	_box(Vector3(35, 3.4, 0), Vector3(14, 0.4, 16), "block_c")
	_box(Vector3(35, 3.4, 0), Vector3(14.1, 0.12, 16.1), "accent_b", true, 0.0, false)
	_wedge(Vector3(35, 0, 11.5), Vector3(7, 3.6, 5), PI / 2, "deck")
	_box(Vector3(30, 4.2, -5), Vector3(0.5, 1.2, 4), "stripes")
	_glow(Vector3(34, 2.6, 0), theme.accent_a, 11.0, 2.0)

	# Mid-field: walls of ice blocks, supply crates, barriers, pines.
	_box(Vector3(20, 2, -12), Vector3(1.4, 4, 10), "block_b")
	_box(Vector3(22, 1.5, 13), Vector3(6, 3, 1.4), "block_b")
	_box(Vector3(12, 1.25, -14), Vector3(2.5, 2.5, 2.5), "block_b", true, 0.15)
	_box(Vector3(14.7, 1.0, -13), Vector3(2, 2, 2), "crate", true, -0.3)
	_box(Vector3(-10, 1.0, -27), Vector3(2, 2, 2), "crate", true, 0.3)
	_box(Vector3(-11.6, 0.65, -25.2), Vector3(1.3, 1.3, 1.3), "crate", true, 0.6)
	_box(Vector3(8, 0.6, -9), Vector3(5, 1.2, 0.6), "stripes")
	_box(Vector3(-8, 0.6, -12), Vector3(0.6, 1.2, 5), "stripes")
	_box(Vector3(26, 0.6, -22), Vector3(6, 1.2, 0.6), "stripes")
	_box(Vector3(30, 0.6, 21), Vector3(0.6, 1.2, 6), "stripes")
	_barrel(Vector3(40.5, 0, 14))
	_barrel(Vector3(-22, 0, 30.2))
	_barrel(Vector3(6, 0, 29.5))
	for p in [Vector3(41.5, 0, -12), Vector3(-12, 0, 30), Vector3(18, 0, -29.5), Vector3(31, 0, 30), Vector3(-36, 0, 24.5)]:
		_pine(p, _rng.randf_range(0.9, 1.25))
	_jump_pad(Vector3(7.2, 0, 7.2), 15.5)
	_jump_pad(Vector3(40, 0, -18), 16.0)
	_glow(Vector3(22, 4.0, -24), theme.accent_b, 14.0, 1.6)
	_glow(Vector3(-30, 4.0, 22), theme.accent_a, 14.0, 1.6)

	_spawns([Vector3(41, 0.1, 27), Vector3(41, 0.1, -27), Vector3(24, 0.1, 29), Vector3(39, 0.1, 0),
		Vector3(30, 0.1, -16), Vector3(-24, 0.1, 29)])
	_pickups([["weapon", Vector3(3.2, 4.0, 3.2)], ["weapon", Vector3(6.5, 4.0, 22.5)], ["weapon", Vector3(36, 3.6, -4)],
		["health", Vector3(38, 0.0, 0)], ["health", Vector3(0, 0.0, 11)]])


# --------------------------------------------------------------------------
# Scenery (no gameplay effect)
# --------------------------------------------------------------------------

func _build_scenery() -> void:
	var rich: bool = Settings.v("scenery") == 1
	# Apron outside the walls so the horizon is not empty.
	var apron := PlaneMesh.new()
	apron.size = Vector2(700, 700)
	var ground_col: Color = theme.mats.ground[0]
	var am := StandardMaterial3D.new()
	am.albedo_color = ground_col.darkened(0.45)
	am.roughness = 0.7
	_prop(apron, am, Vector3(0, -0.6, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match theme.scenery:
		"city": _scenery_city(30 if rich else 14)
		"rocks": _scenery_spires(46 if rich else 20, Color(0.2, 0.13, 0.11), theme.accent_a, false)
		"ice": _scenery_spires(54 if rich else 22, Color(0.25, 0.42, 0.52), theme.accent_a, true)
	if rich:
		if theme.scenery == "ice":
			_snow_drifts()
		_motes()


func _ring_spot(i: int, n: int, near: float, far: float) -> Vector3:
	var a := TAU * i / float(n) + _rng.randf_range(-0.08, 0.08)
	var dir := Vector2(cos(a), sin(a))
	var edge := minf((half_x + 6.0) / maxf(absf(dir.x), 0.001), (half_z + 6.0) / maxf(absf(dir.y), 0.001))
	var d := edge + _rng.randf_range(near, far)
	return Vector3(dir.x * d, 0, dir.y * d)


## Night-city skyline: dark towers with glowing window bands.
func _scenery_city(count: int) -> void:
	var tower := BoxMesh.new()
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.04, 0.045, 0.085)
	body.roughness = 0.5
	for i in count:
		var p := _ring_spot(i, count, 6.0, 55.0)
		var w := _rng.randf_range(7.0, 16.0)
		var h := _rng.randf_range(10.0, 44.0)
		var t := _prop(tower, body, p + Vector3(0, h * 0.5, 0), Vector3(w, h, w))
		t.rotation.y = _rng.randf() * 0.6
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var neon: String = "accent_a" if i % 2 == 0 else "accent_b"
		var bands := 2 + _rng.randi() % 4
		for b in bands:
			var y := h * (0.25 + 0.7 * b / float(bands))
			var band := _prop(tower, neon, p + Vector3(0, y, 0), Vector3(w + 0.15, 0.22, w + 0.15))
			band.rotation.y = t.rotation.y
			band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Jagged spires: dark rock for the pit, glowing crystals for the ice field.
func _scenery_spires(count: int, col: Color, glow: Color, crystal: bool) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 6
	var rock := StandardMaterial3D.new()
	rock.albedo_color = col
	rock.roughness = 0.3 if crystal else 0.8
	if crystal:
		rock.emission_enabled = true
		rock.emission = glow
		rock.emission_energy_multiplier = 0.2
		rock.rim_enabled = true
	else:
		var t: Array = _tex("rock")
		rock.albedo_texture = t[0]
		rock.normal_enabled = true
		rock.normal_texture = t[1]
		rock.uv1_triplanar = true
		rock.uv1_scale = Vector3.ONE * 0.6
	for i in count:
		var p := _ring_spot(i, count, 2.0, 60.0)
		var h := _rng.randf_range(5.0, 30.0) * (1.5 if i % 7 == 0 else 1.0)
		var r := h * _rng.randf_range(0.14, 0.3)
		var s := _prop(cone, rock, p + Vector3(0, h * 0.5 - 0.6, 0), Vector3(r, h, r))
		s.rotation = Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf() * TAU, _rng.randf_range(-0.12, 0.12))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i % 3 == 0 and not crystal:
			# A pool of lava at the foot of some spires.
			var disc := CylinderMesh.new()
			disc.top_radius = r * 1.8
			disc.bottom_radius = r * 1.8
			disc.height = 0.1
			_prop(disc, "lava", p + Vector3(0, -0.5, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Soft mounds of snow against the inside of the walls (visual only).
func _snow_drifts() -> void:
	for i in 22:
		var along := _rng.randf_range(-1.0, 1.0)
		var pos: Vector3
		match i % 4:
			0: pos = Vector3(along * (half_x - 3.0), 0, half_z - 0.4)
			1: pos = Vector3(along * (half_x - 3.0), 0, -half_z + 0.4)
			2: pos = Vector3(half_x - 0.4, 0, along * (half_z - 3.0))
			_: pos = Vector3(-half_x + 0.4, 0, along * (half_z - 3.0))
		var r := _rng.randf_range(1.2, 2.6)
		_prop(_unit_sphere, "ground", pos, Vector3(r, r * 0.3, r)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Glowing specks in the air: fireflies, embers or snow depending on the theme.
func _motes() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	mat.albedo_texture = tex
	var ramp := Gradient.new()
	ramp.set_color(0, theme.motes[0] * 1.8)
	ramp.set_color(1, theme.motes[1] * 1.8)
	var rise: float = theme.mote_rise
	var p := CPUParticles3D.new()
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.mesh = QuadMesh.new()
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = int(half_x * half_z * 0.3)
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(half_x, 4.0, half_z)
	p.direction = Vector3(0.6, signf(rise), 0.3)
	p.spread = 40.0
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.5 + absf(rise)
	p.gravity = Vector3(0, rise * 0.4, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.14
	p.color_initial_ramp = ramp
	p.position = Vector3(0, 4.5, 0)
	add_child(p)


# --------------------------------------------------------------------------
# Bot navigation
# --------------------------------------------------------------------------

func _ray(from: Vector3, to: Vector3, from_inside := false) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.hit_from_inside = from_inside
	return get_world_3d().direct_space_state.intersect_ray(q)


## Must run after the static body has been in the tree for a physics frame.
func build_nav() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var points: Array = []            # Vector3
	var cells := {}                    # Vector2i -> Array of point indices
	var x := -half_x + 1.0
	while x < half_x:
		var z := -half_z + 1.0
		while z < half_z:
			var top := 12.0
			for layer in 4:
				var hit := _ray(Vector3(x, top, z), Vector3(x, -0.5, z))
				if hit.is_empty():
					break
				var p: Vector3 = hit.position
				top = p.y - 0.5
				if hit.normal.y > 0.7 and p.y < 8.0:
					# Standing room, and not inside a solid.
					if _ray(p + Vector3(0, 0.15, 0), p + Vector3(0, 1.9, 0), true).is_empty():
						var key := Vector2i(roundi(x), roundi(z))
						if not cells.has(key):
							cells[key] = []
						cells[key].append(points.size())
						points.append(p)
				if top < 0.0:
					break
			z += NAV_STEP
		x += NAV_STEP

	# Link walkable neighbours.
	var links: Array = []
	var adj := {}
	var step := int(NAV_STEP)
	for key in cells:
		for off in [Vector2i(step, 0), Vector2i(0, step), Vector2i(step, step), Vector2i(step, -step)]:
			var other: Vector2i = key + off
			if not cells.has(other):
				continue
			for i in cells[key]:
				for j in cells[other]:
					if _walkable(points[i], points[j]):
						links.append(Vector2i(i, j))
						if not adj.has(i): adj[i] = []
						if not adj.has(j): adj[j] = []
						adj[i].append(j)
						adj[j].append(i)

	# Keep only the largest connected component so every goal is reachable.
	var seen := {}
	var best: Array = []
	for start in adj:
		if seen.has(start):
			continue
		var comp: Array = []
		var stack: Array = [start]
		seen[start] = true
		while not stack.is_empty():
			var cur = stack.pop_back()
			comp.append(cur)
			for nb in adj[cur]:
				if not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
		if comp.size() > best.size():
			best = comp
	var keep := {}
	for i in best:
		keep[i] = true
		nav.add_point(i, points[i])
		_nav_ids.append(i)
	for l in links:
		if keep.has(l.x) and keep.has(l.y):
			nav.connect_points(l.x, l.y)
	nav_ready = true
	print("[map] %s nav graph: %d nodes, %d links" % [MAPS[map_index].name, best.size(), links.size()])


func _walkable(a: Vector3, b: Vector3) -> bool:
	if absf(a.y - b.y) > 1.25:
		return false
	# Ground must be continuous under the segment.
	for t in [0.25, 0.5, 0.75]:
		var m := a.lerp(b, t)
		var hit := _ray(m + Vector3(0, 1.0, 0), m + Vector3(0, -0.6, 0))
		if hit.is_empty() or absf(hit.position.y - m.y) > 0.45:
			return false
	# Body-width corridor must be clear (the low ray also stops at kerbs).
	var dir := (b - a)
	dir.y = 0.0
	var side := dir.normalized().cross(Vector3.UP) * 0.38
	for off in [Vector3.ZERO, side, -side]:
		for hgt in [0.35, 0.7, 1.5]:
			var up := Vector3(0, hgt, 0)
			if not _ray(a + up + off, b + up + off, true).is_empty():
				return false
	return true


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not nav_ready or _nav_ids.is_empty():
		return PackedVector3Array()
	return nav.get_point_path(_closest_node(from), _closest_node(to))


## Nearest nav node that can actually be reached in a straight line from
## `pos` (the plain nearest node may be on the other side of a wall).
func _closest_node(pos: Vector3) -> int:
	var near: Array = []
	for id in _nav_ids:
		var d := nav.get_point_position(id).distance_squared_to(pos)
		if d < 12.0:
			near.append([d, id])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var up := Vector3(0, 0.8, 0)
	for n in near:
		if _ray(pos + up, nav.get_point_position(n[1]) + up, true).is_empty():
			return n[1]
	return nav.get_closest_point(pos)


func random_nav_point() -> Vector3:
	if not nav_ready or _nav_ids.is_empty():
		return Vector3.ZERO
	return nav.get_point_position(_nav_ids[randi() % _nav_ids.size()])
