extends RefCounted
## Layouts for the maps based on real places. Each function receives the
## map.gd node `m` and builds with its helpers (_box, _building, _stairs,
## _slab, _tunnel, _basement, _tree, ...). See map.gd for the conventions:
## point symmetry via mirror=true, ground holes via m._hole(), material keys
## from the theme.
##
##   museum(m)   MUSEUM   indoor hall with a skylit ceiling, a dinosaur
##                        skeleton, a balcony ring reached by two grand
##                        staircases, galleries under the balconies, display
##                        cases and statues, and two underground vaults.
##   stadium(m)  STADIUM  football pitch with markings and goals, running
##                        track, climbable bleachers, scoreboard platforms,
##                        dugouts, floodlights, training gear for cover, and
##                        locker rooms underground.
##   suburb(m)   SUBURB   a street crossing with houses (two storeys, stairs,
##                        porches, garages with roof access), fenced yards,
##                        pools, parked cars, street lamps, a
##                        roundabout, and a storm drain under the road.

const DEPTH := 3.6


# --------------------------------------------------------------------------
# MUSEUM
# --------------------------------------------------------------------------

static func museum(m) -> void:
	var hx: float = m.half_x
	var hz: float = m.half_z
	# Ceiling with three skylights (glazed, so the sun still comes through).
	var skylights := [Rect2(-15, -3, 8, 6), Rect2(7, -3, 8, 6), Rect2(-3, -3, 6, 6)]
	m._slab(Rect2(-hx, -hz, hx * 2.0, hz * 2.0), 11.3, "ceiling", skylights, false)
	for r in skylights:
		var c: Vector2 = r.get_center()
		m._visual(Vector3(c.x, 11.12, c.y), Vector3(r.size.x, 0.04, r.size.y), "glass")
		m._visual(Vector3(c.x, 11.1, c.y), Vector3(0.15, 0.2, r.size.y), "dark")
		m._visual(Vector3(c.x, 11.1, c.y), Vector3(r.size.x, 0.2, 0.15), "dark")
	m._box(Vector3(0, 10.9, hz - 0.05), Vector3(hx * 2.0, 0.25, 0.1), "gold", true, 0.0, false)
	m._box(Vector3(hx - 0.05, 10.9, 0), Vector3(0.1, 0.25, hz * 2.0), "gold", true, 0.0, false)

	# Balcony ring at 4.2 m on all four sides, with marble balustrades.
	m._slab(Rect2(-hx, 15, hx * 2.0, 5), 4.2, "deck", [], true, 0.4)
	m._slab(Rect2(21, -15, 5, 30), 4.2, "deck", [], true, 0.4)
	m._wall_x(15.1, -21.0, 21.0, 4.2, 1.0, "block_a", [[-10.0, 3.4, 0.0, 1.0]], true, 0.2)
	m._wall_z(20.9, -15.0, 15.0, 4.2, 1.0, "block_a", [], true, 0.2)
	m._box(Vector3(0, 5.25, 15.1), Vector3(42.0, 0.1, 0.32), "gold", true, 0.0, false)
	# Grand staircases up to the north and south balconies.
	m._stairs(Vector3(-10, 0, 11.5), Vector3(7, 4.2, 3.2), -PI * 0.5, "block_a")
	m._box(Vector3(-11.75, 0.6, 11.5), Vector3(0.25, 1.2, 7.0), "gold", true, 0.0, false)
	m._box(Vector3(-8.25, 0.6, 11.5), Vector3(0.25, 1.2, 7.0), "gold", true, 0.0, false)
	# Columns under the balcony edges.
	for x in [-21.0, -15.0, -5.0, 5.0, 15.0, 21.0]:
		m._cyl(Vector3(x, 0, 15.35), 0.45, 3.85, "block_a")
		m._cyl(Vector3(x, 3.6, 15.35), 0.6, 0.25, "gold", true, false)
	for z in [-9.0, -3.0, 3.0, 9.0]:
		m._cyl(Vector3(21.35, 0, z), 0.45, 3.85, "block_a")
		m._cyl(Vector3(21.35, 3.6, z), 0.6, 0.25, "gold", true, false)
	# Galleries under the balconies: red walls and partitions.
	m._box(Vector3(0, 2.1, hz - 0.08), Vector3(hx * 2.0, 4.2, 0.1), "block_b", true, 0.0, false)
	m._box(Vector3(hx - 0.08, 2.1, 0), Vector3(0.1, 4.2, 30.0), "block_b", true, 0.0, false)
	m._box(Vector3(hx - 0.08, 2.1, 17.55), Vector3(0.1, 4.2, 4.9), "block_b", true, 0.0, false)
	m._box(Vector3(-hx + 0.08, 2.1, 17.55), Vector3(0.1, 4.2, 4.9), "block_b", true, 0.0, false)
	m._box(Vector3(-15, 2.1, 17.6), Vector3(0.3, 4.2, 4.8), "block_b")
	m._box(Vector3(15, 2.1, 17.6), Vector3(0.3, 4.2, 4.8), "block_b")
	m._box(Vector3(23.6, 2.1, 0), Vector3(4.8, 4.2, 0.3), "block_b")
	m._box(Vector3(0, 8.0, hz - 0.08), Vector3(hx * 2.0, 6.0, 0.1), "teal", true, 0.0, false)

	# The dinosaur skeleton on its plinth (centre, not mirrored).
	m._box(Vector3(0, 0.25, 0), Vector3(11, 0.5, 4.5), "block_a", false)
	m._box(Vector3(0, 0.52, 0), Vector3(11.1, 0.06, 4.6), "gold", false, 0.0, false)
	var spine := [Vector3(-5.6, 2.2, 0), Vector3(-3.6, 2.9, 0), Vector3(-1.2, 3.4, 0), Vector3(1.4, 3.5, 0), Vector3(3.2, 3.9, 0), Vector3(4.2, 4.7, 0), Vector3(4.9, 5.0, 0)]
	for i in spine.size() - 1:
		m._rod(spine[i], spine[i + 1], 0.16 - i * 0.012, "bone", false)
	m._box(Vector3(5.3, 5.0, 0), Vector3(1.2, 0.6, 0.55), "bone", false, 0.0, false)
	m._box(Vector3(5.5, 4.65, 0), Vector3(0.9, 0.2, 0.45), "bone", false, 0.0, false)
	for side in [-1.0, 1.0]:
		for leg in [[Vector3(-1.0, 3.2, 0.5), Vector3(-0.7, 1.8, 0.75), Vector3(-1.2, 0.55, 0.75)],
				[Vector3(2.6, 3.4, 0.5), Vector3(2.8, 2.0, 0.7), Vector3(2.4, 0.55, 0.7)]]:
			var a: Vector3 = leg[0] * Vector3(1, 1, side)
			var b: Vector3 = leg[1] * Vector3(1, 1, side)
			var c: Vector3 = leg[2] * Vector3(1, 1, side)
			m._rod(a, b, 0.14, "bone", false)
			m._rod(b, c, 0.12, "bone", false)
			m._collider((b + c) * 0.5, Vector3(0.3, 1.4, 0.3))
		for i in 6:
			var x := -0.6 + i * 0.62
			var top := Vector3(x, 3.4 + i * 0.03, 0)
			m._rod(top, Vector3(x + 0.1, 2.9, 0.85 * side), 0.05, "bone", false)
			m._rod(Vector3(x + 0.1, 2.9, 0.85 * side), Vector3(x + 0.25, 2.2, 0.55 * side), 0.045, "bone", false)
	for p in [Vector3(-6.2, 0, -2.9), Vector3(6.2, 0, 2.9), Vector3(-6.2, 0, 2.9), Vector3(6.2, 0, -2.9)]:
		m._cyl(p, 0.06, 1.0, "gold", false, false)
		m._ball(p + Vector3(0, 1.05, 0), Vector3.ONE * 0.09, "gold", false)

	# Display cases with gold artefacts, statues, benches, potted trees.
	var finds := [["fantasy/Chalice", 2.4], ["fantasy/Vase_4", 1.4], ["fantasy/Vase_2", 0.9]]
	var fi := 0
	for p in [Vector3(-16, 0, -9), Vector3(-16, 0, 8), Vector3(-6, 0, -11)]:
		m._box(p + Vector3(0, 0.5, 0), Vector3(1.3, 1.0, 1.3), "block_c")
		m._box(p + Vector3(0, 1.0, 0), Vector3(1.36, 0.05, 1.36), "gold", true, 0.0, false)
		m._box(p + Vector3(0, 1.5, 0), Vector3(1.1, 1.0, 1.1), "glass")
		m._model(finds[fi][0], p + Vector3(0, 1.03, 0), 0.6 * fi, finds[fi][1], true, "none")
		fi += 1
	for p in [Vector3(-11, 0, -4), Vector3(-19, 0, 2)]:
		# Broken classical columns either side of each statue.
		for sgn in [-1.0, 1.0]:
			m._model("retro/Column_Damaged", p + Vector3(sgn * 1.5, 0, 0), 0.5 * sgn, Vector3(3.5, 2.4, 3.5), true)
		m._box(p + Vector3(0, 0.6, 0), Vector3(1.4, 1.2, 1.4), "block_a")
		m._cyl(p + Vector3(0, 1.2, 0), 0.35, 1.3, "block_a", true, false, 0.28)
		m._ball(p + Vector3(0, 2.75, 0), Vector3.ONE * 0.3, "block_a")
		m._rod(p + Vector3(0.2, 2.3, 0), p + Vector3(0.65, 2.9, 0.1), 0.08, "block_a")
		m._collider(p + Vector3(0, 1.6, 0), Vector3(0.8, 1.0, 0.8))
	for p in [Vector3(-7, 0, 5.5), Vector3(-13, 0, -13)]:
		for i in 3:
			m._model("furniture/Bench_Cushion", p + Vector3(-0.88 + i * 0.88, 0, 0), 0.0, 2.15, true)
	for p in [Vector3(-17.5, 0, 12.0), Vector3(-2.0, 0, -13.5)]:
		m._cyl(p, 0.7, 0.8, "block_c", true, true, 0.55)
		m._tree(p + Vector3(0, 0.8, 0), 0.75)
	m._bush(Vector3(-23.5, 0, 12.5), 0.9)

	# Paintings around the upper walls and in the galleries.
	var art := _painting_materials()
	var k := 0
	for x in [-18.0, -9.0, 0.0, 9.0, 18.0]:
		_painting(m, Vector3(x, 7.6, hz - 0.14), art[k % art.size()], false)
		k += 1
	for z in [-10.0, 0.0, 10.0]:
		_painting(m, Vector3(hx - 0.14, 7.6, z), art[k % art.size()], true)
		k += 1
	for x in [-20.0, -8.0, 8.0, 20.0]:
		_painting(m, Vector3(x, 2.4, hz - 0.2), art[k % art.size()], false)
		k += 1
	# Banners hanging over the balconies.
	for x in [-6.0, 6.0]:
		m._box(Vector3(x, 8.8, 14.9), Vector3(1.4, 3.6, 0.05), "teal", true, 0.0, false)
		m._box(Vector3(x, 10.7, 14.9), Vector3(1.6, 0.12, 0.12), "gold", true, 0.0, false)

	_galleries(m)

	# Vaults under the floor.
	m._basement(Rect2(-19, -7, 11, 6))
	m._box(Vector3(-10.5, -DEPTH + 0.3, -2.0), Vector3(1.2, 0.6, 0.6), "gold")
	m._box(Vector3(-10.5, -DEPTH + 0.75, -2.0), Vector3(0.8, 0.3, 0.45), "gold", true, 0.0, false)

	# Lighting: chandeliers and wall lamps (on at every time of day indoors).
	var inside := 1.0 / maxf(m.light_scale, 0.55)
	for p in [Vector3(-12, 8.8, 0), Vector3(0, 9.6, 0)]:
		var mirror: bool = p.x != 0.0
		m._cyl(p + Vector3(0, 0.3, 0), 0.04, 1.8, "gold", mirror, false)
		m._cyl(p, 1.2, 0.12, "gold", mirror, false)
		m._cyl(p + Vector3(0, -0.1, 0), 1.0, 0.1, "lamp", mirror, false)
		m._glow(p + Vector3(0, -0.6, 0), Color(1.0, 0.85, 0.65), 20.0, 2.6 * inside, mirror)
	for x in [-20.0, -10.0, 0.0, 10.0, 20.0]:
		m._glow(Vector3(x, 3.2, 17.5), Color(1.0, 0.8, 0.6), 7.0, 1.2 * inside)
		m._glow(Vector3(x, 7.0, 17.5), Color(1.0, 0.8, 0.6), 9.0, 1.2 * inside)
	m._glow(Vector3(23.5, 3.2, -8), Color(1.0, 0.8, 0.6), 7.0, 1.2 * inside)
	m._glow(Vector3(23.5, 3.2, 8), Color(1.0, 0.8, 0.6), 7.0, 1.2 * inside)

	m._spawns([Vector3(-18, 0.1, -12), Vector3(-5, 0.1, 12), Vector3(0, 4.3, 17.5), Vector3(23.5, 4.3, -8), Vector3(-23.5, 0.1, 17.5),
		Vector3(-10, -DEPTH + 0.1, -2.5)])
	m._pickups([["weapon", Vector3(0, 4.2, 18.5)], ["weapon", Vector3(23.5, 4.2, 4.0)], ["health", Vector3(-12, -DEPTH, -3.0)], ["weapon", Vector3(-8, 0, -7)]])


## The rooms under the balconies, each with its own purpose (all mirrored,
## so each appears twice): a cafe in the north-west bay, an armoury hall with
## a catapult and a ballista on plinths behind ropes in the long north bay,
## a gift shop in the north-east corner, antiquities on column pedestals
## along the east gallery and coin vitrines along the west one.
static func _galleries(m) -> void:
	var f := 2.15
	# Cafe: counter with coffee machine, bar stools, a table (counter and
	# table fixed, seats loose).
	for i in 3:
		m._fixed("furniture/Kitchen_Bar", Vector3(-16.7, 0, 16.4 + i * 1.16), -PI * 0.5, f * 1.25)
	for i in 2:
		m._prop("furniture/Stool_Bar", Vector3(-17.7, 0, 16.9 + i * 1.16), 0.0, f, 5.0)
	m._fixed("furniture/Kitchen_Coffee_Machine", Vector3(-16.7, 1.14, 16.4), PI * 0.5, f, true, "none")
	m._fixed("furniture/Kitchen_Fridge", Vector3(-15.65, 0, 19.3), -PI * 0.5, f)
	m._fixed("furniture/Table_Round", Vector3(-20.6, 0, 17.6), 0.0, f)
	m._prop("furniture/Chair", Vector3(-21.7, 0, 17.6), PI * 0.5, f, 5.0)
	m._prop("furniture/Chair_Cushion", Vector3(-19.5, 0, 17.6), -PI * 0.5, f, 5.0)
	m._fixed("furniture/Potted_Plant", Vector3(-25.4, 0, 19.4), 0.0, f)
	# Armoury: siege engines on plinths, roped off, weapon racks on the wall.
	for ex in [["castle/Siege_Catapult", -4.0, 4.6], ["castle/Siege_Ballista", 3.0, 4.4]]:
		var x: float = ex[1]
		var w: float = ex[2]
		m._box(Vector3(x, 0.15, 17.7), Vector3(w, 0.3, 3.0), "block_a")
		m._box(Vector3(x, 0.31, 17.7), Vector3(w + 0.06, 0.03, 3.06), "gold", true, 0.0, false)
		m._model(ex[0], Vector3(x, 0.3, 17.7), 0.0, 2.2, true, "none")
		m._collider(Vector3(x, 1.5, 17.7), Vector3(w - 0.6, 2.4, 2.4))
		for sx in [-1.0, 1.0]:
			m._cyl(Vector3(x + sx * w * 0.5, 0, 15.85), 0.05, 0.95, "gold", true, false)
			m._ball(Vector3(x + sx * w * 0.5, 1.0, 15.85), Vector3.ONE * 0.08, "gold")
		m._rod(Vector3(x - w * 0.5, 0.85, 15.85), Vector3(x + w * 0.5, 0.85, 15.85), 0.03, "block_b")
	for x in [-11.5, 11.5]:
		m._model("medieval/Weapon_Rack", Vector3(x, 0, 19.45), 0.0, 2.6, true)
	# Gift shop: shelves on the back wall, a till, a book table.
	for i in 4:
		var bx := 22.0 + i * 0.86
		# (The furniture kit's origin is a corner: offset to centre it.)
		m._model("furniture/Bookcase_Open", Vector3(bx + 0.43, 0, 19.28), PI, f, true)
		for lvl in 4:
			m._model("fantasy/BookGroup_Medium_%d" % (1 + (i + lvl) % 3), Vector3(bx, 0.07 + lvl * 0.465, 19.5), PI, 0.7, true, "none", false)
	for i in 2:
		m._fixed("furniture/Kitchen_Bar", Vector3(17.6 + i * 1.16, 0, 17.0), 0.0, f * 1.25)
	m._fixed("furniture/Laptop", Vector3(17.6, 1.14, 17.0), PI, f, true, "none")
	m._fixed("furniture/Table_Cross_Cloth", Vector3(20.4, 0, 16.4), 0.0, f)
	m._fixed("furniture/Books", Vector3(20.4, 0.75, 16.4), 0.4, f, true, "none")
	# Antiquities on column pedestals along the east gallery.
	var antiques := [["fantasy/Vase_2", 0.9], ["fantasy/Vase_4", 1.3], ["fantasy/Chalice", 2.6]]
	for i in 3:
		var z := 3.5 + i * 4.0
		m._box(Vector3(25.2, 0.55, z), Vector3(0.7, 1.1, 0.7), "block_a")
		m._box(Vector3(25.2, 0.06, z), Vector3(0.8, 0.12, 0.8), "gold", true, 0.0, false)
		m._box(Vector3(25.2, 1.12, z), Vector3(0.8, 0.05, 0.8), "gold", true, 0.0, false)
		m._model(antiques[i][0], Vector3(25.2, 1.15, z), 0.7 * i, antiques[i][1], true, "none")
		m._glow(Vector3(24.2, 2.6, z), Color(1.0, 0.88, 0.7), 2.6, 0.5 / maxf(m.light_scale, 0.55))
	for i in 3:
		m._model("furniture/Bench_Cushion", Vector3(23.2, 0, 6.4 + i * 0.86), PI * 0.5, f, true)
	m._model("fantasy/BookStand", Vector3(22.6, 0, 13.4), -0.6, 1.0, true)
	# Coin vitrines along the west gallery.
	for z in [3.5, 8.5]:
		m._box(Vector3(-25.2, 0.45, z), Vector3(0.8, 0.9, 1.8), "block_c")
		m._box(Vector3(-25.2, 1.08, z), Vector3(0.76, 0.36, 1.76), "glass")
		for k in 5:
			var cz: float = z - 0.6 + k * 0.3
			m._cyl(Vector3(-25.25 + 0.1 * (k % 2), 0.9, cz), 0.07, 0.04 + 0.03 * ((k * 7) % 4), "gold", true, false)
		m._box(Vector3(-25.05, 0.95, z + 0.55), Vector3(0.12, 0.08, 0.26), "gold", true, 0.0, false)
		m._box(Vector3(-25.05, 0.95, z - 0.55), Vector3(0.12, 0.08, 0.26), "gold", true, 0.0, false)


static func _painting_materials() -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var palettes := [
		[Color(0.85, 0.3, 0.2), Color(0.95, 0.75, 0.3), Color(0.2, 0.2, 0.35)],
		[Color(0.15, 0.35, 0.6), Color(0.9, 0.9, 0.85), Color(0.95, 0.6, 0.2)],
		[Color(0.2, 0.45, 0.3), Color(0.85, 0.8, 0.5), Color(0.5, 0.2, 0.3)],
		[Color(0.55, 0.2, 0.5), Color(0.2, 0.7, 0.75), Color(0.95, 0.9, 0.7)],
	]
	for pal in palettes:
		var img := Image.create(96, 72, false, Image.FORMAT_RGB8)
		img.fill(pal[2].darkened(0.3))
		for i in 7:
			var col: Color = pal[i % 3]
			if rng.randf() < 0.5:
				img.fill_rect(Rect2i(rng.randi_range(0, 70), rng.randi_range(0, 50), rng.randi_range(14, 50), rng.randi_range(10, 34)), col)
			else:
				var c := Vector2(rng.randi_range(10, 86), rng.randi_range(10, 62))
				var r := rng.randf_range(6.0, 18.0)
				for y in 72:
					for x in 96:
						if Vector2(x, y).distance_to(c) < r:
							img.set_pixel(x, y, col)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.roughness = 0.8
		out.append(mat)
	return out


## A framed canvas on a wall; `on_x` = the wall runs along Z (east/west walls).
static func _painting(m, pos: Vector3, mat: Material, on_x: bool) -> void:
	var frame := Vector3(0.06, 2.0, 2.7) if on_x else Vector3(2.7, 2.0, 0.06)
	var canvas := Vector3(0.03, 1.7, 2.4) if on_x else Vector3(2.4, 1.7, 0.03)
	var inward := Vector3(-signf(pos.x), 0, 0) if on_x else Vector3(0, 0, -signf(pos.z))
	m._box(pos, frame, "gold", true, 0.0, false)
	var box := BoxMesh.new()
	box.size = canvas
	for s in [pos + inward * 0.04, Vector3(-pos.x, pos.y, -pos.z) - inward * 0.04]:
		m._add(box, mat, Transform3D(Basis(), s))
	m._glow(pos + inward * 1.2 + Vector3(0, 1.1, 0), Color(1.0, 0.9, 0.75), 4.0, 0.8 / maxf(m.light_scale, 0.55))


# --------------------------------------------------------------------------
# STADIUM
# --------------------------------------------------------------------------

static func stadium(m) -> void:
	m._basement(Rect2(36.0, 9.0, 9.0, 8.0))
	# Running track around the pitch, with lane lines.
	m._surface(Rect2(-38, 18, 76, 5), 0.01, "path")
	m._surface(Rect2(32, -18, 6, 36), 0.01, "path")
	for i in 4:
		var off := 18.0 + 1.25 * i
		m._visual(Vector3(0, 0.02, off), Vector3(76.0 - 2.5 * i * 0.0, 0.01, 0.06), "line")
		m._visual(Vector3(0, 0.02, -off), Vector3(76.0, 0.01, 0.06), "line")
		m._visual(Vector3(32.0 + 1.25 * i + 0.62, 0.02, 0), Vector3(0.06, 0.01, 36.0), "line")
		m._visual(Vector3(-32.0 - 1.25 * i - 0.62, 0.02, 0), Vector3(0.06, 0.01, 36.0), "line")
	# Pitch markings.
	m._visual(Vector3(0, 0.02, 17.9), Vector3(64, 0.01, 0.14), "line")
	m._visual(Vector3(0, 0.02, -17.9), Vector3(64, 0.01, 0.14), "line")
	m._visual(Vector3(31.9, 0.02, 0), Vector3(0.14, 0.01, 36), "line")
	m._visual(Vector3(-31.9, 0.02, 0), Vector3(0.14, 0.01, 36), "line")
	m._visual(Vector3(0, 0.02, 0), Vector3(0.14, 0.01, 36), "line")
	var circle := TorusMesh.new()
	circle.inner_radius = 5.9
	circle.outer_radius = 6.05
	circle.rings = 64
	circle.ring_segments = 3
	m._add(circle, m._mats["line"], Transform3D(Basis.from_scale(Vector3(1, 0.05, 1)), Vector3(0, 0.02, 0)), false)
	m._box(Vector3(25.5, 0.02, 0), Vector3(0.14, 0.01, 20), "line", true, 0.0, false)
	m._box(Vector3(28.7, 0.02, 10), Vector3(6.4, 0.01, 0.14), "line", true, 0.0, false)
	m._box(Vector3(28.7, 0.02, -10), Vector3(6.4, 0.01, 0.14), "line", true, 0.0, false)
	m._box(Vector3(29.6, 0.02, 0), Vector3(0.14, 0.01, 9), "line", true, 0.0, false)
	m._box(Vector3(30.75, 0.02, 4.5), Vector3(2.3, 0.01, 0.14), "line", true, 0.0, false)
	m._box(Vector3(30.75, 0.02, -4.5), Vector3(2.3, 0.01, 0.14), "line", true, 0.0, false)
	m._lawn(Rect2(-32, -18, 64, 36), false)

	# Goals with nets.
	var net := StandardMaterial3D.new()
	net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net.albedo_color = Color(0.95, 0.95, 0.95, 0.28)
	net.cull_mode = BaseMaterial3D.CULL_DISABLED
	for z in [-3.66, 3.66]:
		m._cyl(Vector3(32.0, 0, z), 0.07, 2.44, "metal")
		m._rod(Vector3(32.0, 2.44, z), Vector3(34.0, 0.0, z), 0.04, "metal")
	m._rod(Vector3(32.0, 2.44, -3.66), Vector3(32.0, 2.44, 3.66), 0.07, "metal")
	m._collider(Vector3(34.2, 1.2, 0), Vector3(0.1, 2.4, 7.4))
	var net_box := BoxMesh.new()
	net_box.size = Vector3(0.02, 2.44, 7.32)
	for s in [1.0, -1.0]:
		m._add(net_box, net, Transform3D(Basis(Vector3.BACK, -0.88), Vector3(33.0 * s, 1.22, 0)), false)
		var side := BoxMesh.new()
		side.size = Vector3(2.0, 2.44, 0.02)
		for z in [-3.66, 3.66]:
			m._add(side, net, Transform3D(Basis(), Vector3(33.0 * s, 1.22, z)), false)

	# Advertising boards along the touchlines (low cover, glowing faces).
	for i in 5:
		var x := -24.0 + i * 12.0
		m._box(Vector3(x, 0.5, 18.9), Vector3(9.0, 1.0, 0.3), "block_c")
		m._box(Vector3(x, 0.55, 18.73), Vector3(8.6, 0.7, 0.04), "accent_a" if i % 2 == 0 else "accent_b", true, 0.0, false)

	# Bleachers along both long sides: climbable stepped seating.
	m._stairs(Vector3(0, 0, 26.6), Vector3(6, 4.5, 60), -PI * 0.5, "block_b")
	for i in [2, 5, 8]:
		m._box(Vector3(0, 4.5 * (i + 1) / 18.0 + 0.01, 23.6 + 6.0 * (i + 0.5) / 18.0), Vector3(60.0, 0.03, 0.3), "seat_red", true, 0.0, false)
	m._box(Vector3(0, 5.1, 29.7), Vector3(60.6, 1.2, 0.3), "block_a")
	m._box(Vector3(30.15, 2.6, 26.6), Vector3(0.3, 5.2, 6.2), "block_a")
	m._box(Vector3(-30.15, 2.6, 26.6), Vector3(0.3, 5.2, 6.2), "block_a")
	for x in [-20.0, 0.0, 20.0]:
		m._cyl(Vector3(x, 4.5, 29.3), 0.12, 3.6, "metal", true, false)
	m._box(Vector3(0, 8.2, 28.0), Vector3(60.0, 0.15, 3.6), "block_c", true, 0.0, false)

	# Scoreboard platforms at both ends (vantage points).
	m._slab(Rect2(39.5, -7, 5, 14), 3.4, "deck")
	for z in [-6.5, 6.5]:
		m._box(Vector3(42.0, 1.7, z), Vector3(0.5, 3.4, 0.5), "block_c")
	m._stairs(Vector3(36.5, 0, -5.8), Vector3(6, 3.4, 1.6), 0.0, "deck")
	m._wall_z(39.6, -7.0, 7.0, 3.4, 1.0, "block_c", [[-5.8, 1.7, 0.0, 1.0]], true, 0.12)
	m._box(Vector3(44.6, 7.2, 0), Vector3(0.6, 7.6, 12.0), "block_c")
	m._box(Vector3(44.27, 7.6, 0), Vector3(0.05, 5.6, 11.2), "accent_b", true, 0.0, false)
	m._box(Vector3(44.25, 8.6, -2.5), Vector3(0.05, 1.4, 3.0), "accent_a", true, 0.0, false)

	# Dugouts on the track.
	m._box(Vector3(-10, 1.2, 21.8), Vector3(6, 2.4, 0.3), "block_a")
	m._box(Vector3(-12.85, 1.2, 20.6), Vector3(0.3, 2.4, 2.6), "block_a")
	m._box(Vector3(-7.15, 1.2, 20.6), Vector3(0.3, 2.4, 2.6), "block_a")
	m._box(Vector3(-10, 2.5, 20.6), Vector3(6.4, 0.15, 2.8), "glass")
	m._box(Vector3(-10, 0.4, 21.3), Vector3(5.2, 0.15, 0.6), "block_b")

	# Floodlight masts in the corners.
	for p in [Vector3(44.5, 0, 28.5), Vector3(44.5, 0, -28.5)]:
		m._cyl(p, 0.35, 22.0, "metal")
		var head: Vector3 = p + Vector3(0, 22.5, 0)
		var yaw := atan2(-p.x, -p.z)
		m._box(head, Vector3(4.5, 2.4, 0.5), "dark", true, yaw + PI * 0.5, false)
		m._box(head + Vector3(-p.x, 0, -p.z).normalized() * 0.28, Vector3(4.1, 2.0, 0.08), "lamp", true, yaw + PI * 0.5, false)
		if m.night_amount > 0.0:
			for s in [p, Vector3(-p.x, p.y, -p.z)]:
				var spot := SpotLight3D.new()
				spot.light_color = Color(1.0, 0.97, 0.9)
				spot.light_energy = 9.0 * m.night_amount
				spot.spot_range = 110.0
				spot.spot_angle = 38.0
				spot.spot_attenuation = 0.6
				m.add_child(spot)
				spot.look_at_from_position(s + Vector3(0, 22.0, 0), Vector3(s.x * 0.15, 0, s.z * 0.1))

	# Training gear on the pitch: sleds, mannequins, ball carts, hurdles.
	for p in [Vector3(-20, 0, -8), Vector3(-13, 0, 7), Vector3(-6, 0, -12), Vector3(-24, 0, 10), Vector3(-9, 0, 0.5)]:
		m._box(p + Vector3(0, 0.6, 0), Vector3(1.6, 1.2, 1.0), "crate", true, 0.3)
	for p in [Vector3(-16, 0, -2), Vector3(-27, 0, -4), Vector3(-3, 0, 9)]:
		m._cyl(p, 0.35, 1.9, "seat_red", true, true, 0.25)
		m._ball(p + Vector3(0, 2.05, 0), Vector3.ONE * 0.22, "line")
	for p in [Vector3(-18, 0, 13.5), Vector3(-28, 0, 14.5)]:
		m._box(p + Vector3(0, 0.45, 0), Vector3(3.0, 0.08, 0.08), "line")
		m._box(p + Vector3(-1.4, 0.22, 0), Vector3(0.06, 0.45, 0.4), "metal", true, 0.0, false)
		m._box(p + Vector3(1.4, 0.22, 0), Vector3(0.06, 0.45, 0.4), "metal", true, 0.0, false)

	# Locker rooms underground in the corners (the room itself is built first).
	for i in 6:
		m._box(Vector3(37.0 + i * 1.2, -DEPTH + 1.0, 16.6), Vector3(1.1, 2.0, 0.6), "block_b")
	m._box(Vector3(40.5, -DEPTH + 0.25, 14.0), Vector3(5.0, 0.12, 0.6), "block_c")

	# The club stand in the corner outside the track: a bar downstairs, a
	# trophy lounge upstairs, a viewing balcony on the pitch side and a roof
	# terrace (arch.gd "clubhouse").
	m._building(Vector3(-41.8, 0, 15.2), 7.6, 11.0, 2, "wall", {"style": "clubhouse", "roof": "block_c"})
	# Trees and a lawn behind it.
	for p in [Vector3(-42, 0, 25.5), Vector3(-44.6, 0, 22.6)]:
		m._tree(p, 1.1)
	m._bush(Vector3(-39.5, 0, 26.5), 1.2)
	m._lawn(Rect2(-46, 21.5, 8, 8.5))

	m._spawns([Vector3(35, 0.1, 20.5), Vector3(-20, 4.7, 29.0), Vector3(41.5, 3.5, 0), Vector3(36, 0.1, -14), Vector3(-28, 0.1, 21.0),
		Vector3(20, 0.1, -10), Vector3(40, -DEPTH + 0.1, 14.5)])
	m._pickups([["weapon", Vector3(41.5, 3.4, 3.0)], ["health", Vector3(-10, 0, 20.4)], ["weapon", Vector3(10, 4.5, 29.0)], ["health", Vector3(43, -DEPTH, 13)]])
	m._pickups([["weapon", Vector3(0, 0, 0)]], false)


# --------------------------------------------------------------------------
# SUBURB
# --------------------------------------------------------------------------

static func suburb(m) -> void:
	# Storm drain under the main road (holes first, so surfaces are cut around them).
	m._tunnel(0.0, -30.0, 30.0, false, 3.0)
	_pool(m, Rect2(11, 22.5, 9, 5))
	# Streets, sidewalks and road markings.
	m._surface(Rect2(-40, -4, 80, 8), 0.01, "road", false)
	m._surface(Rect2(-4, -30, 8, 26), 0.011, "road")
	m._surface(Rect2(-40, 4, 80, 2.5), 0.02, "path")
	m._surface(Rect2(4, 6.5, 2.5, 23.5), 0.02, "path")
	m._surface(Rect2(-6.5, 6.5, 2.5, 23.5), 0.02, "path")
	for x in range(-38, 38, 4):
		if absf(x + 1.0) > 6.0 and absf(x + 1.0) < 22.0 or absf(x + 1.0) > 31.0:
			m._visual(Vector3(x + 1.0, 0.022, 0), Vector3(2.0, 0.01, 0.16), "line")
	for z in range(8, 30, 4):
		m._visual(Vector3(0, 0.022, z + 1.0), Vector3(0.16, 0.01, 2.0), "line")
		m._visual(Vector3(0, 0.022, -z - 1.0), Vector3(0.16, 0.01, 2.0), "line")
	m._box(Vector3(0, 0.08, 4.05), Vector3(80, 0.16, 0.12), "block_a", true, 0.0, false)

	# Roundabout in the middle of the crossing.
	m._cyl(Vector3(0, 0, 0), 2.6, 0.45, "block_a", false)
	m._cyl(Vector3(0, 0.45, 0), 2.3, 0.04, "soil", false, false)
	m._tree(Vector3(0, 0.45, 0), 1.0, false)

	# --- North-east plot (mirrored: south-west) ---
	m._building(Vector3(16, 0, 15.5), 11.0, 9.0, 2, "siding0", {"pitched": true, "roof": "roof_red", "style": "house"})
	m._building(Vector3(25.1, 0, 15.5), 6.5, 9.0, 1, "siding0", {"roof": "block_c", "style": "garage"})
	m._surface(Rect2(22.2, 6.5, 6.0, 4.5), 0.02, "path")
	m._surface(Rect2(15.1, 6.5, 1.8, 4.5), 0.02, "path")
	m.no_grass.append_array([Rect2(22.2, 6.5, 6.0, 4.5), Rect2(15.1, 6.5, 1.8, 4.5), Rect2(-28.2, -11.0, 6.0, 4.5), Rect2(-16.9, -11.0, 1.8, 4.5)])
	# On the drive, clear of the garage porch.
	_car(m, Vector3(25.2, 0, 7.9), 0.0, "car_white")
	_fence_x(m, 6.9, 7.0, 15.0)
	_fence_x(m, 6.9, 17.0, 21.6)
	_fence_x(m, 20.6, 28.6, 39.8)
	_fence_z(m, 6.9, 20.6, 29.8)
	for p in [Vector3(8.6, 0, 9.0), Vector3(34.0, 0, 26.0), Vector3(37.0, 0, 21.8)]:
		m._tree(p, m._rng.randf_range(0.9, 1.3))
	for p in [Vector3(12.0, 0, 10.4), Vector3(19.5, 0, 10.4), Vector3(23.0, 0, 28.6), Vector3(30.0, 0, 28.8)]:
		m._bush(p, 1.0)
	m._cyl(Vector3(29.0, 0, 10.6), 0.32, 1.0, "block_c")
	m._box(Vector3(13.0, 0.6, 6.4), Vector3(0.3, 1.2, 0.3), "car_blue")
	m._lawn(Rect2(6.6, 6.6, 33.2, 4.3))
	m._lawn(Rect2(7.0, 20.8, 32.8, 9.0))

	# --- North-west plot (mirrored: south-east) ---
	m._building(Vector3(-21, 0, 16), 12.0, 9.0, 2, "siding1", {"pitched": true, "roof": "block_c", "style": "house"})
	m._slab(Rect2(-26.5, 9.6, 11.0, 1.9), 3.0, "deck", [], true, 0.25)
	# Porch posts at the ends only (one used to stand right in the doorway).
	for x in [-26.2, -15.8]:
		m._cyl(Vector3(x, 0, 9.8), 0.1, 2.75, "trim")
	m._building(Vector3(-33.5, 0, 14.5), 8.2, 8.6, 1, "siding2", {"roof": "block_c", "style": "store"})
	# A big tree in the back garden (the treehouse is gone: players spawned
	# up there and got stuck).
	m._tree(Vector3(-33, 0, 25), 1.9)
	# Basketball hoop on the drive.
	m._cyl(Vector3(-9.0, 0, 8.5), 0.08, 3.05, "metal")
	m._box(Vector3(-9.0, 3.35, 8.2), Vector3(1.8, 1.1, 0.06), "trim", true, 0.0, false)
	var hoop := TorusMesh.new()
	hoop.inner_radius = 0.21
	hoop.outer_radius = 0.24
	m._add(hoop, m._mats["car_red"], Transform3D(Basis(), Vector3(-9.0, 3.05, 7.9)))
	m._add(hoop, m._mats["car_red"], Transform3D(Basis(), Vector3(9.0, 3.05, -7.9)))
	_fence_x(m, 21.2, -39.8, -27.4)
	_fence_x(m, 6.9, -27.0, -15.6)
	for p in [Vector3(-38.0, 0, 9.0), Vector3(-12.0, 0, 26.0), Vector3(-24.0, 0, 27.5)]:
		m._tree(p, m._rng.randf_range(0.9, 1.3))
	for p in [Vector3(-14.0, 0, 11.0), Vector3(-28.4, 0, 11.0), Vector3(-17.0, 0, 21.8)]:
		m._bush(p, 1.1)
	m._lawn(Rect2(-39.8, 6.6, 33.2, 2.9))
	m._lawn(Rect2(-39.8, 21.4, 33.2, 8.4))

	# Parked cars, lamps, bins and hydrants along the streets.
	_car(m, Vector3(-26, 0, 2.7), 0.0, "car_red")
	_car(m, Vector3(14, 0, 2.7), 0.0, "car_blue")
	_car(m, Vector3(2.7, 0, 18.0), PI * 0.5, "car_black")
	for x in [-30.0, -10.0, 10.0, 30.0]:
		m._lamp_post(Vector3(x, 0, 5.6))
	m._lamp_post(Vector3(5.6, 0, 20.0))
	m._lamp_post(Vector3(-5.6, 0, 20.0))
	m._model("zombie/Prop/Fire_Hydrant", Vector3(20.0, 0, 5.8), 0.0, 1.1)
	m._model("zombie/Prop/Fire_Hydrant", Vector3(-20.0, 0, 5.8), PI, 1.1, false)
	m._model("zombie/Prop/Trash_Bag_1", Vector3(24.0, 0, 6.6), 0.4, 1.2, true, "none")
	m._model("zombie/Prop/Trash_Bag_2", Vector3(24.8, 0, 6.4), 1.2, 1.2, true, "none")

	m._spawns([Vector3(31, 0.1, 9.0), Vector3(34, 0.1, 24.0), Vector3(-36, 0.1, 8.0), Vector3(-29, 0.1, 27.0), Vector3(25.5, 3.5, 12.5),
		Vector3(17, 3.5, 13.0), Vector3(-25.5, 0.1, 23.5), Vector3(-15, -DEPTH + 0.1, 0.0)])
	m._pickups([["weapon", Vector3(13.5, 3.4, 17.5)], ["weapon", Vector3(-30.0, 0, 23.0)], ["health", Vector3(30, 0, 25.5)], ["health", Vector3(26.5, 3.4, 18.0)]])
	m._pickups([["weapon", Vector3(0, -DEPTH, 0)]], false)


## A picket fence along X at z (collidable, jumpable at 1.2 m).
static func _fence_x(m, z: float, x0: float, x1: float) -> void:
	var length := x1 - x0
	var mid := (x0 + x1) * 0.5
	m._collider(Vector3(mid, 0.6, z), Vector3(length, 1.2, 0.12))
	m._collider(Vector3(-mid, 0.6, -z), Vector3(length, 1.2, 0.12))
	m._box(Vector3(mid, 0.45, z), Vector3(length, 0.08, 0.06), "trim", true, 0.0, false)
	m._box(Vector3(mid, 0.95, z), Vector3(length, 0.08, 0.06), "trim", true, 0.0, false)
	var n := int(length / 0.22)
	for i in n + 1:
		m._box(Vector3(x0 + length * i / n, 0.6, z + 0.04), Vector3(0.09, 1.2, 0.03), "trim", true, 0.0, false)


static func _fence_z(m, x: float, z0: float, z1: float) -> void:
	var length := z1 - z0
	var mid := (z0 + z1) * 0.5
	m._collider(Vector3(x, 0.6, mid), Vector3(0.12, 1.2, length))
	m._collider(Vector3(-x, 0.6, -mid), Vector3(0.12, 1.2, length))
	m._box(Vector3(x, 0.45, mid), Vector3(0.06, 0.08, length), "trim", true, 0.0, false)
	m._box(Vector3(x, 0.95, mid), Vector3(0.06, 0.08, length), "trim", true, 0.0, false)
	var n := int(length / 0.22)
	for i in n + 1:
		m._box(Vector3(x + 0.04, 0.6, z0 + length * i / n), Vector3(0.03, 1.2, 0.09), "trim", true, 0.0, false)


## A parked car (Zombie Apocalypse kit model, chosen by paint colour). Climbable.
static func _car(m, pos: Vector3, yaw: float, paint: String) -> void:
	var model := "zombie/Vehicle/Vehicle_Sports"
	if paint == "car_blue":
		model = "zombie/Vehicle/Vehicle_Pickup"
	elif paint == "car_black" or paint == "car_white":
		model = "zombie/Vehicle/Vehicle_Truck" if paint == "car_white" else "zombie/Vehicle/Vehicle_Sports_Armored"
	# Model length runs along Z; the old cars ran along X.
	m._model(model, pos, yaw + PI * 0.5, 0.8)


## A sunken pool with a shallow ramp at its west end, tiled walls and water.
static func _pool(m, r: Rect2) -> void:
	var deep := 1.8
	var c := r.get_center()
	m._hole(r)
	m._box(Vector3(c.x, -deep - 0.25, c.y), Vector3(r.size.x + 0.4, 0.5, r.size.y + 0.4), "tile_blue")
	# (Walls a little inside the hole's edge: flush, they flickered.)
	var zf: float = m.ZF
	m._box(Vector3(c.x, -deep * 0.5, r.position.y - 0.1 + zf), Vector3(r.size.x + 0.4, deep, 0.2), "tile_blue")
	m._box(Vector3(c.x, -deep * 0.5, r.end.y + 0.1 - zf), Vector3(r.size.x + 0.4, deep, 0.2), "tile_blue")
	m._box(Vector3(r.position.x - 0.1 + zf, -deep * 0.5, c.y), Vector3(0.2, deep, r.size.y), "tile_blue")
	m._box(Vector3(r.end.x + 0.1 - zf, -deep * 0.5, c.y), Vector3(0.2, deep, r.size.y), "tile_blue")
	m._wedge(Vector3(r.position.x + 2.5, -deep, c.y), Vector3(5.0, deep, r.size.y), PI, "tile_blue", true, false)
	m._box(Vector3(c.x, -0.4, c.y), Vector3(r.size.x, 0.02, r.size.y), "water", true, 0.0, false)
	m._surface(Rect2(r.position.x - 1.0, r.position.y - 1.0, r.size.x + 2.0, r.size.y + 2.0), 0.02, "path")
	m.no_grass.append(r.grow(1.2))
	m.no_grass.append(Rect2(-r.end.x, -r.end.y, r.size.x, r.size.y).grow(1.2))
	m._glow(Vector3(c.x, -1.0, c.y), Color(0.4, 0.8, 1.0), 6.0, 1.2)
