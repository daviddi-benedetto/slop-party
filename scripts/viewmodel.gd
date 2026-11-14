extends Node3D
## First-person toy blaster. A child of one player's Camera3D, drawn only on
## that player's private viewmodel layer. Animated per rendered frame by
## game.gd calling update(): walk bob, look sway, recoil, reload spin, landing
## dip and muzzle flash.

var _flash: MeshInstance3D
var _last_yaw := 0.0
var _last_pitch := 0.0
var _sway := Vector2.ZERO
var _bob := 0.0
var _rest := Vector3(0.27, -0.25, -0.58)


func build(color: Color, layer_bit: int) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var shell := _mat(Color(0.93, 0.91, 0.88), 0.65)
	var accent := _mat(color, 0.35)
	var dark := _mat(Color(0.2, 0.17, 0.27), 0.5)
	var plush := _mat(color.lerp(Color(1, 0.97, 0.9), 0.3), 0.95)
	plush.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	plush.rim_enabled = true
	plush.rim = 0.5
	var glow := _mat(color.lerp(Color.WHITE, 0.4), 0.2)
	glow.emission_enabled = true
	glow.emission = color.lerp(Color.WHITE, 0.3)
	glow.emission_energy_multiplier = 1.4

	var body := CapsuleMesh.new()
	body.radius = 0.055
	body.height = 0.4
	_part(body, shell, Vector3(0, 0, 0), layer_bit).rotation.x = PI / 2
	var ring := CylinderMesh.new()
	ring.top_radius = 0.07
	ring.bottom_radius = 0.07
	ring.height = 0.07
	_part(ring, accent, Vector3(0, 0, -0.15), layer_bit).rotation.x = PI / 2
	var ring2 := CylinderMesh.new()
	ring2.top_radius = 0.064
	ring2.bottom_radius = 0.064
	ring2.height = 0.03
	_part(ring2, accent, Vector3(0, 0, 0.1), layer_bit).rotation.x = PI / 2
	var nozzle := CylinderMesh.new()
	nozzle.top_radius = 0.036
	nozzle.bottom_radius = 0.046
	nozzle.height = 0.08
	_part(nozzle, dark, Vector3(0, 0, -0.22), layer_bit).rotation.x = -PI / 2
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	_part(sphere, glow, Vector3(0, 0.07, 0.0), layer_bit).scale = Vector3(0.045, 0.045, 0.09)
	_part(sphere, accent, Vector3(0, 0.055, -0.1), layer_bit).scale = Vector3(0.018, 0.03, 0.018)
	var grip := CapsuleMesh.new()
	grip.radius = 0.034
	grip.height = 0.17
	_part(grip, dark, Vector3(0, -0.1, 0.1), layer_bit).rotation.x = 0.3
	# The paw holding it.
	_part(sphere, plush, Vector3(0.005, -0.11, 0.11), layer_bit).scale = Vector3(0.075, 0.07, 0.08)
	_part(sphere, plush, Vector3(0.04, -0.22, 0.3), layer_bit).scale = Vector3(0.065, 0.065, 0.22)

	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.albedo_color = Color(1.0, 0.95, 0.6, 0.9)
	_flash = _part(sphere, fmat, Vector3(0, 0, -0.32), layer_bit)
	_flash.visible = false
	position = _rest


func _mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


func _part(mesh: Mesh, mat: Material, pos: Vector3, layer_bit: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.layers = layer_bit
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mi)
	return mi


func update(delta: float, p) -> void:
	visible = p.alive
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

	var pos := _rest + bob + Vector3(_sway.x, -_sway.y - p.land_dip * 0.05, p.recoil * 0.07)
	var rot := Vector3(p.recoil * 0.16 - _sway.y * 1.2, _sway.x * 1.5, _sway.x * -1.2)
	if p.reload_left > 0.0:
		var f: float = 1.0 - p.reload_left / p.stats.reload_time
		var dip := sin(f * PI)
		pos.y -= dip * 0.12
		rot.x -= dip * 0.5
		rot.z += smoothstep(0.15, 0.85, f) * TAU
	position = pos
	rotation = rot

	_flash.visible = p.muzzle_flash > 0.0
	if _flash.visible:
		var fs: float = 0.03 + p.muzzle_flash * 0.07
		_flash.scale = Vector3(fs, fs, fs * 1.6)
