extends RefCounted
## Analytic two-bone solve in skeleton space. Used for feet and weapon grips.
static func aim(skeleton: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var old := (skeleton.get_bone_global_pose(child).origin - pose.origin).normalized()
	var direction := (target - pose.origin).normalized()
	pose.basis = Basis(Quaternion(old, direction)) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)

static func solve(skeleton: Skeleton3D, upper: String, middle: String, end: String, target: Vector3, pole: Vector3) -> float:
	var a_id := skeleton.find_bone(upper)
	var b_id := skeleton.find_bone(middle)
	var c_id := skeleton.find_bone(end)
	assert(a_id >= 0 and b_id >= 0 and c_id >= 0, "Incomplete combat skeleton")
	var a := skeleton.get_bone_global_pose(a_id).origin
	var b := skeleton.get_bone_global_pose(b_id).origin
	var c := skeleton.get_bone_global_pose(c_id).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var distance := clampf(a.distance_to(target), absf(l1 - l2) + 0.00001, l1 + l2 - 0.00001)
	var direction := (target - a).normalized()
	var bend := pole - a
	bend = (bend - direction * bend.dot(direction)).normalized()
	var along := (l1 * l1 + distance * distance - l2 * l2) / (2 * distance)
	var elbow := a + direction * along + bend * sqrt(maxf(0, l1 * l1 - along * along))
	aim(skeleton, a_id, b_id, elbow)
	aim(skeleton, b_id, c_id, target)
	return skeleton.get_bone_global_pose(c_id).origin.distance_to(target)
