extends ColorRect
## Screen effects for one splitscreen view (option "screenfx"), as a 2D
## post-process over the finished 3D image (so fire, smoke and sparks are
## included):
##   speed   streaky radial blur towards the edges while dashing / sliding
##   zoom    a quick zoom blur from the centre when a blast goes off nearby
##   aberr   red / blue colour fringing at the edges when badly hurt
## Hidden while every amount is zero, so it costs nothing most of the time.
## game.gd calls set_fx() every frame.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float speed = 0.0;
uniform float zoom = 0.0;
uniform float aberr = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r = length(d);
	float rim = smoothstep(0.18, 0.7, r);
	float blur = speed * rim * 0.06 + zoom * 0.05 * (0.3 + r);
	vec3 col = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		col += textureLod(screen, uv - d * blur * float(i) / 5.0, 0.0).rgb;
	}
	col /= 6.0;
	if (aberr > 0.0) {
		float a = aberr * rim * 0.012;
		col.r = mix(col.r, textureLod(screen, uv + d * a, 0.0).r, 0.85);
		col.b = mix(col.b, textureLod(screen, uv - d * a, 0.0).b, 0.85);
	}
	COLOR = vec4(col, 1.0);
}
"""

static var _shader: Shader
var _fx := Vector3.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	material = m
	visible = false


func set_fx(speed: float, zoom: float, aberr: float) -> void:
	var f := Vector3(speed, zoom, aberr) if Settings.v("screenfx") else Vector3.ZERO
	if f.is_equal_approx(_fx):
		return
	_fx = f
	visible = f.length() > 0.001
	if visible:
		var m := material as ShaderMaterial
		m.set_shader_parameter("speed", f.x)
		m.set_shader_parameter("zoom", f.y)
		m.set_shader_parameter("aberr", f.z)
