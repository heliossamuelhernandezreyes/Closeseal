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
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png"))

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="): capture_dir = argument.trim_prefix("--captures=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	arena = load("res://src/shooter/shooter_arena.tscn").instantiate()
	root.add_child(arena)
	await frames(4)
	check("authored_map", arena.visual_stats.asset_instances == 59 and arena.visual_stats.errors.is_empty(), arena.visual_stats)
	check("map_dimensions", arena.contract.bounds.width == 256 and arena.contract.bounds.depth == 256)
	await capture("01-menu")
	arena.begin()
	for enemy in arena.enemies: enemy.set_physics_process(false)
	await frames(6)
	var map: RID = arena.navigation.get_navigation_map()
	var paths: Array = []
	for test in arena.design.navigation_checks:
		var from: Vector3 = arena.vec(test[0])
		var to: Vector3 = arena.vec(test[1])
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		var reaches: bool = path.size() > 1 and path[-1].distance_to(to) < 1.5
		paths.append({"points": path.size(), "reaches": reaches, "end": str(path[-1]) if path.size() else "none"})
	check("three_objectives_navigable", paths.all(func(p): return p.reaches), paths)
	var player: CharacterBody3D = arena.player
	player.position = Vector3(0, 0.1, 97)
	var active_enemy: CharacterBody3D = arena.enemies[2]
	active_enemy.position = Vector3(-3, 0.1, 75)
	active_enemy.home = active_enemy.position
	active_enemy.set_physics_process(true)
	await frames(360)
	check("active_enemy_navigation_and_fire", active_enemy.distance_travelled > 3.0 and active_enemy.shots > 0,
		{"distance_m": active_enemy.distance_travelled, "shots": active_enemy.shots})
	check("active_enemy_can_damage_player", player.health < 100, player.health)
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
	player.look_pitch = atan2(1.1 - 1.65, 12.0)
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
	check("bullets_blocked_by_cover", enemy.health == 90 and player.ammo == 23)
	check("enemy_cannot_see_through_cover", not enemy.line_of_sight())
	wall.queue_free()
	await frames(12)
	check("enemy_line_of_sight", enemy.line_of_sight())
	player.shoot()
	check("body_damage", enemy.health == 56, enemy.health)
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
	await frames(100)
	check("reload_conserves_ammo", player.ammo == 5 and player.reserve == 0)
	var animated: Node3D = arena.enemies[1].rig
	animated.set_motion(0.0)
	await frames(12)
	var bone: int = animated.skeleton.find_bone("LeftLeg")
	animated.set_motion(4.2)
	await frames(15)
	var first: Quaternion = animated.skeleton.get_bone_pose_rotation(bone)
	await frames(15)
	var second: Quaternion = animated.skeleton.get_bone_pose_rotation(bone)
	check("skeletal_run_changes_leg_pose", first.angle_to(second) > 0.15, first.angle_to(second))
	check("weapon_grips_aligned", animated.combat.grip_errors.x < 0.09 and animated.combat.grip_errors.y < 0.09, str(animated.combat.grip_errors))
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
	await capture("06-touch-controls")
	for definition in arena.design.beacons:
		player.position = arena.vec(definition.position) + Vector3.UP * 0.02
		player.velocity = Vector3.ZERO
		arena.interact()
		await frames(185)
	check("three_points_secured", arena.secured.size() == 3, arena.secured)
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
	for speaker in arena.get_children():
		if speaker is AudioStreamPlayer: speaker.stop()
	await create_timer(0.1).timeout
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
