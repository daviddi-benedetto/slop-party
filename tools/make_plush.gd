extends SceneTree
## Generates the plush animal meshes (scripts/plush.gd) into
## assets/models/plush/. Run after changing a shape or colour in plush.gd:
##   engine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tools/make_plush.gd
## Optional: -- <kind> to rebuild one animal only.

const Plush = preload("res://scripts/plush.gd")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Plush.DIR))
	var only := -1
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = int(args[0])
	for kind in Plush.NAMES.size():
		if only >= 0 and kind != only:
			continue
		for part in ["body", "tail"]:
			var t := Time.get_ticks_msec()
			var m: ArrayMesh = Plush.build(kind, part)
			var path: String = Plush.DIR + "%s_%s.res" % [Plush.NAMES[kind], part]
			var err := ResourceSaver.save(m, path, ResourceSaver.FLAG_COMPRESS)
			print("%s: %d tris, %d ms, %s" % [path, m.surface_get_array_len(0) if false else m.get_faces().size() / 3, Time.get_ticks_msec() - t, error_string(err)])
	quit()
