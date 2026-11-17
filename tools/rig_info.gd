extends SceneTree
## Dev tool: print bones and animations of one rigged model.
##   --script tools/rig_info.gd -- res://assets/models/animals/m_Bunny_14.glb
func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var n: Node = load(a).instantiate()
		for s in n.find_children("*", "Skeleton3D", true, false):
			var sk: Skeleton3D = s
			var names: Array = []
			for i in sk.get_bone_count():
				names.append("%s<%d" % [sk.get_bone_name(i), sk.get_bone_parent(i)])
			print(a, " bones: ", ", ".join(names))
			for bn in ["Hand.R", "Hand.L", "Fist.R", "LowerArm.R", "UpperArm.R", "Head"]:
				var bi := sk.find_bone(bn)
				if bi >= 0:
					print("  ", bn, " rest global ", sk.get_bone_global_rest(bi).origin, " basis x", sk.get_bone_global_rest(bi).basis.x, " y", sk.get_bone_global_rest(bi).basis.y)
		for p in n.find_children("*", "AnimationPlayer", true, false):
			var ap: AnimationPlayer = p
			var out: Array = []
			for an in ap.get_animation_list():
				out.append("%s(%.2f)" % [an, ap.get_animation(an).length])
			print("  anims: ", ", ".join(out))
		n.free()
	for c in ["TwoBoneIK3D", "SkeletonIK3D", "SkeletonModifier3D"]:
		print(c, " exists=", ClassDB.class_exists(c))
	if ClassDB.class_exists("TwoBoneIK3D"):
		var ms: Array = []
		for m in ClassDB.class_get_method_list("TwoBoneIK3D", true):
			ms.append(m.name)
		print(ms)
		var ps: Array = []
		for m in ClassDB.class_get_property_list("TwoBoneIK3D", true):
			ps.append(m.name)
		print(ps)
	quit()
