extends RefCounted
## Surfaces with real-looking depth (map.gd `_mat`, option "parallax").
##
## Godot's built-in height mapping does not work with triplanar mapping, and
## every level surface is mapped triplanar in world space. So this is our own
## shader: world-space triplanar on the dominant axis (the level is built
## from axis-aligned boxes, so one projection per pixel is enough), plus
## parallax occlusion mapping from the procedural height map (map._tex): each
## pixel steps into the height field along the view ray, so mortar lines,
## tile grooves, plank seams, cobble cracks and corrugation ridges sink in
## and stand out, and shift as you move past them. The surface stays flat
## for physics and triangle count. The effect fades out with distance
## (FADE_FAR), where it would only cost time.
##
## It also does what StandardMaterial3D did for these surfaces: tint x
## albedo, normal map, wrapped diffuse, rim, roughness, metallic, emission.

const FADE_FAR := 30.0
const Voxel = preload("res://scripts/voxel.gd")

## Depth in metres of the deepest groove for each texture kind (map._tex).
const DEPTH := {"bricks": 0.07, "tiles": 0.04, "planks": 0.04, "plates": 0.035, "rock": 0.11, "corrugated": 0.05,
	"shingles": 0.07, "siding": 0.045, "marble": 0.02, "ice": 0.03, "lava": 0.08, "concrete": 0.02, "asphalt": 0.006,
	# Ground: with these the lawn, turf and soil get real relief too (in the
	# voxel style the ground steps in and out in blocks instead of looking
	# like a flat striped floor).
	"lawn": 0.03, "turf": 0.02, "soil": 0.03}

const CODE := """
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
uniform vec3 tint : source_color = vec3(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D height_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D emission_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float emission_energy = 0.0;
uniform float uv_scale = 0.25;
uniform float depth = 0.03;
uniform float normal_scale = 0.5;
uniform float roughness = 0.7;
uniform float metallic = 0.0;
uniform float rim_amount = 0.22;
uniform float rim_tint_amount = 0.6;
uniform float fade_far = 30.0;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float weather = 1.0;      // grime at the foot of walls, bleached tops, patchy colour
uniform float wet = 0.0;          // wet themes: damp sheen and puddles on the ground
varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

float amt_px(vec2 f) {
	vec2 fw = fwidth(f);
	return 1.0 / max(sqrt(fw.x * fw.y), 1e-4);
}
void fragment() {
	vec3 n = normalize(w_nrm);
	vec3 an = abs(n);
	vec2 uv;
	vec3 T;
	vec3 B;
	vec3 N;
	if (an.x >= an.y && an.x >= an.z) {
		uv = vec2(w_pos.z * sign(n.x), -w_pos.y);
		T = vec3(0.0, 0.0, sign(n.x));
		B = vec3(0.0, -1.0, 0.0);
		N = vec3(sign(n.x), 0.0, 0.0);
	} else if (an.y >= an.z) {
		uv = vec2(w_pos.x, w_pos.z * sign(n.y));
		T = vec3(1.0, 0.0, 0.0);
		B = vec3(0.0, 0.0, sign(n.y));
		N = vec3(0.0, sign(n.y), 0.0);
	} else {
		uv = vec2(-w_pos.x * sign(n.z), -w_pos.y);
		T = vec3(-sign(n.z), 0.0, 0.0);
		B = vec3(0.0, -1.0, 0.0);
		N = vec3(0.0, 0.0, sign(n.z));
	}
	uv *= uv_scale;
	vec2 gx = dFdx(uv);
	vec2 gy = dFdy(uv);
	vec3 to_cam = CAMERA_POSITION_WORLD - w_pos;
	float dist = length(to_cam);
	vec3 v = to_cam / max(dist, 0.0001);
	vec3 vt = vec3(dot(v, T), dot(v, B), dot(v, N));
	float k = depth * uv_scale * (1.0 - smoothstep(fade_far * 0.6, fade_far, dist));
	if (k > 0.00005 && vt.z > 0.08) {
		// Parallax occlusion: march into the height field (1 = top, 0 = deepest).
		float steps = mix(16.0, 6.0, clamp(vt.z, 0.0, 1.0));
		float layer = 1.0 / steps;
		vec2 duv = vt.xy / vt.z * k * layer;
		float cur = 0.0;
		vec2 p = uv;
		float hd = 1.0 - textureGrad(height_tex, p, gx, gy).r;
		for (int i = 0; i < 16; i++) {
			if (float(i) >= steps || cur >= hd) {
				break;
			}
			p -= duv;
			hd = 1.0 - textureGrad(height_tex, p, gx, gy).r;
			cur += layer;
		}
		vec2 prev = p + duv;
		float after = hd - cur;
		float before = (1.0 - textureGrad(height_tex, prev, gx, gy).r) - cur + layer;
		float w = after / min(after - before, -0.0001);
		uv = mix(p, prev, clamp(w, 0.0, 1.0));
	}
	// Cavity shading: grooves and seams sit in their own shadow.
	float h = textureGrad(height_tex, uv, gx, gy).r;
	float cavity = mix(0.55, 1.0, smoothstep(0.05, 0.55, h));
	vec3 col = tint * textureGrad(albedo_tex, uv, gx, gy).rgb * cavity;
	// Weathering, in world units so it ignores texture tiling.
	vec2 wuv = uv / uv_scale;
	float mac = texture(macro_tex, wuv * 0.035).r;
	float mac2 = texture(macro_tex, wuv * 0.11 + vec2(0.37, 0.71)).r;
	col *= mix(1.0, mix(0.84, 1.1, mac) * mix(0.95, 1.04, mac2), weather);
	float rough = roughness;
	if (abs(N.y) < 0.5) {
		// Walls: damp, dirty feet and sun-bleached tops.
		float grime = (1.0 - smoothstep(0.0, 1.3, w_pos.y)) * (0.55 + 0.45 * mac2);
		col = mix(col, col * vec3(0.6, 0.56, 0.5), grime * 0.65 * weather);
		col += vec3(0.05, 0.045, 0.035) * smoothstep(2.5, 7.0, w_pos.y) * weather;
	} else if (N.y > 0.5 && wet > 0.0) {
		// Wet ground: everything glistens, low spots hold puddles.
		float puddle = smoothstep(0.56, 0.64, mac * 0.7 + mac2 * 0.3) * smoothstep(0.35, 0.0, h - 0.4);
		col *= 1.0 - 0.3 * wet - 0.25 * puddle * wet;
		rough = mix(rough, 0.32, wet);
		rough = mix(rough, 0.03, puddle * wet);
	}
	ALBEDO = col;
	AO = cavity;
	AO_LIGHT_AFFECT = 0.4;
	vec3 tn = textureGrad(normal_tex, uv, gx, gy).xyz * 2.0 - 1.0;
	tn.xy *= normal_scale;
	vec3 wn = normalize(T * tn.x - B * tn.y + N * max(tn.z, 0.05));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = rough;
	METALLIC = metallic;
	RIM = rim_amount;
	RIM_TINT = rim_tint_amount;
	EMISSION = textureGrad(emission_tex, uv, gx, gy).rgb * emission_energy;
}
"""

## The voxel style (Voxel.on): the same inputs, but the surface is a field of
## cubes (Voxel.SIZE) standing at different heights: the height map sampled
## at each cube's centre plus a random offset. The parallax march stops at
## the first cube whose top or side the view ray meets; tops are bevelled,
## sides shaded by their own normal. One colour per cube.
const VOX_CODE := """
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
uniform vec3 tint : source_color = vec3(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D height_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D emission_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float emission_energy = 0.0;
uniform float uv_scale = 0.25;
uniform float depth = 0.03;
uniform float normal_scale = 0.5;
uniform float roughness = 0.7;
uniform float metallic = 0.0;
uniform float rim_amount = 0.22;
uniform float rim_tint_amount = 0.6;
uniform float fade_far = 30.0;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float weather = 1.0;
uniform float wet = 0.0;
uniform float relief_depth = 1.5; // how far the voxels step in and out, in voxel sizes
varying vec3 w_pos;
varying vec3 w_nrm;
%s
void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}
float amt_px(vec2 f) {
	vec2 fw = fwidth(f);
	return 1.0 / max(sqrt(fw.x * fw.y), 1e-4);
}
// How far a cube is sunk: 0 = flush with the surface, 1 = deepest.
float cell_h(vec2 c, float layer, vec3 cur_T, vec3 cur_B, vec3 cur_N) {
	vec2 uvc = (c + 0.5) * vox_size * uv_scale;
	float g = vox_size * uv_scale;
	float ht = textureGrad(height_tex, uvc, vec2(g, 0.0), vec2(0.0, g)).r;
	// Every cube face at its own random depth (vox_h, the same numbers the
	// fake relief shading uses), grooves in the texture (mortar, seams)
	// deeper, and now and then a voxel simply missing.
	vec3 c3 = cur_T * c.x + cur_B * c.y + cur_N * layer;
	// Three clear depths (flush, half, full voxel) instead of tiny random
	// differences: big steps read as blocks; tiny ones only made thin
	// shimmering edges.
	float s = floor((1.0 - vox_h2(c, cur_N, layer)) * 2.99) * 0.5 + ((1.0 - ht) > 0.45 ? 0.5 : 0.0);
	return vox_hash(vec3(c, dot(cur_N, vec3(1.0, 2.0, 3.0)))) > 0.988 ? 1.0 : min(s, 0.9);
}
void fragment() {
	vec3 n = normalize(w_nrm);
	vec3 T; vec3 B; vec3 N;
	vox_frame(n, T, B, N);
	float layer = floor(dot(w_pos, N) / vox_size + 0.5);
	vec2 f = vec2(dot(w_pos, T), dot(w_pos, B)) / vox_size;
	vec3 to_cam = CAMERA_POSITION_WORLD - w_pos;
	float dist = length(to_cam);
	vec3 v = to_cam / max(dist, 0.0001);
	vec3 vt = vec3(dot(v, T), dot(v, B), dot(v, N));
	// Real parallax relief within ~28 m; beyond, the fake relief shading
	// (vox_depth) carries the same heights, so there is no visible edge.
	// Real parallax wherever a cube is still a few pixels wide (no
	// distance cut-off: it fades with the cube's size on screen).
	float k = relief_depth * smoothstep(3.5, 9.0, amt_px(f));
	vec2 p = f;
	vec2 cellp = floor(p);
	float hd = cell_h(cellp, layer, T, B, N);
	float cur = 0.0;
	bool side = false;
	vec2 side_n = vec2(0.0);
	if (k > 0.002 && vt.z > 0.06) {
		// March down into the cube field (in cube units).
		const float STEPS = 24.0;
		vec2 duv = vt.xy / vt.z * k / STEPS;
		float ls = 1.0 / STEPS;
		for (int i = 0; i < 24; i++) {
			if (cur * k >= hd * k) {
				break;
			}
			vec2 np = p - duv;
			cur += ls;
			vec2 nc = floor(np);
			if (nc != cellp) {
				float nh = cell_h(nc, layer, T, B, N);
				if (cur >= nh) {
					// Entered a taller cube from the side.
					side = true;
					side_n = cellp - nc;
					if (abs(side_n.x) > 0.5 && abs(side_n.y) > 0.5) {
						side_n.y = 0.0;
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
	// One colour per cube (its centre), at the mip of the cube or of the
	// pixel, whichever is bigger: smooth with distance, never a switch.
	vec2 uvf = f * vox_size * uv_scale;
	float cs = vox_size * uv_scale;
	vec2 g1 = dFdx(uvf);
	vec2 g2 = dFdy(uvf);
	g1 *= max(1.0, cs / max(length(g1), 1e-6));
	g2 *= max(1.0, cs / max(length(g2), 1e-6));
	vec2 uv = (cellp + 0.5) * vox_size * uv_scale;
	vec3 col = tint * textureGrad(albedo_tex, uv, g1, g2).rgb;
	vec3 c3 = T * cellp.x + B * cellp.y + N * layer;
	vec3 wn = N;
	float sh = 1.0;
	if (side) {
		wn = normalize(T * side_n.x + B * side_n.y + N * 0.7);
		col *= mix(1.0, 0.62, vox_strength);
	} else {
		vox_depth(p, T, B, N, layer, wn, sh);
	}
	// Sunk cubes sit in their own shadow.
	float cavity = mix(1.0, mix(1.0, 0.62, vox_strength), hd);
	col *= sh * cavity;
	vec2 wuv = f * vox_size;
	float mac = texture(macro_tex, wuv * 0.035).r;
	float mac2 = texture(macro_tex, wuv * 0.11 + vec2(0.37, 0.71)).r;
	col *= mix(1.0, mix(0.84, 1.1, mac) * mix(0.95, 1.04, mac2), weather);
	float rough = roughness;
	if (abs(N.y) < 0.5) {
		float grime = (1.0 - smoothstep(0.0, 1.3, w_pos.y)) * (0.55 + 0.45 * mac2);
		col = mix(col, col * vec3(0.6, 0.56, 0.5), grime * 0.65 * weather);
		col += vec3(0.05, 0.045, 0.035) * smoothstep(2.5, 7.0, w_pos.y) * weather;
	} else if (N.y > 0.5 && wet > 0.0) {
		col *= 1.0 - 0.3 * wet;
		rough = mix(rough, 0.32, wet);
	}
	ALBEDO = col;
	AO = cavity;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = rough;
	METALLIC = metallic;
	// (No rim light, no specular: they drew bright borders on voxel edges.)
	EMISSION = textureGrad(emission_tex, uv, g1, g2).rgb * emission_energy;
}
"""

static var _vox_shader: Shader

static var _shader: Shader
static var _macro: NoiseTexture2D


## Low-frequency seamless noise for weathering (shared).
static func macro() -> NoiseTexture2D:
	if _macro == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.012
		n.fractal_octaves = 3
		_macro = NoiseTexture2D.new()
		_macro.noise = n
		_macro.width = 256
		_macro.height = 256
		_macro.seamless = true
		_macro.generate_mipmaps = true
	return _macro


## Voxel style per texture kind: [how far voxels step in and out (voxel
## sizes), how strong the per-voxel light / dark variation is]. Ground and
## rock are deep and rough; plaster, drywall-like siding, tiles, marble and
## metal stay nearly flat and calm.
const VOX_STYLE := {
	"lawn": [1.6, 1.0], "soil": [1.6, 1.0], "turf": [1.2, 0.9], "rock": [1.6, 1.0], "snow": [1.0, 0.7],
	"lava": [1.3, 0.9], "bricks": [0.9, 0.8], "shingles": [0.9, 0.8], "planks": [0.5, 0.6], "asphalt": [0.5, 0.6],
	"corrugated": [0.4, 0.5], "siding": [0.3, 0.45], "concrete": [0.3, 0.45], "tiles": [0.25, 0.4],
	"plates": [0.2, 0.35], "ice": [0.25, 0.4], "marble": [0.12, 0.3], "plaster": [0.15, 0.35],
}


static func make(tint: Color, albedo: Texture2D, normal: Texture2D, height: Texture2D, emission: Texture2D,
		uv_scale: float, depth: float, rough: float, metal: float, kind := "") -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	var m := ShaderMaterial.new()
	m.shader = _shader
	if Voxel.on:
		if _vox_shader == null:
			_vox_shader = Shader.new()
			_vox_shader.code = VOX_CODE % Voxel.FN
		m.shader = _vox_shader
		m.set_shader_parameter("vox_size", Voxel.SIZE)
		m.set_shader_parameter("vox_detail", Voxel.detail())
		var vs: Array = VOX_STYLE.get(kind, [clampf(depth * 12.0, 0.2, 1.2), 0.6])
		m.set_shader_parameter("relief_depth", vs[0])
		m.set_shader_parameter("vox_strength", vs[1])
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("albedo_tex", albedo)
	m.set_shader_parameter("normal_tex", normal)
	m.set_shader_parameter("height_tex", height)
	if emission != null:
		m.set_shader_parameter("emission_tex", emission)
		m.set_shader_parameter("emission_energy", 2.4)
	m.set_shader_parameter("uv_scale", uv_scale)
	m.set_shader_parameter("depth", depth)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("fade_far", FADE_FAR)
	m.set_shader_parameter("macro_tex", macro())
	return m
