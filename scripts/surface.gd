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

## Depth in metres of the deepest groove for each texture kind (map._tex).
const DEPTH := {"bricks": 0.07, "tiles": 0.04, "planks": 0.04, "plates": 0.035, "rock": 0.11, "corrugated": 0.05,
	"shingles": 0.07, "siding": 0.045, "marble": 0.02, "ice": 0.03, "lava": 0.08, "concrete": 0.02}

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
varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
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
	ALBEDO = tint * textureGrad(albedo_tex, uv, gx, gy).rgb * cavity;
	AO = cavity;
	AO_LIGHT_AFFECT = 0.4;
	vec3 tn = textureGrad(normal_tex, uv, gx, gy).xyz * 2.0 - 1.0;
	tn.xy *= normal_scale;
	vec3 wn = normalize(T * tn.x - B * tn.y + N * max(tn.z, 0.05));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	RIM = rim_amount;
	RIM_TINT = rim_tint_amount;
	EMISSION = textureGrad(emission_tex, uv, gx, gy).rgb * emission_energy;
}
"""

static var _shader: Shader


static func make(tint: Color, albedo: Texture2D, normal: Texture2D, height: Texture2D, emission: Texture2D,
		uv_scale: float, depth: float, rough: float, metal: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	var m := ShaderMaterial.new()
	m.shader = _shader
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
	return m
