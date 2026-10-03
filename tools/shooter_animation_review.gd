extends SceneTree
const RIG = preload("res://src/shooter/character_rig.gd")
var actor: Node3D
var camera: Camera3D
var directory := "user://animation-review"

func _initialize() -> void: call_deferred("run")
func snapshot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(name + ".png"))
func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): directory = argument.trim_prefix("--captures=")
	DirAccess.make_dir_recursive_absolute(directory)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("182c3b")
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load("res://assets/shooter/serious/evening_road_01_puresky.hdr")
	sky_material.energy_multiplier = 0.55
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.environment.sky = sky
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.environment.ambient_light_energy = 0.75
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	light.light_energy = 0.8
	light.shadow_enabled = true
	world.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("314a58")
	floor_mesh.material_override = material
	floor_mesh.position.y = -0.02
	world.add_child(floor_mesh)
	actor = RIG.new()
	world.add_child(actor)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(2.8, 1.7, -3.5)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.fov = 38
	camera.current = true
	await create_timer(1.2).timeout
	print("RIG_GEOMETRY " + JSON.stringify({"skeleton_transform": str(actor.skeleton.global_transform),
		"left_shoulder": str(actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("upper_arm.L")).origin),
		"right_shoulder": str(actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("upper_arm.R")).origin),
		"left_grip": str(actor.weapon.to_global(Vector3(-0.012, -0.028, -0.19))), "grip_errors": str(actor.combat.grip_errors)}))
	await snapshot("idle-aim")
	actor.set_motion(4.2)
	await create_timer(1.8).timeout
	await snapshot("run-aim")
	actor.fire()
	await snapshot("fire")
	await create_timer(0.2).timeout
	actor.reload()
	await create_timer(0.75).timeout
	await snapshot("reload")
	await create_timer(0.9).timeout
	actor.die()
	await create_timer(0.95).timeout
	await snapshot("death")
	world.queue_free()
	await process_frame
	quit()
