extends RefCounted
## Authoring-only global rest-space rotation transfer for an explicit partial bone map.
## Different topology is supported through global poses; contacts remain project-owned.
static func transfer(source: Skeleton3D, target: Skeleton3D, mapping: Dictionary, translation_scale: float = 1.0, translated_source_bone: String = "") -> Dictionary:
	if mapping.is_empty(): return {"ok":false,"error":"explicit non-empty bone map required"}
	if translation_scale <= 0 or not is_finite(translation_scale): return {"ok":false,"error":"positive finite translation scale required"}
	var pairs: Array[Vector2i] = []
	var targets: Array[int] = []
	for source_name in mapping:
		var a := source.find_bone(source_name)
		var b := target.find_bone(mapping[source_name])
		if a < 0 or b < 0 or b in targets: return {"ok":false,"error":"missing or duplicate mapped bone: "+source_name}
		targets.append(b); pairs.append(Vector2i(a,b))
	if not translated_source_bone.is_empty() and not mapping.has(translated_source_bone): return {"ok":false,"error":"translated source bone must be mapped explicitly"}
	# Parent order is needed when global rotations are converted into local poses.
	pairs.sort_custom(func(a,b):return depth(target,a.y)<depth(target,b.y))
	for pair in pairs:
		var source_rest := source.get_bone_global_rest(pair.x)
		var source_pose := source.get_bone_global_pose(pair.x)
		var target_rest := target.get_bone_global_rest(pair.y)
		var pose := target.get_bone_global_pose(pair.y)
		var pose_scale := pose.basis.get_scale()
		pose.basis = (source_pose.basis.orthonormalized()*source_rest.basis.orthonormalized().inverse()*target_rest.basis.orthonormalized()).orthonormalized().scaled_local(pose_scale)
		if source.get_bone_name(pair.x) == translated_source_bone:
			pose.origin = target_rest.origin+(source_pose.origin-source_rest.origin)*translation_scale
		target.set_bone_global_pose(pair.y,pose)
	return {"ok":true,"mapped_bones":pairs.size(),"scope":"global rest-space authoring transfer; project contact and visual review required"}
static func depth(skeleton: Skeleton3D, bone: int) -> int:
	var count := 0
	while bone >= 0:
		bone = skeleton.get_bone_parent(bone); count += 1
	return count
