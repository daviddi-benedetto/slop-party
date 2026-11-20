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

const FpArm = preload("res://scripts/fp_arm.gd")
const Voxelizer = preload("res://scripts/voxelizer.gd")
const VOX_CELL := 0.014      # voxel size of the first-person gun (viewmodel units)
const VOX_CELL_TP := 0.022   # in a character's hands
const Fx = preload("res://scripts/fx.gd")
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
	"crossbow": ["medieval/Skeleton_Crossbow", "+z", 0.8, 0.0],
}

## Hand-held items that stand upright in the fist (blade / shaft along the
## model's +Y): [model, length, where along it the hand grips (0 = bottom),
## forward tilt, roll, optional width scale x / z and yaw]. Swords, axes and spears are swung (player melee);
## staffs cast from the tip; knives and bombs are thrown.
const UPRIGHT := {
	"sword": ["medieval/Sword_1", 0.95, 0.1, -0.5, -0.12],
	"axe": ["medieval/Skeleton_Axe", 0.95, 0.12, -0.45, -0.1],
	"spear": ["medieval/Weapon_Spear", 1.9, 0.38, -1.4, 0.0, 0.35, 0.35, 0.0],
	"knives": ["medieval/Dagger", 0.42, 0.15, -0.6, 0.2],
	"staff_storm": ["medieval/Skeleton_Staff", 1.2, 0.3, -0.8, -0.2],
	"staff_arcane": ["medieval/Skeleton_Staff", 1.2, 0.3, -0.8, -0.2],
	"bow": ["medieval/Weapon_Bow", 1.05, 0.5, -0.08, 0.3, 0.4, 1.0, PI],
	"bomb": ["medieval/Bomb", 0.26, 0.3, 0.0, 0.0],
}
const MELEE_STYLES := ["sword", "axe", "spear"]
## Long held items sit further out to the side and lower at the hip (they
## covered the middle of the screen): style -> [position offset, roll].
const HIP_SHIFT := {
	"sword": [Vector3(0.11, -0.07, 0.03), -0.12],
	"axe": [Vector3(0.11, -0.07, 0.03), -0.12],
	"spear": [Vector3(0.1, -0.05, 0.0), -0.08],
	"staff_storm": [Vector3(0.15, -0.12, 0.0), -0.1],
	"staff_arcane": [Vector3(0.15, -0.12, 0.0), -0.1],
}
## How far a sword / axe turns about its own length at rest (radians): a
## little, so its face shows; it turns edge-first into every slash.
const BLADE_REST_YAW := 0.55
## Dev: --melee-pose=0..1 freezes melee swings at that point (screenshots).
static var _melee_pose := -2.0
const KNIFE_TIME := 0.55         # the knife slash (melee with a gun in hand)
## Knife slash keyframes [time 0-1, position, rotation] in camera space: the
## off-paw draws the knife up and back (wind-up), whips it down across the
## view (fast, eased in), overshoots a touch, then lowers it away.
const KNIFE_KEYS := [
	[0.0, Vector3(0.5, -0.72, -0.5), Vector3(0.3, 0.6, -0.6)],
	[0.24, Vector3(0.42, -0.04, -0.56), Vector3(0.35, 0.5, -1.1)],
	[0.42, Vector3(-0.3, -0.34, -0.74), Vector3(-0.9, -0.35, 1.05)],
	[0.58, Vector3(-0.38, -0.4, -0.7), Vector3(-1.0, -0.45, 1.25)],
	[1.0, Vector3(-0.12, -0.86, -0.5), Vector3(-0.6, -0.2, 0.9)],
]

const HIP := Vector3(0.26, -0.24, -0.7)    # (further out than when paws held it: the stock no longer fills the corner)
const ADS := Vector3(0.0, -0.155, -0.5)

const LENS_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D view : source_color, filter_linear;
uniform float mag = 2.0;
void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c);
	if (r > 0.5) { discard; }
	// The scope camera looks the same way with its view narrowed by `mag`
	// (game.gd), on a square image. Show, at each pixel of the lens, what
	// lies behind that pixel on screen, magnified: a real zoom, never wider
	// than the view around it.
	vec2 ndc = SCREEN_UV * 2.0 - 1.0;
	ndc.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	vec3 col = texture(view, clamp(0.5 + 0.5 * ndc * mag, vec2(0.0), vec2(1.0))).rgb;
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
var kind := 0                    # the animal you play (fp_arm.gd fur colours); set before build()
var _layer := 1
var _with_paw := true
var _knife: Node3D               # the melee knife rig (under the camera, built on first use)
var _swoosh: MeshInstance3D      # the slash trail: an arc that flashes during the cut
var _reload_arm: Node3D          # the off paw that fetches a fresh magazine on reload
var _reload_rest := Transform3D()
var _mag_mesh: MeshInstance3D    # the magazine in that paw
var _flash: MeshInstance3D
var _spin: Node3D                # rotating barrel cluster (Spinner)
var _muzzle_z := -0.3
var _muzzle_xy := Vector2.ZERO   # muzzle offset from the bore axis (staff tip, mage orb)
var _blade: Node3D               # pivot of an UPRIGHT item
var _arrow: Node3D               # nocked arrow (bow) / spare item
var _orb: MeshInstance3D         # glowing spell orb (magic weapons)
var _shield: Node3D              # Medieval mode: the block is a shield on the left arm
var grip_r := Vector3(0, -0.08, 0.12)    # where the right / left hand holds it
var grip_l := Vector3(0, -0.05, -0.16)   # (third person: character.gd arm IK)
var two_handed := true
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
var _hover_beam: MeshInstance3D    # the light beam under a hovering sight
var _hover_mat: StandardMaterial3D
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
	_blade = null
	_arrow = null
	_orb = null
	_shield = null
	_muzzle_xy = Vector2.ZERO
	grip_r = Vector3(0, -0.08, 0.12)
	grip_l = Vector3(0, -0.05, -0.16)
	two_handed = true
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
	_merge()
	_reload_arm = null
	_mag_mesh = null
	# No arms in first person: the weapon simply floats (it still bobs and
	# sways as if held). Magic hands are the exception: they are the weapon.
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.albedo_color = Color(_color.lerp(Color(1.0, 0.85, 0.5), 0.7) * 2.6, 1.0)
	fmat.albedo_texture = Fx.star_texture()
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Muzzle flash: a hot four-point star facing the camera, a new angle
	# every shot (update()).
	var fq := QuadMesh.new()
	fq.size = Vector2.ONE * 0.9
	_flash = _part(fq, fmat, Vector3(_muzzle_xy.x, _muzzle_xy.y, _muzzle_z - 0.04))
	_flash.visible = false
	_swap = 0.0
	# The voxel world style: the gun and paws in small voxels (first person
	# finer, as it is right in front of the camera).
	if Settings.v("voxel"):
		Voxelizer.voxelize_node(self, VOX_CELL if _with_paw else VOX_CELL_TP, _color)


## Distance of the muzzle along -Z in model units (character.gd uses it).
func muzzle_z() -> float:
	return _muzzle_z


## World-space bore exit for shots and muzzle effects.
func muzzle_position() -> Vector3:
	return global_transform * Vector3(_muzzle_xy.x, _muzzle_xy.y, _muzzle_z)


## Same point in this model's own space (character.gd).
func muzzle_local() -> Vector3:
	return Vector3(_muzzle_xy.x, _muzzle_xy.y, _muzzle_z)


## Weapon models. Bore axis = the Z axis (y = 0), muzzle towards -Z, the
## pistol grip at z = 0.1 where the paw holds it. Real-world layout: receiver,
## barrel, handguard, magazine, stock, sights; the player's colour goes on
## the receiver / furniture, glowing strips mark the sci-fi parts.
## _sight_y = height of the iron-sight line (aiming lines it up with the eye).
func _build_gun(style: String) -> void:
	if UPRIGHT.has(style):
		_build_upright(style, UPRIGHT[style])
		return
	if style.begins_with("hands_"):
		_build_hands(style)
		return
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


## The sword / axe pivot: rest tilt and roll (UPRIGHT), then `roll` more
## about the view axis (the slash angle), `chop` about the blade's own
## sideways axis, and turned about its length from BLADE_REST_YAW to
## edge-on by `edge` (0..1). The model's flat side faces the camera at 0.
func _blade_basis(roll: float, chop: float, edge: float) -> Basis:
	var spec: Array = UPRIGHT[_style]
	# (The axe head already meets the air edge-first: it is not turned.)
	var yaw := 0.0 if _style == "axe" else lerpf(BLADE_REST_YAW, PI * 0.5, edge)
	return Basis(Vector3.BACK, float(spec[4]) + roll) * Basis(Vector3.RIGHT, float(spec[3]) + chop) * Basis(Vector3.UP, yaw)


## A sword, axe, spear, staff, bow, knife or bomb held upright in the fist.
## The model hangs on the _blade pivot (at the hand) so swings can turn it.
func _build_upright(style: String, spec: Array) -> void:
	var path: String = spec[0]
	var b: AABB = Models.bounds(path)
	var length: float = spec[1]
	var k: float = length / b.size.y
	var grip: float = spec[2]
	_blade = _node(Vector3(0, -0.07, 0.1))
	_blade.rotation = Vector3(spec[3], 0.0, spec[4])
	var off := Vector3(-b.get_center().x * k, -(b.position.y + grip * b.size.y) * k, -b.get_center().z * k)
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * k), off)
	if spec.size() > 7:
		# Chunky toy models are slimmed down (and the bow turned belly-forward).
		xf = Transform3D(Basis(Vector3.UP, spec[7]) * Basis.from_scale(Vector3(spec[5], 1.0, spec[6])), Vector3.ZERO) * xf
	for part in Models.parts(path):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = xf * part[1]
		mi.layers = _layer
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _with_paw else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_blade.add_child(mi)
	var tip: Vector3 = _blade.transform * Vector3(0, (1.0 - grip) * length, 0)
	two_handed = false
	grip_r = Vector3(0, -0.07, 0.1)
	_sight_y = 0.02
	_muzzle_z = -0.3
	if style.begins_with("staff_"):
		# The spell leaves from a glowing orb at the head of the staff.
		var col := Color(0.55, 0.8, 1.0) if style == "staff_storm" else Color(0.85, 0.45, 1.0)
		_target = _blade
		_orb = _ball(_spell_mat(col), Vector3(0, (1.0 - grip) * length + 0.03, 0), Vector3.ONE * 0.06)
		_target = self
		_muzzle_xy = Vector2(tip.x, tip.y)
		_muzzle_z = tip.z
	elif style == "bow":
		# A nocked arrow lies through the grip, pointing down range.
		_arrow = _node(Vector3(0.015, -0.07, 0.1))
		var ab: AABB = Models.bounds("medieval/Weapon_Arrow")
		var ak: float = 0.78 / ab.size.z
		for part in Models.parts("medieval/Weapon_Arrow"):
			var am := MeshInstance3D.new()
			am.mesh = part[0]
			am.transform = Transform3D(Basis.from_scale(Vector3.ONE * ak), Vector3(0, 0, -0.12) - ab.get_center() * ak) * part[1]
			am.layers = _layer
			am.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			am.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			_arrow.add_child(am)
		two_handed = true
		grip_l = Vector3(0, -0.07, 0.1)
		grip_r = Vector3(0.03, -0.07, 0.42)
		_muzzle_z = -0.5
	elif style == "spear":
		grip_l = Vector3(0, -0.07, -0.3)
		two_handed = true


## Mage hands: two open hands with a ball of fire or frost between them.
func _build_hands(style: String) -> void:
	var fire := style == "hands_fire"
	var col := Color(1.0, 0.5, 0.12) if fire else Color(0.55, 0.85, 1.0)
	if _with_paw:
		for sx in [0.0, -0.54]:
			var inward := 1.0 if sx == 0.0 else -1.0
			var hand := _node(Vector3(sx, 0.02, -0.04))
			# Forearms rise from the bottom corners, palms (toe beans) up.
			hand.rotation = Vector3(0.45, inward * 0.42, inward * 0.3)
			# Your own open plush paw, toe beans up, a glow round the wrist.
			hand.add_child(FpArm.build(kind, _color, _layer, inward, "open", 0.42))
	_orb = _ball(_spell_mat(col), Vector3(-0.27, 0.1, -0.2), Vector3.ONE * (0.055 if _with_paw else 0.11))
	if not _with_paw:
		_orb.position = Vector3(-0.12, 0.0, -0.1)
	_muzzle_xy = Vector2(_orb.position.x, _orb.position.y)
	_muzzle_z = _orb.position.z - 0.08
	_sight_y = 0.05
	grip_r = Vector3(0.02, -0.02, 0.05)
	grip_l = Vector3(-0.26, -0.02, 0.05)


static var _spell_mats := {}

static func _spell_mat(col: Color) -> StandardMaterial3D:
	if not _spell_mats.has(col):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col.lerp(Color.WHITE, 0.25) * 2.4
		_spell_mats[col] = m
	return _spell_mats[col]


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


## Reload: the off paw drops out of view, comes back up with a fresh
## magazine, slaps it into the gun and returns to the fore-end.
func _update_reload_paw(p) -> void:
	if _reload_arm == null or not is_instance_valid(_reload_arm):
		return
	var one_handed: bool = not two_handed or _style in ["magnum", "twins"]
	if p.reload_left <= 0.0:
		_reload_arm.transform = _reload_rest
		_reload_arm.visible = not one_handed
		_mag_mesh.visible = false
		return
	var f: float = 1.0 - p.reload_left / p.stats.reload_time
	var down := _reload_rest.origin + Vector3(-0.1, -0.32, 0.18)
	var well := Vector3(0.0, -0.17, -0.02)
	var pos: Vector3
	if f < 0.3:
		pos = _reload_rest.origin.lerp(down, smoothstep(0.0, 1.0, f / 0.3))
	elif f < 0.62:
		pos = down.lerp(well, smoothstep(0.0, 1.0, (f - 0.3) / 0.32))
	elif f < 0.78:
		pos = well + Vector3(0, 0.05 * sin((f - 0.62) / 0.16 * PI), 0)
	else:
		pos = well.lerp(_reload_rest.origin, smoothstep(0.0, 1.0, (f - 0.78) / 0.22))
	_reload_arm.visible = true
	_reload_arm.transform = Transform3D(_reload_rest.basis, pos)
	_mag_mesh.visible = f > 0.3 and f < 0.72


## A first-person plush arm (fp_arm.gd) with its paw at `at`, the forearm
## running back along `back` (towards the bottom edge of the screen).
func _arm(at: Vector3, back: Vector3, side: float, length: float, pose := "fist", parent: Node3D = null) -> Node3D:
	var a := FpArm.build(kind, _color, _layer, side, pose, length)
	a.position = at
	a.basis = Basis.looking_at(-back.normalized(), Vector3.UP)
	(parent if parent != null else self).add_child(a)
	return a


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
			_lens_mat.set_shader_parameter("mag", p.stats.scope)
		return
	_attach_key = key
	_hover_beam = null
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
		# No mount: the scope hovers on an anti-grav emitter (_hover_parts).
		_hover_parts(Vector3(0, sy - 0.052, -0.03), 0.042, 0.05)
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
		_box(_dark, Vector3(0.05, 0.006, 0.05), Vector3(0, y + 0.028, -0.05))
		_hover_parts(Vector3(0, y + 0.022, -0.05), 0.022, 0.03)
		var dot := _mat(Color(1.0, 0.1, 0.1), 0.3)
		dot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dot.albedo_color = Color(2.0, 0.2, 0.2)
		_ball(dot, Vector3(0, y + 0.05, -0.05), Vector3.ONE * 0.0035)
	_target = self


## A hovering sight's emitter: a glowing ring in the player's colour under
## the sight and a soft beam of light down to the gun (pulses in update()).
func _hover_parts(at: Vector3, ring_r: float, beam_h: float) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = ring_r * 0.7
	ring.outer_radius = ring_r
	ring.rings = 16
	ring.ring_segments = 6
	var rm := _mat(_color.lerp(Color.WHITE, 0.35), 0.2)
	rm.emission_enabled = true
	rm.emission = _color.lerp(Color.WHITE, 0.3)
	rm.emission_energy_multiplier = 3.0
	_part(ring, rm, at).scale = Vector3(1.0, 0.5, 1.0)
	_part(ring, rm, at - Vector3(0, beam_h * 0.55, 0)).scale = Vector3(0.55, 0.5, 0.55)
	_hover_mat = StandardMaterial3D.new()
	_hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_hover_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hover_mat.albedo_color = Color(_color.lerp(Color.WHITE, 0.4) * 1.6, 0.5)
	var cone := CylinderMesh.new()
	cone.top_radius = ring_r * 0.75
	cone.bottom_radius = ring_r * 0.25
	cone.height = beam_h
	cone.radial_segments = 12
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_hover_beam = _part(cone, _hover_mat, at - Vector3(0, beam_h * 0.5, 0))


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
		if _knife != null:
			_knife.visible = false
			_swoosh.visible = false
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
	if _attach != null:
		# The hovering sight bobs on its emitter, steady while aiming so the
		# sight still lines up with the eye.
		_attach.position.y = sin(_t * 2.4) * 0.006 * (1.0 - aim)
		if _hover_beam != null and _hover_mat != null:
			_hover_mat.albedo_color.a = 0.4 + 0.2 * sin(_t * 7.0)
	var ads := ADS - Vector3(0, _sight_y - 0.07, 0)
	if _attach_key == "scope":
		ads = Vector3(0, -(_sight_y + 0.045), -0.33)
	elif _attach_key == "dot":
		ads = Vector3(0, -(_sight_y + 0.05), -0.4)
	var shift: Array = HIP_SHIFT.get(_style, [Vector3.ZERO, 0.0])
	var base := (HIP + (shift[0] as Vector3)).lerp(ads, smoothstep(0.0, 1.0, aim))
	var pos := base + bob
	pos += Vector3(sway.x - p.strafe_amount * 0.014 * hip, -sway.y - p.land_dip * 0.06, kick * 0.06)
	# Jump / fall inertia: the gun trails the body's vertical motion.
	pos.y -= clampf(p.fall_amount * 0.005, -0.045, 0.05) * hip
	pos.y += sin(_t * 1.5) * 0.0025 * hip
	pos.z -= p.fov_kick * 0.05
	var rot := Vector3(
		kick * 0.13 - sway.y * 1.3 + p.fall_amount * 0.008 * hip,
		sway.x * 1.6,
		sway.x * -1.4 - p.strafe_amount * 0.1 * (0.3 + 0.7 * hip) + sin(p.bob_phase) * 0.02 * amt + sin(_t * 1.1) * 0.008 * hip + float(shift[1]) * hip)
	if p.reload_left > 0.0:
		var f: float = 1.0 - p.reload_left / p.stats.reload_time
		var dip := sin(f * PI)
		pos.y -= dip * 0.13
		rot.x -= dip * 0.55
		rot.z += sin(f * TAU) * 0.35
	_update_reload_paw(p)
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
		"knives", "bomb":
			var flick := exp(-st * 9.0)
			rot.x -= flick * 0.9
			pos.z -= flick * 0.14
			if _blade != null:
				_blade.visible = st > 0.16 and p.reload_left <= 0.0
		"bow":
			rot.z += exp(-st * 12.0) * 0.12
			pos.z += exp(-st * 10.0) * 0.03
			if _arrow != null:
				_arrow.visible = st > 0.4 and p.reload_left <= 0.0
				_arrow.position.z = 0.1 + clampf(st - 0.4, 0.0, 0.3) * 0.5 * hip
		"staff_storm", "staff_arcane":
			rot.x -= exp(-st * 7.0) * 0.4
			pos.z -= exp(-st * 7.0) * 0.08
		"hands_fire", "hands_frost":
			pos.z -= exp(-st * 8.0) * 0.12
			pos.y += sin(_t * 2.2) * 0.004
	if _orb != null:
		var pulse := 1.0 + sin(_t * 7.0) * 0.12 + exp(-st * 6.0) * 0.9
		_orb.scale = Vector3.ONE * (0.055 if _style.begins_with("hands_") and _with_paw else 0.06) * pulse
	# Melee: weapons slash or thrust; anything else is a quick butt strike.
	var knife_slash: bool = _with_paw and not _style in MELEE_STYLES
	var mdur: float = minf(KNIFE_TIME, p.stats.melee_cd * 0.9) if knife_slash else clampf(p.stats.fire_interval * 0.75, 0.3, 0.5)
	if _melee_pose < -1.0:
		_melee_pose = -1.0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--melee-pose="):
				_melee_pose = float(a.substr(13))
	if _melee_pose >= 0.0:
		p.melee_t = _melee_pose * mdur
	_update_knife(p, mdur if knife_slash else 0.0)
	if _blade != null and _style in ["sword", "axe"]:
		_blade.basis = _blade_basis(0.0, 0.0, 0.0)
	if p.melee_t < mdur:
		var mf: float = p.melee_t / mdur
		var sw := sin(mf * PI)
		var sgn := 1.0 if p.melee_n % 2 == 0 else -1.0
		match _style:
			"spear":
				pos.z -= sw * 0.55
				pos.y += sw * 0.05
			"sword", "axe":
				# The chop (about the view's sideways axis) leads with the
				# edge: the blade turns edge-on as the swing starts, so it
				# cuts instead of paddling the air flat-first.
				rot.x += 0.35 * (1.0 - mf) - 1.45 * sw
				rot.z += sgn * (0.9 - 1.9 * mf) * sw
				rot.y += sgn * 0.5 * sw
				pos.x -= sgn * 0.14 * sw + 0.08 * sw
				pos.z -= 0.14 * sw
				var turn := smoothstep(0.0, 0.15, mf) * (1.0 - smoothstep(0.85, 1.0, mf))
				if _blade != null:
					_blade.basis = _blade_basis(0.0, 0.0, turn)
			_:
				# The gun drops out of the way while the other paw slashes.
				var away := smoothstep(0.0, 0.25, mf) * (1.0 - smoothstep(0.6, 1.0, mf))
				rot.x -= 0.55 * away
				rot.z -= 0.35 * away
				pos += Vector3(0.08, -0.16, 0.06) * away
	# Medieval mode: blocking raises a shield in front of you.
	if p.game.mode == "medieval" and _with_paw:
		if _shield == null or not is_instance_valid(_shield):
			_shield = _node(Vector3.ZERO)
			var sb: AABB = Models.bounds("medieval/Skeleton_Shield_Large_A")
			var sk: float = 0.5 / sb.size.y
			for part in Models.parts("medieval/Skeleton_Shield_Large_A"):
				var sm := MeshInstance3D.new()
				sm.mesh = part[0]
				sm.transform = Transform3D(Basis(Vector3.UP, PI) * Basis.from_scale(Vector3.ONE * sk), -sb.get_center() * sk) * part[1]
				sm.layers = _layer
				sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				sm.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
				_shield.add_child(sm)
		var up: float = clampf(p.block_left * 8.0, 0.0, 1.0)
		_shield.visible = up > 0.01
		_shield.position = Vector3(-0.3, -0.3 + 0.32 * up, -0.12)
		_shield.rotation = Vector3(0.1, 0.25, 0.08 * (1.0 - up))
	# Sprinting: the weapon drops and turns across the body.
	var run: float = p.sprint_amount * hip
	pos += Vector3(-0.05, -0.05, 0.03) * run
	rot += Vector3(-0.12, 0.45, 0.1) * run
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

	_flash.visible = p.muzzle_flash > 0.0 and not _style in MELEE_STYLES and not _style in ["flamer", "hands_fire", "hands_frost", "staff_storm", "staff_arcane", "bow", "knives", "bomb"]
	if _flash.visible:
		if p.muzzle_flash > 0.95:
			_flash.rotation.z = randf() * TAU
		var fs: float = (0.05 + p.muzzle_flash * 0.12) * clampf(p.stats.recoil_kick, 0.8, 1.8)
		_flash.scale = Vector3(fs, fs, 1.0)


## The melee knife: a plush paw holding a short blade, animated through
## KNIFE_KEYS over `dur` seconds after a melee starts (dur 0 = hidden). It
## lives under the camera (not this gun node) so the gun can drop away.
func _update_knife(p, dur: float) -> void:
	var active: bool = dur > 0.0 and p.melee_t < dur and p.alive
	if not active:
		if _knife != null:
			_knife.visible = false
		return
	if _knife == null:
		_build_knife()
		_build_swoosh()
	_knife.visible = true
	var f: float = clampf(p.melee_t / dur, 0.0, 1.0)
	var i := 0
	while i < KNIFE_KEYS.size() - 2 and f > KNIFE_KEYS[i + 1][0]:
		i += 1
	var a: Array = KNIFE_KEYS[i]
	var b: Array = KNIFE_KEYS[i + 1]
	var u: float = clampf((f - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	match i:
		0: u = 1.0 - pow(1.0 - u, 2.0)      # wind-up: quick, then settles
		1: u = u * u * u                    # the strike accelerates
		2: u = 1.0 - pow(1.0 - u, 3.0)      # overshoot eases out
		_: u = u * u * (3.0 - 2.0 * u)      # recovery
	_knife.position = (a[1] as Vector3).lerp(b[1], u)
	_knife.rotation = (a[2] as Vector3).lerp(b[2], u)
	# Slash trail: flashes in with the cut and fades as the blade overshoots.
	var sw := 0.0
	if f > 0.3 and f < 0.75:
		sw = clampf((f - 0.3) / 0.08, 0.0, 1.0) * (1.0 - clampf((f - 0.48) / 0.27, 0.0, 1.0))
	_swoosh.visible = sw > 0.01
	(_swoosh.material_override as StandardMaterial3D).albedo_color.a = sw * 0.75


func _build_knife() -> void:
	_knife = Node3D.new()
	_knife.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_parent().add_child(_knife)
	# (The knife floats too, like every first-person weapon: no paw.)
	# Blade along the model's +Y; grip 15 % up the model sits in the paw,
	# the blade pointing forward and a little up.
	var path := "medieval/Knife"
	var bb: AABB = Models.bounds(path)
	var k := 0.44 / bb.size.y
	var grip := Vector3(bb.get_center().x, bb.position.y + bb.size.y * 0.15, bb.get_center().z)
	var hold := Basis(Vector3.RIGHT, -1.25)
	for part in Models.parts(path):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = Transform3D(hold * Basis.from_scale(Vector3.ONE * k), -(hold * (grip * k))) * part[1]
		mi.layers = _layer
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_knife.add_child(mi)
		Models.toy_node(mi, false)


## The slash trail: a ribbon along the path the blade tip sweeps (from the
## wind-up key to the overshoot), fading towards where the cut began.
func _build_swoosh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var a: Vector3 = KNIFE_KEYS[1][1] + Vector3(0.0, 0.18, -0.2)
	var c: Vector3 = KNIFE_KEYS[3][1] + Vector3(-0.05, 0.02, -0.25)
	var mid: Vector3 = (a + c) * 0.5 + Vector3(0.05, 0.12, -0.18)
	var n := 18
	for i in n + 1:
		var t := float(i) / n
		var p: Vector3 = a.lerp(mid, t).lerp(mid.lerp(c, t), t)
		var w := 0.025 + 0.07 * sin(t * PI)
		var col := Color(1, 1, 1, pow(t, 1.4))
		st.set_color(col)
		st.add_vertex(p + Vector3(0, w, 0.01))
		st.set_color(Color(col, col.a * 0.2))
		st.add_vertex(p - Vector3(0, w, -0.01))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.albedo_color = Color(_color.lerp(Color.WHITE, 0.7), 0.0)
	_swoosh = MeshInstance3D.new()
	_swoosh.mesh = st.commit()
	_swoosh.material_override = mat
	_swoosh.layers = _layer
	_swoosh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_swoosh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_swoosh.visible = false
	get_parent().add_child(_swoosh)


func _exit_tree() -> void:
	if _knife != null and is_instance_valid(_knife):
		_knife.queue_free()
	if _swoosh != null and is_instance_valid(_swoosh):
		_swoosh.queue_free()


## Rotate the cylinder one chamber per shot (shot_t drops back to 0 on a shot).
func _turn_drum(st: float, delta: float) -> void:
	if _drum == null:
		return
	if st < _last_st:
		_drum_angle += TAU / 6.0
	_last_st = st
	_drum.rotation.z = lerp_angle(_drum.rotation.z, _drum_angle, clampf(delta * 18.0, 0.0, 1.0))
