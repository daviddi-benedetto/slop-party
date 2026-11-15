extends Node3D
## A toy gun model. Used two ways:
##  - first person: a child of one player's Camera3D, drawn only on that
##    player's private viewmodel layer and animated per rendered frame by
##    game.gd calling update() (walk bob, look sway, recoil, reload, landing
##    dip, muzzle flash). It rebuilds itself when the player's weapon changes.
##  - as a prop: pickup.gd builds one with with_paw = false on layer 1.
##
## Each weapon style (weapons.gd "style") is a small arrangement of primitive
## parts in _build_gun(). Local space: the barrel points down -Z.

const Weapons = preload("res://scripts/weapons.gd")

var weapon := -1
var _color := Color.WHITE
var _layer := 1
var _with_paw := true
var _flash: MeshInstance3D
var _muzzle_z := -0.3
var _last_yaw := 0.0
var _last_pitch := 0.0
var _sway := Vector2.ZERO
var _bob := 0.0
var _swap := 1.0
var _rest := Vector3(0.27, -0.25, -0.58)

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
	_shell = _mat(Color(0.93, 0.91, 0.88), 0.6)
	_accent = _mat(color, 0.5)
	_dark = _mat(Color(0.2, 0.17, 0.27), 0.5)
	_glow = _mat(color.lerp(Color.WHITE, 0.4), 0.2)
	_glow.emission_enabled = true
	_glow.emission = color.lerp(Color.WHITE, 0.3)
	_glow.emission_energy_multiplier = 0.9
	_sphere = SphereMesh.new()
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 20
	_sphere.rings = 10
	set_weapon(weapon_id)
	position = _rest


func set_weapon(id: int) -> void:
	if id == weapon:
		return
	weapon = id
	for c in get_children():
		c.queue_free()
	_build_gun(Weapons.LIST[id].style)
	if _with_paw:
		var plush := _mat(_color.lerp(Color(1, 0.97, 0.9), 0.3), 0.95)
		plush.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		plush.rim_enabled = true
		plush.rim = 0.5
		_ball(plush, Vector3(0.005, -0.11, 0.11), Vector3(0.075, 0.07, 0.08))
		_ball(plush, Vector3(0.04, -0.22, 0.3), Vector3(0.065, 0.065, 0.22))
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.albedo_color = Color(1.0, 0.95, 0.6, 0.9)
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
				_tube(_accent, 0.042, 0.4, Vector3(sx, 0.0, -0.04))
				_tube(_dark, 0.034, 0.05, Vector3(sx, 0.0, -0.25))
			_tube(_shell, 0.062, 0.1, Vector3(0, 0, 0.1), true)
			_tube(_shell, 0.06, 0.05, Vector3(0, 0, -0.12), true)
			_ball(_glow, Vector3(0, 0.055, 0.02), Vector3(0.03, 0.025, 0.07))
			_muzzle_z = -0.3
		"zapper":
			_tube(_accent, 0.04, 0.34, Vector3(0, 0, 0.0), false, true)
			_tube(_shell, 0.026, 0.3, Vector3(0, 0, -0.26))
			_tube(_shell, 0.05, 0.04, Vector3(0, 0, -0.13))
			var drum := CylinderMesh.new()
			drum.top_radius = 0.06
			drum.bottom_radius = 0.06
			drum.height = 0.07
			_part(drum, _shell, Vector3(0, -0.07, -0.05))
			_ball(_glow, Vector3(0, 0.0, -0.42), Vector3.ONE * 0.03)
			_muzzle_z = -0.46
		"boomer":
			_tube(_accent, 0.085, 0.5, Vector3(0, 0.02, -0.03))
			_tube(_shell, 0.1, 0.07, Vector3(0, 0.02, -0.27))
			_tube(_shell, 0.095, 0.05, Vector3(0, 0.02, 0.2))
			_tube(_dark, 0.07, 0.03, Vector3(0, 0.02, -0.31))
			_ball(_glow, Vector3(0, 0.02, -0.3), Vector3(0.055, 0.055, 0.075))
			_muzzle_z = -0.4
		"rail":
			_tube(_accent, 0.04, 0.3, Vector3(0, 0, 0.04), false, true)
			_tube(_shell, 0.022, 0.5, Vector3(0, 0, -0.34))
			for z in [-0.2, -0.33, -0.46]:
				_tube(_glow, 0.036, 0.022, Vector3(0, 0, z))
			_tube(_dark, 0.028, 0.2, Vector3(0, 0.07, -0.02))
			_tube(_glow, 0.024, 0.012, Vector3(0, 0.07, -0.125))
			_muzzle_z = -0.62
		"lobber":
			_tube(_accent, 0.08, 0.28, Vector3(0, 0.01, -0.06))
			_tube(_shell, 0.092, 0.05, Vector3(0, 0.01, -0.2))
			_tube(_dark, 0.066, 0.03, Vector3(0, 0.01, -0.225))
			_ball(_shell, Vector3(0, -0.02, 0.1), Vector3(0.085, 0.085, 0.085))
			_ball(_glow, Vector3(0, 0.085, -0.02), Vector3(0.03, 0.02, 0.05))
			_muzzle_z = -0.3
		"bubbler":
			_tube(_accent, 0.05, 0.26, Vector3(0, 0, -0.02), false, true)
			var tank := _mat(_color.lerp(Color.WHITE, 0.6), 0.1)
			tank.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tank.albedo_color.a = 0.6
			tank.emission_enabled = true
			tank.emission = _color.lerp(Color.WHITE, 0.5)
			tank.emission_energy_multiplier = 0.4
			_ball(tank, Vector3(0, 0.09, 0.03), Vector3.ONE * 0.075)
			var horn := CylinderMesh.new()
			horn.top_radius = 0.085
			horn.bottom_radius = 0.04
			horn.height = 0.1
			_part(horn, _shell, Vector3(0, 0, -0.2)).rotation.x = -PI / 2
			_muzzle_z = -0.3
		_:
			_tube(_accent, 0.055, 0.4, Vector3(0, 0, 0), false, true)
			_tube(_shell, 0.07, 0.07, Vector3(0, 0, -0.15))
			_tube(_shell, 0.064, 0.03, Vector3(0, 0, 0.1))
			var nozzle := CylinderMesh.new()
			nozzle.top_radius = 0.036
			nozzle.bottom_radius = 0.046
			nozzle.height = 0.08
			_part(nozzle, _dark, Vector3(0, 0, -0.22)).rotation.x = -PI / 2
			_ball(_glow, Vector3(0, 0.065, -0.02), Vector3(0.03, 0.03, 0.07))
			_ball(_accent, Vector3(0, 0.055, -0.1), Vector3(0.018, 0.03, 0.018))
			_muzzle_z = -0.32


func _mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


## A cylinder (or capsule) lying along the barrel axis.
func _tube(mat: Material, radius: float, length: float, pos: Vector3, _wide := false, capsule := false) -> MeshInstance3D:
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
	visible = p.alive
	if p.weapon != weapon:
		set_weapon(p.weapon)
	if not p.alive:
		_last_yaw = p.yaw
		_last_pitch = p.pitch
		return
	# Sway: the gun lags slightly behind the view.
	var dy := wrapf(p.yaw - _last_yaw, -PI, PI)
	var dp: float = p.pitch - _last_pitch
	_last_yaw = p.yaw
	_last_pitch = p.pitch
	_sway = _sway.lerp(Vector2(clampf(dy * 2.5, -0.06, 0.06), clampf(dp * 2.5, -0.05, 0.05)), clampf(delta * 14.0, 0.0, 1.0))
	_sway = _sway.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))

	var speed: float = clampf(Vector2(p.velocity.x, p.velocity.z).length() / 7.5, 0.0, 1.3)
	if p.is_on_floor():
		_bob += delta * (5.0 + speed * 8.0) * (1.0 if speed > 0.05 else 0.0)
	var bob := Vector3(cos(_bob) * 0.008, -absf(sin(_bob)) * 0.012, 0.0) * speed

	var kick: float = p.recoil * p.stats.recoil_kick
	var pos := _rest + bob + Vector3(_sway.x, -_sway.y - p.land_dip * 0.05, kick * 0.06)
	var rot := Vector3(kick * 0.13 - _sway.y * 1.2, _sway.x * 1.5, _sway.x * -1.2)
	if p.reload_left > 0.0:
		var f: float = 1.0 - p.reload_left / p.stats.reload_time
		var dip := sin(f * PI)
		pos.y -= dip * 0.12
		rot.x -= dip * 0.5
		rot.z += sin(f * TAU) * 0.35
	# New weapon swings up into view.
	_swap = minf(1.0, _swap + delta * 3.5)
	if _swap < 1.0:
		var e := 1.0 - _swap
		pos.y -= e * e * 0.3
		rot.x -= e * e * 1.2
	position = pos
	rotation = rot

	_flash.visible = p.muzzle_flash > 0.0
	if _flash.visible:
		var fs: float = (0.03 + p.muzzle_flash * 0.07) * clampf(p.stats.recoil_kick, 0.8, 1.8)
		_flash.scale = Vector3(fs, fs, fs * 1.6)
