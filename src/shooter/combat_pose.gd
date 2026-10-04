extends SkeletonModifier3D
## Weapon layer runs after the baked locomotion blend, preserving leg motion.
const IK = preload("res://src/shooter/limb_ik.gd")
var rig: Node3D
var grip_errors := Vector2.ZERO
var first_person := false

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if not is_instance_valid(rig) or not is_instance_valid(skeleton): return
	if rig.death_time > 0: return
	if first_person: skeleton.reset_bone_poses()
	else:
		var hips := skeleton.find_bone("hips")
		var hips_pose := skeleton.get_bone_global_pose(hips)
		hips_pose.basis = Basis(Vector3.FORWARD, rig.turn_lean) * Basis(Vector3.RIGHT, rig.acceleration_lean) * hips_pose.basis
		skeleton.set_bone_global_pose(hips, hips_pose)
		var chest := skeleton.find_bone("chest")
		var chest_pose := skeleton.get_bone_global_pose(chest)
		chest_pose.basis = Basis(Vector3.RIGHT, 0.14 + rig.hit_weight * 0.06) * Basis(Vector3.UP, -0.25) * chest_pose.basis
		skeleton.set_bone_global_pose(chest, chest_pose)
	var right_target: Vector3 = rig.weapon.to_global(Vector3(0.015, -0.095, 0.18))
	var left_target: Vector3 = rig.weapon.to_global(Vector3(-0.012, -0.028, -0.19 if first_person else -0.10))
	var planting: bool = rig.action_pose == "vault" and rig.action_phase > 0.18 and rig.action_phase < 0.75
	if planting: left_target = rig.vault_hand_target + Vector3.UP * 0.03
	if rig.reload_time > 0:
		var phase: float = 1.0 - rig.reload_time / rig.reload_duration
		var reach := smoothstep(0.08,0.18,phase)*(1.0-smoothstep(0.75,0.90,phase))
		var magazine_target: Vector3 = rig.magazine.global_position+rig.weapon.global_basis*Vector3(-0.025,-0.035,0.015)
		left_target = left_target.lerp(magazine_target, reach)
		if rig.reload_empty:
			var charge:=sin(clampf(inverse_lerp(0.78,0.99,phase),0,1)*PI)
			right_target=right_target.lerp(rig.weapon.to_global(Vector3(0.035,0.02,0.07)),charge)
	var right_pole := rig.to_global(Vector3(0.60, -0.50, 0.05) if first_person else Vector3(0.65, 1.15 - rig.stance_weight * 0.5, 0.15))
	var left_pole := rig.to_global(Vector3(-0.55, -0.50, -0.10) if first_person else Vector3(-0.65, 1.15 - rig.stance_weight * 0.5, 0.10))
	grip_errors.x = IK.solve(skeleton, "upper_arm.R", "forearm.R", "hand.R", skeleton.to_local(right_target), skeleton.to_local(right_pole))
	grip_errors.y = IK.solve(skeleton, "upper_arm.L", "forearm.L", "hand.L", skeleton.to_local(left_target), skeleton.to_local(left_pole))
	for side in ["R", "L"]:
		if side == "L" and planting: continue
		var hand := skeleton.find_bone("hand." + side)
		var pose := skeleton.get_bone_global_pose(hand)
		var source := skeleton.get_bone_global_rest(hand).basis
		var desired_world: Basis = rig.weapon.global_basis * Basis(Vector3.FORWARD, 0.4 if side == "R" else -0.9)
		pose.basis = skeleton.global_basis.inverse() * desired_world * Basis(Vector3.RIGHT, 0.32) * source
		skeleton.set_bone_global_pose(hand, pose)
		for finger in ["f_index", "f_middle", "f_ring", "f_pinky"]:
			for joint in ["01", "02", "03"]:
				var bone := skeleton.find_bone(finger + "." + joint + "." + side)
				var curl := 0.35 if finger == "f_index" and side == "R" else 0.72
				skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3.RIGHT, curl))
