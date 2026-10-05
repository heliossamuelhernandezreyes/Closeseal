extends SceneTree
## Check the rendered player camera, including silhouette pixels without cast shadows.
var arena: Node3D
var directory := "user://camera-review"
var checks := {}
var failures: Array[String] = []
func _initialize() -> void:call_deferred("run")
func frames(count: int) -> void:
	for tick in count:await physics_frame
func check(id: String, passed: bool, detail: Variant = null) -> void:
	checks[id] = {"ok":passed,"detail":detail}
	if not passed:failures.append(id)
func image_frame() -> Image:
	# Drain pending visibility/shadow changes before comparing readback pixels.
	for frame in 3:await process_frame;await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func screen_bounds(node: Node3D) -> Rect2i:
	var camera: Camera3D = arena.player.camera
	var low := Vector2(INF,INF);var high := Vector2(-INF,-INF)
	var meshes: Array = node.find_children("*","MeshInstance3D",true,false)
	if node is MeshInstance3D:meshes.append(node)
	for mesh in meshes:
		for corner in 8:
			var point: Vector3 = mesh.to_global(mesh.get_aabb().get_endpoint(corner))
			if camera.is_position_behind(point):continue
			var pixel := camera.unproject_position(point)
			low=low.min(pixel);high=high.max(pixel)
	if not low.is_finite():return Rect2i()
	return Rect2i(Rect2(low,high-low).grow(2).intersection(Rect2(Vector2.ZERO,Vector2(root.size))))
func changed_pixels(a: Image, b: Image, region: Rect2i) -> int:
	var count := 0
	for y in range(region.position.y,region.end.y,2):
		for x in range(region.position.x,region.end.x,2):
			var p := a.get_pixel(x,y);var q := b.get_pixel(x,y)
			if maxf(absf(p.r-q.r),maxf(absf(p.g-q.g),absf(p.b-q.b))) > 0.025:count += 1
	return count*4
func inspect_view(id: String, pixels := false) -> void:
	var player: CharacterBody3D = arena.player
	var image := await image_frame()
	var actual: float = (player.camera.global_position-player.spring_arm.global_position).dot(player.spring_arm.global_basis.z)
	var allowed: float = player.spring_arm.get_hit_length()
	check(id+"_rendered_distance",absf(actual-player.camera_motion.distance)<0.001,{"actual":actual,"smooth":player.camera_motion.distance,"allowed":allowed})
	check(id+"_swept_segment",actual>=0.0 and actual<=allowed+0.001)
	check(id+"_player_camera_current",player.camera.is_current())
	image.save_png(directory.path_join(id+".png"))
	if not pixels:return
	# Freeze pose/camera and disable shadows so a moving shadow cannot pass visibility.
	player.set_process(false);player.set_physics_process(false)
	player.spring_arm.set_physics_process_internal(false)
	var rig: Node3D = player.rig
	rig.set_process(false)
	var tree_idle: bool = rig.tree.is_processing_internal()
	var tree_physics: bool = rig.tree.is_physics_processing_internal()
	rig.tree.set_process_internal(false);rig.tree.set_physics_process_internal(false)
	var meshes: Array = rig.find_children("*","MeshInstance3D",true,false)
	for mesh in meshes:mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var both := await image_frame()
	var camera_point: Vector3 = player.camera.global_position
	var model: Node3D = rig.get_node("Model")
	var body_region := screen_bounds(model)
	var weapon_region := screen_bounds(rig.weapon)
	model.hide();var no_body := await image_frame();model.show()
	rig.weapon.hide();var no_weapon := await image_frame();rig.weapon.show()
	check(id+"_pixel_camera_stable",camera_point.distance_to(player.camera.global_position)<0.001 and player.camera.is_current())
	if id=="01-spawn":
		both.save_png(directory.path_join("mask-visible.png"))
		no_body.save_png(directory.path_join("mask-without-body.png"))
		no_weapon.save_png(directory.path_join("mask-without-weapon.png"))
	var body_count := changed_pixels(both,no_body,body_region)
	var weapon_count := changed_pixels(both,no_weapon,weapon_region)
	check(id+"_body_pixels",body_count>500,body_count)
	# A swapped shoulder may put the rifle behind the torso. The normal/ADS views
	# must show the rifle; the opposite shoulder still records its pixel count.
	check(id+"_weapon_pixels",weapon_count>20 if id!="03-left" else rig.weapon.visible,weapon_count)
	player.set_process(true);player.set_physics_process(true);rig.set_process(true)
	rig.tree.set_process_internal(tree_idle);rig.tree.set_physics_process_internal(tree_physics)
	player.spring_arm.set_physics_process_internal(true)
func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):directory=argument.trim_prefix("--captures=")
	DirAccess.make_dir_recursive_absolute(directory);root.size=Vector2i(1280,720)
	arena=load("res://src/shooter/shooter_arena.tscn").instantiate();root.add_child(arena)
	await frames(8);arena.begin_slice();arena.hud.hide()
	for enemy in arena.enemies:
		enemy.set_physics_process(false);enemy.rig.set_process(false);enemy.rig.tree.active=false
		enemy.rig.transition.active=false;enemy.rig.combat.active=false;enemy.rig.ground_contact.active=false
	var player: CharacterBody3D=arena.player
	await frames(40);await inspect_view("01-spawn",true)
	check("spawn_is_third_person",player.camera.position.z>3.2,player.camera.position.z)
	check("spawn_marker_does_not_cover_body",not arena.extraction_marker.visible)
	player.position=Vector3(3,0.04,116);player.rotation=Vector3.ZERO;player.look_pitch=-0.12
	player.camera_motion.reset();await frames(40)
	player.aim_held=true;await frames(35);await inspect_view("02-aim",true)
	check("aim_stays_third_person",player.camera.position.z>2.15)
	player.aim_held=false;player.shoulder=-1;await frames(40);await inspect_view("03-left",true)
	player.shoulder=1;player.mobility.stance();await frames(35);await inspect_view("04-crouch",true)
	player.start_reload();await frames(12);await inspect_view("05-reload")
	player.mobility.stance();await frames(40)
	var wall:=StaticBody3D.new();wall.position=player.position+Vector3(0,2,0.9)
	var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(4,4,0.4)
	wall.add_child(shape);arena.add_child(wall);await frames(8);await inspect_view("06-wall")
	check("wall_retracts_actual_camera",player.camera.position.z<0.8)
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=SphereShape3D.new();query.shape.radius=0.1
	query.transform=Transform3D(Basis.IDENTITY,player.camera.global_position);query.collision_mask=1|4;query.exclude=[player.get_rid()]
	check("wall_has_no_camera_overlap",player.get_world_3d().direct_space_state.intersect_shape(query).is_empty())
	var compressed: float = player.camera_motion.distance
	wall.queue_free();await image_frame();await frames(2)
	# Use one controlled 60 Hz update: pixel readback can span several wall frames.
	player.camera_motion.distance=compressed;player.camera_motion.render_tick(1.0/60.0)
	check("release_is_damped",player.camera.position.z>compressed and player.camera.position.z<3.2,{"compressed":compressed,"allowed":player.spring_arm.get_hit_length(),"controlled":player.camera.position.z})
	await inspect_view("07-release")
	await frames(45);await inspect_view("08-recovered",true)
	check("recovered_actual_camera",player.camera.position.z>3.35)
	var report:={"ok":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Linux player-camera renders and actual transforms; no Android camera or FPS claim"}
	var file:=FileAccess.open(directory.path_join("camera-acceptance.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("CAMERA_ACCEPTANCE ",JSON.stringify(report))
	player.end_playtest();arena.queue_free()
	for frame in 8:await process_frame;await RenderingServer.frame_post_draw
	await create_timer(0.25).timeout;quit(0 if failures.is_empty() else 1)
