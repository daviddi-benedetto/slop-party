extends Node3D
## A small sunny 3D "showroom" used behind the lobby and the results screen:
## sky, sun, grassy disc, hills, clouds, balloons, and a camera.
## Characters placed with add_character() are animated here.
##
## It lives in the root viewport's World3D, the same one a match uses, so it
## must be freed before a match starts (main.gd / game.gd take care of that).

const Character = preload("res://scripts/character.gd")
const SkyKit = preload("res://scripts/sky.gd")

var camera: Camera3D
var characters: Array = []       # character.gd nodes this stage animates
var _sphere: SphereMesh
var _floaters: Array = []        # [node, base_y, phase]
var _time := 0.0
var _env: Environment
var _sun: DirectionalLight3D


func build(cam_pos: Vector3, look_at_pos: Vector3, fov: float) -> void:
	_sphere = SphereMesh.new()
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 24
	_sphere.rings = 12

	var sky: Sky = SkyKit.make()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.0
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.5
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.22
	env.adjustment_contrast = 1.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.9, 1.0)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	# Cool fill light from the opposite side keeps shaded faces readable.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30.0, -150.0, 0.0)
	fill.light_color = Color(0.7, 0.82, 1.0)
	fill.light_energy = 0.28
	fill.light_specular = 0.0
	add_child(fill)
	_env = env
	_sun = sun
	_on_settings()
	Settings.changed.connect(_on_settings)

	var ground := CylinderMesh.new()
	ground.top_radius = 150.0
	ground.bottom_radius = 150.0
	ground.height = 0.2
	ground.radial_segments = 48
	_prop(ground, _flat(Color(0.52, 0.82, 0.4)), Vector3(0, -0.1, 0))
	var disc := CylinderMesh.new()
	disc.top_radius = 9.0
	disc.bottom_radius = 9.2
	disc.height = 0.12
	disc.radial_segments = 64
	_prop(disc, _flat(Color(1.0, 0.9, 0.66)), Vector3(0, 0.0, -0.5))
	var ring := CylinderMesh.new()
	ring.top_radius = 9.5
	ring.bottom_radius = 9.7
	ring.height = 0.08
	ring.radial_segments = 64
	_prop(ring, _flat(Color(1.0, 0.5, 0.45)), Vector3(0, -0.03, -0.5))

	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 9:
		var a := lerpf(PI * 1.08, PI * 1.92, i / 8.0)
		var d := rng.randf_range(42.0, 70.0)
		var rad := rng.randf_range(14.0, 26.0)
		_prop(_sphere, _flat(Color(0.42, 0.76, 0.4) if i % 2 == 0 else Color(0.5, 0.82, 0.46)),
			Vector3(cos(a) * d, -3.0, sin(a) * d), Vector3(rad, rad * 0.45, rad))
	for i in 7:
		var a2 := lerpf(PI * 1.1, PI * 1.9, i / 6.0)
		var d2 := rng.randf_range(16.0, 30.0)
		_tree(Vector3(cos(a2) * d2, 0, sin(a2) * d2), rng.randf_range(0.9, 1.4), i)
	var cloud := StandardMaterial3D.new()
	cloud.emission_enabled = true
	cloud.emission = Color(0.9, 0.94, 1.0)
	cloud.emission_energy_multiplier = 0.6
	cloud.disable_fog = true
	for i in 7:
		var centre := Vector3(rng.randf_range(-60, 60), rng.randf_range(14, 30), rng.randf_range(-90, -45))
		var big := rng.randf_range(3.0, 6.0)
		for j in 4:
			var rr := big * rng.randf_range(0.6, 1.0)
			var puff := _prop(_sphere, cloud, centre + Vector3((j - 1.5) * big * 0.8, rng.randf_range(-0.2, 0.4) * big, 0), Vector3(rr, rr * 0.7, rr))
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cols := [Color(1.0, 0.36, 0.4), Color(1.0, 0.82, 0.25), Color(0.3, 0.66, 1.0), Color(0.45, 0.88, 0.5), Color(0.78, 0.5, 1.0)]
	for i in 10:
		var side := -1.0 if i % 2 == 0 else 1.0
		var holder := Node3D.new()
		holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		holder.position = Vector3(side * rng.randf_range(7.5, 13.0), rng.randf_range(2.5, 6.5), rng.randf_range(-7.0, -1.0))
		add_child(holder)
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[i % cols.size()]
		m.roughness = 0.2
		m.rim_enabled = true
		_prop(_sphere, m, Vector3.ZERO, Vector3(0.45, 0.54, 0.45), holder)
		var string := CylinderMesh.new()
		string.top_radius = 0.012
		string.bottom_radius = 0.012
		string.height = 1.6
		_prop(string, _flat(Color(1, 1, 1)), Vector3(0, -1.3, 0), Vector3.ONE, holder)
		_floaters.append([holder, holder.position.y, rng.randf() * TAU])

	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = fov
	add_child(camera)
	camera.look_at_from_position(cam_pos, look_at_pos)
	camera.current = true


func _on_settings() -> void:
	Settings.apply_environment(_env, _sun)


func _flat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	return m


func _prop(mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	(parent if parent != null else self).add_child(mi)
	return mi


func _tree(pos: Vector3, scl: float, i: int) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.28 * scl
	trunk.bottom_radius = 0.4 * scl
	trunk.height = 3.6 * scl
	_prop(trunk, _flat(Color(0.62, 0.42, 0.28)), pos + Vector3(0, 1.8 * scl, 0))
	var leaf := _flat(Color(0.98, 0.6, 0.72) if i % 4 == 1 else (Color(0.3, 0.72, 0.36) if i % 2 == 0 else Color(0.45, 0.82, 0.38)))
	_prop(_sphere, leaf, pos + Vector3(0, 4.6 * scl, 0), Vector3(2.2, 2.0, 2.2) * scl)
	_prop(_sphere, leaf, pos + Vector3(0.9 * scl, 3.9 * scl, 0.5 * scl), Vector3(1.5, 1.3, 1.5) * scl)
	_prop(_sphere, leaf, pos + Vector3(-0.8 * scl, 4.1 * scl, -0.6 * scl), Vector3(1.6, 1.4, 1.6) * scl)


## A round pedestal; returns the Y of its top surface.
func add_podium(pos: Vector3, height: float, color: Color) -> float:
	var body := CylinderMesh.new()
	body.top_radius = 0.92
	body.bottom_radius = 1.0
	body.height = height
	body.radial_segments = 32
	_prop(body, _flat(Color(1.0, 0.97, 0.9)), pos + Vector3(0, height * 0.5, 0))
	var cap := CylinderMesh.new()
	cap.top_radius = 0.98
	cap.bottom_radius = 0.98
	cap.height = 0.12
	cap.radial_segments = 32
	_prop(cap, _flat(color), pos + Vector3(0, height, 0))
	return pos.y + height + 0.06


## Adds a character facing the camera (+Z).
func add_character(kind: int, color: Color, pos: Vector3):
	var c = Character.new()
	add_child(c)
	c.build(kind, color, 1, true)
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
	for f in _floaters:
		f[0].position.y = f[1] + sin(_time * 1.2 + f[2]) * 0.25
		f[0].rotation.z = sin(_time * 0.8 + f[2]) * 0.1


func _physics_process(delta: float) -> void:
	for c in characters:
		c.animate(delta, 0.0, true, 0.0, 0.0)
