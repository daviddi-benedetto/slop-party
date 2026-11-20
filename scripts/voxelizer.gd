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
const VERSION := 10
const MAX_DIM := 96
const FAR_STEPS := 2              # far version: voxels 2x bigger
const FAR_FROM := 55.0            # metres: map.gd cross-fades to the far version here
const FAR_FADE := 14.0            # metres of dithered cross-fade (no visible pop)
const BAKED := "res://assets/voxel/"
const USER := "user://voxel_cache/"

## The material for voxel meshes. Each exposed face cell has one texel in a
## 2D colour atlas (UV = its texel, in pixels; UV2 = position in face cells),
## so models can share one atlas and be merged (map.gd). Per face cell: a
## random depth (lit lip where it steps down, shadowed corner where it steps
## up, small random tilt), the theme's colour grade, optional wind sway,
## emission and player colour from alpha codes (255 plain, 60 glowing, 200
## player colour, 120 both), hit flash.
const PROP_CODE := """
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled%s;
uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D vox_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rough = 0.85;
uniform float sway = 0.0;
uniform float emit = 2.4;
uniform float sat = 1.0;
uniform float val = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float pastel = 0.0;
uniform vec3 accent : source_color = vec3(1.0);   // the player colour (voxelize_node)
uniform float flash = 0.0;                         // hit flash (character.gd)
uniform float RELIEF = 1.5;                        // how far voxels step in and out (voxels; 0 = option "Surface depth" off)
uniform float vox_strength = 1.0;                  // per-voxel tilt and light / dark variation
// Depth of the voxel at face cell c (0 flush .. 1 deepest), from the tile.
float cell_depth(vec2 c, vec2 doff) {
	float a = textureLod(vox_detail, (c + doff + 0.5) / 64.0, 3.0).a;
	return floor((1.0 - a) * 2.99) * 0.5;
}
float h2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
varying vec2 qsize;
void vertex() {
	qsize = CUSTOM0.xy;
	if (sway > 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float h = clamp(w.y - 0.4, 0.0, 7.0);
		float s = sin(TIME * 1.25 + w.x * 0.31 + w.z * 0.23) + 0.35 * sin(TIME * 3.1 + w.x * 1.7 + w.z * 1.3);
		vec3 off = vec3(s, 0.0, s * 0.55) * sway * h * h * 0.0035;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
	}
}
void fragment() {
	// Relief from the shared tile (voxel.gd detail()), offset per quad.
	vec2 qo = floor(UV - UV2 + 0.5);
	vec2 doff = floor(fract(qo * vec2(0.0731, 0.0577)) * 64.0);
	// Real depth: march into a field of voxels at three depths (flush,
	// half, full; RELIEF voxels at most), so voxels step in and out of every
	// face. Faded by the voxel's size on screen, never by distance.
	vec3 V = normalize(-VERTEX);
	vec3 vt = vec3(dot(V, TANGENT), dot(V, BINORMAL), dot(V, NORMAL));
	vec2 fw = fwidth(UV2);
	float k = RELIEF * smoothstep(4.0, 10.0, 1.0 / max(sqrt(fw.x * fw.y), 1e-4));
	vec2 p = UV2;
	vec2 cellp = floor(p);
	float hd = cell_depth(cellp, doff);
	float cur = 0.0;
	bool side = false;
	vec2 sn = vec2(0.0);
	if (k > 0.002 && vt.z > 0.06) {
		vec2 duv = vt.xy / vt.z * k / 12.0;
		for (int i = 0; i < 12; i++) {
			if (cur >= hd) {
				break;
			}
			// Never past the face's own edges (they would pick up another
			// face's colours from the atlas: thin coloured lines at seams).
			vec2 np = clamp(p - duv, vec2(0.001), qsize - vec2(0.001));
			cur += 1.0 / 12.0;
			vec2 nc = floor(np);
			if (nc != cellp) {
				float nh = cell_depth(nc, doff);
				if (cur >= nh) {
					side = true;
					sn = cellp - nc;
					if (abs(sn.x) > 0.5 && abs(sn.y) > 0.5) {
						sn.y = 0.0;
					}
					p = np;
					cellp = nc;
					hd = nh;
					break;
				}
				cellp = nc;
				hd = nh;
			}
			p = np;
		}
	} else {
		hd = 0.0;
	}
	// Colour: nearest texel up close (crisp voxels), smaller copies of the
	// atlas (mipmaps) far away, so distant voxels blend instead of shimmer.
	vec2 asz = vec2(textureSize(atlas, 0));
	vec4 v = texture(atlas, (UV + (p - UV2)) / asz);
	if (v.a < 0.01 && max(v.r, max(v.g, v.b)) < 0.01) {
		// Marched off the face into empty atlas: use the face's own colour.
		v = texture(atlas, UV / asz);
	}
	vec4 d = texture(vox_detail, (p + doff) / 64.0);
	vec2 tilt = (d.rg * 2.0 - 1.0) * 1.9 * vox_strength;
	float sh = mix(1.0, d.b * 1.25, vox_strength) * mix(1.0, mix(1.0, 0.62, vox_strength), hd);
	if (side) {
		sh *= mix(1.0, 0.62, vox_strength);
	}
	// Alpha: 1 plain, 0.5 player colour, 0 glowing (blends sensibly).
	float a = v.a;
	float aw = a >= 0.5 ? (1.0 - a) * 2.0 : a * 2.0;
	float gw = max(0.0, 1.0 - a * 2.0);
	vec3 base = mix(v.rgb, accent, aw) * COLOR.rgb;
	vec3 col = base * sh;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = clamp(mix(vec3(l), col, sat) * val, 0.0, 1.0) * tint;
	col = mix(col, vec3(1.0), pastel);
	ALBEDO = col;
	NORMAL = side ? normalize(NORMAL * 0.7 + TANGENT * sn.x + BINORMAL * sn.y) : normalize(NORMAL + TANGENT * tilt.x + BINORMAL * tilt.y);
	ROUGHNESS = 1.0;
	EMISSION = base * gw * emit * 0.7 + vec3(flash);
}
"""

static var _mem := {}          # key -> voxel data (Dictionary)
static var _meshes := {}       # key -> ArrayMesh
static var _tex := {}          # key -> ImageTexture (the model's colour atlas)
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
		key += "f%d" % FAR_STEPS
		vs *= pow(2.0, FAR_STEPS * 0.5)
	var d := _data(key, parts, vs)
	if d.is_empty() or (d.verts as PackedVector3Array).is_empty():
		return []
	return [_mesh(key, d), _material(key, d, sway), key, d]


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
		if OS.is_debug_build() and "--voxel-log" in OS.get_cmdline_user_args():
			print("[voxel] live: ", key)
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
	arr[Mesh.ARRAY_TANGENT] = d.tans
	arr[Mesh.ARRAY_TEX_UV] = d.uvs
	arr[Mesh.ARRAY_TEX_UV2] = d.uv2s
	arr[Mesh.ARRAY_CUSTOM0] = d.qs
	arr[Mesh.ARRAY_INDEX] = d.idx
	var m := ArrayMesh.new()
	if (d.verts as PackedVector3Array).size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	_meshes[key] = m
	return m


static func _material(key: String, d: Dictionary, sway: bool) -> ShaderMaterial:
	var look: Dictionary = Voxel.look
	var mk := "%s|%s|%s" % [key, look.get("key", ""), sway]
	if _mats.has(mk):
		return _mats[mk]
	if not _tex.has(key):
		_tex[key] = ImageTexture.create_from_image(atlas_image(d))
	var m := material_for(_tex[key], sway or d.get("double", false), sway)
	_mats[mk] = m
	return m


## The voxel material on a colour atlas (theme grade from Voxel.look).
## map.gd uses one for all its merged voxel models.
static func material_for(atlas: Texture2D, double: bool, sway: bool) -> ShaderMaterial:
	var look: Dictionary = Voxel.look
	if not _shaders.has(double):
		var s := Shader.new()
		s.code = PROP_CODE % (", cull_disabled" if double else "")
		_shaders[double] = s
	var m := ShaderMaterial.new()
	m.shader = _shaders[double]
	m.set_shader_parameter("atlas", atlas)
	m.set_shader_parameter("vox_detail", Voxel.detail())
	# Foliage is rough and deep; buildings and props more restrained (their
	# walls are mostly plaster, wood and stone).
	m.set_shader_parameter("RELIEF", (1.3 if sway else 0.6) if Settings.v("voxel_relief") else 0.0)
	m.set_shader_parameter("vox_strength", 0.9 if sway else 0.6)
	m.set_shader_parameter("sway", 1.0 if sway else 0.0)
	var g: Dictionary = look.get("grade", {})
	m.set_shader_parameter("sat", float(g.get("sat", 1.0)) * 1.1)
	m.set_shader_parameter("val", float(g.get("val", 1.0)) * 1.04)
	var tn: Color = g.get("tint", Color.WHITE)
	m.set_shader_parameter("tint", Vector3(tn.r, tn.g, tn.b))
	m.set_shader_parameter("pastel", float(g.get("pastel", 0.0)))
	return m


static func atlas_image(d: Dictionary) -> Image:
	var img := Image.create_from_data(d.aw, d.ah, false, Image.FORMAT_RGBA8, d.atlas)
	img.generate_mipmaps()
	return img


# --------------------------------------------------------------------------
# Voxelization
# --------------------------------------------------------------------------

## parts: [[Mesh, Transform3D], ...] in model space, optionally with a third
## element: the material per surface (overrides) and a fourth: materials
## whose voxels take the player colour (shader uniform `accent`).
## vs: voxel size there. Returns the voxel data: dims, origin, vs, verts,
## norms, idx, cols.
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
	# The grid fits the model's bounds exactly: the cells are stretched a
	# hair (about 1 %) per axis so a whole number of them spans each side,
	# and every sample is kept inside. Snap-together pieces (kit walls,
	# floors, stairs) then tile edge to edge, with no overlap and no gap:
	# before, each piece's voxels poked up to a cell past its edges and the
	# neighbours' grids did not line up (jagged double edges at every seam).
	var cells := Vector3i(maxi(1, roundi(box.size.x / vs)), maxi(1, roundi(box.size.y / vs)), maxi(1, roundi(box.size.z / vs)))
	var vs3 := Vector3(box.size.x / cells.x if box.size.x > 0.0001 else vs, box.size.y / cells.y if box.size.y > 0.0001 else vs, box.size.z / cells.z if box.size.z > 0.0001 else vs)
	var origin := box.position - vs3
	var dims := cells + Vector3i(2, 2, 2)
	var n := dims.x * dims.y * dims.z
	var sums := PackedFloat32Array()
	sums.resize(n * 4)
	var counts := PackedInt32Array()
	counts.resize(n)
	# The same per facing axis: a voxel face takes its colour from triangles
	# facing that way (a wall's front never picks up its hidden end cap,
	# which drew a thin line at every seam between pieces).
	var sums_ax := PackedFloat32Array()
	sums_ax.resize(n * 9)
	var counts_ax := PackedInt32Array()
	counts_ax.resize(n * 3)
	var glow := PackedByteArray()
	glow.resize(n)
	var double := false
	var step := vs * 0.55
	for p in parts:
		var mesh: Mesh = p[0]
		var xf: Transform3D = p[1]
		for si in mesh.get_surface_count():
			if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat: Material = mesh.surface_get_material(si)
			if p.size() > 2 and si < (p[2] as Array).size() and p[2][si] != null:
				mat = p[2][si]
			var accent_mat: bool = p.size() > 3 and (p[3] as Array).has(mat)
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
				# (Only if it really glows: the plush material has emission
				# switched on at energy 0 for the hit flash, which made every
				# voxel character glow.)
				emissive = bm.emission_enabled and bm.emission.get_luminance() * bm.emission_energy_multiplier > 0.05
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
				var tn := (p1 - p0).cross(p2 - p0).abs()
				var tax := 0 if tn.x >= tn.y and tn.x >= tn.z else (1 if tn.y >= tn.z else 2)
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
						var g := Vector3i(((pos - origin) / vs3).floor()).clamp(Vector3i.ONE, cells)
						if g.x < 0 or g.y < 0 or g.z < 0 or g.x >= dims.x or g.y >= dims.y or g.z >= dims.z:
							continue
						var ci := g.x + dims.x * (g.y + dims.y * g.z)
						sums[ci * 4] += c.r
						sums[ci * 4 + 1] += c.g
						sums[ci * 4 + 2] += c.b
						counts[ci] += 1
						var ai3 := (ci * 3 + tax) * 3
						sums_ax[ai3] += c.r
						sums_ax[ai3 + 1] += c.g
						sums_ax[ai3 + 2] += c.b
						counts_ax[ci * 3 + tax] += 1
						if emissive:
							glow[ci] = 1
						if accent_mat:
							glow[ci] |= 2
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
	# Colours (RGBA8; alpha codes: 255 plain, 60 glowing, 200 player colour,
	# 120 both). Solid cells without samples (inside) are never seen.
	var cols := PackedByteArray()
	cols.resize(n * 4)
	for ci in n:
		var cn := counts[ci]
		if cn > 0:
			var k := 1.0 / cn
			cols[ci * 4] = clampi(int(sums[ci * 4] * k * 255.0), 0, 255)
			cols[ci * 4 + 1] = clampi(int(sums[ci * 4 + 1] * k * 255.0), 0, 255)
			cols[ci * 4 + 2] = clampi(int(sums[ci * 4 + 2] * k * 255.0), 0, 255)
			cols[ci * 4 + 3] = [255, 0, 128, 128][glow[ci]]
		else:
			cols[ci * 4] = 128
			cols[ci * 4 + 1] = 128
			cols[ci * 4 + 2] = 128
			cols[ci * 4 + 3] = 255
	# Exposed faces: 6 colour-blind greedy passes. Each quad remembers the
	# solid cells behind it, for the colour atlas below.
	var quads: Array = []      # [corner, eu, ev, normal, axis, u_ax, v_ax, w, uu, vv, wlen, hlen]
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
						var face := 0
						if outside[ci] == 0:
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
						var c0 := Vector3.ZERO
						c0[axis] = float(w + (1 if dir > 0 else 0))
						c0[u_ax] = uu
						c0[v_ax] = vv
						var eu := Vector3.ZERO
						eu[u_ax] = wlen
						var ev := Vector3.ZERO
						ev[v_ax] = hlen
						quads.append([c0, eu, ev, nrm, axis, u_ax, v_ax, w, uu, vv, wlen, hlen, dir])
						uu += wlen
	# Colour atlas: every quad gets wlen x hlen texels (one per face cell),
	# packed on shelves, tallest first.
	var area := 0
	for q in quads:
		area += int(q[10]) * int(q[11])
	var aw := clampi(nearest_po2(int(ceil(sqrt(area * 1.25)))), 16, 2048)
	var order := range(quads.size())
	order.sort_custom(func(a, b): return quads[a][11] > quads[b][11])
	var place := []
	place.resize(quads.size())
	var sx2 := 0
	var sy2 := 0
	var shelf_h := 0
	for qi in order:
		var qw: int = quads[qi][10]
		var qh: int = quads[qi][11]
		if qw > aw:
			aw = nearest_po2(qw)
		if sx2 + qw > aw:
			sx2 = 0
			sy2 += shelf_h
			shelf_h = 0
		place[qi] = Vector2i(sx2, sy2)
		sx2 += qw
		shelf_h = maxi(shelf_h, qh)
	var ah := maxi(1, sy2 + shelf_h)
	var atlas := PackedByteArray()
	atlas.resize(aw * ah * 4)
	var mv := PackedVector3Array()
	var mn := PackedVector3Array()
	var mt := PackedFloat32Array()
	var muv := PackedVector2Array()
	var muv2 := PackedVector2Array()
	var mqs := PackedFloat32Array()     # the quad's size in cells (CUSTOM0)
	var mi := PackedInt32Array()
	for qi in quads.size():
		var q: Array = quads[qi]
		var c0: Vector3 = q[0]
		var eu: Vector3 = q[1]
		var ev: Vector3 = q[2]
		var nrm: Vector3 = q[3]
		var axis: int = q[4]
		var u_ax: int = q[5]
		var v_ax: int = q[6]
		var wlen: int = q[10]
		var hlen: int = q[11]
		var at: Vector2i = place[qi]
		for k2 in hlen:
			for k in wlen:
				var g := Vector3i.ZERO
				g[axis] = q[7]
				g[u_ax] = int(q[8]) + k
				g[v_ax] = int(q[9]) + k2
				var ci := g.x + dims.x * (g.y + dims.y * g.z)
				var ai := ((at.y + k2) * aw + at.x + k) * 4
				var src := ci
				var cax := counts_ax[ci * 3 + axis]
				if cax == 0:
					# No triangle faces this way in this cell (the face stops
					# short of the piece's edge): borrow the nearest cell on
					# the same face that has one, not the edge's own colour.
					for r in [1, 2, 3]:
						for off in [Vector2i(-r, 0), Vector2i(r, 0), Vector2i(0, -r), Vector2i(0, r)]:
							var g2 := g
							g2[u_ax] += (off as Vector2i).x
							g2[v_ax] += (off as Vector2i).y
							if g2[u_ax] < 0 or g2[v_ax] < 0 or g2[u_ax] >= dims[u_ax] or g2[v_ax] >= dims[v_ax]:
								continue
							var c2 := g2.x + dims.x * (g2.y + dims.y * g2.z)
							if counts_ax[c2 * 3 + axis] > 0:
								src = c2
								cax = counts_ax[c2 * 3 + axis]
								break
						if cax > 0:
							break
				if cax > 0:
					var s3 := (src * 3 + axis) * 3
					var kk := 255.0 / cax
					atlas[ai] = clampi(int(sums_ax[s3] * kk), 0, 255)
					atlas[ai + 1] = clampi(int(sums_ax[s3 + 1] * kk), 0, 255)
					atlas[ai + 2] = clampi(int(sums_ax[s3 + 2] * kk), 0, 255)
				else:
					atlas[ai] = cols[ci * 4]
					atlas[ai + 1] = cols[ci * 4 + 1]
					atlas[ai + 2] = cols[ci * 4 + 2]
				atlas[ai + 3] = cols[ci * 4 + 3]
		var tdir := eu.normalized()
		var bdir := ev.normalized()
		var tw := 1.0 if nrm.cross(tdir).dot(bdir) > 0.0 else -1.0
		var base_i := mv.size()
		var corners := [c0, c0 + eu, c0 + eu + ev, c0 + ev]
		var uvs := [Vector2(at.x, at.y), Vector2(at.x + wlen, at.y), Vector2(at.x + wlen, at.y + hlen), Vector2(at.x, at.y + hlen)]
		var uv2s := [Vector2.ZERO, Vector2(wlen, 0), Vector2(wlen, hlen), Vector2(0, hlen)]
		for vi in 4:
			mv.append(origin + (corners[vi] as Vector3) * vs3)
			mn.append(nrm)
			mt.append_array([tdir.x, tdir.y, tdir.z, tw])
			muv.append(uvs[vi])
			muv2.append(uv2s[vi])
			mqs.append(float(wlen))
			mqs.append(float(hlen))
		# Winding so the face points along nrm (Godot: clockwise front).
		if int(q[12]) > 0:
			mi.append_array([base_i, base_i + 2, base_i + 1, base_i, base_i + 3, base_i + 2])
		else:
			mi.append_array([base_i, base_i + 1, base_i + 2, base_i, base_i + 2, base_i + 3])
	return {"v": VERSION, "vs": vs, "verts": mv, "norms": mn, "tans": mt, "uvs": muv, "uv2s": muv2, "qs": mqs, "idx": mi,
		"atlas": atlas, "aw": aw, "ah": ah, "double": double}


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


# --------------------------------------------------------------------------
# Whole node trees: characters, guns, anything built from MeshInstances
# --------------------------------------------------------------------------

## Turns every opaque MeshInstance3D under `root` into voxels of `cell`
## (in root's units), in place: the mesh is replaced by its voxel mesh and
## the material by a voxel material, so parts keep animating as before.
## Materials whose colour is `accent` (the player colour) are drawn from
## the shader's accent uniform, so one voxelization (and one bake) serves
## every player colour. Returns the new materials (for the hit flash).
## Skips parts already done, see-through parts and skinned meshes.
static func voxelize_node(root: Node, cell: float, accent := Color(-1, -1, -1)) -> Array:
	var out: Array = []
	_walk(root, root, cell, accent, out)
	return out


static func _walk(n: Node, root: Node, cell: float, accent: Color, out: Array) -> void:
	if n is MeshInstance3D:
		_voxel_mi(n, root, cell, accent, out)
	for c in n.get_children():
		_walk(c, root, cell, accent, out)


static func _voxel_mi(mi: MeshInstance3D, root: Node, cell: float, accent: Color, out: Array) -> void:
	if mi.mesh == null or mi.has_meta("voxel") or mi.skin != null or not mi.visible and mi.mesh is QuadMesh:
		return
	var mesh: Mesh = mi.mesh
	# Skinned (animated) meshes cannot be split into rigid voxel parts.
	if mesh is ArrayMesh and ((mesh as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES) != 0:
		return
	var mats: Array = []
	var accents: Array = []
	var mkey := ""
	for s in mesh.get_surface_count():
		var m: Material = mi.material_override
		if m == null:
			m = mi.get_surface_override_material(s)
		if m == null:
			m = mesh.surface_get_material(s)
		if m is BaseMaterial3D:
			var bm: BaseMaterial3D = m
			if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				return
			var is_acc := accent.r >= 0.0 and bm.albedo_color.is_equal_approx(accent)
			if is_acc:
				accents.append(m)
			mkey += "%s%s%d%s;" % ["A" if is_acc else bm.albedo_color.to_html(), bm.albedo_texture.get_instance_id() if bm.albedo_texture != null else 0,
				int(bm.vertex_color_use_as_albedo), "e" if bm.emission_enabled else ""]
		elif m != null:
			return     # a custom shader (lens, effect): leave it smooth
		mats.append(m)
	# Size of a root unit in the part's own units.
	var xf := Transform3D()
	var node: Node = mi
	while node != null and node != root:
		if node is Node3D:
			xf = (node as Node3D).transform * xf
		node = node.get_parent()
	var s := (xf.basis.x.length() + xf.basis.y.length() + xf.basis.z.length()) / 3.0
	var want := cell / maxf(s, 0.0001)
	var b := roundi(log(want) / log(2.0) * 2.0)
	var vs := pow(2.0, b * 0.5)
	var shape := ""
	if mesh is ArrayMesh:
		shape = "%s|%s|%d|%d" % [mesh.get_class(), mesh.get_aabb(), mesh.get_surface_count(), (mesh as ArrayMesh).surface_get_array_len(0)]
	elif mesh is PrimitiveMesh:
		# Primitive shapes: their class and parameters say it all.
		var props := ""
		for pr in ["radius", "height", "size", "top_radius", "bottom_radius", "radial_segments", "rings", "inner_radius", "outer_radius", "mid_height"]:
			if pr in mesh:
				props += str(mesh.get(pr)) + ","
		shape = "%s|%s" % [mesh.get_class(), props]
	else:
		shape = "%s|%d" % [mesh.get_class(), mesh.get_instance_id()]
	var key := "n%d_%s@%d" % [hash(shape + mkey), mesh.get_class(), b]
	var d := _data(key, [[mesh, Transform3D(), mats, accents]], vs)
	if d.is_empty() or (d.verts as PackedVector3Array).is_empty():
		return
	var base := _material(key, d, false)
	var m2: ShaderMaterial = base.duplicate()
	m2.set_shader_parameter("sat", 1.0)
	m2.set_shader_parameter("val", 1.0)
	m2.set_shader_parameter("tint", Vector3.ONE)
	m2.set_shader_parameter("pastel", 0.0)
	# Characters, guns, vehicles: fine voxels, subtle depth and variation.
	m2.set_shader_parameter("RELIEF", 0.5 if Settings.v("voxel_relief") else 0.0)
	m2.set_shader_parameter("vox_strength", 0.45)
	if accent.r >= 0.0:
		m2.set_shader_parameter("accent", accent)
	mi.mesh = _mesh(key, d)
	mi.material_override = m2
	for si in mi.get_surface_override_material_count():
		mi.set_surface_override_material(si, null)
	mi.set_meta("voxel", true)
	out.append(m2)
