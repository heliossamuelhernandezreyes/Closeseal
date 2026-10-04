extends SceneTree
## Saved native lightmaps, matched art views, real collision camera and action continuity.
var arena: Node3D
var directory: String="user://presentation-review"
var checks: Dictionary={}
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func frames(count: int) -> void:
	for tick in count:await physics_frame
func check(id_: String,passed: bool,value: Variant=null) -> void:
	checks[id_]={"ok":passed,"value":value}
	if not passed:failures.append(id_)
func capture(name_: String) -> void:
	RenderingServer.render_loop_enabled=true
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(name_+".png"))
	RenderingServer.render_loop_enabled=false
func fixture(point: Vector3,size_: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.position=point
	var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=size_;body.add_child(shape)
	arena.add_child(body);return body
func run() -> void:
	root.size=Vector2i(1280,720);RenderingServer.render_loop_enabled=false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):directory=argument.trim_prefix("--captures=")
	DirAccess.make_dir_recursive_absolute(directory)
	arena=load("res://src/shooter/shooter_arena.tscn").instantiate();root.add_child(arena)
	await frames(8);arena.begin_slice()
	for enemy in arena.enemies:enemy.set_physics_process(false)
	var lightmaps: Array=arena.world.find_children("*","LightmapGI",true,false)
	check("saved_lightmap_present",lightmaps.size()==1)
	if lightmaps.size()==1:
		var data: LightmapGIData=lightmaps[0].light_data
		check("saved_lightmap_has_textures",data!=null and not data.get("lightmap_textures").is_empty())
		check("saved_lightmap_has_mesh_bindings",data!=null and not data.get("user_data").is_empty())
		check("saved_lightmap_has_actor_probes",data!=null and data.get("probe_data").points.size()>0)
		var missing_bindings: Array[String]=[]
		if data:
			var bindings: Array=data.get("user_data")
			for index in range(0,bindings.size(),4):
				var mesh: MeshInstance3D=lightmaps[0].get_node_or_null(bindings[index])
				if not mesh or not mesh.is_visible_in_tree() or mesh.gi_mode!=GeometryInstance3D.GI_MODE_STATIC:
					missing_bindings.append(str(bindings[index]))
		check("lightmap_bindings_resolve_to_visible_geometry",data!=null and missing_bindings.is_empty(),missing_bindings)
		data=null
	lightmaps.clear()
	check("derived_map_matches_canonical",arena.world.get_meta("canonical_sha256","")==FileAccess.get_sha256("res://maps/nexo_combat_01.json"))
	check("sector_details_preserve_collision",arena.world.get_meta("presentation_details",{}).get("additional_colliders",-1)==0)
	var player: CharacterBody3D=arena.player
	await capture("01-runtime")
	arena.hud.hide()
	var camera:=Camera3D.new();arena.add_child(camera);camera.current=true;camera.fov=58.0
	for view in [["02-courtyard",Vector3(-7,3.3,106),Vector3(0,2.0,77)],
		["03-workshop",Vector3(21,2.7,92),Vector3(29,2.0,74)],
		["04-mezzanine",Vector3(18,4.5,74),Vector3(31,3.5,84)]]:
		camera.position=view[1];camera.look_at(view[2]);await capture(view[0])
	camera.queue_free();player.camera.current=true;arena.hud.show()
	player.position=Vector3(3,0.06,116);player.rotation=Vector3.ZERO;player.rig.rotation=Vector3.ZERO
	player.mobility.reset();player.camera_motion.reset();await frames(15)
	var wall:=fixture(player.position+Vector3(0,2,0.9),Vector3(4,4,0.4));await frames(5)
	check("close_camera_preserves_rig",player.rig.visible)
	check("close_camera_retracts",player.camera_motion.distance<0.8,player.camera_motion.distance)
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=SphereShape3D.new();query.shape.radius=0.10
	query.transform=Transform3D(Basis.IDENTITY,player.camera.global_position);query.collision_mask=1|4;query.exclude=[player.get_rid()]
	check("close_camera_does_not_overlap_wall",player.get_world_3d().direct_space_state.intersect_shape(query).is_empty())
	await capture("05-camera-close")
	var compressed: float=player.camera_motion.distance
	wall.queue_free();await frames(1)
	check("camera_release_is_smoothed",player.camera_motion.distance<3.2 and player.camera_motion.distance>=compressed,player.camera_motion.distance)
	await frames(45)
	check("camera_release_recovers",player.camera_motion.distance>3.35,player.camera_motion.distance)
	var side:=fixture(player.position+Vector3(0.62,2,0),Vector3(0.16,4,7));await frames(6)
	check("sphere_shoulder_clears_side_wall",player.spring_arm.position.x<0.30,player.spring_arm.position.x)
	player.shoulder=-1.0;await frames(20)
	check("shoulder_swap_preserves_rig",player.rig.visible and player.spring_arm.position.x< -0.5)
	side.queue_free();player.shoulder=1.0;await frames(15)
	# Inspect actual animated hip deltas during crouch/stand action changes.
	var hips: int=player.rig.skeleton.find_bone("hips")
	var previous: Vector3=player.rig.skeleton.get_bone_global_pose(hips).origin
	var maximum_jump:=0.0
	player.mobility.stance()
	for tick in 20:
		await frames(1)
		var point: Vector3=player.rig.skeleton.get_bone_global_pose(hips).origin
		maximum_jump=maxf(maximum_jump,point.distance_to(previous));previous=point
	check("action_pose_has_bounded_hip_steps",maximum_jump<0.10,maximum_jump)
	check("pose_offsets_are_bounded",player.rig.transition.maximum_correction<0.30,player.rig.transition.maximum_correction)
	check("weapon_grips_survive_transition",player.rig.combat.grip_errors.x<0.04 and player.rig.combat.grip_errors.y<0.04,player.rig.combat.grip_errors)
	await capture("06-crouch")
	var file:=FileAccess.open(directory.path_join("presentation-acceptance.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":failures.is_empty(),"engine":Engine.get_version_info(),"scope":"saved native scene and controlled runtime; not Android performance","checks":checks,"failures":failures},"  "));file.close()
	print("NEXO_PRESENTATION_ACCEPTANCE ",JSON.stringify({"ok":failures.is_empty(),"checks":checks.size(),"failures":failures}))
	player.end_playtest();OS.delay_msec(250);await create_timer(0.1).timeout
	arena.queue_free();RenderingServer.render_loop_enabled=true
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	await create_timer(0.25).timeout
	quit(0 if failures.is_empty() else 1)
