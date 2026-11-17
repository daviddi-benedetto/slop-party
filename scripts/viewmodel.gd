extends Node3D
## A gun model. Used two ways:
##  - first person: a child of one player's Camera3D, drawn only on that
##    player's private viewmodel layer and animated per rendered frame by
##    game.gd calling update(). It rebuilds itself when the weapon changes.
##  - as a prop: pickup.gd builds one with with_paw = false on layer 1.
##
## Each weapon style (weapons.gd "style") is a small arrangement of primitive
## parts in _build_gun(). Local space: the barrel points down -Z.
##
## First-person motion (all driven by smoothed values on player.gd):
##   walk bob (figure of eight), look sway (the gun lags the view), strafe
##   roll, jump/fall inertia, landing dip, recoil kick, reload dip, a swing-up
##   when a new weapon arrives, a guard pose while blocking, idle breathing,
##   and the slide to the centre of the screen when aiming down sights.
## The "bob" setting scales the walking part.

const Weapons = preload("res://scripts/weapons.gd")
const Models = preload("res://scripts/models.gd")

## Styles drawn with an imported model: [model path, forward axis of the
## model ("-x" or "+z"), overall length, extra height offset]. The rest
## (Spinner, Bubbler, Pinball, Flamer) keep their hand-built sci-fi models.
const GLB := {
	"_": ["toon/Weapon/AK", "-x", 0.86, 0.0],
	"burst": ["zombie/Weapon/Rifle", "+z", 0.92, 0.0],
	"zapper": ["toon/Weapon/SMG", "-x", 0.62, 0.0],
	"scatter": ["toon/Weapon/Shotgun", "-x", 0.98, 0.0],
	"magnum": ["toon/Weapon/Revolver", "-x", 0.5, 0.0],
	"rail": ["toon/Weapon/Sniper", "-x", 1.2, 0.0],
	"boomer": ["toon/Weapon/Rocket_Launcher", "-x", 0.95, 0.0],
	"lobber": ["toon/Weapon/Grenade_Launcher", "-x", 0.78, 0.0],
	# Toy blasters (Kenney Blaster Kit) for the sci-fi and newer weapons.
	"bubbler": ["blaster/Blaster_N", "+z", 0.62, 0.0],
	"pinball": ["blaster/Blaster_R", "+z", 0.66, 0.0],
	"flamer": ["blaster/Blaster_P", "+z", 0.84, 0.0],
	"twins": ["toon/Weapon/Pistol", "-x", 0.42, 0.0],
	"tesla": ["blaster/Blaster_F", "+z", 1.0, 0.0],
	"cluster": ["blaster/Blaster_L", "+z", 0.62, 0.0],
	"vortex": ["blaster/Blaster_O", "+z", 0.58, 0.0],
	"ripper": ["blaster/Blaster_G", "+z", 0.78, 0.0],
	"sticky": ["blaster/Blaster_D", "+z", 0.86, 0.0],
	"longshot": ["toon/Weapon/Sniper_2", "-x", 1.15, 0.0],
	"frost": ["blaster/Blaster_Q", "+z", 0.7, 0.0],
}

const HIP := Vector3(0.27, -0.25, -0.58)
const ADS := Vector3(0.0, -0.155, -0.5)

const LENS_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D view : source_color, filter_linear;
void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c);
	if (r > 0.5) { discard; }
	vec3 col = texture(view, UV).rgb;
	float cross = (abs(c.x) < 0.0035 || abs(c.y) < 0.0035) ? step(0.07, r) : 0.0;
	col = mix(col, vec3(0.0), cross * 0.85);
	col = mix(col, vec3(1.0, 0.15, 0.1), smoothstep(0.016, 0.01, r));
	col *= smoothstep(0.5, 0.36, r);
	ALBEDO = col;
}
"""

var weapon := -1
var scope_texture: Texture2D          # set by game.gd: the live view of the scope camera
var _color := Color.WHITE
var _layer := 1
var _with_paw := true
var _flash: MeshInstance3D
var _spin: Node3D                # rotating barrel cluster (Spinner)
var _muzzle_z := -0.3
var _sight_y := 0.07             # height of the sight line above the barrel axis
var _last_yaw := 0.0
var _last_pitch := 0.0
var _sway := Vector2.ZERO
var _swap := 1.0
var _t := 0.0
var _spin_speed := 0.0
var _style := ""
var _attach: Node3D
var _lens_mat: ShaderMaterial
var _attach_key := ""
var _target: Node3D              # where _part() puts new pieces (self or a pivot)
var _pump: Node3D                # sliding fore-end (Scatter)
var _drum: Node3D                # revolving cylinder (Magnum, Lobber)
var _warhead: Node3D             # loaded rocket (Boomer)
var _drum_angle := 0.0
var _last_st := 0.0

var _shell: StandardMaterial3D
var _accent: StandardMaterial3D
var _dark: StandardMaterial3D
var _glow: StandardMaterial3D
var _metal: StandardMaterial3D
var _wood: StandardMaterial3D
var _brass: StandardMaterial3D
var _shellred: StandardMaterial3D
var _sphere: SphereMesh


func build(color: Color, layer_bit: int, weapon_id := 0, with_paw := true) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_color = color
	_layer = layer_bit
	_with_paw = with_paw
	_shell = _mat(Color(0.82, 0.83, 0.88), 0.35)
	_shell.metallic = 0.6
	_accent = _mat(color, 0.4)
	_accent.metallic = 0.25
	_dark = _mat(Color(0.075, 0.075, 0.09), 0.55)
	_dark.metallic = 0.35
	_metal = _mat(Color(0.25, 0.26, 0.29), 0.3)
	_metal.metallic = 0.85
	_wood = _mat(Color(0.42, 0.24, 0.12), 0.6)
	_brass = _mat(Color(0.85, 0.65, 0.3), 0.3)
	_brass.metallic = 0.9
	_shellred = _mat(Color(0.75, 0.12, 0.1), 0.5)
	_target = self
	_glow = _mat(color.lerp(Color.WHITE, 0.3), 0.2)
	_glow.emission_enabled = true
	_glow.emission = color.lerp(Color.WHITE, 0.25)
	_glow.emission_energy_multiplier = 1.8
	_sphere = SphereMesh.new()
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 20
	_sphere.rings = 10
	set_weapon(weapon_id)
	position = HIP


func set_weapon(id: int) -> void:
	if id == weapon:
		return
	weapon = id
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_spin = null
	_pump = null
	_drum = null
	_warhead = null
	_drum_angle = 0.0
	_target = self
	_sight_y = 0.07
	_style = Weapons.LIST[id].style
	_build_gun(_style)
	_attach = null
	_attach_key = ""
	if _with_paw:
		var plush := _mat(_color.lerp(Color(1, 0.97, 0.9), 0.25), 0.95)
		plush.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		plush.rim_enabled = true
		plush.rim = 0.5
		_ball(plush, Vector3(0.005, -0.11, 0.11), Vector3(0.075, 0.07, 0.08))
		_ball(plush, Vector3(0.04, -0.22, 0.3), Vector3(0.065, 0.065, 0.22))
	_merge()
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.albedo_color = Color(_color.lerp(Color(1.0, 0.9, 0.6), 0.6) * 2.0, 0.9)
	_flash = _ball(fmat, Vector3(0, 0, _muzzle_z), Vector3.ONE * 0.05)
	_flash.visible = false
	_swap = 0.0


## Distance of the muzzle along -Z in model units (character.gd uses it).
func muzzle_z() -> float:
	return _muzzle_z


## World-space bore exit for shots and muzzle effects.
func muzzle_position() -> Vector3:
	return global_transform * Vector3(0.0, 0.0, _muzzle_z)


## Weapon models. Bore axis = the Z axis (y = 0), muzzle towards -Z, the
## pistol grip at z = 0.1 where the paw holds it. Real-world layout: receiver,
## barrel, handguard, magazine, stock, sights; the player's colour goes on
## the receiver / furniture, glowing strips mark the sci-fi parts.
## _sight_y = height of the iron-sight line (aiming lines it up with the eye).
func _build_gun(style: String) -> void:
	var key := style if GLB.has(style) else ("_" if style != "spinner" else "")
	if key != "":
		_build_glb(style, GLB[key])
		return
	match style:
		"burst":
			# Bullpup assault rifle with a carry handle.
			_sight_y = 0.112
			_box(_accent, Vector3(0.058, 0.085, 0.4), Vector3(0, -0.005, 0.08))
			_box(_dark, Vector3(0.062, 0.03, 0.4), Vector3(0, -0.058, 0.08))
			_box(_dark, Vector3(0.064, 0.11, 0.025), Vector3(0, -0.02, 0.29))
			_box(_dark, Vector3(0.05, 0.05, 0.17), Vector3(0, 0.0, -0.2))
			_box(_glow, Vector3(0.052, 0.006, 0.12), Vector3(0, 0.012, -0.2))
			_tube(_metal, 0.012, 0.18, Vector3(0, 0, -0.37))
			_tube(_dark, 0.018, 0.06, Vector3(0, 0, -0.48))
			_box(_dark, Vector3(0.022, 0.016, 0.3), Vector3(0, 0.09, 0.02))
			for z in [-0.11, 0.15]:
				_box(_dark, Vector3(0.02, 0.05, 0.03), Vector3(0, 0.06, z))
			_irons(0.14, -0.1, 0.098, 0.098)
			_mag(0.2, 0.13, 0.12)
			_grip(_dark, 0.1)
			_tilt(_box(_dark, Vector3(0.028, 0.08, 0.034), Vector3(0, -0.065, -0.2)), -0.1)
			for z in [0.0, 0.035, 0.07]:
				_box(_glow, Vector3(0.061, 0.014, 0.018), Vector3(0, 0.018, z))
			_box(_metal, Vector3(0.012, 0.012, 0.04), Vector3(0.034, 0.02, 0.17))
			_muzzle_z = -0.52
		"zapper":
			# Compact energy SMG: boxy receiver, coil barrel, long magazine.
			_sight_y = 0.068
			_box(_accent, Vector3(0.05, 0.07, 0.26), Vector3(0, 0.0, 0.0))
			_box(_dark, Vector3(0.046, 0.035, 0.16), Vector3(0, -0.05, 0.04))
			_box(_dark, Vector3(0.048, 0.05, 0.12), Vector3(0, 0.0, -0.18))
			_tube(_metal, 0.011, 0.14, Vector3(0, 0, -0.29))
			for z in [-0.255, -0.285, -0.315]:
				_tube(_glow, 0.02, 0.012, Vector3(0, 0, z))
			_tube(_dark, 0.017, 0.03, Vector3(0, 0, -0.365))
			_rail(-0.22, 0.1, 0.035)
			_irons(0.09, -0.2, 0.04, 0.025)
			_tilt(_box(_dark, Vector3(0.028, 0.17, 0.042), Vector3(0, -0.12, -0.07)), 0.06)
			_box(_glow, Vector3(0.03, 0.08, 0.008), Vector3(0, -0.1, -0.047))
			_grip(_dark, 0.1)
			_tilt(_box(_dark, Vector3(0.026, 0.07, 0.03), Vector3(0, -0.06, -0.19)), -0.1)
			for sx in [-0.02, 0.02]:
				_box(_metal, Vector3(0.008, 0.008, 0.18), Vector3(sx, -0.005, 0.2))
			_box(_dark, Vector3(0.05, 0.065, 0.015), Vector3(0, -0.015, 0.29))
			_muzzle_z = -0.39
		"scatter":
			# Pump-action shotgun: wooden furniture, sliding fore-end.
			_sight_y = 0.044
			_box(_accent, Vector3(0.05, 0.075, 0.2), Vector3(0, -0.005, 0.0))
			_tube(_metal, 0.018, 0.46, Vector3(0, 0.012, -0.33))
			_box(_dark, Vector3(0.012, 0.006, 0.44), Vector3(0, 0.033, -0.33))
			_ball(_brass, Vector3(0, 0.04, -0.545), Vector3.ONE * 0.006)
			_tube(_metal, 0.014, 0.38, Vector3(0, -0.025, -0.28))
			_tube(_dark, 0.017, 0.02, Vector3(0, -0.025, -0.47))
			_box(_dark, Vector3(0.03, 0.01, 0.03), Vector3(0, 0.036, 0.06))
			_pump = _node(Vector3(0, -0.022, -0.2))
			_target = _pump
			_box(_wood, Vector3(0.05, 0.046, 0.14), Vector3.ZERO)
			for gy in [-0.012, 0.0, 0.012]:
				_box(_dark, Vector3(0.052, 0.004, 0.12), Vector3(0, gy, 0))
			_target = self
			_grip(_wood, 0.1)
			_tilt(_box(_wood, Vector3(0.042, 0.065, 0.2), Vector3(0, -0.04, 0.21)), -0.12)
			_tilt(_box(_dark, Vector3(0.046, 0.09, 0.02), Vector3(0, -0.055, 0.31)), -0.12)
			for i in 4:
				_box(_shellred, Vector3(0.012, 0.04, 0.014), Vector3(0.031, -0.004, -0.06 + i * 0.022))
				_box(_brass, Vector3(0.013, 0.012, 0.015), Vector3(0.031, -0.028, -0.06 + i * 0.022))
			_muzzle_z = -0.57
		"magnum":
			# Heavy revolver: full-lug barrel, fluted cylinder, wooden grip.
			_sight_y = 0.046
			_box(_metal, Vector3(0.036, 0.07, 0.12), Vector3(0, -0.012, 0.03))
			_box(_metal, Vector3(0.03, 0.012, 0.13), Vector3(0, 0.03, 0.01))
			_tube(_metal, 0.015, 0.2, Vector3(0, 0.0, -0.14))
			_box(_metal, Vector3(0.022, 0.02, 0.2), Vector3(0, 0.016, -0.14))
			_box(_metal, Vector3(0.026, 0.03, 0.18), Vector3(0, -0.02, -0.15))
			_box(_accent, Vector3(0.006, 0.022, 0.022), Vector3(0, 0.035, -0.225))
			for sx in [-0.008, 0.008]:
				_box(_dark, Vector3(0.005, 0.014, 0.01), Vector3(sx, 0.042, 0.07))
			_tilt(_box(_dark, Vector3(0.012, 0.03, 0.02), Vector3(0, 0.035, 0.09)), -0.6)
			_drum = _node(Vector3(0, -0.024, -0.01))
			_target = _drum
			var cyl := _tube(_shell, 0.042, 0.075, Vector3.ZERO)
			(cyl.mesh as CylinderMesh).radial_segments = 12
			for i in 6:
				var a := TAU * i / 6.0
				_tube(_dark, 0.009, 0.078, Vector3(cos(a) * 0.024, sin(a) * 0.024, 0))
				_tube(_dark, 0.006, 0.05, Vector3(cos(a + PI / 6) * 0.041, sin(a + PI / 6) * 0.041, 0))
			_target = self
			_tilt(_box(_wood, Vector3(0.034, 0.12, 0.052), Vector3(0, -0.08, 0.1)), -0.45)
			_tilt(_box(_metal, Vector3(0.036, 0.012, 0.054), Vector3(0, -0.135, 0.125)), -0.45)
			_guard(0.1, -0.045)
			_muzzle_z = -0.25
		"rail":
			# Bolt-action rail sniper: long barrel with energy coils, big scope.
			_sight_y = 0.077
			_box(_metal, Vector3(0.044, 0.05, 0.24), Vector3(0, 0.0, 0.02))
			_box(_accent, Vector3(0.05, 0.05, 0.26), Vector3(0, -0.02, -0.25))
			_box(_accent, Vector3(0.044, 0.075, 0.18), Vector3(0, -0.028, 0.25))
			_box(_dark, Vector3(0.036, 0.02, 0.11), Vector3(0, 0.018, 0.25))
			_box(_dark, Vector3(0.048, 0.1, 0.02), Vector3(0, -0.035, 0.345))
			_tube(_metal, 0.013, 0.42, Vector3(0, 0, -0.48))
			_tube(_dark, 0.021, 0.07, Vector3(0, 0, -0.72))
			for z in [-0.42, -0.5, -0.58]:
				_tube(_glow, 0.026, 0.018, Vector3(0, 0, z))
			_box(_metal, Vector3(0.05, 0.008, 0.008), Vector3(0.035, 0.0, 0.09))
			_ball(_dark, Vector3(0.062, 0.0, 0.09), Vector3.ONE * 0.012)
			_box(_dark, Vector3(0.03, 0.06, 0.07), Vector3(0, -0.07, -0.03))
			_tube(_dark, 0.026, 0.24, Vector3(0, 0.077, 0.0))
			_cone(_dark, 0.026, 0.037, 0.06, Vector3(0, 0.077, -0.15))
			_tube(_glow, 0.031, 0.003, Vector3(0, 0.077, -0.18))
			_tube(_dark, 0.03, 0.05, Vector3(0, 0.077, 0.13))
			_box(_dark, Vector3(0.02, 0.022, 0.022), Vector3(0, 0.108, 0.0))
			_box(_dark, Vector3(0.022, 0.02, 0.022), Vector3(0.03, 0.077, 0.0))
			for z in [-0.06, 0.07]:
				_box(_dark, Vector3(0.018, 0.035, 0.02), Vector3(0, 0.045, z))
			for sx in [-0.017, 0.017]:
				_box(_dark, Vector3(0.008, 0.008, 0.18), Vector3(sx, -0.052, -0.3))
			_grip(_accent, 0.1)
			_muzzle_z = -0.76
		"boomer":
			# Shoulder-fired rocket launcher with a visible warhead.
			_sight_y = 0.135
			_tube(_accent, 0.07, 0.62, Vector3(0, 0.03, -0.06))
			_cone(_dark, 0.072, 0.082, 0.05, Vector3(0, 0.03, -0.39))
			_cone(_dark, 0.092, 0.072, 0.07, Vector3(0, 0.03, 0.27))
			for z in [-0.2, 0.1]:
				_tube(_dark, 0.074, 0.03, Vector3(0, 0.03, z))
			_box(_glow, Vector3(0.012, 0.008, 0.3), Vector3(0.071, 0.03, -0.06))
			_warhead = _node(Vector3(0, 0.03, -0.42))
			_target = _warhead
			_cone(_metal, 0.05, 0.008, 0.11, Vector3(0, 0, -0.03))
			_tube(_dark, 0.05, 0.03, Vector3(0, 0, 0.035))
			_target = self
			_irons(0.12, -0.26, 0.1, 0.1)
			_grip(_dark, 0.1, -0.09)
			_tilt(_box(_dark, Vector3(0.03, 0.09, 0.035), Vector3(0, -0.075, -0.18)), -0.1)
			_box(_dark, Vector3(0.03, 0.06, 0.12), Vector3(0, -0.06, 0.2))
			_box(_dark, Vector3(0.05, 0.05, 0.08), Vector3(-0.07, 0.07, -0.02))
			_tube(_glow, 0.018, 0.004, Vector3(-0.07, 0.07, -0.062))
			_muzzle_z = -0.45
		"lobber":
			# Revolving grenade launcher: six-shot drum, short fat barrel.
			_sight_y = 0.1
			_box(_metal, Vector3(0.03, 0.016, 0.24), Vector3(0, 0.04, -0.06))
			_box(_metal, Vector3(0.05, 0.15, 0.02), Vector3(0, -0.04, -0.115))
			_box(_metal, Vector3(0.05, 0.15, 0.02), Vector3(0, -0.04, 0.035))
			_tube(_dark, 0.03, 0.16, Vector3(0, 0, -0.2))
			_tube(_metal, 0.035, 0.02, Vector3(0, 0, -0.275))
			_drum = _node(Vector3(0, -0.047, -0.04))
			_target = _drum
			var d := _tube(_accent, 0.075, 0.13, Vector3.ZERO)
			(d.mesh as CylinderMesh).radial_segments = 12
			for i in 6:
				var a := TAU * i / 6.0
				_tube(_dark, 0.022, 0.134, Vector3(cos(a) * 0.047, sin(a) * 0.047, 0))
			_target = self
			_box(_dark, Vector3(0.04, 0.04, 0.1), Vector3(0, -0.03, 0.09))
			_grip(_dark, 0.1)
			_tilt(_box(_dark, Vector3(0.028, 0.08, 0.035), Vector3(0, -0.07, -0.21)), -0.1)
			for sx in [-0.02, 0.02]:
				_box(_metal, Vector3(0.01, 0.01, 0.2), Vector3(sx, -0.01, 0.22))
			_box(_dark, Vector3(0.05, 0.08, 0.02), Vector3(0, -0.03, 0.32))
			_box(_dark, Vector3(0.03, 0.04, 0.02), Vector3(0, 0.065, -0.12))
			_irons(0.03, -0.12, 0.048, 0.085)
			_muzzle_z = -0.3
		"bubbler":
			# Sci-fi foam gun: side tank feeding a bell muzzle.
			_sight_y = 0.07
			_box(_accent, Vector3(0.055, 0.07, 0.28), Vector3(0, 0, 0.0))
			_box(_dark, Vector3(0.05, 0.03, 0.16), Vector3(0, -0.048, 0.04))
			var tank := _mat(_color.lerp(Color.WHITE, 0.4), 0.1)
			tank.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tank.albedo_color.a = 0.55
			tank.emission_enabled = true
			tank.emission = _color.lerp(Color.WHITE, 0.3)
			tank.emission_energy_multiplier = 1.6
			_tube(tank, 0.03, 0.15, Vector3(0.058, 0.008, -0.03))
			for z in [-0.11, 0.05]:
				_tube(_metal, 0.033, 0.016, Vector3(0.058, 0.008, z))
			_tube(_dark, 0.006, 0.1, Vector3(0.04, 0.0, -0.16))
			_tube(_metal, 0.016, 0.12, Vector3(0, 0, -0.2))
			_cone(_shell, 0.02, 0.06, 0.08, Vector3(0, 0, -0.29))
			_tube(_dark, 0.052, 0.004, Vector3(0, 0, -0.328))
			_rail(-0.12, 0.1, 0.035)
			_irons(0.1, -0.12, 0.04, 0.035)
			_grip(_dark, 0.1)
			_box(_dark, Vector3(0.04, 0.06, 0.12), Vector3(0, -0.015, 0.2))
			_muzzle_z = -0.34
		"spinner":
			# Minigun: motor housing, six spinning barrels, ammo box, carry handle.
			_sight_y = 0.13
			_box(_accent, Vector3(0.1, 0.1, 0.16), Vector3(0, 0, 0.1))
			_tube(_dark, 0.06, 0.06, Vector3(0, 0, -0.01))
			_box(_dark, Vector3(0.02, 0.015, 0.17), Vector3(0, 0.1, 0.06))
			for z in [0.0, 0.13]:
				_box(_dark, Vector3(0.02, 0.05, 0.02), Vector3(0, 0.07, z))
			_irons(0.12, -0.0, 0.108, 0.108)
			_box(_dark, Vector3(0.06, 0.09, 0.1), Vector3(-0.09, -0.04, 0.08))
			_box(_brass, Vector3(0.04, 0.018, 0.08), Vector3(-0.05, 0.0, 0.06))
			_grip(_dark, 0.12, -0.11)
			_box(_dark, Vector3(0.04, 0.03, 0.08), Vector3(0, -0.06, 0.12))
			_spin = _node(Vector3.ZERO)
			_target = _spin
			for i in 6:
				var a := TAU * i / 6.0
				_tube(_metal, 0.013, 0.48, Vector3(cos(a) * 0.04, sin(a) * 0.04, -0.25))
			_tube(_dark, 0.062, 0.025, Vector3(0, 0, -0.2))
			_tube(_dark, 0.062, 0.025, Vector3(0, 0, -0.38))
			_tube(_glow, 0.058, 0.01, Vector3(0, 0, -0.48))
			_target = self
			_muzzle_z = -0.5
		"pinball":
			# Bouncing-ball launcher: wide shroud, bumper muzzle, side plunger.
			_sight_y = 0.07
			_box(_accent, Vector3(0.06, 0.08, 0.24), Vector3(0, 0, 0.02))
			_box(_dark, Vector3(0.072, 0.045, 0.18), Vector3(0, 0.0, -0.18))
			_box(_glow, Vector3(0.074, 0.008, 0.14), Vector3(0, 0, -0.18))
			_tube(_shell, 0.042, 0.03, Vector3(0, 0, -0.29))
			_tube(_glow, 0.032, 0.034, Vector3(0, 0, -0.29))
			_tube(_dark, 0.024, 0.036, Vector3(0, 0, -0.29))
			_tube(_metal, 0.006, 0.09, Vector3(0.036, -0.01, 0.15))
			_ball(_accent, Vector3(0.036, -0.01, 0.2), Vector3.ONE * 0.016)
			_box(_dark, Vector3(0.04, 0.08, 0.06), Vector3(0, -0.08, -0.06))
			_rail(-0.1, 0.12, 0.045)
			_irons(0.11, -0.09, 0.05, 0.05)
			_grip(_dark, 0.1)
			_box(_dark, Vector3(0.044, 0.065, 0.14), Vector3(0, -0.015, 0.2))
			_muzzle_z = -0.32
		"flamer":
			# Flamethrower: fuel tank underneath, shrouded barrel, pilot light.
			_sight_y = 0.065
			_box(_dark, Vector3(0.05, 0.06, 0.22), Vector3(0, 0.0, 0.0))
			_tube(_accent, 0.05, 0.24, Vector3(0, -0.078, -0.04))
			_cone(_metal, 0.035, 0.05, 0.03, Vector3(0, -0.078, -0.175))
			for z in [-0.1, 0.04]:
				_tube(_dark, 0.052, 0.012, Vector3(0, -0.078, z))
			_tube(_metal, 0.02, 0.24, Vector3(0, 0, -0.22))
			_tube(_dark, 0.03, 0.15, Vector3(0, 0, -0.2))
			for z in [-0.25, -0.2, -0.15]:
				_box(_metal, Vector3(0.05, 0.01, 0.02), Vector3(0, 0.0, z))
			_cone(_shell, 0.024, 0.042, 0.06, Vector3(0, 0, -0.36))
			var pilot := _mat(Color(1.0, 0.5, 0.1), 0.2)
			pilot.emission_enabled = true
			pilot.emission = Color(1.0, 0.45, 0.1)
			pilot.emission_energy_multiplier = 4.0
			_tube(_metal, 0.006, 0.1, Vector3(0, -0.035, -0.32))
			_ball(pilot, Vector3(0, -0.035, -0.375), Vector3.ONE * 0.012)
			_tube(_dark, 0.01, 0.2, Vector3(0.032, -0.04, 0.06))
			_irons(0.08, -0.12, 0.03, 0.03)
			_grip(_dark, 0.1)
			_tilt(_box(_dark, Vector3(0.03, 0.08, 0.035), Vector3(0, -0.06, -0.26)), -0.1)
			_box(_dark, Vector3(0.04, 0.06, 0.12), Vector3(0, -0.01, 0.2))
			_muzzle_z = -0.4
		_:
			# Blaster: modern carbine (upper/lower receiver, rail, stock).
			_sight_y = 0.075
			_box(_accent, Vector3(0.05, 0.05, 0.26), Vector3(0, 0.012, 0.0))
			_box(_dark, Vector3(0.046, 0.04, 0.17), Vector3(0, -0.035, 0.03))
			_box(_metal, Vector3(0.052, 0.016, 0.05), Vector3(0, 0.015, -0.02))
			_box(_dark, Vector3(0.058, 0.058, 0.2), Vector3(0, 0.005, -0.23))
			_box(_glow, Vector3(0.06, 0.008, 0.13), Vector3(0, 0.0, -0.23))
			_tube(_metal, 0.012, 0.12, Vector3(0, 0, -0.39))
			_tube(_dark, 0.018, 0.05, Vector3(0, 0, -0.465))
			_rail(-0.32, 0.12, 0.042)
			_irons(0.1, -0.3, 0.047, 0.047)
			_mag(-0.06, 0.14, 0.18)
			_grip(_dark, 0.1)
			_box(_dark, Vector3(0.03, 0.01, 0.02), Vector3(0, 0.042, 0.125))
			_tube(_metal, 0.013, 0.12, Vector3(0, 0.0, 0.18))
			_box(_dark, Vector3(0.04, 0.075, 0.12), Vector3(0, -0.015, 0.26))
			_box(_accent, Vector3(0.042, 0.085, 0.02), Vector3(0, -0.018, 0.325))
			_muzzle_z = -0.49


## An imported gun model, turned so its barrel points down -Z, scaled to
## `length`, with the rear end behind the grip (z = 0.1) and the top of the
## gun just above the bore line. Its meshes become our own parts (so they
## get our layers and merge like the hand-built ones).
func _build_glb(style: String, spec: Array) -> void:
	var path: String = spec[0]
	var rot := Basis(Vector3.UP, -PI * 0.5) if spec[1] == "-x" else Basis(Vector3.UP, PI)
	var b: AABB = Models.bounds(path)
	var rb := Transform3D(rot) * b
	var length: float = spec[2]
	var k: float = length / rb.size.z
	var rear: float = 0.36 * length
	var top: float = 0.055 + float(spec[3])
	var off := Vector3(-rb.get_center().x * k, top - rb.end.y * k, rear - rb.end.z * k)
	var xf := Transform3D(rot.scaled(Vector3.ONE * k), off)
	for part in Models.parts(path):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = xf * part[1]
		var mesh: Mesh = part[0]
		for s in mesh.get_surface_count():
			mi.set_surface_override_material(s, _gunmetal(mesh.surface_get_material(s)))
		mi.layers = _layer
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _with_paw else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_target.add_child(mi)
	_muzzle_z = rear - length
	_sight_y = top + 0.012
	# A band of the player's colour on the stock, so guns stay recognisable.
	var w: float = rb.size.x * k
	if not path.begins_with("blaster/"):
		_box(_accent, Vector3(w + 0.004, 0.022, 0.05), Vector3(0, top - 0.04, rear - 0.12))
	# Sci-fi touches for the energy weapons.
	if style == "rail":
		for z in [-0.18, -0.26, -0.34]:
			_tube(_glow, 0.03, 0.016, Vector3(0, top - 0.06, _muzzle_z * 0.6 + z * 0.5))
	elif style == "zapper":
		_box(_glow, Vector3(w + 0.008, 0.01, 0.12), Vector3(0, top - 0.03, -0.1))


## The toon guns come with pale flat colours that wash out under the arena
## lighting: grey parts become darker, slightly metallic gun-metal, coloured
## parts (wood, tape) keep their hue a little deeper. Cached per material.
static var _metal_cache := {}

static func _gunmetal(src: Material) -> Material:
	if not src is StandardMaterial3D:
		return src
	if _metal_cache.has(src):
		return _metal_cache[src]
	var m: StandardMaterial3D = src.duplicate()
	var c: Color = m.albedo_color
	if m.albedo_texture != null:
		# Textured toy blasters keep their colours.
		m.roughness = 0.45
	elif c.s < 0.2:
		m.albedo_color = Color(c.r * 0.42, c.g * 0.42, c.b * 0.46)
		m.metallic = 0.55
		m.roughness = 0.38
	else:
		m.albedo_color = c.darkened(0.15)
		m.roughness = 0.6
	_metal_cache[src] = m
	return m


## --- model building helpers --------------------------------------------------

## Pistol grip, trigger and trigger guard at depth z (top of the grip at y_top).
func _grip(mat: Material, z: float, y_top := -0.03) -> void:
	_tilt(_box(mat, Vector3(0.032, 0.115, 0.05), Vector3(0, y_top - 0.055, z)), -0.28)
	_guard(z, y_top)


func _guard(z: float, y_top: float) -> void:
	_box(_dark, Vector3(0.01, 0.006, 0.065), Vector3(0, y_top - 0.045, z - 0.065))
	_box(_dark, Vector3(0.01, 0.04, 0.006), Vector3(0, y_top - 0.025, z - 0.098))
	_tilt(_box(_metal, Vector3(0.006, 0.024, 0.008), Vector3(0, y_top - 0.02, z - 0.055)), 0.3)


## Box magazine below the receiver; `rake` tilts the bottom forward.
func _mag(z: float, length: float, rake: float) -> void:
	_tilt(_box(_dark, Vector3(0.03, length, 0.055), Vector3(0, -0.04 - length * 0.5, z)), rake)
	_tilt(_box(_metal, Vector3(0.034, 0.01, 0.06), Vector3(0, -0.04 - length + 0.004, z + sin(rake) * length * 0.5)), rake)


## Picatinny rail on top from z0 to z1 at height y.
func _rail(z0: float, z1: float, y: float) -> void:
	_box(_dark, Vector3(0.024, 0.008, z1 - z0), Vector3(0, y, (z0 + z1) * 0.5))
	var z := z0 + 0.012
	while z < z1 - 0.008:
		_box(_dark, Vector3(0.028, 0.006, 0.01), Vector3(0, y + 0.005, z))
		z += 0.024


## Rear notch at rear_z and front post at front_z, both reaching _sight_y,
## standing on bodies whose tops are at rear_base / front_base.
func _irons(rear_z: float, front_z: float, rear_base: float, front_base: float) -> void:
	var sy := _sight_y
	var h := maxf(sy - 0.008 - rear_base, 0.004)
	_box(_dark, Vector3(0.03, h, 0.014), Vector3(0, rear_base + h * 0.5, rear_z))
	for sx in [-0.01, 0.01]:
		_box(_dark, Vector3(0.007, 0.014, 0.012), Vector3(sx, sy - 0.003, rear_z))
	var fh := maxf(sy - 0.012 - front_base, 0.004)
	_box(_dark, Vector3(0.02, fh, 0.012), Vector3(0, front_base + fh * 0.5, front_z))
	_box(_glow, Vector3(0.004, 0.014, 0.005), Vector3(0, sy - 0.007, front_z))
	for sx in [-0.009, 0.009]:
		_box(_dark, Vector3(0.004, 0.016, 0.012), Vector3(sx, sy - 0.006, front_z))


func _tilt(mi: MeshInstance3D, angle: float) -> MeshInstance3D:
	mi.rotation.x = angle
	return mi


## An empty pivot for animated parts (pump, cylinder, barrels, warhead).
func _node(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	n.position = pos
	add_child(n)
	return n


## Merge every static part (direct MeshInstance children) into one mesh with a
## surface per material: ~40 parts become ~6 draw calls per view.
func _merge() -> void:
	# Group every surface by (material, vertex format): imported meshes carry
	# their own materials and may have a different vertex layout.
	var groups := {}
	var order: Array = []
	var done: Array = []
	for c in get_children():
		if c is MeshInstance3D:
			var mesh: Mesh = c.mesh
			for s in mesh.get_surface_count():
				var m: Material = c.material_override
				if m == null:
					m = c.get_surface_override_material(s)
				if m == null:
					m = mesh.surface_get_material(s)
				var key := "%d_%d" % [m.get_instance_id() if m != null else 0, (mesh as ArrayMesh).surface_get_format(s) if mesh is ArrayMesh else -1]
				if not groups.has(key):
					groups[key] = [m, []]
					order.append(key)
				groups[key][1].append([mesh, s, c.transform])
			done.append(c)
	if order.is_empty():
		return
	for c in done:
		remove_child(c)
		c.queue_free()
	var am := ArrayMesh.new()
	for key in order:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for e in groups[key][1]:
			st.append_from(e[0], e[1], e[2])
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, groups[key][0])
	var merged := MeshInstance3D.new()
	merged.mesh = am
	merged.layers = _layer
	merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _with_paw else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	merged.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(merged)
	move_child(merged, 0)


## Scope (live lens) or red-dot sight on top of the gun, from the player's cards.
func _update_attachments(p) -> void:
	var lens: bool = p.stats.scope > 1.0 and p.stats.zoom >= 0.5
	var key := "scope" if lens else ("dot" if p.stats.red_dot else "")
	if key == _attach_key:
		if lens and _lens_mat != null:
			_lens_mat.set_shader_parameter("view", scope_texture)
		return
	_attach_key = key
	if _attach != null:
		_attach.queue_free()
		_attach = null
	if key == "":
		return
	_attach = _node(Vector3.ZERO)
	_target = _attach
	var sy := _sight_y + 0.045
	if lens:
		_tube(_dark, 0.036, 0.2, Vector3(0, sy, -0.03))
		_tube(_accent, 0.04, 0.025, Vector3(0, sy, -0.12))
		_tube(_dark, 0.04, 0.025, Vector3(0, sy, 0.06))
		_box(_dark, Vector3(0.02, 0.05, 0.04), Vector3(0, sy - 0.045, -0.06))
		var sh := Shader.new()
		sh.code = LENS_SHADER
		_lens_mat = ShaderMaterial.new()
		_lens_mat.shader = sh
		_lens_mat.set_shader_parameter("view", scope_texture)
		var quad := QuadMesh.new()
		quad.size = Vector2(0.066, 0.066)
		_part(quad, _lens_mat, Vector3(0, sy, 0.074))
	else:
		var y := _sight_y
		_box(_dark, Vector3(0.05, 0.004, 0.006), Vector3(0, y + 0.07, -0.05))
		_box(_dark, Vector3(0.004, 0.04, 0.006), Vector3(-0.024, y + 0.05, -0.05))
		_box(_dark, Vector3(0.004, 0.04, 0.006), Vector3(0.024, y + 0.05, -0.05))
		_box(_dark, Vector3(0.05, 0.012, 0.05), Vector3(0, y + 0.025, -0.05))
		var dot := _mat(Color(1.0, 0.1, 0.1), 0.3)
		dot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dot.albedo_color = Color(2.0, 0.2, 0.2)
		_ball(dot, Vector3(0, y + 0.05, -0.05), Vector3.ONE * 0.0035)
	_target = self


func _mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


## A cylinder (or capsule) lying along the barrel axis.
func _tube(mat: Material, radius: float, length: float, pos: Vector3, capsule := false) -> MeshInstance3D:
	var mesh: Mesh
	if capsule:
		var c := CapsuleMesh.new()
		c.radius = radius
		c.height = length
		mesh = c
	else:
		var cy := CylinderMesh.new()
		cy.top_radius = radius
		cy.bottom_radius = radius
		cy.height = length
		cy.radial_segments = 20
		cy.rings = 1
		mesh = cy
	var mi := _part(mesh, mat, pos)
	mi.rotation.x = PI / 2
	return mi


## A cone along the barrel axis: r_back at +Z, r_front at -Z.
func _cone(mat: Material, r_back: float, r_front: float, length: float, pos: Vector3) -> MeshInstance3D:
	var cy := CylinderMesh.new()
	cy.top_radius = r_back
	cy.bottom_radius = r_front
	cy.height = length
	cy.radial_segments = 20
	cy.rings = 1
	var mi := _part(cy, mat, pos)
	mi.rotation.x = PI / 2
	return mi


func _box(mat: Material, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _part(b, mat, pos)


func _ball(mat: Material, pos: Vector3, radii: Vector3) -> MeshInstance3D:
	var mi := _part(_sphere, mat, pos)
	mi.scale = radii
	return mi


func _part(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.layers = _layer
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _with_paw else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_target.add_child(mi)
	return mi


func update(delta: float, p) -> void:
	if p.weapon != weapon:
		set_weapon(p.weapon)
	var aim: float = p.aim_amount
	# A scoped weapon fills the screen with its scope instead (drawn by the HUD).
	visible = p.alive and not (p.stats.zoom < 0.5 and aim > 0.7)
	if not p.alive:
		_last_yaw = p.yaw
		_last_pitch = p.pitch
		return
	_t += delta
	var hip := 1.0 - aim
	var bob_scale: float = Settings.v("bob")

	# Look sway: the gun lags slightly behind the view.
	var dy := wrapf(p.yaw - _last_yaw, -PI, PI)
	var dp: float = p.pitch - _last_pitch
	_last_yaw = p.yaw
	_last_pitch = p.pitch
	_sway = _sway.lerp(Vector2(clampf(dy * 3.2, -0.08, 0.08), clampf(dp * 3.2, -0.06, 0.06)), clampf(delta * 14.0, 0.0, 1.0))
	_sway = _sway.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))
	var sway := _sway * (0.35 + 0.65 * hip)

	# Walk bob: a figure of eight, much smaller when aiming.
	var amt: float = p.bob_amount * bob_scale * (0.2 + 0.8 * hip)
	var bob := Vector3(cos(p.bob_phase) * 0.014, -absf(sin(p.bob_phase)) * 0.022 + 0.008, 0.0) * amt

	var kick: float = p.recoil * p.stats.recoil_kick * (0.6 + 0.4 * hip)
	_update_attachments(p)
	var ads := ADS - Vector3(0, _sight_y - 0.07, 0)
	if _attach_key == "scope":
		ads = Vector3(0, -(_sight_y + 0.045), -0.33)
	elif _attach_key == "dot":
		ads = Vector3(0, -(_sight_y + 0.05), -0.4)
	var base := HIP.lerp(ads, smoothstep(0.0, 1.0, aim))
	var pos := base + bob
	pos += Vector3(sway.x - p.strafe_amount * 0.014 * hip, -sway.y - p.land_dip * 0.06, kick * 0.06)
	# Jump / fall inertia: the gun trails the body's vertical motion.
	pos.y -= clampf(p.fall_amount * 0.005, -0.045, 0.05) * hip
	pos.y += sin(_t * 1.5) * 0.0025 * hip
	pos.z -= p.fov_kick * 0.05
	var rot := Vector3(
		kick * 0.13 - sway.y * 1.3 + p.fall_amount * 0.008 * hip,
		sway.x * 1.6,
		sway.x * -1.4 - p.strafe_amount * 0.1 * (0.3 + 0.7 * hip) + sin(p.bob_phase) * 0.02 * amt + sin(_t * 1.1) * 0.008 * hip)
	if p.reload_left > 0.0:
		var f: float = 1.0 - p.reload_left / p.stats.reload_time
		var dip := sin(f * PI)
		pos.y -= dip * 0.13
		rot.x -= dip * 0.55
		rot.z += sin(f * TAU) * 0.35
	if p.block_left > 0.0:
		# Guard pose: gun swings across the body.
		var g := sin(clampf(p.block_left / p.BLOCK_TIME, 0.0, 1.0) * PI)
		pos += Vector3(-0.12, 0.03, 0.06) * g
		rot += Vector3(0.1, 0.7, 0.3) * g
	# Per-weapon fire animation, driven by the time since the last shot.
	var st: float = p.shot_t
	scale = Vector3.ONE
	match _style:
		"scatter":
			var pump := sin(clampf((st - 0.12) / 0.35, 0.0, 1.0) * PI)
			pos.z += pump * 0.03 * hip
			rot.z += pump * 0.12 * hip
			if _pump != null:
				_pump.position.z = -0.2 + pump * 0.09
		"magnum":
			rot.x += exp(-st * 9.0) * 0.55 * (0.4 + 0.6 * hip)
			pos.y += exp(-st * 9.0) * 0.03
			_turn_drum(st, delta)
		"rail":
			pos.z += exp(-st * 5.0) * 0.1
			rot.x += exp(-st * 5.0) * 0.2 * hip
			_glow.emission_energy_multiplier = 1.8 + 6.0 * exp(-st * 3.0)
		"boomer", "lobber":
			pos.z += exp(-st * 4.0) * 0.14
			rot.x += exp(-st * 4.0) * 0.3 * hip
			_turn_drum(st, delta)
			if _warhead != null:
				# The next rocket slides in from the back once the last one left.
				_warhead.visible = st > 0.35
				_warhead.position.z = -0.42 + maxf(0.0, 0.6 - st) * 0.3
		"spinner", "zapper", "flamer":
			var j: float = p.recoil * 0.005
			pos += Vector3(randf_range(-j, j), randf_range(-j, j), 0.0)
		"bubbler":
			scale = Vector3.ONE * (1.0 + sin(st * 40.0) * exp(-st * 9.0) * 0.1)
		"pinball":
			rot.z += exp(-st * 8.0) * 0.5 * hip
		"burst":
			rot.x += exp(-st * 14.0) * 0.12
	# Parkour poses: tilt away from a wall, lower and roll during a slide.
	rot.z += p.wall_tilt * 0.3 * hip
	if p.sliding > 0.0:
		pos += Vector3(-0.04, -0.03, 0.02) * hip
		rot.z += 0.3 * hip
	# New weapon swings up into view.
	_swap = minf(1.0, _swap + delta * 3.5)
	if _swap < 1.0:
		var e := 1.0 - _swap
		pos.y -= e * e * 0.3
		rot.x -= e * e * 1.2
	position = pos
	rotation = rot

	if _spin != null:
		_spin_speed = lerpf(_spin_speed, 26.0 if p.recoil > 0.05 else 0.0, clampf(delta * 6.0, 0.0, 1.0))
		_spin.rotation.z += _spin_speed * delta

	_flash.visible = p.muzzle_flash > 0.0
	if _flash.visible:
		var fs: float = (0.035 + p.muzzle_flash * 0.08) * clampf(p.stats.recoil_kick, 0.8, 1.8)
		_flash.scale = Vector3(fs, fs, fs * 1.8)


## Rotate the cylinder one chamber per shot (shot_t drops back to 0 on a shot).
func _turn_drum(st: float, delta: float) -> void:
	if _drum == null:
		return
	if st < _last_st:
		_drum_angle += TAU / 6.0
	_last_st = st
	_drum.rotation.z = lerp_angle(_drum.rotation.z, _drum_angle, clampf(delta * 18.0, 0.0, 1.0))
