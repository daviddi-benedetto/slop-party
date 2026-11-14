extends Node3D
## The plush animal model used for players in a match, in the lobby and on the
## victory podium. Built from primitive meshes; animated procedurally.
##
## It has no _process of its own: whoever owns it calls animate() once per
## PHYSICS tick (physics interpolation then smooths it to the display rate).
##
## Kinds: 0 bear, 1 bunny, 2 cat, 3 dog, 4 fox, 5 frog  (see ui_kit.KIND_NAMES;
## ui_kit.portrait() draws the matching 2D face).
##
## Local space: feet at y = 0, facing -Z, about 1.75 m tall plus ears.

const KIND_COUNT := 6

var kind := 0
var color := Color.WHITE
var emote := ""                # "", "cheer", "sad"

var rig: Node3D                # squash / stretch / lean
var head: Node3D
var aim: Node3D                # right arm + blaster, pitches with the view
var muzzle: Node3D
var _arm_l: Node3D
var _foot_l: Node3D
var _foot_r: Node3D
var _ears: Array = []
var _eyes: Array = []
var _tail: Node3D
var _mat_body: StandardMaterial3D
var _mat_light: StandardMaterial3D
var _outline: StandardMaterial3D
var _layers := 1

var _phase := 0.0
var _t := 0.0
var _squash := 0.0
var _squash_v := 0.0
var _was_floor := true
var _blink := 2.0
var _flash := 0.0
var _pop := 1.0


func build(k: int, col: Color, layer_bits := 1, with_gun := true) -> void:
	kind = posmod(k, KIND_COUNT)
	color = col
	_layers = layer_bits
	_t = randf() * 10.0

	_outline = StandardMaterial3D.new()
	_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline.albedo_color = col.darkened(0.72)
	_outline.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline.grow = true
	_outline.grow_amount = 0.022
	_mat_body = _plush(col)
	_mat_light = _plush(col.lerp(Color(1.0, 0.97, 0.9), 0.68))
	var mat_dark := _plush(col.darkened(0.35))
	var mat_ink := _plain(Color(0.1, 0.08, 0.12), 0.25)
	var mat_white := _plain(Color(1, 1, 1), 0.3)
	var mat_pink := _plain(Color(1.0, 0.6, 0.65), 0.8)

	rig = Node3D.new()
	add_child(rig)

	# Body, belly, feet.
	_ball(rig, _mat_body, Vector3(0, 0.62, 0), Vector3(0.42, 0.5, 0.38))
	_ball(rig, _mat_light, Vector3(0, 0.58, -0.1), Vector3(0.32, 0.38, 0.31))
	_foot_l = _ball(rig, mat_dark, Vector3(-0.18, 0.1, -0.03), Vector3(0.15, 0.1, 0.2))
	_foot_r = _ball(rig, mat_dark, Vector3(0.18, 0.1, -0.03), Vector3(0.15, 0.1, 0.2))

	# Left arm swings from the shoulder.
	_arm_l = Node3D.new()
	_arm_l.position = Vector3(-0.4, 0.92, 0)
	rig.add_child(_arm_l)
	_ball(_arm_l, _mat_body, Vector3(-0.03, -0.17, 0), Vector3(0.11, 0.22, 0.11))
	_ball(_arm_l, mat_dark, Vector3(-0.04, -0.36, 0), Vector3(0.11, 0.09, 0.11))

	# Right arm + blaster pitch together.
	aim = Node3D.new()
	aim.position = Vector3(0, 0.92, 0)
	rig.add_child(aim)
	_ball(aim, _mat_body, Vector3(0.4, -0.04, -0.17), Vector3(0.11, 0.11, 0.24))
	_ball(aim, mat_dark, Vector3(0.4, -0.04, -0.38), Vector3(0.11, 0.1, 0.1))
	muzzle = Node3D.new()
	muzzle.position = Vector3(0.4, 0.04, -0.95)
	aim.add_child(muzzle)
	if with_gun:
		var gun_mat := _plain(Color(0.95, 0.93, 0.9), 0.4)
		var barrel := CapsuleMesh.new()
		barrel.radius = 0.085
		barrel.height = 0.62
		var b := _mesh(aim, barrel, gun_mat, Vector3(0.4, 0.05, -0.58))
		b.rotation.x = PI / 2
		var ring := CylinderMesh.new()
		ring.top_radius = 0.105
		ring.bottom_radius = 0.105
		ring.height = 0.1
		var rg := _mesh(aim, ring, _plain(col, 0.4), Vector3(0.4, 0.05, -0.78))
		rg.rotation.x = PI / 2
		_ball(aim, _plain(col.lerp(Color.WHITE, 0.3), 0.2), Vector3(0.4, 0.15, -0.5), Vector3(0.07, 0.07, 0.1))

	# Head.
	head = Node3D.new()
	head.position = Vector3(0, 1.36, 0)
	rig.add_child(head)
	_ball(head, _mat_body, Vector3.ZERO, Vector3(0.41, 0.37, 0.38))
	if kind == 5:
		# Frog: eyes on stalks, wide mouth, no snout.
		for sx in [-1.0, 1.0]:
			_ball(head, _mat_body, Vector3(sx * 0.2, 0.3, -0.08), Vector3(0.15, 0.15, 0.15))
			var e := _ball(head, mat_white, Vector3(sx * 0.2, 0.32, -0.16), Vector3(0.11, 0.11, 0.09), false)
			_ball(e, mat_ink, Vector3(0, 0, -0.75), Vector3(0.5, 0.5, 0.4), false)
			_eyes.append(e)
		_ball(head, _mat_light, Vector3(0, -0.1, -0.2), Vector3(0.3, 0.16, 0.2))
		_ball(head, mat_ink, Vector3(0, -0.06, -0.37), Vector3(0.2, 0.018, 0.03), false)
	else:
		_ball(head, _mat_light, Vector3(0, -0.09, -0.3), Vector3(0.17, 0.13, 0.14))
		_ball(head, mat_ink, Vector3(0, -0.04, -0.43), Vector3(0.055, 0.04, 0.035), false)
		for sx in [-1.0, 1.0]:
			var e2 := _ball(head, mat_ink, Vector3(sx * 0.16, 0.07, -0.33), Vector3(0.058, 0.07, 0.04), false)
			_ball(e2, mat_white, Vector3(-0.3, 0.35, -0.7), Vector3(0.35, 0.3, 0.3), false)
			_eyes.append(e2)
			_ball(head, mat_pink, Vector3(sx * 0.27, -0.07, -0.25), Vector3(0.07, 0.045, 0.03), false)

	# Ears and tail by species.
	for sx in [-1.0, 1.0]:
		var ear := Node3D.new()
		head.add_child(ear)
		match kind:
			0:
				ear.position = Vector3(sx * 0.29, 0.27, 0)
				_ball(ear, _mat_body, Vector3.ZERO, Vector3(0.14, 0.14, 0.09))
				_ball(ear, _mat_light, Vector3(0, 0, -0.04), Vector3(0.08, 0.08, 0.06), false)
			1:
				ear.position = Vector3(sx * 0.15, 0.3, 0)
				ear.rotation.z = -sx * 0.16
				_ball(ear, _mat_body, Vector3(0, 0.3, 0), Vector3(0.09, 0.34, 0.07))
				_ball(ear, mat_pink, Vector3(0, 0.3, -0.035), Vector3(0.05, 0.26, 0.045), false)
			2, 4:
				var big := 1.35 if kind == 4 else 1.0
				ear.position = Vector3(sx * 0.24, 0.25, 0)
				ear.rotation.z = -sx * 0.3
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.13 * big
				cone.height = 0.26 * big
				cone.radial_segments = 12
				_mesh(ear, cone, _mat_body, Vector3(0, 0.12 * big, 0))
				var tip := CylinderMesh.new()
				tip.top_radius = 0.0
				tip.bottom_radius = 0.075 * big
				tip.height = 0.16 * big
				tip.radial_segments = 10
				_mesh(ear, tip, mat_pink if kind == 2 else mat_dark, Vector3(0, 0.12 * big, -0.045), false)
			3:
				ear.position = Vector3(sx * 0.36, 0.14, 0)
				ear.rotation.z = sx * 0.25
				_ball(ear, mat_dark, Vector3(sx * 0.03, -0.2, 0), Vector3(0.1, 0.26, 0.13))
		if kind != 5:
			_ears.append(ear)
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.5, 0.34)
	rig.add_child(_tail)
	match kind:
		0, 1:
			_ball(_tail, _mat_light if kind == 1 else _mat_body, Vector3(0, 0, 0.04), Vector3(0.12, 0.12, 0.12))
		2, 3:
			_tail.rotation.x = -0.7
			_ball(_tail, _mat_body if kind == 2 else mat_dark, Vector3(0, 0, 0.22), Vector3(0.06, 0.06, 0.27))
		4:
			_tail.rotation.x = -0.5
			_ball(_tail, _mat_body, Vector3(0, 0, 0.26), Vector3(0.15, 0.15, 0.32))
			_ball(_tail, _mat_light, Vector3(0, 0, 0.5), Vector3(0.1, 0.1, 0.13))


func _plush(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.rim_enabled = true
	m.rim = 0.55
	m.rim_tint = 0.4
	m.emission_enabled = true
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.0
	m.next_pass = _outline
	return m


func _plain(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


static var _sphere: SphereMesh


func _ball(parent: Node3D, mat: Material, pos: Vector3, radii: Vector3, _outlined := true) -> MeshInstance3D:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 20
		_sphere.rings = 10
	var mi := _mesh(parent, _sphere, mat, pos)
	mi.scale = radii
	return mi


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, _outlined := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.layers = _layers
	parent.add_child(mi)
	return mi


func hit_flash() -> void:
	_flash = 1.0
	_squash_v -= 1.6


## Scale up from nothing with a bounce (joining the lobby, respawning).
func pop_in() -> void:
	_pop = 0.0


func muzzle_position() -> Vector3:
	return muzzle.global_position


## speed: 0..1+ fraction of run speed. vy: vertical velocity. pitch: view pitch.
func animate(delta: float, speed: float, on_floor: bool, vy: float, pitch: float, recoil := 0.0) -> void:
	_t += delta
	speed = clampf(speed, 0.0, 1.5)
	var run := minf(speed, 1.0)
	if speed > 0.05 and on_floor:
		_phase += delta * (5.0 + 8.0 * speed)

	# Landing squash (damped spring) + air stretch + breathing.
	if on_floor and not _was_floor:
		_squash_v -= 3.2
	_was_floor = on_floor
	_squash_v += (-_squash * 160.0 - _squash_v * 13.0) * delta
	_squash += _squash_v * delta
	var stretch := clampf(_squash, -0.35, 0.35) + sin(_t * 2.3) * 0.014
	if not on_floor:
		stretch += clampf(absf(vy) * 0.012, 0.0, 0.14)
	_pop = minf(1.0, _pop + delta * 2.2)
	var pop := 1.0 if _pop >= 1.0 else maxf(0.001, pow(2.0, -10.0 * _pop) * sin((_pop * 10.0 - 0.75) * TAU / 3.0) + 1.0)
	rig.scale = Vector3(1.0 - stretch * 0.6, 1.0 + stretch, 1.0 - stretch * 0.6) * pop

	var sw := sin(_phase) * run
	var bob := absf(sin(_phase)) * 0.06 * run
	var hop := 0.0
	var arm_x := sw * 0.9
	var aim_x := pitch + recoil * 0.3
	var head_x := pitch * 0.55
	match emote:
		"cheer":
			hop = absf(sin(_t * 6.5)) * 0.32
			arm_x = -2.7 + sin(_t * 13.0) * 0.35
			aim_x = 1.25 + sin(_t * 13.0 + 1.0) * 0.25
			head_x = 0.25
		"sad":
			head_x = -0.5
			arm_x = 0.15
			aim_x = -0.9
	rig.position.y = bob + hop
	rig.rotation.x = -0.13 * run
	rig.rotation.z = sin(_phase) * 0.05 * run
	_arm_l.rotation.x = arm_x
	aim.rotation.x = aim_x
	head.rotation.x = head_x
	head.rotation.z = sin(_phase * 0.5 + 0.5) * 0.06 * run + sin(_t * 1.3) * 0.03

	if on_floor and hop <= 0.01:
		_foot_l.position = Vector3(-0.18, 0.1 + maxf(0.0, cos(_phase)) * 0.12 * run, -0.03 - sw * 0.24)
		_foot_r.position = Vector3(0.18, 0.1 + maxf(0.0, -cos(_phase)) * 0.12 * run, -0.03 + sw * 0.24)
	else:
		_foot_l.position = Vector3(-0.2, 0.16, 0.08)
		_foot_r.position = Vector3(0.2, 0.2, -0.12)

	for i in _ears.size():
		_ears[i].rotation.x = sin(_t * 3.1 + i * 1.7) * 0.06 + clampf(vy * 0.03, -0.4, 0.4) - sw * 0.08
	_tail.rotation.y = sin(_t * 5.0) * 0.25 + sw * 0.3

	_blink -= delta
	var eye_y := 0.12 if _blink < 0.0 else 1.0
	if _blink < -0.11:
		_blink = randf_range(1.6, 4.5)
	for e in _eyes:
		e.scale.y = absf(e.scale.x) * (1.2 if kind != 5 else 1.0) * eye_y

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_mat_body.emission_energy_multiplier = _flash * 1.6
		_mat_light.emission_energy_multiplier = _flash * 1.6
