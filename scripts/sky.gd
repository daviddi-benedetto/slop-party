extends RefCounted
## The painted sky used by the arena (map.gd) and the lobby/results stage
## (stage.gd): a vertical colour gradient, a soft sun with a wide halo, and a
## band of fluffy stylised clouds from layered value noise.
##
## The shader does not use TIME, so Godot renders the sky's lighting cubemap
## once instead of every frame (the drifting 3D cloud meshes in map.gd provide
## the motion).

const SHADER := """
shader_type sky;

uniform vec3 top : source_color = vec3(0.1, 0.36, 0.92);
uniform vec3 horizon : source_color = vec3(0.56, 0.8, 1.0);
uniform vec3 ground : source_color = vec3(0.46, 0.76, 0.5);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.93, 0.75);

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
	vec3 col = mix(horizon, top, pow(clamp(h, 0.0, 1.0), 0.42));
	col = mix(col, ground, smoothstep(0.0, -0.22, h));

	float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += sun_tint * (pow(sd, 420.0) * 2.5 + pow(sd, 10.0) * 0.22);

	if (h > 0.015) {
		vec2 uv = d.xz / (h + 0.22) * 1.25;
		float c = fbm(uv + vec2(3.1, 1.7));
		float shape = smoothstep(0.5, 0.74, c);
		float shade = smoothstep(0.5, 0.95, fbm(uv * 1.9 + vec2(8.0, 2.0)));
		vec3 cloud = mix(vec3(1.0, 0.99, 0.97), vec3(0.8, 0.86, 0.97), shade * 0.55);
		cloud += sun_tint * pow(sd, 6.0) * 0.12;
		col = mix(col, cloud, shape * smoothstep(0.015, 0.28, h) * 0.9);
	}
	COLOR = col;
}
"""

static var _shader: Shader


static func make() -> Sky:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	var sky := Sky.new()
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	return sky
