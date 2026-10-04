extends SceneTree
const BUILDER=preload("res://tools/shooter_motion_builder.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var library: AnimationLibrary=BUILDER.new().build(self)
	if not library:quit(1);return
	var error:=ResourceSaver.save(library,"res://assets/shooter/serious/combat_motion.res",ResourceSaver.FLAG_COMPRESS)
	print("COMBAT_ANIMATION_BAKE ",error," ",library.get_animation_list())
	quit(error)
