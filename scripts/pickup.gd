extends Area3D
## A pickup pad placed by game.gd at the spots map.gd lists.
##
## kind "weapon": a MYSTERY BOX. Stand at it and press interact (Y / E): the
##                lid flips open, weapons spin up out of it, slowing down,
##                and the last one is yours (a random weapon from the mode's
##                pool, never the one you hold; cards are kept). Each tick the
##                box tells every player standing at it
##                (`player.near_pickup = self`); the player shows the prompt
##                and calls take(). Bots open one while they still hold the
##                starting Blaster. Closed for 16 s after use.
## kind "health": restores 50 health automatically if you are hurt. Returns
##                after 12 s.
##
## The floating item spins and bobs per rendered frame; the pad itself has no
## collision, only this Area3D (mask = players).

const Viewmodel = preload("res://scripts/viewmodel.gd")
const Models = preload("res://scripts/models.gd")
const Weapons = preload("res://scripts/weapons.gd")
const Fx = preload("res://scripts/fx.gd")

var kind := "weapon"
var game
var weapon_id := 1
var _holder: Node3D
var _ring_mat: StandardMaterial3D
var _light: OmniLight3D
var _active := true
var _timer := 0.0
var _t := 0.0
var _tint := Color.WHITE
const OPEN_TIME := 1.5           # mystery box: lid open to weapon in hand
var _lid: Node3D                 # mystery box lid (hinged at the back)
var _marks: Array = []           # the "?" labels
var _opening := -1.0             # seconds into an opening, -1 = closed
var _opener = null               # who opened it
var _roll: Array = []            # weapon models shown in turn while it rolls
var _roll_i := -1
var _roll_next := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	_tint = Color(1.0, 0.78, 0.3) if kind == "weapon" else Color(1.0, 0.35, 0.5)
	var shape := SphereShape3D.new()
	shape.radius = 1.15
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)

	var base := CylinderMesh.new()
	base.top_radius = 0.75
	base.bottom_radius = 0.9
	base.height = 0.1
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.06, 0.06, 0.1)
	base_mat.roughness = 0.4
	_mesh(self, base, base_mat, Vector3(0, 0.05, 0))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.56
	ring.outer_radius = 0.7
	ring.rings = 28
	ring.ring_segments = 8
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = _tint
	_ring_mat.emission_enabled = true
	_ring_mat.emission = _tint
	_ring_mat.emission_energy_multiplier = 1.8
	_mesh(self, ring, _ring_mat, Vector3(0, 0.1, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = OmniLight3D.new()
	_light.light_color = _tint
	_light.light_energy = 1.2
	_light.omni_range = 4.5
	_light.position.y = 1.0
	add_child(_light)

	_holder = Node3D.new()
	_holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_holder.position.y = 1.0
	add_child(_holder)
	if kind == "weapon":
		_build_box()
	_fill()


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(mi)
	return mi


## The mystery box: a purple crate with gold trim, a hinged lid and glowing
## question marks.
func _build_box() -> void:
	var body := _toy_mat(Color(0.42, 0.22, 0.72))
	var gold := _toy_mat(Color(1.0, 0.76, 0.28))
	gold.metallic = 0.5
	gold.roughness = 0.35
	var box := BoxMesh.new()
	_mesh(self, box, body, Vector3(0, 0.45, 0)).scale = Vector3(1.0, 0.7, 0.7)
	# Gold bands round the corners and the middle.
	for sx in [-0.49, 0.49]:
		for sz in [-0.34, 0.34]:
			_mesh(self, box, gold, Vector3(sx, 0.45, sz)).scale = Vector3(0.06, 0.72, 0.06)
	_mesh(self, box, gold, Vector3(0, 0.12, 0)).scale = Vector3(1.04, 0.06, 0.74)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.8, 0.35)
	add_child(_lid)
	_mesh(_lid, box, body, Vector3(0, 0.06, -0.35)).scale = Vector3(1.06, 0.12, 0.74)
	_mesh(_lid, box, gold, Vector3(0, 0.06, -0.35)).scale = Vector3(0.12, 0.14, 0.76)
	_mesh(_lid, box, gold, Vector3(0, 0.06, -0.72)).scale = Vector3(1.08, 0.14, 0.05)
	# A Label3D faces its own +Z, so each mark is turned to face outwards.
	for spec in [[Vector3(0, 0.45, 0.36), 0.0], [Vector3(0, 0.45, -0.36), PI], [Vector3(0.51, 0.45, 0), PI * 0.5], [Vector3(-0.51, 0.45, 0), -PI * 0.5]]:
		var q := Label3D.new()
		q.text = "?"
		q.font = load("res://fonts/Fredoka.ttf") if ResourceLoader.exists("res://fonts/Fredoka.ttf") else null
		q.font_size = 96
		q.pixel_size = 0.004
		q.modulate = Color(1.0, 0.86, 0.35)
		q.outline_size = 18
		q.outline_modulate = Color(0.2, 0.05, 0.3)
		q.shaded = false
		q.double_sided = false
		q.position = spec[0]
		q.rotation.y = spec[1]
		add_child(q)
		_marks.append(q)


func _toy_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.rim_enabled = true
	m.rim = 0.25
	return m


## (Re)create the floating item (health) / close the box (weapon).
func _fill() -> void:
	for c in _holder.get_children():
		c.queue_free()
	if kind == "weapon":
		_roll.clear()
		_opening = -1.0
		_opener = null
		if _lid != null:
			_lid.rotation.x = 0.0
		for q in _marks:
			q.visible = true
	else:
		# First-aid kit model from the Toon Shooter kit.
		var kit: Node3D = Models.scene("toon/Collectable/Health").instantiate()
		kit.scale = Vector3.ONE * 0.75
		kit.position = Vector3(0, -0.2, 0)
		_holder.add_child(kit)
		Models.toy_node(kit)
	_holder.visible = true
	_active = true
	_ring_mat.emission_energy_multiplier = 1.8
	_light.visible = true


func prompt() -> String:
	return "OPEN MYSTERY BOX"


## Called by a player pressing interact while standing here: opens the box
## and starts the roll; the weapon is handed over when it stops.
func take(player) -> void:
	if not _active or kind != "weapon" or _opening >= 0.0:
		return
	var allowed: Array = game.weapon_pool() if game != null else []
	allowed = allowed.filter(func(id): return id != player.weapon and id != 0)
	if allowed.is_empty():
		allowed = range(1, Weapons.LIST.size()).filter(func(id): return id != player.weapon)
	weapon_id = allowed[randi() % allowed.size()]
	_opener = player
	_opening = 0.0
	player.boxes_opened += 1
	# Turn so the lid (hinged at the box's +Z) swings away from the opener.
	var d: Vector3 = player.global_position - global_position
	rotation.y = atan2(-d.x, -d.z)
	_roll_i = -1
	_roll_next = 0.0
	# Three decoys then the prize; built now, shown one at a time.
	var ids: Array = []
	for i in 3:
		ids.append(allowed[randi() % allowed.size()])
	ids.append(weapon_id)
	for id in ids:
		var model = Viewmodel.new()
		_holder.add_child(model)
		model.build(Color(1.0, 0.75, 0.25), 1, id, false)
		model.position = Vector3(0, 0.05, 0.1)
		model.scale = Vector3.ONE * 2.0
		model.visible = false
		_roll.append(model)
	for q in _marks:
		q.visible = false
	Sfx.play_at("door", global_position, -4.0, 1.3)
	Fx.sparks(game.world, global_position + Vector3(0, 0.9, 0), Color(1.0, 0.85, 0.4), 18, 5.0, Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	if kind != "weapon":
		_holder.rotation.y = _t * 1.6
		_holder.position.y = 1.0 + sin(_t * 2.2) * 0.1
		return
	for q in _marks:
		q.scale = Vector3.ONE * (1.0 + sin(_t * 3.0) * 0.08)
	if _opening < 0.0:
		return
	# Lid flips open; the weapons rise out spinning, swapping ever slower.
	var o := _opening
	_lid.rotation.x = -1.9 * (1.0 - pow(1.0 - clampf(o / 0.3, 0.0, 1.0), 3.0))
	_holder.position.y = lerpf(0.55, 1.35, 1.0 - pow(1.0 - clampf(o / 0.6, 0.0, 1.0), 2.0))
	_holder.rotation.y = _t * (9.0 - 7.0 * clampf(o / OPEN_TIME, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	if _opening >= 0.0:
		_roll_step(delta)
		return
	if not _active:
		_timer -= delta
		if _timer <= 0.0:
			_fill()
			Fx.ring(game.world, global_position + Vector3(0, 0.2, 0), Color(_tint, 0.9), 0.3, 1.4, 0.4)
		return
	for body in get_overlapping_bodies():
		if not body.has_method("pick_weapon") or not body.alive:
			continue
		if kind == "weapon":
			if body.is_bot:
				if body.weapon == 0 and game._balance == null:
					take(body)
					return
			else:
				body.near_pickup = self
		elif body.health < body.stats.max_health - 1.0:
			body.heal(50.0)
			body.say("+50 HEALTH")
			Sfx.play_at("join", global_position, -4.0)
			_taken(12.0)
			return


## The roll: show the next model at shrinking pace, the prize from 1.05 s,
## and hand it over at OPEN_TIME.
func _roll_step(delta: float) -> void:
	_opening += delta
	if _opening < 1.05:
		_roll_next -= delta
		if _roll_next <= 0.0:
			_roll_i = (_roll_i + 1) % maxi(1, _roll.size() - 1)
			for i in _roll.size():
				_roll[i].visible = i == _roll_i
			_roll_next = lerpf(0.06, 0.22, _opening / 1.05)
			Sfx.play_at("tick", global_position, -8.0, 0.9 + _opening * 0.5)
	elif _roll_i != _roll.size() - 1:
		_roll_i = _roll.size() - 1
		for i in _roll.size():
			_roll[i].visible = i == _roll_i
		Sfx.play_at("card", global_position, -4.0, 1.2)
		Fx.ring(game.world, global_position + Vector3(0, 1.35, 0), Color(1.0, 0.85, 0.4, 0.9), 0.2, 1.4, 0.3)
	if _opening >= OPEN_TIME:
		var who = _opener
		_opening = -1.0
		if who != null and is_instance_valid(who) and who.alive:
			who.pick_weapon(weapon_id)
			Sfx.play_at("join", global_position, -6.0)
		_taken(16.0)


func _taken(respawn: float) -> void:
	_active = false
	_timer = respawn
	_holder.visible = false
	_light.visible = false
	if _lid != null:
		_lid.rotation.x = 0.0          # shut until it is ready again
	_ring_mat.emission_energy_multiplier = 0.25
	Fx.sparks(game.world, global_position + Vector3(0, 1.0, 0), _tint.lerp(Color.WHITE, 0.4), 16, 6.0, Vector3.UP)
	Fx.ring(game.world, global_position + Vector3(0, 0.2, 0), Color(_tint, 0.9), 0.4, 1.8, 0.35)
