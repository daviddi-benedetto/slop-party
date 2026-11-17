extends RefCounted
## Layout 7: QUARANTINE (144 x 104 m), the Zombies map: a hospital campus
## sealed off behind a fence and abandoned in a hurry. Not mirrored: every
## quarter has its own job, tied together by the crossroads in the middle.
##
##                         N (+z)
##   +----------------- perimeter fence ------------------+
##   |  HOSPITAL (3 floors, roof)      CLINIC   triage    |
##   |  ambulance bay, car park        (2 fl.)  tent rows |
##   |              covered walkway ====          morgue  |
##   |------------- east-west road, CHECKPOINT -----------|
##   |  MOTEL (2 floors, pitched)   service   WAREHOUSE   |
##   |  forecourt with parked cars  tunnel    loading yard|
##   |  fuel pumps                  (below)   containers  |
##   +------------------- gate (south) -------------------+
##        dead woods outside the fence on every side
##
## Indoors: hospital, clinic, motel, warehouse (with a mezzanine), the
## service tunnel under the south side and the morgue cellar.
## Outdoors: the checkpoint, car park, tent field, loading yard and woods.
## Uses map.gd's helpers; zombies spawn anywhere on the nav graph.


static func build(m) -> void:
	_roads(m)
	_hospital(m)
	_clinic_and_tents(m)
	_warehouse(m)
	_motel(m)
	_checkpoint(m)
	_perimeter(m)
	_grounds(m)

	# Service tunnel under the south side (stairs down at both ends) and the
	# morgue cellar behind the tents.
	m._tunnel(-10.0, -18.0, 18.0, false, 4.0)
	m._basement(Rect2(42, 31, 15, 10), false)
	m._glow(Vector3(49.5, -1.6, 36), Color(0.8, 0.12, 0.08), 12.0, 1.5, false)
	m._glow(Vector3(0, -1.8, -10), Color(0.8, 0.15, 0.1), 14.0, 1.2, false)

	m._spawns([
		Vector3(-6, 0.1, -7), Vector3(6, 0.1, 7), Vector3(-7, 0.1, 6), Vector3(7, 0.1, -6),
		Vector3(-26, 0.1, 9), Vector3(22, 0.1, 10), Vector3(30, 0.1, -9), Vector3(-34, 0.1, -12),
		Vector3(-26, 3.5, 24), Vector3(22, 3.5, 22),
	], false)
	m._pickups([
		["weapon", Vector3(-26, 6.8, 22)], ["weapon", Vector3(37, 0, -24)], ["weapon", Vector3(-38, 3.4, -25)],
		["weapon", Vector3(0, -3.6, -10)], ["health", Vector3(22, 0, 21)], ["health", Vector3(49.5, -3.6, 36)],
		["health", Vector3(-12, 0, -3)], ["weapon", Vector3(48, 0, 20)],
	], false)


static func _roads(m) -> void:
	# The crossroads, a ring road inside the fence and the forecourts.
	m._surface(Rect2(-61, -4.5, 122, 9.0), 0.012, "road", false)
	m._surface(Rect2(-4.5, -40, 9.0, 85), 0.014, "road", false)
	m._surface(Rect2(-52, 6.5, 20, 9.0), 0.016, "road", false)        # hospital car park
	m._surface(Rect2(-52, -15.5, 28, 9.5), 0.016, "road", false)      # motel forecourt
	m._surface(Rect2(20, -13.0, 36, 7.5), 0.016, "road", false)       # loading yard
	m._sidewalk(Rect2(-61, 4.5, 56.5, 2.0), false)
	m._sidewalk(Rect2(4.5, 4.5, 56.5, 2.0), false)
	m._sidewalk(Rect2(-61, -6.5, 56.5, 2.0), false)
	m._sidewalk(Rect2(4.5, -6.5, 56.5, 2.0), false)
	for x in range(-58, 60, 5):
		if absf(x + 1.0) > 7.0:
			m._visual(Vector3(x + 1.0, 0.026, 0), Vector3(2.4, 0.01, 0.16), "line")
	for z in range(-36, 42, 5):
		if absf(z + 1.0) > 7.0:
			m._visual(Vector3(0, 0.026, z + 1.0), Vector3(0.16, 0.01, 2.4), "line")
	# Parking bays.
	for i in 6:
		m._visual(Vector3(-50.0 + i * 3.2, 0.03, 11.0), Vector3(0.12, 0.01, 4.4), "trim")
	for x in [-10.0, 10.0, -34.0, 34.0]:
		m._lamp_post(Vector3(x, 0, 5.4), false)
		m._lamp_post(Vector3(x, 0, -5.4), false)


static func _hospital(m) -> void:
	# Three floors with a roof terrace; the front (south) faces the car park.
	m._building(Vector3(-26, 0, 25), 27.0, 18.0, 3, "block_a", {"mirror": false, "floor": "deck", "roof": "block_c"})
	# Ambulance canopy over the entrance.
	m._box(Vector3(-26, 3.3, 13.2), Vector3(11.0, 0.3, 5.0), "trim", false)
	for x in [-31.0, -21.0]:
		m._cyl(Vector3(x, 0, 11.2), 0.16, 3.2, "metal", false)
	m._box(Vector3(-26, 3.75, 10.9), Vector3(7.0, 0.7, 0.2), "beacon", false, 0.0, false)
	m._glow(Vector3(-26, 2.6, 12.5), Color(1.0, 0.2, 0.15), 13.0, 1.6, false)
	_veh(m, "zombie/Vehicle/Vehicle_Truck", Vector3(-28.5, 0, 9.0), 0.25)
	# Abandoned cars in the car park, a few shoved together.
	_veh(m, "zombie/Vehicle/Vehicle_Sports", Vector3(-48.4, 0, 11.0), PI * 0.5)
	_veh(m, "zombie/Vehicle/Vehicle_Pickup", Vector3(-42.0, 0, 11.2), PI * 0.5)
	_veh(m, "zombie/Vehicle/Vehicle_Sports_Armored", Vector3(-37.4, 0, 9.6), PI * 0.5 + 0.5)
	m._model("toon/Prop/Debris_Broken_Car", Vector3(-45.0, 0, 21.5), 2.0, 1.0, false)
	# Helipad markings on the roof.
	m._visual(Vector3(-26, 10.23, 27), Vector3(6.0, 0.02, 1.0), "trim")
	m._visual(Vector3(-28.5, 10.23, 27), Vector3(1.0, 0.02, 6.0), "trim")
	m._visual(Vector3(-23.5, 10.23, 27), Vector3(1.0, 0.02, 6.0), "trim")
	# Covered walkway across the north road to the clinic.
	m._box(Vector3(0.5, 3.0, 22.0), Vector3(26.0, 0.25, 3.0), "metal", false)
	for x in [-10.0, -5.6, 5.6, 12.0]:
		m._cyl(Vector3(x, 0, 23.2), 0.13, 2.9, "metal", false)
		m._cyl(Vector3(x, 0, 20.8), 0.13, 2.9, "metal", false)
	m._weak_wall(Vector3(-41.5, 0, 33.0), Vector3(4.5, 2.2, 0.45), 0.0, Color(0.6, 0.58, 0.55), 130.0, false)


static func _clinic_and_tents(m) -> void:
	m._building(Vector3(22, 0, 22), 17.0, 13.0, 2, "block_b", {"mirror": false, "floor": "deck", "roof": "block_c"})
	# Triage field: rows of tents, cots and supply crates under floodlights.
	for row in 2:
		for i in 3:
			var p := Vector3(40.0 + i * 7.0, 0, 13.0 + row * 9.0)
			m._model("survival/Tent_Canvas", p, PI * 0.5 if row == 0 else -PI * 0.5, 5.4, false)
			m._model("survival/Bedroll", p + Vector3(0.0, 0, 3.2 if row == 0 else -3.2), 0.3 * i, 3.0, false, "none")
			m.no_grass.append(Rect2(p.x - 2.6, p.z - 2.6, 5.2, 5.2))
	for p in [Vector3(43.5, 0, 17.6), Vector3(50.6, 0, 17.4), Vector3(57.0, 0, 20.0)]:
		m._prop("survival/Box_Large", p, m._rng.randf() * TAU, 3.0, 8.0, false)
		m._prop("survival/Barrel", p + Vector3(1.2, 0, 0.6), 0.0, 3.0, 10.0, false)
	for p in [Vector3(37.0, 0, 9.5), Vector3(58.0, 0, 26.0)]:
		m._lamp_post(p, false, 6.0)
		m._glow(p + Vector3(0, 6.2, 0), Color(1.0, 0.25, 0.15), 14.0, 1.4, false)
	# Decontamination line: plastic barriers funnelling towards the clinic.
	for i in 5:
		m._model("zombie/Prop/Plastic_Barrier", Vector3(33.5, 0, 9.5 + i * 2.2), PI * 0.5, 1.3, false)
	m._model("toon/Prop/Trash_Container_Open", Vector3(32.0, 0, 30.5), 0.0, 1.0, false)
	m._model("zombie/Prop/Trash_Bag_1", Vector3(34.4, 0, 30.2), 0.7, 1.3, false, "none")
	m._model("zombie/Prop/Trash_Bag_2", Vector3(35.2, 0, 31.0), 2.0, 1.3, false, "none")


static func _warehouse(m) -> void:
	m._building(Vector3(38, 0, -24), 26.0, 15.0, 1, "block_c", {"mirror": false, "floor": "deck", "roof": "metal", "furnish": false})
	# Mezzanine at the east end with stairs, shelving rows of crates below.
	m._slab(Rect2(43.5, -31.0, 7.0, 13.5), 3.3, "deck", [Rect2(43.5, -26.5, 1.6, 6.2)], false, 0.25)
	m._stairs(Vector3(44.3, 0, -23.4), Vector3(5.8, 3.3, 1.5), -PI * 0.5, "deck", false)
	for i in 3:
		m._box(Vector3(29.0 + i * 4.2, 0.6, -27.6), Vector3(1.2, 1.2, 1.2), "crate", false)
		m._box(Vector3(29.0 + i * 4.2, 1.8, -27.6), Vector3(1.2, 1.2, 1.2), "crate", false)
		m._box(Vector3(29.6 + i * 4.2, 0.6, -20.6), Vector3(1.2, 1.2, 1.2), "crate", false)
		m._prop("toon/Prop/Pallet", Vector3(30.8 + i * 4.2, 0, -24.0), 0.3 * i, 0.8, 7.0, false)
	m._prop("toon/Prop/Exploding_Barrel", Vector3(47.5, 0, -19.4), 0.0, 1.0, 10.0, false)
	# Loading yard: containers, a truck backed up to the dock, forklift pallets.
	m._container(Vector3(27.0, 0, -11.5), 0.0, "c_red", 6.0, false)
	m._container(Vector3(34.4, 0, -11.2), 0.06, "c_green", 6.0, false)
	m._container(Vector3(30.6, 2.6, -11.4), 0.03, "c_green", 6.0, false)
	m._container(Vector3(53.0, 0, -9.0), PI * 0.5, "c_red", 6.0, false)
	_veh(m, "zombie/Vehicle/Vehicle_Truck_Armored", Vector3(44.0, 0, -11.6), 0.0)
	m._model("zombie/Prop/Wheels_Stack", Vector3(49.5, 0, -13.6), 0.0, 1.3, false)
	m._model("zombie/Prop/Pipes", Vector3(23.0, 0, -15.2), PI * 0.5, 1.2, false)
	m._lamp_post(Vector3(40.0, 0, -6.4), false, 6.0)


static func _motel(m) -> void:
	m._building(Vector3(-40, 0, -26), 20.0, 13.0, 2, "siding3", {"mirror": false, "pitched": true, "roof": "roof_red"})
	# Office hut and fuel pumps on the forecourt.
	m._building(Vector3(-20.5, 0, -27.5), 8.6, 9.0, 1, "siding0", {"mirror": false, "roof": "block_c"})
	m._box(Vector3(-36.0, 3.6, -11.0), Vector3(9.0, 0.3, 5.0), "trim", false)
	for x in [-39.8, -32.2]:
		m._cyl(Vector3(x, 0, -11.0), 0.2, 3.5, "metal", false)
		m._box(Vector3(x, 0.75, -9.4), Vector3(0.7, 1.5, 0.5), "car_red", false)
	m._prop("toon/Prop/Gas_Can", Vector3(-35.0, 0, -9.2), 0.4, 0.8, 5.0, false)
	m._prop("toon/Prop/Exploding_Barrel", Vector3(-30.6, 0, -12.6), 0.0, 1.0, 10.0, false)
	_veh(m, "zombie/Vehicle/Vehicle_Sports", Vector3(-36.0, 0, -12.2), 0.0)
	_veh(m, "zombie/Vehicle/Vehicle_Pickup_Armored", Vector3(-47.0, 0, -9.0), 0.4)
	m._model("toon/Prop/Debris_Broken_Car", Vector3(-27.0, 0, -8.6), 0.9, 1.0, false)
	m._model("zombie/Prop/Town_Sign", Vector3(-53.0, 0, -7.6), PI * 0.5, 1.4, false)
	m._model("toon/Prop/Trash_Container", Vector3(-51.5, 0, -30.0), PI * 0.5, 1.0, false)
	m._weak_wall(Vector3(-27.0, 0, -18.0), Vector3(4.0, 2.0, 0.45), PI * 0.5, Color(0.6, 0.5, 0.45), 120.0, false)


static func _checkpoint(m) -> void:
	# Army checkpoint on the crossroads: sandbag horseshoes, barriers that
	# split each road into lanes, a wrecked truck, floodlights.
	for q in [[1.0, 1.0], [-1.0, 1.0], [1.0, -1.0], [-1.0, -1.0]]:
		var c := Vector3(q[0] * 7.5, 0, q[1] * 7.5)
		m._model("toon/Wall/Sack_Trench", c + Vector3(0, 0, q[1] * 1.4), 0.0, 1.25, false)
		m._model("toon/Wall/Sack_Trench", c + Vector3(q[0] * 1.9, 0, -q[1] * 0.2), PI * 0.5, 1.25, false)
	for s in [-1.0, 1.0]:
		m._model("toon/Wall/Barrier_Large", Vector3(s * 14.0, 0, -1.4 * s), PI * 0.5, 1.1, false)
		m._model("toon/Wall/Barrier_Large", Vector3(s * 19.0, 0, 1.6 * s), PI * 0.5, 1.1, false)
		m._model("toon/Wall/Barrier_Large", Vector3(1.5 * s, 0, s * 14.0), 0.0, 1.1, false)
		m._model("zombie/Prop/Traffic_Barrier_1", Vector3(-1.6 * s, 0, s * 19.5), 0.0, 1.3, false)
		m._model("zombie/Prop/Traffic_Light_1", Vector3(s * 5.6, 0, s * 5.6), 0.0, 1.2, false)
	_veh(m, "zombie/Vehicle/Vehicle_Truck_Armored", Vector3(-25.0, 0, -1.8), PI * 0.5 + 0.2)
	m._prop("toon/Prop/Exploding_Barrel", Vector3(10.2, 0, 2.2), 0.0, 1.0, 10.0, false)
	m._prop("survival/Box_Large", Vector3(8.8, 0, 9.6), 0.3, 3.0, 8.0, false)
	m._prop("survival/Box", Vector3(-8.6, 0, -9.8), 0.8, 3.0, 5.0, false)
	m._model("toon/Building/Water_Tank_Platform", Vector3(13.5, 0, -15.0), 0.0, 0.9, false)
	for i in 3:
		m._model("zombie/Prop/Blood_%d" % (i + 1), Vector3(-3.0 + i * 3.4, 0.03, 2.0 - i * 2.2), i * 1.3, 0.8, false, "none", false)


static func _perimeter(m) -> void:
	# The quarantine fence, with a breached gate on each side.
	m._wall_x(-40, -61, 61, 0, 2.6, "block_c", [[0, 9, 0, 2.6]], false, 0.25)
	m._wall_x(45, -61, 61, 0, 2.6, "block_c", [[0, 9, 0, 2.6]], false, 0.25)
	m._wall_z(-61, -40, 45, 0, 2.6, "block_c", [[0, 9, 0, 2.6]], false, 0.25)
	m._wall_z(61, -40, 45, 0, 2.6, "block_c", [[0, 9, 0, 2.6]], false, 0.25)
	for p in [Vector3(-5.2, 0, -40), Vector3(5.2, 0, -40), Vector3(-5.2, 0, 45), Vector3(5.2, 0, 45),
			Vector3(-61, 0, -5.2), Vector3(-61, 0, 5.2), Vector3(61, 0, -5.2), Vector3(61, 0, 5.2)]:
		m._box(p + Vector3(0, 1.7, 0), Vector3(0.7, 3.4, 0.7), "block_a", false)
		m._box(p + Vector3(0, 3.5, 0), Vector3(0.36, 0.22, 0.36), "beacon", false, 0.0, false)
		m._glow(p + Vector3(0, 3.6, 0), Color(1.0, 0.2, 0.12), 9.0, 1.2, false)
	m._model("zombie/Prop/Traffic_Barrier_2", Vector3(-2.2, 0, -41.5), 0.2, 1.4, false)
	m._model("zombie/Prop/Traffic_Barrier_1", Vector3(2.4, 0, 46.4), -0.3, 1.4, false)
	m._model("toon/Prop/Debris_Broken_Car", Vector3(63.5, 0, 2.0), 1.2, 1.0, false)
	# Dead and autumn woods pressing against the fence from outside.
	for band in [Rect2(-68, -49.0, 136, 6.0), Rect2(-68.5, -40, 5.0, 85), Rect2(63.5, -40, 5.0, 85)]:
		var n := int(band.get_area() / 26.0)
		for i in n:
			var p := Vector3(m._rng.randf_range(band.position.x, band.end.x), 0, m._rng.randf_range(band.position.y, band.end.y))
			if absf(p.x) < 6.0 or absf(p.z) < 6.0:
				continue
			# (inside the fence the same loop plants the overgrown grounds)
			var roll: float = m._rng.randf()
			if roll < 0.45:
				m._model(m._pick(["nature/Tree/Dead_Tree_1", "nature/Tree/Dead_Tree_2", "nature/Tree/Dead_Tree_3", "nature/Tree/Dead_Tree_4", "nature/Tree/Dead_Tree_5"]), p, m._rng.randf() * TAU, m._rng.randf_range(0.7, 1.0), false, "none")
				m._trunk(p, 0.3, 3.0, false)
			elif roll < 0.8:
				m._model(m._pick(["survival/Tree_Autumn", "survival/Tree_Autumn_Tall", "survival/Tree_Fall"]), p, m._rng.randf() * TAU, m._rng.randf_range(3.4, 4.6), false, "none")
				m._trunk(p, 0.3, 3.0, false)
			else:
				m._bush(p, m._rng.randf_range(0.8, 1.3), false)


## The grounds have gone wild: dead trees, benches and rubbish on the lawns
## between the buildings.
static func _grounds(m) -> void:
	for p in [Vector3(-52, 0, 36), Vector3(-10, 0, 37), Vector3(9, 0, 36), Vector3(36, 0, 38), Vector3(-55, 0, -34), Vector3(-12, 0, -30),
			Vector3(12, 0, -33), Vector3(55, 0, -35), Vector3(-12, 0, 12), Vector3(12, 0, 34), Vector3(56, 0, 4.5 + 4.0), Vector3(-56, 0, 24)]:
		if m._rng.randf() < 0.55:
			m._model(m._pick(["nature/Tree/Dead_Tree_1", "nature/Tree/Dead_Tree_2", "nature/Tree/Dead_Tree_4"]), p, m._rng.randf() * TAU, m._rng.randf_range(0.7, 0.95), false, "none")
			m._trunk(p, 0.3, 3.0, false)
		else:
			m._tree(p, m._rng.randf_range(0.9, 1.25), false)
	for p in [[Vector3(-9.5, 0, 30), PI * 0.5], [Vector3(9.5, 0, 30), -PI * 0.5], [Vector3(-9.0, 0, -22), PI * 0.5], [Vector3(30, 0, 39), PI]]:
		m._prop("furniture/Bench", p[0], p[1], 2.15, 9.0, false)
	for p in [Vector3(-14, 0, 38), Vector3(48, 0, 40.5), Vector3(-50, 0, -36), Vector3(16, 0, -36)]:
		m._model("toon/Prop/Debris_Pile", p, m._rng.randf() * TAU, 1.0, false)
	m._weak_wall(Vector3(14.0, 0, -28.0), Vector3(4.2, 2.0, 0.45), 0.4, Color(0.6, 0.56, 0.5), 120.0, false)
	m._weak_wall(Vector3(-13.0, 0, 34.0), Vector3(3.6, 1.8, 0.45), 1.2, Color(0.6, 0.56, 0.5), 120.0, false)


## A parked or abandoned vehicle (model length along Z).
static func _veh(m, model: String, pos: Vector3, yaw: float) -> void:
	m._model(model, pos, yaw, 0.8, false)
