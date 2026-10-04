@tool
extends RefCounted
const BUILDER=preload("res://tools/shooter_motion_builder.gd")
func run(context: SceneTree, _arguments: Dictionary) -> Dictionary:
	var library: AnimationLibrary=BUILDER.new().build(context)
	if not library:return {"ok":false,"error":"motion bake failed"}
	context.register("motion_library",library)
	return {"ok":true,"clips":library.get_animation_list().size(),"scope":"explicit source retarget with project contact cleanup"}
