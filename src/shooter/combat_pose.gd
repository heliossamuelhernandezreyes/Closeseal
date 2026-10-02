extends SkeletonModifier3D
## Combat layer runs after the licensed skeletal clips, preserving the leg animation.
var rig: Node3D
var grip_errors := Vector2.ZERO

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if not is_instance_valid(rig) or not is_instance_valid(skeleton): return
	if rig.death_time > 0.0:
		var hip := skeleton.find_bone("HipsCtrl")
		var pose := skeleton.get_bone_global_pose(hip)
		var fall := smoothstep(0.0, 0.8, rig.death_time)
		var axis := skeleton.global_basis.inverse() * rig.global_basis.x
		pose.basis = Basis(axis.normalized(), fall * 1.48) * pose.basis
		var world_position := skeleton.global_transform * pose.origin
		world_position.y = lerpf(world_position.y, rig.global_position.y + 0.35, fall)
		pose.origin = skeleton.to_local(world_position)
		skeleton.set_bone_global_pose(hip, pose)
		return
	var left_target: Vector3 = rig.weapon.to_global(Vector3(-0.055, 0.01, -0.19))
	if rig.reload_time > 0.0:
		var phase: float = clampf(rig.reload_time / 1.6, 0.0, 1.0)
		left_target = left_target.lerp(rig.to_global(Vector3(-0.18, 0.85, -0.12)), sin(phase * PI))
	var right_target: Vector3 = rig.weapon.to_global(Vector3(0.045, -0.06, 0.17))
	grip_errors.x = solve_arm(skeleton, "Right", right_target, rig.to_global(Vector3(0.5, 0.95, 0.03)))
	grip_errors.y = solve_arm(skeleton, "Left", left_target, rig.to_global(Vector3(-0.48, 1.0, -0.03)))

func solve_arm(skeleton: Skeleton3D, side: String, world_target: Vector3, world_pole: Vector3) -> float:
	var upper := skeleton.find_bone(side + "Arm")
	var fore := skeleton.find_bone(side + "ForeArm")
	var hand := skeleton.find_bone(side + "Hand")
	var a := skeleton.get_bone_global_pose(upper).origin
	var b := skeleton.get_bone_global_pose(fore).origin
	var c := skeleton.get_bone_global_pose(hand).origin
	var target := skeleton.to_local(world_target)
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var d := clampf(a.distance_to(target), absf(l1 - l2) + 0.00001, l1 + l2 - 0.00001)
	var direction := (target - a).normalized()
	var pole := skeleton.to_local(world_pole) - a
	var bend := (pole - direction * pole.dot(direction)).normalized()
	var along := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
	var elbow := a + direction * along + bend * sqrt(maxf(0.0, l1 * l1 - along * along))
	_aim_bone(skeleton, upper, fore, elbow)
	_aim_bone(skeleton, fore, hand, target)
	return (skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin).distance_to(world_target)

func _aim_bone(skeleton: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var old_direction := (skeleton.get_bone_global_pose(child).origin - pose.origin).normalized()
	var new_direction := (target - pose.origin).normalized()
	pose.basis = Basis(Quaternion(old_direction, new_direction)) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
