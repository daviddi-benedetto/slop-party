extends Node3D
## The arena ("Depot"). Everything is generated in code: geometry, materials,
## textures, lighting, spawn points, jump pads and the bot nav graph.
##
## Layout (metres, Y up): floor is 64 x 48 centred on the origin. Almost every
## piece is added with mirror=true, which also places a copy rotated 180 deg
## about the Y axis ((x, z) -> (-x, -z)), so the map is point-symmetric.
##
## Collision layers: 1 = world (this file), 2 = players.
##
## Nav graph: build_nav() samples a 2 m grid with downward ray-casts (several
## height layers, so space under decks counts too), links neighbours that are
## actually walkable, and keeps the largest connected component in an AStar3D.

const HALF_X := 32.0
const HALF_Z := 24.0
const NAV_STEP := 2.0

var spawn_points: Array = []      # Array of Vector3
var nav := AStar3D.new()
var nav_ready := false
var _nav_ids := PackedInt64Array()
var _body: StaticBody3D
var _mats := {}
var _unit_box: BoxMesh


func build() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_make_materials()
	_build_environment()
	_build_geometry()


# --------------------------------------------------------------------------
# Materials / procedural textures
# --------------------------------------------------------------------------

func _make_materials() -> void:
	_mats["ground"] = _mat(Color(0.74, 0.62, 0.44), _texture("dirt"), 0.16)
	_mats["concrete"] = _mat(Color(0.74, 0.71, 0.65), _texture("panels"), 0.25)
	_mats["brick"] = _mat(Color(0.72, 0.4, 0.3), _texture("bricks"), 0.4)
	_mats["wood"] = _mat(Color(0.68, 0.48, 0.28), _texture("planks"), 0.5)
	_mats["metal"] = _mat(Color(0.36, 0.44, 0.52), _texture("panels"), 0.5)
	_mats["metal"].roughness = 0.55
	_mats["metal"].metallic = 0.3
	_mats["trim"] = _mat(Color(0.2, 0.2, 0.22), null, 1.0)
	_mats["barrel"] = _mat(Color(0.8, 0.3, 0.15), _texture("panels"), 1.0)
	var pad := StandardMaterial3D.new()
	pad.albedo_color = Color(0.2, 0.9, 1.0)
	pad.emission_enabled = true
	pad.emission = Color(0.1, 0.8, 1.0)
	pad.emission_energy_multiplier = 1.5
	_mats["pad"] = pad


func _mat(tint: Color, tex: Texture2D, uv_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = 0.92
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * uv_scale
	return m


## Greyscale, tileable detail textures (multiplied by the material tint).
func _texture(kind: String) -> ImageTexture:
	const N := 256
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	# Tileable value-noise lattice.
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
			var n: float = noise.call(u, v, 4) * 0.6 + noise.call(u, v, 16) * 0.4
			var val := 0.82 + n * 0.18
			match kind:
				"dirt":
					val = 0.7 + n * 0.3
				"panels":
					if px % 128 < 2 or py % 128 < 2:
						val *= 0.72
				"planks":
					var plank := py / 32
					val *= 0.86 + 0.14 * lattice[plank % (P * P)]
					val *= 0.94 + 0.06 * sin(u * TAU * 24.0 + n * 9.0)
					if py % 32 < 2 or (px + plank * 67) % 128 < 2:
						val *= 0.62
				"bricks":
					var row := py / 32
					var bx := (px + (row % 2) * 32) % 64
					val *= 0.84 + 0.16 * lattice[(row * 5 + ((px + (row % 2) * 32) / 64) * 3) % (P * P)]
					if py % 32 < 3 or bx < 3:
						val = 0.78 + n * 0.1
			val = clampf(val, 0.0, 1.0)
			img.set_pixel(px, py, Color(val, val, val))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --------------------------------------------------------------------------
# Lighting
# --------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.72)
	sky_mat.sky_horizon_color = Color(0.9, 0.78, 0.62)
	sky_mat.ground_horizon_color = Color(0.9, 0.78, 0.62)
	sky_mat.ground_bottom_color = Color(0.35, 0.28, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.9, 0.8, 0.68)
	env.fog_density = 0.0006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 38.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.06
	add_child(sun)


# --------------------------------------------------------------------------
# Geometry
# --------------------------------------------------------------------------

func _build_geometry() -> void:
	# Floor and perimeter.
	_box(Vector3(0, -0.5, 0), Vector3(66, 1, 50), "ground", false)
	_box(Vector3(0, 3.5, HALF_Z + 0.5), Vector3(66, 7, 1), "brick")
	_box(Vector3(HALF_X + 0.5, 3.5, 0), Vector3(1, 7, 50), "brick")
	_box(Vector3(0, 7.15, HALF_Z + 0.5), Vector3(66.4, 0.3, 1.4), "trim")
	_box(Vector3(HALF_X + 0.5, 7.15, 0), Vector3(1.4, 0.3, 50.4), "trim")
	_box(Vector3(0, 0.5, HALF_Z - 0.05), Vector3(64, 1.0, 0.1), "concrete")
	_box(Vector3(HALF_X - 0.05, 0.5, 0), Vector3(0.1, 1.0, 48), "concrete")

	# Centre platform with east/west ramps.
	_box(Vector3(0, 1.5, 0), Vector3(12, 3, 12), "concrete", false)
	_wedge(Vector3(10, 0, 0), Vector3(8, 3, 5), PI, "wood")
	_box(Vector3(0, 3.65, 0), Vector3(2.4, 1.3, 2.4), "wood", false, 0.5)
	_box(Vector3(4.6, 3.5, -4.2), Vector3(0.5, 1.0, 3.0), "concrete")

	# Bridge from the platform to the north deck (mirrored: south deck).
	_box(Vector3(0, 2.8, 10), Vector3(3, 0.4, 8), "wood")
	_box(Vector3(1.55, 3.45, 10), Vector3(0.15, 0.9, 8), "metal")
	_box(Vector3(-1.55, 3.45, 10), Vector3(0.15, 0.9, 8), "metal")

	# North deck on pillars, ramp down to the west, jump pad on the east.
	_box(Vector3(0, 2.8, 18), Vector3(16, 0.4, 8), "wood")
	for px in [-7.0, 7.0]:
		for pz in [15.0, 21.0]:
			_box(Vector3(px, 1.3, pz), Vector3(0.8, 2.6, 0.8), "metal")
	_wedge(Vector3(-12, 0, 18), Vector3(8, 3, 4), 0.0, "wood")
	_box(Vector3(-4.75, 3.45, 14.1), Vector3(6.5, 0.9, 0.2), "metal")
	_box(Vector3(4.75, 3.45, 14.1), Vector3(6.5, 0.9, 0.2), "metal")
	_box(Vector3(4, 3.6, 20.5), Vector3(3, 1.2, 0.5), "concrete")
	_jump_pad(Vector3(9.6, 0, 18), 14.5)

	# Brick hut with two doors.
	_box(Vector3(-27.3, 1.6, 13), Vector3(0.4, 3.2, 9), "brick")
	_box(Vector3(-23, 1.6, 17.3), Vector3(9, 3.2, 0.4), "brick")
	_box(Vector3(-18.7, 1.6, 10.15), Vector3(0.4, 3.2, 3.3), "brick")
	_box(Vector3(-18.7, 1.6, 15.85), Vector3(0.4, 3.2, 3.3), "brick")
	_box(Vector3(-18.7, 2.8, 13), Vector3(0.4, 0.8, 2.4), "brick")
	_box(Vector3(-25.85, 1.6, 8.7), Vector3(3.3, 3.2, 0.4), "brick")
	_box(Vector3(-20.15, 1.6, 8.7), Vector3(3.3, 3.2, 0.4), "brick")
	_box(Vector3(-23, 2.8, 8.7), Vector3(2.4, 0.8, 0.4), "brick")
	_box(Vector3(-23, 3.4, 13), Vector3(9.8, 0.4, 9.8), "metal")
	_box(Vector3(-26.2, 0.6, 16.2), Vector3(1.2, 1.2, 1.2), "wood", true, 0.2)
	_lamp(Vector3(-23, 2.7, 13))

	# Lane-splitting wall, crates, low cover, barrels.
	_box(Vector3(16, 2, -5), Vector3(1, 4, 9), "concrete")
	_box(Vector3(16, 4.1, -5), Vector3(1.3, 0.2, 9.3), "trim")
	_box(Vector3(22, 1.25, 14), Vector3(2.5, 2.5, 2.5), "wood", true, 0.15)
	_box(Vector3(24.7, 1.0, 13.0), Vector3(2, 2, 2), "wood", true, -0.3)
	_box(Vector3(22.2, 3.25, 14.1), Vector3(1.5, 1.5, 1.5), "wood", true, 0.6)
	_box(Vector3(14, 0.6, 21), Vector3(1.2, 1.2, 1.2), "wood", true, 0.4)
	_box(Vector3(-6, 0.75, -16.5), Vector3(1.5, 1.5, 1.5), "wood", true, 0.25)
	_box(Vector3(9, 0.6, -9.5), Vector3(5, 1.2, 0.6), "concrete")
	_box(Vector3(-12, 0.6, -11), Vector3(0.6, 1.2, 5), "concrete")
	_box(Vector3(27, 0.6, 3), Vector3(0.6, 1.2, 6), "concrete")
	_barrel(Vector3(20, 0, -20.5))
	_barrel(Vector3(21.3, 0, -19.8))
	_barrel(Vector3(-3, 0, 22.6))
	_barrel(Vector3(30.5, 0, 9))

	for p in [Vector3(28, 0.1, 20.5), Vector3(29.5, 0.1, -6), Vector3(-18, 0.1, 21.5),
			Vector3(24, 0.1, -21.5), Vector3(-23, 0.1, 13)]:
		spawn_points.append(p)
		spawn_points.append(Vector3(-p.x, p.y, -p.z))


func _box(pos: Vector3, size: Vector3, mat: String, mirror := true, yaw := 0.0) -> void:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var copies := [Transform3D(Basis(Vector3.UP, yaw), pos)]
	if mirror:
		copies.append(Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(-pos.x, pos.y, -pos.z)))
	for xf in copies:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = xf
		_body.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = _unit_box
		mi.material_override = _mats[mat]
		mi.transform = xf.scaled_local(size)
		add_child(mi)


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


func _barrel(pos: Vector3, mirror := true) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.45
	mesh.height = 1.2
	mesh.radial_segments = 14
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
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mats["barrel"]
		mi.position = s + Vector3(0, 0.6, 0)
		add_child(mi)


func _lamp(pos: Vector3) -> void:
	for s in [pos, Vector3(-pos.x, pos.y, -pos.z)]:
		var l := OmniLight3D.new()
		l.position = s
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = 1.6
		l.omni_range = 9.0
		add_child(l)


## Launches any player that steps on it straight up.
func _jump_pad(pos: Vector3, power: float) -> void:
	for s in [pos, Vector3(-pos.x, pos.y, -pos.z)]:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 1.0
		mesh.bottom_radius = 1.15
		mesh.height = 0.12
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mats["pad"]
		mi.position = s + Vector3(0, 0.06, 0)
		add_child(mi)
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
