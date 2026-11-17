extends RefCounted
## Layout 8: CASTLE (92 x 68 m), home of Medieval mode and also offered in
## the lobby's map list. Uses map.gd's helpers; point-symmetric like the
## other arenas (most pieces are placed with mirror = true).
##
##   - a curtain wall (56 x 40 m, 5.6 m high) whose top is a walkable
##     wall-walk with battlements, reached by stairs inside the south and
##     north walls; square towers with pointed roofs on the corners;
##   - gatehouses south and north with two-leaf wooden gates (door.gd:
##     they open, close and can be smashed);
##   - a breach in the east and west walls bricked up with a crumbling wall
##     (rubble.gd): blow it open for a side entrance;
##   - the keep in the middle: three floors, stairs to a roof terrace;
##   - a courtyard with a market, a well, a smithy, stables and training
##     dummies; a siege camp, trees and rocks outside the walls.
## Models: Kenney Castle Kit, Quaternius Medieval Village and Fantasy Props
## MegaKit (all CC0, see ASSETS.md).

const WX := 28.0        # curtain wall centre lines
const WZ := 20.0
const WT := 2.4         # wall thickness (the wall-walk)
const WH := 5.6         # wall height


static func build(m) -> void:
	# Ground: cobbled courtyard, dirt roads through both gates.
	m._surface(Rect2(-WX + 1.2, -WZ + 1.2, WX * 2.0 - 2.4, WZ * 2.0 - 2.4), 0.012, "path", false)
	m._surface(Rect2(-3.0, -m.half_z, 6.0, m.half_z * 2.0), 0.02, "road", false)
	m.no_grass.append(Rect2(-WX, -WZ, WX * 2.0, WZ * 2.0))
	m.no_grass.append(Rect2(-3.5, -m.half_z, 7.0, m.half_z * 2.0))

	_walls(m)
	_keep(m)
	_courtyard(m)
	_outside(m)

	m._spawns([
		Vector3(-20, 0.1, -13), Vector3(18, 0.1, -6), Vector3(-13, 0.1, 15),
		Vector3(0, WH + 0.1, -WZ), Vector3(-WX, WH + 0.1, 8), Vector3(0, 0.1, -29),
		Vector3(-39, 0.1, -14), Vector3(5, 3.5, 3),
	])
	m._pickups([
		["weapon", Vector3(-22, 0, 0)], ["weapon", Vector3(12, WH, -WZ)],
		["health", Vector3(-10, 0, -14)], ["weapon", Vector3(-36, 0, 24)],
	])
	m.pickup_spots.append(["weapon", Vector3(0, 10.2, 2)])
	m.pickup_spots.append(["health", Vector3(0, 0, -5.5)])


static func _walls(m) -> void:
	var half := WT * 0.5
	# South wall (the north one is its mirror image) with the gate opening.
	m._wall_x(-WZ, -WX, WX, 0, WH, "wall", [[0.0, 5.0, 0.0, 4.2]], true, WT)
	# East wall with the bricked-up breach (west = mirror).
	m._wall_z(WX, -WZ + half, WZ - half, 0, WH, "wall", [[6.0, 4.0, 0.0, 3.6]], true, WT)
	m._weak_wall(Vector3(WX, 0, 6.0), Vector3(4.0, 3.6, 1.4), PI * 0.5, Color(0.5, 0.47, 0.42), 240.0)
	# Battlements on the outer edge of the wall-walk.
	var x := -WX + 1.6
	while x < WX - 1.0:
		m._box(Vector3(x, WH + 0.55, -WZ - half + 0.3), Vector3(1.3, 1.1, 0.6), "block_a")
		x += 2.6
	var z := -WZ + 2.6
	while z < WZ - 2.0:
		m._box(Vector3(WX + half - 0.3, WH + 0.55, z), Vector3(0.6, 1.1, 1.3), "block_a")
		z += 2.6
	# A low kerb on the inner edge, so you know where the walk ends.
	m._box(Vector3(0, WH + 0.12, -WZ + half - 0.12), Vector3(WX * 2.0 - 8.0, 0.24, 0.24), "block_b", true, 0.0, false)
	# Corner towers with pointed roofs and flags.
	for sx in [-1.0, 1.0]:
		var c := Vector3(sx * WX, 0, -WZ)
		m._box(c + Vector3(0, 4.6, 0), Vector3(7.0, 9.2, 7.0), "block_a")
		m._box(c + Vector3(0, 9.35, 0), Vector3(7.6, 0.5, 7.6), "block_b", true, 0.0, false)
		m._model("castle/Tower_Square_Roof", c + Vector3(0, 9.6, 0), 0.0, Vector3(7.6, 3.2, 7.6), true, "none")
		m._model("castle/Flag", c + Vector3(0, 15.6, 0), 0.6, 4.0, true, "none")
		# Arrow slits (dark insets) on the faces.
		for face in [Vector3(0, 0, 3.52), Vector3(0, 0, -3.52)]:
			m._box(c + face + Vector3(0, 6.2, 0), Vector3(0.3, 1.6, 0.06), "dark", true, 0.0, false)
	# Gatehouse: two flanking piers, a lintel block above and the gates.
	for sx in [-1.0, 1.0]:
		m._box(Vector3(sx * 4.3, 3.9, -WZ), Vector3(3.2, 7.8, 3.6), "block_a")
		m._model("castle/Flag_Banner_Long", Vector3(sx * 4.3, 2.4, -WZ - 1.86), PI * 0.5, 2.2, true, "none")
		m._torch(Vector3(sx * 2.9, 2.6, -WZ + 1.35))
	m._box(Vector3(0, 6.5, -WZ), Vector3(5.4, 1.8, 3.0), "block_b")
	m._door(Vector3(-2.5, 0, -WZ), 0.0, 2.5, 4.2, "castle/Gate", true, 260.0, "GATE")
	m._door(Vector3(2.5, 0, -WZ), PI, 2.5, 4.2, "castle/Gate", true, 260.0, "GATE")
	# Stairs up to the wall-walk, inside the south (and north) wall.
	m._stairs(Vector3(-14.0, 0, -WZ + half + 1.1), Vector3(9.0, WH, 2.2), 0.0, "block_b")
	m._stairs(Vector3(17.0, 0, -WZ + half + 1.1), Vector3(9.0, WH, 2.2), PI, "block_b")
	for x2 in [-22.0, -8.0, 9.0, 23.0]:
		m._torch(Vector3(x2, 3.2, -WZ + half + 0.05))


static func _keep(m) -> void:
	# The keep: three storeys of stone with a roof terrace.
	m._building(Vector3(0, 0, 2), 15.0, 12.0, 3, "block_a", {
		"mirror": false, "floor": "deck", "roof": "deck", "furnish": false, "door_model": "castle/Door", "glass": false})
	# Corner turrets with cone roofs, banners on the front.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * 7.5, 0, 2.0 + sz * 6.0)
			m._cyl(p, 1.25, 12.6, "block_b", false)
			m._cyl(p + Vector3(0, 12.6, 0), 1.6, 2.6, "roof_red", false, false, 0.05)
	m._model("castle/Flag_Banner_Long", Vector3(-3.6, 5.2, -4.12), PI * 0.5, 2.4, false, "none")
	m._model("castle/Flag_Banner_Long", Vector3(3.6, 5.2, -4.12), PI * 0.5, 2.4, false, "none")
	m._model("castle/Flag_Wide", Vector3(0, 11.2, 2.0), 0.0, 5.0, false, "none")
	# Great hall on the ground floor, armoury and bedchamber above.
	m._prop("fantasy/Table_Large", Vector3(-1.0, 0, 4.5), 0.0, 1.1, 30.0, false)
	for sx in [-1.9, -0.1]:
		m._prop("fantasy/Chair_1", Vector3(sx, 0, 5.6), PI, 1.0, 5.0, false)
		m._prop("fantasy/Chair_1", Vector3(sx, 0, 3.4), 0.0, 1.0, 5.0, false)
	m._prop("fantasy/Mug", Vector3(-1.5, 0.92, 4.5), 0.5, 1.3, 0.3, false)
	m._prop("fantasy/Chalice", Vector3(-0.4, 0.92, 4.7), 0.0, 1.3, 0.3, false)
	m._prop("fantasy/CandleStick_Triple", Vector3(-1.0, 0.92, 4.3), 0.0, 1.2, 0.5, false)
	m._prop("fantasy/Barrel", Vector3(4.6, 0, 6.6), 0.0, 1.0, 12.0, false)
	m._prop("fantasy/Barrel", Vector3(5.4, 0, 6.0), 0.5, 1.0, 12.0, false)
	m._prop("fantasy/WeaponStand", Vector3(-1.0, 3.4, 6.6), PI, 1.0, 14.0, false)
	m._prop("fantasy/Dummy", Vector3(2.4, 3.4, 5.0), 2.6, 1.0, 8.0, false)
	m._prop("fantasy/Chest_Wood", Vector3(3.5, 3.4, 6.6), PI, 1.0, 12.0, false)
	m._prop("fantasy/Bed_Twin1", Vector3(-1.5, 6.8, 5.6), 0.0, 1.0, 26.0, false)
	m._prop("fantasy/Bookcase_2", Vector3(2.0, 6.8, 7.4), PI, 1.0, 20.0, false)
	m._prop("fantasy/Vase_2", Vector3(3.6, 6.8, 6.6), 0.0, 1.0, 2.0, false)
	m._torch(Vector3(0, 2.4, -3.75), false)


static func _courtyard(m) -> void:
	# Market row (mirrored: both halves of the yard get one).
	m._model("fantasy/Stall_Empty", Vector3(-17.0, 0, -9.0), PI, 1.25)
	m._model("fantasy/Stall_Cart_Empty", Vector3(-22.5, 0, -9.0), PI, 1.15)
	m._model("village/Market_Stand_1", Vector3(-12.0, 0, -9.5), PI * 0.5, 2.6)
	for p in [Vector3(-18.6, 0, -7.4), Vector3(-15.4, 0, -7.2), Vector3(-21.0, 0, -6.8)]:
		m._prop("fantasy/Crate_Wooden", p, m._rng.randf() * TAU, 0.9, 6.0)
	m._prop("fantasy/Barrel_Apples", Vector3(-13.8, 0, -7.0), 0.0, 1.0, 10.0)
	m._prop("fantasy/FarmCrate_Carrot", Vector3(-19.6, 0, -7.0), 0.4, 1.2, 4.0)
	m._prop("fantasy/Bucket_Wooden_1", Vector3(-11.0, 0, -6.6), 0.0, 1.2, 1.5)
	# Well and training ground.
	m._model("village/Well", Vector3(-10.0, 0, 9.0), 0.0, 2.4)
	for p in [Vector3(15.0, 0, 13.5), Vector3(18.0, 0, 13.5), Vector3(21.0, 0, 13.5)]:
		m._prop("fantasy/Dummy", p, PI, 1.05, 9.0)
	m._prop("fantasy/WeaponStand", Vector3(12.0, 0, 15.5), PI, 1.1, 14.0)
	m._model("blaster/Target_Large", Vector3(24.0, 0, 16.5), PI, 2.6, true, "none")
	# Smithy and stables against the walls (solid blocks of cover).
	m._model("village/Blacksmith", Vector3(-20.5, 0, 13.6), PI * 0.5, 1.7)
	m._prop("fantasy/Anvil", Vector3(-16.4, 0, 11.4), 0.6, 1.1, 30.0)
	m._model("village/Cart", Vector3(21.5, 0, -1.5), 0.5, 2.6)
	for p in [Vector3(23.6, 0, 2.2), Vector3(24.4, 0, 3.4), Vector3(23.4, 0.9, 2.9)]:
		m._box(p + Vector3(0, 0.45, 0), Vector3(1.4, 0.9, 1.0), "hay")
	m._model("village/Bonfire_Lit", Vector3(-9.0, 0, -1.0), 0.0, 3.0, true, "none")
	m._glow(Vector3(-9.0, 1.0, -1.0), Color(1.0, 0.55, 0.2), 9.0, 1.6)
	for p in [Vector3(-11.4, 0, -1.0), Vector3(-9.0, 0, 1.6)]:
		m._prop("fantasy/Bench", p, PI * 0.5 if p.z == -1.0 else 0.0, 0.8, 9.0)
	# Powder kegs: shoot them.
	for p in [Vector3(-25.4, 0, 6.0), Vector3(9.5, 0, -17.2), Vector3(25.5, 0, -8.5)]:
		m._prop("toon/Prop/Exploding_Barrel", p, 0.0, 1.0, 10.0)


static func _outside(m) -> void:
	# Siege camp in front of the south gate (and, mirrored, the north one).
	m._model("castle/Siege_Catapult", Vector3(-13.0, 0, -29.5), -1.1, 3.6)
	m._model("castle/Siege_Trebuchet", Vector3(17.0, 0, -27.6), -1.9, 3.4)
	m._model("castle/Siege_Ram", Vector3(7.0, 0, -26.0), PI * 0.5, 2.6)
	m._model("castle/Siege_Ballista_Demolished", Vector3(-24.0, 0, -27.0), 0.4, 2.8, true, "none")
	m._camp(Vector3(-36.0, 0, -27.0))
	for p in [Vector3(-8.0, 0, -27.5), Vector3(-9.2, 0, -26.4), Vector3(20.5, 0, -27.0)]:
		m._prop("fantasy/Barrel", p, 0.0, 1.0, 12.0)
	# Palisade stakes as cover on the approach.
	m._box(Vector3(-7.0, 0.75, -25.5), Vector3(4.0, 1.5, 0.5), "deck")
	m._box(Vector3(9.5, 0.75, -31.0), Vector3(0.5, 1.5, 4.0), "deck")
	# The village side: a couple of cottages east of the wall (mirrored west).
	m._model("village/House_1", Vector3(38.0, 0, -8.0), -PI * 0.5, 2.3)
	m._model("village/House_3", Vector3(38.5, 0, 9.0), -PI * 0.5, 2.6)
	m._model("village/Hay", Vector3(34.0, 0, 1.0), 0.0, 6.0)
	m._model("village/Fence", Vector3(34.0, 0, 16.0), 0.0, 4.0)
	m._model("village/Fence", Vector3(37.2, 0, 16.0), 0.0, 4.0)
	# Woods and rocks in the corners.
	m._forest(Rect2(33.5, 24.5, 10.5, 8.0), 12)
	m._forest(Rect2(-44.0, 22.0, 12.0, 10.0), 10)
	for p in [Vector3(33.0, 0, -24.0), Vector3(40.0, 0, -20.0), Vector3(-41.0, 0, -4.0)]:
		m._model("castle/Rocks_Large", p, m._rng.randf() * TAU, 3.0)

