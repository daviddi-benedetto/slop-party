extends RefCounted
## The sky used by every arena (map.gd) and by the lobby/results stage
## (stage.gd). One shader, driven by theme colours: a vertical gradient, a
## moon/sun disc with a wide halo, optional stars, an aurora band and soft
## painted clouds.
##
## The shader does not use TIME, so Godot renders the sky's lighting cubemap
## once instead of every frame.
##
## make(params) accepts any of: top, horizon, ground, sun (Colors),
## cloud_color (Color), clouds, stars, aurora (0..1 floats).

const SHADER := """
shader_type sky;

uniform vec3 top : source_color = vec3(0.02, 0.03, 0.08);
uniform vec3 horizon : source_color = vec3(0.1, 0.12, 0.25);
uniform vec3 ground : source_color = vec3(0.02, 0.02, 0.04);
uniform vec3 sun : source_color = vec3(0.8, 0.85, 1.0);
uniform vec3 cloud_color : source_color = vec3(0.2, 0.22, 0.35);
uniform float clouds = 0.5;
uniform float stars = 1.0;
uniform float aurora = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise(p) * a;
		p = p * 2.03 + vec2(11.3, 7.9);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon, top, pow(clamp(h, 0.0, 1.0), 0.5));
	col = mix(col, ground, smoothstep(0.0, -0.2, h));

	if (stars > 0.0 && h > 0.0) {
		vec2 suv = d.xz / (h + 0.4) * 60.0;
		vec2 cell = floor(suv);
		float r = hash(cell);
		vec2 off = vec2(hash(cell + 3.7), hash(cell + 9.1)) - 0.5;
		float dist = length(fract(suv) - 0.5 - off * 0.6);
		float star = smoothstep(0.09, 0.0, dist) * step(0.86, r);
		col += vec3(0.9, 0.95, 1.0) * star * stars * (0.5 + r) * smoothstep(0.0, 0.25, h);
	}

	if (aurora > 0.0 && h > 0.03) {
		vec2 auv = vec2(atan(d.x, d.z) * 2.2, h * 5.0);
		float band = fbm(vec2(auv.x * 1.6, auv.x * 0.3 + 4.0));
		float curtain = smoothstep(0.35, 0.75, fbm(vec2(auv.x * 5.0, auv.y * 0.6))) * band;
		float mask = smoothstep(0.03, 0.2, h) * smoothstep(0.75, 0.25, h);
		col += mix(vec3(0.1, 1.0, 0.6), vec3(0.6, 0.3, 1.0), clamp(h * 2.2, 0.0, 1.0)) * curtain * mask * aurora * 0.9;
	}

	float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += sun * (smoothstep(0.9993, 0.9997, sd) * 1.6 + pow(sd, 300.0) * 0.6 + pow(sd, 9.0) * 0.14);

	if (clouds > 0.0 && h > 0.015) {
		vec2 uv = d.xz / (h + 0.22) * 1.25;
		float c = fbm(uv + vec2(3.1, 1.7));
		float shape = smoothstep(0.52, 0.76, c);
		vec3 lit = cloud_color + sun * pow(sd, 5.0) * 0.25;
		col = mix(col, lit, shape * smoothstep(0.015, 0.28, h) * clouds);
	}
	COLOR = col;
}
"""

static var _shader: Shader


static func make(params := {}) -> Sky:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	for key in params:
		mat.set_shader_parameter(key, params[key])
	var sky := Sky.new()
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	return sky
