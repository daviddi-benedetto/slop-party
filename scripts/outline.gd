extends MeshInstance3D
## Ink outlines for one camera (option "outlines"): a full-screen quad whose
## shader finds edges in the depth and normal buffers and darkens them, like
## the pen line in a cartoon. Silhouettes and creases separate shapes even
## where their colours and textures are similar, so simple geometry stops
## looking flat. Lines thin out and fade with distance so far scenery and
## grass do not turn into noise. game.gd parents one to every view camera
## on the same per-view layer as its sun rays.
##
## The same pass carries the screen effects (option "screenfx"; two passes
## that both read the screen would overwrite each other): a streaky radial
## blur at the edges while dashing / sliding (speed), a zoom blur when a blast
## goes off nearby (zoom) and colour fringing when badly hurt (aberr).
## game.gd sets them with set_fx(); the quad hides itself when there are
## neither outlines nor effects.

const SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float strength = 0.6;
uniform vec3 ink : source_color = vec3(0.08, 0.05, 0.1);
uniform float speed = 0.0;
uniform float zoom = 0.0;
uniform float aberr = 0.0;
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
	vec3 col = textureLod(screen_tex, uv, 0.0).rgb;
	vec2 dc = uv - 0.5;
	float rr = length(dc);
	float rim = smoothstep(0.18, 0.7, rr);
	float blur = speed * rim * 0.06 + zoom * 0.05 * (0.3 + rr);
	if (blur > 0.0005) {
		col = vec3(0.0);
		for (int i = 0; i < 6; i++) {
			col += textureLod(screen_tex, uv - dc * blur * float(i) / 5.0, 0.0).rgb;
		}
		col /= 6.0;
	}
	if (aberr > 0.0) {
		float a = aberr * rim * 0.012;
		col.r = mix(col.r, textureLod(screen_tex, uv + dc * a, 0.0).r, 0.85);
		col.b = mix(col.b, textureLod(screen_tex, uv - dc * a, 0.0).b, 0.85);
	}
	float edge = 0.0;
	if (zc < 120.0 && strength > 0.0) {
		vec3 nc = nrm(uv);
		vec2 offs[4] = vec2[](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
		float de = 0.0;
		float ne = 0.0;
		for (int i = 0; i < 4; i++) {
			float zn = lin(uv + offs[i], INV_PROJECTION_MATRIX);
			de = max(de, (zn - zc) / zc);
			ne = max(ne, 1.0 - dot(nc, nrm(uv + offs[i])));
		}
		edge = max(smoothstep(0.035, 0.09, de), smoothstep(0.25, 0.6, ne) * 0.7);
		edge *= 1.0 - smoothstep(25.0, 70.0, zc);
	}
	ALBEDO = mix(col, col * ink * 2.0, edge * strength);
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


var _fx := Vector3.ZERO


func _on_settings() -> void:
	(material_override as ShaderMaterial).set_shader_parameter("strength", 0.6 if Settings.v("outlines") else 0.0)
	_refresh()


## Screen effect amounts this frame (game.gd).
func set_fx(speed: float, zoom: float, aberr: float) -> void:
	var f := Vector3(speed, zoom, aberr) if Settings.v("screenfx") else Vector3.ZERO
	if f.is_equal_approx(_fx):
		return
	_fx = f
	var m := material_override as ShaderMaterial
	m.set_shader_parameter("speed", f.x)
	m.set_shader_parameter("zoom", f.y)
	m.set_shader_parameter("aberr", f.z)
	_refresh()


func _refresh() -> void:
	visible = Settings.v("outlines") or _fx.length() > 0.001
