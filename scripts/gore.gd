extends RefCounted
## Blood and gore, for every mode.
##
## hit()    every damaging hit: a spray of blood plus splatter decals where it
##          lands (the wall or floor behind the victim along the shot, and
##          drops under them).
## death()  a KO: a big spray, a ring of splatter on the floor and walls
##          around the body, and gibs: chunks of meat, bones, guts, severed
##          limbs, and a head that pops off (or bursts on a headshot or a
##          blast). Gibs tumble with physics, bleed where they land, then sink.
##
## Blood decals are pooled (MAX_SPLATS, oldest reused) and stay a long time,
## so a big fight really does paint the arena; gibs are capped (MAX_GIBS).
## The "decals" option turns the splatter off; sprays and gibs always show.

const Plush = preload("res://scripts/plush.gd")
const Fx = preload("res://scripts/fx.gd")
const FpArm = preload("res://scripts/fp_arm.gd")
const Voxel = preload("res://scripts/voxel.gd")

const MAX_SPLATS := 150
const MAX_GIBS := 90
const SPLAT_LIFE := 50.0
const GIB_LIFE := 14.0
const BLOOD := Color(0.5, 0.0, 0.02)

static var _splats: Array = []
static var _splat_tex: Array = []
static var _gibs := 0
static var _meshes := {}
static var _mats := {}
static var _spray_mat: StandardMaterial3D


# --------------------------------------------------------------------------
# Hits
# --------------------------------------------------------------------------

## A damaging hit at `pos`, the shot travelling along `dir`. `amount` scales it.
static func hit(world: Node3D, pos: Vector3, dir: Vector3, amount: float) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	var big := clampf(amount / 30.0, 0.4, 2.0)
	spray(world, pos, d, int(18 + 14 * big), 7.0 + 3.0 * big)
	# Exit spray: back towards the shooter a little too.
	spray(world, pos, -d + Vector3(0, 0.4, 0), int(5 + 5 * big), 4.0)
	# Splatter on whatever is behind the victim, and drops below.
	var space := world.get_world_3d().direct_space_state
	var behind := _ray(space, pos, pos + (d + Vector3(randf_range(-0.2, 0.2), randf_range(-0.35, 0.05), randf_range(-0.2, 0.2))).normalized() * 4.0)
	if behind:
		splat(world, behind.position, behind.normal, randf_range(0.6, 1.1) * (0.7 + 0.5 * big))
	var below := _ray(space, pos, pos + Vector3(randf_range(-0.6, 0.6), -3.0, randf_range(-0.6, 0.6)))
	if below:
		splat(world, below.position, below.normal, randf_range(0.35, 0.7) * (0.7 + 0.4 * big))


## A burst of blood droplets that fall under gravity.
static func spray(world: Node3D, pos: Vector3, dir: Vector3, amount: int, speed: float) -> void:
	var p := Fx.burst(world, pos, Color(0.58, 0.01, 0.03), amount, speed, 0.16, 0.9, -14.0, dir.normalized(), 38.0, true, false)
	p.material_override = _droplet_mat()
	p.damping_min = 0.5
	p.damping_max = 1.2
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.16
	if Voxel.on:
		# Voxel style: little cubes of blood instead of round drops.
		p.mesh = _cube()
		p.material_override = _cube_mat()
		p.scale_amount_min = 0.035
		p.scale_amount_max = 0.08
	p.emitting = true


# --------------------------------------------------------------------------
# Deaths
# --------------------------------------------------------------------------

## A KO. `look` = {fur, limb, paw} colours of the body; `how` = "normal",
## "head" (headshot: the head bursts), "blast" (explosion: everything comes
## apart) or "slice" (melee: a limb is lopped off). `scale` sizes the gibs.
static func death(world: Node3D, pos: Vector3, dir: Vector3, look: Dictionary, how := "normal", scale := 1.0) -> void:
	var chest := pos + Vector3(0, 1.0 * scale, 0)
	var head := pos + Vector3(0, 1.45 * scale, 0)
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	var blast: bool = how == "blast"
	spray(world, chest, Vector3.UP, 70 if blast else 45, 9.0 if blast else 7.0)
	spray(world, chest, d + Vector3(0, 0.3, 0), 40, 10.0)
	# Paint the floor and walls all round.
	var space := world.get_world_3d().direct_space_state
	var rays := 18 if blast else 12
	for i in rays:
		var a := TAU * i / rays + randf() * 0.5
		var down := randf_range(-0.9, -0.15) if i % 3 != 0 else randf_range(-0.2, 0.25)
		var to := (Vector3(cos(a), down, sin(a)) + d * 0.6).normalized() * (6.0 if blast else 4.0)
		var h := _ray(space, chest, chest + to)
		if h:
			splat(world, h.position, h.normal, randf_range(1.1, 2.4) * (1.35 if blast else 1.0))
	var pool := _ray(space, chest, chest + Vector3(0, -4, 0))
	if pool:
		splat(world, pool.position, pool.normal, (2.6 if blast else 2.0) * scale)
	# Gibs.
	var meat := 14 if blast else 7
	var bones := 6 if blast else 3
	var guts := 4 if blast else 2
	for i in meat:
		gib(world, chest, "meat", look, d, 6.0 if blast else 4.0, scale)
	for i in bones:
		gib(world, chest, "bone", look, d, 5.0, scale)
	for i in guts:
		gib(world, chest, "guts", look, d, 4.0, scale)
	var limbs := 4 if blast else (1 if how == "slice" else (2 if randf() < 0.5 else 1))
	for i in limbs:
		gib(world, chest + Vector3(randf_range(-0.3, 0.3), 0, 0) * scale, "arm" if i % 2 == 0 else "leg", look, d, 5.0 if blast else 3.5, scale)
	if how == "head" or blast:
		# Head bursts: skull chunks in the fur colour, the eyes, and brains.
		spray(world, head, Vector3.UP, 50, 8.0)
		Fx.flash(world, head, Color(0.6, 0.0, 0.03, 0.85), 0.15 * scale, 0.9 * scale, 0.18)
		for i in 6:
			gib(world, head, "skull", look, d, 5.5, scale)
		for i in 2:
			gib(world, head, "eye", look, d, 5.0, scale)
		for i in 3:
			gib(world, head, "brain", look, d, 4.5, scale)
	else:
		gib(world, head, "head", look, d, 3.0, scale)


# --------------------------------------------------------------------------
# Gibs
# --------------------------------------------------------------------------

## One flying body part. Kinds: meat, bone, guts, arm, leg, head, skull, eye,
## brain.
static func gib(world: Node3D, at: Vector3, kind: String, look: Dictionary, dir: Vector3, speed: float, scale := 1.0) -> void:
	if _gibs >= MAX_GIBS:
		return
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 1.0
	body.linear_damp = 0.1
	body.angular_damp = 0.6
	body.continuous_cd = true
	var parts: Array = _parts(kind, look)
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = part[1]
		mi.transform = part[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 50.0
		body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = {"arm": 0.09, "leg": 0.1, "head": 0.22, "guts": 0.08, "bone": 0.05}.get(kind, 0.045)
	cs.shape = sh
	body.add_child(cs)
	world.add_child(body)
	var s := scale * randf_range(0.85, 1.15)
	body.scale = Vector3.ONE   # physics bodies must not be scaled; parts carry size
	for c in body.get_children():
		if c is MeshInstance3D:
			c.scale *= s
	body.global_position = at + Vector3(randf_range(-0.2, 0.2), randf_range(-0.15, 0.15), randf_range(-0.2, 0.2)) * scale
	body.rotation = Vector3(randf(), randf(), randf()) * TAU
	body.reset_physics_interpolation()
	var throw := (dir * 0.6 + Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1))).normalized()
	body.linear_velocity = throw * speed * randf_range(0.6, 1.2)
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 10.0
	_gibs += 1
	# Bleed where it lands, then sink away.
	var tw := body.create_tween()
	tw.tween_interval(randf_range(0.7, 1.3))
	tw.tween_callback(func():
		if is_instance_valid(body) and body.is_inside_tree():
			var h := _ray(body.get_world_3d().direct_space_state, body.global_position + Vector3(0, 0.3, 0), body.global_position + Vector3(0, -1.5, 0))
			if h:
				splat(world, h.position, h.normal, randf_range(0.35, 0.8)))
	tw.tween_interval(GIB_LIFE * randf_range(0.8, 1.1))
	tw.tween_callback(func(): body.freeze = true)
	tw.tween_property(body, "position:y", body.position.y - 0.6, 1.5)
	tw.tween_callback(func():
		_gibs -= 1
		body.queue_free())


## [mesh, material, transform] pieces for a gib kind (meshes cached).
static func _parts(kind: String, look: Dictionary) -> Array:
	var gore := _mat("gore", Color(0.55, 0.03, 0.05), 0.25)
	var dark := _mat("dark", Color(0.32, 0.0, 0.02), 0.3)
	var bone := _mat("bone", Color(0.93, 0.89, 0.78), 0.6)
	var fur: Color = look.get("fur", Color(0.9, 0.8, 0.7))
	var limb: Color = look.get("limb", fur)
	var paw: Color = look.get("paw", limb)
	var sph := _sphere()
	match kind:
		"meat":
			if Voxel.on:
				# A clump of cubes.
				var clump: Array = []
				var c := 0.045
				for i in randi_range(2, 4):
					var o := Vector3(randi_range(-1, 1), randi_range(-1, 1), randi_range(-1, 1)) * c * 0.5
					clump.append([sph, gore if randf() < 0.6 else dark, Transform3D(Basis.from_scale(Vector3.ONE * c * 0.5), o)])
				return clump
			var k := Vector3(randf_range(0.05, 0.09), randf_range(0.04, 0.07), randf_range(0.05, 0.1))
			return [[sph, gore if randf() < 0.6 else dark, Transform3D(Basis.from_scale(k), Vector3.ZERO)]]
		"bone":
			var l := randf_range(0.18, 0.3)
			return [[_capsule(0.022, l), bone, Transform3D(Basis(), Vector3.ZERO)],
				[sph, bone, Transform3D(Basis.from_scale(Vector3.ONE * 0.038), Vector3(0.022, l * 0.5, 0))],
				[sph, bone, Transform3D(Basis.from_scale(Vector3.ONE * 0.038), Vector3(-0.022, l * 0.5, 0))],
				[sph, bone, Transform3D(Basis.from_scale(Vector3.ONE * 0.038), Vector3(0.022, -l * 0.5, 0))],
				[sph, bone, Transform3D(Basis.from_scale(Vector3.ONE * 0.038), Vector3(-0.022, -l * 0.5, 0))]]
		"guts":
			var out: Array = []
			var pink := _mat("guts", Color(0.86, 0.42, 0.48), 0.2)
			var p := Vector3.ZERO
			var a := 0.0
			for i in 6:
				a += randf_range(0.5, 1.1)
				var step := Vector3(cos(a), sin(a * 0.7) * 0.4, sin(a)) * 0.07
				out.append([sph, pink, Transform3D(Basis.from_scale(Vector3(0.045, 0.04, 0.045)), p)])
				p += step
			return out
		"arm", "leg":
			var r := 0.085 if kind == "arm" else 0.095
			var l2 := 0.42 if kind == "arm" else 0.36
			return [[_capsule(r, l2), FpArm.plush(limb, false), Transform3D(Basis(), Vector3.ZERO)],
				[sph, FpArm.plush(paw, false), Transform3D(Basis.from_scale(Vector3(0.11, 0.1, 0.12)), Vector3(0, -l2 * 0.5, 0))],
				[sph, gore, Transform3D(Basis.from_scale(Vector3(r * 0.95, 0.03, r * 0.95)), Vector3(0, l2 * 0.5, 0))],
				[sph, bone, Transform3D(Basis.from_scale(Vector3(0.03, 0.05, 0.03)), Vector3(0, l2 * 0.5 + 0.03, 0))]]
		"head":
			var eye := _mat("eye", Color(0.05, 0.04, 0.06), 0.15)
			return [[sph, FpArm.plush(fur, false), Transform3D(Basis.from_scale(Vector3(0.3, 0.27, 0.28)), Vector3.ZERO)],
				[sph, eye, Transform3D(Basis.from_scale(Vector3(0.05, 0.065, 0.035)), Vector3(0.12, 0.04, -0.25))],
				[sph, eye, Transform3D(Basis.from_scale(Vector3(0.05, 0.065, 0.035)), Vector3(-0.12, 0.04, -0.25))],
				[sph, gore, Transform3D(Basis.from_scale(Vector3(0.16, 0.05, 0.16)), Vector3(0, -0.25, 0))]]
		"skull":
			var k2 := Vector3(randf_range(0.06, 0.11), randf_range(0.03, 0.05), randf_range(0.06, 0.1))
			return [[sph, FpArm.plush(fur, false), Transform3D(Basis.from_scale(k2), Vector3.ZERO)],
				[sph, gore, Transform3D(Basis.from_scale(k2 * Vector3(0.85, 0.6, 0.85)), Vector3(0, -k2.y * 0.6, 0))]]
		"eye":
			var white := _mat("eyewhite", Color(0.95, 0.93, 0.9), 0.15)
			var eye2 := _mat("eye", Color(0.05, 0.04, 0.06), 0.15)
			return [[sph, white, Transform3D(Basis.from_scale(Vector3.ONE * 0.045), Vector3.ZERO)],
				[sph, eye2, Transform3D(Basis.from_scale(Vector3(0.03, 0.03, 0.02)), Vector3(0, 0, -0.035))]]
		"brain":
			var pink2 := _mat("brain", Color(0.92, 0.6, 0.62), 0.35)
			return [[sph, pink2, Transform3D(Basis.from_scale(Vector3(randf_range(0.05, 0.08), 0.045, randf_range(0.05, 0.08))), Vector3.ZERO)]]
	return [[sph, gore, Transform3D(Basis.from_scale(Vector3.ONE * 0.06), Vector3.ZERO)]]


# --------------------------------------------------------------------------
# Splatter decals
# --------------------------------------------------------------------------

## A blood splat projected onto the level at `pos` (surface normal `normal`).
static func splat(world: Node3D, pos: Vector3, normal: Vector3, size: float) -> void:
	if not Settings.v("decals"):
		return
	var d: Decal = null
	while not _splats.is_empty() and not is_instance_valid(_splats[0]):
		_splats.pop_front()
	if _splats.size() >= MAX_SPLATS:
		d = _splats.pop_front()
		if d.get_parent() != world:
			d.get_parent().remove_child(d)
			world.add_child(d)
	else:
		d = Decal.new()
		d.cull_mask = 1
		d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		d.distance_fade_enabled = true
		d.distance_fade_begin = 40.0
		d.distance_fade_length = 10.0
		d.upper_fade = 0.25
		d.lower_fade = 0.25
		world.add_child(d)
	_splats.append(d)
	if _splat_tex.is_empty():
		for i in 4:
			_splat_tex.append(_make_splat(i))
	if Voxel.on:
		# Voxel style: a splat of 10 cm blocks (three block counts, so the
		# blocks stay about voxel-sized whatever the splat's size).
		var res: int = 0 if size < 0.9 else (1 if size < 1.8 else 2)
		var key := "vox%d" % res
		if not _splat_vox.has(key):
			var set: Array = []
			for i in 4:
				set.append(_voxel_splat(_splat_tex[i], [8, 14, 22][res], i))
			_splat_vox[key] = set
		d.texture_albedo = _splat_vox[key][randi() % 4]
	else:
		d.texture_albedo = _splat_tex[randi() % _splat_tex.size()]
	d.modulate = Color(randf_range(0.8, 1.0), 1.0, 1.0, randf_range(0.85, 1.0))
	d.size = Vector3(size, 0.6, size * randf_range(0.7, 1.2))
	var up := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	d.global_transform = Transform3D(Basis(side, up, side.cross(up)).rotated(up, randf() * TAU), pos)
	d.visible = true
	if d.has_meta("tween"):
		var old: Tween = d.get_meta("tween")
		if old != null and old.is_valid():
			old.kill()
	var tw := d.create_tween()
	tw.tween_interval(SPLAT_LIFE * randf_range(0.8, 1.1))
	tw.tween_property(d, "modulate:a", 0.0, 4.0)
	tw.tween_callback(func(): d.visible = false)
	d.set_meta("tween", tw)


static var _splat_vox := {}


## A smooth splat cut into `blocks` x `blocks` square blocks (each solid or
## empty, its own shade of red), scaled back up without smoothing.
static func _voxel_splat(src: ImageTexture, blocks: int, seed_i: int) -> ImageTexture:
	var img := src.get_image()
	img.clear_mipmaps()
	img.resize(blocks, blocks, Image.INTERPOLATE_BILINEAR)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4000 + seed_i * 31 + blocks
	for y in blocks:
		for x in blocks:
			var c := img.get_pixel(x, y)
			if c.a > 0.42:
				var sh := rng.randf_range(0.72, 1.12)
				img.set_pixel(x, y, Color(minf(1.0, (BLOOD.r + 0.08) * sh), BLOOD.g, BLOOD.b, 0.95))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	img.resize(blocks * 8, blocks * 8, Image.INTERPOLATE_NEAREST)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A procedural splat: a ragged blob, drips and flecks flung outwards.
static func _make_splat(seed_i: int) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var noise := FastNoiseLite.new()
	noise.seed = 77 + seed_i * 13
	noise.frequency = 0.07
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + seed_i
	var blob := rng.randf_range(0.28, 0.42)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var edge := blob + noise.get_noise_2d(x, y) * 0.18
			if r < edge:
				var shade := 0.75 + 0.25 * noise.get_noise_2d(x * 2.0 + 50.0, y * 2.0)
				img.set_pixel(x, y, Color(BLOOD.r * shade + 0.1, BLOOD.g, BLOOD.b, 0.95))
	# Flecks and streaks flung outwards.
	for i in 40:
		var a := rng.randf() * TAU
		var dist := rng.randf_range(blob * 0.9, 0.95)
		var c := Vector2(cos(a), sin(a)) * dist * n * 0.5 + Vector2(n, n) * 0.5
		var rad := rng.randf_range(1.0, 4.5) * (1.0 - dist * 0.6)
		for yy in range(int(c.y - rad - 1), int(c.y + rad + 2)):
			for xx in range(int(c.x - rad - 1), int(c.x + rad + 2)):
				if xx >= 0 and yy >= 0 and xx < n and yy < n and Vector2(xx, yy).distance_to(c) <= rad:
					img.set_pixel(xx, yy, Color(BLOOD.r + 0.08, BLOOD.g, BLOOD.b, 0.92))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return space.intersect_ray(q)


static func _cube(size := 1.0) -> BoxMesh:
	var key := "cube_%.2f" % size
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = Vector3.ONE * size
		_meshes[key] = b
	return _meshes[key]


## Blood cubes (voxel spray): lit, coloured by the particle colour.
static func _cube_mat() -> StandardMaterial3D:
	if not _mats.has("cube_blood"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.35
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		_mats["cube_blood"] = m
	return _mats["cube_blood"]


static func _droplet_mat() -> StandardMaterial3D:
	if _spray_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.set_offset(0, 0.7)
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 32
		tex.height = 32
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
		_spray_mat = m
	return _spray_mat


static func _mat(key: String, col: Color, rough: float) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		_mats[key] = m
	return _mats[key]


## The round piece of a gib: a sphere of radius 1, or in the voxel style a
## cube 2 across (same scale), so gibs are made of voxel blocks.
static func _sphere() -> PrimitiveMesh:
	if Voxel.on:
		return _cube(2.0)
	if not _meshes.has("sphere"):
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 12
		s.rings = 6
		_meshes["sphere"] = s
	return _meshes.sphere


static func _capsule(r: float, l: float) -> PrimitiveMesh:
	var key := "cap_%.3f_%.3f_%s" % [r, l, Voxel.on]
	if Voxel.on:
		if not _meshes.has(key):
			var bx := BoxMesh.new()
			bx.size = Vector3(r * 1.7, maxf(l, r * 2.0), r * 1.7)
			_meshes[key] = bx
		return _meshes[key]
	if not _meshes.has(key):
		var c := CapsuleMesh.new()
		c.radius = r
		c.height = maxf(l, r * 2.0)
		c.radial_segments = 10
		c.rings = 3
		_meshes[key] = c
	return _meshes[key]
