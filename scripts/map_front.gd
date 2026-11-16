extends RefCounted
## Layout 6: FRONTLINE (200 x 140 m), the Battlefield-style map used only by
## the Frontline mode. Built with the map.gd toolkit (see map.gd: _building,
## _wall_x, _stairs, _wedge, _slab, _hole, _surface, mirror = point symmetry).
##
## Geometry is written for the +X half (team 1, orange) and mirrored onto the
## -X half (team 0, blue), so both sides are identical. Anything coloured by
## team is placed with mirror = false.
##
##   x = +/-90   team bases: HQ, helipad, vehicle bays, guard towers
##   x = +/-70   trench lines either side of the main road
##   flag C (55, -24) / flag A (-55, 24): container yard, warehouse with a
##                mezzanine, a hill with a concrete bunker
##   flag B (0, 0) town square: two 4-storey towers (roof terraces = vantage
##                points), houses, apartment blocks, parked cars
##   north / south edges: farms (farmhouse, barn, hay, hedges) and forest
## Map data read by frontline.gd: m.flags, m.bases, m.vehicle_spots.

const Places = preload("res://scripts/map_places.gd")

const TEAM_MAT := ["team0", "team1"]


static func frontline(m) -> void:
	# --- Things below ground first (holes cut the ground slab) ---
	_trench(m, 70.0, 8.0, 34.0)
	_trench(m, 70.0, -34.0, -8.0)
	_trench(m, 46.0, -16.0, -4.5 - 1.0)

	# --- Roads and tracks ---
	m._surface(Rect2(-100, -4, 200, 8), 0.01, "road", false)
	m._surface(Rect2(34, -70, 7, 66), 0.011, "road")
	m._surface(Rect2(34, 4, 7, 66), 0.011, "road")
	for x in range(-96, 96, 6):
		if absf(x) > 16:
			m._visual(Vector3(x, 0.022, 0), Vector3(3.0, 0.01, 0.18), "line")
	m._surface(Rect2(41, -27, 38, 5), 0.012, "dirt")
	m._surface(Rect2(41, 22, 30, 4), 0.012, "dirt")
	m.no_grass.append(Rect2(-100, -4.5, 200, 9))
	for r in [Rect2(33.5, -70, 8, 140), Rect2(41, -27, 38, 5), Rect2(41, 22, 30, 4)]:
		m.no_grass.append(r)
		m.no_grass.append(Rect2(-r.end.x, -r.end.y, r.size.x, r.size.y))

	_town(m)
	_props(m)
	_flag_yard(m)
	_hill_bunker(m, Vector3(36, 0, -54))
	_farm(m)
	_base(m)
	_trees(m)

	m.flags = [Vector3(-55, 0, 24), Vector3(0, 0, 0), Vector3(55, 0, -24)]
	m.bases = [Vector3(-90, 0, 0), Vector3(90, 0, 0)]
	m._lawn(Rect2(-68, -48, 136, 96), false)
	m._spawns([Vector3(88, 0.1, 6), Vector3(88, 0.1, -6), Vector3(94, 0.1, 0), Vector3(84, 0.1, 18)])
	m._pickups([["weapon", Vector3(0, 13.6, 21)], ["health", Vector3(52, 0, -31)], ["weapon", Vector3(66, 3.4, -49)],
		["health", Vector3(20, 0, 6.5)], ["weapon", Vector3(37, 2.5, -50.5)], ["health", Vector3(70, -1.7, 20)]])


## A building plus its footprint kept clear of grass (both mirror copies).
static func _bld(m, c: Vector3, sx: float, sz: float, floors: int, mat: String, opts := {}) -> void:
	m._building(c, sx, sz, floors, mat, opts)
	var r := Rect2(c.x - sx * 0.5, c.z - sz * 0.5, sx, sz)
	m.no_grass.append(r.grow(0.3))
	if opts.get("mirror", true):
		m.no_grass.append(Rect2(-r.end.x, -r.end.y, r.size.x, r.size.y).grow(0.3))


## An open trench along Z at x (2.6 m wide, 1.7 m deep) with ramps at both
## ends, plank revetments and a sandbag rim.
static func _trench(m, x: float, z0: float, z1: float) -> void:
	var w := 2.6
	var d := 1.7
	var mid := (z0 + z1) * 0.5
	var length := z1 - z0
	m._hole(Rect2(x - w * 0.5, z0, w, length))
	m._box(Vector3(x, -d - 0.5, mid), Vector3(w + 0.6, 1.0, length + 0.6), "dirt")
	for s in [-1.0, 1.0]:
		m._box(Vector3(x + s * (w * 0.5 + 0.1), -d * 0.5, mid), Vector3(0.2, d, length), "deck")
		# Sandbag rim: waist-high cover along both edges.
		m._box(Vector3(x + s * (w * 0.5 + 0.45), 0.3, mid), Vector3(0.7, 0.6, length - 1.0), "sand")
	m._box(Vector3(x, -d * 0.5, z0 - 0.1), Vector3(w, d, 0.2), "deck")
	m._box(Vector3(x, -d * 0.5, z1 + 0.1), Vector3(w, d, 0.2), "deck")
	m._wedge(Vector3(x, -d, z0 + 2.2), Vector3(4.4, d, w), PI * 0.5, "dirt", true, false)
	m._wedge(Vector3(x, -d, z1 - 2.2), Vector3(4.4, d, w), -PI * 0.5, "dirt", true, false)
	for i in int(length / 6.0):
		m._cyl(Vector3(x + w * 0.5 + 0.1, -d, z0 + 3.0 + i * 6.0), 0.08, d + 0.8, "deck")
		m._cyl(Vector3(x - w * 0.5 - 0.1, -d, z0 + 3.0 + i * 6.0), 0.08, d + 0.8, "deck")


## Sandbag wall (waist high) centred at pos: Sack_Trench models in a row.
static func _sandbags(m, pos: Vector3, length: float, yaw: float, mirror := true) -> void:
	var n := maxi(1, ceili(length / 3.3))
	var seg := length / n
	var rot := Basis(Vector3.UP, yaw)
	for i in n:
		var c: Vector3 = pos + rot * Vector3(-length * 0.5 + seg * (i + 0.5), 0, 0)
		m._model("toon/Wall/Sack_Trench", c, yaw, Vector3(seg / 3.35, 0.78, 0.95), mirror, "none")
	m._collider(pos + Vector3(0, 0.5, 0), Vector3(length, 1.0, 0.85), yaw)
	if mirror:
		m._collider(Vector3(-pos.x, 0.5, -pos.z), Vector3(length, 1.0, 0.85), yaw + PI)


## Czech hedgehog anti-tank obstacle.
static func _hedgehog(m, pos: Vector3, mirror := true) -> void:
	var s := 1.0
	m._rod(pos + Vector3(-s, 0, -s), pos + Vector3(s, 1.6, s), 0.09, "metal", mirror)
	m._rod(pos + Vector3(s, 0, -s), pos + Vector3(-s, 1.6, s), 0.09, "metal", mirror)
	m._rod(pos + Vector3(0, 0, s * 1.3), pos + Vector3(0, 1.6, -s * 1.3), 0.09, "metal", mirror)
	m._collider(pos + Vector3(0, 0.8, 0), Vector3(1.6, 1.6, 1.6))
	if mirror:
		m._collider(Vector3(-pos.x, 0.8, -pos.z), Vector3(1.6, 1.6, 1.6))


static func _town(m) -> void:
	m._surface(Rect2(-14, -11, 28, 22), 0.015, "path", false)
	m.no_grass.append(Rect2(-14.5, -11.5, 29, 23))
	# Two four-storey towers facing each other across the square.
	_bld(m, Vector3(0, 0, 21), 18.0, 12.0, 4, "block_b", {"roof": "block_a"})
	# Houses and apartment blocks around it.
	_bld(m, Vector3(20, 0, 13), 11.0, 9.0, 2, "house", {"pitched": true, "roof": "roof_red"})
	_bld(m, Vector3(-20, 0, 14), 12.0, 10.0, 3, "block_a", {"roof": "block_c"})
	_bld(m, Vector3(22, 0, 28), 13.0, 10.0, 2, "block_b", {"roof": "block_a"})
	_bld(m, Vector3(-21, 0, 29), 10.0, 9.0, 2, "house", {"pitched": true, "roof": "roof_red"})
	# Square furniture: planters with trees, a statue, sandbag nests.
	for p in [Vector3(11, 0, 8.5), Vector3(-11, 0, 8.5)]:
		m._box(p + Vector3(0, 0.4, 0), Vector3(2.4, 0.8, 2.4), "block_a")
		m._tree(p + Vector3(0, 0.8, 0), 0.8)
	m._cyl(Vector3(0, 0, 0), 1.6, 0.6, "block_a", false)
	m._cyl(Vector3(0, 0.6, 0), 0.9, 0.5, "block_a", false)
	_sandbags(m, Vector3(6, 0, -6), 4.0, 0.6)
	_sandbags(m, Vector3(-7, 0, -6.5), 3.5, -0.5)
	_sandbags(m, Vector3(8, 0, 5.5), 3.0, -0.3)
	Places._car(m, Vector3(13, 0, 2.6), 0.05, "car_white")
	Places._car(m, Vector3(-27, 0, 2.6), PI, "car_red")
	Places._car(m, Vector3(30, 0, -18), PI * 0.5, "car_blue")
	m._box(Vector3(17.5, 0.6, -6.5), Vector3(1.2, 1.2, 1.2), "crate", true, 0.3)
	m._box(Vector3(18.5, 0.6, -7.8), Vector3(1.2, 1.2, 1.2), "crate", true, 0.1)
	for x in [10.0, 26.0, 48.0, 62.0]:
		m._lamp_post(Vector3(x, 0, 5.4))


## Battlefield clutter from the model packs: wrecks, barriers, tyres, signs.
static func _props(m) -> void:
	# Crossroads by the town: traffic lights and a town sign on the way in.
	m._model("zombie/Prop/Traffic_Light_1", Vector3(42.5, 0, 5.5), PI, 1.0, true, "none")
	m._model("zombie/Prop/Traffic_Light_1", Vector3(32.5, 0, -5.5), 0.0, 1.0, true, "none")
	m._model("zombie/Prop/Town_Sign", Vector3(60.0, 0, 7.5), PI, 0.8, true, "none")
	m._model("zombie/Prop/Fire_Hydrant", Vector3(15.5, 0, 5.2), 0.0, 1.1)
	m._model("toon/Prop/Trash_Container", Vector3(26.5, 0, 18.5), PI * 0.5, 1.0)
	m._model("toon/Prop/Trash_Container", Vector3(-27.5, 0, 22.0), PI * 0.5, 1.0)
	for p in [Vector3(9.0, 0, -9.0), Vector3(-10.0, 0, 10.5), Vector3(28.0, 0, 9.0)]:
		m._model("zombie/Prop/Trash_Bag_" + str(1 + m._rng.randi() % 2), p, m._rng.randf() * TAU, 1.3, true, "none")
	# Wrecked cars and debris on the fields between the lines.
	m._model("toon/Prop/Debris_Broken_Car", Vector3(52.0, 0, 12.0), 0.7, 1.0)
	m._model("toon/Prop/Debris_Broken_Car", Vector3(24.0, 0, -36.0), 2.1, 1.0)
	m._model("toon/Prop/Debris_Broken_Car", Vector3(84.0, 0, 34.0), 1.4, 1.0)
	m._model("toon/Prop/Debris_Tires", Vector3(56.0, 0, 15.0), 0.3, 1.2)
	m._model("toon/Prop/Debris_Pile", Vector3(18.0, 0.02, -12.0), 0.5, 1.4, true, "none")
	m._model("toon/Prop/Debris_Pile", Vector3(-6.0, 0.02, 34.0), 2.0, 1.4, true, "none")
	m._model("toon/Prop/Gas_Tank", Vector3(64.0, 0, -30.0), 0.0, 1.2)
	m._model("toon/Prop/Pipes", Vector3(50.0, 0, -44.0), 0.4, 1.2)
	# Concrete barriers in front of the bases and along the road.
	for z in [-24.0, -18.0, 18.0, 24.0]:
		m._model("toon/Wall/Barrier_Large", Vector3(76.5, 0, z), PI * 0.5, Vector3(1.0, 0.6, 1.0))
	for x in [30.0, 46.0]:
		m._model("zombie/Prop/Traffic_Barrier_1", Vector3(x, 0, 3.0), 0.0, 1.2)
		m._model("toon/Prop/Traffic_Cone", Vector3(x + 1.6, 0, 2.6), 0.0, 1.0, true, "none")
	# Water tower by the farm, water tank at each base.
	m._model("zombie/Building/Water_Tower", Vector3(62.0, 0, 62.0), 0.0, 1.1)
	m._model("toon/Building/Water_Tank_Platform", Vector3(95.0, 0, -4.0), 0.0, 1.3)
	# Boulders and undergrowth.
	for p in [Vector3(30.0, 0, 52.0), Vector3(88.0, 0, 48.0), Vector3(12.0, 0, -50.0), Vector3(58.0, 0, -62.0), Vector3(-34.0, 0, -58.0)]:
		m._rock(p, m._rng.randf_range(0.8, 1.4))


## Around flag C: containers, a warehouse with a mezzanine, sandbag nests.
static func _flag_yard(m) -> void:
	var x0 := 57.0
	var x1 := 79.0
	var z0 := -51.0
	var z1 := -37.0
	m._wall_x(z1 - 0.15, x0, x1, 0.0, 7.0, "block_c", [[63.0, 4.5, 0.0, 4.6], [73.0, 4.5, 0.0, 4.6]])
	m._wall_x(z0 + 0.15, x0, x1, 0.0, 7.0, "block_c", [[68.0, 3.0, 0.0, 3.0]])
	m._wall_z(x0 + 0.15, z0 + 0.3, z1 - 0.3, 0.0, 7.0, "block_c", [[-44.0, 3.0, 0.0, 3.0]])
	m._wall_z(x1 - 0.15, z0 + 0.3, z1 - 0.3, 0.0, 7.0, "block_c", [[-44.0, 3.0, 1.4, 2.8]])
	m._slab(Rect2(x0, z0, x1 - x0, z1 - z0), 7.3, "block_a")
	m._slab(Rect2(x0 + 0.3, z0 + 0.3, x1 - x0 - 0.6, 4.2), 3.4, "deck")
	m._box(Vector3((x0 + x1) * 0.5 + 3.0, 3.9, z0 + 4.55), Vector3(x1 - x0 - 6.6, 1.0, 0.08), "metal")
	m._stairs(Vector3(x0 + 4.0, 0, z0 + 5.3), Vector3(6.0, 3.4, 1.5), PI, "deck")
	m.no_grass.append(Rect2(x0, z0, x1 - x0, z1 - z0))
	m.no_grass.append(Rect2(-x1, -z1, x1 - x0, z1 - z0))
	m._glow(Vector3(68, 6.0, -44), Color(1.0, 0.85, 0.6), 14.0, 1.6 / maxf(m.light_scale, 0.4))
	for p in [Vector3(64, 0.6, -42), Vector3(65.2, 0.6, -41.2), Vector3(72, 0.6, -46)]:
		m._box(p, Vector3(1.2, 1.2, 1.2), "crate", true, p.x * 0.3)
	m._container(Vector3(70, 0, -40.5), 0.0, "olive", 6.0)
	# Container yard and cover around the flag.
	m._container(Vector3(46, 0, -33), 0.25, "olive")
	m._container(Vector3(47, 0, -36.5), 0.2, "block_c")
	m._container(Vector3(46.5, 2.6, -34.6), 0.22, "car_red")
	m._container(Vector3(62, 0, -16), PI * 0.5, "olive")
	_sandbags(m, Vector3(55, 0, -18.5), 5.0, 0.0)
	_sandbags(m, Vector3(60.5, 0, -24), 4.0, PI * 0.5)
	_sandbags(m, Vector3(50, 0, -27.5), 4.0, 0.3)
	for p in [Vector3(58, 0, -9), Vector3(64, 0, -11), Vector3(52, 0, -12)]:
		_hedgehog(m, p)


## A raised hill (ramps on two sides) with a concrete bunker on top.
static func _hill_bunker(m, c: Vector3) -> void:
	var h := 2.5
	m._box(c + Vector3(0, h * 0.5, 0), Vector3(16, h, 12), "dirt")
	m._wedge(c + Vector3(0, 0, 9), Vector3(6, h, 6), PI * 0.5, "dirt", true, false)
	m._wedge(c + Vector3(-11, 0, 0), Vector3(6, h, 6), 0.0, "dirt", true, false)
	m.no_grass.append(Rect2(c.x - 14, c.z - 6, 28, 18))
	m.no_grass.append(Rect2(-c.x - 14, -c.z - 12, 28, 18))
	var b := c + Vector3(2, h, -1)
	m._wall_x(b.z + 2.5, b.x - 3.0, b.x + 3.0, h, 2.4, "block_a", [[b.x, 4.0, 1.0, 1.55]])
	m._wall_x(b.z - 2.5, b.x - 3.0, b.x + 3.0, h, 2.4, "block_a", [[b.x, 1.4, 0.0, 2.2]])
	m._wall_z(b.x - 2.85, b.z - 2.2, b.z + 2.2, h, 2.4, "block_a", [[b.z, 2.0, 1.0, 1.5]])
	m._wall_z(b.x + 2.85, b.z - 2.2, b.z + 2.2, h, 2.4, "block_a", [[b.z, 2.0, 1.0, 1.5]])
	m._slab(Rect2(b.x - 3.4, b.z - 3.0, 6.8, 6.0), h + 2.75, "block_a", [], true, 0.35)
	_sandbags(m, c + Vector3(-5, h, 4.5), 4.0, 0.2)
	m._glow(b + Vector3(0, 1.8, 0), Color(1.0, 0.8, 0.5), 6.0, 1.2 / maxf(m.light_scale, 0.4))


## Farmland on the outer edges: farmhouse, barn, hay bales, hedgerows.
static func _farm(m) -> void:
	_bld(m, Vector3(52, 0, 52), 12.0, 9.0, 2, "house", {"pitched": true, "roof": "roof_red"})
	_bld(m, Vector3(70, 0, 50), 14.0, 10.0, 1, "block_b", {"pitched": true, "roof": "roof_red"})
	_bld(m, Vector3(-10, 0, 52), 10.0, 9.0, 2, "house", {"pitched": true, "roof": "block_c"})
	for p in [Vector3(58, 0, 38), Vector3(61, 0, 39.5), Vector3(80, 0, 42), Vector3(20, 0, 46), Vector3(23, 0, 44.5), Vector3(-30, 0, 48)]:
		m._cyl(p, 0.8, 1.3, "hay")
	for x in range(26, 46, 2):
		m._bush(Vector3(x, 0, 38.5), 1.2)
	for x in range(-48, -24, 2):
		m._bush(Vector3(x, 0, 40.0), 1.1)
	Places._fence_x(m, 44.0, 44.0, 64.0)
	Places._fence_z(m, 44.0, 44.0, 60.0)
	m._surface(Rect2(44, 44, 20, 16), 0.012, "dirt")
	m.no_grass.append(Rect2(44, 44, 20, 16))
	m.no_grass.append(Rect2(-64, -60, 20, 16))
	_bld(m, Vector3(78, 0, 60), 8.6, 8.6, 2, "block_c", {"roof": "block_a"})
	_bld(m, Vector3(78, 0, -60), 8.6, 8.6, 2, "block_c", {"roof": "block_a"})


## Team bases: HQ, helipad, vehicle bays, banners in the team colour.
static func _base(m) -> void:
	_bld(m, Vector3(91, 0, -14), 10.0, 9.0, 2, "block_a", {"roof": "olive"})
	for team in 2:
		var sgn := 1.0 if team == 1 else -1.0
		var tm: String = TEAM_MAT[team]
		var pad := Vector3(91, 0, 13) * sgn
		m._cyl(pad, 5.0, 0.12, "block_a", false, false)
		m._cyl(pad + Vector3(0, 0.12, 0), 4.2, 0.02, tm, false, false)
		m._cyl(pad + Vector3(0, 0.14, 0), 3.8, 0.02, "block_a", false, false)
		m._box(pad + Vector3(-1.0, 0.17, 0), Vector3(0.4, 0.02, 3.0), "trim", false, 0.0, false)
		m._box(pad + Vector3(1.0, 0.17, 0), Vector3(0.4, 0.02, 3.0), "trim", false, 0.0, false)
		m._box(pad + Vector3(0, 0.17, 0), Vector3(2.0, 0.02, 0.4), "trim", false, 0.0, false)
		m.no_grass.append(Rect2(pad.x - 5.2, pad.z - 5.2, 10.4, 10.4))
		# Banners on poles at the base entrance.
		for z in [-7.0, 7.0]:
			var pole := Vector3(80, 0, z) * sgn
			m._cyl(pole, 0.1, 6.0, "metal", false)
			m._box(pole + Vector3(0, 4.6, 0), Vector3(0.1, 2.4, 1.4), tm, false)
		m._box(Vector3(96.2, 3.2, -14) * sgn, Vector3(0.1, 1.6, 6.0), tm, false, 0.0, false)
		# Vehicle bay slab.
		m._surface(Rect2(78, -16, 8, 10) if team == 1 else Rect2(-86, 6, 8, 10), 0.014, "block_a", false)
		var face := PI * 0.5 if team == 1 else -PI * 0.5
		m.vehicle_spots.append(["buggy", Transform3D(Basis(Vector3.UP, face), Vector3(84, 0.3, 2.0) * sgn), team])
		m.vehicle_spots.append(["buggy", Transform3D(Basis(Vector3.UP, face), Vector3(84, 0.3, -2.0) * sgn), team])
		m.vehicle_spots.append(["tank", Transform3D(Basis(Vector3.UP, face), Vector3(82, 0.3, -11) * sgn), team])
		m.vehicle_spots.append(["heli", Transform3D(Basis(Vector3.UP, face), pad + Vector3(0, 0.3, 0)), team])
	_sandbags(m, Vector3(78, 0, 14), 6.0, PI * 0.5)
	_sandbags(m, Vector3(78, 0, -20), 6.0, PI * 0.5)
	for p in [Vector3(74, 0, 40), Vector3(76, 0, -26), Vector3(75, 0, 30)]:
		_hedgehog(m, p)
	m._container(Vector3(94, 0, 26), PI * 0.5, "olive")
	m._container(Vector3(96.5, 0, 26), PI * 0.5, "block_c")


## Groves and scattered trees, kept off roads, buildings and the town.
static func _trees(m) -> void:
	var blocked: Array = [Rect2(-15, -12, 30, 40), Rect2(12, 5, 20, 30), Rect2(30, -72, 14, 144), Rect2(-102, -6, 204, 12),
		Rect2(40, -54, 42, 40), Rect2(20, -62, 30, 22), Rect2(42, 40, 40, 24), Rect2(66, -40, 10, 80), Rect2(76, -30, 26, 70),
		Rect2(-16, 46, 12, 12), Rect2(40, -30, 28, 25), Rect2(66, 20, 8, 20), Rect2(68, -36, 6, 30)]
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 600:
		tries += 1
		var p := Vector3(m._rng.randf_range(4, 96), 0, m._rng.randf_range(-66, 66))
		var ok := true
		for r in blocked:
			if (r as Rect2).has_point(Vector2(p.x, p.z)) or (r as Rect2).has_point(Vector2(-p.x, -p.z)):
				ok = false
				break
		if not ok:
			continue
		placed += 1
		if absf(p.z) > 48.0 and m._rng.randf() < 0.6:
			m._pine(p, m._rng.randf_range(1.0, 1.5))
		elif m._rng.randf() < 0.12:
			m._rock(p, m._rng.randf_range(0.6, 1.1))
		elif m._rng.randf() < 0.25:
			m._bush(p, m._rng.randf_range(1.0, 1.6))
			m._plant(p + Vector3(1.4, 0, 0.6), 1.0)
		else:
			m._tree(p, m._rng.randf_range(1.0, 1.6))


## Rolling hills and woods beyond the walls.
static func scenery(m, rich: bool) -> void:
	var hill := StandardMaterial3D.new()
	var g: Color = m.theme.mats.ground[0]
	hill.albedo_color = g.darkened(0.15)
	hill.roughness = 0.95
	var n := 16
	for i in n:
		var p: Vector3 = m._ring_spot(i, n, 30.0, 80.0)
		var r: float = m._rng.randf_range(30.0, 55.0)
		m._add(m._unit_sphere, hill, Transform3D(Basis().scaled(Vector3(r, m._rng.randf_range(8.0, 20.0), r * 0.8)), p + Vector3(0, -2.0, 0)), false)
	m._scenery_trees(60 if rich else 24, 3.0, 26.0)
