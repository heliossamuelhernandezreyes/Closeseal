extends SceneTree
var failures: Array[String] = []
var checks: Dictionary = {}
var arena: Node3D
var capture_dir := ""

func _initialize() -> void: call_deferred("run")
func check(name: String, passed: bool, details: Variant = null) -> void:
	checks[name] = {"ok": passed, "details": details}
	if not passed: failures.append(name)
func frames(count: int) -> void:
	for i in range(count): await physics_frame
func capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	RenderingServer.render_loop_enabled = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png"))
	RenderingServer.render_loop_enabled = false

func run() -> void:
	root.size = Vector2i(1280, 720)
	# Replay physics normally; render the evidence checkpoints. This is acceptance,
	# not a renderer/device throughput benchmark, especially on software GL.
	RenderingServer.render_loop_enabled = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): capture_dir = argument.trim_prefix("--captures=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	arena = load("res://src/shooter/shooter_arena.tscn").instantiate()
	root.add_child(arena)
	await frames(4)
	check("authored_map", arena.visual_stats.asset_instances == arena.contract.authoring.instances.size() and arena.visual_stats.asset_instances >= 78 and arena.visual_stats.errors.is_empty(), arena.visual_stats)
	check("map_dimensions", arena.contract.bounds.width == 256 and arena.contract.bounds.depth == 256)
	var facade: Node3D = load("res://assets/shooter/serious/factory_building.glb").instantiate()
	var sampled_mips := false
	for node in facade.find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			var material: Material = node.mesh.surface_get_material(surface)
			if material is BaseMaterial3D and material.albedo_texture:
				sampled_mips = material.albedo_texture.get_image().has_mipmaps()
				break
		if sampled_mips: break
	check("facade_texture_has_mipmaps", sampled_mips)
	facade.free()
	await capture("01-menu")
	arena.begin()
	for enemy in arena.enemies: enemy.set_physics_process(false)
	await frames(6)
	var map: RID = arena.navigation.get_navigation_map()
	var spawn_checks: Array = []
	for index in range(arena.design.enemy_spawns.size()):
		var spawn: Vector3 = arena.vec(arena.design.enemy_spawns[index])
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.36
		capsule.height = 1.85
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, spawn + Vector3.UP * 0.985)
		query.collision_mask = 1
		var overlaps := arena.get_world_3d().direct_space_state.intersect_shape(query)
		var nearest := NavigationServer3D.map_get_closest_point(map, spawn)
		var route := NavigationServer3D.map_get_path(map, arena.vec(arena.design.player_spawn), spawn, true)
		var reachable: bool = route.size() > 1 and route[-1].distance_to(spawn) < 0.8
		var blockers: Array = []
		for overlap in overlaps: blockers.append(str(overlap.collider.name))
		spawn_checks.append({"index": index, "position": str(spawn), "blockers": blockers,
			"navigation_distance": nearest.distance_to(spawn), "reachable": reachable,
			"ok": overlaps.is_empty() and nearest.distance_to(spawn) < 0.8 and reachable})
	check("all_enemy_spawns_clear_and_navigable", spawn_checks.all(func(s): return s.ok), spawn_checks)
	var paths: Array = []
	for test in arena.design.navigation_checks:
		var from: Vector3 = arena.vec(test[0])
		var to: Vector3 = arena.vec(test[1])
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		var reaches: bool = path.size() > 1 and path[-1].distance_to(to) < 1.5
		paths.append({"points": path.size(), "reaches": reaches, "end": str(path[-1]) if path.size() else "none"})
	check("three_objectives_navigable", paths.all(func(p): return p.reaches), paths)
	var player: CharacterBody3D = arena.player
	check("third_person_full_body", player.rig.skeleton.get_bone_count() > 40 and player.camera.get_parent() is SpringArm3D and player.camera.global_position.distance_to(player.global_position) > 3.0)
	var body_yaw: float = player.rig.global_rotation.y
	player.look(Vector2(120, 0))
	check("free_orbit_preserves_body_heading", absf(angle_difference(body_yaw, player.rig.global_rotation.y)) < 0.001)
	player.rotation.y = 0
	player.rig.rotation.y = 0
	var camera_wall := StaticBody3D.new()
	var camera_shape := CollisionShape3D.new()
	var rear_box := BoxShape3D.new()
	rear_box.size = Vector3(4, 4, 0.4)
	camera_shape.shape = rear_box
	camera_wall.add_child(camera_shape)
	arena.add_child(camera_wall)
	camera_wall.position = player.global_position + Vector3(0, 2, 2)
	await frames(5)
	check("camera_retracts_before_wall", player.spring_arm.get_hit_length() < 1.9 and player.spring_arm.get_hit_length() > 0.5, player.spring_arm.get_hit_length())
	camera_wall.queue_free()
	await frames(5)
	check("camera_recovers_distance", player.spring_arm.get_hit_length() > 3.4, player.spring_arm.get_hit_length())
	var side_wall := StaticBody3D.new()
	var side_shape := CollisionShape3D.new()
	var side_box := BoxShape3D.new()
	side_box.size = Vector3(0.2, 4, 9)
	side_shape.shape = side_box
	side_wall.add_child(side_shape)
	arena.add_child(side_wall)
	side_wall.position = player.global_position + Vector3(0.60, 2, 1)
	await frames(3)
	check("camera_shoulder_clears_side_wall", player.spring_arm.position.x <= 0.27, player.spring_arm.position.x)
	side_wall.queue_free()
	await frames(18)
	player.shoulder = -1.0
	await frames(18)
	check("left_shoulder_available", player.spring_arm.position.x < -0.5, player.spring_arm.position.x)
	player.shoulder = 1.0
	await frames(18)
	player.position = Vector3(0, 0.1, 97)
	var active_enemy: CharacterBody3D = arena.enemies[2]
	active_enemy.position = Vector3(-3, 0.1, 75)
	active_enemy.home = active_enemy.position
	active_enemy.set_physics_process(true)
	await frames(360)
	check("active_enemy_navigation_and_fire", active_enemy.distance_travelled > 3.0 and active_enemy.shots > 0,
		{"distance_m": active_enemy.distance_travelled, "shots": active_enemy.shots})
	check("active_enemy_can_damage_player", player.health < 100, player.health)
	var remembered: Vector3 = active_enemy.last_seen
	player.position = Vector3(112, 0.1, -112)
	await frames(5)
	check("enemy_searches_last_seen", active_enemy.state == "search" and active_enemy.last_seen.distance_to(remembered) < 0.01)
	player.position = Vector3(0, 0.1, 97)
	active_enemy.position = Vector3(-10, 0.1, 85)
	active_enemy.velocity = Vector3.ZERO
	await frames(3)
	active_enemy.take_damage(34)
	var cover_path := NavigationServer3D.map_get_path(map, active_enemy.global_position, active_enemy.cover_target, true)
	check("injured_enemy_seeks_navigable_cover", active_enemy.state == "cover" and active_enemy.cover_time > 0 and cover_path.size() > 1,
		{"target": str(active_enemy.cover_target), "path_points": cover_path.size()})
	active_enemy.set_physics_process(false)
	player.health = 100
	active_enemy.position = Vector3(8, 0.1, 18)
	player.position = Vector3(0, 0.1, -19)
	player.rotation.y = 0
	player.touch_move = Vector2(0, -1)
	await frames(270)
	player.touch_move = Vector2.ZERO
	check("physical_ramp_ascent", player.position.y > 3.8 and player.position.z < -35, str(player.position))
	await capture("02-command-post")
	player.position = Vector3(125, 0.1, 20)
	player.touch_move = Vector2.RIGHT
	await frames(90)
	player.touch_move = Vector2.ZERO
	check("boundary_collision", player.position.x < 127.3 and player.position.x > 126, str(player.position))
	player.position = Vector3(0, 0.1, 97)
	await frames(20)
	player.jump_requested = true
	await frames(18)
	check("player_jump", player.position.y > 0.9, player.position.y)
	await frames(50)
	var enemy: CharacterBody3D = arena.enemies[0]
	enemy.position = Vector3(0, 0.02, 85)
	enemy.rig.rotation.y = PI
	player.rotation.y = 0
	player.look_pitch = 0.0
	await frames(3)
	player.camera.look_at(enemy.global_position + Vector3.UP * 1.1)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 1)
	collision.shape = box
	wall.add_child(collision)
	arena.add_child(wall)
	wall.position = Vector3(0, 1.5, 92)
	await frames(3)
	player.shoot()
	check("bullets_blocked_by_cover", enemy.health == 90 and player.ammo == 29)
	check("enemy_cannot_see_through_cover", not enemy.line_of_sight())
	wall.queue_free()
	await frames(12)
	check("enemy_line_of_sight", enemy.line_of_sight())
	var close_cover := StaticBody3D.new()
	var close_shape := CollisionShape3D.new()
	var close_box := BoxShape3D.new()
	close_box.size = Vector3(3, 1.65, 0.15)
	close_shape.shape = close_box
	close_cover.add_child(close_shape)
	arena.add_child(close_cover)
	close_cover.position = player.global_position + Vector3(0, 0.825, -0.70)
	# Camera sees over this cover while the physical barrel intersects it.
	player.camera.position.y = 1.0
	player.camera.look_at(enemy.global_position + Vector3.UP * 1.1)
	await frames(4)
	player.shoot()
	check("barrel_cannot_shoot_through_near_cover", enemy.health == 90 and player.last_hit.get("collider") == close_cover,
		{"enemy_health": enemy.health, "hit_cover": player.last_hit.get("collider") == close_cover})
	close_cover.queue_free()
	player.camera.position.y = 0.0
	await frames(8)
	player.camera.look_at(enemy.global_position + Vector3.UP * 1.1)
	player.shoot()
	check("body_damage", enemy.health == 56, enemy.health)
	var shot_direction: Vector3 = (player.aim_point() - player.muzzle.global_position).normalized()
	check("visible_weapon_matches_reticle", (-player.muzzle.global_basis.z).dot(shot_direction) > 0.995)
	await capture("03-combat")
	await frames(10)
	player.shoot()
	await frames(10)
	player.shoot()
	check("enemy_death", enemy.dead and enemy.collision_layer == 0 and arena.kills == 1)
	await frames(60)
	await capture("04-death")
	player.ammo = 0
	player.reserve = 5
	player.start_reload()
	player.shoot()
	check("reload_prevents_shots", player.ammo == 0 and player.reload_remaining > 0)
	await frames(130)
	check("reload_conserves_ammo", player.ammo == 5 and player.reserve == 0)
	var animated: Node3D = arena.enemies[1].rig
	animated.set_motion(0.0)
	await frames(12)
	var bone: int = animated.skeleton.find_bone("shin.L")
	animated.set_motion(4.2)
	var previous_callback: int = animated.tree.callback_mode_process
	animated.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animated.motion_blend = 4.2
	animated.tree.set("parameters/Gait/blend_position", Vector2(0, -2))
	animated.tree.set("parameters/Cadence/scale", 1.0)
	animated.tree.advance(0.0)
	var first: Quaternion = animated.skeleton.get_bone_pose_rotation(bone)
	var maximum_angle := 0.0
	# Sample a complete 0.64-second gait in fixed animation steps. Two wall-clock
	# samples can hit equal phases, especially under a slow software renderer.
	for sample in range(16):
		animated.tree.advance(0.04)
		await process_frame
		var pose: Quaternion = animated.skeleton.get_bone_pose_rotation(bone)
		maximum_angle = maxf(maximum_angle, first.angle_to(pose))
	animated.tree.callback_mode_process = previous_callback
	check("skeletal_run_changes_leg_pose", maximum_angle > 0.15, {"maximum_angle_rad": maximum_angle, "samples": 16, "cycle_seconds": 0.64})
	check("weapon_grips_aligned", animated.combat.grip_errors.x < 0.09 and animated.combat.grip_errors.y < 0.09, str(animated.combat.grip_errors))
	check("third_person_weapon_grips", player.rig.combat.grip_errors.x < 0.09 and player.rig.combat.grip_errors.y < 0.09, str(player.rig.combat.grip_errors))
	check("military_assets", arena.contract.shooter_design.art_revision == "industrial-slice-05" and player.gun.find_child("Magazine", true, false) != null)
	animated.reload()
	await frames(45)
	check("magazine_removal", animated.magazine.position.distance_to(animated.magazine_rest.origin) > 0.15)
	animated.fire()
	check("fire_recoil_animation", animated.recoil > 0)
	animated.reload()
	check("reload_animation", animated.reload_time > 0)
	player.fire_held = true
	player.touch_move = Vector2.ONE
	player.clear_input()
	check("input_release", not player.fire_held and player.touch_move == Vector2.ZERO)
	arena.hud.mobile = true
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(140, 575)
	touch.pressed = true
	Input.parse_input_event(touch)
	await process_frame
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(140, 500)
	drag.relative = Vector2(0, -75)
	Input.parse_input_event(drag)
	await process_frame
	check("touch_movement", player.touch_move.y < -0.9)
	var release: InputEventScreenTouch = touch.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	check("touch_release", player.touch_move == Vector2.ZERO and arena.hud.stick_index == -1)
	var yaw := player.rotation.y
	for definition in [[0, Vector2(140, 575)], [1, Vector2(790, 430)],
		[2, arena.hud.button_rect("fire").get_center()], [3, arena.hud.button_rect("aim").get_center()]]:
		var finger := InputEventScreenTouch.new()
		finger.index = definition[0]
		finger.position = definition[1]
		finger.pressed = true
		Input.parse_input_event(finger)
		await process_frame
	for definition in [[0, Vector2(140, 500), Vector2(0, -75)], [1, Vector2(830, 412), Vector2(40, -18)]]:
		var motion := InputEventScreenDrag.new()
		motion.index = definition[0]
		motion.position = definition[1]
		motion.relative = definition[2]
		Input.parse_input_event(motion)
		await process_frame
	check("four_finger_controls", player.fire_held and player.aim_held and player.touch_move.y < -0.9 and absf(player.rotation.y - yaw) > 0.05)
	for index in range(4):
		var finger := InputEventScreenTouch.new()
		finger.index = index
		finger.pressed = false
		Input.parse_input_event(finger)
		await process_frame
	check("four_finger_release", not player.fire_held and not player.aim_held and player.touch_move == Vector2.ZERO)
	player.rotation.y = 0
	player.look_pitch = 0
	player.camera.rotation = Vector3.ZERO
	await capture("06-touch-controls")
	var capture_checks: Array = []
	for definition in arena.design.beacons:
		player.position = arena.vec(definition.position) + Vector3.UP * 0.02
		player.velocity = Vector3.ZERO
		arena.interact()
		var began: String = arena.capture_id
		# Allow the render-driven three-second capture clock to complete.
		for tick in range(240):
			await physics_frame
			if definition.id in arena.secured: break
		capture_checks.append({"id": definition.id, "began": began, "position": str(player.position), "timer": arena.capture_time})
	check("three_points_secured", arena.secured.size() == 3, {"secured": arena.secured, "captures": capture_checks})
	player.position = arena.vec(arena.design.extraction)
	arena.interact()
	check("mission_victory", not arena.playing and arena.outcome == "OPERACIÓN COMPLETADA")
	await capture("05-victory")
	arena.outcome = ""
	arena.playing = true
	player.take_damage(100)
	check("mission_defeat", not arena.playing and arena.outcome == "OPERACIÓN INTERRUMPIDA")
	var report := {"ok": failures.is_empty(), "engine": Engine.get_version_info(), "checks": checks, "failures": failures}
	var report_path := capture_dir.path_join("acceptance.json") if not capture_dir.is_empty() else "user://shooter-acceptance.json"
	var output := FileAccess.open(report_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("SHOOTER_ACCEPTANCE_RESULT " + JSON.stringify(report))
	arena.effects.stop_audio()
	for speaker in arena.get_children():
		if speaker is AudioStreamPlayer or speaker is AudioStreamPlayer3D:
			speaker.stop()
			speaker.stream = null
	# The audio mixer uses real time even when the simulation uses --fixed-fps.
	OS.delay_msec(250)
	await create_timer(0.1).timeout
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
