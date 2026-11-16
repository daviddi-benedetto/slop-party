extends RefCounted
## Dedicated Zombies arena: a quarantined hospital campus with an outdoor
## service yard, multi-storey clinic, warehouse, motel, wooded perimeter and
## a lit underground utility route. Uses map.gd's shared collision/nav helpers.


static func build(m) -> void:
	# Roads, a broad emergency vehicle loop and a central courtyard.
	m._surface(Rect2(-70, -4.5, 140, 9.0), 0.012, "path", false)
	m._surface(Rect2(-4.5, -50, 9.0, 100), 0.014, "path", false)
	m._surface(Rect2(-27, -23, 54, 46), 0.02, "road", false)
	m.no_grass.append(Rect2(-70, -5, 140, 10))
	m.no_grass.append(Rect2(-5, -50, 10, 100))
	m.no_grass.append(Rect2(-28, -24, 56, 48))

	# Quarantine hospital: three navigable floors, open stairwells and a roof.
	m._building(Vector3(-20, 0, 2), 25, 19, 3, "block_a", {
		"mirror": false, "floor": "deck", "roof": "block_c", "furnish": true})
	# A broken annex, linked to the main clinic by an open covered walkway.
	m._building(Vector3(13, 0, 7), 16, 13, 2, "block_b", {
		"mirror": false, "floor": "deck", "roof": "block_c", "furnish": true})
	m._box(Vector3(-1.5, 2.7, 6.0), Vector3(16.5, 0.22, 2.3), "metal", false)
	for x in [-8.0, 5.0]:
		m._cyl(Vector3(x, 0, 6.0), 0.14, 2.7, "metal", false)

	# Freight warehouse with a loading bay and mezzanine, plus a long motel block.
	m._building(Vector3(38, 0, -16), 25, 17, 1, "block_c", {
		"mirror": false, "floor": "deck", "roof": "metal", "furnish": true})
	m._slab(Rect2(27, -22, 11, 8), 3.25, "deck",
		[Rect2(32 - 0.85, -18 - 2.95, 1.7, 5.9)], false, 0.25)
	m._stairs(Vector3(32, 0, -18), Vector3(5.5, 3.4, 1.35), -PI * 0.5, "deck", false)
	m._building(Vector3(-40, 0, -22), 19, 14, 2, "house", {
		"mirror": false, "pitched": true, "roof": "roof_red", "furnish": true})

	# Security checkpoint, perimeter fencing, floodlights, barricades and wrecks.
	m._wall_x(-40, -61, 61, 0, 2.3, "block_c", [[0, 8, 0, 2.1]], false, 0.25)
	m._wall_x(45, -61, 61, 0, 2.3, "block_c", [[-43, 7, 0, 2.1], [42, 7, 0, 2.1]], false, 0.25)
	m._wall_z(-61, -40, 45, 0, 2.3, "block_c", [[-4, 7, 0, 2.1]], false, 0.25)
	m._wall_z(61, -40, 45, 0, 2.3, "block_c", [[8, 7, 0, 2.1]], false, 0.25)
	m._box(Vector3(-4, 2.55, -40), Vector3(0.28, 0.22, 7.0), "beacon", false, 0.0, false)
	m._box(Vector3(-4, 2.55, 45), Vector3(0.28, 0.22, 7.0), "beacon", false, 0.0, false)
	for p in [Vector3(-8, 0, -34), Vector3(8, 0, -34), Vector3(-55, 0, 30), Vector3(55, 0, 28)]:
		m._lamp_post(p, false)
		m._glow(p + Vector3(0, 6.5, 0), Color(1.0, 0.22, 0.12), 13.0, 1.3, false)
	for p in [Vector3(-13, 0.5, -13), Vector3(12, 0.5, -12), Vector3(-49, 0.5, 3), Vector3(51, 0.5, 4)]:
		m._box(p, Vector3(3.0, 1.0, 1.0), "block_b", false, 0.15)
	for p in [Vector3(26, 0, 10), Vector3(-52, 0, -12), Vector3(48, 0, 28)]:
		m._model("toon/Prop/Debris_Broken_Car", p, m._rng.randf() * TAU, 1.0, false)
	for p in [Vector3(21, 0.6, -2), Vector3(24, 0.6, -2.5), Vector3(20, 0.6, -5)]:
		m._model("zombie/Prop/Container_Red", p, 0.0, Vector3(0.65, 0.72, 0.72), false, "none")

	# Utility tunnel below the courtyard and a small underground triage room.
	m._tunnel(-31, -34, 34, false, 4.0)
	m._basement(Rect2(18, 22, 17, 12), false)
	m._glow(Vector3(26, -1.6, 28), Color(0.8, 0.12, 0.08), 12.0, 1.5, false)

	# Woodland fringe beyond the fence keeps the large map from feeling empty.
	for p in [Vector3(-66, 0, -33), Vector3(-65, 0, -18), Vector3(-66, 0, 2), Vector3(-66, 0, 24),
		Vector3(66, 0, -32), Vector3(66, 0, -8), Vector3(66, 0, 16), Vector3(66, 0, 35),
		Vector3(-45, 0, 49), Vector3(-20, 0, 49), Vector3(8, 0, 49), Vector3(37, 0, 49)]:
		m._tree(p, m._rng.randf_range(1.0, 1.5))
	for p in [Vector3(-57, 0, -4), Vector3(-58, 0, 16), Vector3(57, 0, -24), Vector3(58, 0, 7), Vector3(43, 0, 39)]:
		m._bush(p, m._rng.randf_range(0.8, 1.3))

	m._spawns([
		Vector3(-20, 0.1, 2), Vector3(-14, 3.5, 6), Vector3(-27, 6.9, 0),
		Vector3(13, 0.1, 7), Vector3(38, 0.1, -16), Vector3(-40, 0.1, -22),
		Vector3(-20, -3.4, -31), Vector3(26, -3.4, 28), Vector3(48, 0.1, 20), Vector3(-52, 0.1, 22),
	], false)
	m._pickups([
		["weapon", Vector3(-20, 3.5, 2)], ["weapon", Vector3(38, 0, -16)],
		["health", Vector3(13, 0, 7)], ["health", Vector3(26, -3.6, 28)],
	], false)
