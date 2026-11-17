extends SkeletonModifier3D
## Two-bone arm IK for the creature rig, so characters really hold what they
## carry: character.gd keeps the weapon on its aim pivot (it follows the view
## pitch exactly) and this modifier bends each arm so the hand reaches a grip
## marker on the weapon, on top of whatever animation is playing.
##
## Bones point along their local +Y. add_arm() takes the upper and lower arm
## bone names; `hand` is the distance from the elbow to the palm in skeleton
## units. A chain whose target is null or hidden is left to the animation
## (taunts and punches switch the whole modifier off through `influence`).

var _arms: Array = []       # [{upper, lower, hand, target, pole}]


func add_arm(upper: String, lower: String, hand: float, pole: Vector3) -> int:
	var sk := get_skeleton()
	_arms.append({"upper": sk.find_bone(upper), "lower": sk.find_bone(lower), "hand": hand, "target": null, "pole": pole})
	return _arms.size() - 1


func set_target(arm: int, target: Node3D) -> void:
	_arms[arm].target = target


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var inv := sk.global_transform.affine_inverse()
	for arm in _arms:
		var target: Node3D = arm.target
		if target == null or not is_instance_valid(target) or not target.is_visible_in_tree() or arm.upper < 0 or arm.lower < 0:
			continue
		var up: Transform3D = sk.get_bone_global_pose(arm.upper)
		var lo: Transform3D = sk.get_bone_global_pose(arm.lower)
		var shoulder := up.origin
		var goal: Vector3 = inv * target.global_position
		var l1 := shoulder.distance_to(lo.origin)
		var l2: float = arm.hand
		var to := goal - shoulder
		var d := clampf(to.length(), absf(l1 - l2) + 0.02, (l1 + l2) * 0.995)
		var dir := to.normalized()
		# Elbow position from the law of cosines, pushed towards the pole.
		var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
		var pole: Vector3 = arm.pole
		var side := pole - dir * pole.dot(dir)
		side = side.normalized() if side.length() > 0.001 else Vector3.DOWN
		var elbow := shoulder + dir * a + side * h
		var want_up := (elbow - shoulder).normalized()
		var cur_up := (lo.origin - shoulder).normalized()
		if cur_up.dot(want_up) > -0.999:
			sk.set_bone_global_pose(arm.upper, Transform3D(Basis(Quaternion(cur_up, want_up)) * up.basis, shoulder))
		var lo2: Transform3D = sk.get_bone_global_pose(arm.lower)
		var cur_lo := lo2.basis.y.normalized()
		var want_lo := (shoulder + dir * d - lo2.origin).normalized()
		if cur_lo.dot(want_lo) > -0.999:
			sk.set_bone_global_pose(arm.lower, Transform3D(Basis(Quaternion(cur_lo, want_lo)) * lo2.basis, lo2.origin))
