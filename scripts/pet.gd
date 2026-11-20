extends Node3D
## A friendly dog, cat, fox or bunny that wanders the map and can be petted.
## Spawned by game.gd on random walkable spots once the nav graph exists.
## Pets are scenery with a heart: nothing can hurt them, bullets pass through,
## bots ignore them.
##
## Wandering: pick a nav point nearby, follow map.find_path() at walking pace,
## sit for a while, repeat. Petting: player.gd shows "PET THE DOG" when one is
## within reach (game.pet_near) and calls pet(): happy animation, hearts, a
## bark or meow, and a small heal for the player (once every few seconds).

const Models = preload("res://scripts/models.gd")
const Fx = preload("res://scripts/fx.gd")

## [model, label, height in model units, wanted height (m), walk anim, idle anim, happy anim, sound]
const KINDS := [
	["pets/Husky", "HUSKY", 3.19, 0.8, "Walk", "Idle", "Idle_2", "bark"],
	["pets/ShibaInu", "SHIBA", 3.1, 0.7, "Walk", "Idle", "Idle_2", "bark"],
	["pets/Characters_German_Shepherd", "DOG", 0.94, 0.85, "Walk", "Idle", "Idle_2", "bark"],
	["pets/Characters_Pug", "PUG", 0.76, 0.5, "Walk", "Idle", "Idle_2", "bark"],
	["pets/Cat", "CAT", 1.71, 0.55, "walk", "idle", "gesture-positive", "meow"],
	["pets/Cat", "CAT", 1.71, 0.5, "walk", "idle", "dance", "meow"],
	["pets/Fox", "FOX", 2.68, 0.65, "Walk", "Idle", "Idle_2", "meow"],
	["pets/Bunny", "BUNNY", 2.01, 0.45, "walk", "idle", "dance", "pet"],
]

var game
var label := "DOG"
var _kind: Array
var _anim: AnimationPlayer
var _path := PackedVector3Array()
var _path_i := 0
var _wait := 1.0
var _happy := 0.0
var _cooldown := 0.0


func setup(kind: int) -> void:
	_kind = KINDS[kind % KINDS.size()]
	label = _kind[1]


func _ready() -> void:
	var inst: Node3D = Models.scene(_kind[0]).instantiate()
	inst.scale = Vector3.ONE * (float(_kind[3]) / float(_kind[2]))
	add_child(inst)
	Models.toy_node(inst, false)
	for c in inst.find_children("*", "AnimationPlayer", true, false):
		_anim = c
	if _anim != null:
		for a in [_kind[4], _kind[5]]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		_anim.playback_default_blend_time = 0.2
	_play(_kind[5])
	_wait = randf_range(0.5, 3.0)


func _play(a: String) -> void:
	if _anim != null and _anim.has_animation(a) and _anim.current_animation != a:
		_anim.play(a)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _happy > 0.0:
		_happy -= delta
		if _happy <= 0.0:
			_play(_kind[5])
		return
	if _path_i < _path.size():
		var to: Vector3 = _path[_path_i] - global_position
		var flat := Vector3(to.x, 0, to.z)
		if flat.length() < 0.25:
			_path_i += 1
		else:
			var step := to.normalized() * minf(1.6 * delta, to.length())
			global_position += step
			rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), clampf(delta * 6.0, 0.0, 1.0))
			_play(_kind[4])
		return
	_play(_kind[5])
	_wait -= delta
	if _wait <= 0.0:
		_wait = randf_range(2.0, 7.0)
		# Wander to a walkable spot not too far away.
		for i in 6:
			var p: Vector3 = game.map.random_nav_point()
			if p.distance_to(global_position) < 16.0 and absf(p.y - global_position.y) < 1.0:
				_path = game.map.find_path(global_position, p)
				_path_i = 1
				break


func pet(player) -> void:
	_happy = 1.8
	_path = PackedVector3Array()
	var to: Vector3 = player.global_position - global_position
	rotation.y = atan2(to.x, to.z)
	_play(_kind[6])
	if _anim != null:
		_anim.seek(0.0)
	var head := global_position + Vector3(0, float(_kind[3]) + 0.3, 0)
	Fx.sparks(game.world, head, Color(1.0, 0.35, 0.55), 10, 1.6, Vector3.UP, 50.0, 1.2)
	Fx.ring(game.world, head, Color(1.0, 0.5, 0.7, 0.8), 0.1, 0.7, 0.4)
	Sfx.play_at(_kind[7], global_position, -4.0, randf_range(0.9, 1.2))
	Sfx.play_at("pet", global_position, -8.0)
	player.say("YOU PET THE %s!" % label)
	if _cooldown <= 0.0:
		_cooldown = 6.0
		player.heal(15.0)
