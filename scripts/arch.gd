extends RefCounted
## Architecture kit: what makes a building a *kind* of building rather than
## a box with windows. map._building() makes the shell (walls, floors,
## stairs, doors, glass); when it is given opts.style it calls:
##   exterior()  massing and character outside: verandas, bay windows,
##               dormers and balconies on houses; a log porch, stone chimney
##               and woodpile on cabins; shop fronts with awnings and signs;
##               stepped tower tiers with fins, crown and mast on offices;
##               sawtooth roofs, docks and tanks on warehouses; and so on.
##   interior()  partition walls that divide each storey into rooms, and a
##               room programme per style and storey (a house has a kitchen
##               and living room downstairs, bedrooms and a bathroom above;
##               a clinic has reception and wards; a store has aisles, a
##               counter and a stock room...).
## Styles: house, cabin, store, office, warehouse, barn, clinic, motel,
## garage, barracks, lab, workshop, clubhouse.
##
## Buildings are axis-aligned: south = -Z (front door), east = +X (side
## door). Stairs run along the west wall on even storeys and the east wall
## on odd ones, in the middle third of the depth, so rooms sit north of the
## partition (the back) and in the south corners (the front).
## Everything is placed through map.gd helpers, so `mirror` copies work.

const F := 2.15                # scale of the Kenney furniture kit


## First material name of `names` this map's theme has.
static func _mat(m, names: Array) -> String:
	for n in names:
		if m._mats.has(n):
			return n
	return "block_a"


static func _p(m, path: String, pos: Vector3, yaw: float, mirror: bool, scl := F) -> void:
	m._prop(path, pos, yaw, scl, 5.0, mirror)


# --------------------------------------------------------------------------
# Exteriors
# --------------------------------------------------------------------------

static func exterior(m, style: String, c: Vector3, sx: float, sz: float, floors: int, mat: String, opts: Dictionary) -> void:
	var mirror: bool = opts.get("mirror", true)
	var x0 := c.x - sx * 0.5
	var x1 := c.x + sx * 0.5
	var z0 := c.z - sz * 0.5
	var z1 := c.z + sz * 0.5
	var top: float = c.y + floors * m.FLOOR_H
	var trim := _mat(m, ["trim", "block_a"])
	var wood := _mat(m, ["deck", "crate"])
	var dark := "dark"
	match style:
		"house":
			# Veranda along the front: deck, posts, rail and a lean-to roof.
			m._box(Vector3(c.x, c.y + 0.03, z0 - 1.3), Vector3(sx, 0.06, 2.6), wood, mirror, 0.0, false)
			for i in 4:
				var px := x0 + 0.3 + (sx - 0.6) * i / 3.0
				m._cyl(Vector3(px, c.y, z0 - 2.45), 0.09, 2.6, trim, mirror, false)
			m._box(Vector3(c.x, c.y + 2.7, z0 - 1.3), Vector3(sx + 0.3, 0.12, 2.8), _mat(m, ["roof_red", "block_c"]), mirror)
			for sgn in [-1.0, 1.0]:
				m._box(Vector3(c.x + sgn * (sx * 0.25 + 0.45), c.y + 0.55, z0 - 2.45), Vector3(sx * 0.5 - 1.2, 0.08, 0.08), trim, mirror, 0.0, false)
			# Bay window on the west side, flower boxes under the front windows.
			if sz >= 8.5:
				m._box(Vector3(x0 - 0.45, c.y + 1.55, c.z + sz * 0.25), Vector3(0.9, 2.3, 2.6), mat, mirror)
				m._box(Vector3(x0 - 0.92, c.y + 1.65, c.z + sz * 0.25), Vector3(0.05, 1.3, 2.0), "glass", mirror, 0.0, false)
				m._box(Vector3(x0 - 0.45, c.y + 2.78, c.z + sz * 0.25), Vector3(1.1, 0.14, 2.9), _mat(m, ["roof_red", "block_c"]), mirror, 0.0, false)
			if floors >= 2:
				# Balcony over the side door, with a rail.
				var by: float = c.y + m.FLOOR_H
				m._box(Vector3(x1 + 0.9, by - 0.1, c.z), Vector3(1.8, 0.2, 3.4), wood, mirror)
				m._box(Vector3(x1 + 1.76, by + 0.5, c.z), Vector3(0.08, 1.0, 3.4), trim, mirror)
				for sgn in [-1.0, 1.0]:
					m._box(Vector3(x1 + 0.9, by + 0.5, c.z + sgn * 1.66), Vector3(1.8, 1.0, 0.08), trim, mirror)
				# Dormers on the roof slopes.
				for sgn in [-1.0, 1.0]:
					var dz: float = c.z + sgn * sz * 0.27
					m._box(Vector3(c.x - sx * 0.2, top + 0.75, dz), Vector3(1.5, 1.2, 1.3), mat, mirror, 0.0, false)
					m._box(Vector3(c.x - sx * 0.2, top + 0.8, dz + sgn * 0.67), Vector3(0.9, 0.7, 0.05), "window", mirror, 0.0, false)
					m._box(Vector3(c.x - sx * 0.2, top + 1.42, dz), Vector3(1.8, 0.12, 1.6), _mat(m, ["roof_red", "block_c"]), mirror, 0.0, false)
			# A path of stepping stones from the veranda, a mailbox.
			for i in 3:
				m._box(Vector3(c.x, c.y + 0.02, z0 - 3.2 - i * 0.9), Vector3(1.0, 0.04, 0.6), trim, mirror, 0.0, false)
			m._box(Vector3(c.x + 1.6, c.y + 0.5, z0 - 4.8), Vector3(0.1, 1.0, 0.1), dark, mirror, 0.0, false)
			m._box(Vector3(c.x + 1.6, c.y + 1.08, z0 - 4.8), Vector3(0.24, 0.2, 0.42), _mat(m, ["car_red", "accent_a"]), mirror, 0.0, false)
		"cabin":
			# Log ends at the corners, a deep porch, a stone chimney outside
			# the west wall, a woodpile and a lantern by the door.
			for cx in [x0, x1]:
				for cz in [z0, z1]:
					for i in int(floors * m.FLOOR_H / 0.45):
						var ly := c.y + 0.25 + i * 0.45
						m._box(Vector3(cx, ly, cz), Vector3(0.7 if i % 2 == 0 else 0.26, 0.26, 0.26 if i % 2 == 0 else 0.7), wood, mirror, 0.0, false)
			m._box(Vector3(c.x, c.y + 0.1, z0 - 1.5), Vector3(sx, 0.2, 3.0), wood, mirror)
			for sgn in [-1.0, 1.0]:
				m._cyl(Vector3(c.x + sgn * (sx * 0.5 - 0.25), c.y + 0.2, z0 - 2.8), 0.13, 2.5, wood, mirror, false)
				m._box(Vector3(c.x + sgn * (sx * 0.25 + 0.5), c.y + 0.75, z0 - 2.8), Vector3(sx * 0.5 - 1.3, 0.1, 0.1), wood, mirror, 0.0, false)
			m._box(Vector3(c.x, c.y + 2.8, z0 - 1.5), Vector3(sx + 0.5, 0.14, 3.3), _mat(m, ["block_c", "roof_red"]), mirror)
			m._box(Vector3(x0 - 0.55, c.y + (top - c.y + 2.6) * 0.5, c.z), Vector3(1.1, top - c.y + 2.6, 1.5), _mat(m, ["wall", "block_b"]), mirror)
			m._model("survival/Resource_Wood", Vector3(x1 + 0.7, c.y, c.z + sz * 0.25), PI * 0.5, 3.0, mirror, "none")
			m._model("survival/Resource_Wood", Vector3(x1 + 0.7, c.y, c.z + sz * 0.25 - 1.0), PI * 0.5, 3.0, mirror, "none")
			m._model("survival/Tree_Trunk", Vector3(c.x + sx * 0.5 + 2.2, c.y, z0 - 1.6), 0.3, 2.6, mirror)
			m._glow(Vector3(c.x + 1.3, c.y + 2.2, z0 - 0.5), Color(1.0, 0.62, 0.3), 6.0, 1.3, mirror)
		"store":
			# Striped awning over the shop front, a lit sign board on a raised
			# parapet, roof-top air conditioners, a bin and crates out back.
			var awn := _mat(m, ["car_red", "accent_a"])
			for i in int(sx / 1.2):
				m._box(Vector3(x0 + 0.6 + i * 1.2, c.y + 2.85, z0 - 0.9), Vector3(1.2, 0.1, 1.8), awn if i % 2 == 0 else trim, mirror, 0.0, false)
			m._box(Vector3(c.x, c.y + 2.72, z0 - 1.78), Vector3(sx, 0.28, 0.06), awn, mirror, 0.0, false)
			m._box(Vector3(c.x, top + 0.9, z0 + 0.1), Vector3(sx * 0.82, 1.5, 0.3), dark, mirror)
			m._box(Vector3(c.x, top + 0.9, z0 - 0.07), Vector3(sx * 0.7, 0.9, 0.06), "accent_b", mirror, 0.0, false)
			m._glow(Vector3(c.x, top + 0.2, z0 - 1.6), m.theme.accent_b, 8.0, 1.2, mirror)
			m._box(Vector3(c.x + sx * 0.22, top + 0.45, c.z + sz * 0.2), Vector3(1.5, 0.9, 1.1), _mat(m, ["metal", "block_c"]), mirror)
			m._box(Vector3(c.x - sx * 0.2, top + 0.35, c.z + sz * 0.25), Vector3(1.0, 0.7, 1.0), _mat(m, ["metal", "block_c"]), mirror)
			m._model("toon/Prop/Trash_Container", Vector3(c.x - sx * 0.28, c.y, z1 + 1.1), 0.0, 0.9, mirror)
			m._prop("toon/Prop/Pallet", Vector3(c.x + sx * 0.25, c.y, z1 + 1.0), 0.3, 0.8, 5.0, mirror)
			m._prop("furniture/Cardboard_Box_Closed", Vector3(c.x + sx * 0.25, c.y + 0.2, z1 + 1.0), 0.6, 2.4, 5.0, mirror)
		"office":
			# A tower: the walkable building is the podium; above it rise set-
			# back tiers of glass with vertical fins, a crown and a mast.
			var tiers: int = opts.get("tiers", 3)
			var y := top
			var w := sx - 3.6
			var d := sz - 3.6
			for ti in tiers:
				var th := 9.0 if ti < tiers - 1 else 6.0
				m._box(Vector3(c.x, y + th * 0.5, c.z), Vector3(w, th, d), _mat(m, ["block_c", "block_a"]), mirror)
				for band in int(th / 1.5):
					var byy: float = y + 0.9 + band * 1.5
					m._box(Vector3(c.x, byy, c.z), Vector3(w + 0.08, 0.8, d + 0.08), "window", mirror, 0.0, false)
				for fx in int(w / 1.6) + 1:
					var fpx := c.x - w * 0.5 + fx * (w / maxf(int(w / 1.6), 1))
					m._box(Vector3(fpx, y + th * 0.5, c.z), Vector3(0.14, th, d + 0.3), trim, mirror, 0.0, false)
				y += th
				w = maxf(w - 1.8, 2.4)
				d = maxf(d - 1.8, 2.4)
			m._box(Vector3(c.x, y + 0.25, c.z), Vector3(w + 2.2, 0.5, d + 2.2), dark, mirror, 0.0, false)
			m._cyl(Vector3(c.x, y + 0.5, c.z), 0.1, 6.0, dark, mirror, false)
			m._ball(Vector3(c.x, y + 6.6, c.z), Vector3(0.22, 0.22, 0.22), "beacon", mirror)
			m._glow(Vector3(c.x, y + 6.0, c.z), Color(1.0, 0.25, 0.2), 14.0, 1.4, mirror)
			# Entrance: a canopy on columns and planters either side.
			m._box(Vector3(c.x, c.y + 3.0, z0 - 1.5), Vector3(5.0, 0.2, 3.0), dark, mirror)
			for sgn in [-1.0, 1.0]:
				m._cyl(Vector3(c.x + sgn * 2.2, c.y, z0 - 2.7), 0.14, 2.9, _mat(m, ["metal", "trim"]), mirror, false)
				m._box(Vector3(c.x + sgn * 3.6, c.y + 0.3, z0 - 0.9), Vector3(1.4, 0.6, 1.0), _mat(m, ["block_a", "trim"]), mirror)
				m._bush(Vector3(c.x + sgn * 3.6, c.y + 0.6, z0 - 0.9), 0.7, mirror)
		"warehouse", "barn":
			if style == "warehouse":
				# Sawtooth roof lights, a loading dock with bumpers, a tank.
				var n := maxi(2, int(sx / 6.0))
				for i in n:
					var wx := x0 + sx * (i + 0.5) / n
					m._wedge(Vector3(wx, top, c.z), Vector3(sx / n - 0.3, 1.5, sz - 1.2), 0.0, _mat(m, ["block_c", "metal"]), mirror, false)
					m._box(Vector3(wx + (sx / n - 0.3) * 0.5 + 0.03, top + 0.8, c.z), Vector3(0.05, 1.1, sz - 2.0), "window", mirror, 0.0, false)
				m._box(Vector3(c.x, c.y + 0.15, z0 - 1.4), Vector3(minf(sx - 2.0, 9.0), 0.3, 2.8), _mat(m, ["block_a", "path"]), mirror)
				for sgn in [-1.0, 1.0]:
					m._box(Vector3(c.x + sgn * 1.4, c.y + 0.75, z0 - 0.1), Vector3(0.3, 0.9, 0.2), "stripes", mirror, 0.0, false)
				m._model("toon/Building/Water_Tank_Floor", Vector3(x1 + 1.8, c.y, c.z - sz * 0.25), 0.0, 0.8, mirror)
				m._model("zombie/Prop/Pipes", Vector3(x0 - 1.2, c.y, c.z + sz * 0.2), PI * 0.5, 1.1, mirror)
			else:
				# Barn: big cross-braced doors (painted on), hay loft hatch, bales.
				for sgn in [-1.0, 1.0]:
					m._box(Vector3(c.x + sgn * 2.0, c.y + 1.5, z0 - 0.04), Vector3(1.8, 2.8, 0.08), _mat(m, ["car_red", "roof_red"]), mirror, 0.0, false)
					m._box(Vector3(c.x + sgn * 2.0, c.y + 1.5, z0 - 0.09), Vector3(1.9, 0.14, 0.05), trim, mirror, 0.0, false)
					m._box(Vector3(c.x + sgn * 2.0, c.y + 1.5, z0 - 0.09), Vector3(0.14, 2.8, 0.05), trim, mirror, 0.0, false)
				m._box(Vector3(c.x, top + 0.9, z0 - 0.3), Vector3(1.4, 1.2, 0.3), wood, mirror, 0.0, false)
				for p in [Vector3(x1 + 1.4, 0.45, c.z), Vector3(x1 + 1.4, 0.45, c.z + 1.3), Vector3(x1 + 1.5, 1.35, c.z + 0.6)]:
					m._box(c * Vector3(0, 1, 0) + p, Vector3(1.4, 0.9, 1.0), _mat(m, ["hay", "crate"]), mirror)
		"clinic":
			# A green cross sign, entrance canopy, benches, ambulance ramp rail.
			var gy: float = top + 1.4
			m._box(Vector3(c.x + sx * 0.3, gy, z0 - 0.06), Vector3(0.5, 1.6, 0.08), "accent_b", mirror, 0.0, false)
			m._box(Vector3(c.x + sx * 0.3, gy, z0 - 0.06), Vector3(1.6, 0.5, 0.08), "accent_b", mirror, 0.0, false)
			m._box(Vector3(c.x + sx * 0.3, gy, z0 + 0.12), Vector3(2.2, 2.2, 0.3), dark, mirror)
			for sgn in [-1.0, 1.0]:
				m._prop("furniture/Bench", Vector3(c.x + sgn * 3.4, c.y, z0 - 0.9), 0.0, F, 5.0, mirror)
			m._box(Vector3(c.x, c.y + 1.0, z1 + 0.5), Vector3(sx * 0.5, 0.7, 0.9), _mat(m, ["metal", "block_c"]), mirror)
		"motel":
			# An access balcony along the front of the upper floor with a
			# rail, room doors painted on, numbers lit, an ice machine.
			if floors >= 2:
				var by2: float = c.y + m.FLOOR_H
				m._box(Vector3(c.x, by2 - 0.1, z0 - 1.0), Vector3(sx, 0.2, 2.0), wood, mirror)
				m._box(Vector3(c.x, by2 + 0.5, z0 - 1.95), Vector3(sx, 1.0, 0.08), trim, mirror)
				for i in 5:
					m._cyl(Vector3(x0 + 0.2 + (sx - 0.4) * i / 4.0, c.y, z0 - 1.9), 0.08, m.FLOOR_H, trim, mirror, false)
				m._stairs(Vector3(x1 + 3.0, c.y, z0 - 1.0), Vector3(6.0, m.FLOOR_H, 1.6), PI, wood, mirror)
			m._box(Vector3(x0 + 1.0, c.y + 0.9, z0 - 0.5), Vector3(0.9, 1.8, 0.8), _mat(m, ["metal", "block_c"]), mirror)
			m._box(Vector3(x0 + 1.0, c.y + 1.3, z0 - 0.92), Vector3(0.6, 0.6, 0.04), "lamp", mirror, 0.0, false)
		"garage":
			# Roller door (painted panels), workbench light, oil drum, tyres.
			for i in 5:
				m._box(Vector3(c.x, c.y + 0.35 + i * 0.5, z1 + 0.03), Vector3(minf(sx - 1.6, 4.2), 0.44, 0.06), _mat(m, ["metal", "trim"]), mirror, 0.0, false)
			m._model("zombie/Prop/Wheels_Stack", Vector3(x0 - 0.8, c.y, c.z - sz * 0.2), 0.0, 1.1, mirror)
			m._prop("survival/Barrel", Vector3(x0 - 0.8, c.y, c.z + sz * 0.2), 0.0, 3.0, 5.0, mirror)
		"barracks":
			# Sandbagged base, a radio mast, a flag, camo netting slab.
			m._model("toon/Wall/Sack_Trench", Vector3(c.x - sx * 0.25, c.y, z0 - 1.6), 0.0, 1.2, mirror)
			m._model("toon/Wall/Sack_Trench_Small", Vector3(c.x + sx * 0.3, c.y, z0 - 1.6), 0.0, 1.2, mirror)
			m._cyl(Vector3(x1 - 0.8, top, z1 - 0.8), 0.07, 5.0, dark, mirror, false)
			m._box(Vector3(x1 - 0.8, top + 4.2, z1 - 0.8), Vector3(1.4, 0.05, 0.05), dark, mirror, 0.0, false)
			m._box(Vector3(c.x, top + 2.2, c.z - sz * 0.2), Vector3(sx * 0.6, 0.08, sz * 0.4), _mat(m, ["olive", "block_c"]), mirror, 0.0, false)
			for sgn in [-1.0, 1.0]:
				m._cyl(Vector3(c.x + sgn * sx * 0.28, top, c.z - sz * 0.38), 0.06, 2.2, dark, mirror, false)
		"lab":
			# A dish on the roof, cable trunking, a fuel tank and vents.
			m._cyl(Vector3(c.x - sx * 0.25, top, c.z), 0.12, 1.6, dark, mirror, false)
			m._cyl(Vector3(c.x - sx * 0.25, top + 1.6, c.z), 1.3, 0.25, _mat(m, ["block_a", "trim"]), mirror, false, 0.5)
			m._box(Vector3(x1 + 0.12, c.y + (top - c.y) * 0.5, c.z + sz * 0.3), Vector3(0.24, top - c.y, 0.3), dark, mirror, 0.0, false)
			m._model("toon/Prop/Gas_Tank", Vector3(x0 - 1.0, c.y, c.z + sz * 0.25), 0.0, 1.0, mirror)
			m._box(Vector3(c.x + sx * 0.2, top + 0.4, c.z + sz * 0.25), Vector3(1.3, 0.8, 1.0), _mat(m, ["block_c", "metal"]), mirror)
		"workshop":
			# A tall brick stack with a glow, a lean-to store, an anvil yard.
			m._box(Vector3(x0 + 1.0, top + 2.4, z1 - 1.0), Vector3(1.3, 4.8, 1.3), _mat(m, ["block_b", "wall"]), mirror)
			m._box(Vector3(x0 + 1.0, top + 4.9, z1 - 1.0), Vector3(1.6, 0.25, 1.6), dark, mirror, 0.0, false)
			m._glow(Vector3(x0 + 1.0, top + 5.4, z1 - 1.0), Color(1.0, 0.45, 0.12), 9.0, 1.6, mirror)
			m._wedge(Vector3(x0 - 1.2, c.y + 2.2, c.z), Vector3(2.4, 0.9, sz * 0.7), 0.0, _mat(m, ["block_c", "deck"]), mirror, false)
			for sgn in [-1.0, 1.0]:
				m._cyl(Vector3(x0 - 2.2, c.y, c.z + sgn * sz * 0.3), 0.1, 2.2, wood, mirror, false)
			m._prop("fantasy/Anvil", Vector3(x0 - 1.3, c.y, c.z), 0.4, 1.1, 5.0, mirror)
			m._prop("survival/Barrel", Vector3(x0 - 1.4, c.y, c.z + 1.4), 0.0, 3.0, 5.0, mirror)
		"clubhouse":
			# A sports club stand: a viewing balcony on the pitch side (east)
			# with a glass rail, a row of seats and a canopy; a club-colour
			# band under the parapet, a crest board, flagpoles on the roof, a
			# ticket window by the front door and a vending machine.
			var club := _mat(m, ["seat_red", "car_red", "accent_a"])
			var club2 := _mat(m, ["block_b", "teal"])
			var metal := _mat(m, ["metal", "trim"])
			var by: float = c.y + m.FLOOR_H
			m._box(Vector3(x1 + 1.0, by - 0.1, c.z), Vector3(2.0, 0.2, sz - 1.0), _mat(m, ["deck"]), mirror)
			m._box(Vector3(x1 + 1.96, by + 0.55, c.z), Vector3(0.06, 1.1, sz - 1.0), "glass", mirror)
			for sgn in [-1.0, 1.0]:
				m._box(Vector3(x1 + 1.0, by + 0.55, c.z + sgn * (sz * 0.5 - 0.53)), Vector3(2.0, 1.1, 0.06), "glass", mirror)
				m._cyl(Vector3(x1 + 1.8, c.y, c.z + sgn * (sz * 0.5 - 0.7)), 0.09, by - c.y - 0.2, metal, mirror, false)
			for i in int((sz - 2.4) / 0.75):
				var sz_i: float = c.z - (sz - 2.4) * 0.5 + 0.37 + i * 0.75
				m._box(Vector3(x1 + 1.15, by + 0.22, sz_i), Vector3(0.5, 0.44, 0.6), club, mirror, 0.0, false)
				m._box(Vector3(x1 + 0.88, by + 0.55, sz_i), Vector3(0.06, 0.5, 0.6), club, mirror, 0.0, false)
			m._box(Vector3(x1 + 1.2, top - 0.2, c.z), Vector3(2.6, 0.15, sz), _mat(m, ["block_c", "metal"]), mirror)
			# Club band and crest.
			m._box(Vector3(c.x, top - 0.5, z0 - 0.04), Vector3(sx + 0.1, 0.32, 0.06), club, mirror, 0.0, false)
			m._box(Vector3(c.x, top - 0.5, z1 + 0.04), Vector3(sx + 0.1, 0.32, 0.06), club, mirror, 0.0, false)
			m._box(Vector3(x0 - 0.04, top - 0.5, c.z), Vector3(0.06, 0.32, sz + 0.1), club, mirror, 0.0, false)
			m._box(Vector3(c.x, top + 1.3, z0 + 0.15), Vector3(2.6, 1.6, 0.25), dark, mirror)
			m._box(Vector3(c.x, top + 1.3, z0 - 0.03), Vector3(1.9, 1.1, 0.06), club2, mirror, 0.0, false)
			m._box(Vector3(c.x, top + 1.3, z0 - 0.07), Vector3(1.9, 0.3, 0.04), club, mirror, 0.0, false)
			m._glow(Vector3(c.x, top + 0.6, z0 - 1.2), m.theme.accent_b, 6.0, 1.0, mirror)
			# Flags on the roof corners.
			for fl in [[x0 + 0.5, club2], [x1 - 0.5, club]]:
				m._cyl(Vector3(fl[0], top, z0 + 0.5), 0.05, 4.2, metal, mirror, false)
				m._box(Vector3(fl[0] + 0.62, top + 3.75, z0 + 0.5), Vector3(1.2, 0.7, 0.03), fl[1], mirror, 0.0, false)
			# Ticket window west of the door, vending machine by the side door.
			var tx: float = c.x - sx * 0.3
			m._box(Vector3(tx, c.y + 1.35, z0 - 0.03), Vector3(1.2, 0.8, 0.05), "window", mirror, 0.0, false)
			m._box(Vector3(tx, c.y + 0.92, z0 - 0.2), Vector3(1.4, 0.08, 0.4), metal, mirror)
			m._box(Vector3(tx, c.y + 2.05, z0 - 0.45), Vector3(1.6, 0.08, 0.9), club, mirror, 0.0, false)
			m._box(Vector3(x1 + 0.5, c.y + 0.9, c.z - 3.2), Vector3(0.8, 1.8, 0.9), club2, mirror)
			m._box(Vector3(x1 + 0.92, c.y + 1.2, c.z - 3.2), Vector3(0.04, 1.0, 0.6), "lamp", mirror, 0.0, false)
			m._prop("furniture/Bench", Vector3(c.x + sx * 0.3, c.y, z0 - 0.9), 0.0, F, 5.0, mirror)


# --------------------------------------------------------------------------
# Interiors
# --------------------------------------------------------------------------

## One storey: partitions, then a room in each slot.
static func interior(m, style: String, f: int, floors: int, c: Vector3, sx: float, sz: float, y: float, mirror: bool) -> void:
	var wide := sx >= 11.0
	var hall_z := c.z + sz * 0.16            # the partition line
	var wall := _mat(m, ["trim", "block_a"])
	var h: float = m.FLOOR_H - 0.32       # up into the ceiling slab (0.3 thick)
	var back_z := (hall_z + c.z + sz * 0.5) * 0.5 + 0.1
	var back_d := c.z + sz * 0.5 - hall_z - 0.5
	if wide and sz >= 8.5 and not style in ["warehouse", "barn", "garage", "cabin"]:
		# Back rooms either side of a 2.8 m doorway, clear of both stairs:
		# full-height walls (into the ceiling slab, so they read as walls and
		# not as free-standing boards), a skirting board, a lintel and a
		# frame round the doorway.
		var h2: float = h + 0.3
		for sgn in [-1.0, 1.0]:
			var a: float = c.x + sgn * 1.4
			var b: float = c.x + sgn * (sx * 0.5 - 2.3)
			m._box(Vector3((a + b) * 0.5, y + h2 * 0.5, hall_z), Vector3(absf(b - a), h2, 0.16), wall, mirror)
			m._box(Vector3((a + b) * 0.5, y + 0.06, hall_z), Vector3(absf(b - a), 0.12, 0.2), "dark", mirror, 0.0, false)
			m._box(Vector3(c.x + sgn * 1.35, y + 1.27, hall_z), Vector3(0.1, 2.55, 0.22), _mat(m, ["deck", "dark"]), mirror, 0.0, false)
		m._box(Vector3(c.x, y + 2.55 + (h2 - 2.55) * 0.5, hall_z), Vector3(2.8, h2 - 2.55, 0.16), wall, mirror)
		m._box(Vector3(c.x, y + 2.6, hall_z), Vector3(2.8, 0.1, 0.22), _mat(m, ["deck", "dark"]), mirror, 0.0, false)
		# A wall between the two back rooms, also full height.
		m._box(Vector3(c.x, y + h2 * 0.5, c.z + sz * 0.5 - back_d * 0.3 - 0.3), Vector3(0.16, h2, back_d * 0.6), wall, mirror)
	var ne := Vector3(c.x + (sx * 0.27 if wide else 0.0), y, back_z)
	var nw := Vector3(c.x - sx * 0.25, y, back_z)
	var se := Vector3(c.x + sx * 0.28, y, c.z - sz * 0.3)
	var sw := Vector3(c.x - sx * 0.2, y, c.z - sz * 0.33)
	var room_w := (sx * 0.5 - 2.6) if wide else (sx - 4.2)
	var north := c.z + sz * 0.5 - 0.3
	var south := c.z - sz * 0.5 + 0.3
	var upper := f > 0
	match style:
		"house":
			if not upper:
				_kitchen(m, ne, room_w, north, mirror)
				if wide:
					_bathroom(m, nw, north, mirror)
				_living(m, se, south, mirror)
			else:
				_bedroom(m, ne, north, mirror, true)
				if wide:
					_office(m, nw, north, mirror)
				_bedroom(m, se, south, mirror, false)
		"cabin":
			_cabin(m, c, sx, sz, y, mirror)
		"store":
			if not upper:
				_shop(m, c, sx, sz, y, mirror)
				_storage(m, ne if wide else nw, north, mirror)
			else:
				_office(m, ne, north, mirror)
				_storage(m, se, south, mirror)
		"office":
			if not upper:
				_reception(m, se, south, mirror)
			else:
				_office(m, se, south, mirror, PI)
			_office(m, ne, north, mirror)
			if wide:
				_office(m, nw, north, mirror)
				_p(m, "furniture/Potted_Plant", Vector3(c.x, y, hall_z - 0.5), 0.0, mirror)
		"clinic":
			if not upper:
				_reception(m, se, south, mirror)
			else:
				_ward(m, se, south, mirror, 2)
			_ward(m, ne, north, mirror, 3 if room_w > 4.0 else 2)
			if wide:
				if upper:
					_ward(m, nw, north, mirror, 2)
				else:
					_office(m, nw, north, mirror)
		"motel":
			_motel_room(m, ne, north, mirror)
			if wide:
				_motel_room(m, nw, north, mirror)
			if not upper:
				_reception(m, se, south, mirror)
			else:
				_motel_room(m, se, south, mirror, true)
		"warehouse", "barn":
			_storage(m, ne, north, mirror)
			_storage(m, Vector3(c.x - sx * 0.2, y, back_z), north, mirror)
			if style == "warehouse":
				_office(m, se, south, mirror, PI)
			else:
				for i in 3:
					m._box(Vector3(se.x - 0.8 + i * 0.9, y + 0.45, se.z), Vector3(0.85, 0.9, 1.2), _mat(m, ["hay", "crate"]), mirror)
		"garage":
			_garage(m, c, sx, sz, y, mirror)
		"barracks":
			_bunks(m, ne, north, mirror)
			if wide:
				_storage(m, nw, north, mirror)
			_briefing(m, se, mirror)
		"lab":
			_lab(m, ne, north, mirror)
			if wide:
				_lab(m, nw, north, mirror)
			if not upper:
				_reception(m, se, south, mirror)
			else:
				_storage(m, se, south, mirror)
		"workshop":
			_workshop(m, ne, north, mirror)
			_storage(m, se, south, mirror)
		"clubhouse":
			_clubhouse(m, c, sx, sz, y, mirror, upper)


# ---- rooms: `at` is the middle of the room on the floor; `wall_z` the z of
# ---- the wall its big furniture stands against.

static func _kitchen(m, at: Vector3, w: float, wall_z: float, mirror: bool) -> void:
	var z := wall_z - 0.55 * signf(wall_z - at.z)
	_p(m, "furniture/Kitchen_Fridge", at + Vector3(-1.4, 0, z - at.z), PI, mirror)
	_p(m, "furniture/Kitchen_Stove", at + Vector3(-0.4, 0, z - at.z), PI, mirror)
	_p(m, "furniture/Kitchen_Sink", at + Vector3(0.55, 0, z - at.z), PI, mirror)
	_p(m, "furniture/Kitchen_Cabinet", at + Vector3(1.5, 0, z - at.z), PI, mirror)
	_p(m, "furniture/Toaster", at + Vector3(1.5, 0.99, z - at.z), 0.0, mirror)
	_p(m, "furniture/Kitchen_Coffee_Machine", at + Vector3(0.55, 1.08, z - at.z + 0.2), 0.0, mirror)
	if w > 3.4:
		_p(m, "furniture/Table_Round", at + Vector3(0, 0, -0.55), 0.0, mirror)
		_p(m, "furniture/Chair", at + Vector3(-1.1, 0, -0.55), PI * 0.5, mirror)
		_p(m, "furniture/Chair_Cushion", at + Vector3(1.1, 0, -0.55), -PI * 0.5, mirror)
		_p(m, "survival/Bottle", at + Vector3(0.1, 0.82, -0.5), 0.0, mirror, 2.4)


static func _bathroom(m, at: Vector3, wall_z: float, mirror: bool) -> void:
	var z := wall_z - 0.7
	_p(m, "furniture/Bathtub", at + Vector3(0.2, 0, z - at.z), 0.0, mirror)
	_p(m, "furniture/Toilet", at + Vector3(-1.6, 0, z - at.z + 0.1), PI, mirror)
	_p(m, "furniture/Washer", at + Vector3(1.9, 0, z - at.z + 0.2), PI, mirror)
	m._model("furniture/Rug_Round", at + Vector3(0.5, 0.01, -0.2), 0.0, F * 0.8, mirror, "none", false)


static func _living(m, at: Vector3, wall_z: float, mirror: bool) -> void:
	var s := signf(wall_z - at.z)
	m._model("furniture/Rug_Rectangle", at + Vector3(0, 0.01, 0.2), 0.0, F, mirror, "none", false)
	_p(m, "furniture/Lounge_Sofa", at + Vector3(0, 0, -s * 1.1), 0.0 if s < 0 else PI, mirror)
	_p(m, "furniture/Pillow_Blue", at + Vector3(-0.5, 0.55, -s * 1.1), 0.3, mirror)
	_p(m, "furniture/Table_Coffee", at + Vector3(0, 0, 0.1), 0.0, mirror)
	_p(m, "furniture/Books", at + Vector3(0.2, 0.52, 0.1), 0.4, mirror)
	_p(m, "furniture/Cabinet_Television", at + Vector3(0, 0, wall_z - at.z - s * 0.5), PI if s < 0 else 0.0, mirror)
	_p(m, "furniture/Television_Modern", at + Vector3(0, 0.69, wall_z - at.z - s * 0.5), PI if s < 0 else 0.0, mirror)
	_p(m, "furniture/Lamp_Round_Floor", at + Vector3(1.5, 0, -s * 1.2), 0.0, mirror)
	_p(m, "furniture/Potted_Plant", at + Vector3(-1.6, 0, wall_z - at.z - s * 0.5), 0.0, mirror)
	_p(m, "furniture/Speaker", at + Vector3(1.3, 0, wall_z - at.z - s * 0.45), 0.0, mirror)


static func _bedroom(m, at: Vector3, wall_z: float, mirror: bool, double: bool) -> void:
	var s := signf(wall_z - at.z)
	var z := wall_z - at.z - s * 1.35
	m._model("furniture/Rug_Round", at + Vector3(0.9, 0.01, z - s * 0.6), 0.0, F, mirror, "none", false)
	_p(m, "furniture/Bed_Double" if double else "furniture/Bed_Single", at + Vector3(-0.4, 0, z), 0.0 if s > 0 else PI, mirror)
	_p(m, "furniture/Side_Table", at + Vector3(1.05, 0, wall_z - at.z - s * 0.4), 0.0 if s < 0 else PI, mirror)
	_p(m, "furniture/Lamp_Round_Table", at + Vector3(1.05, 0.84, wall_z - at.z - s * 0.4), 0.0, mirror)
	_p(m, "furniture/Bookcase_Open", at + Vector3(-1.9, 0, wall_z - at.z - s * 0.4), 0.0 if s < 0 else PI, mirror)
	_p(m, "furniture/Coat_Rack_Standing", at + Vector3(1.9, 0, z - s * 1.2), 0.0, mirror)
	if double:
		_p(m, "furniture/Bear", at + Vector3(-0.2, 0.84, z + s * 0.5), 2.4, mirror)


static func _office(m, at: Vector3, wall_z: float, mirror: bool, face := 0.0) -> void:
	var s := signf(wall_z - at.z)
	var z := wall_z - at.z - s * 0.6
	_p(m, "furniture/Desk", at + Vector3(-0.3, 0, z), 0.0 if s < 0 else PI, mirror)
	_p(m, "furniture/Computer_Screen", at + Vector3(-0.3, 0.84, z + s * 0.12), 0.0 if s < 0 else PI, mirror)
	_p(m, "furniture/Computer_Keyboard", at + Vector3(-0.3, 0.84, z - s * 0.22), 0.0, mirror)
	_p(m, "furniture/Chair_Desk", at + Vector3(-0.3, 0, z - s * 0.95), PI if s < 0 else 0.0, mirror)
	_p(m, "furniture/Bookcase_Closed_Wide", at + Vector3(1.7, 0, wall_z - at.z - s * 0.4), 0.0 if s < 0 else PI, mirror)
	_p(m, "furniture/Trashcan", at + Vector3(-1.5, 0, z), 0.0, mirror)
	_p(m, "furniture/Plant_Small_1", at + Vector3(1.7, 1.72, wall_z - at.z - s * 0.4), 0.0, mirror)


static func _reception(m, at: Vector3, wall_z: float, mirror: bool) -> void:
	var s := signf(wall_z - at.z)
	_p(m, "furniture/Kitchen_Bar", at + Vector3(-0.5, 0, 0.6 * -s), PI * 0.5, mirror, F * 1.25)
	_p(m, "furniture/Laptop", at + Vector3(-0.5, 1.14, 0.6 * -s), PI * 0.5, mirror)
	_p(m, "furniture/Chair_Desk", at + Vector3(0.5, 0, 0.6 * -s), -PI * 0.5, mirror)
	for i in 3:
		_p(m, "furniture/Bench_Cushion", at + Vector3(-1.2 + i * 0.95, 0, wall_z - at.z - s * 0.4), 0.0 if s < 0 else PI, mirror)
	_p(m, "furniture/Potted_Plant", at + Vector3(1.9, 0, wall_z - at.z - s * 0.5), 0.0, mirror)
	_p(m, "furniture/Coat_Rack_Standing", at + Vector3(-2.1, 0, wall_z - at.z - s * 0.4), 0.0, mirror)


static func _ward(m, at: Vector3, wall_z: float, mirror: bool, beds: int) -> void:
	var s := signf(wall_z - at.z)
	for i in beds:
		var x := (i - (beds - 1) * 0.5) * 1.7
		_p(m, "furniture/Bed_Single", at + Vector3(x, 0, wall_z - at.z - s * 1.35), 0.0 if s > 0 else PI, mirror)
		_p(m, "furniture/Side_Table", at + Vector3(x + 0.8, 0, wall_z - at.z - s * 0.35), 0.0 if s < 0 else PI, mirror, F * 0.7)
		# A screen between beds.
		if i > 0:
			m._box(at + Vector3(x - 0.85, 0.9, wall_z - at.z - s * 1.2), Vector3(0.05, 1.8, 1.9), _mat(m, ["trim", "block_a"]), mirror, 0.0, false)
	_p(m, "furniture/Coat_Rack_Standing", at + Vector3(-(beds * 0.85 + 0.3), 0, wall_z - at.z - s * 0.4), 0.0, mirror)


static func _motel_room(m, at: Vector3, wall_z: float, mirror: bool, flip := false) -> void:
	var s := signf(wall_z - at.z)
	_p(m, "furniture/Bed_Double", at + Vector3(-0.6, 0, wall_z - at.z - s * 1.35), 0.0 if s > 0 else PI, mirror)
	_p(m, "furniture/Pillow", at + Vector3(-0.6, 0.84, wall_z - at.z - s * 0.7), 0.0, mirror)
	_p(m, "furniture/Side_Table", at + Vector3(0.9, 0, wall_z - at.z - s * 0.35), 0.0 if s < 0 else PI, mirror)
	_p(m, "furniture/Lamp_Round_Table", at + Vector3(0.9, 0.84, wall_z - at.z - s * 0.35), 0.0, mirror)
	_p(m, "furniture/Television_Vintage", at + Vector3(1.9, 0.0, wall_z - at.z - s * 2.2), -PI * 0.5, mirror)
	_p(m, "furniture/Chair_Rounded", at + Vector3(-1.9, 0, wall_z - at.z - s * 2.3), 0.6 if not flip else -0.6, mirror)


static func _shop(m, c: Vector3, sx: float, sz: float, y: float, mirror: bool) -> void:
	# Shelf aisles running back from the shop front, a counter by the door
	# with the till, fridges along the east wall, stock boxes.
	var rows := clampi(int((sx - 5.0) / 2.2), 1, 3)
	for r in rows:
		var x := c.x - sx * 0.5 + 2.9 + r * 2.1
		for i in 2:
			var z := c.z - sz * 0.3 + i * 1.0
			_p(m, "furniture/Bookcase_Open", Vector3(x, y, z), PI * 0.5, mirror)
			_p(m, "furniture/Bookcase_Open", Vector3(x + 0.56, y, z), -PI * 0.5, mirror)
		_p(m, "furniture/Cardboard_Box_Open", Vector3(x + 0.3, y, c.z - sz * 0.3 + 2.0), 0.3 * r, mirror)
	var cx := c.x + sx * 0.5 - 2.4
	_p(m, "furniture/Kitchen_Bar", Vector3(cx, y, c.z - sz * 0.5 + 1.6), 0.0, mirror, F * 1.3)
	_p(m, "furniture/Laptop", Vector3(cx, y + 1.18, c.z - sz * 0.5 + 1.6), PI, mirror)
	_p(m, "furniture/Stool_Bar", Vector3(cx, y, c.z - sz * 0.5 + 2.5), 0.0, mirror)
	_p(m, "furniture/Kitchen_Fridge", Vector3(c.x + sx * 0.5 - 0.75, y, c.z - sz * 0.5 + 3.4), -PI * 0.5, mirror)
	_p(m, "furniture/Trashcan", Vector3(c.x - 1.4, y, c.z - sz * 0.5 + 0.8), 0.0, mirror)


static func _storage(m, at: Vector3, wall_z: float, mirror: bool) -> void:
	var s := signf(wall_z - at.z)
	var z := wall_z - at.z - s * 0.8
	var crate := _mat(m, ["crate"])
	m._box(at + Vector3(-1.2, 0.5, z), Vector3(1.0, 1.0, 1.0), crate, mirror)
	m._box(at + Vector3(-0.1, 0.5, z), Vector3(1.0, 1.0, 1.0), crate, mirror)
	m._box(at + Vector3(-0.6, 1.5, z), Vector3(1.0, 1.0, 1.0), crate, mirror)
	_p(m, "furniture/Bookcase_Closed_Wide", at + Vector3(1.6, 0, wall_z - at.z - s * 0.4), 0.0 if s < 0 else PI, mirror)
	_p(m, "furniture/Cardboard_Box_Closed", at + Vector3(1.0, 0, z - s * 1.2), 0.5, mirror, 2.4)
	_p(m, "furniture/Cardboard_Box_Closed", at + Vector3(1.6, 0, z - s * 1.4), 1.1, mirror, 2.4)
	_p(m, "survival/Barrel", at + Vector3(-1.9, 0, z - s * 1.2), 0.0, mirror, 3.0)


static func _bunks(m, at: Vector3, wall_z: float, mirror: bool) -> void:
	var s := signf(wall_z - at.z)
	for i in 3:
		var x := (i - 1) * 1.6
		_p(m, "furniture/Bed_Single", at + Vector3(x, 0, wall_z - at.z - s * 1.35), 0.0 if s > 0 else PI, mirror)
		m._box(at + Vector3(x, 0.3, wall_z - at.z - s * 2.9), Vector3(0.9, 0.6, 0.5), _mat(m, ["olive", "crate"]), mirror)
	_p(m, "furniture/Bookcase_Closed_Wide", at + Vector3(2.7, 0, wall_z - at.z - s * 0.4), 0.0 if s < 0 else PI, mirror)


static func _briefing(m, at: Vector3, mirror: bool) -> void:
	_p(m, "furniture/Table", at, 0.0, mirror)
	_p(m, "furniture/Radio", at + Vector3(-0.4, 0.75, 0), 0.5, mirror)
	_p(m, "furniture/Books", at + Vector3(0.4, 0.75, 0.1), 1.0, mirror)
	for sgn in [-1.0, 1.0]:
		_p(m, "furniture/Chair", at + Vector3(sgn * 0.5, 0, 0.95), PI, mirror)
		_p(m, "furniture/Chair", at + Vector3(sgn * 0.5, 0, -0.95), 0.0, mirror)
	_p(m, "survival/Box_Large", at + Vector3(1.9, 0, -0.8), 0.3, mirror, 3.0)


static func _lab(m, at: Vector3, wall_z: float, mirror: bool) -> void:
	var s := signf(wall_z - at.z)
	for i in 2:
		var x := -1.0 + i * 1.7
		_p(m, "furniture/Desk", at + Vector3(x, 0, wall_z - at.z - s * 0.6), 0.0 if s < 0 else PI, mirror)
		_p(m, "furniture/Computer_Screen", at + Vector3(x, 0.84, wall_z - at.z - s * 0.5), 0.0 if s < 0 else PI, mirror)
		_p(m, "furniture/Chair_Desk", at + Vector3(x, 0, wall_z - at.z - s * 1.5), PI if s < 0 else 0.0, mirror)
	# Server racks with status lights.
	for i in 2:
		var rp: Vector3 = at + Vector3(2.3, 1.0, wall_z - at.z - s * (0.5 + i * 0.9))
		m._box(rp, Vector3(0.7, 2.0, 0.8), "dark", mirror)
		m._box(rp + Vector3(-0.36, 0.4, 0), Vector3(0.03, 0.08, 0.5), "accent_b", mirror, 0.0, false)
		m._box(rp + Vector3(-0.36, 0.1, 0), Vector3(0.03, 0.08, 0.5), "accent_a", mirror, 0.0, false)
	_p(m, "blaster/Crate_Small", at + Vector3(-2.2, 0, wall_z - at.z - s * 0.6), 0.2, mirror, 1.6)


static func _workshop(m, at: Vector3, wall_z: float, mirror: bool) -> void:
	var s := signf(wall_z - at.z)
	m._model("survival/Workbench", at + Vector3(-0.6, 0, wall_z - at.z - s * 0.7), 0.0 if s < 0 else PI, 3.0, mirror)
	_p(m, "fantasy/Anvil", at + Vector3(1.2, 0, wall_z - at.z - s * 1.6), 0.5, mirror, 1.1)
	_p(m, "survival/Bucket", at + Vector3(1.9, 0, wall_z - at.z - s * 0.6), 0.0, mirror, 2.6)
	_p(m, "survival/Barrel", at + Vector3(-2.1, 0, wall_z - at.z - s * 0.7), 0.0, mirror, 3.0)
	# The forge: a brick hearth with a glow.
	m._box(at + Vector3(2.0, 0.5, wall_z - at.z - s * 2.6), Vector3(1.1, 1.0, 1.1), _mat(m, ["block_b", "wall"]), mirror)
	m._box(at + Vector3(2.0, 1.02, wall_z - at.z - s * 2.6), Vector3(0.8, 0.06, 0.8), "accent_a", mirror, 0.0, false)
	m._glow(at + Vector3(2.0, 1.5, wall_z - at.z - s * 2.6), Color(1.0, 0.45, 0.12), 6.0, 1.6, mirror)


static func _cabin(m, c: Vector3, sx: float, sz: float, y: float, mirror: bool) -> void:
	var north := c.z + sz * 0.5 - 0.3
	m._model("furniture/Rug_Rectangle", Vector3(c.x + 0.6, y + 0.01, c.z - 0.3), PI * 0.5, F * 1.1, mirror, "none", false)
	_p(m, "furniture/Bed_Single", Vector3(c.x + sx * 0.5 - 1.2, y, north - 1.3), 0.0, mirror)
	_p(m, "furniture/Bear", Vector3(c.x + sx * 0.5 - 1.2, y + 0.84, north - 1.0), 2.6, mirror)
	_p(m, "furniture/Table_Round", Vector3(c.x + 0.4, y, c.z - 0.2), 0.0, mirror)
	_p(m, "furniture/Chair", Vector3(c.x + 0.4, y, c.z - 1.3), 0.0, mirror)
	_p(m, "fantasy/Mug", Vector3(c.x + 0.3, y + 0.82, c.z - 0.2), 0.4, mirror, 1.3)
	_p(m, "furniture/Bookcase_Open", Vector3(c.x + 0.6, y, north - 0.4), PI, mirror)
	# Hearth against the west wall under the chimney, with a warm glow.
	var hx := c.x - sx * 0.5 + 0.75
	m._box(Vector3(hx, y + 0.6, c.z), Vector3(0.9, 1.2, 1.5), _mat(m, ["wall", "block_b"]), mirror)
	m._box(Vector3(hx + 0.47, y + 0.45, c.z), Vector3(0.05, 0.6, 0.9), "accent_a", mirror, 0.0, false)
	m._glow(Vector3(hx + 1.2, y + 0.8, c.z), Color(1.0, 0.5, 0.18), 6.5, 1.7, mirror)
	_p(m, "survival/Bucket", Vector3(hx + 0.2, y, c.z + 1.3), 0.0, mirror, 2.6)


static func _garage(m, c: Vector3, sx: float, sz: float, y: float, mirror: bool) -> void:
	var north := c.z + sz * 0.5 - 0.3
	m._model("survival/Workbench", Vector3(c.x + 0.4, y, north - 0.6), PI, 3.0, mirror)
	_p(m, "furniture/Washer", Vector3(c.x + sx * 0.5 - 0.8, y, north - 0.6), PI, mirror)
	_p(m, "furniture/Bookcase_Open", Vector3(c.x + sx * 0.5 - 0.6, y, c.z + 0.6), -PI * 0.5, mirror)
	_p(m, "furniture/Cardboard_Box_Closed", Vector3(c.x + 1.0, y, c.z - sz * 0.5 + 1.0), 0.4, mirror, 2.4)
	_p(m, "furniture/Cardboard_Box_Open", Vector3(c.x + 1.7, y, c.z - sz * 0.5 + 1.1), 1.2, mirror, 2.4)
	_p(m, "toon/Prop/Gas_Can", Vector3(c.x + 0.2, y, c.z - sz * 0.5 + 0.8), 0.0, mirror, 0.8)
	_p(m, "furniture/Trashcan", Vector3(c.x + sx * 0.5 - 0.7, y, c.z - sz * 0.5 + 0.9), 0.0, mirror)


## A narrow club stand (stairs on the west wall below, east wall above).
## Ground floor: a bar along the back wall with stools, two tables, a TV.
## Upper floor: a lit trophy cabinet, a lounge under the front window.
static func _clubhouse(m, c: Vector3, sx: float, sz: float, y: float, mirror: bool, upper: bool) -> void:
	var b := Vector3(c.x, y, c.z)
	var n := sz * 0.5 - 0.3
	var e := sx * 0.5 - 0.3
	if not upper:
		for i in 3:
			_p(m, "furniture/Kitchen_Bar", b + Vector3(-1.0 + i * 1.16, 0, n - 1.1), 0.0, mirror, F * 1.25)
			_p(m, "furniture/Stool_Bar", b + Vector3(-1.0 + i * 1.16, 0, n - 2.0), 0.0, mirror)
		_p(m, "furniture/Kitchen_Coffee_Machine", b + Vector3(-1.0, 1.14, n - 1.1), PI, mirror)
		_p(m, "survival/Bottle", b + Vector3(0.3, 1.14, n - 1.05), 0.0, mirror, 2.4)
		_p(m, "survival/Bottle", b + Vector3(0.55, 1.14, n - 1.15), 0.0, mirror, 2.4)
		_p(m, "furniture/Bookcase_Open", b + Vector3(0.0, 0, n - 0.32), PI, mirror)
		_p(m, "furniture/Kitchen_Fridge", b + Vector3(e - 0.5, 0, n - 0.45), PI, mirror)
		_p(m, "furniture/Table_Round", b + Vector3(1.6, 0, 1.9), 0.0, mirror)
		_p(m, "furniture/Chair", b + Vector3(0.45, 0, 1.9), PI * 0.5, mirror)
		_p(m, "furniture/Chair", b + Vector3(2.75, 0, 1.9), -PI * 0.5, mirror)
		_p(m, "furniture/Table_Round", b + Vector3(2.1, 0, -3.5), 0.0, mirror)
		_p(m, "furniture/Chair", b + Vector3(2.1, 0, -4.6), 0.0, mirror)
		_p(m, "furniture/Chair", b + Vector3(2.1, 0, -2.4), PI, mirror)
		_p(m, "furniture/Cabinet_Television", b + Vector3(-2.6, 0, -n + 0.45), PI, mirror)
		_p(m, "furniture/Television_Modern", b + Vector3(-2.6, 0.69, -n + 0.45), PI, mirror)
		_p(m, "furniture/Potted_Plant", b + Vector3(-3.1, 0, n - 0.5), 0.0, mirror)
	else:
		m._box(b + Vector3(-0.3, 0.45, n - 0.3), Vector3(3.0, 0.9, 0.55), "dark", mirror)
		m._box(b + Vector3(-0.3, 1.35, n - 0.3), Vector3(2.9, 0.9, 0.5), "glass", mirror)
		for i in 3:
			m._model("fantasy/Chalice", b + Vector3(-1.3 + i * 1.0, 0.9, n - 0.3), 0.5 * i, 2.8 - 0.4 * absf(i - 1), mirror, "none")
		m._glow(b + Vector3(-0.3, 2.4, n - 0.9), Color(1.0, 0.85, 0.6), 3.5, 0.8, mirror)
		m._model("furniture/Rug_Rectangle", b + Vector3(0, 0.01, -n + 1.6), 0.0, F, mirror, "none", false)
		_p(m, "furniture/Lounge_Sofa", b + Vector3(0, 0, -n + 0.6), PI, mirror)
		_p(m, "furniture/Table_Coffee", b + Vector3(0, 0, -n + 1.7), 0.0, mirror)
		_p(m, "furniture/Lounge_Chair", b + Vector3(-1.5, 0, -n + 1.8), PI * 0.5, mirror)
		_p(m, "furniture/Lounge_Chair", b + Vector3(1.2, 0, -n + 1.9), -PI * 0.5, mirror)
		_p(m, "furniture/Potted_Plant", b + Vector3(-3.1, 0, -n + 0.5), 0.0, mirror)
