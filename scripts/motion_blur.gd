extends ColorRect
## Lightweight per-split-view camera-motion blur. The screen is sampled along
## the previous frame's camera rotation/translation; strength is user-adjustable.

const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec2 blur_vector = vec2(0.0);
uniform float strength = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 color = textureLod(screen_texture, uv, 0.0);
	for (int i = 1; i <= 5; i++) {
		float t = float(i) / 5.0;
		color += textureLod(screen_texture, clamp(uv + blur_vector * strength * t, vec2(0.001), vec2(0.999)), 0.0);
	}
	COLOR = color / 6.0;
}
"""

var _material: ShaderMaterial
var _last_position := Vector3.ZERO
var _last_rotation := Vector3.ZERO
var _initialized := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material.shader = shader
	material = _material
	color = Color.WHITE
	visible = false


func track(camera: Camera3D) -> void:
	var amount := float(Settings.v("motion_blur"))
	visible = amount > 0.0
	var pos := camera.global_position
	var rot := camera.global_rotation
	if not _initialized:
		_last_position = pos
		_last_rotation = rot
		_initialized = true
		_material.set_shader_parameter("blur_vector", Vector2.ZERO)
		_material.set_shader_parameter("strength", amount / 10.0)
		return
	var dyaw := wrapf(rot.y - _last_rotation.y, -PI, PI)
	var dpitch := wrapf(rot.x - _last_rotation.x, -PI, PI)
	var local_delta := camera.global_transform.basis.inverse() * (pos - _last_position)
	var vector := Vector2(-dyaw * 0.42 - local_delta.x * 0.0025, dpitch * 0.42 + local_delta.y * 0.0025)
	if vector.length() > 0.024:
		vector = vector.normalized() * 0.024
	_material.set_shader_parameter("blur_vector", vector)
	_material.set_shader_parameter("strength", amount / 10.0)
	_last_position = pos
	_last_rotation = rot
