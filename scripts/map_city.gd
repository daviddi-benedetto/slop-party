extends RefCounted
## Layout 9: HIGHTOWN (200 x 140 m), a medieval city that grew upwards:
## timber-and-plaster towers five to nine storeys tall, built from the
## Quaternius Medieval Village MegaKit (assets/models/kit_medieval), around a
## market square. Plays as Frontline (team bases at x = +/-90 from
## map_front.gd, flags A / B / C) and as a Rounds / Gun Game free-for-all.
##
## Point symmetric like every map (mirror = true copies (x, z) to (-x, -z)).
## Everything below is written for the +X half.
##
##   avenue        z = -7..7 the full width (vehicles drive base to base)
##   cross streets x = 44..56 and z = 30..42
##   market square around flag B (0, 0); flags A (-50, 36) / C (50, -36)
##     sit on street crossings
##   towers        _tower(): kit walls as visuals, our own invisible boxes
##                 for collision (with real door / window / arch openings),
##                 plank floors, a switchback stair core up to a flat roof
##                 with railings (or a tiled pitched roof on the houses)
##
## Kit scale: the kit's 2 m grid and 3.12 m walls are scaled by S = 1.25 so
## doorways suit our animals: modules M = 2.5 m, storeys H = 3.9 m.

const Front = preload("res://scripts/map_front.gd")
const Models = preload("res://scripts/models.gd")

const K := "kit_medieval/"
const S := 1.25
const M := 2.5
const H := 3.9
const WALL_T := 0.45            # collision thickness of a wall
const RUN := 5.4                # length of one stair flight

## [centre x, centre z, modules along x, modules along z, storeys, roof]
## (+X half; each is mirrored). Roofs: "flat" (a roof terrace with railings,
## reached by the stairs) or "pitched" (kit tiled roof; footprint must match
## one of the kit's roof sizes, see _roof_piece).
const BUILDINGS := [
	[24.0, 20.0, 6, 6, 7, "flat"],
	[39.0, 19.0, 3, 4, 4, "pitched"],
	[30.0, -20.0, 8, 4, 5, "flat"],
	[25.0, 53.0, 6, 6, 8, "flat"],
	[39.5, 53.0, 3, 6, 3, "pitched"],
	[22.0, -53.0, 4, 6, 6, "flat"],
	[37.0, -53.0, 4, 4, 4, "pitched"],
	[65.0, 20.0, 6, 8, 6, "flat"],
	[63.0, 53.0, 4, 6, 4, "pitched"],
	[65.0, -20.0, 4, 6, 5, "flat"],
	[65.0, -53.0, 6, 6, 9, "flat"],
	[0.0, 53.0, 8, 6, 9, "flat"],
	[0.0, 24.0, 4, 3, 3, "pitched"],
]

const FFA_SPAWNS := [Vector3(10, 0.1, 3), Vector3(30, 0.1, -3), Vector3(50, 0.1, 2), Vector3(50, 0.1, 20),
	Vector3(50, 0.1, -20), Vector3(12, 0.1, 36), Vector3(36, 0.1, 36), Vector3(66, 0.1, 37), Vector3(14, 0.1, -36),
	Vector3(46, 0.1, 62), Vector3(9, 0.1, 19), Vector3(76, 0.1, 6)]

## Rounds rides (unarmed), +X half: [type, position, yaw (0 faces -Z)].
const FFA_VEHICLES := [["bike", Vector3(18, 0.3, -2.5), -PI * 0.5], ["buggy", Vector3(50, 0.3, -12), 0.0],
	["bike", Vector3(50, 0.3, 26), PI]]


static func build(m) -> void:
	_streets(m)
	var seed_i := 0
	for b in BUILDINGS:
		seed_i += 1
		_tower(m, Vector3(b[0], 0, b[1]), b[2], b[3], b[4], b[5], seed_i)
	_square(m)
	Front._base(m)
	_greenery(m)
	m.flags = [Vector3(-50, 0, 36), Vector3(0, 0, 0), Vector3(50, 0, -36)]
	m.bases = [Vector3(-90, 0, 0), Vector3(90, 0, 0)]
	m._spawns([Vector3(88, 0.1, 6), Vector3(88, 0.1, -6), Vector3(94, 0.1, 0), Vector3(84, 0.1, 18)])
	m._spawns(FFA_SPAWNS)
	for v in FFA_VEHICLES:
		var yaw: float = v[2]
		m.ffa_vehicle_spots.append([v[0], Transform3D(Basis(Vector3.UP, yaw), v[1])])
		m.ffa_vehicle_spots.append([v[0], Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(-v[1].x, v[1].y, -v[1].z))])
	# Weapons up high (roof terraces) and in the square; health in the streets.
	m._pickups([["weapon", Vector3(24, 7 * H + 0.05, 20)], ["weapon", Vector3(65, 9 * H + 0.05, -53)], ["weapon", Vector3(6, 0.05, -6)],
		["health", Vector3(50, 0.05, 8)], ["health", Vector3(36, 0.05, 36)], ["weapon", Vector3(30, 5 * H + 0.05, -20)],
		["health", Vector3(24, 3 * H + 0.05, 24)]])


# --------------------------------------------------------------------------
# Streets and the square
# --------------------------------------------------------------------------

static func _streets(m) -> void:
	m._surface(Rect2(-100, -7, 200, 14), 0.01, "path", false)
	m._surface(Rect2(44, -70, 12, 140), 0.011, "path")
	m._surface(Rect2(-74, 30, 148, 12), 0.012, "path", false)
	m._surface(Rect2(-74, -42, 148, 12), 0.012, "path", false)
	m._surface(Rect2(-14, -16, 28, 32), 0.013, "path", false)
	for r in [Rect2(-100, -7.5, 200, 15), Rect2(44, -70, 12, 140), Rect2(-56, -70, 12, 140), Rect2(-74, 29.5, 148, 13),
			Rect2(-74, -42.5, 148, 13), Rect2(-14.5, -16.5, 29, 33)]:
		m.no_grass.append(r)
	# Gutter kerbs along the avenue (decor only).
	for x in range(-96, 97, 8):
		if absf(x) > 16:
			m._visual(Vector3(x, 0.03, 7.2), Vector3(7.6, 0.06, 0.3), "trim")
			m._visual(Vector3(x, 0.03, -7.2), Vector3(7.6, 0.06, 0.3), "trim")
	# Street lanterns on posts at the crossings.
	for p in [Vector3(43, 0, 8.5), Vector3(57, 0, -8.5), Vector3(15, 0, 29), Vector3(43, 0, 43), Vector3(57, 0, 29)]:
		_lantern_post(m, p)


static func _lantern_post(m, p: Vector3) -> void:
	m._cyl(p, 0.12, 3.6, "metal")
	m._model("fantasy/Lantern_Wall", p + Vector3(0, 2.4, 0), 0.0, 1.6, true, "none")


## The market square around flag B: a well, stalls, carts, crates, benches.
## The flag itself (0, 0) stays clear.
static func _square(m) -> void:
	m._fixed("village/Well", Vector3(8.5, 0, 9), 0.4, 3.0)
	var stalls := [[Vector3(-9, 0, 12), 0.0, 1], [Vector3(-3, 0, 12.5), 0.0, 2], [Vector3(11.5, 0, -3), -PI * 0.5, 1]]
	for st in stalls:
		m._fixed("village/Market_Stand_%d" % st[2], st[0], st[1], 3.0)
	m._fixed("village/Cart", Vector3(-11.5, 0, 3.5), 1.2, 3.2)
	m._fixed("fantasy/FarmCrate_Apple", Vector3(-6.5, 0, 12.6), 0.2, 1.4)
	m._fixed("fantasy/Barrel_Apples", Vector3(-1, 0, 13), 0.0, 1.4)
	m._fixed("village/Bench_1", Vector3(5, 0, -12.5), PI, 2.2)
	m._fixed("village/Hay", Vector3(12, 0, 12.5), 0.3, 2.4)
	m._fixed("village/Bell_Tower", Vector3(-12, 0, -12.5), 0.0, 1.6)


## Trees in the gaps and woods beyond the city edge.
static func _greenery(m) -> void:
	for p in [Vector3(14, 0, 9.5), Vector3(14, 0, -9.5), Vector3(45, 0, 28), Vector3(55, 0, -28), Vector3(30, 0, 39),
			Vector3(52, 0, 66), Vector3(8, 0, 66)]:
		m._tree(p, 1.3)
	m._forest(Rect2(76, 44, 22, 24), 40)
	m._forest(Rect2(76, -68, 22, 28), 46)
	m._lawn(Rect2(-100, -70, 200, 140), false)


# --------------------------------------------------------------------------
# Towers
# --------------------------------------------------------------------------

## One building: c = centre on the ground, nx / nz modules, n storeys.
static func _tower(m, c: Vector3, nx: int, nz: int, n: int, roof: String, seed_i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * seed_i + 31
	var w := nx * M
	var d := nz * M
	var x0 := c.x - w * 0.5
	var z0 := c.z - d * 0.5
	var x1 := x0 + w
	var z1 := z0 + d
	var rect := Rect2(x0, z0, w, d)
	m.roofs.append(rect)
	m.roofs.append(Rect2(-rect.end.x, -rect.end.y, w, d))
	m.no_grass.append(rect.grow(0.6))
	m.no_grass.append(Rect2(-rect.end.x, -rect.end.y, w, d).grow(0.6))
	if roof == "pitched" and _roof_piece(nx, nz) == "":
		roof = "flat"
	# Stair core along the -X wall: two strips (A, B), flights alternate.
	var xa := x0 + 0.45 + 1.25
	var xb := xa + 2.5
	var zs := z0 + 1.4
	var flights := n if roof == "flat" else n - 1
	var core := Rect2(x0, z0, 5.9, RUN + 2.8)
	m._surface(rect.grow(-0.1), 0.02, "deck")
	for s in n:
		var y := s * H
		var mat := "UnevenBrick" if s == 0 or (s % 4 == 0) else "Plaster"
		for side in 4:
			_side(m, rng, side, x0, z0, x1, z1, nx, nz, s, y, mat, core)
		var corner := "Corner_Exterior_Brick" if s == 0 else "Corner_Exterior_Wood"
		for cx in [x0, x1]:
			for cz in [z0, z1]:
				m._model(K + corner, Vector3(cx, y, cz), 0.0, S, true, "none")
		if s > 0:
			var hole := _flight_rect(s - 1, xa, xb, zs)
			m._slab(Rect2(x0 + 0.2, z0 + 0.2, w - 0.4, d - 0.4), y, "deck", [hole])
		_furnish(m, rng, x0, z0, x1, z1, y, core, s)
	for k in flights:
		var even := k % 2 == 0
		var sx := xa if even else xb
		m._stairs(Vector3(sx, k * H, zs + RUN * 0.5), Vector3(RUN, H, 2.2), -PI * 0.5 if even else PI * 0.5, "deck")
		# Bots: the flight as an explicit nav link (both mirror copies).
		var lo := Vector3(sx, k * H, zs - 0.5 if even else zs + RUN + 0.5)
		var hi := Vector3(sx, (k + 1) * H, zs + RUN + 0.5 if even else zs - 0.5)
		m.nav_links.append([lo, hi])
		m.nav_links.append([Vector3(-lo.x, lo.y, -lo.z), Vector3(-hi.x, hi.y, -hi.z)])
	var top := n * H
	if roof == "flat":
		m._slab(Rect2(x0 - 0.1, z0 - 0.1, w + 0.2, d + 0.2), top, "path", [_flight_rect(n - 1, xa, xb, zs)])
		_railings(m, x0, z0, x1, z1, nx, nz, top)
		# A chimney stack or two for the skyline.
		m._model(K + "Prop_Chimney", Vector3(x1 - 1.4, top, z1 - 1.4), 0.0, S, true, "box")
	else:
		_pitched_roof(m, c, nx, nz, x0, z0, x1, z1, top)


## The floor rectangle a flight occupies (cut out of the floor above it).
static func _flight_rect(k: int, xa: float, xb: float, zs: float) -> Rect2:
	var x := xa if k % 2 == 0 else xb
	return Rect2(x - 1.2, zs - 0.05, 2.4, RUN + 0.1)


## One storey of one side: kit wall pieces plus collision boxes with the
## real openings. side 0 = +Z (front), 1 = -Z, 2 = -X, 3 = +X.
static func _side(m, rng: RandomNumberGenerator, side: int, x0: float, z0: float, x1: float, z1: float, nx: int, nz: int,
		s: int, y: float, mat: String, core: Rect2) -> void:
	var along_x := side < 2
	var count := nx if along_x else nz
	var yaw: float = [0.0, PI, -PI * 0.5, PI * 0.5][side]
	var openings: Array = []
	for i in count:
		var t := (i + 0.5) * M
		var pos: Vector3
		match side:
			0: pos = Vector3(x0 + t, y, z1)
			1: pos = Vector3(x1 - t, y, z0)
			2: pos = Vector3(x0, y, z1 - t)
			_: pos = Vector3(x1, y, z0 + t)
		var in_core := core.grow(0.5).has_point(Vector2(pos.x + (1.0 if side == 2 else 0.0), pos.z))
		var kind := _pick_kind(rng, side, i, count, s, in_core)
		var piece := ""
		match kind:
			"door": piece = "Wall_%s_Door_Round" % mat
			"balcony": piece = "Wall_%s_Door_Flat" % mat
			"arch": piece = "Wall_Arch"
			"wide": piece = "Wall_%s_Window_Wide_%s" % [mat, "Round" if (i + s) % 2 == 0 else "Flat"]
			"thin": piece = "Wall_%s_Window_Thin_Round" % mat
			"grid": piece = "Wall_Plaster_WoodGrid" if mat == "Plaster" else "Wall_UnevenBrick_Straight"
			_: piece = "Wall_%s_Straight" % mat
		m._model(K + piece, pos, yaw, S, true, "none")
		var along := pos.x if along_x else pos.z
		match kind:
			"door", "balcony":
				openings.append([along, 1.45, 0.0, 2.75])
			"arch":
				openings.append([along, 2.0, 0.0, 3.2])
			"wide":
				openings.append([along, 1.9, 1.2, 3.1])
				if rng.randf() < 0.35 and s > 0:
					m._model(K + "WindowShutters_Wide_%s_Open" % ("Round" if (i + s) % 2 == 0 else "Flat"), pos, yaw, S, true, "none")
			"thin":
				m._model(K + "Window_Thin_Round1", pos, yaw, S, true, "none")
		if kind == "balcony":
			_balcony(m, pos, yaw)
		if kind == "door" or kind == "wide":
			# Furniture stays out of doorways and from under windows.
			var inward := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1.2)
			var cpos: Vector3 = pos + inward
			m._keep_clear(Rect2(cpos.x - 1.5, cpos.z - 1.5, 3.0, 3.0), y - 0.3, y + 2.6, true)
	# Collision: one box per solid stretch, sunk slightly inside the face.
	var out := 1.0 if side == 0 or side == 3 else -1.0
	var a: float = (x0 if along_x else z0) - 0.2
	var b: float = (x1 if along_x else z1) + 0.2
	for seg in m._wall_segments(a, b, H, openings):
		var length: float = seg[1] - seg[0]
		var hh: float = seg[3] - seg[2]
		if length < 0.02 or hh < 0.02:
			continue
		var mid: float = (seg[0] + seg[1]) * 0.5
		var cy: float = y + (seg[2] + seg[3]) * 0.5
		if along_x:
			var z: float = (z1 if side == 0 else z0) - out * 0.13
			_solid(m, Vector3(mid, cy, z), Vector3(length, hh, WALL_T))
		else:
			var x: float = (x0 if side == 2 else x1) - out * 0.13
			_solid(m, Vector3(x, cy, mid), Vector3(WALL_T, hh, length))


## Which kind of wall module goes here.
static func _pick_kind(rng: RandomNumberGenerator, side: int, i: int, count: int, s: int, in_core: bool) -> String:
	var middle := i == count / 2
	if s == 0:
		if in_core:
			return "plain"
		if middle and (side < 2 or count >= 4):
			return "door"
		if side == 0 and count >= 4:
			return "arch"            # an arcade of shop fronts on the street side
		return "wide" if i % 2 == 0 else "plain"
	if not in_core and side < 2 and rng.randf() < 0.12:
		return "balcony"
	match (i + s * 2 + side) % 4:
		0, 2: return "wide"
		1: return "thin"
		_: return "grid"


## A small balcony outside an upper-floor door: plank floor, kit railing.
static func _balcony(m, pos: Vector3, yaw: float) -> void:
	var rot := Basis(Vector3.UP, yaw)
	var floor_c: Vector3 = pos + rot * Vector3(0, -0.1, 0.75)
	m._box(floor_c, Vector3(M, 0.2, 1.4) if absf(sin(yaw)) < 0.5 else Vector3(1.4, 0.2, M), "deck")
	m._model(K + "Balcony_Cross_Straight", pos + rot * Vector3(0, 0, 0.2), yaw, S, true, "none")
	var rail: Vector3 = pos + rot * Vector3(0, 0.7, 1.4)
	_solid(m, rail, Vector3(M, 1.2, 0.2) if absf(sin(yaw)) < 0.5 else Vector3(0.2, 1.2, M))


## Railings around a flat roof terrace (kit balcony rails, invisible box).
static func _railings(m, x0: float, z0: float, x1: float, z1: float, nx: int, nz: int, y: float) -> void:
	for i in nx:
		var x := x0 + (i + 0.5) * M
		m._model(K + "Balcony_Cross_Straight", Vector3(x, y, z1 - 1.0 * S - 0.05), 0.0, S, true, "none")
		m._model(K + "Balcony_Cross_Straight", Vector3(x1 - (i + 0.5) * M, y, z0 + 1.0 * S + 0.05), PI, S, true, "none")
	for i in nz:
		var z := z0 + (i + 0.5) * M
		m._model(K + "Balcony_Cross_Straight", Vector3(x0 + 1.0 * S + 0.05, y, z1 - (i + 0.5) * M), -PI * 0.5, S, true, "none")
		m._model(K + "Balcony_Cross_Straight", Vector3(x1 - 1.0 * S - 0.05, y, z), PI * 0.5, S, true, "none")
	_solid(m, Vector3((x0 + x1) * 0.5, y + 0.6, z1 - 0.1), Vector3(x1 - x0, 1.2, 0.2))
	_solid(m, Vector3((x0 + x1) * 0.5, y + 0.6, z0 + 0.1), Vector3(x1 - x0, 1.2, 0.2))
	_solid(m, Vector3(x0 + 0.1, y + 0.6, (z0 + z1) * 0.5), Vector3(0.2, 1.2, z1 - z0))
	_solid(m, Vector3(x1 - 0.1, y + 0.6, (z0 + z1) * 0.5), Vector3(0.2, 1.2, z1 - z0))


## The kit's tiled roof for this footprint ("" if the kit has none).
static func _roof_piece(nx: int, nz: int) -> String:
	var name := "Roof_RoundTiles_%dx%d" % [nx * 2, nz * 2]
	var ok := ["Roof_RoundTiles_4x4", "Roof_RoundTiles_4x6", "Roof_RoundTiles_4x8", "Roof_RoundTiles_6x6", "Roof_RoundTiles_6x8",
		"Roof_RoundTiles_6x10", "Roof_RoundTiles_6x12", "Roof_RoundTiles_6x14", "Roof_RoundTiles_8x8", "Roof_RoundTiles_8x10",
		"Roof_RoundTiles_8x12", "Roof_RoundTiles_8x14"]
	return name if name in ok else ""


static func _pitched_roof(m, c: Vector3, nx: int, nz: int, x0: float, z0: float, x1: float, z1: float, top: float) -> void:
	var piece := _roof_piece(nx, nz)
	m._model(K + piece, Vector3(c.x, top, c.z), 0.0, S, true, "none")
	var gable := "Roof_Front_Brick%d" % (nx * 2)
	m._model(K + gable, Vector3(c.x, top, z1), 0.0, S, true, "none")
	m._model(K + gable, Vector3(c.x, top, z0), PI, S, true, "none")
	# Ceiling under the roof and a prism collider so you can stand on it.
	m._slab(Rect2(x0 + 0.2, z0 + 0.2, x1 - x0 - 0.4, z1 - z0 - 0.4), top, "deck")
	var h: float = Models.bounds(K + piece).end.y * S
	var a := (x1 - x0) * 0.5 + 0.2
	var b := (z1 - z0) * 0.5 + 0.2
	var pts := PackedVector3Array([Vector3(-a, 0, -b), Vector3(a, 0, -b), Vector3(-a, 0, b), Vector3(a, 0, b), Vector3(0, h, -b), Vector3(0, h, b)])
	for p in [Vector3(c.x, top, c.z), Vector3(-c.x, top, -c.z)]:
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = p
		m._body.add_child(cs)
	m._model(K + "Prop_Chimney", Vector3(x1 - 1.6, top, c.z + 1.0), 0.0, S, true, "none")


## A few dungeon-kit props on each floor, away from the stairs.
static func _furnish(m, rng: RandomNumberGenerator, x0: float, z0: float, x1: float, z1: float, y: float, core: Rect2, s: int) -> void:
	var kinds := [["kit_dungeon/barrel_large", 0.55], ["kit_dungeon/crates_stacked", 0.6], ["kit_dungeon/table_medium_decorated_A", 0.6],
		["kit_dungeon/box_large", 0.6], ["kit_dungeon/barrel_small_stack", 0.7], ["kit_dungeon/table_long_tablecloth_decorated_A", 0.6]]
	var count := 2 + rng.randi() % 2
	for i in count:
		for attempt in 6:
			var p := Vector3(rng.randf_range(x0 + 1.6, x1 - 1.6), y, rng.randf_range(z0 + 1.6, z1 - 1.6))
			if core.grow(1.0).has_point(Vector2(p.x, p.z)):
				continue
			# Hug a wall: snap the nearer axis to the wall.
			if rng.randf() < 0.7:
				if minf(p.x - x0, x1 - p.x) < minf(p.z - z0, z1 - p.z):
					p.x = x0 + 1.3 if p.x - x0 < x1 - p.x else x1 - 1.3
				else:
					p.z = z0 + 1.3 if p.z - z0 < z1 - p.z else z1 - 1.3
			var k: Array = kinds[rng.randi() % kinds.size()]
			m._fixed(k[0], p, rng.randf() * TAU, k[1])
			break


## An invisible collision box (both mirror copies).
static func _solid(m, pos: Vector3, size: Vector3) -> void:
	m._collider(pos, size)
	m._collider(Vector3(-pos.x, pos.y, -pos.z), size)
