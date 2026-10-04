extends SkeletonModifier3D
## Bounded Hermite pose offsets preserve continuity on action changes before contact IK.
var rig: Node3D
var previous_positions: Array[Vector3] = []
var previous_rotations: Array[Quaternion] = []
var previous_velocities: Array[Vector3] = []
var previous_inputs: Array[Vector3] = []
var position_offsets: Array[Vector3] = []
var rotation_offsets: Array[Quaternion] = []
var velocity_offsets: Array[Vector3] = []
var key := ""
var elapsed := 1.0
var duration := 0.16
var maximum_correction := 0.0

func _process_modification() -> void:
	apply_pose(get_process_delta_time())

func apply_pose(sample_delta: float) -> void:
	var skeleton := get_skeleton()
	if not is_instance_valid(rig) or rig.death_time>0:return
	var next_key: String = rig.action_pose + ("/air" if rig.airborne else "/floor")
	var delta := maxf(sample_delta,0.0001)
	if previous_positions.size()!=skeleton.get_bone_count():
		for bone in skeleton.get_bone_count():
			previous_positions.append(skeleton.get_bone_pose_position(bone))
			previous_rotations.append(skeleton.get_bone_pose_rotation(bone))
			previous_velocities.append(Vector3.ZERO)
			previous_inputs.append(skeleton.get_bone_pose_position(bone))
			position_offsets.append(Vector3.ZERO)
			rotation_offsets.append(Quaternion.IDENTITY)
			velocity_offsets.append(Vector3.ZERO)
		key=next_key
	if key!=next_key:
		key=next_key
		elapsed=0.0
		duration=0.12 if rig.action_pose in ["jump","land","vault"] else 0.16
		for bone in skeleton.get_bone_count():
			position_offsets[bone]=(previous_positions[bone]-skeleton.get_bone_pose_position(bone)).limit_length(0.25)
			rotation_offsets[bone]=previous_rotations[bone]*skeleton.get_bone_pose_rotation(bone).inverse()
			var incoming_velocity := ((skeleton.get_bone_pose_position(bone)-previous_inputs[bone])/delta).limit_length(1.0)
			velocity_offsets[bone]=(previous_velocities[bone]-incoming_velocity).limit_length(2.0)
	var u := clampf(elapsed/duration,0.0,1.0)
	var decay := 1.0-u*u*(3.0-2.0*u)
	var tangent := duration*(u-2.0*u*u+u*u*u)
	for bone in skeleton.get_bone_count():
		var position := skeleton.get_bone_pose_position(bone)
		var rotation := skeleton.get_bone_pose_rotation(bone)
		previous_inputs[bone]=position
		if elapsed<duration:
			var correction := position_offsets[bone]*decay+velocity_offsets[bone]*tangent
			maximum_correction=maxf(maximum_correction,correction.length())
			position+=correction
			rotation=Quaternion.IDENTITY.slerp(rotation_offsets[bone],decay)*rotation
			skeleton.set_bone_pose_rotation(bone,rotation.normalized())
		if skeleton.get_bone_name(bone)=="hips" and rig.action_pose not in ["jump","land","vault","slide"]:
			position=previous_positions[bone]+(position-previous_positions[bone]).limit_length(1.4*delta)
		skeleton.set_bone_pose_position(bone,position)
		previous_velocities[bone]=(position-previous_positions[bone])/delta
		previous_positions[bone]=position
		previous_rotations[bone]=rotation
	elapsed+=delta
