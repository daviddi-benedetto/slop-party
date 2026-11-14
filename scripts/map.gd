extends Node3D
## The arena ("Toy Park"). Everything is generated in code: geometry,
## materials, textures, lighting, scenery, spawn points, jump pads and the bot
## nav graph.
##
## Layout (metres, Y up): floor is 64 x 48 centred on the origin. Almost every
## piece is added with mirror=true, which also places a copy rotated 180 deg
## about the Y axis ((x, z) -> (-x, -z)), so the map is point-symmetric.
##
## Look: soft toy-like shapes. _box() meshes have rounded edges (the collision
## stays a plain box). Materials are pastel colours with faint world-space
## triplanar detail textures. Scenery outside the walls (hills, trees, clouds)
## and decorations (bunting, balloons, bushes) have no collision.
##
## Collision layers: 1 = world (this file), 2 = players.
##
## Nav graph: build_nav() samples a 2 m grid with downward ray-casts (several
## height layers, so space under decks counts too), links neighbours that are
## actually walkable, and keeps the largest connected component in an AStar3D.

const HALF_X := 32.0
const HALF_Z := 24.0
const NAV_STEP := 2.0
const WALL_H := 4.5

var spawn_points: Array = []      # Array of Vector3
var nav := AStar3D.new()
var nav_ready := false
var _nav_ids := PackedInt64Array()
var _body: StaticBody3D
var _mats := {}
var _box_cache := {}
var _unit_sphere: SphereMesh
var _rng := RandomNumberGenerator.new()

# Animated decorations.
var _clouds: Node3D
var _balloons: Array = []         # [node, base_y, phase]
var _pad_rings: Array = []        # [mesh_instance, material, phase]
var _time := 0.0


func build() -> void:
	_rng.seed = 20240607
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
	_build_geometry()
	_build_scenery()


func _process(delta: float) -> void:
	_time += delta
	if _clouds != null:
		_clouds.rotation.y += delta * 0.006
	for b in _balloons:
		b[0].position.y = b[1] + sin(_time * 1.3 + b[2]) * 0.12
		b[0].rotation.z = sin(_time * 0.9 + b[2]) * 0.08
	for r in _pad_rings:
		var t := fmod(_time * 0.8 + r[2], 1.0)
		r[0].position.y = 0.15 + t * 1.6
		r[0].scale = Vector3.ONE * (1.0 - t * 0.35)
		r[1].albedo_color.a = (1.0 - t) * 0.8


# --------------------------------------------------------------------------
# Materials / procedural textures
# --------------------------------------------------------------------------

func _make_materials() -> void:
	_mats["grass"] = _mat(Color(0.5, 0.8, 0.38), _texture("soft"), 0.07)
	_mats["path"] = _mat(Color(1.0, 0.88, 0.62), _texture("soft"), 0.11)
	_mats["wall"] = _mat(Color(1.0, 0.94, 0.8), _texture("panels"), 0.25)
	_mats["coral"] = _mat(Color(1.0, 0.47, 0.42), null, 1.0)
	_mats["stone"] = _mat(Color(0.93, 0.91, 0.96), _texture("panels"), 0.25)
	_mats["teal"] = _mat(Color(0.16, 0.74, 0.72), null, 1.0)
	_mats["wood"] = _mat(Color(1.0, 0.75, 0.42), _texture("planks"), 0.5)
	_mats["blue"] = _mat(Color(0.26, 0.56, 1.0), null, 1.0)
	_mats["pink"] = _mat(Color(1.0, 0.62, 0.7), _texture("bricks"), 0.4)
	_mats["roof"] = _mat(Color(0.5, 0.42, 0.92), _texture("planks"), 0.35)
	_mats["block_r"] = _mat(Color(1.0, 0.4, 0.4), _texture("soft"), 0.3)
	_mats["block_y"] = _mat(Color(1.0, 0.82, 0.25), _texture("soft"), 0.3)
	_mats["block_b"] = _mat(Color(0.3, 0.66, 1.0), _texture("soft"), 0.3)
	_mats["block_g"] = _mat(Color(0.4, 0.85, 0.5), _texture("soft"), 0.3)
	_mats["stripes"] = _mat(Color.WHITE, _texture("stripes"), 0.7)
	_mats["barrel"] = _mat(Color(1.0, 0.58, 0.2), null, 1.0)
	_mats["trunk"] = _mat(Color(0.62, 0.42, 0.28), null, 1.0)
	_mats["leaf_a"] = _mat(Color(0.3, 0.72, 0.36), null, 1.0)
	_mats["leaf_b"] = _mat(Color(0.45, 0.82, 0.38), null, 1.0)
	_mats["leaf_c"] = _mat(Color(0.98, 0.6, 0.72), null, 1.0)
	_mats["hill_a"] = _mat(Color(0.42, 0.76, 0.4), null, 1.0)
	_mats["hill_b"] = _mat(Color(0.52, 0.82, 0.46), null, 1.0)
	_mats["pad_base"] = _mat(Color(0.24, 0.2, 0.36), null, 1.0)
	for k in _mats:
		_mats[k].diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var cloud := StandardMaterial3D.new()
	cloud.albedo_color = Color(1, 1, 1)
	cloud.emission_enabled = true
	cloud.emission = Color(0.85, 0.9, 1.0)
	cloud.emission_energy_multiplier = 0.55
	cloud.roughness = 1.0
	cloud.disable_fog = true
	_mats["cloud"] = cloud
	var pad := StandardMaterial3D.new()
	pad.albedo_color = Color(0.3, 1.0, 0.9)
	pad.emission_enabled = true
	pad.emission = Color(0.2, 1.0, 0.85)
	pad.emission_energy_multiplier = 2.2
	_mats["pad"] = pad


func _mat(tint: Color, tex: Texture2D, uv_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = 0.9
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * uv_scale
	return m


func _glossy(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.22
	m.rim_enabled = true
	m.rim = 0.6
	return m


## Tileable detail textures, multiplied by the material tint. Deliberately
## low contrast so surfaces read as painted toys rather than gritty materials.
func _texture(kind: String) -> ImageTexture:
	const N := 256
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	const P := 16
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

	var img := Image.create(N, N, true, Image.FORMAT_RGB8)
	for py in N:
		for px in N:
			var u := float(px) / N
			var v := float(py) / N
			var n: float = noise.call(u, v, 4) * 0.65 + noise.call(u, v, 8) * 0.35
			var val := 0.9 + n * 0.1
			var col := Color(val, val, val)
			match kind:
				"soft":
					val = 0.84 + n * 0.16
					col = Color(val, val, val)
				"panels":
					if px % 128 < 3 or py % 128 < 3:
						val *= 0.86
					col = Color(val, val, val)
				"planks":
					var plank := py / 32
					val *= 0.92 + 0.08 * lattice[plank % (P * P)]
					if py % 32 < 3 or (px + plank * 67) % 128 < 3:
						val *= 0.8
					col = Color(val, val, val)
				"bricks":
					var row := py / 32
					var bx := (px + (row % 2) * 32) % 64
					val *= 0.93 + 0.07 * lattice[(row * 5 + ((px + (row % 2) * 32) / 64) * 3) % (P * P)]
					if py % 32 < 3 or bx < 3:
						val = 1.0
					col = Color(val, val, val)
				"stripes":
					var band := ((px + py) % 128) < 64
					col = Color(1.0, 0.36, 0.38) if band else Color(1.0, 0.98, 0.94)
			img.set_pixel(px, py, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --------------------------------------------------------------------------
# Lighting
# --------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.5, 0.98)
	sky_mat.sky_horizon_color = Color(0.72, 0.9, 1.0)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.72, 0.9, 1.0)
	sky_mat.ground_bottom_color = Color(0.45, 0.75, 0.5)
	sky_mat.sun_angle_max = 12.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.5
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.88, 1.0)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	var dbg := OS.get_cmdline_user_args()
	if "--noglow" in dbg: env.glow_enabled = false
	if "--nossao" in dbg: env.ssao_enabled = false
	if "--nofog" in dbg: env.fog_enabled = false
	if "--noadj" in dbg: env.adjustment_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.shadow_opacity = 0.8
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_bias = 0.06
	if "--noshadow" in dbg: sun.shadow_enabled = false
	add_child(sun)


# --------------------------------------------------------------------------
# Geometry
# --------------------------------------------------------------------------

func _build_geometry() -> void:
	# Floor, painted paths, perimeter (visual wall is low; collision is tall).
	_collider(Vector3(0, -0.5, 0), Vector3(66, 1, 50))
	_visual(Vector3(0, -0.5, 0), Vector3(140, 1, 120), "grass")
	_visual(Vector3(0, 0.006, 0), Vector3(64, 0.012, 7), "path")
	_visual(Vector3(0, 0.008, 0), Vector3(7, 0.012, 48), "path")
	for sgn in [1.0, -1.0]:
		_collider(Vector3(0, 8, sgn * (HALF_Z + 0.5)), Vector3(66, 16, 1))
		_collider(Vector3(sgn * (HALF_X + 0.5), 8, 0), Vector3(1, 16, 50))
	_box(Vector3(0, WALL_H * 0.5, HALF_Z + 0.5), Vector3(66, WALL_H, 1), "wall", true, 0.0, false)
	_box(Vector3(HALF_X + 0.5, WALL_H * 0.5, 0), Vector3(1, WALL_H, 50), "wall", true, 0.0, false)
	_box(Vector3(0, WALL_H + 0.2, HALF_Z + 0.5), Vector3(66.6, 0.5, 1.5), "coral", true, 0.0, false)
	_box(Vector3(HALF_X + 0.5, WALL_H + 0.2, 0), Vector3(1.5, 0.5, 50.6), "coral", true, 0.0, false)
	_box(Vector3(0, 0.3, HALF_Z + 0.02), Vector3(64, 0.6, 0.25), "teal", true, 0.0, false)
	_box(Vector3(HALF_X + 0.02, 0.3, 0), Vector3(0.25, 0.6, 48), "teal", true, 0.0, false)

	# Centre platform with east/west ramps.
	_box(Vector3(0, 1.5, 0), Vector3(12, 3, 12), "stone", false)
	_box(Vector3(0, 2.55, 0), Vector3(12.12, 0.5, 12.12), "teal", false, 0.0, false)
	_wedge(Vector3(10, 0, 0), Vector3(8, 3, 5), PI, "wood")
	_box(Vector3(0, 3.65, 0), Vector3(2.4, 1.3, 2.4), "block_y", false, 0.5)
	_box(Vector3(4.6, 3.5, -4.2), Vector3(0.5, 1.0, 3.0), "stripes")

	# Bridge from the platform to the north deck (mirrored: south deck).
	_box(Vector3(0, 2.8, 10), Vector3(3, 0.4, 8), "wood")
	_box(Vector3(1.55, 3.45, 10), Vector3(0.15, 0.9, 8), "blue")
	_box(Vector3(-1.55, 3.45, 10), Vector3(0.15, 0.9, 8), "blue")

	# North deck on pillars, ramp down to the west, jump pad on the east.
	_box(Vector3(0, 2.8, 18), Vector3(16, 0.4, 8), "wood")
	for px in [-7.0, 7.0]:
		for pz in [15.0, 21.0]:
			_box(Vector3(px, 1.3, pz), Vector3(0.8, 2.6, 0.8), "blue")
	_wedge(Vector3(-12, 0, 18), Vector3(8, 3, 4), 0.0, "wood")
	_box(Vector3(-4.75, 3.45, 14.1), Vector3(6.5, 0.9, 0.2), "blue")
	_box(Vector3(4.75, 3.45, 14.1), Vector3(6.5, 0.9, 0.2), "blue")
	_box(Vector3(4, 3.6, 20.5), Vector3(3, 1.2, 0.5), "stripes")
	_jump_pad(Vector3(9.6, 0, 18), 14.5)

	# Pink hut with two doors.
	_box(Vector3(-27.3, 1.6, 13), Vector3(0.4, 3.2, 9), "pink")
	_box(Vector3(-23, 1.6, 17.3), Vector3(9, 3.2, 0.4), "pink")
	_box(Vector3(-18.7, 1.6, 10.15), Vector3(0.4, 3.2, 3.3), "pink")
	_box(Vector3(-18.7, 1.6, 15.85), Vector3(0.4, 3.2, 3.3), "pink")
	_box(Vector3(-18.7, 2.8, 13), Vector3(0.4, 0.8, 2.4), "pink")
	_box(Vector3(-25.85, 1.6, 8.7), Vector3(3.3, 3.2, 0.4), "pink")
	_box(Vector3(-20.15, 1.6, 8.7), Vector3(3.3, 3.2, 0.4), "pink")
	_box(Vector3(-23, 2.8, 8.7), Vector3(2.4, 0.8, 0.4), "pink")
	_box(Vector3(-23, 3.4, 13), Vector3(9.8, 0.4, 9.8), "roof")
	_box(Vector3(-26.2, 0.6, 16.2), Vector3(1.2, 1.2, 1.2), "block_b", true, 0.2)
	_lamp(Vector3(-23, 2.7, 13))

	# Lane-splitting wall, toy blocks, striped barriers, barrels.
	_box(Vector3(16, 2, -5), Vector3(1, 4, 9), "stone")
	_box(Vector3(16, 4.15, -5), Vector3(1.3, 0.3, 9.3), "coral", true, 0.0, false)
	_box(Vector3(22, 1.25, 14), Vector3(2.5, 2.5, 2.5), "block_r", true, 0.15)
	_box(Vector3(24.7, 1.0, 13.0), Vector3(2, 2, 2), "block_b", true, -0.3)
	_box(Vector3(22.2, 3.25, 14.1), Vector3(1.5, 1.5, 1.5), "block_y", true, 0.6)
	_box(Vector3(14, 0.6, 21), Vector3(1.2, 1.2, 1.2), "block_g", true, 0.4)
	_box(Vector3(-6, 0.75, -16.5), Vector3(1.5, 1.5, 1.5), "block_r", true, 0.25)
	_box(Vector3(9, 0.6, -9.5), Vector3(5, 1.2, 0.6), "stripes")
	_box(Vector3(-12, 0.6, -11), Vector3(0.6, 1.2, 5), "stripes")
	_box(Vector3(27, 0.6, 3), Vector3(0.6, 1.2, 6), "stripes")
	_barrel(Vector3(20, 0, -20.5))
	_barrel(Vector3(21.3, 0, -19.8))
	_barrel(Vector3(-3, 0, 22.6))
	_barrel(Vector3(30.5, 0, 9))

	for p in [Vector3(28, 0.1, 20.5), Vector3(29.5, 0.1, -6), Vector3(-18, 0.1, 21.5),
			Vector3(24, 0.1, -21.5), Vector3(-23, 0.1, 13)]:
		spawn_points.append(p)
		spawn_points.append(Vector3(-p.x, p.y, -p.z))


func _collider(pos: Vector3, size: Vector3, yaw := 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	_body.add_child(cs)


func _visual(pos: Vector3, size: Vector3, mat: String, yaw := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _rounded_box(size)
	mi.material_override = _mats[mat]
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	add_child(mi)


func _box(pos: Vector3, size: Vector3, mat: String, mirror := true, yaw := 0.0, collide := true) -> void:
	var copies := [[pos, yaw]]
	if mirror:
		copies.append([Vector3(-pos.x, pos.y, -pos.z), yaw + PI])
	for c in copies:
		if collide:
			_collider(c[0], size, c[1])
		_visual(c[0], size, mat, c[1])


## Box mesh with rounded edges, built at its real size so the bevel radius is
## not distorted by scaling. Cached per size.
func _rounded_box(size: Vector3) -> ArrayMesh:
	var key := "%.3f,%.3f,%.3f" % [size.x, size.y, size.z]
	if _box_cache.has(key):
		return _box_cache[key]
	const SEG := 2
	var h := size * 0.5
	var r := minf(0.14, minf(size.x, minf(size.y, size.z)) * 0.3)
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
		# Painted side rails so the ramp reads as a toy slide.
		for side in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var length := sqrt(size.x * size.x + size.y * size.y)
			rail.mesh = _rounded_box(Vector3(length, 0.22, 0.22))
			rail.material_override = _mats["coral"]
			rail.transform = xf * Transform3D(Basis(Vector3.BACK, atan2(size.y, size.x)), Vector3(0, h * 0.5 + 0.06, side * (w - 0.05)))
			add_child(rail)


func _barrel(pos: Vector3, mirror := true) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.42
	mesh.height = 1.2
	mesh.radial_segments = 18
	var band := CylinderMesh.new()
	band.top_radius = 0.46
	band.bottom_radius = 0.46
	band.height = 0.14
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
		_prop(mesh, "barrel", s + Vector3(0, 0.6, 0))
		_prop(band, "wall", s + Vector3(0, 0.95, 0))
		_prop(band, "wall", s + Vector3(0, 0.25, 0))


func _prop(mesh: Mesh, mat, pos: Vector3, scl := Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[mat] if mat is String else mat
	mi.position = pos
	mi.scale = scl
	(parent if parent != null else self).add_child(mi)
	return mi


func _lamp(pos: Vector3) -> void:
	for s in [pos, Vector3(-pos.x, pos.y, -pos.z)]:
		var l := OmniLight3D.new()
		l.position = s
		l.light_color = Color(1.0, 0.85, 0.6)
		l.light_energy = 1.4
		l.omni_range = 9.0
		add_child(l)


## Launches any player that steps on it straight up.
func _jump_pad(pos: Vector3, power: float) -> void:
	for s in [pos, Vector3(-pos.x, pos.y, -pos.z)]:
		var base := CylinderMesh.new()
		base.top_radius = 1.15
		base.bottom_radius = 1.3
		base.height = 0.14
		_prop(base, "pad_base", s + Vector3(0, 0.07, 0))
		var top := CylinderMesh.new()
		top.top_radius = 0.9
		top.bottom_radius = 0.9
		top.height = 0.06
		_prop(top, "pad", s + Vector3(0, 0.16, 0))
		var torus := TorusMesh.new()
		torus.inner_radius = 0.78
		torus.outer_radius = 0.9
		torus.rings = 28
		torus.ring_segments = 6
		for i in 3:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.4, 1.0, 0.9, 0.8)
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
				Sfx.play("pad", -8.0))


# --------------------------------------------------------------------------
# Scenery (no gameplay effect)
# --------------------------------------------------------------------------

func _build_scenery() -> void:
	# Rolling hills on the horizon.
	for i in 16:
		var a := TAU * i / 16.0 + _rng.randf_range(-0.12, 0.12)
		var d := _rng.randf_range(78.0, 120.0)
		var rad := _rng.randf_range(26.0, 46.0)
		var hill := _prop(_unit_sphere, "hill_a" if i % 2 == 0 else "hill_b",
			Vector3(cos(a) * d, -4.0, sin(a) * d), Vector3(rad, rad * _rng.randf_range(0.3, 0.5), rad))
		hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Trees: a ring outside the walls plus one in each inside corner.
	for i in 46:
		var a2 := TAU * i / 46.0 + _rng.randf_range(-0.05, 0.05)
		var dir := Vector2(cos(a2), sin(a2))
		var edge := minf((HALF_X + 4.0) / maxf(absf(dir.x), 0.001), (HALF_Z + 4.0) / maxf(absf(dir.y), 0.001))
		var d2 := edge + _rng.randf_range(1.0, 16.0)
		_tree(Vector3(dir.x * d2, 0, dir.y * d2), _rng.randf_range(0.9, 1.5), false)
	for c in [Vector3(30.3, 0, 22.4), Vector3(-30.3, 0, 22.4)]:
		_tree(c, 1.0, true)
		_tree(Vector3(-c.x, 0, -c.z), 1.0, true)

	# Bushes hugging the inside of the walls.
	for i in 26:
		var along := _rng.randf_range(-1.0, 1.0)
		var pos: Vector3
		match i % 4:
			0: pos = Vector3(along * (HALF_X - 2.0), 0, HALF_Z - 0.5)
			1: pos = Vector3(along * (HALF_X - 2.0), 0, -HALF_Z + 0.5)
			2: pos = Vector3(HALF_X - 0.5, 0, along * (HALF_Z - 2.0))
			_: pos = Vector3(-HALF_X + 0.5, 0, along * (HALF_Z - 2.0))
		var rad2 := _rng.randf_range(0.5, 0.85)
		var mat := "leaf_c" if i % 7 == 0 else ("leaf_a" if i % 2 == 0 else "leaf_b")
		_prop(_unit_sphere, mat, pos + Vector3(0, rad2 * 0.45, 0), Vector3(rad2, rad2 * 0.75, rad2))

	# Clouds drifting slowly around the arena.
	_clouds = Node3D.new()
	_clouds.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_clouds)
	for i in 15:
		var a3 := TAU * i / 15.0 + _rng.randf_range(-0.2, 0.2)
		var d3 := _rng.randf_range(55.0, 130.0)
		var centre := Vector3(cos(a3) * d3, _rng.randf_range(26.0, 48.0), sin(a3) * d3)
		var big := _rng.randf_range(3.5, 7.0)
		for j in 5:
			var off := Vector3((j - 2) * big * 0.75, _rng.randf_range(-0.2, 0.5) * big, _rng.randf_range(-0.4, 0.4) * big)
			var rr := big * (1.0 - absf(j - 2) * 0.22) * _rng.randf_range(0.85, 1.1)
			var puff := _prop(_unit_sphere, "cloud", centre + off, Vector3(rr, rr * 0.7, rr), _clouds)
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Bunting across the corners and balloons on the roofs.
	for sgn in [1.0, -1.0]:
		_bunting(Vector3(-HALF_X, WALL_H + 0.4, sgn * 6.0), Vector3(-12.0, WALL_H + 0.4, sgn * HALF_Z))
		_bunting(Vector3(HALF_X, WALL_H + 0.4, sgn * 6.0), Vector3(12.0, WALL_H + 0.4, sgn * HALF_Z))
	for p in [Vector3(-18.6, 3.6, 8.6), Vector3(-27.4, 3.6, 17.4), Vector3(7.6, 3.0, 21.6), Vector3(16, 4.3, -9.2)]:
		_balloon_bunch(p)
		_balloon_bunch(Vector3(-p.x, p.y, -p.z))


func _tree(pos: Vector3, scl: float, solid: bool) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.28 * scl
	trunk.bottom_radius = 0.4 * scl
	trunk.height = 3.6 * scl
	trunk.radial_segments = 10
	_prop(trunk, "trunk", pos + Vector3(0, 1.8 * scl, 0))
	var mat := "leaf_c" if _rng.randf() < 0.14 else ("leaf_a" if _rng.randf() < 0.5 else "leaf_b")
	_prop(_unit_sphere, mat, pos + Vector3(0, 4.6 * scl, 0), Vector3(2.2, 2.0, 2.2) * scl)
	_prop(_unit_sphere, mat, pos + Vector3(0.9 * scl, 3.9 * scl, 0.5 * scl), Vector3(1.5, 1.3, 1.5) * scl)
	_prop(_unit_sphere, mat, pos + Vector3(-0.8 * scl, 4.1 * scl, -0.6 * scl), Vector3(1.6, 1.4, 1.6) * scl)
	if solid:
		var shape := CylinderShape3D.new()
		shape.radius = 0.4
		shape.height = 4.0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = pos + Vector3(0, 2.0, 0)
		_body.add_child(cs)


## A sagging string of little triangular flags between two points.
func _bunting(from: Vector3, to: Vector3) -> void:
	var colors := [Color(1.0, 0.4, 0.42), Color(1.0, 0.82, 0.25), Color(0.3, 0.66, 1.0), Color(0.4, 0.85, 0.5), Color(0.75, 0.5, 1.0)]
	var count := int(from.distance_to(to) / 0.85)
	var along := (to - from).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var line := SurfaceTool.new()
	line.begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in count + 1:
		var t := float(i) / count
		var p := from.lerp(to, t) + Vector3(0, -4.0 * 1.6 * t * (1.0 - t), 0)
		line.set_color(Color(0.3, 0.25, 0.35))
		line.add_vertex(p)
		if i < count:
			var t2 := float(i + 1) / count
			var q := from.lerp(to, t2) + Vector3(0, -4.0 * 1.6 * t2 * (1.0 - t2), 0)
			var a := p.lerp(q, 0.12)
			var b := p.lerp(q, 0.88)
			var tip := (a + b) * 0.5 + Vector3(0, -0.6, 0)
			for vtx in [a, b, tip]:
				st.set_color(colors[i % colors.size()])
				st.set_normal(along.cross(Vector3.UP).normalized())
				st.add_vertex(vtx)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.vertex_color_use_as_albedo = true
	var li := MeshInstance3D.new()
	li.mesh = line.commit()
	li.material_override = lmat
	li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(li)


func _balloon_bunch(anchor: Vector3) -> void:
	var cols := [Color(1.0, 0.36, 0.4), Color(1.0, 0.82, 0.25), Color(0.3, 0.66, 1.0), Color(0.45, 0.88, 0.5), Color(0.78, 0.5, 1.0)]
	for i in 3:
		var holder := Node3D.new()
		holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		var top := anchor + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(1.9, 2.7), _rng.randf_range(-0.5, 0.5))
		holder.position = top
		add_child(holder)
		_prop(_unit_sphere, _glossy(cols[_rng.randi() % cols.size()]), Vector3.ZERO, Vector3(0.42, 0.5, 0.42), holder)
		var string := CylinderMesh.new()
		string.top_radius = 0.012
		string.bottom_radius = 0.012
		string.height = top.y - anchor.y - 0.45
		string.radial_segments = 4
		var smi := _prop(string, "wall", Vector3(0, -0.45 - string.height * 0.5, 0), Vector3.ONE, holder)
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_balloons.append([holder, top.y, _rng.randf() * TAU])


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
	var x := -HALF_X + 1.0
	while x < HALF_X:
		var z := -HALF_Z + 1.0
		while z < HALF_Z:
			var top := 12.0
			for layer in 4:
				var hit := _ray(Vector3(x, top, z), Vector3(x, -0.5, z))
				if hit.is_empty():
					break
				var p: Vector3 = hit.position
				top = p.y - 0.5
				if hit.normal.y > 0.7 and p.y < 6.0:
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
	print("[map] nav graph: %d nodes, %d links" % [best.size(), links.size()])


func _walkable(a: Vector3, b: Vector3) -> bool:
	if absf(a.y - b.y) > 1.25:
		return false
	# Ground must be continuous under the segment.
	for t in [0.25, 0.5, 0.75]:
		var m := a.lerp(b, t)
		var hit := _ray(m + Vector3(0, 1.0, 0), m + Vector3(0, -0.6, 0))
		if hit.is_empty() or absf(hit.position.y - m.y) > 0.45:
			return false
	# Body-width corridor must be clear.
	var dir := (b - a)
	dir.y = 0.0
	var side := dir.normalized().cross(Vector3.UP) * 0.38
	for off in [Vector3.ZERO, side, -side]:
		for hgt in [0.7, 1.5]:
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
