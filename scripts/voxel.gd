extends RefCounted
## The voxel world style (option "voxel"): every surface of the level looks
## built from small cubes, without adding a single triangle.
##
## Everything happens in the fragment shader, in world space:
##   - the world is cut into cubes of SIZE metres; the cube under each pixel
##     is found from its world position, nudged into the surface;
##   - each cube gets ONE colour: the texture is sampled at the cube's
##     centre, at the mip level that matches the cube size (a model's UVs are
##     carried to the centre with the screen-space UV / position Jacobian);
##   - each cube is shaded a little lighter or darker (a hash of its index),
##     with bevelled edges (tilted normals) and darker seams, so cubes read
##     as separate blocks in any light;
##   - on level floors and walls (surface.gd) the cubes also stand at
##     different heights: parallax ray-marching through a stepped height
##     field, with lit tops and shaded sides.
## Far away, where a cube would cover only a few pixels, the effect fades to
## plain shading so it never shimmers.
##
## Used by map.gd (`_mat`), surface.gd, models.gd (`toy`, `sway`). Characters,
## weapons and pets stay smooth: only the environment is voxel.

## Cube edge in metres.
const SIZE := 0.1

## Set by map.gd / stage.gd from the option when a level is built.
static var on := false
## The theme in play (looks.gd), for the voxel props' colour grade.
static var look := {}

## Shared GLSL: hashing, the dominant-axis frame, fade and bevel.
const FN := """
uniform float vox_size = 0.1;
float vox_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}
// Dominant-axis frame of a world normal (T, B span the face, N faces out).
void vox_frame(vec3 n, out vec3 T, out vec3 B, out vec3 N) {
	vec3 an = abs(n);
	if (an.x >= an.y && an.x >= an.z) {
		T = vec3(0.0, 0.0, sign(n.x)); B = vec3(0.0, -1.0, 0.0); N = vec3(sign(n.x), 0.0, 0.0);
	} else if (an.y >= an.z) {
		T = vec3(1.0, 0.0, 0.0); B = vec3(0.0, 0.0, sign(n.y)); N = vec3(0.0, sign(n.y), 0.0);
	} else {
		T = vec3(-sign(n.z), 0.0, 0.0); B = vec3(0.0, -1.0, 0.0); N = vec3(0.0, 0.0, sign(n.z));
	}
}
// 0..1: how much voxel detail this pixel can show (fades out below a few
// pixels per cube, before it would alias). f = face coordinates in cubes.
float vox_amount(vec2 f) {
	// Pixels per cube from its average footprint (not the most squashed
	// side), so floors seen at a low angle keep their detail.
	vec2 fw = fwidth(f);
	float ppc = 1.0 / max(sqrt(fw.x * fw.y), 1e-4);
	return smoothstep(0.9, 2.6, ppc);
}
// Every face of every cube stands at its own random depth. The relief
// (lit lip where a face steps DOWN to its neighbour, shadowed corner where
// it steps UP, a small random tilt, lighter when higher) is baked into
// `vox_detail` (Voxel.detail(): 64 x 64 cubes, 8 px each, with mipmaps), so
// far away the GPU blends it smoothly: no shimmer, nothing switches off.
uniform sampler2D vox_detail : filter_linear_mipmap_anisotropic, repeat_enable;
// Whole-cube offset into the tile per face direction, so walls and floors
// do not share one pattern. (Not per layer: a face lying exactly on a cube
// boundary got a different layer pixel by pixel, which sprinkled the
// surface with flickering dots.)
vec2 vox_off(vec3 N, float layer) {
	return floor(fract(vec2(dot(N, vec3(0.37, 0.11, 0.73)), dot(N, vec3(0.19, 0.53, 0.29)))) * 64.0);
}
// Height of the cube face at cube `c2` (face coordinates), 0..1.
float vox_h2(vec2 c2, vec3 N, float layer) {
	return textureLod(vox_detail, (c2 + 0.5 + vox_off(N, layer)) / 64.0, 3.0).a;
}
// f = position on the face in cube units (not wrapped), layer = which plane.
void vox_depth(vec2 f, vec3 T, vec3 B, vec3 N, float layer, inout vec3 nrm, out float shade) {
	vec4 d = texture(vox_detail, (f + vox_off(N, layer)) / 64.0);
	vec2 tilt = (d.rg * 2.0 - 1.0) * 1.9;
	nrm = normalize(nrm + T * tilt.x + B * tilt.y);
	shade = d.b * 1.25;
}
"""

## Imported and plain level materials in the voxel style. Two variants (back
## faces culled or not), built on first use.
const CODE := """
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx%s;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_tex = false;
uniform bool use_vcol = false;
uniform bool triplanar = false;
uniform float tri_scale = 0.25;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float rough = 0.8;
uniform float metal = 0.0;
uniform vec3 emission = vec3(0.0);
uniform sampler2D emission_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform bool use_emission_tex = false;
uniform float emission_energy = 1.0;
uniform float rim_amount = 0.22;
uniform float sway = 0.0;
varying vec3 w_pos;
varying vec3 w_nrm;
%s
void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	if (sway > 0.0) {
		// Foliage in the wind (as Models.SWAY_CODE); the cubes stay put on
		// the rest position so they do not crawl over the leaves.
		float h = clamp(w_pos.y - 0.4, 0.0, 7.0);
		float s = sin(TIME * 1.25 + w_pos.x * 0.31 + w_pos.z * 0.23) + 0.35 * sin(TIME * 3.1 + w_pos.x * 1.7 + w_pos.z * 1.3);
		vec3 off = vec3(s, 0.0, s * 0.55) * sway * h * h * 0.0035;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
	}
}
void fragment() {
	vec3 wn = normalize(w_nrm);
	if (!FRONT_FACING) { wn = -wn; }
	vec3 T; vec3 B; vec3 N;
	vox_frame(wn, T, B, N);
	vec3 q = w_pos / vox_size;
	vec3 cell = floor(q - N * 0.5);
	vec3 cc = (cell + 0.5) * vox_size;
	vec2 f = vec2(dot(q, T), dot(q, B));
	vec3 c = albedo.rgb;
	if (use_tex) {
		if (triplanar) {
			// One colour per cube (its centre), at the mip of the cube or of the
			// pixel, whichever is bigger: smooth with distance, never a switch.
			vec2 uvp = vec2(dot(w_pos, T), dot(w_pos, B)) * tri_scale;
			float pix = max(length(dFdx(uvp)), length(dFdy(uvp)));
			float s = max(vox_size * tri_scale, pix);
			uvp = vec2(dot(cc, T), dot(cc, B)) * tri_scale;
			c *= textureGrad(tex, uvp, vec2(s, 0.0), vec2(0.0, s)).rgb;
		} else {
			vec2 uv0 = UV * uv_scale.xy + uv_offset.xy;
			vec2 u1 = dFdx(uv0);
			vec2 u2 = dFdy(uv0);
			vec2 uvc = uv0;
			vec2 g1 = u1;
			vec2 g2 = u2;
			vec3 dpx = dFdx(w_pos);
			vec3 dpy = dFdy(w_pos);
			vec2 a1 = vec2(dot(dpx, T), dot(dpx, B));
			vec2 a2 = vec2(dot(dpy, T), dot(dpy, B));
			float det = a1.x * a2.y - a2.x * a1.y;
			if (abs(det) > 1e-14) {
				// UV per metre on the face, from the screen-space derivatives;
				// then the UV at the cube's centre and a cube-sized footprint.
				mat2 ainv = mat2(vec2(a2.y, -a1.y), vec2(-a2.x, a1.x)) / det;
				mat2 J = mat2(u1, u2) * ainv;
				vec3 d = cc - w_pos;
				uvc = uv0 + J * vec2(dot(d, T), dot(d, B));
				vec2 j1 = J * vec2(vox_size, 0.0);
				vec2 j2 = J * vec2(0.0, vox_size);
				g1 = length(j1) > length(u1) ? j1 : u1;
				g2 = length(j2) > length(u2) ? j2 : u2;
			}
			c *= textureGrad(tex, uvc, g1, g2).rgb;
		}
	}
	if (use_vcol) {
		c *= COLOR.rgb;
	}
	float sh;
	vec3 vn = wn;
	vox_depth(f, T, B, N, dot(cell, N), vn, sh);
	c *= sh;
	ALBEDO = c;
	NORMAL = normalize((VIEW_MATRIX * vec4(vn, 0.0)).xyz);
	ROUGHNESS = rough;
	METALLIC = metal;
	RIM = rim_amount;
	RIM_TINT = 0.6;
	vec3 e = emission;
	if (use_emission_tex) {
		e = texture(emission_tex, UV * uv_scale.xy + uv_offset.xy).rgb * emission_energy;
	}
	EMISSION = e * sh;
}
"""

static var _shaders := {}
static var _cache := {}
static var _detail: ImageTexture
const DETAIL_FILE := "res://assets/voxel/detail.vox"
## tools (--voxel-bake): write the detail tile into the game.
static var save_detail := false


## The relief tile (see FN): 64 x 64 cubes of 8 x 8 px. RG = normal tilt,
## B = shade, A = the cube's height (one value per cube, for parallax).
static func detail() -> ImageTexture:
	if _detail != null:
		return _detail
	const N := 64
	const P := 8
	# Baked with the voxel models (main.gd --voxel-bake): making it here
	# takes about a second.
	if FileAccess.file_exists(DETAIL_FILE):
		var f := FileAccess.open_compressed(DETAIL_FILE, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		var bytes = f.get_var() if f != null else null
		if bytes is PackedByteArray and (bytes as PackedByteArray).size() == N * P * N * P * 4:
			var im := Image.create_from_data(N * P, N * P, false, Image.FORMAT_RGBA8, bytes)
			im.generate_mipmaps()
			_detail = ImageTexture.create_from_image(im)
			return _detail
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var h := PackedFloat32Array()
	h.resize(N * N)
	for i in N * N:
		h[i] = rng.randf()
	var rnd := PackedVector2Array()
	rnd.resize(N * N)
	for i in N * N:
		rnd[i] = Vector2(rng.randf() - 0.5, rng.randf() - 0.5)
	var img := Image.create_empty(N * P, N * P, false, Image.FORMAT_RGBA8)
	var w := 0.26
	for cy in N:
		for cx in N:
			var h0 := h[cy * N + cx]
			var dl := h0 - h[cy * N + posmod(cx - 1, N)]
			var dr := h0 - h[cy * N + posmod(cx + 1, N)]
			var dd := h0 - h[posmod(cy - 1, N) * N + cx]
			var du := h0 - h[posmod(cy + 1, N) * N + cx]
			var rv := rnd[cy * N + cx]
			for py in P:
				var fy := (py + 0.5) / P
				var ed := 1.0 - smoothstep(0.0, w, fy)
				var eu := 1.0 - smoothstep(0.0, w, 1.0 - fy)
				for px in P:
					var fx := (px + 0.5) / P
					var el := 1.0 - smoothstep(0.0, w, fx)
					var er := 1.0 - smoothstep(0.0, w, 1.0 - fx)
					var tx := -maxf(dl, 0.0) * el + maxf(dr, 0.0) * er
					var ty := -maxf(dd, 0.0) * ed + maxf(du, 0.0) * eu
					var ao := maxf(-dl, 0.0) * el + maxf(-dr, 0.0) * er + maxf(-dd, 0.0) * ed + maxf(-du, 0.0) * eu
					tx = tx * 0.8 + rv.x * 0.16
					ty = ty * 0.8 + rv.y * 0.16
					var shade := (0.8 + 0.32 * h0) * (1.0 - 0.5 * minf(ao, 1.0)) / 1.25
					img.set_pixel(cx * P + px, cy * P + py, Color(clampf(tx * 0.5 + 0.5, 0.0, 1.0), clampf(ty * 0.5 + 0.5, 0.0, 1.0), clampf(shade, 0.0, 1.0), h0))
	if save_detail:
		var fw := FileAccess.open_compressed(DETAIL_FILE, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		if fw != null:
			fw.store_var(img.get_data())
	img.generate_mipmaps()
	_detail = ImageTexture.create_from_image(img)
	return _detail


static func _shader(double_sided: bool) -> Shader:
	if not _shaders.has(double_sided):
		var s := Shader.new()
		s.code = CODE % [", cull_disabled" if double_sided else "", FN]
		_shaders[double_sided] = s
	return _shaders[double_sided]


## A plain level material (map._mat without parallax): colour, optional
## world-triplanar texture and emission texture.
static func plain(color: Color, tex: Texture2D, tri_scale: float, rough: float, metal: float,
		emission_tex: Texture2D = null, emission_energy := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(false)
	m.set_shader_parameter("vox_size", SIZE)
	m.set_shader_parameter("vox_detail", detail())
	m.set_shader_parameter("albedo", color)
	if tex != null:
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("use_tex", true)
		m.set_shader_parameter("triplanar", true)
		m.set_shader_parameter("tri_scale", tri_scale)
	if emission_tex != null:
		m.set_shader_parameter("emission_tex", emission_tex)
		m.set_shader_parameter("use_emission_tex", true)
		m.set_shader_parameter("emission_energy", emission_energy)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	return m


## An imported model's (already toy()-styled) material in the voxel style;
## see-through materials are returned unchanged. Cached per material.
static func from_standard(src: BaseMaterial3D, sway := 0.0) -> Material:
	if src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return src
	var key := "%d|%s" % [src.get_instance_id(), sway]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader(src.cull_mode == BaseMaterial3D.CULL_DISABLED or sway > 0.0)
	m.set_shader_parameter("vox_size", SIZE)
	m.set_shader_parameter("vox_detail", detail())
	m.set_shader_parameter("albedo", src.albedo_color)
	if src.albedo_texture != null:
		m.set_shader_parameter("tex", src.albedo_texture)
		m.set_shader_parameter("use_tex", true)
		if src.uv1_triplanar:
			m.set_shader_parameter("triplanar", true)
			m.set_shader_parameter("tri_scale", src.uv1_scale.x)
	m.set_shader_parameter("use_vcol", src.vertex_color_use_as_albedo)
	m.set_shader_parameter("uv_scale", src.uv1_scale)
	m.set_shader_parameter("uv_offset", src.uv1_offset)
	m.set_shader_parameter("rough", src.roughness)
	m.set_shader_parameter("metal", src.metallic)
	m.set_shader_parameter("rim_amount", src.rim if src.rim_enabled else 0.0)
	if src.emission_enabled:
		m.set_shader_parameter("emission", src.emission * src.emission_energy_multiplier)
		if src.emission_texture != null:
			m.set_shader_parameter("emission_tex", src.emission_texture)
			m.set_shader_parameter("use_emission_tex", true)
			m.set_shader_parameter("emission_energy", src.emission_energy_multiplier)
	m.set_shader_parameter("sway", sway)
	_cache[key] = m
	return m
