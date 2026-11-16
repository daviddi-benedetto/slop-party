extends Node3D
## A small 3D "showroom" used behind the lobby and the results screen: night
## sky, a dark glossy floor with neon rings, a glowing skyline and a camera.
## Characters placed with add_character() are animated here.
##
## It lives in the root viewport's World3D, the same one a match uses, so it
## must be freed before a match starts (main.gd / game.gd take care of that).

const Character = preload("res://scripts/character.gd")
const SkyKit = preload("res://scripts/sky.gd")

const ORANGE := Color(1.0, 0.42, 0.16)
const CYAN := Color(0.15, 0.75, 1.0)

var camera: Camera3D
var characters: Array = []       # character.gd nodes this stage animates
var _time := 0.0
var _env: Environment
var _sun: DirectionalLight3D
var _rings: Array = []


func build(cam_pos: Vector3, look_at_pos: Vector3, fov: float) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = SkyKit.make({"top": Color(0.01, 0.015, 0.05), "horizon": Color(0.12, 0.1, 0.28), "ground": Color(0.02, 0.02, 0.05),
		"sun": Color(0.75, 0.82, 1.0), "cloud_color": Color(0.14, 0.13, 0.28), "clouds": 0.6, "stars": 1.0, "aurora": 0.35})
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 2.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.3
	env.tonemap_white = 4.0
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.14)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	sun.light_color = Color(0.7, 0.78, 1.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	# Warm key light from the front so faces read well against the dark.
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.82)
	key.light_energy = 3.2
	key.spot_range = 26.0
	key.spot_angle = 50.0
	add_child(key)
	key.look_at_from_position(Vector3(0, 7.5, 9.0), Vector3(0, 1.2, 0))
	_env = env
	_sun = sun
	_on_settings()
	Settings.changed.connect(_on_settings)

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.05, 0.06, 0.11)
	floor_mat.roughness = 0.3
	floor_mat.metallic = 0.3
	var ground := CylinderMesh.new()
	ground.top_radius = 160.0
	ground.bottom_radius = 160.0
	ground.height = 0.2
	ground.radial_segments = 48
	_prop(ground, floor_mat, Vector3(0, -0.1, 0))
	for i in 4:
		var torus := TorusMesh.new()
		var r := 9.0 + i * 5.5
		torus.inner_radius = r
		torus.outer_radius = r + 0.09
		torus.rings = 96
		torus.ring_segments = 6
		var ring := _prop(torus, _neon(ORANGE if i % 2 == 0 else CYAN, 1.8), Vector3(0, 0.03, -0.5))
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rings.append(ring)

	# A glowing skyline behind the podiums.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var box := BoxMesh.new()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.035, 0.07)
	dark.roughness = 0.5
	for i in 22:
		var a := lerpf(PI * 1.05, PI * 1.95, i / 21.0)
		var d := rng.randf_range(34.0, 80.0)
		var w := rng.randf_range(5.0, 11.0)
		var h := rng.randf_range(8.0, 36.0)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		_prop(box, dark, p + Vector3(0, h * 0.5, 0), Vector3(w, h, w)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var neon := _neon(ORANGE if i % 2 == 0 else CYAN, 1.8)
		for b in 3:
			_prop(box, neon, p + Vector3(0, h * (0.3 + 0.3 * b), 0), Vector3(w + 0.12, 0.2, w + 0.12)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx in [-1.0, 1.0]:
		for j in 3:
			var l := OmniLight3D.new()
			l.position = Vector3(sx * (6.0 + j * 4.0), 2.5, -4.0 - j * 2.0)
			l.light_color = ORANGE if (j + int(sx)) % 2 == 0 else CYAN
			l.light_energy = 2.5
			l.omni_range = 10.0
			add_child(l)

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


## A round pedestal with a glowing cap; returns the Y of its top surface.
func add_podium(pos: Vector3, height: float, color: Color) -> float:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.08, 0.09, 0.15)
	body_mat.roughness = 0.35
	body_mat.metallic = 0.3
	var body := CylinderMesh.new()
	body.top_radius = 0.92
	body.bottom_radius = 1.0
	body.height = height
	body.radial_segments = 32
	_prop(body, body_mat, pos + Vector3(0, height * 0.5, 0))
	var cap := CylinderMesh.new()
	cap.top_radius = 0.98
	cap.bottom_radius = 0.98
	cap.height = 0.1
	cap.radial_segments = 32
	_prop(cap, _neon(color, 1.1), pos + Vector3(0, height, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return pos.y + height + 0.05


## Adds a character facing the camera (+Z). `look` = {kind, color, hat, face}.
func add_character(look: Dictionary, pos: Vector3):
	var c = Character.new()
	add_child(c)
	c.build(look.get("kind", 0), look.color, 1, true, look.get("hat", 0), look.get("face", 0))
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
