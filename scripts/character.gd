extends Node3D
## The plush animal model used for players in a match, in the lobby and on the
## victory podium. Built from primitive meshes; animated procedurally.
##
## It has no _process of its own: whoever owns it calls animate() once per
## PHYSICS tick (physics interpolation then smooths it to the display rate).
##
## Kinds: 0 bear, 1 bunny, 2 cat, 3 dog, 4 fox, 5 frog  (see ui_kit.KIND_NAMES;
## ui_kit.portrait() draws the matching 2D face).
## Customisation: a hat (ui_kit.HAT_NAMES) and a face accessory
## (ui_kit.FACE_NAMES), built by _build_hat() / _build_face(). To add one,
## append its name in ui_kit.gd and a branch in the matching function.
##
## Local space: feet at y = 0, facing -Z, about 1.75 m tall plus ears.

const Viewmodel = preload("res://scripts/viewmodel.gd")
const GUN_SCALE := 1.6
const Weapons = preload("res://scripts/weapons.gd")
const Models = preload("res://scripts/models.gd")

## Every character is an imported, rigged model driven by its own animations
## (the old sphere-built plush rig further down is no longer reachable).
## ROSTER[kind] = [model, "creature" | "human"]; names are ui_kit.KIND_NAMES.
##   creatures: Quaternius Ultimate Monsters (one shared rig: Idle, Walk, Run,
##              Jump_Idle, Duck, Wave, No, HitReact)
##   humans:    Quaternius animated characters (Idle_Gun_Pointing, Run_Shoot...)
const ROSTER := [
	["animals/m_Bunny_14", "creature"], ["animals/m_Frog_14", "creature"], ["animals/m_Dino_14", "creature"],
	["animals/m_Birb_14", "creature"], ["animals/m_Yeti_14", "creature"], ["animals/m_Fish_14", "creature"],
	["animals/m_Monkroose_14", "creature"], ["animals/m_Alien_14", "creature"], ["animals/m_Orc_14", "creature"],
	["animals/m_Ninja_14", "creature"], ["animals/m_Demon_14", "creature"], ["animals/m_BlueDemon_14", "creature"],
	["animals/m_MushroomKing_14", "creature"], ["animals/m_Cactoro_14", "creature"], ["animals/m_Tribal_14", "creature"],
	["chars/Swat", "human"], ["chars/Spacesuit", "human"], ["chars/Male_King", "human"], ["chars/Femal_Witch", "human"],
	["chars/Male_Punk", "human"], ["chars/Femal_Punk", "human"], ["chars/Femal_SciFi", "human"], ["chars/Male_Adventurer", "human"],
]
const KIND_COUNT := 23

var kind := 0
var color := Color.WHITE
var emote := ""                # "", "cheer", "sad"
var crouch := 0.0              # 0..1, set by player.gd
var jetting := false
var _jetpack: Node3D
var _jet_flames: Array = []
var hat := 0
var face := 0
var back := 0                  # back accessory (ui_kit.BACK_NAMES)
var _human: Node3D             # the imported model when kind >= 6
var _anim: AnimationPlayer
var _human_meshes: Array = []
var _tint: StandardMaterial3D
var _white: StandardMaterial3D
var _gun_scale := GUN_SCALE
var _with_gun := true
var _back_node: Node3D
var _creature := false

var rig: Node3D                # squash / stretch / lean
var head: Node3D
var aim: Node3D                # right arm + blaster, pitches with the view
var muzzle: Node3D
var _gun: Node3D
var _weapon := -1
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
var _eye_pos := Vector3(0.16, 0.07, -0.33)   # right eye, in head space
var _accent: StandardMaterial3D


func build(k: int, col: Color, layer_bits := 1, with_gun := true, hat_id := 0, face_id := 0, back_id := 0) -> void:
	kind = posmod(k, KIND_COUNT)
	color = col
	hat = hat_id
	face = face_id
	back = back_id
	_with_gun = with_gun
	if kind == 5:
		_eye_pos = Vector3(0.2, 0.32, -0.2)
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
	if true:
		var scarf_h := _plush(Color.from_hsv(fmod(col.h + 0.45, 1.0), 0.55, 1.0), false)
		scarf_h.emission = scarf_h.albedo_color
		scarf_h.emission_energy_multiplier = 0.9
		_accent = scarf_h
		_build_human(with_gun)
		_build_hat()
		_build_back()
		return

	# Body, belly, feet.
	_ball(rig, _mat_body, Vector3(0, 0.62, 0), Vector3(0.42, 0.5, 0.38))
	_ball(rig, _mat_light, Vector3(0, 0.58, -0.1), Vector3(0.32, 0.38, 0.31))
	_foot_l = _ball(rig, mat_dark, Vector3(-0.18, 0.1, -0.03), Vector3(0.15, 0.1, 0.2))
	_foot_r = _ball(rig, mat_dark, Vector3(0.18, 0.1, -0.03), Vector3(0.15, 0.1, 0.2))

	# Scarf in a contrasting colour hides the neck seam and adds charm.
	var scarf_mat := _plush(Color.from_hsv(fmod(col.h + 0.45, 1.0), 0.55, 1.0), false)
	scarf_mat.emission = scarf_mat.albedo_color
	scarf_mat.emission_energy_multiplier = 0.9
	_accent = scarf_mat
	var scarf := TorusMesh.new()
	scarf.inner_radius = 0.19
	scarf.outer_radius = 0.33
	scarf.rings = 24
	scarf.ring_segments = 10
	_mesh(rig, scarf, scarf_mat, Vector3(0, 1.07, 0)).scale = Vector3(1.0, 0.8, 1.0)
	_ball(rig, scarf_mat, Vector3(0.2, 0.93, -0.28), Vector3(0.075, 0.14, 0.05)).rotation.z = 0.25

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
		_gun = Node3D.new()
		_gun.position = Vector3(0.4, 0.05, -0.3)
		aim.add_child(_gun)
		set_weapon(0)

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
	_build_hat()
	_build_face()
	_build_back()


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
		c.queue_free()
	# The same model as the first-person gun, scaled up to the plush proportions.
	var model = Viewmodel.new()
	_gun.add_child(model)
	model.build(color, _layers, id, false)
	model.position = Vector3(0, -0.02, 0.08)
	model.scale = Vector3.ONE * _gun_scale
	muzzle.position = _gun.position + Vector3(0, 0.0, 0.08 + model.muzzle_z() * _gun_scale)


func _plush(col: Color, furry := true) -> StandardMaterial3D:
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
	# Fine felt bumps so the plush catches light like fabric.
	m.normal_enabled = true
	m.normal_texture = _felt()
	m.normal_scale = 0.45
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 5.0
	if not furry:
		m.next_pass = _outline
		return m
	# A fuzzy shell over the surface, then the dark outline: plush fur.
	var fur := StandardMaterial3D.new()
	fur.albedo_color = col.lerp(Color.WHITE, 0.06)
	fur.albedo_texture = _fuzz()
	fur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fur.alpha_scissor_threshold = 0.5
	fur.roughness = 1.0
	fur.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	fur.grow = true
	fur.grow_amount = 0.014
	fur.uv1_triplanar = true
	fur.uv1_scale = Vector3.ONE * 7.0
	fur.next_pass = _outline
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


func hit_flash() -> void:
	_flash = 1.0
	_squash_v -= 1.6


## Scale up from nothing with a bounce (joining the lobby, respawning).
func pop_in() -> void:
	_pop = 0.0


func muzzle_position() -> Vector3:
	return muzzle.global_position


## speed: 0..1+ fraction of run speed. vy: vertical velocity. pitch: view pitch.
## strafe: -1..1 sideways speed (leans the body into the turn).
func animate(delta: float, speed: float, on_floor: bool, vy: float, pitch: float, recoil := 0.0, strafe := 0.0) -> void:
	if _human != null:
		_animate_human(delta, speed, on_floor, pitch, recoil, strafe)
		return
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
	rig.position.y = bob + hop - crouch * 0.45
	rig.rotation.x -= crouch * 0.25
	rig.rotation.x = -0.13 * run
	rig.rotation.z = sin(_phase) * 0.05 * run - strafe * 0.16
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

	for f in _jet_flames:
		f.visible = jetting
		if jetting:
			f.scale = Vector3.ONE * (0.8 + randf() * 0.5)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_mat_body.emission_energy_multiplier = _flash * 1.6
		_mat_light.emission_energy_multiplier = _flash * 1.6


# --------------------------------------------------------------------------
# Back accessories (both plush and human characters)
# --------------------------------------------------------------------------

func _build_back() -> void:
	if back <= 0:
		return
	_back_node = Node3D.new()
	_back_node.position = Vector3(0, 1.0, 0.42) if _creature else Vector3(0, 1.2, 0.2)
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


# --------------------------------------------------------------------------
# Human characters (kinds 6+): imported rigged models with real animations
# --------------------------------------------------------------------------

func _build_human(with_gun: bool) -> void:
	var path: String = ROSTER[kind][0]
	_creature = ROSTER[kind][1] == "creature"
	_human = Models.scene(path).instantiate()
	# Creatures share a rig about 3.3 units tall; humans are about 1.9.
	_human.scale = Vector3.ONE * (0.53 if _creature else 0.94)
	_human.rotation.y = PI
	rig.add_child(_human)
	# A light wash of the player's colour over the whole model, and a white
	# overlay used for the hit flash.
	_tint = StandardMaterial3D.new()
	_tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tint.albedo_color = Color(color, 0.26 if _creature else 0.2)
	_tint.roughness = 0.8
	_white = StandardMaterial3D.new()
	_white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_white.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_white.albedo_color = Color(1, 1, 1, 0.6)
	for mi in Models.mesh_instances(_human):
		var m: MeshInstance3D = mi
		m.layers = _layers
		# The models carry their own pistol / sword; we give them our guns.
		var mb: AABB = m.mesh.get_aabb() if m.mesh != null else AABB()
		if m.name in ["Pistol", "Sword", "Gun", "Weapon", "Staff", "Axe"] or mb.position.x > 0.3 or mb.end.x < -0.3:
			m.visible = false
			continue
		m.material_overlay = _tint
		_human_meshes.append(m)
	for c in _human.find_children("*", "AnimationPlayer", true, false):
		_anim = c
	if _anim != null:
		for a in _anim.get_animation_list():
			if a.begins_with("Idle") or a.begins_with("Run") or a in ["Walk", "Wave", "Duck", "Jump_Idle", "No"]:
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		_anim.playback_default_blend_time = 0.18
	# Hats sit on the head bone (scaled down from the plush head size).
	head = Node3D.new()
	var skel: Skeleton3D = null
	for s in _human.find_children("*", "Skeleton3D", true, false):
		skel = s
	if skel != null and skel.find_bone("Head") >= 0:
		var att := BoneAttachment3D.new()
		att.bone_name = "Head"
		skel.add_child(att)
		att.add_child(head)
		head.rotation.y = PI
		if _creature:
			head.position = Vector3(0, 0.42, -0.12)
			head.scale = Vector3.ONE * 1.25
		else:
			head.position = Vector3(0, 0.13, 0.02)
			head.scale = Vector3.ONE * 0.62
	else:
		head.position = Vector3(0, 1.62, 0)
		rig.add_child(head)
	# The gun floats in the two-handed aiming pose and pitches with the view.
	aim = Node3D.new()
	aim.position = Vector3(0, 1.0 if _creature else 1.22, 0)
	rig.add_child(aim)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0.12, 0.04, -1.0)
	aim.add_child(muzzle)
	_gun_scale = 1.2
	if with_gun:
		_gun = Node3D.new()
		_gun.position = Vector3(0.3, 0.0, -0.5) if _creature else Vector3(0.12, 0.02, -0.42)
		aim.add_child(_gun)
		set_weapon(0)
	_play_h("Idle" if _creature or not with_gun else "Idle_Gun_Pointing")


func _play_h(a: String, speed := 1.0) -> void:
	if _anim == null:
		return
	if not _anim.has_animation(a):
		a = "Idle"
	if _anim.current_animation != a:
		_anim.play(a)
	_anim.speed_scale = speed


func _animate_human(delta: float, speed: float, on_floor: bool, pitch: float, recoil: float, strafe: float) -> void:
	_t += delta
	_pop = minf(1.0, _pop + delta * 2.2)
	var pop := 1.0 if _pop >= 1.0 else maxf(0.001, pow(2.0, -10.0 * _pop) * sin((_pop * 10.0 - 0.75) * TAU / 3.0) + 1.0)
	rig.scale = Vector3(1.0, 1.0 - (0.0 if _creature else crouch * 0.28), 1.0) * pop
	var hop := 0.0
	if _creature:
		# Creature rig: Idle / Walk / Run / Jump_Idle / Duck / Wave / No.
		match emote:
			"cheer":
				hop = absf(sin(_t * 6.5)) * 0.25
				_play_h("Wave", 1.5)
			"sad":
				_play_h("No", 0.8)
			_:
				if _flash > 0.6:
					_play_h("HitReact", 1.6)
				elif crouch > 0.5:
					_play_h("Duck")
				elif not on_floor:
					_play_h("Jump_Idle")
				elif speed > 0.6:
					_play_h("Run", 0.7 + speed * 0.5)
				elif speed > 0.12:
					_play_h("Walk", 0.8 + speed)
				else:
					_play_h("Idle")
		rig.position.y = hop
		rig.rotation.z = -strafe * 0.1
		aim.rotation.x = pitch + recoil * 0.2
		aim.position.y = 1.0 - crouch * 0.4
		for f in _jet_flames:
			f.visible = jetting
		if _flash > 0.0:
			_flash = maxf(0.0, _flash - delta * 6.0)
			var ovc: Material = _white if _flash > 0.35 else _tint
			for m in _human_meshes:
				m.material_overlay = ovc
		return
	match emote:
		"cheer":
			hop = absf(sin(_t * 6.5)) * 0.25
			_play_h("Wave", 1.6)
		"sad":
			_play_h("Idle_Neutral", 0.6)
		_:
			if not _with_gun:
				_play_h("Idle")
			elif not on_floor:
				_play_h("Idle_Gun_Pointing")
			elif speed > 0.15:
				if strafe > 0.6:
					_play_h("Run_Right", 0.7 + speed * 0.5)
				elif strafe < -0.6:
					_play_h("Run_Left", 0.7 + speed * 0.5)
				else:
					_play_h("Run_Shoot", 0.6 + speed * 0.6)
			else:
				_play_h("Idle_Gun_Pointing")
	rig.position.y = hop
	rig.rotation.z = -strafe * 0.08
	aim.rotation.x = pitch + recoil * 0.2
	for f in _jet_flames:
		f.visible = jetting
		if jetting:
			f.scale = Vector3.ONE * (0.8 + randf() * 0.5)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		var ov: Material = _white if _flash > 0.35 else _tint
		for m in _human_meshes:
			m.material_overlay = ov
