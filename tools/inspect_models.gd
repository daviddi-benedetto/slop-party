extends SceneTree
## Dev tool: print size, node layout and animations of imported .glb models.
##   engine\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tools/inspect_models.gd -- res://assets/models/toon/Weapon [tree]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "res://assets/models"
	var tree := "tree" in args
	_scan(dir, tree)
	quit()


func _scan(dir: String, tree: bool) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_scan(dir.path_join(sub), tree)
	for f in d.get_files():
		if not f.ends_with(".glb"):
			continue
		var ps: PackedScene = load(dir.path_join(f))
		var n: Node3D = ps.instantiate()
		var aabb := _aabb(n, Transform3D())
		var meshes := _count(n)
		var anims := ""
		var ap: AnimationPlayer = n.find_child("*", true, false) as AnimationPlayer
		for c in n.find_children("*", "AnimationPlayer", true, false):
			ap = c
		if ap != null:
			anims = ", ".join(ap.get_animation_list())
		print("%s  size=(%.2f, %.2f, %.2f) centre=(%.2f, %.2f, %.2f) meshes=%d %s" % [dir.path_join(f).replace("res://assets/models/", ""), aabb.size.x, aabb.size.y, aabb.size.z,
			aabb.get_center().x, aabb.get_center().y, aabb.get_center().z, meshes, ("anims=[" + anims + "]") if anims != "" else ""])
		if tree:
			_print_tree(n, "    ")
		n.free()


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var x := xf
	if n is Node3D:
		x = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out = x * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var a := _aabb(c, x)
		if a.size != Vector3.ZERO:
			out = a if first else out.merge(a)
			first = false
	return out


func _count(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for k in n.get_children():
		c += _count(k)
	return c


func _print_tree(n: Node, ind: String) -> void:
	for c in n.get_children():
		var extra := ""
		if c is Node3D:
			extra = " pos=%s rot=%s" % [(c as Node3D).position, (c as Node3D).rotation_degrees]
		print(ind, c.name, " (", c.get_class(), ")", extra)
		_print_tree(c, ind + "  ")
