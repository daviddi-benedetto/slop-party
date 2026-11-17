extends Node3D
## A small 3D scene used behind the lobby and the results screen: a backyard
## (striped lawn, picket fence, flower beds, trees, hills and mountains or a
## neon skyline, party lights), seats (tree stumps, or rugs on a deck), and a
## camera, all coloured by the visual theme passed to build() (looks.gd
## "stage" and "grade"; default: a sunny day).
## Characters placed with add_character() are animated here.
##
## It lives in the root viewport's World3D, the same one a match uses, so it
## must be freed before a match starts (main.gd / game.gd take care of that).

const Character = preload("res://scripts/character.gd")
const SkyKit = preload("res://scripts/sky.gd")
const Looks = preload("res://scripts/looks.gd")
const Models = preload("res://scripts/models.gd")

const ORANGE := Color(1.0, 0.42, 0.16)
const CYAN := Color(0.15, 0.75, 1.0)

var camera: Camera3D
var characters: Array = []       # character.gd nodes this stage animates
var _time := 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _rings: Array = []
var _look := {}


func build(cam_pos: Vector3, look_at_pos: Vector3, fov: float, look := {}) -> void:
	# Theme colours (looks.gd "stage"); anything missing falls back to a
	# sunny day (or a starry night when the stage says "day": false).
	var st: Dictionary = look.get("stage", {})
	var day: bool = st.get("day", true)
	var ring_a: Color = st.get("ring_a", ORANGE)
	var ring_b: Color = st.get("ring_b", CYAN)
	var band_a: Color = st.get("band_a", ring_a)
	var band_b: Color = st.get("band_b", ring_b)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var night_sky := {"top": Color(0.01, 0.015, 0.05), "horizon": Color(0.12, 0.1, 0.28), "ground": Color(0.02, 0.02, 0.05),
		"sun": Color(0.75, 0.82, 1.0), "cloud_color": Color(0.14, 0.13, 0.28), "clouds": 0.6, "stars": 1.0, "aurora": 0.35}
	var day_sky := {"top": Color(0.22, 0.48, 0.92), "horizon": Color(0.72, 0.84, 0.96), "ground": Color(0.3, 0.32, 0.3),
		"sun": Color(1.0, 0.95, 0.85), "cloud_color": Color(0.96, 0.97, 1.0), "clouds": 0.6, "stars": 0.0, "aurora": 0.0}
	env.sky = SkyKit.make(st.get("sky", day_sky if day else night_sky))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = st.get("ambient", 1.1 if day else 2.4)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = st.get("exposure", 0.95 if day else 1.3)
	env.tonemap_white = 4.0
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = st.get("glow", 1.4 if day else 1.0)
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08
	Looks.apply_post(look, env)
	env.fog_enabled = true
	env.fog_light_color = st.get("fog", Color(0.66, 0.76, 0.9) if day else Color(0.05, 0.06, 0.14))
	if st.has("ambient_color"):
		env.ambient_light_color = st.ambient_color
		env.ambient_light_sky_contribution = 0.5
	env.fog_density = st.get("fog_density", 0.0035 if day else 0.006)
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(st.get("sun_pitch", -40.0), -30.0, 0.0)
	sun.light_color = st.get("sun_color", Color(1.0, 0.96, 0.88) if day else Color(0.7, 0.78, 1.0))
	sun.light_energy = st.get("sun_energy", 1.8 if day else 1.1)
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.shadow_opacity = look.get("shadow", 1.0)
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	# Warm key light from the front so faces read well against the dark.
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.82)
	key.light_energy = 1.4 if day else 3.2
	key.spot_range = 26.0
	key.spot_angle = 50.0
	add_child(key)
	key.look_at_from_position(Vector3(0, 7.5, 9.0), Vector3(0, 1.2, 0))
	_env = env
	_sun = sun
	_on_settings()
	Settings.changed.connect(_on_settings)

	_look = look
	_backyard(look, st, day, ring_a, ring_b, band_a, band_b)

	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = fov
	add_child(camera)
	camera.look_at_from_position(cam_pos, look_at_pos)
	camera.current = true


func _on_settings() -> void:
	Settings.apply_environment(_env, _sun)


func _neon(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.3)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


func _prop(mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	(parent if parent != null else self).add_child(mi)
	return mi


## A seat to stand on; returns the Y of its top surface. "stump" is a tree
## stump (any height) ringed in the player's colour; "rug" is just a round
## rug in that colour lying at pos.y + height (on the deck).
func add_podium(pos: Vector3, height: float, color: Color, kind := "stump") -> float:
	var top := pos + Vector3(0, height, 0)
	if kind == "stump":
		var bark := CylinderMesh.new()
		bark.top_radius = 0.9
		bark.bottom_radius = 1.05
		bark.height = height
		bark.radial_segments = 14
		_prop(bark, _mat(_g(Color(0.42, 0.28, 0.18)), 0.95), pos + Vector3(0, height * 0.5, 0))
		var wood := CylinderMesh.new()
		wood.top_radius = 0.86
		wood.bottom_radius = 0.86
		wood.height = 0.04
		wood.radial_segments = 28
		_prop(wood, _mat(_g(Color(0.86, 0.68, 0.45)), 0.9), top + Vector3(0, 0.01, 0))
		for r in [0.3, 0.55]:
			var ring := TorusMesh.new()
			ring.inner_radius = r
			ring.outer_radius = r + 0.025
			ring.rings = 32
			ring.ring_segments = 4
			_prop(ring, _mat(_g(Color(0.66, 0.48, 0.3)), 0.9), top + Vector3(0, 0.03, 0))
	var rug := CylinderMesh.new()
	rug.top_radius = 1.0 if kind == "stump" else 0.95
	rug.bottom_radius = rug.top_radius
	rug.height = 0.06
	rug.radial_segments = 32
	if kind == "stump":
		# A coloured band round the top edge.
		var band := TorusMesh.new()
		band.inner_radius = 0.88
		band.outer_radius = 1.0
		band.rings = 40
		band.ring_segments = 6
		_prop(band, _neon(color, 0.5), top + Vector3(0, -0.02, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		_prop(rug, _neon(color, 0.45), top + Vector3(0, 0.03, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return top.y + (0.05 if kind == "stump" else 0.06)


## A wooden backyard deck over x0..x1, z0..z1 (z1 is the front), h metres
## high, with a plank skirt, posts, a back railing, steps down the right
## side and potted plants.
func add_deck(x0: float, x1: float, z0: float, z1: float, h: float) -> void:
	var wood := _mat(_g(Color(0.66, 0.46, 0.29)), 0.85)
	var dark := _mat(_g(Color(0.44, 0.3, 0.19)), 0.9)
	var skirt := _mat(_g(Color(0.5, 0.34, 0.22)), 0.9)
	var box := BoxMesh.new()
	var w := x1 - x0
	var d := z1 - z0
	var cx := (x0 + x1) * 0.5
	_prop(box, wood, Vector3(cx, h - 0.1, (z0 + z1) * 0.5), Vector3(w, 0.2, d))
	_prop(box, dark, Vector3(cx, h * 0.5 - 0.1, (z0 + z1) * 0.5), Vector3(w - 0.3, h - 0.2, d - 0.3))
	# Plank skirt on the front and the sides.
	var planks: Array = []
	var n := int((h - 0.2) / 0.32)
	for k in n:
		var y := 0.16 + k * 0.32
		planks.append(Transform3D(Basis.from_scale(Vector3(w, 0.26, 0.06)), Vector3(cx, y, z1 - 0.03)))
		for sx in [x0 + 0.03, x1 - 0.03]:
			planks.append(Transform3D(Basis.from_scale(Vector3(0.06, 0.26, d)), Vector3(sx, y, (z0 + z1) * 0.5)))
	_multi(box, skirt, planks)
	# Shrubs and flowers along the foot of the deck.
	var ball := SphereMesh.new()
	ball.radial_segments = 12
	ball.rings = 6
	var shrubs: Array = []
	var blooms: Array = []
	var bx := x0 + 0.6
	var k2 := 0
	while bx < x1:
		var r := 0.55 + 0.2 * sin(k2 * 1.7)
		shrubs.append(Transform3D(Basis.from_scale(Vector3(r * 1.3, r, r)), Vector3(bx, r * 0.55, z1 + 0.45)))
		blooms.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.13), Vector3(bx + 0.25 * sin(k2 * 2.3), r * 1.05, z1 + 0.45 + r * 0.6)))
		blooms.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.12), Vector3(bx - 0.35, r * 0.8, z1 + 0.5 + r * 0.7)))
		bx += 1.1
		k2 += 1
	_multi(ball, _mat(_g(Color(0.25, 0.52, 0.22)), 0.95), shrubs)
	_multi(ball, _mat(_g(Color(1.0, 0.62, 0.78)), 0.7), blooms)
	# Bunting along the deck's front edge.
	var prism := PrismMesh.new()
	var flags := [[], [], []]
	var fx := x0 + 0.3
	var fk := 0
	while fx < x1 - 0.2:
		flags[fk % 3].append(Transform3D(Basis(Vector3.RIGHT, PI).scaled(Vector3(0.42, 0.5, 0.03)), Vector3(fx, h - 0.45, z1 + 0.03)))
		fx += 0.62
		fk += 1
	var flag_cols := [Color(1.0, 0.36, 0.36), Color(1.0, 0.84, 0.3), Color(0.36, 0.7, 1.0)]
	for f in 3:
		_multi(prism, _mat(_g(flag_cols[f]), 0.8), flags[f])
	# Posts at the corners and along the front, a rail along the back.
	var posts: Array = []
	var px := x0
	while px <= x1 + 0.01:
		posts.append(Transform3D(Basis.from_scale(Vector3(0.22, h, 0.22)), Vector3(px, h * 0.5, z1 - 0.05)))
		posts.append(Transform3D(Basis.from_scale(Vector3(0.14, 1.0, 0.14)), Vector3(px, h + 0.5, z0 + 0.08)))
		px += w / 4.0
	posts.append(Transform3D(Basis.from_scale(Vector3(w, 0.1, 0.12)), Vector3(cx, h + 1.0, z0 + 0.08)))
	posts.append(Transform3D(Basis.from_scale(Vector3(w, 0.06, 0.08)), Vector3(cx, h + 0.55, z0 + 0.08)))
	_multi(box, dark, posts)
	# Steps down the right-hand side.
	var steps: Array = []
	var sn := int(h / 0.34)
	for k in sn:
		var y := h - (k + 1) * (h / sn)
		steps.append(Transform3D(Basis.from_scale(Vector3(0.5, 0.12, 1.6)), Vector3(x1 + 0.25 + k * 0.42, y + 0.06, z0 + 1.2)))
	# Stringers under both edges of the steps, so they read as a staircase.
	var run := sn * 0.42
	var slope := atan2(h, run)
	var length := sqrt(h * h + run * run)
	for ez in [z0 + 0.45, z0 + 1.95]:
		steps.append(Transform3D(Basis(Vector3.BACK, -slope).scaled(Vector3(length, 0.3, 0.1)), Vector3(x1 + run * 0.5, h * 0.5 - 0.1, ez)))
	_multi(box, wood, steps)
	# Potted plants in the back corners.
	for sx in [x0 + 0.6, x1 - 0.6]:
		var pot := CylinderMesh.new()
		pot.top_radius = 0.34
		pot.bottom_radius = 0.26
		pot.height = 0.55
		_prop(pot, _mat(_g(Color(0.78, 0.42, 0.28)), 0.9), Vector3(sx, h + 0.27, z0 + 0.6))
		var bush := SphereMesh.new()
		bush.radius = 0.55
		bush.height = 1.0
		_prop(bush, _mat(_g(Color(0.3, 0.58, 0.24)), 0.95), Vector3(sx, h + 0.85, z0 + 0.6))


## The backyard: striped lawn, a picket fence with flower beds, trees,
## rolling hills and far mountains (or, in a city theme, a neon skyline),
## and strings of party lights in the theme's two colours.
func _backyard(look: Dictionary, st: Dictionary, day: bool, light_a: Color, light_b: Color, band_a: Color, band_b: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var night: bool = not day
	var lawn_col: Color = _g(st.get("lawn", Color(0.36, 0.62, 0.25)))
	var ground := CylinderMesh.new()
	ground.top_radius = 220.0
	ground.bottom_radius = 220.0
	ground.height = 0.2
	ground.radial_segments = 48
	_prop(ground, _mat(lawn_col, 0.95), Vector3(0, -0.1, 0))
	# Mown stripes.
	var box := BoxMesh.new()
	var stripes: Array = []
	for k in 9:
		stripes.append(Transform3D(Basis.from_scale(Vector3(60.0, 0.02, 1.6)), Vector3(0, 0.005, 8.0 - k * 3.2)))
	_multi(box, _mat(lawn_col.lightened(0.1), 0.95), stripes)

	# Picket fence across the back of the yard.
	var fz := -11.0
	var white := _mat(_g(st.get("fence", Color(0.95, 0.93, 0.88))), 0.8)
	var pickets: Array = []
	var tips: Array = []
	var x := -30.0
	while x <= 30.0:
		pickets.append(Transform3D(Basis.from_scale(Vector3(0.16, 1.3, 0.06)), Vector3(x, 0.65, fz)))
		tips.append(Transform3D(Basis.from_scale(Vector3(0.16, 0.16, 0.06)), Vector3(x, 1.38, fz)))
		x += 0.42
	for y in [0.35, 1.0]:
		pickets.append(Transform3D(Basis.from_scale(Vector3(60.0, 0.1, 0.05)), Vector3(0, y, fz - 0.06)))
	_multi(box, white, pickets)
	var prism := PrismMesh.new()
	_multi(prism, white, tips)
	# Flower beds along the fence.
	var soil: Array = [Transform3D(Basis.from_scale(Vector3(60.0, 0.08, 1.2)), Vector3(0, 0.04, fz + 0.8))]
	_multi(box, _mat(_g(Color(0.36, 0.25, 0.17)), 1.0), soil)
	var bush := SphereMesh.new()
	bush.radial_segments = 12
	bush.rings = 6
	var bushes: Array = []
	var flowers := {}
	var petal := [Color(1.0, 0.55, 0.7), Color(1.0, 0.85, 0.3), Color(0.95, 0.95, 1.0), Color(0.7, 0.5, 1.0)]
	for k in 26:
		var bx := rng.randf_range(-28.0, 28.0)
		var r := rng.randf_range(0.45, 0.8)
		bushes.append(Transform3D(Basis.from_scale(Vector3(r * 1.3, r, r)), Vector3(bx, r * 0.6, fz + 0.75)))
		for f in 4:
			var c: int = rng.randi() % petal.size()
			if not flowers.has(c):
				flowers[c] = []
			flowers[c].append(Transform3D(Basis.from_scale(Vector3.ONE * 0.13), Vector3(bx + rng.randf_range(-1.0, 1.0), r * 0.6 + rng.randf_range(0.1, r * 0.8), fz + 0.75 + rng.randf_range(0.2, r))))
	_multi(bush, _mat(_g(Color(0.24, 0.5, 0.2)), 0.95), bushes)
	for c in flowers:
		_multi(bush, _mat(_g(petal[c]), 0.7), flowers[c])

	# Trees: in the yard's corners and beyond the fence.
	for spec in [[-17.0, -6.0, 4.6], [16.0, -7.0, 5.0], [-23.0, -15.0, 5.4], [22.0, -16.0, 5.8], [-9.0, -19.0, 4.8], [9.0, -21.0, 5.2], [0.0, -24.0, 5.6], [-30.0, -9.0, 5.0], [30.0, -8.0, 5.0]]:
		var path := "survival/Tree_Large" if rng.randf() < 0.4 else ("survival/Tree_Autumn" if look.get("key", "") in ["warm", "spooky"] else "survival/Tree")
		var tree: Node3D = Models.scene(path).instantiate()
		tree.position = Vector3(spec[0], 0, spec[1])
		tree.scale = Vector3.ONE * spec[2]
		tree.rotation.y = rng.randf() * TAU
		add_child(tree)

	if st.get("city", false):
		# A neon skyline beyond the fence.
		var tower := _mat(st.get("tower", [Color(0.08, 0.06, 0.14)])[0], 0.6)
		for k in 26:
			var a := lerpf(PI * 1.1, PI * 1.9, k / 25.0)
			var dd := rng.randf_range(60.0, 110.0)
			var tw := rng.randf_range(6.0, 12.0)
			var th := rng.randf_range(14.0, 46.0)
			var tp := Vector3(cos(a) * dd, 0, sin(a) * dd)
			_prop(box, tower, tp + Vector3(0, th * 0.5, 0), Vector3(tw, th, tw)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var neon := _neon(band_a if k % 2 == 0 else band_b, 2.2)
			for b in 3:
				_prop(box, neon, tp + Vector3(0, th * (0.3 + 0.3 * b), 0), Vector3(tw + 0.15, 0.3, tw + 0.15)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		# Rolling hills, then mountains with snow caps.
		var hill := SphereMesh.new()
		hill.radial_segments = 24
		hill.rings = 12
		var hills: Array = []
		for k in 9:
			var r := rng.randf_range(18.0, 30.0)
			hills.append(Transform3D(Basis.from_scale(Vector3(r, r * 0.32, r * 0.8)), Vector3(-80.0 + k * 20.0 + rng.randf_range(-6, 6), -2.0, rng.randf_range(-48.0, -38.0))))
		_multi(hill, _mat(_g(st.get("hill", Color(0.3, 0.55, 0.26))), 0.95), hills)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.0
		cone.height = 1.0
		cone.radial_segments = 9
		var peaks: Array = []
		var caps: Array = []
		for k in 11:
			var r := rng.randf_range(32.0, 48.0)
			var mh := rng.randf_range(16.0, 26.0)
			var mp := Vector3(-150.0 + k * 30.0 + rng.randf_range(-8, 8), 0, rng.randf_range(-150.0, -125.0))
			var yaw := Basis(Vector3.UP, rng.randf() * TAU)
			peaks.append(Transform3D(yaw.scaled(Vector3(r, mh, r)), mp + Vector3(0, mh * 0.5, 0)))
			caps.append(Transform3D(yaw.scaled(Vector3(r * 0.32, mh * 0.32, r * 0.32)), mp + Vector3(0, mh * 0.84 + 0.3, 0)))
		_multi(cone, _mat(_g(st.get("mountain", Color(0.46, 0.5, 0.62))), 0.95), peaks)
		_multi(cone, _mat(_g(Color(0.96, 0.97, 1.0)), 0.8), caps)

	# Party lights: strings of bulbs over the deck and along the fence.
	var bulb := SphereMesh.new()
	bulb.radius = 0.11
	bulb.height = 0.22
	bulb.radial_segments = 8
	bulb.rings = 4
	var bulbs := [[], []]
	var strings := [[Vector3(-9.5, 7.6, -3.8), Vector3(8.5, 7.6, -3.8), 1.0], [Vector3(-30.0, 2.6, fz - 0.3), Vector3(-10.0, 2.6, fz - 0.3), 0.7],
		[Vector3(10.0, 2.6, fz - 0.3), Vector3(30.0, 2.6, fz - 0.3), 0.7]]
	var poles: Array = []
	for sdef in strings:
		var a: Vector3 = sdef[0]
		var b: Vector3 = sdef[1]
		var cnt := int(a.distance_to(b) / 0.7)
		for k in cnt + 1:
			var f := float(k) / cnt
			var bp := a.lerp(b, f) - Vector3(0, sin(f * PI) * sdef[2], 0)
			bulbs[k % 2].append(Transform3D(Basis(), bp))
		for e in [a, b]:
			poles.append(Transform3D(Basis.from_scale(Vector3(0.12, e.y, 0.12)), Vector3(e.x, e.y * 0.5, e.z)))
	_multi(box, _mat(_g(Color(0.4, 0.3, 0.22)), 0.9), poles)
	_multi(bulb, _neon(light_a, 3.0 if night else 1.2), bulbs[0])
	_multi(bulb, _neon(light_b, 3.0 if night else 1.2), bulbs[1])
	if night:
		for k in 4:
			var l := OmniLight3D.new()
			l.position = Vector3(-7.5 + k * 5.0, 6.6, -3.0)
			l.light_color = light_a if k % 2 == 0 else light_b
			l.light_energy = 2.2
			l.omni_range = 9.0
			add_child(l)
		for sx in [-1.0, 1.0]:
			var l := OmniLight3D.new()
			l.position = Vector3(sx * 7.0, 2.4, 4.5)
			l.light_color = light_b if sx < 0 else light_a
			l.light_energy = 1.6
			l.omni_range = 10.0
			add_child(l)
	# Spooky: pumpkins on the lawn.
	if look.get("key", "") == "spooky":
		var pump := SphereMesh.new()
		pump.radial_segments = 12
		pump.rings = 6
		var pumps: Array = []
		for spec in [[-11.0, 6.0], [-9.5, 6.8], [10.5, 6.2], [12.0, 5.2], [-14.0, -8.5], [14.0, -9.0]]:
			pumps.append(Transform3D(Basis.from_scale(Vector3(0.55, 0.42, 0.55)), Vector3(spec[0], 0.38, spec[1])))
		_multi(pump, _neon(Color(1.0, 0.45, 0.05), 0.6), pumps)


## A matte toy material (wrapped diffuse, soft rim).
func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.rim_enabled = true
	m.rim = 0.2
	m.rim_tint = 0.6
	return m


## A colour through the theme's surface grade.
func _g(c: Color) -> Color:
	return Looks.grade(_look, c)


## Many copies of one mesh in one draw call.
func _multi(mesh: Mesh, mat: Material, xforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)


## Adds a character facing the camera (+Z). `look` = {kind, color, hat, face}.
func add_character(look: Dictionary, pos: Vector3):
	var c = Character.new()
	add_child(c)
	c.build(look.get("kind", 0), look.color, 1, true, look.get("hat", 0), look.get("face", 0), look.get("back", 0))
	c.position = pos
	c.rotation.y = PI
	c.pop_in()
	c.reset_physics_interpolation()
	characters.append(c)
	return c


func remove_character(c) -> void:
	characters.erase(c)
	c.queue_free()


func _process(delta: float) -> void:
	_time += delta
	for i in _rings.size():
		_rings[i].rotation.y += delta * (0.05 if i % 2 == 0 else -0.04)


func _physics_process(delta: float) -> void:
	for c in characters:
		c.animate(delta, 0.0, true, 0.0, 0.0)
