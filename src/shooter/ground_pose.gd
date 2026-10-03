extends SkeletonModifier3D
## Ground-height correction preserves the authored swing; airborne actions opt out.
const IK = preload("res://src/shooter/limb_ik.gd")
var rig: Node3D
var offsets := Vector2.ZERO
var contact_errors := Vector2.ZERO

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if not is_instance_valid(rig) or rig.death_time > 0: return
	var actor := rig.get_parent() as CharacterBody3D
	if not is_instance_valid(actor) or not actor.is_on_floor() or rig.action_pose in ["jump", "vault", "slide"]:
		offsets = Vector2.ZERO
		return
	var delta := minf(get_process_delta_time(), 0.05)
	for index in range(2):
		var side := "L" if index == 0 else "R"
		var foot := skeleton.find_bone("foot." + side)
		var pose := skeleton.get_bone_global_pose(foot)
		var point := skeleton.to_global(pose.origin)
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.35,
			Vector3(point.x, actor.global_position.y - 0.42, point.z), 1, [actor.get_rid()])
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		var correction := 0.0
		if not hit.is_empty() and hit.normal.y > 0.8:
			correction = clampf(hit.position.y - actor.global_position.y, -0.18, 0.18)
		offsets[index] = lerpf(offsets[index], correction, 1.0 - exp(-delta * 18))
		var target := point + Vector3.UP * offsets[index]
		var pole := rig.to_global(Vector3(0.2 if side == "L" else -0.2, 0.5, -0.65))
		contact_errors[index] = IK.solve(skeleton, "thigh." + side, "shin." + side, "foot." + side,
			skeleton.to_local(target), skeleton.to_local(pole))
