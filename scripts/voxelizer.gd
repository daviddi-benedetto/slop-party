extends RefCounted
## The voxel prop workflow: turns ANY model (or list of meshes) into real
## voxel geometry in the game's one voxel size (Voxel.SIZE), so imported
## props, trees, kit buildings and vehicles all share the Teardown-like look.
##
## How it works (voxelize()):
##  1. Rasterize: every triangle is sampled densely; each sample lands in a
##     cell of a 3D grid and adds its colour there: material colour x
##     texture at the sample's UV x vertex colour (alpha-scissored texels,
##     e.g. leaf cards, are skipped; emissive materials are marked).
##  2. Fill: a flood fill from the grid border finds the outside; every cell
##     that is not outside counts as solid, so no faces are made inside.
##  3. Greedy mesh: for each of the 6 directions, exposed faces are merged
##     into the largest rectangles (whatever their colours), which keeps the
##     triangle count tiny: a flat wall is a handful of quads.
##  4. Colour: the averaged cell colours go into a small 3D texture that the
##     voxel prop shader (PROP_CODE) reads with the cell under each pixel,
##     so every voxel shows its own colour on the merged quads.
##
## Results are cached in memory, on disk in user://voxel_cache/, and can be
## baked into the game (res://assets/voxel/) with tools/voxel_bake.gd, so a
## player never waits for voxelization. Adding a new prop to the game is:
## drop the model in assets/models, place it with map._model() (or
## prop.gd), and it is voxelized automatically; bake before a release.
##
## Model scale: the voxel size in the model's own units is SIZE / scale,
## rounded to half-octave buckets so a model placed at similar scales
## shares one voxelization (voxels stay within ~20 % of SIZE in the world).

const Voxel = preload("res://scripts/voxel.gd")
const Looks = preload("res://scripts/looks.gd")
const VERSION := 3
const MAX_DIM := 96
const FAR_STEPS := 3              # far version: voxels 2^(3/2) = 2.8x bigger
const FAR_FROM := 34.0            # metres: map.gd draws the far version beyond this
const BAKED := "res://assets/voxel/"
const USER := "user://voxel_cache/"

## The material for voxel props: colour from the 3D texture, a faint
## per-voxel variation, the theme's colour grade, optional wind sway and
## emission (cells whose alpha is below 1 glow).
const PROP_CODE := """
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx%s;
uniform sampler3D cols : source_color, filter_nearest, repeat_disable;
uniform vec3 dims = vec3(1.0);
uniform vec3 origin = vec3(0.0);
uniform float cell = 0.1;
uniform float rough = 0.85;
uniform float sway = 0.0;
uniform float emit = 2.4;
uniform float sat = 1.0;
uniform float val = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float pastel = 0.0;
varying vec3 l_pos;
varying vec3 l_nrm;
float h3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}
void vertex() {
	l_pos = VERTEX;
	l_nrm = NORMAL;
	if (sway > 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float h = clamp(w.y - 0.4, 0.0, 7.0);
		float s = sin(TIME * 1.25 + w.x * 0.31 + w.z * 0.23) + 0.35 * sin(TIME * 3.1 + w.x * 1.7 + w.z * 1.3);
		vec3 off = vec3(s, 0.0, s * 0.55) * sway * h * h * 0.0035;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
	}
}
void fragment() {
	vec3 g = (l_pos - origin) / cell - normalize(l_nrm) * 0.5;
	vec3 c = floor(g);
	vec4 v = texture(cols, (c + 0.5) / dims);
	// Fade the per-voxel variation out where voxels get smaller than a few
	// pixels, so far props do not sparkle.
	vec3 fw = fwidth(g);
	float amt = smoothstep(2.0, 5.0, 1.0 / max(max(fw.x, fw.y), max(fw.z, 1e-4)));
	vec3 col = v.rgb * mix(1.0, 0.93 + 0.14 * h3(c), amt);
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = clamp(mix(vec3(l), col, sat) * val, 0.0, 1.0) * tint;
	col = mix(col, vec3(1.0), pastel);
	ALBEDO = col;
	ROUGHNESS = rough;
	RIM = 0.18;
	RIM_TINT = 0.6;
	EMISSION = v.rgb * (1.0 - v.a) * emit;
}
"""

static var _mem := {}          # key -> voxel data (Dictionary)
static var _meshes := {}       # key -> ArrayMesh
static var _tex := {}          # key -> ImageTexture3D
static var _mats := {}         # key|theme|sway -> ShaderMaterial
static var _images := {}       # texture instance id -> Image (decompressed)
static var _shaders := {}
static var stats := {"live": 0, "cached": 0, "ms": 0}
## tools: write voxelizations into the game (res://assets/voxel/) instead
## of the player's cache (main.gd --voxel-bake).
static var bake := false


## Voxel size (model units) for a model placed at `scale`, and the cache key.
static func _bucket(path: String, scale: float) -> Array:
	var want := Voxel.SIZE / maxf(scale, 0.001)
	var b := roundi(log(want) / log(2.0) * 2.0)
	return [pow(2.0, b * 0.5), "%s@%d" % [path, b]]


## The voxel version of a model (models.gd path) placed at `scale`:
## [ArrayMesh, Material]. sway: foliage bends in the wind. far: a coarse
## version (voxels FAR_STEPS half-octaves bigger, a fraction of the
## triangles) for drawing far away (map.gd swaps it in by distance).
static func model(path: String, parts: Array, scale: float, sway := false, far := false) -> Array:
	var bk := _bucket(path, scale)
	var key: String = bk[1]
	var vs: float = bk[0]
	if far:
		key += "f"
		vs *= pow(2.0, FAR_STEPS * 0.5)
	var d := _data(key, parts, vs)
	if d.is_empty():
		return []
	return [_mesh(key, d), _material(key, d, sway)]


static func _data(key: String, parts: Array, vs: float) -> Dictionary:
	if _mem.has(key):
		return _mem[key]
	var file := key.replace("/", "_").replace("@", "_") + ".vox"
	var d := _load(BAKED + file)
	if d.is_empty():
		d = _load(USER + file)
		if bake and not d.is_empty():
			DirAccess.make_dir_recursive_absolute(BAKED)
			_save(BAKED + file, d)
	if d.is_empty():
		var t0 := Time.get_ticks_msec()
		d = voxelize(parts, vs)
		stats.ms += Time.get_ticks_msec() - t0
		stats.live += 1
		var dir := BAKED if bake else USER
		DirAccess.make_dir_recursive_absolute(dir)
		_save(dir + file, d)
	else:
		stats.cached += 1
	_mem[key] = d
	return d


static func _load(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open_compressed(p, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var d = f.get_var()
	if not (d is Dictionary) or d.get("v", 0) != VERSION:
		return {}
	return d


static func _save(p: String, d: Dictionary) -> void:
	var f := FileAccess.open_compressed(p, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f != null:
		f.store_var(d)


static func _mesh(key: String, d: Dictionary) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = d.verts
	arr[Mesh.ARRAY_NORMAL] = d.norms
	arr[Mesh.ARRAY_INDEX] = d.idx
	var m := ArrayMesh.new()
	if (d.verts as PackedVector3Array).size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[key] = m
	return m


static func _material(key: String, d: Dictionary, sway: bool) -> ShaderMaterial:
	var look: Dictionary = Voxel.look
	var mk := "%s|%s|%s" % [key, look.get("key", ""), sway]
	if _mats.has(mk):
		return _mats[mk]
	if not _tex.has(key):
		var dims: Vector3i = d.dims
		var slices: Array[Image] = []
		var bytes: PackedByteArray = d.cols
		var per := dims.x * dims.y * 4
		for z in dims.z:
			slices.append(Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RGBA8, bytes.slice(z * per, (z + 1) * per)))
		var t := ImageTexture3D.new()
		t.create(Image.FORMAT_RGBA8, dims.x, dims.y, dims.z, false, slices)
		_tex[key] = t
	var double: bool = sway or d.get("double", false)
	if not _shaders.has(double):
		var s := Shader.new()
		s.code = PROP_CODE % (", cull_disabled" if double else "")
		_shaders[double] = s
	var m := ShaderMaterial.new()
	m.shader = _shaders[double]
	m.set_shader_parameter("cols", _tex[key])
	m.set_shader_parameter("dims", Vector3(d.dims))
	m.set_shader_parameter("origin", d.origin)
	m.set_shader_parameter("cell", d.vs)
	m.set_shader_parameter("sway", 1.0 if sway else 0.0)
	var g: Dictionary = look.get("grade", {})
	m.set_shader_parameter("sat", float(g.get("sat", 1.0)) * 1.1)
	m.set_shader_parameter("val", float(g.get("val", 1.0)) * 1.04)
	var tn: Color = g.get("tint", Color.WHITE)
	m.set_shader_parameter("tint", Vector3(tn.r, tn.g, tn.b))
	m.set_shader_parameter("pastel", float(g.get("pastel", 0.0)))
	_mats[mk] = m
	return m


# --------------------------------------------------------------------------
# Voxelization
# --------------------------------------------------------------------------

## parts: [[Mesh, Transform3D], ...] in model space. vs: voxel size there.
## Returns the voxel data: dims, origin, vs, verts, norms, idx, cols.
static func voxelize(parts: Array, vs: float) -> Dictionary:
	var box := AABB()
	var first := true
	for p in parts:
		var a: AABB = p[1] * (p[0] as Mesh).get_aabb()
		box = a if first else box.merge(a)
		first = false
	if first:
		return {}
	var biggest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if biggest / vs > MAX_DIM - 2:
		vs = biggest / float(MAX_DIM - 2)
	var origin := box.position - Vector3.ONE * vs
	var dims := Vector3i((box.size / vs).ceil()) + Vector3i(3, 3, 3)
	var n := dims.x * dims.y * dims.z
	var sums := PackedFloat32Array()
	sums.resize(n * 4)
	var counts := PackedInt32Array()
	counts.resize(n)
	var glow := PackedByteArray()
	glow.resize(n)
	var double := false
	var step := vs * 0.55
	for p in parts:
		var mesh: Mesh = p[0]
		var xf: Transform3D = p[1]
		for si in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat: Material = mesh.surface_get_material(si)
			var base := Color.WHITE
			var img: Image = null
			var use_vcol := false
			var scissor := -1.0
			var emissive := false
			var uv_s := Vector2.ONE
			var uv_o := Vector2.ZERO
			if mat is BaseMaterial3D:
				var bm: BaseMaterial3D = mat
				base = bm.albedo_color
				use_vcol = bm.vertex_color_use_as_albedo
				img = _image(bm.albedo_texture)
				uv_s = Vector2(bm.uv1_scale.x, bm.uv1_scale.y)
				uv_o = Vector2(bm.uv1_offset.x, bm.uv1_offset.y)
				if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					scissor = 0.5
				emissive = bm.emission_enabled and bm.emission.get_luminance() > 0.05
				if bm.cull_mode == BaseMaterial3D.CULL_DISABLED:
					double = true
			var a := mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var vcols: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				idx.resize(verts.size())
				for i in verts.size():
					idx[i] = i
			var has_uv := uvs.size() == verts.size() and img != null
			var has_vc := use_vcol and vcols.size() == verts.size()
			var iw := img.get_width() if img != null else 1
			var ih := img.get_height() if img != null else 1
			for t in range(0, idx.size() - 2, 3):
				var i0 := idx[t]
				var i1 := idx[t + 1]
				var i2 := idx[t + 2]
				var p0: Vector3 = xf * verts[i0]
				var p1: Vector3 = xf * verts[i1]
				var p2: Vector3 = xf * verts[i2]
				var e := maxf(p0.distance_to(p1), maxf(p1.distance_to(p2), p2.distance_to(p0)))
				var steps := maxi(1, ceili(e / step))
				var inv := 1.0 / steps
				for si2 in steps + 1:
					for sj in steps + 1 - si2:
						var u := si2 * inv
						var v := sj * inv
						var w := 1.0 - u - v
						var pos: Vector3 = p0 * w + p1 * u + p2 * v
						var c := base
						if has_uv:
							var uv: Vector2 = (uvs[i0] * w + uvs[i1] * u + uvs[i2] * v) * uv_s + uv_o
							var px := posmod(int(floor(uv.x * iw)), iw)
							var py := posmod(int(floor(uv.y * ih)), ih)
							var tc := img.get_pixel(px, py)
							if scissor > 0.0 and tc.a < scissor:
								continue
							c = c * tc
						if has_vc:
							c = c * (vcols[i0] * w + vcols[i1] * u + vcols[i2] * v)
						var g := Vector3i(((pos - origin) / vs).floor())
						if g.x < 0 or g.y < 0 or g.z < 0 or g.x >= dims.x or g.y >= dims.y or g.z >= dims.z:
							continue
						var ci := g.x + dims.x * (g.y + dims.y * g.z)
						sums[ci * 4] += c.r
						sums[ci * 4 + 1] += c.g
						sums[ci * 4 + 2] += c.b
						counts[ci] += 1
						if emissive:
							glow[ci] = 1
	# Flood fill the outside from the border (6-connected).
	var outside := PackedByteArray()
	outside.resize(n)
	var queue := PackedInt32Array()
	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				if x == 0 or y == 0 or z == 0 or x == dims.x - 1 or y == dims.y - 1 or z == dims.z - 1:
					var ci := x + dims.x * (y + dims.y * z)
					if counts[ci] == 0:
						outside[ci] = 1
						queue.append(ci)
	var head := 0
	var sx := 1
	var sy := dims.x
	var sz := dims.x * dims.y
	while head < queue.size():
		var ci := queue[head]
		head += 1
		var x := ci % dims.x
		var y := (ci / dims.x) % dims.y
		var z := ci / sz
		for k in 6:
			var nb := -1
			match k:
				0: nb = ci - sx if x > 0 else -1
				1: nb = ci + sx if x < dims.x - 1 else -1
				2: nb = ci - sy if y > 0 else -1
				3: nb = ci + sy if y < dims.y - 1 else -1
				4: nb = ci - sz if z > 0 else -1
				5: nb = ci + sz if z < dims.z - 1 else -1
			if nb >= 0 and outside[nb] == 0 and counts[nb] == 0:
				outside[nb] = 1
				queue.append(nb)
	# Colours (RGBA8; alpha < 255 = emissive). Solid cells without samples
	# (inside) are never seen.
	var cols := PackedByteArray()
	cols.resize(n * 4)
	for ci in n:
		var cn := counts[ci]
		if cn > 0:
			var k := 1.0 / cn
			cols[ci * 4] = clampi(int(sums[ci * 4] * k * 255.0), 0, 255)
			cols[ci * 4 + 1] = clampi(int(sums[ci * 4 + 1] * k * 255.0), 0, 255)
			cols[ci * 4 + 2] = clampi(int(sums[ci * 4 + 2] * k * 255.0), 0, 255)
			cols[ci * 4 + 3] = 60 if glow[ci] == 1 else 255
	# Exposed faces: 6 colour-blind greedy passes.
	var mv := PackedVector3Array()
	var mn := PackedVector3Array()
	var mi := PackedInt32Array()
	for axis in 3:
		var u_ax := (axis + 1) % 3
		var v_ax := (axis + 2) % 3
		var du := dims[u_ax]
		var dv := dims[v_ax]
		var dw := dims[axis]
		for di in 2:
			var dir: int = -1 if di == 0 else 1
			var nrm := Vector3.ZERO
			nrm[axis] = dir
			var mask := PackedByteArray()
			mask.resize(du * dv)
			for w in dw:
				var any := false
				for vv in dv:
					for uu in du:
						var g := Vector3i.ZERO
						g[axis] = w
						g[u_ax] = uu
						g[v_ax] = vv
						var ci := g.x + dims.x * (g.y + dims.y * g.z)
						var solid := outside[ci] == 0
						var face := 0
						if solid:
							var w2 := w + dir
							if w2 < 0 or w2 >= dw:
								face = 1
							else:
								var g2 := g
								g2[axis] = w2
								face = 1 if outside[g2.x + dims.x * (g2.y + dims.y * g2.z)] == 1 else 0
						mask[uu + du * vv] = face
						if face == 1:
							any = true
				if not any:
					continue
				for vv in dv:
					var uu := 0
					while uu < du:
						if mask[uu + du * vv] == 0:
							uu += 1
							continue
						var wlen := 1
						while uu + wlen < du and mask[uu + wlen + du * vv] == 1:
							wlen += 1
						var hlen := 1
						var grow := true
						while grow and vv + hlen < dv:
							for k in wlen:
								if mask[uu + k + du * (vv + hlen)] == 0:
									grow = false
									break
							if grow:
								hlen += 1
						for k2 in hlen:
							for k in wlen:
								mask[uu + k + du * (vv + k2)] = 0
						var plane := float(w + (1 if dir > 0 else 0))
						var c0 := Vector3.ZERO
						c0[axis] = plane
						c0[u_ax] = uu
						c0[v_ax] = vv
						var eu := Vector3.ZERO
						eu[u_ax] = wlen
						var ev := Vector3.ZERO
						ev[v_ax] = hlen
						var base_i := mv.size()
						for q in [c0, c0 + eu, c0 + eu + ev, c0 + ev]:
							mv.append(origin + (q as Vector3) * vs)
							mn.append(nrm)
						# Winding so the face points along nrm (Godot: clockwise front).
						if dir > 0:
							mi.append_array([base_i, base_i + 2, base_i + 1, base_i, base_i + 3, base_i + 2])
						else:
							mi.append_array([base_i, base_i + 1, base_i + 2, base_i, base_i + 2, base_i + 3])
						uu += wlen
	return {"v": VERSION, "dims": dims, "origin": origin, "vs": vs, "verts": mv, "norms": mn, "idx": mi, "cols": cols, "double": double}


static func _image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var id := tex.get_instance_id()
	if _images.has(id):
		return _images[id]
	var img := tex.get_image()
	if img != null:
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		# Plenty for 10 cm voxels, and fast to sample.
		if img.get_width() > 256:
			img.resize(256, maxi(1, img.get_height() * 256 / img.get_width()), Image.INTERPOLATE_BILINEAR)
		img.convert(Image.FORMAT_RGBA8)
	_images[id] = img
	return img
