extends Node3D
## Dev showcase for the snap-together building kits (assets/models/kit_*):
## one small building from each kit on a lawn, in the lobby's sunny lighting
## (stage.gd), with plush animals out front for scale.
##
##   --kit-test[=medieval|dungeon|all] --shot=out.png [--shot-time=4]
##   [--kit-cam=x,y,z,tx,ty,tz]   override the camera
##
## Kit conventions (measured, see the kit_* folders):
##   medieval  2 m grid, walls 3.12 high, centred on their edge (x -1..1),
##             scaled 1.25 here so doorways suit our animals
##   dungeon   4 m grid, walls 4 high, centred on their edge (x -2..2)

const Stage = preload("res://scripts/stage.gd")
const Models = preload("res://scripts/models.gd")
const UiKit = preload("res://scripts/ui_kit.gd")

const SPOTS := {"medieval": Vector3(-9, 0, 0), "dungeon": Vector3(9, 0, 0)}
const BASE := Vector3(300, 0, 0)       # far from the lobby backyard
var stage


func run(which: String, cam: String) -> void:
	stage = Stage.new()
	add_child(stage)
	stage.build(Vector3(0, 5, 18), Vector3(0, 3, 0), 40.0, {})
	# A lawn under the showcase.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.62, 0.3)
	gm.roughness = 0.9
	ground.material_override = gm
	ground.position = BASE + Vector3(0, 0.01, 0)
	add_child(ground)
	var kits: Array = SPOTS.keys() if which == "all" or which == "1" else [which]
	for k in kits:
		var root := Node3D.new()
		root.position = BASE + (SPOTS[k] if kits.size() > 1 else Vector3.ZERO)
		add_child(root)
		call("_" + k, root)
		# Two plush animals for scale.
		for i in 2:
			stage.add_character({"kind": i * 3 + kits.find(k), "color": UiKit.PLAYER_COLORS[(i + kits.find(k) * 2) % 6], "hat": i},
				root.position + Vector3(-1.2 + i * 2.4, 0, 6.5))
	var c: Camera3D = stage.camera
	if cam != "":
		var v := cam.split(",")
		c.look_at_from_position(Vector3(float(v[0]), float(v[1]), float(v[2])), Vector3(float(v[3]), float(v[4]), float(v[5])))
	elif kits.size() > 1:
		c.look_at_from_position(BASE + Vector3(0, 10, 34), BASE + Vector3(0, 3, 0))
	else:
		c.look_at_from_position(BASE + Vector3(7, 6, 17), BASE + Vector3(0, 3, 0))
	c.fov = 55.0


func _put(parent: Node3D, path: String, pos: Vector3, yaw := 0.0) -> Node3D:
	var inst: Node3D = Models.scene(path).instantiate()
	inst.position = pos
	inst.rotation.y = yaw
	parent.add_child(inst)
	Models.toy_node(inst)
	return inst


## A two-storey cottage, 2 x 3 modules (5 x 7.5 m after scaling), brick below,
## plaster and timber above, tiled roof with brick gables, stairs inside.
func _medieval(root: Node3D) -> void:
	var h := Node3D.new()
	h.scale = Vector3.ONE * 1.25
	root.add_child(h)
	var K := "kit_medieval/"
	var fh := 3.12
	for storey in 2:
		var y := storey * fh
		var mat := "UnevenBrick" if storey == 0 else "Plaster"
		var front := ["Wall_%s_Door_Round" % mat, "Wall_%s_Window_Wide_Round" % mat] if storey == 0 else ["Wall_Plaster_Window_Wide_Round", "Wall_Plaster_Window_Wide_Round"]
		var back := ["Wall_%s_Straight" % mat, "Wall_%s_Window_Thin_Round" % mat]
		var side := ["Wall_%s_Straight" % mat, "Wall_%s_Window_Wide_Flat" % mat, "Wall_%s_Straight" % mat] if storey == 0 else ["Wall_Plaster_WoodGrid", "Wall_Plaster_Window_Wide_Flat", "Wall_Plaster_WoodGrid"]
		for i in 2:
			_put(h, K + front[i], Vector3(-1 + i * 2, y, 3), 0.0)
			_put(h, K + back[i], Vector3(1 - i * 2, y, -3), PI)
		for i in 3:
			_put(h, K + side[i], Vector3(-2, y, 2 - i * 2), -PI * 0.5)
			_put(h, K + side[i], Vector3(2, y, -2 + i * 2), PI * 0.5)
		for cx in [-2, 2]:
			for cz in [-3, 3]:
				_put(h, K + ("Corner_Exterior_Brick" if storey == 0 else "Corner_Exterior_Wood"), Vector3(cx, y, cz), 0.0)
		for x in [-1, 1]:
			for z in [-2, 0, 2]:
				if storey == 1 and x == -1 and z != 2:
					continue           # stairwell
				_put(h, K + ("Floor_WoodLight" if storey == 0 else "Floor_WoodDark"), Vector3(x, y + 0.01, z))
	# Glass in the window holes, shutters on the front.
	_put(h, K + "Window_Wide_Round1", Vector3(1, 0, 3))
	for x in [-1, 1]:
		_put(h, K + "Window_Wide_Round1", Vector3(x, fh, 3))
		_put(h, K + "WindowShutters_Wide_Round_Open", Vector3(x, fh, 3))
	_put(h, K + "Door_1_Round", Vector3(-1.55, 0, 3.05))
	_put(h, K + "Stair_Interior_Solid", Vector3(-1, 0, 2.3), 0.0)
	_put(h, K + "Roof_RoundTiles_4x6", Vector3(0, fh * 2, 0))
	_put(h, K + "Roof_Front_Brick4", Vector3(0, fh * 2, 3))
	_put(h, K + "Roof_Front_Brick4", Vector3(0, fh * 2, -3), PI)


## A stone hall, 3 x 2 cells (12 x 8 m) with an arched window front, a
## doorway, torches and a table inside.
func _dungeon(root: Node3D) -> void:
	var K := "kit_dungeon/"
	for x in [-4, 0, 4]:
		for z in [-2, 2]:
			_put(root, K + "floor_tile_large", Vector3(x, 0, z))
	var front := ["wall_window_open", "wall_doorway", "wall_window_open"]
	var back := ["wall", "wall_arched", "wall"]
	for i in 3:
		_put(root, K + front[i], Vector3(-4 + i * 4, 0, 4))
		_put(root, K + back[i], Vector3(-4 + i * 4, 0, -4), PI)
	for z in [-2, 2]:
		_put(root, K + "wall", Vector3(-6, 0, z), PI * 0.5)
		_put(root, K + "wall", Vector3(6, 0, z), -PI * 0.5)
	for c in [Vector3(-6, 0, 4), Vector3(6, 0, 4), Vector3(6, 0, -4), Vector3(-6, 0, -4)]:
		_put(root, K + "pillar", c)
	_put(root, K + "table_medium_decorated_A", Vector3(1.5, 0, -1.0))
	_put(root, K + "barrel_large", Vector3(-4.5, 0, -2.5))
	_put(root, K + "torch_mounted", Vector3(-2, 2.2, -3.4))
	_put(root, K + "torch_mounted", Vector3(2, 2.2, -3.4))
	_put(root, K + "banner_patternA_blue", Vector3(0, 2.5, -3.4))
	_put(root, K + "chest", Vector3(4.2, 0, 2.5), PI)
