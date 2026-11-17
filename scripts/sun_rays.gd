extends MeshInstance3D
## Sun rays ("god rays") for one camera: shafts of light that fan out from
## the sun when you look towards it, cut off by whatever stands in front of
## it (roofs, trees, walls).
##
## A full-screen quad parented to the camera. For every pixel the shader
## walks towards the sun's position on screen and counts how much open sky
## (depth buffer at the far plane) it crosses near the sun; that amount is
## added as warm light. game.gd calls aim() every frame with the camera and
## the direction to the sun. Indoors, or with the sun behind you, it fades
## to nothing. Option "rays" turns it off.

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform vec2 sun_uv = vec2(0.5, 0.2);
uniform float strength = 0.0;
uniform float aspect = 1.78;
uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.7);
void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 to_sun = sun_uv - uv;
	vec2 stp = to_sun / 26.0;
	vec2 p = uv;
	float acc = 0.0;
	float w = 1.0;
	for (int i = 0; i < 26; i++) {
		p += stp;
		vec2 q = clamp(p, vec2(0.001), vec2(0.999));
		// Reversed depth: 0 is the far plane, i.e. open sky.
		float sky = step(textureLod(depth_tex, q, 0.0).r, 0.000001);
		float near_sun = smoothstep(0.42, 0.0, length((q - sun_uv) * vec2(aspect, 1.0)));
		acc += sky * near_sun * w;
		w *= 0.965;
	}
	float reach = smoothstep(1.25, 0.05, length(to_sun * vec2(aspect, 1.0)));
	ALBEDO = tint * (acc / 26.0) * strength * reach;
}
"""

var _mat: ShaderMaterial
var _level := 0.0


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mesh = quad
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = 100
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	position = Vector3(0, 0, -1.0)


## `to_sun`: unit vector from the camera towards the sun. `power`: how
## strong the shafts are for this time of day (0 = none).
func aim(cam: Camera3D, to_sun: Vector3, color: Color, power: float, delta: float) -> void:
	var want := 0.0
	var size: Vector2 = cam.get_viewport().get_visible_rect().size
	if power > 0.0 and Settings.v("rays") and size.x > 8.0:
		var facing := (-cam.global_transform.basis.z).dot(to_sun)
		if facing > 0.15:
			var p := cam.unproject_position(cam.global_position + to_sun * 500.0)
			_mat.set_shader_parameter("sun_uv", p / size)
			_mat.set_shader_parameter("aspect", size.x / size.y)
			want = power * smoothstep(0.15, 0.6, facing)
	_level = move_toward(_level, want, delta * 2.5)
	visible = _level > 0.003
	if visible:
		_mat.set_shader_parameter("strength", _level)
		_mat.set_shader_parameter("tint", color)
