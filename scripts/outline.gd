extends MeshInstance3D
## Ink outlines for one camera (option "outlines"): a full-screen quad whose
## shader finds edges in the depth and normal buffers and darkens them, like
## the pen line in a cartoon. Silhouettes and creases separate shapes even
## where their colours and textures are similar, so simple geometry stops
## looking flat. Lines thin out and fade with distance so far scenery and
## grass do not turn into noise. game.gd parents one to every view camera
## on the same per-view layer as its sun rays.
## It multiplies the edges dark instead of reading the screen, so transparent
## effects drawn earlier (fire, smoke, sparks) survive it.

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mul, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;
uniform float strength = 0.6;
uniform vec3 ink : source_color = vec3(0.08, 0.05, 0.1);
void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}
float lin(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_tex, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}
vec3 nrm(vec2 uv) {
	return textureLod(normal_tex, uv, 0.0).xyz * 2.0 - 1.0;
}
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float zc = lin(uv, INV_PROJECTION_MATRIX);
	float edge = 0.0;
	if (zc < 120.0) {
		vec3 nc = nrm(uv);
		vec2 offs[4] = vec2[](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
		float de = 0.0;
		float ne = 0.0;
		for (int i = 0; i < 4; i++) {
			float zn = lin(uv + offs[i], INV_PROJECTION_MATRIX);
			de = max(de, (zn - zc) / zc);
			ne = max(ne, 1.0 - dot(nc, nrm(uv + offs[i])));
		}
		// Normal edges only for real creases (corners, roof ridges), not the
		// bumps a normal-mapped texture puts in every brick; and they fade
		// out sooner than silhouettes, where pixels get coarse.
		float crease = smoothstep(0.5, 0.85, ne) * 0.7 * (1.0 - smoothstep(14.0, 35.0, zc));
		edge = max(smoothstep(0.035, 0.09, de), crease);
		edge *= 1.0 - smoothstep(25.0, 70.0, zc);
	}
	// Multiply blend: darken the edges of whatever is already drawn, without
	// copying the screen (a copy would be taken before transparent effects
	// such as fire and smoke, and painting it back would erase them).
	ALBEDO = mix(vec3(1.0), ink * 2.0, edge * strength);
}
"""

static var _shader: Shader


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mesh = quad
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.render_priority = 99
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Settings.changed.connect(_on_settings)
	_on_settings()


func _on_settings() -> void:
	visible = Settings.v("outlines")
