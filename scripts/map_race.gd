extends RefCounted
## Layout 10: RACEWAY, the Racing mode's circuit (racing.gd). A closed
## Catmull-Rom loop through CTRL is resampled every STEP metres into
## `m.race_path` (index 0 = the start / finish line, driving towards higher
## indices); racing.gd uses it for laps, places, resets and the CPU drivers.
##
## Built from that path: an asphalt ribbon W wide (overlapping thin slabs,
## which the world-space textures hide), red / white kerbs where it bends,
## red / white crash barriers RUNOFF beyond each edge (with collision, so
## cars stay on the circuit), a chequered start line under a gantry, grid
## boxes, a grandstand, tyre stacks and trees outside the barriers.
## Not mirrored: a circuit has one direction.

const W := 14.0                 # road width
const STEP := 3.0               # path sample spacing (m)
const RUNOFF := 3.0             # verge between road edge and barrier
const CTRL := [Vector3(-60, 0, -50), Vector3(10, 0, -56), Vector3(60, 0, -50), Vector3(84, 0, -28), Vector3(80, 0, 5),
	Vector3(56, 0, 16), Vector3(36, 0, 4), Vector3(14, 0, 16), Vector3(26, 0, 40), Vector3(0, 0, 56), Vector3(-50, 0, 56),
	Vector3(-82, 0, 36), Vector3(-86, 0, 2), Vector3(-66, 0, -22), Vector3(-86, 0, -40)]
const START := Vector3(-22, 0, -53)


static func build(m) -> void:
	var path := _resample(_smooth(_resample(_spline(CTRL), STEP), 40), STEP)
	# Start / finish on the long back straight.
	var best := 0
	for i in path.size():
		if path[i].distance_to(START) < path[best].distance_to(START):
			best = i
	var p0: Array = path.slice(best) + path.slice(0, best)
	m.race_path = p0
	if "--check-spawns" in OS.get_cmdline_user_args():
		var tight := 1e9
		for k in p0.size():
			var ang: float = _bend(p0, k) * 2.0
			if ang > 0.001:
				tight = minf(tight, 2.0 * STEP / ang)
		print("[raceway] tightest bend radius %.1f m (road half-width %.1f)" % [tight, W * 0.5])
	m.race_width = W
	var n := p0.size()
	# Everything that follows the curve is one continuous strip, sample to
	# sample (separate straight blocks left wedge-shaped gaps on the outside
	# of every bend).
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kerb_red := SurfaceTool.new()
	kerb_red.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kerb_white := SurfaceTool.new()
	kerb_white.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bar_red := SurfaceTool.new()
	bar_red.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bar_white := SurfaceTool.new()
	bar_white.begin(Mesh.PRIMITIVE_TRIANGLES)
	for st in [bar_red, bar_white]:
		st.set_smooth_group(-1)
	var off := W * 0.5 + RUNOFF
	for i in n:
		var j := (i + 1) % n
		var a: Vector3 = p0[i]
		var b: Vector3 = p0[j]
		var na := _normal(p0, i)
		var nb := _normal(p0, j)
		m.no_grass.append(Rect2(a.x - W * 0.5 - 1.5, a.z - W * 0.5 - 1.5, W + 3.0, W + 3.0))   # no grass on the asphalt
		# Asphalt.
		_flat_quad(road, a + na * W * 0.5, a - na * W * 0.5, b - nb * W * 0.5, b + nb * W * 0.5, 0.04)
		# Kerbs where it bends (red / white every sample).
		if _bend(p0, i) > 0.035 or _bend(p0, j) > 0.035:
			var ks: SurfaceTool = kerb_red if i % 2 == 0 else kerb_white
			for sgn in [1.0, -1.0]:
				var i0: float = W * 0.5 * sgn
				var i1: float = (W * 0.5 + 1.1) * sgn
				# Skip a piece that would flip over on the inside of a tight bend.
				if (b + nb * i0 - (a + na * i0)).dot(b - a) <= 0.0:
					continue
				_flat_quad(ks, a + na * i1, a + na * i0, b + nb * i0, b + nb * i1, 0.07)
		# Barriers both sides: a continuous wall with a convex collider per
		# panel; panels that would fold back over the road in a tight bend
		# are left out.
		for sgn in [1.0, -1.0]:
			var ea: Vector3 = a + na * sgn * off
			var eb: Vector3 = b + nb * sgn * off
			if ea.distance_to(eb) < 0.05 or _near_road(p0, (ea + eb) * 0.5, off - 1.0) or _near_road(p0, ea, off - 1.0) or _near_road(p0, eb, off - 1.0):
				continue
			var bs: SurfaceTool = bar_red if (i / 2) % 2 == 0 else bar_white
			_wall_panel(m, bs, ea, eb, na * sgn, nb * sgn, 0.5, 1.1)
	m._add(road.commit(), m._mats["road"], Transform3D(), false, 0, "track")
	m._add(kerb_red.commit(), m._mats["car_red"], Transform3D(), false, 0, "track")
	m._add(kerb_white.commit(), m._mats["trim"], Transform3D(), false, 0, "track")
	bar_red.generate_normals()
	bar_white.generate_normals()
	m._add(bar_red.commit(), m._mats["car_red"], Transform3D(), true, 0, "track")
	m._add(bar_white.commit(), m._mats["trim"], Transform3D(), true, 0, "track")
	_start_line(m, p0)
	_town(m, p0)
	_scenery(m, p0)
	# Grid slots (also spawn points, should anything need one).
	for slot in 6:
		var g := grid_slot(p0, slot)
		m.spawn_points.append(g[0] + Vector3(0, 0.3, 0))
		m._visual(g[0] + Vector3(0, 0.05, 0) + Basis(Vector3.UP, g[1]) * Vector3(0, 0, -2.2), Vector3(2.6, 0.04, 0.25), "trim", g[1])


## A flat quad at height y (corners in order round the edge), facing up.
static func _flat_quad(st: SurfaceTool, c0: Vector3, c1: Vector3, c2: Vector3, c3: Vector3, y: float) -> void:
	var q := [Vector3(c0.x, y, c0.z), Vector3(c1.x, y, c1.z), Vector3(c2.x, y, c2.z), Vector3(c3.x, y, c3.z)]
	# Wind so the face points up whichever way round the corners came.
	var up: bool = (q[1] - q[0]).cross(q[2] - q[0]).y > 0.0
	var tris := [0, 2, 1, 0, 3, 2] if up else [0, 1, 2, 0, 2, 3]
	for k in tris:
		st.set_normal(Vector3.UP)
		st.add_vertex(q[k])


## One barrier panel from ea to eb (outward normals na / nb), thickness t,
## height h: top and both faces, plus a matching convex collider. Ends are
## mitred by the per-sample normals, so neighbouring panels meet exactly.
static func _wall_panel(m, st: SurfaceTool, ea: Vector3, eb: Vector3, na: Vector3, nb: Vector3, t: float, h: float) -> void:
	var ai := ea - na * t * 0.5
	var ao := ea + na * t * 0.5
	var bi := eb - nb * t * 0.5
	var bo := eb + nb * t * 0.5
	var up := Vector3(0, h, 0)
	var pts := [ai, ao, bi, bo, ai + up, ao + up, bi + up, bo + up]
	# Faces as quads [a, b, c, d]; winding fixed below so each faces outwards.
	var centre := (ea + eb) * 0.5 + up * 0.5
	for f in [[0, 2, 6, 4], [1, 5, 7, 3], [4, 6, 7, 5]]:
		var q: Array = f.map(func(k): return pts[k])
		var nrm: Vector3 = (q[1] - q[0]).cross(q[2] - q[0])
		var mid: Vector3 = (q[0] + q[1] + q[2] + q[3]) * 0.25
		var order := [0, 1, 2, 0, 2, 3] if nrm.dot(mid - centre) < 0.0 else [0, 2, 1, 0, 3, 2]
		for k in order:
			st.add_vertex(q[k])
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(pts)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	m._body.add_child(cs)


## Grid slot `i` behind the line: [position, yaw] (two columns, staggered).
static func grid_slot(path: Array, i: int) -> Array:
	var back := 9.0 + (i / 2) * 8.0 + (i % 2) * 3.5
	var k := posmod(-int(round(back / STEP)), path.size())
	var p: Vector3 = path[k]
	var t: Vector3 = (path[(k + 1) % path.size()] - path[k]).normalized()
	var side := 1.0 if i % 2 == 0 else -1.0
	var pos: Vector3 = p + _normal(path, k) * side * 3.2
	return [pos, atan2(-t.x, -t.z)]


## True if q is within `r` of the centre line anywhere.
static func _near_road(path: Array, q: Vector3, r: float) -> bool:
	for p in path:
		if Vector2(p.x - q.x, p.z - q.z).length() < r:
			return true
	return false


## Left-hand normal of the path at sample i (unit, horizontal).
static func _normal(path: Array, i: int) -> Vector3:
	var n := path.size()
	var t: Vector3 = (path[(i + 1) % n] - path[posmod(i - 1, n)]).normalized()
	return Vector3(-t.z, 0, t.x)


## How sharply the path turns at sample i (radians between neighbours).
static func _bend(path: Array, i: int) -> float:
	var n := path.size()
	var a: Vector3 = (path[i] - path[posmod(i - 2, n)]).normalized()
	var b: Vector3 = (path[(i + 2) % n] - path[i]).normalized()
	return a.angle_to(b) * 0.5


static func _spline(ctrl: Array) -> Array:
	var out: Array = []
	var n := ctrl.size()
	for i in n:
		var p0: Vector3 = ctrl[posmod(i - 1, n)]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[(i + 1) % n]
		var p3: Vector3 = ctrl[(i + 2) % n]
		for s in 40:
			var t := s / 40.0
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	return out


## Round off kinks: each pass pulls every point a little towards the middle
## of its neighbours (the loop closes on itself), so no bend ends up tighter
## than the road is wide.
static func _smooth(pts: Array, passes: int) -> Array:
	var cur := pts.duplicate()
	var n := cur.size()
	for k in passes:
		var nxt: Array = []
		for i in n:
			var p: Vector3 = cur[i]
			var avg: Vector3 = ((cur[posmod(i - 1, n)] as Vector3) + (cur[(i + 1) % n] as Vector3)) * 0.5
			nxt.append(p.lerp(avg, 0.5))
		cur = nxt
	return cur


static func _resample(dense: Array, step: float) -> Array:
	var out: Array = [dense[0]]
	var acc := 0.0
	var n := dense.size()
	for i in n:
		var a: Vector3 = dense[i]
		var b: Vector3 = dense[(i + 1) % n]
		var seg := a.distance_to(b)
		var pos := 0.0
		while acc + (seg - pos) >= step:
			pos += step - acc
			acc = 0.0
			out.append(a.lerp(b, pos / seg))
		acc += seg - pos
	if out.size() > 1 and (out[-1] as Vector3).distance_to(out[0]) < step * 0.5:
		out.pop_back()
	return out


static func _start_line(m, path: Array) -> void:
	var p: Vector3 = path[0]
	var t: Vector3 = (path[1] - path[0]).normalized()
	var nrm := _normal(path, 0)
	var yaw := atan2(-t.z, t.x)
	# Chequered line: 2 rows across the road.
	var cols := 8
	for row in 2:
		for c in cols:
			var lat := -W * 0.5 + (c + 0.5) * W / cols
			var pos: Vector3 = p + nrm * lat + t * (row - 0.5) * 1.0 + Vector3(0, 0.07, 0)
			m._visual(pos, Vector3(1.0, 0.04, W / cols), "tyre" if (c + row) % 2 == 0 else "trim", yaw)
	# Gantry over the line.
	for sgn in [1.0, -1.0]:
		m._cyl(p + nrm * sgn * (W * 0.5 + 1.6), 0.25, 6.5, "metal", false)
	m._box(p + Vector3(0, 6.4, 0), Vector3(0.6, 1.4, W + 4.0), "car_red", false, atan2(-t.z, t.x) + 0.0)
	var label := Label3D.new()
	label.text = "SLOP PARTY GRAND PRIX"
	label.font_size = 140
	label.pixel_size = 0.012
	label.outline_size = 24
	label.modulate = Color(1.0, 0.92, 0.6)
	label.outline_modulate = Color(0.25, 0.05, 0.05)
	label.position = p + Vector3(0, 6.4, 0) - t * 0.35
	label.rotation.y = atan2(-t.x, -t.z)        # faces the cars coming up to the line
	m.add_child(label)
	var label2: Label3D = label.duplicate()
	label2.position = p + Vector3(0, 6.4, 0) + t * 0.35
	label2.rotation.y = atan2(t.x, t.z)
	m.add_child(label2)


## A little village in the infield and around the outside: the cute
## Quaternius village houses scaled up, plus medieval kit chimneys and
## lanterns. Each is kept clear of the road and barriers by its own size.
static func _town(m, path: Array) -> void:
	var Models = load("res://scripts/models.gd")
	var kinds := [["village/House_1", 4.2], ["village/House_2", 4.2], ["village/House_3", 4.2], ["village/House_4", 4.2],
		["village/Inn", 3.6], ["village/Blacksmith", 3.8], ["village/Mill", 3.4], ["village/Stable", 3.8], ["village/Bell_Tower", 3.2],
		["village/Sawmill", 3.6]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var placed: Array = []           # [Vector3, radius]
	var clear := W * 0.5 + RUNOFF + 1.5
	var count := 0
	for gx in range(-92, 93, 11):
		for gz in range(-62, 63, 11):
			var q := Vector3(gx + rng.randf_range(-3, 3), 0, gz + rng.randf_range(-3, 3))
			var k: Array = kinds[rng.randi() % kinds.size()]
			var b: AABB = Models.bounds(k[0])
			var r: float = maxf(b.size.x, b.size.z) * float(k[1]) * 0.5
			if absf(q.x) + r > 96.0 or absf(q.z) + r > 66.0:
				continue
			if _near_road(path, q, clear + r):
				continue
			var ok := true
			for pr in placed:
				if (pr[0] as Vector3).distance_to(q) < pr[1] + r + 2.5:
					ok = false
					break
			if not ok or rng.randf() < 0.25:
				continue
			# Face the nearest bit of road.
			var near: Vector3 = path[0]
			for p in path:
				if (p as Vector3).distance_to(q) < near.distance_to(q):
					near = p
			var yaw := atan2(near.x - q.x, near.z - q.z)
			m._model(k[0], q - Basis(Vector3.UP, yaw) * (Vector3(b.get_center().x, b.position.y, b.get_center().z) * float(k[1])), yaw, float(k[1]), false, "box")
			placed.append([q, r])
			count += 1
	print("[raceway] %d village buildings" % count)


static func _scenery(m, path: Array) -> void:
	var n := path.size()
	# A grandstand along the outside of the start straight.
	var p: Vector3 = path[4]
	var t: Vector3 = (path[5] - path[3]).normalized()
	var out := -_normal(path, 4)
	if out.dot(-p) > 0.0:
		out = -out                      # put it on the outer side
	var yaw := atan2(-t.z, t.x)
	for step in 4:
		var c: Vector3 = p + out * (W * 0.5 + RUNOFF + 4.0 + step * 1.6) + Vector3(0, 0.4 + step * 0.8, 0)
		m._box(c, Vector3(34.0, 0.8 + step * 1.6, 1.6), "block_a" if step % 2 == 0 else "trim", false, yaw)
	for i in 7:
		var fpos: Vector3 = p + out * (W * 0.5 + RUNOFF + 11.0) + t * (-15.0 + i * 5.0)
		m._cyl(fpos, 0.08, 5.0, "metal", false)
		m._box(fpos + Vector3(0, 4.3, 0) + t * 0.6, Vector3(0.05, 1.0, 1.2), ["car_red", "car_blue", "car_white", "accent_a"][i % 4], false, yaw + PI * 0.5, false)
	# Tyre stacks on the outside of the sharpest bends; trees beyond.
	var placed := 0
	for i in n:
		if _bend(path, i) > 0.09 and i % 3 == 0:
			var o := _normal(path, i)
			var nxt: Vector3 = path[(i + 6) % n]
			if o.dot(nxt - path[i]) > 0.0:
				o = -o                  # the outside of the bend
			var tp: Vector3 = path[i] + o * (W * 0.5 + RUNOFF + 1.4)
			for k in 3:
				m._cyl(tp + Vector3(0, k * 0.45, 0), 0.6, 0.42, "tyre", false, k == 0)
			placed += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var trees := 0
	var tries := 0
	while trees < 70 and tries < 900:
		tries += 1
		var q := Vector3(rng.randf_range(-94, 94), 0, rng.randf_range(-64, 64))
		var ok := true
		for j in range(0, n, 2):
			if (path[j] as Vector3).distance_to(q) < W * 0.5 + RUNOFF + 6.0:
				ok = false
				break
		if not ok:
			continue
		trees += 1
		if rng.randf() < 0.25:
			m._pine(q, rng.randf_range(1.0, 1.5), false)
		elif rng.randf() < 0.2:
			m._bush(q, rng.randf_range(1.0, 1.6), false)
		else:
			m._tree(q, rng.randf_range(1.0, 1.5), false)
