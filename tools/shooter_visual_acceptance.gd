extends SceneTree
## Sample whole modified gait cycles and ray-test every repaired facade module.
var arena: Node3D
var directory := ""
var checks := {}
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(name_: String, passed: bool, details: Variant = null) -> void:
	checks[name_] = {"ok": passed, "details": details}
	if not passed: failures.append(name_)
func capture(name_: String) -> void:
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	RenderingServer.render_loop_enabled = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(name_ + ".png"))
	RenderingServer.render_loop_enabled = false
func run() -> void:
	root.size = Vector2i(1280,720)
	RenderingServer.render_loop_enabled = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): directory = argument.trim_prefix("--captures=")
	if not directory.is_empty(): DirAccess.make_dir_recursive_absolute(directory)
	arena = load("res://src/shooter/shooter_arena.tscn").instantiate()
	root.add_child(arena)
	for tick in range(6): await physics_frame
	arena.begin()
	for enemy in arena.enemies: enemy.set_physics_process(false)
	var player: CharacterBody3D = arena.player
	player.position = Vector3(3,0.04,116)
	for tick in range(8): await physics_frame
	player.set_physics_process(false)
	player.set_process(false)
	var rig: Node3D = player.rig
	rig.set_process(false)
	rig.tree.active = false
	rig.combat.active = false
	rig.ground_contact.active = false
	var skeleton: Skeleton3D = rig.skeleton
	var worst_delta := 0.0
	var minimum_knee_width := INF
	var minimum_foot_width := INF
	var samples := 0
	for clip in ["run", "walk", "cover_idle", "cover_left", "cover_right", "cover_peek_idle", "cover_peek_left", "cover_peek_right"]:
		for sample in range(31):
			skeleton.reset_bone_poses()
			rig.animation.play(clip)
			rig.animation.seek(rig.animation.get_animation(clip).length * sample / 31.0, true)
			var before: Array[Transform3D] = []
			for bone in ["shin.L", "shin.R", "foot.L", "foot.R"]:
				before.append(skeleton.get_bone_global_pose(skeleton.find_bone(bone)))
			rig.ground_contact._process_modification()
			for index in range(4):
				var bone: String = ["shin.L", "shin.R", "foot.L", "foot.R"][index]
				var after := skeleton.get_bone_global_pose(skeleton.find_bone(bone))
				worst_delta = maxf(worst_delta, before[index].origin.distance_to(after.origin))
				worst_delta = maxf(worst_delta, (before[index].basis.x - after.basis.x).length())
			minimum_knee_width = minf(minimum_knee_width, before[0].origin.x - before[1].origin.x)
			minimum_foot_width = minf(minimum_foot_width, before[2].origin.x - before[3].origin.x)
			samples += 1
	check("flat_ground_preserves_entire_animated_pose", worst_delta < 0.0001, {"samples":samples,"maximum_delta":worst_delta})
	check("knees_never_cross_in_sampled_cycles", minimum_knee_width > 0.08, minimum_knee_width)
	check("boots_never_cross_in_sampled_cycles", minimum_foot_width > 0.08, minimum_foot_width)
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.current = true
	camera.fov = 38
	camera.position = player.position + Vector3(2.5,1.55,-3.4)
	camera.look_at(player.position + Vector3.UP * 0.85)
	rig.combat.active = true
	for clip in ["run", "cover_idle", "cover_peek_idle"]:
		rig.stance_weight = 1.0 if clip == "cover_idle" else 0.443 if clip == "cover_peek_idle" else 0.0
		rig.action_pose = clip if clip != "run" else ""
		rig.weapon.position = Vector3(0.14,1.42-rig.stance_weight*0.52+(0.17 if clip == "cover_peek_idle" else 0.0),-0.42)
		rig.animation.play(clip)
		rig.animation.seek(0.2,true)
		rig.animation.pause()
		await capture("pose-"+clip)
	arena.hud.visible = false
	var facade: Node3D = load("res://assets/shooter/serious/factory_building_fixed.glb").instantiate()
	root.add_child(facade)
	facade.position = Vector3(0,0,180)
	for node in facade.find_children("*","MeshInstance3D",true,false): node.create_trimesh_collision()
	for tick in range(4): await physics_frame
	var misses := []
	var rays := 0
	for definition in [["north",Vector3.FORWARD,8],["south",Vector3.BACK,8],["east",Vector3.RIGHT,6],["west",Vector3.LEFT,6]]:
		var normal: Vector3 = definition[1]
		var columns: int = definition[2]
		var width := 24.0 if columns == 8 else 18.0
		var distance := 9.0 if columns == 8 else 12.0
		var tangent := Vector3.RIGHT if columns == 8 else Vector3.BACK
		for row in range(3):
			for col in range(columns):
				var point: Vector3 = facade.position + normal * distance + tangent * (-width/2+1.5+col*3) + Vector3.UP * (1.5+row*3)
				var query := PhysicsRayQueryParameters3D.create(point+normal*2,point-normal*0.6,1)
				var hit := facade.get_world_3d().direct_space_state.intersect_ray(query)
				if hit.is_empty() or not facade.is_ancestor_of(hit.collider): misses.append([definition[0],row,col])
				rays += 1
		camera.position = facade.position + normal * 30 + Vector3.UP * 8 + tangent * 6
		camera.look_at(facade.position + Vector3.UP * 4)
		camera.fov = 55
		await capture("facade-"+definition[0])
	check("every_facade_module_has_real_geometry", misses.is_empty(), {"rays":rays,"misses":misses})
	var report := {"ok":failures.is_empty(),"checks":checks,"failures":failures,"engine":Engine.get_version_info()}
	var path := directory.path_join("visual-acceptance.json") if not directory.is_empty() else "user://visual-acceptance.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("VISUAL_ACCEPTANCE_RESULT "+JSON.stringify(report))
	player.end_playtest()
	facade.queue_free()
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
