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
const Voxel = preload("res://scripts/voxel.gd")
const Voxelizer = preload("res://scripts/voxelizer.gd")

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
	env.glow_intensity = 0.3
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = st.get("glow", 1.4 if day else 1.0) + 0.25
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
	Models.look = look
	# The lobby and podium follow the world style too (voxel.gd).
	Voxel.on = Settings.v("voxel")
	Voxel.look = look
	_backyard(look, st, day, ring_a, ring_b, band_a, band_b)

	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = fov
	add_child(camera)
	camera.look_at_from_position(cam_pos, look_at_pos)
	camera.current = true
	# Depth of field: only the stage (seats, deck, characters) is sharp; the
	# yard in front and everything behind the fence goes soft.
	var d := cam_pos.distance_to(look_at_pos)
	var lens := CameraAttributesPractical.new()
	lens.dof_blur_far_enabled = true
	lens.dof_blur_far_distance = d + 4.0
	lens.dof_blur_far_transition = 7.0
	lens.dof_blur_near_enabled = true
	lens.dof_blur_near_distance = maxf(1.0, d - 9.0)
	lens.dof_blur_near_transition = 4.0
	lens.dof_blur_amount = 0.16
	camera.attributes = lens


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
	mi.material_override = _vox(mat)
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


## A party stage over x0..x1, z0..z1 (z1 is the front), h metres high:
## a red carpet with a gold border on top, a pleated velvet skirt with a
## gold fringe round the front and sides, bunting, a draped back rail,
## carpeted steps down the right side, tall banners and potted plants.
func add_deck(x0: float, x1: float, z0: float, z1: float, h: float) -> void:
	var carpet := _mat(_g(Color(0.6, 0.1, 0.14)), 0.95)
	var velvet := _mat(_g(Color(0.55, 0.08, 0.13)), 0.95)
	var fold := _mat(_g(Color(0.38, 0.05, 0.09)), 0.95)
	var gold := _mat(_g(Color(0.95, 0.74, 0.3)), 0.6)
	var cream := _mat(_g(Color(0.93, 0.88, 0.78)), 0.8)
	var box := BoxMesh.new()
	var w := x1 - x0
	var d := z1 - z0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	# The stage body (hidden behind the skirt) and the carpet on top.
	_prop(box, fold, Vector3(cx, h * 0.5 - 0.05, cz), Vector3(w - 0.1, h - 0.1, d - 0.1))
	_prop(box, carpet, Vector3(cx, h - 0.1, cz), Vector3(w + 0.1, 0.2, d + 0.1))
	var trim: Array = []
	for tz in [z0 + 0.35, z1 - 0.35]:
		trim.append(Transform3D(Basis.from_scale(Vector3(w - 0.5, 0.04, 0.12)), Vector3(cx, h + 0.01, tz)))
	for tx in [x0 + 0.35, x1 - 0.35]:
		trim.append(Transform3D(Basis.from_scale(Vector3(0.12, 0.04, d - 0.5)), Vector3(tx, h + 0.01, cz)))
	# Gold fringe along the top of the skirt.
	trim.append(Transform3D(Basis.from_scale(Vector3(w + 0.36, 0.14, 0.06)), Vector3(cx, h - 0.17, z1 + 0.2)))
	for sx in [x0 - 0.2, x1 + 0.2]:
		trim.append(Transform3D(Basis.from_scale(Vector3(0.06, 0.14, d + 0.36)), Vector3(sx, h - 0.17, cz)))
	_multi(box, gold, trim)
	# Pleated velvet skirt: deep folds alternate with forward ones.
	var pleats := [[], []]
	var pw := 0.3
	var sh := h - 0.2
	var n := int(ceil((w + 0.3) / pw))
	for k in n:
		var px := x0 - 0.15 + (k + 0.5) * (w + 0.3) / n
		var out := k % 2 == 0
		pleats[0 if out else 1].append(Transform3D(Basis.from_scale(Vector3((w + 0.3) / n + 0.02, sh, 0.1)), Vector3(px, sh * 0.5, z1 + (0.12 if out else 0.04))))
	var nd := int(ceil((d + 0.3) / pw))
	for sx in [x0, x1]:
		var dir := -1.0 if sx == x0 else 1.0
		for k in nd:
			var pz := z0 - 0.15 + (k + 0.5) * (d + 0.3) / nd
			var out := k % 2 == 0
			pleats[0 if out else 1].append(Transform3D(Basis.from_scale(Vector3(0.1, sh, (d + 0.3) / nd + 0.02)), Vector3(sx + dir * (0.12 if out else 0.04), sh * 0.5, pz)))
	_multi(box, velvet, pleats[0])
	_multi(box, fold, pleats[1])
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
		flags[fk % 3].append(Transform3D(Basis(Vector3.RIGHT, PI).scaled(Vector3(0.42, 0.5, 0.03)), Vector3(fx, h - 0.5, z1 + 0.24)))
		fx += 0.62
		fk += 1
	var flag_cols := [Color(1.0, 0.36, 0.36), Color(1.0, 0.84, 0.3), Color(0.36, 0.7, 1.0)]
	for f in 3:
		_multi(prism, _mat(_g(flag_cols[f]), 0.8), flags[f])
	# Cream posts along the back, with velvet drapes hanging from the rail.
	var posts: Array = []
	var px := x0
	while px <= x1 + 0.01:
		posts.append(Transform3D(Basis.from_scale(Vector3(0.16, 1.1, 0.16)), Vector3(px, h + 0.55, z0 + 0.08)))
		px += w / 4.0
	posts.append(Transform3D(Basis.from_scale(Vector3(w + 0.1, 0.1, 0.14)), Vector3(cx, h + 1.08, z0 + 0.08)))
	_multi(box, cream, posts)
	var drapes := [[], []]
	var bn := int(ceil(w / pw))
	for k in bn:
		var bx2 := x0 + (k + 0.5) * w / bn
		var out := k % 2 == 0
		drapes[0 if out else 1].append(Transform3D(Basis.from_scale(Vector3(w / bn + 0.02, 0.95, 0.08)), Vector3(bx2, h + 0.52, z0 + (0.0 if out else 0.07))))
	_multi(box, velvet, drapes[0])
	_multi(box, fold, drapes[1])
	# Tall banners at the front corners, in the bunting colours.
	for b in 2:
		var bxp: float = x0 - 0.35 if b == 0 else x1 + 0.35
		_prop(box, cream, Vector3(bxp, (h + 3.2) * 0.5, z1 + 0.35), Vector3(0.12, h + 3.2, 0.12))
		_prop(SphereMesh.new(), gold, Vector3(bxp, h + 3.25, z1 + 0.35), Vector3.ONE * 0.22)
		_prop(box, cream, Vector3(bxp + (0.45 if b == 0 else -0.45), h + 2.95, z1 + 0.35), Vector3(0.95, 0.07, 0.07))
		var bc: Color = flag_cols[0] if b == 0 else flag_cols[2]
		var bxc := bxp + (0.45 if b == 0 else -0.45)
		_prop(box, _mat(_g(bc), 0.85), Vector3(bxc, h + 2.1, z1 + 0.35), Vector3(0.8, 1.6, 0.05))
		var tip := PrismMesh.new()
		_prop(tip, _mat(_g(bc), 0.85), Vector3(bxc, h + 1.08, z1 + 0.35), Vector3(0.8, 0.45, 0.05)).rotation.x = PI
		_prop(box, gold, Vector3(bxc, h + 2.35, z1 + 0.38), Vector3(0.5, 0.5, 0.03)).rotation.z = PI / 4
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
	_multi(box, carpet, steps)
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

	_dress_yard(rng, st, day)

	# Trees: in the yard's corners and beyond the fence.
	for spec in [[-17.0, -6.0, 4.6], [16.0, -7.0, 5.0], [-23.0, -15.0, 5.4], [22.0, -16.0, 5.8], [-9.0, -19.0, 4.8], [9.0, -21.0, 5.2], [0.0, -24.0, 5.6], [-30.0, -9.0, 5.0], [30.0, -8.0, 5.0]]:
		var path := "survival/Tree_Large" if rng.randf() < 0.4 else ("survival/Tree_Autumn" if look.get("key", "") in ["warm", "spooky"] else "survival/Tree")
		var tree: Node3D
		var vx: Array = Voxelizer.model(path, Models.parts(path), spec[2], true) if Voxel.on else []
		if not vx.is_empty():
			tree = MeshInstance3D.new()
			(tree as MeshInstance3D).mesh = vx[0]
			(tree as MeshInstance3D).material_override = vx[1]
		else:
			tree = Models.scene(path).instantiate()
		tree.position = Vector3(spec[0], 0, spec[1])
		tree.scale = Vector3.ONE * spec[2]
		tree.rotation.y = rng.randf() * TAU
		add_child(tree)
		if vx.is_empty():
			Models.toy_node(tree)

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


## A model in the yard: voxels in the voxel style, else the toy look.
func _yard_model(path: String, pos: Vector3, yaw: float, scl: float, sway := false) -> void:
	var node: Node3D
	var vx: Array = Voxelizer.model(path, Models.parts(path), scl, sway) if Voxel.on else []
	if not vx.is_empty():
		node = MeshInstance3D.new()
		(node as MeshInstance3D).mesh = vx[0]
		(node as MeshInstance3D).material_override = vx[1]
	else:
		node = Models.scene(path).instantiate()
	node.position = pos
	node.rotation.y = yaw
	node.scale = Vector3.ONE * scl
	add_child(node)
	if vx.is_empty():
		Models.toy_node(node)


## Life in the backyard (it looked bare): trees beyond the fence, bushes,
## plants and rocks along the sides, a few village props, flowers and voxel
## grass across the lawn. Everything stays clear of the seats and the deck
## (|x| < 9 and -10 < z < 7) and out of the camera's way.
func _dress_yard(rng: RandomNumberGenerator, st: Dictionary, day: bool) -> void:
	var clear := func(p: Vector3) -> bool: return absf(p.x) < 9.5 and p.z > -10.5 and p.z < 7.5
	# Trees behind the fence, in two loose rows.
	var trees := ["nature/Tree/Common_Tree_1", "nature/Tree/Common_Tree_3", "nature/Tree/Common_Tree_5", "nature/Tree/Pine_2", "nature/Tree/Pine_4", "nature/Tree/Twisted_Tree_2"]
	for k in 22:
		var x := rng.randf_range(-34.0, 34.0)
		var z := rng.randf_range(-30.0, -14.0)
		_yard_model(trees[rng.randi() % trees.size()], Vector3(x, 0, z), rng.randf() * TAU, rng.randf_range(1.6, 2.6), true)
	# Bushes, plants and rocks along both sides of the yard.
	var green := ["nature/Bush/Bush_Common", "nature/Bush/Bush_Common_Flowers", "nature/Plant/Plant_1_Big", "nature/Plant/Plant_7_Big", "nature/Plant/Fern_1", "nature/Rock/Rock_Medium_1", "nature/Rock/Rock_Medium_3", "nature/Rock/Pebble_Round_2"]
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 400:
		tries += 1
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var p := Vector3(side * rng.randf_range(10.5, 26.0), 0, rng.randf_range(-10.0, 12.0))
		if clear.call(p):
			continue
		var path: String = green[rng.randi() % green.size()]
		var big := path.contains("Rock_Medium")
		_yard_model(path, p, rng.randf() * TAU, rng.randf_range(0.9, 1.5) * (0.6 if big else 1.0), not path.contains("Rock"))
		placed += 1
	# Village props on the sides: a cart, hay, barrels, crates, a bench, a well.
	var props := [["village/Cart", Vector3(-16.0, 0, -4.0), 0.6], ["village/Hay", Vector3(-13.5, 0, -7.5), 0.3], ["village/Hay", Vector3(-12.2, 0, -6.2), 1.2],
		["village/Barrel", Vector3(13.0, 0, -6.8), 0.0], ["village/Barrel", Vector3(13.9, 0, -6.1), 0.7], ["village/Crate", Vector3(14.6, 0, -7.4), 0.4],
		["village/Crate", Vector3(15.2, 0, -6.4), 1.1], ["village/Bench_1", Vector3(17.0, 0, 2.5), -1.4], ["village/Well", Vector3(19.0, 0, -5.0), 0.3],
		["village/Bonfire", Vector3(-19.0, 0, 3.0), 0.0], ["survival/Signpost", Vector3(11.0, 0, 6.0), -0.6], ["village/Bags", Vector3(-12.0, 0, 1.5), 0.9]]
	for pr in props:
		if ResourceLoader.exists("res://assets/models/" + pr[0] + ".glb") or ResourceLoader.exists("res://assets/models/" + pr[0] + ".gltf"):
			_yard_model(pr[0], pr[1], pr[2], 1.0)
	# Flowers and small plants in the foreground (soft in the depth of field).
	for k in 26:
		var p2 := Vector3(rng.randf_range(-14.0, 14.0), 0, rng.randf_range(8.5, 15.0))
		_yard_model(["nature/Bush/Bush_Common_Flowers", "nature/Plant/Plant_1", "nature/Plant/Fern_1", "nature/Rock/Pebble_Round_4"][rng.randi() % 4], p2, rng.randf() * TAU, rng.randf_range(0.7, 1.2), true)
	# Voxel grass across the lawn (map.gd tufts), not on the deck.
	if Voxel.on:
		var Map = load("res://scripts/map.gd")
		var sh := Shader.new()
		sh.code = Map.VOX_GRASS_SHADER
		var gm := ShaderMaterial.new()
		gm.shader = sh
		var lawn: Color = _g(st.get("lawn", Color(0.36, 0.62, 0.25)))
		gm.set_shader_parameter("base", lawn.darkened(0.25))
		gm.set_shader_parameter("tip", lawn.lightened(0.25))
		gm.set_shader_parameter("sway", 0.06)
		var spots: Array = []
		while spots.size() < 1800:
			var p3 := Vector3(rng.randf_range(-30.0, 30.0), 0, rng.randf_range(-10.5, 16.0))
			if absf(p3.x) < 8.6 and p3.z > -10.0 and p3.z < 6.5:
				continue
			spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.6, 1.0)), p3))
		_multi(Map._vox_tuft("grass"), gm, spots)


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
	mi.material_override = _vox(mat)
	add_child(mi)


## In the voxel world style, a plain material drawn as voxels.
func _vox(mat: Material) -> Material:
	return Voxel.from_standard(mat) if Voxel.on and mat is BaseMaterial3D else mat


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
