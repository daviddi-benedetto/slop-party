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

const HIP := Vector3(0.27, -0.25, -0.58)
const ADS := Vector3(0.0, -0.155, -0.5)

var weapon := -1
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

var _shell: StandardMaterial3D
var _accent: StandardMaterial3D
var _dark: StandardMaterial3D
var _glow: StandardMaterial3D
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
	_dark = _mat(Color(0.07, 0.07, 0.1), 0.45)
	_dark.metallic = 0.5
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
		c.queue_free()
	_spin = null
	_sight_y = 0.07
	_build_gun(Weapons.LIST[id].style)
	if _with_paw:
		var plush := _mat(_color.lerp(Color(1, 0.97, 0.9), 0.25), 0.95)
		plush.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		plush.rim_enabled = true
		plush.rim = 0.5
		_ball(plush, Vector3(0.005, -0.11, 0.11), Vector3(0.075, 0.07, 0.08))
		_ball(plush, Vector3(0.04, -0.22, 0.3), Vector3(0.065, 0.065, 0.22))
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.albedo_color = Color(_color.lerp(Color(1.0, 0.9, 0.6), 0.6) * 2.0, 0.9)
	_flash = _ball(fmat, Vector3(0, 0, _muzzle_z), Vector3.ONE * 0.05)
	_flash.visible = false
	_swap = 0.0


func _build_gun(style: String) -> void:
	# Grip shared by every weapon.
	var grip := CapsuleMesh.new()
	grip.radius = 0.034
	grip.height = 0.17
	_part(grip, _dark, Vector3(0, -0.1, 0.1)).rotation.x = 0.3
	match style:
		"scatter":
			for sx in [-0.045, 0.045]:
				_tube(_dark, 0.042, 0.4, Vector3(sx, 0.0, -0.04))
				_tube(_glow, 0.03, 0.02, Vector3(sx, 0.0, -0.245))
			_tube(_accent, 0.064, 0.12, Vector3(0, 0, 0.1))
			_tube(_shell, 0.06, 0.05, Vector3(0, 0, -0.12))
			_ball(_glow, Vector3(0, 0.055, 0.02), Vector3(0.022, 0.018, 0.07))
			_muzzle_z = -0.3
		"zapper":
			_tube(_accent, 0.04, 0.34, Vector3(0, 0, 0.0), true)
			_tube(_shell, 0.026, 0.3, Vector3(0, 0, -0.26))
			_tube(_dark, 0.05, 0.04, Vector3(0, 0, -0.13))
			var drum := CylinderMesh.new()
			drum.top_radius = 0.06
			drum.bottom_radius = 0.06
			drum.height = 0.07
			_part(drum, _dark, Vector3(0, -0.07, -0.05))
			_ball(_glow, Vector3(0, 0.0, -0.42), Vector3.ONE * 0.03)
			_muzzle_z = -0.46
		"boomer":
			_tube(_dark, 0.085, 0.5, Vector3(0, 0.02, -0.03))
			_tube(_accent, 0.1, 0.07, Vector3(0, 0.02, -0.27))
			_tube(_accent, 0.095, 0.05, Vector3(0, 0.02, 0.2))
			_tube(_shell, 0.09, 0.03, Vector3(0, 0.02, -0.05))
			_ball(_glow, Vector3(0, 0.02, -0.3), Vector3(0.055, 0.055, 0.075))
			_sight_y = 0.13
			_muzzle_z = -0.4
		"rail":
			_tube(_dark, 0.04, 0.3, Vector3(0, 0, 0.04), true)
			_tube(_shell, 0.022, 0.5, Vector3(0, 0, -0.34))
			for z in [-0.2, -0.33, -0.46]:
				_tube(_glow, 0.036, 0.022, Vector3(0, 0, z))
			_tube(_accent, 0.028, 0.2, Vector3(0, 0.07, -0.02))
			_tube(_glow, 0.024, 0.012, Vector3(0, 0.07, -0.125))
			_sight_y = 0.07
			_muzzle_z = -0.62
		"lobber":
			_tube(_dark, 0.08, 0.28, Vector3(0, 0.01, -0.06))
			_tube(_accent, 0.092, 0.05, Vector3(0, 0.01, -0.2))
			_ball(_shell, Vector3(0, -0.02, 0.1), Vector3(0.085, 0.085, 0.085))
			_ball(_glow, Vector3(0, 0.085, -0.02), Vector3(0.03, 0.02, 0.05))
			_sight_y = 0.11
			_muzzle_z = -0.3
		"bubbler":
			_tube(_dark, 0.05, 0.26, Vector3(0, 0, -0.02), true)
			var tank := _mat(_color.lerp(Color.WHITE, 0.4), 0.1)
			tank.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tank.albedo_color.a = 0.55
			tank.emission_enabled = true
			tank.emission = _color.lerp(Color.WHITE, 0.3)
			tank.emission_energy_multiplier = 1.6
			_ball(tank, Vector3(0, 0.09, 0.03), Vector3.ONE * 0.075)
			var horn := CylinderMesh.new()
			horn.top_radius = 0.085
			horn.bottom_radius = 0.04
			horn.height = 0.1
			_part(horn, _accent, Vector3(0, 0, -0.2)).rotation.x = -PI / 2
			_sight_y = 0.17
			_muzzle_z = -0.3
		"burst":
			_tube(_dark, 0.045, 0.46, Vector3(0, 0, -0.05), true)
			_tube(_shell, 0.024, 0.26, Vector3(0, 0, -0.38))
			_box(_accent, Vector3(0.06, 0.035, 0.3), Vector3(0, 0.055, -0.04))
			_box(_dark, Vector3(0.045, 0.14, 0.07), Vector3(0, -0.1, -0.08)).rotation.x = -0.2
			for z in [-0.15, -0.05, 0.05]:
				_box(_glow, Vector3(0.064, 0.012, 0.03), Vector3(0, 0.074, z))
			_sight_y = 0.09
			_muzzle_z = -0.54
		"magnum":
			_tube(_shell, 0.04, 0.3, Vector3(0, 0.02, -0.14))
			_box(_dark, Vector3(0.05, 0.03, 0.3), Vector3(0, 0.065, -0.14))
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.062
			cyl.bottom_radius = 0.062
			cyl.height = 0.1
			cyl.radial_segments = 6
			_part(cyl, _accent, Vector3(0, 0.01, 0.04)).rotation.x = PI / 2
			_tube(_glow, 0.03, 0.012, Vector3(0, 0.02, -0.295))
			_sight_y = 0.085
			_muzzle_z = -0.36
		"spinner":
			_tube(_dark, 0.085, 0.24, Vector3(0, 0, 0.06))
			_tube(_accent, 0.092, 0.04, Vector3(0, 0, -0.05))
			_spin = Node3D.new()
			_spin.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			add_child(_spin)
			for i in 4:
				var a := TAU * i / 4.0
				var barrel := _tube(_shell, 0.022, 0.42, Vector3(cos(a) * 0.045, sin(a) * 0.045, -0.26))
				remove_child(barrel)
				_spin.add_child(barrel)
			var cap := _tube(_glow, 0.07, 0.015, Vector3(0, 0, -0.46))
			remove_child(cap)
			_spin.add_child(cap)
			_sight_y = 0.11
			_muzzle_z = -0.5
		"pinball":
			_ball(_dark, Vector3(0, 0.0, 0.0), Vector3.ONE * 0.085)
			_ball(_glow, Vector3(0, 0.0, 0.0), Vector3(0.09, 0.03, 0.09))
			_tube(_accent, 0.045, 0.22, Vector3(0, 0, -0.16))
			_tube(_shell, 0.055, 0.03, Vector3(0, 0, -0.27))
			_sight_y = 0.1
			_muzzle_z = -0.32
		"flamer":
			_tube(_dark, 0.045, 0.4, Vector3(0, 0.0, -0.08))
			_tube(_accent, 0.07, 0.24, Vector3(0, -0.085, 0.02), true)
			var cone := CylinderMesh.new()
			cone.top_radius = 0.07
			cone.bottom_radius = 0.035
			cone.height = 0.09
			_part(cone, _shell, Vector3(0, 0, -0.31)).rotation.x = -PI / 2
			var pilot := _mat(Color(1.0, 0.5, 0.1), 0.2)
			pilot.emission_enabled = true
			pilot.emission = Color(1.0, 0.45, 0.1)
			pilot.emission_energy_multiplier = 4.0
			_ball(pilot, Vector3(0, 0, -0.34), Vector3.ONE * 0.025)
			_muzzle_z = -0.4
		_:
			_tube(_dark, 0.055, 0.4, Vector3(0, 0, 0), true)
			_tube(_accent, 0.07, 0.07, Vector3(0, 0, -0.15))
			_tube(_accent, 0.064, 0.03, Vector3(0, 0, 0.1))
			var nozzle := CylinderMesh.new()
			nozzle.top_radius = 0.036
			nozzle.bottom_radius = 0.046
			nozzle.height = 0.08
			_part(nozzle, _shell, Vector3(0, 0, -0.22)).rotation.x = -PI / 2
			_ball(_glow, Vector3(0, 0.065, -0.02), Vector3(0.022, 0.02, 0.09))
			_muzzle_z = -0.32


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
		mesh = cy
	var mi := _part(mesh, mat, pos)
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
	add_child(mi)
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
	var base := HIP.lerp(ADS - Vector3(0, _sight_y - 0.07, 0), smoothstep(0.0, 1.0, aim))
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
