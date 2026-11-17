extends RefCounted
## The playable plush animals: shapes, colours and the mesher that turns them
## into smooth, seamless toy bodies.
##
## Each animal is a signed-distance field (round blobs smoothly melted
## together: a big head, a bean body, ears and a snout) that surface nets turns
## into one closed mesh, painted with vertex colours (belly, muzzle, inner
## ears, patches). The tail is a second, smaller mesh so it can wag. Eyes, nose,
## cheeks, arms and feet are added by character.gd as separate moving parts,
## placed on the surface with surface_z().
##
## The meshes are generated once by tools/make_plush.gd into
## assets/models/plush/*.res (so the game does not spend seconds on it at
## start-up); body() and tail() fall back to generating them in memory when a
## file is missing.
##
## Local space: feet at y = 0, facing -Z. Head centre (0, 1.3, -0.02).

const DIR := "res://assets/models/plush/"
const NAMES := ["bunny", "kitty", "pup", "bear", "fox", "panda", "duck"]
const HEAD := Vector3(0, 1.3, -0.02)
const CELL := 0.028

## Per-animal look used by character.gd and ui_kit.portrait().
##   fur / belly: main and light colours.  limb / paw: arm and foot colours.
##   eye: [x, y] of the eyes on the face.  nose: [y, colour] or [] for none.
const SPEC := [
	{"fur": Color(0.97, 0.95, 0.93), "belly": Color(1.0, 0.86, 0.88), "limb": Color(0.97, 0.95, 0.93), "paw": Color(1.0, 0.8, 0.84),
		"eye": [0.17, 1.34], "nose": [1.2, Color(1.0, 0.5, 0.6)]},
	{"fur": Color(0.98, 0.64, 0.32), "belly": Color(1.0, 0.94, 0.84), "limb": Color(0.98, 0.64, 0.32), "paw": Color(1.0, 0.94, 0.84),
		"eye": [0.18, 1.35], "nose": [1.21, Color(1.0, 0.55, 0.6)]},
	{"fur": Color(0.94, 0.62, 0.34), "belly": Color(1.0, 0.94, 0.86), "limb": Color(0.94, 0.62, 0.34), "paw": Color(1.0, 0.94, 0.86),
		"eye": [0.17, 1.36], "nose": [1.22, Color(0.12, 0.09, 0.1)]},
	{"fur": Color(0.58, 0.38, 0.24), "belly": Color(0.9, 0.74, 0.55), "limb": Color(0.58, 0.38, 0.24), "paw": Color(0.45, 0.28, 0.17),
		"eye": [0.17, 1.37], "nose": [1.22, Color(0.12, 0.08, 0.08)]},
	{"fur": Color(0.97, 0.46, 0.18), "belly": Color(1.0, 0.97, 0.94), "limb": Color(0.2, 0.15, 0.14), "paw": Color(0.2, 0.15, 0.14),
		"eye": [0.18, 1.36], "nose": [1.17, Color(0.12, 0.08, 0.08)]},
	{"fur": Color(0.97, 0.97, 0.96), "belly": Color(0.97, 0.97, 0.96), "limb": Color(0.13, 0.13, 0.15), "paw": Color(0.13, 0.13, 0.15),
		"eye": [0.17, 1.35], "nose": [1.22, Color(0.1, 0.1, 0.12)]},
	{"fur": Color(1.0, 0.86, 0.3), "belly": Color(1.0, 0.94, 0.62), "limb": Color(1.0, 0.86, 0.3), "paw": Color(1.0, 0.55, 0.15),
		"eye": [0.18, 1.38], "nose": []},
]

const INK := Color(0.13, 0.12, 0.14)

static var _cache := {}


## The body mesh of animal `kind` (cached).
static func body(kind: int) -> ArrayMesh:
	return _part(kind, "body")


## The tail mesh (origin at the tail root, which sits at TAIL_ROOT).
static func tail(kind: int) -> ArrayMesh:
	return _part(kind, "tail")


const TAIL_ROOT := Vector3(0, 0.42, 0.3)


static func _part(kind: int, part: String) -> ArrayMesh:
	var key := "%s_%s" % [NAMES[kind], part]
	if not _cache.has(key):
		var path := DIR + key + ".res"
		var m: ArrayMesh = load(path) if ResourceLoader.exists(path) else null
		if m == null:
			m = build(kind, part)
		_cache[key] = m
	return _cache[key]


## Where the surface is along a ray from the front (-Z) at (x, y): the z of
## the first point on the body, for placing eyes, nose and cheeks.
static func surface_z(kind: int, x: float, y: float) -> float:
	var z := -1.0
	for i in 64:
		var d := sdf(kind, Vector3(x, y, z))
		if d < 0.001:
			break
		z += maxf(d, 0.004)
	return z


# ---------------------------------------------------------------------------
# Shapes
# ---------------------------------------------------------------------------

static func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


## Ellipsoid (approximate distance; good enough near the surface).
static func _ell(p: Vector3, c: Vector3, r: Vector3) -> float:
	var q := (p - c) / r
	var k0 := q.length()
	var k1 := (q / r).length()
	if k1 < 0.00001:
		return -minf(r.x, minf(r.y, r.z))
	return k0 * (k0 - 1.0) / k1


## A capsule between a and b whose radius goes from ra to rb.
static func _cone(p: Vector3, a: Vector3, b: Vector3, ra: float, rb: float) -> float:
	var ba := b - a
	var t := clampf((p - a).dot(ba) / ba.dot(ba), 0.0, 1.0)
	return p.distance_to(a + ba * t) - lerpf(ra, rb, t)


## Rotates p about the Z axis through c (to tilt ears).
static func _rz(p: Vector3, c: Vector3, ang: float) -> Vector3:
	var d := p - c
	return c + Vector3(d.x * cos(ang) - d.y * sin(ang), d.x * sin(ang) + d.y * cos(ang), d.z)


static func sdf(kind: int, p: Vector3) -> float:
	var q := Vector3(absf(p.x), p.y, p.z)
	var fat := 1.06 if kind in [3, 5] else 1.0
	var torso := _ell(p, Vector3(0, 0.6, 0.03), Vector3(0.37, 0.43, 0.33) * fat)
	var head := _ell(p, HEAD, Vector3(0.46, 0.41, 0.42) * (1.0 if kind != 6 else 0.96))
	var d := _smin(torso, head, 0.17)
	match kind:
		0:  # bunny: long upright ears, puffy cheeks
			var e := _rz(q, Vector3(0.15, 1.62, 0.03), 0.12)
			d = _smin(d, _ell(e, Vector3(0.15, 1.95, 0.03), Vector3(0.105, 0.36, 0.065)), 0.06)
			d = _smin(d, _ell(q, Vector3(0.09, 1.19, -0.37), Vector3(0.12, 0.095, 0.08)), 0.05)
		1:  # kitty: pointed ears, cheek puffs
			d = _smin(d, _cone(q, Vector3(0.25, 1.58, 0.0), Vector3(0.31, 1.86, 0.02), 0.13, 0.025), 0.06)
			d = _smin(d, _ell(q, Vector3(0.085, 1.2, -0.37), Vector3(0.11, 0.085, 0.075)), 0.05)
		2:  # pup: floppy ears hanging at the sides, a short snout
			d = _smin(d, _pup_ear(q), 0.025)
			d = _smin(d, _ell(p, Vector3(0, 1.19, -0.36), Vector3(0.16, 0.12, 0.13)), 0.08)
		3, 5:  # bear and panda: round ears, a muzzle
			d = _smin(d, _ell(q, Vector3(0.3, 1.63, 0.02), Vector3(0.13, 0.13, 0.075)), 0.05)
			d = _smin(d, _ell(p, Vector3(0, 1.19, -0.36), Vector3(0.15 if kind == 3 else 0.13, 0.11, 0.12)), 0.08)
		4:  # fox: big pointed ears, a pointy snout
			d = _smin(d, _cone(q, Vector3(0.23, 1.58, 0.02), Vector3(0.35, 1.97, 0.04), 0.155, 0.025), 0.06)
			d = _smin(d, _cone(p, Vector3(0, 1.2, -0.28), Vector3(0, 1.15, -0.53), 0.15, 0.05), 0.08)
		6:  # duck: a wide flat bill and a tuft
			d = _smin(d, _ell(p, Vector3(0, 1.17, -0.43), Vector3(0.2, 0.055, 0.16)), 0.04)
			d = _smin(d, _cone(p, Vector3(0, 1.66, -0.02), Vector3(0.02, 1.85, 0.07), 0.05, 0.018), 0.04)
	return d


## The pup's floppy ear: hinged high on the head, hanging out and down.
static func _pup_ear(q: Vector3) -> float:
	var e := _rz(q, Vector3(0.36, 1.62, -0.02), -0.4)
	return _ell(e, Vector3(0.42, 1.37, -0.02), Vector3(0.12, 0.27, 0.085))


static func tail_sdf(kind: int, p: Vector3) -> float:
	match kind:
		0:
			return _ell(p, Vector3(0, 0.02, 0.07), Vector3(0.13, 0.13, 0.12))
		1:
			var t := _cone(p, Vector3(0, 0, 0), Vector3(0, 0.14, 0.24), 0.06, 0.055)
			t = _smin(t, _cone(p, Vector3(0, 0.14, 0.24), Vector3(0, 0.44, 0.32), 0.055, 0.05), 0.03)
			return _smin(t, _cone(p, Vector3(0, 0.44, 0.32), Vector3(0.04, 0.6, 0.24), 0.05, 0.045), 0.03)
		2:
			var c := _cone(p, Vector3(0, 0, 0), Vector3(0, 0.2, 0.17), 0.08, 0.075)
			return _smin(c, _cone(p, Vector3(0, 0.2, 0.17), Vector3(0, 0.3, 0.03), 0.075, 0.05), 0.04)
		3, 5:
			return _ell(p, Vector3(0, 0.0, 0.05), Vector3(0.09, 0.09, 0.08))
		4:
			var f := _cone(p, Vector3(0, 0, 0), Vector3(0, 0.2, 0.36), 0.07, 0.16)
			return _smin(f, _ell(p, Vector3(0, 0.3, 0.52), Vector3(0.13, 0.14, 0.15)), 0.08)
		6:
			return _cone(p, Vector3(0, 0, 0), Vector3(0, 0.14, 0.12), 0.09, 0.02)
	return 1.0


## Fur colour at point p on the body: the patches, blurred a little so their
## edges are soft rather than jagged along the mesh.
static func paint(kind: int, p: Vector3) -> Color:
	return _soft(func(x: Vector3) -> Color: return _paint(kind, x), p)


static func _soft(f: Callable, p: Vector3) -> Color:
	var r := 0.024
	var acc: Color = f.call(p) * 2.0
	for o in [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, r, 0), Vector3(0, -r, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
		acc += f.call(p + o)
	return acc / 8.0


static func _paint(kind: int, p: Vector3) -> Color:
	var s: Dictionary = SPEC[kind]
	var fur: Color = s.fur
	var belly: Color = s.belly
	var q := Vector3(absf(p.x), p.y, p.z)
	var pink := Color(1.0, 0.68, 0.74)
	var ink := Color(0.14, 0.13, 0.15)
	# A light tummy patch on the front of the body.
	var tummy := _ell(p, Vector3(0, 0.56, -0.3), Vector3(0.25, 0.3, 0.2)) < 0.0
	var muzzle := _ell(p, Vector3(0, 1.16, -0.4), Vector3(0.21, 0.13, 0.16)) < 0.0
	match kind:
		0:
			if q.y > 1.62 and p.z < 0.0 and absf(q.x - 0.15 - (q.y - 1.62) * 0.12) < 0.06:
				return pink
			if muzzle:
				return Color(1.0, 0.98, 0.97)
			return belly.lerp(fur, 0.5) if tummy else fur
		1:
			if q.y > 1.6 and p.z < -0.03 and q.x > 0.2:
				return pink
			if muzzle or tummy:
				return belly
			# Tabby stripes over the head and down the back.
			if p.y > 1.52 and absf(p.x) < 0.24 and sin(p.x * 40.0) > 0.35:
				return fur.darkened(0.25)
			if p.z > 0.12 and p.y < 1.0 and sin(p.y * 24.0) > 0.45:
				return fur.darkened(0.25)
			return fur
		2:
			if muzzle or tummy:
				return belly
			# Shiba cheeks and eyebrow dots.
			if p.z < -0.2 and p.y < 1.27 and p.y > 1.05:
				return belly
			if _ell(q, Vector3(0.13, 1.5, -0.35), Vector3(0.05, 0.035, 0.08)) < 0.0:
				return belly
			if _pup_ear(q) < 0.012:
				return fur.darkened(0.4)
			return fur
		3:
			if muzzle or tummy:
				return belly
			if q.y > 1.55 and p.z < 0.0 and _ell(q, Vector3(0.3, 1.63, -0.04), Vector3(0.08, 0.08, 0.06)) < 0.0:
				return belly
			return fur
		4:
			if q.y > 1.84:
				return ink
			if q.y > 1.6 and p.z < -0.02 and q.x > 0.22:
				return Color(1.0, 0.93, 0.88)
			if (p.z < -0.18 and p.y < 1.25 and p.y > 1.0) or p.z < -0.42 or tummy:
				return belly
			return fur
		5:
			if q.y > 1.55:
				return ink
			if _ell(_rz(q, Vector3(0.17, 1.34, -0.37), -0.5), Vector3(0.17, 1.34, -0.37), Vector3(0.1, 0.13, 0.12)) < 0.0:
				return ink
			if p.y > 0.66 and p.y < 0.97 and not tummy:
				return ink
			return fur
		6:
			if _ell(p, Vector3(0, 1.17, -0.43), Vector3(0.21, 0.07, 0.17)) < 0.0:
				return Color(1.0, 0.55, 0.15)
			return belly if tummy else fur
	return fur


static func tail_paint(kind: int, p: Vector3) -> Color:
	return _soft(func(x: Vector3) -> Color: return _tail_paint(kind, x), p)


static func _tail_paint(kind: int, p: Vector3) -> Color:
	var s: Dictionary = SPEC[kind]
	match kind:
		0:
			return Color(1, 1, 1)
		1:
			return s.fur.darkened(0.25) if sin((p.y + p.z) * 22.0) > 0.4 else s.fur
		2:
			return s.belly if p.z < 0.1 and p.y > 0.12 else s.fur
		4:
			return s.belly if p.z > 0.5 else s.fur
		5:
			return INK
	return s.fur


# ---------------------------------------------------------------------------
# Surface nets
# ---------------------------------------------------------------------------

static func build(kind: int, part: String) -> ArrayMesh:
	var is_tail := part == "tail"
	var lo := Vector3(-0.62, 0.06, -0.72) if not is_tail else Vector3(-0.3, -0.25, -0.2)
	var hi := Vector3(0.62, 2.4, 0.56) if not is_tail else Vector3(0.3, 0.8, 0.8)
	var f := func(p: Vector3) -> float:
		return tail_sdf(kind, p) if is_tail else sdf(kind, p)
	var col := func(p: Vector3) -> Color:
		return tail_paint(kind, p) if is_tail else paint(kind, p)
	return mesh_field(f, col, lo, hi, CELL * (0.7 if is_tail else 1.0))


## Meshes the zero level of `f` inside [lo, hi] with surface nets; `col` gives
## each vertex its colour. Vertices are pulled onto the true surface and get
## the field's gradient as their normal, so the result is smooth.
static func mesh_field(f: Callable, col: Callable, lo: Vector3, hi: Vector3, h: float) -> ArrayMesh:
	var n := Vector3i(ceili((hi.x - lo.x) / h) + 1, ceili((hi.y - lo.y) / h) + 1, ceili((hi.z - lo.z) / h) + 1)
	var sx := n.x
	var sxy := n.x * n.y
	var v := PackedFloat32Array()
	v.resize(n.x * n.y * n.z)
	for k in n.z:
		for j in n.y:
			for i in n.x:
				v[i + j * sx + k * sxy] = f.call(lo + Vector3(i, j, k) * h)
	# One vertex per cell that the surface passes through.
	var cell_idx := {}
	var verts := PackedVector3Array()
	var corners := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
		Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	for k in n.z - 1:
		for j in n.y - 1:
			for i in n.x - 1:
				var vals := []
				var neg := 0
				for c in corners:
					var val: float = v[(i + c.x) + (j + c.y) * sx + (k + c.z) * sxy]
					vals.append(val)
					if val < 0.0:
						neg += 1
				if neg == 0 or neg == 8:
					continue
				var acc := Vector3.ZERO
				var cnt := 0
				for e in edges:
					var a: float = vals[e[0]]
					var b: float = vals[e[1]]
					if (a < 0.0) != (b < 0.0):
						var t := a / (a - b)
						acc += Vector3(corners[e[0]]).lerp(Vector3(corners[e[1]]), t)
						cnt += 1
				var p := lo + (Vector3(i, j, k) + acc / cnt) * h
				cell_idx[i + j * sx + k * sxy] = verts.size()
				verts.append(p)
	# Pull each vertex onto the surface; the gradient is the normal.
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	var colors := PackedColorArray()
	colors.resize(verts.size())
	var e2 := h * 0.25
	for vi in verts.size():
		var p: Vector3 = verts[vi]
		var g := Vector3.ZERO
		for _it in 3:
			g = Vector3(
				f.call(p + Vector3(e2, 0, 0)) - f.call(p - Vector3(e2, 0, 0)),
				f.call(p + Vector3(0, e2, 0)) - f.call(p - Vector3(0, e2, 0)),
				f.call(p + Vector3(0, 0, e2)) - f.call(p - Vector3(0, 0, e2))).normalized()
			var d: float = f.call(p)
			p -= g * clampf(d, -h, h)
		verts[vi] = p
		norms[vi] = g
		colors[vi] = col.call(p)
	# A quad for every grid edge that crosses the surface.
	var idx := PackedInt32Array()
	for k in range(1, n.z - 1):
		for j in range(1, n.y - 1):
			for i in range(1, n.x - 1):
				var here := i + j * sx + k * sxy
				var a0: bool = v[here] < 0.0
				for axis in 3:
					var nb: int = here + [1, sx, sxy][axis]
					if a0 == (v[nb] < 0.0):
						continue
					# The four cells around this edge.
					var o1: int = [sx, 1, 1][axis]
					var o2: int = [sxy, sxy, sx][axis]
					var c := [here, here - o1, here - o1 - o2, here - o2]
					if not (cell_idx.has(c[0]) and cell_idx.has(c[1]) and cell_idx.has(c[2]) and cell_idx.has(c[3])):
						continue
					var q := [cell_idx[c[0]], cell_idx[c[1]], cell_idx[c[2]], cell_idx[c[3]]]
					# Godot's front faces wind clockwise seen from outside.
					var nrm: Vector3 = (verts[q[1]] - verts[q[0]]).cross(verts[q[2]] - verts[q[0]])
					var outward: Vector3 = norms[q[0]] + norms[q[1]] + norms[q[2]] + norms[q[3]]
					if nrm.dot(outward) > 0.0:
						q.reverse()
					idx.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
