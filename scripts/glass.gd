extends StaticBody3D
## A breakable glass pane (windows, glass walls). On the props layer (4), so
## it never blocks movement: bullets, explosions and anyone walking through
## it call knock(), which shatters it into shards (fx + sound). Bullets carry
## on through. Shattered panes stay gone for the rest of the match.

const Fx = preload("res://scripts/fx.gd")

static var _mat: StandardMaterial3D

var is_glass := true
var mass := 1.0
var size := Vector3(1.4, 1.35, 0.05)
var game_world: Node3D
var _broken := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	add_to_group("props")
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color = Color(0.62, 0.82, 0.92, 0.3)
		_mat.roughness = 0.04
		_mat.metallic = 0.5
		_mat.rim_enabled = true
		_mat.rim = 0.6
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = size + Vector3(0, 0, 0.1)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)


func knock(impulse: Vector3, at: Vector3) -> void:
	if _broken:
		return
	_broken = true
	collision_layer = 0
	var world: Node3D = game_world if game_world != null else get_parent()
	var dir := impulse.normalized() if impulse.length() > 0.01 else global_transform.basis.z
	var n := int(clampf(size.x * size.y * 14.0, 10.0, 40.0))
	for i in 3:
		var p: Vector3 = global_transform * Vector3(randf_range(-0.4, 0.4) * size.x, randf_range(-0.4, 0.4) * size.y, 0)
		Fx.sparks(world, p, Color(0.8, 0.95, 1.0), n / 3, 5.0, dir, 70.0, 0.7)
	Fx.puff(world, at, Color(0.85, 0.95, 1.0, 0.35), 4, 0.5)
	Sfx.play_at("glass", global_position, -2.0, randf_range(0.9, 1.15))
	queue_free()
