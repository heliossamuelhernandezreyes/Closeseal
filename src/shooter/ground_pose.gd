extends SkeletonModifier3D
## Bounded world-space stance contacts; authored swing and airborne actions opt out.
const IK = preload("res://src/shooter/limb_ik.gd")
const MOTION = preload("res://src/shooter/motion_profile.gd")
signal foot_planted(side: int, point: Vector3, collider: Object)
var rig: Node3D
var offsets := Vector2.ZERO
var contact_errors := Vector2.ZERO
var planted: Array[bool] = [false, false]
var anchors: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var support: Array[RID] = [RID(), RID()]
var last_action := ""
var maximum_lock_correction := 0.0

func reset_contacts() -> void:
	planted = [false, false]
	support = [RID(), RID()]

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if not is_instance_valid(rig) or rig.death_time > 0: return
	var actor := rig.get_parent() as CharacterBody3D
	if not is_instance_valid(actor) or not actor.is_on_floor() or rig.action_pose in ["jump", "vault", "slide"]:
		offsets = Vector2.ZERO
		reset_contacts()
		return
	if last_action != rig.action_pose:
		reset_contacts()
		last_action = rig.action_pose
	var locking: bool = rig.motion_speed > 0.15 and (not "mobility" in actor or actor.mobility.state not in ["corner", "transfer"])
	if not locking: reset_contacts()
	var delta := minf(get_process_delta_time(), 0.05)
	for index in range(2):
		var side := "L" if index == 0 else "R"
		var foot := skeleton.find_bone("foot." + side)
		var pose := skeleton.get_bone_global_pose(foot)
		var knee := skeleton.get_bone_global_pose(skeleton.find_bone("shin." + side)).origin
		var point := skeleton.to_global(pose.origin)
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.35,
			Vector3(point.x, actor.global_position.y - 0.42, point.z), 1, [actor.get_rid()])
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		var correction := 0.0
		if not hit.is_empty() and hit.normal.y > 0.8:
			correction = clampf(hit.position.y - actor.global_position.y, -0.18, 0.18)
		offsets[index] = lerpf(offsets[index], correction, 1.0 - exp(-delta * 18))
		var target := point + Vector3.UP * offsets[index]
		if locking and not hit.is_empty() and hit.normal.y > 0.8:
			var ankle_height: float = point.y - actor.global_position.y
			var stance := ankle_height <= MOTION.SOLE_HEIGHT + (0.018 if planted[index] else 0.008)
			if not stance or support[index] != hit.rid or point.distance_to(anchors[index]) > 0.20:
				planted[index] = false
			if stance and not planted[index]:
				anchors[index] = target
				support[index] = hit.rid
				planted[index] = true
				foot_planted.emit(index, hit.position, hit.collider)
			if planted[index]:
				var horizontal := Vector3(anchors[index].x-point.x,0,anchors[index].z-point.z)
				maximum_lock_correction = maxf(maximum_lock_correction,horizontal.length())
				target += horizontal.limit_length(0.16)
		else: planted[index] = false
		# With no active contact or slope correction the authored pose is untouched.
		if point.distance_to(target) < 0.001:
			contact_errors[index] = 0.0
			continue
		contact_errors[index] = IK.solve(skeleton, "thigh." + side, "shin." + side, "foot." + side,
			skeleton.to_local(target), knee)
		var corrected := skeleton.get_bone_global_pose(foot)
		corrected.basis = pose.basis
		if planted[index] and not hit.is_empty():
			var normal_local: Vector3 = skeleton.global_basis.inverse() * hit.normal
			var up := corrected.basis.y.normalized()
			if up.dot(normal_local) > 0.95:
				corrected.basis = Basis(Quaternion(up, normal_local)) * corrected.basis
		skeleton.set_bone_global_pose(foot, corrected)
