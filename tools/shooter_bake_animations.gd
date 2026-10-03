extends SceneTree
## Bake explicit metre-based gait and a grounded fall into a native library.
const IK = preload("res://src/shooter/limb_ik.gd")
var skeleton: Skeleton3D
var model: Node3D

func _initialize() -> void: call_deferred("run")
func run() -> void:
	model = load("res://assets/shooter/serious/soldier.glb").instantiate()
	root.add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false)
	var library := AnimationLibrary.new()
	for definition in [["idle", 2.4], ["walk", 0.92], ["walk_back", 0.92], ["walk_left", 0.92], ["walk_right", 0.92], ["run", 0.64], ["death", 1.15],
		["cover_enter", 0.22], ["cover_idle", 2.4], ["cover_left", 0.82], ["cover_right", 0.82], ["cover_high", 2.4],
		["crouch_idle", 2.4], ["crouch_walk", 0.92], ["slide", 0.62], ["vault", 0.68], ["jump", 0.6], ["land", 0.18]]:
		var name_: String = definition[0]
		var duration: float = definition[1]
		var animation := Animation.new()
		animation.length = duration
		animation.loop_mode = Animation.LOOP_NONE if name_ in ["death", "cover_enter", "slide", "vault", "jump", "land"] else Animation.LOOP_LINEAR
		for bone in skeleton.get_bone_count():
			for type_ in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
				var track := animation.add_track(type_)
				animation.track_set_path(track, NodePath("CombatSkeleton/Skeleton3D:" + skeleton.get_bone_name(bone)))
		var samples := ceili(duration * 30)
		for sample in range(samples + 1):
			var phase := float(sample) / samples
			pose(name_, phase)
			for bone in skeleton.get_bone_count():
				animation.position_track_insert_key(bone * 2, phase * duration, skeleton.get_bone_pose_position(bone))
				animation.rotation_track_insert_key(bone * 2 + 1, phase * duration, skeleton.get_bone_pose_rotation(bone))
		library.add_animation(name_, animation)
	var error := ResourceSaver.save(library, "res://assets/shooter/serious/combat_motion.res", ResourceSaver.FLAG_COMPRESS)
	print("COMBAT_ANIMATION_BAKE ", error, " ", library.get_animation_list())
	model.queue_free()
	await process_frame
	quit(error)

func pose(clip: String, phase: float) -> void:
	skeleton.reset_bone_poses()
	var hip := skeleton.find_bone("hips")
	var pose_ := skeleton.get_bone_global_pose(hip)
	if clip == "death":
		var fall := smoothstep(0.12, 0.85, phase)
		pose_.basis = Basis(Vector3.RIGHT, fall * 1.57) * pose_.basis
		pose_.origin = Vector3(0, lerpf(1.01, 0.23, fall), lerpf(-0.055, -0.28, fall))
		skeleton.set_bone_global_pose(hip, pose_)
		for side in ["L", "R"]:
			var sign_ := 1.0 if side == "L" else -1.0
			var foot_target := Vector3(sign_ * (0.15 + fall * 0.10), 0.10, lerpf(-0.06, -1.12, fall))
			IK.solve(skeleton, "thigh."+side, "shin."+side, "foot."+side, foot_target, Vector3(sign_*0.25, 0.4, -0.4))
			var hand_target := Vector3(sign_ * 0.52, lerpf(1.08, 0.17, fall), lerpf(-0.03, 0.37, fall))
			IK.solve(skeleton, "upper_arm."+side, "forearm."+side, "hand."+side, hand_target, Vector3(sign_*0.7, 0.3, 0))
		return
	if clip.begins_with("cover_") or clip.begins_with("crouch_") or clip in ["slide", "vault", "jump", "land"]:
		var lateral := clip in ["cover_left", "cover_right"]
		var moving := lateral or clip == "crouch_walk"
		var hip_y := 0.47
		var lean := 0.12
		if clip == "cover_enter": hip_y = lerpf(0.95, 0.47, smoothstep(0, 1, phase))
		if clip == "cover_high": hip_y = 0.94; lean = -0.08
		if clip == "slide": hip_y = 0.43 + sin(phase * PI) * 0.035; lean = -0.28
		if clip == "vault": hip_y = 0.73; lean = 0.26 * sin(phase * PI)
		if clip == "jump": hip_y = 0.96; lean = 0.08
		if clip == "land": hip_y = lerpf(0.71, 0.95, smoothstep(0, 1, phase))
		pose_.origin.y = hip_y + sin(phase * TAU * (2 if moving else 1)) * 0.008
		pose_.basis = Basis(Vector3.RIGHT, lean) * pose_.basis
		skeleton.set_bone_global_pose(hip, pose_)
		for side in ["L", "R"]:
			var sign_ := 1.0 if side == "L" else -1.0
			var step := fposmod(phase + (0.5 if side == "R" else 0.0), 1)
			var travel := (0.28 * (1.0 - step * 4) if step < 0.5 else lerpf(-0.28, 0.28, smoothstep(0.5, 1, step))) if moving else 0.0
			var lift := sin((step - 0.5) * TAU) * 0.08 if moving and step > 0.5 else 0.0
			var target := Vector3(sign_ * 0.22, 0.095 + lift, 0.02 + travel)
			if lateral: target = Vector3(sign_ * 0.22 + travel * (-1 if clip == "cover_left" else 1), 0.095 + lift, 0.02)
			if clip == "slide": target = Vector3(sign_ * 0.24, 0.14, 0.55 if side == "L" else 0.26)
			if clip == "vault": target = Vector3(sign_ * 0.24, 0.18 + sin(phase * PI) * 0.22, 0.10 + sin(phase * PI) * 0.18)
			if clip == "jump": target = Vector3(sign_ * 0.18, 0.10 + sin(phase * PI) * 0.22, -0.02 + sign_ * 0.15)
			IK.solve(skeleton, "thigh."+side, "shin."+side, "foot."+side, target, Vector3(sign_*0.25, 0.45, 0.8))
			var foot := skeleton.find_bone("foot."+side)
			var foot_pose := skeleton.get_bone_global_pose(foot)
			foot_pose.basis = skeleton.get_bone_global_rest(foot).basis
			skeleton.set_bone_global_pose(foot, foot_pose)
		return
	var running := clip == "run"
	var moving := clip != "idle"
	var stride := 0.61 if running else 0.42
	pose_.origin.y -= 0.10 if moving else 0.06
	pose_.origin.y += (cos(phase * TAU * 2) * 0.022) if moving else sin(phase * TAU) * 0.007
	pose_.basis = Basis(Vector3.FORWARD, sin(phase * TAU) * (0.025 if moving else 0.005)) * pose_.basis
	skeleton.set_bone_global_pose(hip, pose_)
	for side in ["L", "R"]:
		var sign_ := 1.0 if side == "L" else -1.0
		var step := fposmod(phase + (0.5 if side == "R" else 0.0), 1.0)
		var z := -0.06
		var lift := 0.0
		if moving:
			if step < 0.5: z += lerpf(stride, -stride, step * 2)
			else:
				z += lerpf(-stride, stride, smoothstep(0.5, 1.0, step))
				lift = sin((step - 0.5) * TAU) * (0.21 if running else 0.12)
		var target := Vector3(sign_ * 0.15, 0.095 + lift, z)
		var angle := PI if clip == "walk_back" else PI / 2 if clip == "walk_left" else -PI / 2 if clip == "walk_right" else 0.0
		var neutral := Vector3(sign_ * 0.15, 0, -0.06)
		target = neutral + Basis(Vector3.UP, angle) * (target - neutral)
		IK.solve(skeleton, "thigh."+side, "shin."+side, "foot."+side, target, Vector3(sign_*0.15, 0.5, 0.8))
		var foot := skeleton.find_bone("foot."+side)
		var foot_pose := skeleton.get_bone_global_pose(foot)
		foot_pose.basis = skeleton.get_bone_global_rest(foot).basis
		skeleton.set_bone_global_pose(foot, foot_pose)
