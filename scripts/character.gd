extends Node3D
## The plush animal model used for players in a match, in the lobby and on the
## victory podium. The body is one seamless generated mesh (plush.gd); eyes,
## nose, limbs, tail and accessories are separate parts animated procedurally
## (squash and stretch, waddle, stepping feet, paws that hold the weapon).
##
## It has no _process of its own: whoever owns it calls animate() once per
## PHYSICS tick (physics interpolation then smooths it to the display rate).
##
## Selectable kinds: Bunny, Kitty, Pup, Bear, Fox, Panda and Duck (plush.gd
## NAMES / SPEC; ui_kit.KIND_NAMES; ui_kit.portrait() draws the 2D face).
## Customisation: a hat (ui_kit.HAT_NAMES), a face accessory
## (ui_kit.FACE_NAMES) and a back item, built by _build_hat() / _build_face() /
## _build_back(). To add one, append its name in ui_kit.gd and a branch in the
## matching function. The player's colour is the bandana round the neck.
##
## Local space: feet at y = 0, facing -Z, about 1.72 m tall plus ears.

const Viewmodel = preload("res://scripts/viewmodel.gd")
const Weapons = preload("res://scripts/weapons.gd")
const Models = preload("res://scripts/models.gd")
const Plush = preload("res://scripts/plush.gd")
const KIND_COUNT := 7

var kind := 0
var color := Color.WHITE
var emote := ""                # "", "cheer", "sad"
var crouch := 0.0              # 0..1, set by player.gd
# Set by player.gd every frame (body language and expressions):
var turn_rate := 0.0           # yaw speed, rad/s (lean into turns)
var wall_side := 0.0           # -1..1 while wall running (body tilts to the wall)
var sliding := false           # slide pose: low, leaning back, feet first
var hurt := 0.0                # 0..1 just hit: squint, mouth open
var low_health := false        # wide, worried eyes
var happy := 0.0               # 0..1 after a KO: smiling eyes
var _hit_dir := Vector3.ZERO   # rig-space direction of the last hit (snap away)
var _hit_t := 0.0
var _mouth: MeshInstance3D
var _eye_base: Array = []      # [scale, position] of each eye as built
var jetting := false
var _jetpack: Node3D
var _jet_flames: Array = []
var hat := 0
var face := 0
var back := 0                  # back accessory (ui_kit.BACK_NAMES)
var _gun_scale := 1.2
var _with_gun := true
var _back_node: Node3D
var taunt := -1                # player.TAUNTS index while taunting, else -1
var _swing_t := 9.0            # seconds since swing() (melee animation)
var _swing_weapon := false
var _knife: Node3D               # third-person melee knife (shown while slashing)
var _swing_n := 0
var _grip_r: Node3D
var _grip_l: Node3D
var _gun_rest := Vector3.ZERO

var rig: Node3D                # squash / stretch / lean
var head: Node3D
var aim: Node3D                # the weapon pivot, pitches with the view
var muzzle: Node3D
var _gun: Node3D
var _weapon := -1
var _arm_l: Dictionary         # limbs: see _limb()
var _arm_r: Dictionary
var _leg_l: Dictionary
var _leg_r: Dictionary
var _foot_l: Node3D
var _foot_r: Node3D
var _eyes: Array = []
var _tail: Node3D
var _mat_body: StandardMaterial3D
var _mat_light: StandardMaterial3D
var _mat_paw: StandardMaterial3D
var _layers := 1

var _phase := 0.0
var _t := 0.0
var _squash := 0.0
var _squash_v := 0.0
var _was_floor := true
var _blink := 2.0
var _flash := 0.0
var _pop := 1.0
var _eye_pos := Vector3(0.16, 0.07, -0.33)   # right eye, in head space
var _accent: StandardMaterial3D


func build(k: int, col: Color, layer_bits := 1, with_gun := true, hat_id := 0, face_id := 0, back_id := 0) -> void:
	kind = posmod(k, KIND_COUNT)
	color = col
	hat = hat_id
	face = face_id
	back = back_id
	_with_gun = with_gun
	_layers = layer_bits
	_t = randf() * 10.0
	var spec: Dictionary = Plush.SPEC[kind]

	rig = Node3D.new()
	add_child(rig)
	# One seamless plush body (head, tummy, ears, snout) painted with patches.
	_mat_body = _plush(Color.WHITE, true, true)
	_mesh(rig, Plush.body(kind), _mat_body, Vector3.ZERO)
	_tail = Node3D.new()
	_tail.position = Plush.TAIL_ROOT
	rig.add_child(_tail)
	_mesh(_tail, Plush.tail(kind), _mat_body, Vector3.ZERO)
	_mat_light = _plush(spec.limb)
	_mat_paw = _plush(spec.paw)

	# Face: glossy button eyes, a nose, blush, all sitting on the surface.
	head = Node3D.new()
	head.position = Plush.HEAD
	rig.add_child(head)
	var ink := _plain(Color(0.06, 0.05, 0.07), 0.12)
	ink.metallic_specular = 0.9
	var shine := _plain(Color(1, 1, 1), 0.3)
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ex: float = spec.eye[0]
	var ey: float = spec.eye[1]
	for sx in [-1.0, 1.0]:
		var z := Plush.surface_z(kind, sx * ex, ey)
		var e := _ball(head, ink, Vector3(sx * ex, ey, z - 0.01) - Plush.HEAD, Vector3(0.062, 0.078, 0.04))
		e.rotation.y = -sx * 0.35
		_ball(e, shine, Vector3(-0.32, 0.38, -0.75), Vector3(0.34, 0.3, 0.3))
		_ball(e, shine, Vector3(0.3, -0.35, -0.8), Vector3(0.15, 0.13, 0.15))
		_eyes.append(e)
		if kind != 5:
			var bz := Plush.surface_z(kind, sx * 0.29, 1.2)
			var blush := _plain(Color(1.0, 0.55, 0.6, 0.55), 1.0)
			blush.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_ball(head, blush, Vector3(sx * 0.29, 1.2, bz - 0.004) - Plush.HEAD, Vector3(0.07, 0.04, 0.02)).rotation.y = -sx * 0.6
	_eye_pos = Vector3(ex, ey, Plush.surface_z(kind, ex, ey)) - Plush.HEAD
	if not spec.nose.is_empty():
		var ny: float = spec.nose[0]
		var nz := Plush.surface_z(kind, 0.0, ny)
		var nose := _plain(spec.nose[1], 0.2)
		_ball(head, nose, Vector3(0, ny, nz - 0.004) - Plush.HEAD, Vector3(0.055, 0.038, 0.035))
		# A little smile under the nose.
		var mz := Plush.surface_z(kind, 0.0, ny - 0.07)
		var mouth_mat := _plain(Color(0.35, 0.05, 0.08), 0.4)
		_mouth = _ball(head, mouth_mat, Vector3(0, ny - 0.1, mz - 0.006) - Plush.HEAD, Vector3(0.045, 0.02, 0.02))
		_mouth.visible = false
		for sx in [-1.0, 1.0]:
			_ball(head, ink, Vector3(sx * 0.03, ny - 0.07, mz - 0.008) - Plush.HEAD, Vector3(0.035, 0.009, 0.01)).rotation.z = sx * 0.45

	# Stubby limbs: a capsule from the shoulder / hip to a round paw.
	_arm_l = _limb(Vector3(-0.31, 0.9, -0.02), 0.095, _mat_light)
	_arm_r = _limb(Vector3(0.31, 0.9, -0.02), 0.095, _mat_light)
	_leg_l = _limb(Vector3(-0.16, 0.3, 0.0), 0.1, _mat_light)
	_leg_r = _limb(Vector3(0.16, 0.3, 0.0), 0.1, _mat_light)
	_foot_l = _ball(rig, _mat_paw, Vector3(-0.17, 0.09, -0.05), Vector3(0.13, 0.085, 0.17))
	_foot_r = _ball(rig, _mat_paw, Vector3(0.17, 0.09, -0.05), Vector3(0.13, 0.085, 0.17))
	for limb in [_arm_l, _arm_r]:
		limb.paw = _ball(limb.root, _mat_paw, Vector3.ZERO, Vector3.ONE * 0.105)

	# The weapon pitches with the view; both paws hold it.
	aim = Node3D.new()
	aim.position = Vector3(0, 0.92, 0)
	rig.add_child(aim)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0.12, 0.04, -1.0)
	aim.add_child(muzzle)
	_gun_scale = 1.2
	if with_gun:
		_gun = Node3D.new()
		_gun.position = Vector3(0.16, -0.06, -0.46)
		_gun_rest = _gun.position
		aim.add_child(_gun)
		_grip_r = Node3D.new()
		_gun.add_child(_grip_r)
		_grip_l = Node3D.new()
		_gun.add_child(_grip_l)
		set_weapon(0)

	var scarf_h := _plush(Color.from_hsv(fmod(col.h + 0.45, 1.0), 0.55, 1.0), false)
	scarf_h.emission = scarf_h.albedo_color
	scarf_h.emission_energy_multiplier = 0.25
	_accent = scarf_h
	_build_scarf(col)
	_build_hat()
	_build_face()
	_build_back()


## A limb: {root (at the joint), seg (the capsule), paw}. _reach() aims it.
func _limb(at: Vector3, r: float, mat: Material) -> Dictionary:
	var root := Node3D.new()
	root.position = at
	rig.add_child(root)
	var cap := CapsuleMesh.new()
	cap.radius = r
	cap.height = 1.0
	cap.radial_segments = 12
	cap.rings = 4
	var seg := _mesh(root, cap, mat, Vector3.ZERO)
	return {"root": root, "seg": seg, "paw": null, "at": at, "r": r}


## Points a limb at `to` (rig space) and stretches it to reach.
func _reach(limb: Dictionary, to: Vector3, max_len := 0.62) -> void:
	var root: Node3D = limb.root
	var d: Vector3 = to - root.position
	var l := clampf(d.length(), 0.12, max_len)
	var down := -d.normalized() if d.length() > 0.001 else Vector3.UP
	var side := Vector3.RIGHT if absf(down.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var z := side.cross(down).normalized()
	var x := down.cross(z).normalized()
	root.basis = Basis(x, down, z)
	var seg: MeshInstance3D = limb.seg
	var r: float = limb.r
	seg.position = Vector3(0, -l * 0.5, 0)
	seg.scale = Vector3(1.0, maxf(l + r * 0.8, r * 2.0), 1.0)
	if limb.paw != null:
		limb.paw.position = Vector3(0, -l, 0)


## A bandana in the player's colour round the neck: who is who, without
## dyeing the whole animal.
func _build_scarf(col: Color) -> void:
	var y := 0.95
	var rx := 0.6
	while rx > 0.05 and Plush.sdf(kind, Vector3(rx, y, 0.0)) > 0.0:
		rx -= 0.01
	var rz := 0.6
	while rz > 0.05 and Plush.sdf(kind, Vector3(0.0, y, -rz)) > 0.0:
		rz -= 0.01
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = col
	cloth.roughness = 0.85
	cloth.emission_enabled = true
	cloth.emission = col
	cloth.emission_energy_multiplier = 0.35
	cloth.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var ring := TorusMesh.new()
	ring.inner_radius = 0.9
	ring.outer_radius = 1.2
	ring.rings = 28
	ring.ring_segments = 8
	var mi := _mesh(rig, ring, cloth, Vector3(0, y, 0))
	mi.scale = Vector3(rx, 0.32, rz)
	var knot := PrismMesh.new()
	knot.size = Vector3(0.26, 0.24, 0.05)
	var tail := _mesh(rig, knot, cloth, Vector3(0.08, y - 0.12, -rz - 0.04))
	tail.rotation = Vector3(-0.25, 0, PI + 0.2)


func _cyl(parent: Node3D, mat: Material, top: float, bottom: float, height: float, pos: Vector3, sides := 20) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = sides
	return _mesh(parent, m, mat, pos)


func _build_hat() -> void:
	var gold := _plain(Color(1.0, 0.78, 0.2), 0.25)
	gold.metallic = 0.7
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.65, 0.1)
	gold.emission_energy_multiplier = 0.6
	var dark := _plain(Color(0.07, 0.07, 0.1), 0.5)
	var cream := _plain(Color(0.95, 0.92, 0.85), 0.6)
	match hat:
		1:  # cap
			_ball(head, _accent, Vector3(0, 0.2, 0.0), Vector3(0.43, 0.22, 0.41))
			var brim := BoxMesh.new()
			brim.size = Vector3(0.5, 0.04, 0.3)
			_mesh(head, brim, _accent, Vector3(0, 0.2, -0.46)).rotation.x = -0.15
		2:  # crown
			_cyl(head, gold, 0.21, 0.19, 0.1, Vector3(0, 0.4, 0))
			for i in 5:
				var a := TAU * i / 5.0
				_cyl(head, gold, 0.0, 0.06, 0.16, Vector3(cos(a) * 0.17, 0.52, sin(a) * 0.17), 8)
		3:  # top hat
			_cyl(head, dark, 0.34, 0.34, 0.035, Vector3(0, 0.36, 0))
			_cyl(head, dark, 0.2, 0.21, 0.34, Vector3(0, 0.54, 0))
			_cyl(head, _accent, 0.215, 0.215, 0.07, Vector3(0, 0.42, 0))
		4:  # party hat
			_cyl(head, _accent, 0.0, 0.17, 0.42, Vector3(0, 0.56, 0))
			_ball(head, gold, Vector3(0, 0.78, 0), Vector3.ONE * 0.05)
		5:  # horns
			for sx in [-1.0, 1.0]:
				var horn := _cyl(head, cream, 0.0, 0.07, 0.3, Vector3(sx * 0.24, 0.42, 0), 10)
				horn.rotation.z = -sx * 0.5
		6:  # halo
			var torus := TorusMesh.new()
			torus.inner_radius = 0.19
			torus.outer_radius = 0.25
			torus.rings = 24
			torus.ring_segments = 8
			var glow := _plain(Color(1.0, 0.9, 0.4), 0.3)
			glow.emission_enabled = true
			glow.emission = Color(1.0, 0.85, 0.3)
			glow.emission_energy_multiplier = 3.0
			_mesh(head, torus, glow, Vector3(0, 0.62, 0))
		7:  # headphones
			var band := TorusMesh.new()
			band.inner_radius = 0.4
			band.outer_radius = 0.45
			band.rings = 24
			band.ring_segments = 8
			var b := _mesh(head, band, dark, Vector3(0, 0.02, 0))
			b.rotation.x = PI / 2
			b.scale = Vector3(1.0, 1.0, 0.95)
			for sx in [-1.0, 1.0]:
				_ball(head, _accent, Vector3(sx * 0.43, 0.0, 0), Vector3(0.07, 0.13, 0.13))
		8:  # bow
			for sx in [-1.0, 1.0]:
				_ball(head, _accent, Vector3(0.2 + sx * 0.1, 0.36, -0.05), Vector3(0.1, 0.075, 0.05)).rotation.z = sx * 0.4
			_ball(head, gold, Vector3(0.2, 0.36, -0.06), Vector3.ONE * 0.04)
		9:  # antenna
			_cyl(head, dark, 0.012, 0.012, 0.34, Vector3(0, 0.52, 0), 6)
			var bulb := _plain(color, 0.3)
			bulb.emission_enabled = true
			bulb.emission = color
			bulb.emission_energy_multiplier = 3.5
			_ball(head, bulb, Vector3(0, 0.72, 0), Vector3.ONE * 0.06)
		10:  # mohawk
			for i in 5:
				var z := -0.24 + i * 0.12
				_cyl(head, _accent, 0.0, 0.06, 0.22 - absf(i - 2) * 0.03, Vector3(0, 0.42 - absf(i - 2) * 0.03, z), 8)
		11:  # cowboy
			var leather := _plain(Color(0.45, 0.28, 0.14), 0.7)
			_cyl(head, leather, 0.62, 0.66, 0.03, Vector3(0, 0.3, 0), 24)
			_cyl(head, leather, 0.24, 0.3, 0.26, Vector3(0, 0.44, 0), 20)
			_cyl(head, _accent, 0.305, 0.305, 0.05, Vector3(0, 0.35, 0), 20)
		12:  # wizard
			var cloth := _plain(Color(0.25, 0.2, 0.6), 0.7)
			_cyl(head, cloth, 0.5, 0.55, 0.03, Vector3(0, 0.3, 0), 24)
			_cyl(head, cloth, 0.0, 0.3, 0.7, Vector3(0, 0.66, 0.04), 20).rotation.x = 0.15
			_ball(head, gold, Vector3(0, 0.5, -0.27), Vector3.ONE * 0.05)
		13:  # chef
			_cyl(head, cream, 0.3, 0.3, 0.22, Vector3(0, 0.42, 0), 20)
			_ball(head, cream, Vector3(0, 0.62, 0), Vector3(0.4, 0.2, 0.4))
		14:  # viking
			var steel := _plain(Color(0.6, 0.62, 0.66), 0.3)
			steel.metallic = 0.8
			_ball(head, steel, Vector3(0, 0.22, 0), Vector3(0.42, 0.24, 0.4))
			for sx in [-1.0, 1.0]:
				_cyl(head, cream, 0.0, 0.07, 0.34, Vector3(sx * 0.42, 0.42, 0), 10).rotation.z = -sx * 0.7
		15:  # propeller cap
			_ball(head, _accent, Vector3(0, 0.2, 0.0), Vector3(0.42, 0.2, 0.4))
			_cyl(head, dark, 0.015, 0.015, 0.14, Vector3(0, 0.46, 0), 6)
			var blade := BoxMesh.new()
			blade.size = Vector3(0.5, 0.015, 0.08)
			_mesh(head, blade, gold, Vector3(0, 0.53, 0)).rotation.y = 0.5


func _build_face() -> void:
	var dark := _plain(Color(0.06, 0.06, 0.09), 0.35)
	var e := _eye_pos
	match face:
		1:  # angry brows
			for sx in [-1.0, 1.0]:
				var brow := BoxMesh.new()
				brow.size = Vector3(0.14, 0.035, 0.04)
				_mesh(head, brow, dark, Vector3(sx * e.x, e.y + 0.1, e.z - 0.03)).rotation.z = sx * 0.45
		2:  # shades
			var bar := BoxMesh.new()
			bar.size = Vector3(e.x * 2.0 + 0.2, 0.11, 0.06)
			_mesh(head, bar, dark, Vector3(0, e.y, e.z - 0.04))
			var shine := _plain(Color(0.3, 0.8, 1.0), 0.2)
			shine.emission_enabled = true
			shine.emission = Color(0.2, 0.7, 1.0)
			shine.emission_energy_multiplier = 1.5
			var glint := BoxMesh.new()
			glint.size = Vector3(e.x * 2.0 + 0.16, 0.02, 0.065)
			_mesh(head, glint, shine, Vector3(0, e.y + 0.025, e.z - 0.04))
		3:  # eye patch
			_ball(head, dark, Vector3(-e.x, e.y, e.z - 0.02), Vector3(0.09, 0.09, 0.04))
			var strap := BoxMesh.new()
			strap.size = Vector3(0.6, 0.025, 0.02)
			_mesh(head, strap, dark, Vector3(-0.05, e.y + 0.07, e.z + 0.02)).rotation.z = 0.25
		4:  # sleepy lids
			for sx in [-1.0, 1.0]:
				_ball(head, _mat_body, Vector3(sx * e.x, e.y + 0.045, e.z - 0.005), Vector3(0.075, 0.05, 0.05))
		5:  # monocle
			var rim := TorusMesh.new()
			rim.inner_radius = 0.075
			rim.outer_radius = 0.095
			rim.rings = 20
			rim.ring_segments = 6
			var gold := _plain(Color(1.0, 0.8, 0.25), 0.25)
			gold.metallic = 0.7
			_mesh(head, rim, gold, Vector3(e.x, e.y, e.z - 0.04)).rotation.x = PI / 2
		6:  # mustache
			for sx in [-1.0, 1.0]:
				_ball(head, dark, Vector3(sx * 0.075, -0.1, -0.44), Vector3(0.085, 0.03, 0.03)).rotation.z = -sx * 0.3


## Two fuel canisters on the back with flame jets (visible while flying).
func set_jetpack(on: bool) -> void:
	if on == (_jetpack != null):
		return
	if not on:
		_jetpack.queue_free()
		_jetpack = null
		_jet_flames.clear()
		return
	_jetpack = Node3D.new()
	_jetpack.position = Vector3(0, 0.85, 0.36)
	rig.add_child(_jetpack)
	var metal := _plain(Color(0.55, 0.57, 0.62), 0.35)
	metal.metallic = 0.7
	var can := CapsuleMesh.new()
	can.radius = 0.11
	can.height = 0.55
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.albedo_color = Color(1.4, 0.6, 0.15, 0.8)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.09
	cone.bottom_radius = 0.0
	cone.height = 0.6
	for sx in [-0.14, 0.14]:
		_mesh(_jetpack, can, metal, Vector3(sx, 0, 0))
		var f := _mesh(_jetpack, cone, flame_mat, Vector3(sx, -0.55, 0))
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.visible = false
		_jet_flames.append(f)
	_mesh(_jetpack, _sphere, _plain(color, 0.4), Vector3(0, 0.05, 0.06)).scale = Vector3(0.12, 0.2, 0.06)


## Third-person gun: a simple barrel sized per weapon ("tp" in weapons.gd).
func set_weapon(id: int) -> void:
	if _gun == null or id == _weapon:
		return
	_weapon = id
	for c in _gun.get_children():
		if c != _grip_r and c != _grip_l:
			c.queue_free()
	# The same model as the first-person weapon, sized for the character.
	var model = Viewmodel.new()
	_gun.add_child(model)
	model.build(color, _layers, id, false)
	model.position = Vector3(0, -0.02, 0.08)
	model.scale = Vector3.ONE * _gun_scale
	muzzle.position = _gun.position + Vector3(0, -0.02, 0.08) + model.muzzle_local() * _gun_scale
	# Where the hands go (arm IK): both on a long gun, one on a blade.
	if _grip_r != null:
		_grip_r.position = model.position + model.grip_r * _gun_scale
		_grip_l.position = model.position + model.grip_l * _gun_scale
		_grip_l.visible = model.two_handed


## Soft felt with a fuzzy shell and a thin outline of a darker shade.
## vcol: the colour comes from the mesh's vertex colours (the plush bodies).
func _plush(col: Color, furry := true, vcol := false) -> StandardMaterial3D:
	var outline := StandardMaterial3D.new()
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = 0.016
	outline.albedo_color = Color(0.32, 0.27, 0.3) if vcol else col.darkened(0.68)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.rim_enabled = true
	m.rim = 0.5
	m.rim_tint = 0.5
	m.emission_enabled = true
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.0
	# Fine felt bumps so the plush catches light like fabric.
	m.normal_enabled = true
	m.normal_texture = _felt()
	m.normal_scale = 0.4
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 5.0
	if vcol:
		for x in [m, outline]:
			x.vertex_color_use_as_albedo = true
			x.vertex_color_is_srgb = true
	if not furry:
		m.next_pass = outline
		return m
	# A fuzzy shell over the surface, then the outline: plush fur.
	var fur := StandardMaterial3D.new()
	fur.albedo_color = col.lerp(Color.WHITE, 0.06)
	fur.albedo_texture = _fuzz()
	fur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fur.alpha_scissor_threshold = 0.5
	fur.roughness = 1.0
	fur.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	fur.grow = true
	fur.grow_amount = 0.012
	fur.uv1_triplanar = true
	fur.uv1_scale = Vector3.ONE * 7.0
	if vcol:
		fur.vertex_color_use_as_albedo = true
		fur.vertex_color_is_srgb = true
	fur.next_pass = outline
	m.next_pass = fur
	return m


static var _fuzz_tex: ImageTexture


## Speckled alpha texture: the tips of the fur shell.
static func _fuzz() -> ImageTexture:
	if _fuzz_tex == null:
		var img := Image.create(96, 96, true, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for y in 96:
			for x in 96:
				var on := rng.randf() < 0.3
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if on else 0.0))
		img.generate_mipmaps()
		_fuzz_tex = ImageTexture.create_from_image(img)
	return _fuzz_tex


func _plain(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


static var _sphere: SphereMesh
static var _felt_tex: NoiseTexture2D


static func _felt() -> NoiseTexture2D:
	if _felt_tex == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.09
		_felt_tex = NoiseTexture2D.new()
		_felt_tex.noise = n
		_felt_tex.width = 256
		_felt_tex.height = 256
		_felt_tex.seamless = true
		_felt_tex.as_normal_map = true
		_felt_tex.bump_strength = 5.0
		_felt_tex.generate_mipmaps = true
	return _felt_tex


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


## Start the melee animation (player._melee_start).
func swing(with_weapon: bool) -> void:
	_swing_t = 0.0
	_swing_weapon = with_weapon
	_swing_n += 1


## The knife in the right paw at `at` (rig space), blade tilting through the
## slash as f goes 0..1.
func _show_knife(at: Vector3, f: float) -> void:
	if _knife == null:
		_knife = Node3D.new()
		rig.add_child(_knife)
		var path := "medieval/Knife"
		var bb: AABB = Models.bounds(path)
		var k := 0.42 / bb.size.y
		var grip := Vector3(bb.get_center().x, bb.position.y + bb.size.y * 0.15, bb.get_center().z)
		for part in Models.parts(path):
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.transform = Transform3D(Basis.from_scale(Vector3.ONE * k), -grip * k) * part[1]
			_knife.add_child(mi)
			Models.toy_node(mi)
	_knife.visible = true
	_knife.position = at
	# Blade up and back on the wind-up, forward and down through the cut.
	_knife.rotation = Vector3(lerpf(0.6, -1.9, smoothstep(0.15, 0.5, f)), 0.0, lerpf(-0.5, 0.7, smoothstep(0.2, 0.5, f)))


func hit_flash(from := Vector3.ZERO) -> void:
	_flash = 1.0
	_squash_v -= 1.6
	if from != Vector3.ZERO and rig != null:
		# The body snaps away from where the hit came from.
		_hit_dir = (rig.global_transform.basis.inverse() * (global_position - from)).normalized()
		_hit_t = 1.0


## Scale up from nothing with a bounce (joining the lobby, respawning).
func pop_in() -> void:
	_pop = 0.0


func muzzle_position() -> Vector3:
	return muzzle.global_position


## speed: 0..1+ fraction of run speed. vy: vertical velocity. pitch: view pitch.
## strafe: -1..1 sideways speed (leans the body into the turn).
func animate(delta: float, speed: float, on_floor: bool, vy: float, pitch: float, recoil := 0.0, strafe := 0.0) -> void:
	_t += delta
	_swing_t += delta
	speed = clampf(speed, 0.0, 1.5)
	var run := minf(speed, 1.0)
	if speed > 0.05 and on_floor:
		_phase += delta * (6.0 + 9.0 * speed)

	# Landing squash (damped spring) + air stretch + breathing.
	if on_floor and not _was_floor:
		_squash_v -= 3.2
	_was_floor = on_floor
	_squash_v += (-_squash * 160.0 - _squash_v * 13.0) * delta
	_squash += _squash_v * delta
	var stretch := clampf(_squash, -0.35, 0.35) + sin(_t * 2.3) * 0.014
	if not on_floor:
		stretch += clampf(absf(vy) * 0.012, 0.0, 0.12)
	_pop = minf(1.0, _pop + delta * 2.2)
	var pop := 1.0 if _pop >= 1.0 else maxf(0.001, pow(2.0, -10.0 * _pop) * sin((_pop * 10.0 - 0.75) * TAU / 3.0) + 1.0)
	var low := 1.0 - crouch * 0.22
	rig.scale = Vector3(1.0 - stretch * 0.5 + crouch * 0.06, (1.0 + stretch) * low, 1.0 - stretch * 0.5 + crouch * 0.06) * pop

	var sw := sin(_phase) * run
	var hop := 0.0
	var lean := -0.12 * run
	var roll := sin(_phase) * 0.07 * run - strafe * 0.14
	var yaw := 0.0
	# Where the paws go (rig space); null = hold the weapon.
	var paw_l = null
	var paw_r = null
	var sh_l: Vector3 = _arm_l.at
	var sh_r: Vector3 = _arm_r.at
	var busy := taunt >= 0 or emote != "" or (_swing_t < 0.45 and not _swing_weapon)
	if _gun != null:
		_gun.visible = taunt < 0 and emote == ""
		var swing := sin(clampf(_swing_t / 0.36, 0.0, 1.0) * PI)
		var side := 1.0 if _swing_n % 2 == 0 else -1.0
		if _swing_weapon and _swing_t < 0.45:
			_gun.rotation = Vector3(-1.3 * swing, side * 0.5 * swing, side * 0.7 * swing)
			_gun.position = _gun_rest + Vector3(0, 0.12 * swing, -0.22 * swing)
		else:
			_gun.rotation = Vector3.ZERO
			_gun.position = _gun_rest + Vector3(0, 0, recoil * 0.05)
	if not _with_gun or _gun == null:
		busy = true
	if taunt >= 0:
		match taunt:
			0:  # wave
				paw_r = sh_r + Vector3(0.18 + sin(_t * 12.0) * 0.12, 0.42, -0.05)
				paw_l = sh_l + Vector3(0.0, -0.4, 0.0)
				roll = sin(_t * 6.0) * 0.08
			1:  # spin dance
				yaw = _t * 7.0
				hop = absf(sin(_t * 8.0)) * 0.22
				paw_l = sh_l + Vector3(-0.2, 0.3 + sin(_t * 8.0) * 0.15, 0)
				paw_r = sh_r + Vector3(0.2, 0.3 - sin(_t * 8.0) * 0.15, 0)
			2:  # no-no wiggle
				yaw = sin(_t * 9.0) * 0.45
				paw_l = sh_l + Vector3(0.12, -0.25, -0.2)
				paw_r = sh_r + Vector3(-0.12, -0.25, -0.2)
			_:  # flex
				hop = absf(sin(_t * 5.0)) * 0.08
				var f := sin(_t * 6.0) * 0.06
				paw_l = sh_l + Vector3(-0.25, 0.25 + f, 0)
				paw_r = sh_r + Vector3(0.25, 0.25 - f, 0)
				roll = sin(_t * 5.0) * 0.06
		pitch = 0.0
	elif emote == "cheer":
		hop = absf(sin(_t * 6.5)) * 0.3
		paw_l = sh_l + Vector3(-0.15, 0.45 + sin(_t * 13.0) * 0.08, 0)
		paw_r = sh_r + Vector3(0.15, 0.45 - sin(_t * 13.0) * 0.08, 0)
		pitch = 0.2
	elif emote == "sad":
		lean = 0.25
		paw_l = sh_l + Vector3(0.05, -0.38, 0.05)
		paw_r = sh_r + Vector3(-0.05, -0.38, 0.05)
		pitch = -0.4
	elif _swing_t < 0.5 and not _swing_weapon:
		# A knife slash with the right paw: wind up high, whip it down
		# across the body, recover.
		var f := clampf(_swing_t / 0.5, 0.0, 1.0)
		var up := sh_r + Vector3(0.12, 0.38, 0.12)
		var down := sh_r + Vector3(-0.5, -0.18, -0.45)
		var rest := sh_r + Vector3(0.0, -0.3, -0.1)
		if f < 0.25:
			paw_r = rest.lerp(up, 1.0 - pow(1.0 - f / 0.25, 2.0))
		elif f < 0.45:
			var u := (f - 0.25) / 0.2
			paw_r = up.lerp(down, u * u * u)
		else:
			paw_r = down.lerp(rest, smoothstep(0.0, 1.0, (f - 0.45) / 0.55))
		paw_l = sh_l + Vector3(0.1, -0.1, -0.2)
		var cut := sin(clampf((f - 0.2) / 0.35, 0.0, 1.0) * PI)
		roll += -0.18 * cut
		lean += 0.12 * cut
		_show_knife(paw_r, f)
	elif busy:
		# Arms swing as it walks.
		paw_l = sh_l + Vector3(-0.06, -0.36, -sw * 0.22)
		paw_r = sh_r + Vector3(0.06, -0.36, sw * 0.22)
	if _flash > 0.6:
		lean += 0.15
	# Body language: lean into turns, tilt to the wall on a wall run, sit
	# back low in a slide, snap away from a hit, fidget when standing still.
	var slide_drop := 0.0
	if taunt < 0 and emote == "":
		roll += clampf(-turn_rate * 0.045 * maxf(run, 0.3), -0.28, 0.28)
		roll += wall_side * 0.42
		if sliding:
			lean += 0.38
			slide_drop = 0.16
		_hit_t = maxf(0.0, _hit_t - delta * 5.0)
		if _hit_t > 0.0:
			var snap := _hit_t * _hit_t
			lean += -_hit_dir.z * 0.35 * snap
			roll += _hit_dir.x * 0.35 * snap
		if run < 0.05 and on_floor and not busy:
			var idle := clampf(_t * 0.5, 0.0, 1.0)
			yaw += sin(_t * 0.6) * 0.18 * idle + sin(_t * 1.7) * 0.04
			roll += sin(_t * 0.43 + 1.0) * 0.05 * idle
	rig.position.y = hop - crouch * 0.12 - slide_drop + absf(sin(_phase)) * 0.05 * run
	rig.rotation = Vector3(lean - crouch * 0.1, yaw, roll)
	aim.rotation.x = pitch + recoil * 0.2
	aim.position.y = 0.92 - crouch * 0.05

	# Paws: on the weapon's grips, or wherever the pose wants them.
	if paw_l == null and _grip_l != null:
		paw_l = rig.to_local(_grip_l.global_position) if _grip_l.visible else sh_l + Vector3(0.04, -0.3, -0.18)
	if paw_r == null and _grip_r != null:
		paw_r = rig.to_local(_grip_r.global_position)
	if paw_l == null:
		paw_l = sh_l + Vector3(0, -0.36, 0)
	if paw_r == null:
		paw_r = sh_r + Vector3(0, -0.36, 0)
	_reach(_arm_l, paw_l)
	_reach(_arm_r, paw_r)
	if _knife != null and not (_swing_t < 0.5 and not _swing_weapon):
		_knife.visible = false

	# Feet: step in time, tuck up in the air.
	var fl: Vector3
	var fr: Vector3
	if sliding and on_floor:
		fl = Vector3(-0.17, 0.12, -0.32)
		fr = Vector3(0.17, 0.16, -0.24)
	elif on_floor and hop <= 0.01:
		fl = Vector3(-0.17, 0.09 + maxf(0.0, cos(_phase)) * 0.12 * run, -0.05 - sw * 0.24)
		fr = Vector3(0.17, 0.09 + maxf(0.0, -cos(_phase)) * 0.12 * run, -0.05 + sw * 0.24)
	else:
		fl = Vector3(-0.19, 0.16, 0.04)
		fr = Vector3(0.19, 0.2, -0.12)
	_foot_l.position = fl
	_foot_r.position = fr
	_reach(_leg_l, fl + Vector3(0, 0.05, 0.02), 0.4)
	_reach(_leg_r, fr + Vector3(0, 0.05, 0.02), 0.4)

	_tail.rotation = Vector3(sin(_t * 2.0) * 0.08, sin(_t * (5.0 + run * 6.0)) * (0.3 + run * 0.2), 0)

	_blink -= delta
	var eye_y := 0.12 if _blink < 0.0 else 1.0
	if _blink < -0.11:
		_blink = randf_range(1.6, 4.5)
	# Expressions: squint when hit, wide and worried when low, smiling after
	# a KO; the mouth opens when hit or taunting.
	if _eye_base.is_empty():
		for e in _eyes:
			_eye_base.append([e.scale, e.position])
	var sx := 1.0
	var sy := eye_y
	var lift := 0.0
	if hurt > 0.3:
		sy = minf(sy, 0.35)
		sx = 1.12
	elif happy > 0.2:
		sy = minf(sy, 0.3)
		lift = 0.02
	elif low_health:
		sx = 1.18
		sy *= 1.22
	for i in _eyes.size():
		var e: Node3D = _eyes[i]
		var b: Array = _eye_base[i]
		e.scale = Vector3(b[0].x * sx, b[0].y * sy, b[0].z)
		e.position = b[1] + Vector3(0, lift, 0)
	if _mouth != null:
		var open := maxf(hurt, 1.0 if taunt >= 0 else 0.0)
		_mouth.visible = open > 0.15 or happy > 0.2
		if _mouth.visible:
			var o := clampf(open, 0.0, 1.0)
			_mouth.scale = Vector3(0.045 + 0.02 * happy, 0.012 + 0.04 * o, 0.02)

	for f in _jet_flames:
		f.visible = jetting
		if jetting:
			f.scale = Vector3.ONE * (0.8 + randf() * 0.5)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		for m in [_mat_body, _mat_light, _mat_paw]:
			m.emission_energy_multiplier = _flash * 1.6


# --------------------------------------------------------------------------
# Back accessories
# --------------------------------------------------------------------------

func _build_back() -> void:
	if back <= 0:
		return
	_back_node = Node3D.new()
	_back_node.position = Vector3(0, 0.88, 0.36)
	rig.add_child(_back_node)
	var b := _back_node
	var dark := _plain(Color(0.08, 0.08, 0.1), 0.5)
	match back:
		1:  # cape
			var cloth := BoxMesh.new()
			cloth.size = Vector3(0.62, 0.95, 0.04)
			_mesh(b, cloth, _accent, Vector3(0, -0.3, 0.1)).rotation.x = 0.22
			_cyl(b, _accent, 0.34, 0.34, 0.07, Vector3(0, 0.18, -0.3), 20)
		2:  # backpack
			var pack := BoxMesh.new()
			pack.size = Vector3(0.44, 0.5, 0.22)
			_mesh(b, pack, _accent, Vector3(0, -0.05, 0.08))
			var pocket := BoxMesh.new()
			pocket.size = Vector3(0.3, 0.2, 0.08)
			_mesh(b, pocket, dark, Vector3(0, -0.14, 0.22))
			_cyl(b, dark, 0.06, 0.06, 0.4, Vector3(0, 0.28, 0.08), 10).rotation.z = PI * 0.5
		3:  # wings
			var white := _plain(Color(0.97, 0.97, 1.0), 0.6)
			for sx in [-1.0, 1.0]:
				for i in 3:
					var w := _ball(b, white, Vector3(sx * (0.25 + i * 0.17), 0.2 - i * 0.12, 0.08), Vector3(0.2, 0.07, 0.1))
					w.rotation.z = sx * (0.5 - i * 0.25)
		4:  # balloon
			_cyl(b, dark, 0.006, 0.006, 1.2, Vector3(0.15, 0.75, 0.1), 5)
			var rubber := _plain(color.lerp(Color.WHITE, 0.15), 0.2)
			rubber.emission_enabled = true
			rubber.emission = color
			rubber.emission_energy_multiplier = 0.5
			_ball(b, rubber, Vector3(0.15, 1.55, 0.1), Vector3(0.24, 0.3, 0.24))
		5:  # katana
			var steel := _plain(Color(0.8, 0.82, 0.86), 0.2)
			steel.metallic = 0.9
			var blade := BoxMesh.new()
			blade.size = Vector3(0.05, 1.0, 0.015)
			_mesh(b, blade, steel, Vector3(0.05, 0.1, 0.1)).rotation.z = 0.6
			var grip := BoxMesh.new()
			grip.size = Vector3(0.06, 0.26, 0.04)
			_mesh(b, grip, dark, Vector3(-0.31, 0.62, 0.1)).rotation.z = 0.6
		6:  # flag
			_cyl(b, dark, 0.02, 0.02, 1.5, Vector3(0, 0.55, 0.1), 6)
			var cloth2 := BoxMesh.new()
			cloth2.size = Vector3(0.55, 0.34, 0.02)
			_mesh(b, cloth2, _accent, Vector3(0.29, 1.1, 0.1))
