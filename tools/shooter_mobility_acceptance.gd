extends SceneTree
## Real production controller, swept collisions, input events and rendered evidence.
var arena: Node3D
var player: CharacterBody3D
var checks := {}
var failures: Array[String] = []
var directory := ""
func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for tick in range(count): await physics_frame
func check(name: String, passed: bool, details: Variant = null) -> void:
	checks[name] = {"ok": passed, "details": details}
	if not passed: failures.append(name)
func action(name: String) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = name
	event.pressed = false
	Input.parse_input_event(event)
func reset_at(point: Vector3) -> void:
	player.clear_input()
	player.mobility.reset()
	player.position = point
	player.rotation = Vector3.ZERO
	player.rig.rotation = Vector3.ZERO
	player.look_pitch = -0.12
	player.camera.rotation = Vector3.ZERO
	await frames(8)
func box(point: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var mesh := MeshInstance3D.new()
	var collider := BoxShape3D.new()
	var visual := BoxMesh.new()
	collider.size = dimensions
	visual.size = dimensions
	shape.shape = collider
	mesh.mesh = visual
	mesh.material_override = load("res://assets/shooter/serious/materials/oxide.tres")
	body.add_child(shape)
	body.add_child(mesh)
	arena.add_child(body)
	body.position = point
	return body
func capture(name_: String) -> void:
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	RenderingServer.render_loop_enabled = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(name_ + ".png"))
	RenderingServer.render_loop_enabled = false
func run() -> void:
	root.size = Vector2i(1280, 720)
	RenderingServer.render_loop_enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): directory = arg.trim_prefix("--captures=")
	if not directory.is_empty(): DirAccess.make_dir_recursive_absolute(directory)
	arena = load("res://src/shooter/shooter_arena.tscn").instantiate()
	root.add_child(arena)
	await frames(5)
	arena.begin()
	for enemy in arena.enemies: enemy.set_physics_process(false)
	player = arena.player
	await reset_at(Vector3(3, 0.04, 116))
	player.touch_move = Vector2(0, -1)
	await frames(15)
	check("fast_ground_acceleration", -player.velocity.z > 5.25, player.velocity.z)
	player.touch_sprint = true
	await frames(15)
	check("sprint_speed", -player.velocity.z > 8.6, player.velocity.z)
	var start := player.position
	await action("stance")
	await frames(7)
	check("sprint_input_enters_slide", player.mobility.state == "slide" and player.mobility.capsule_height < 0.9)
	var ammo_before: int = player.ammo
	player.shoot()
	check("slide_blocks_weapon", player.ammo == ammo_before)
	await frames(34)
	check("slide_finishes_without_sticking", player.mobility.state == "free" and player.position.distance_to(start) > 3.0, player.position.distance_to(start))
	player.clear_input()
	await frames(12)
	check("responsive_braking", Vector2(player.velocity.x, player.velocity.z).length() < 0.05)
	await reset_at(Vector3(3, 0.04, 116))
	player.touch_move = Vector2(1, -1)
	player.touch_sprint = true
	await frames(20)
	check("diagonal_speed_is_normalized", Vector2(player.velocity.x, player.velocity.z).length() <= 8.81)
	await reset_at(Vector3(3, 0.04, 116))
	await action("stance")
	await frames(8)
	check("crouch_changes_actual_capsule", player.mobility.capsule_height < 1.1 and player.body_shape.shape.height < 1.1)
	var ceiling := box(player.position + Vector3(0, 1.40, 0), Vector3(3, 0.20, 3))
	await frames(3)
	await action("stance")
	await frames(5)
	check("ceiling_prevents_standing", player.mobility.capsule_height < 1.1)
	ceiling.queue_free()
	await frames(8)
	check("stands_when_ceiling_clears", player.mobility.capsule_height > 1.8)
	var low := box(Vector3(3, 0.57, 109), Vector3(5, 1.14, 0.56))
	await reset_at(Vector3(3, 0.04, 109.95))
	await action("cover")
	await frames(20)
	check("cover_input_snaps_and_crouches", player.mobility.state == "cover" and player.mobility.cover_low and player.mobility.capsule_height < 1.1,
		{"state": player.mobility.state, "height": player.mobility.capsule_height, "position": str(player.position)})
	var observer: CharacterBody3D = arena.enemies[-1]
	observer.position = Vector3(3, 0.03, 105)
	await frames(3)
	check("low_cover_physically_hides_player", not observer.line_of_sight())
	player.camera.look_at(observer.global_position + Vector3.UP)
	player.shoot()
	check("covered_muzzle_cannot_hit_through_wall", observer.health == 90 and player.last_hit.get("collider") == low)
	player.aim_held = true
	await frames(15)
	check("aim_peek_keeps_bent_stance", player.mobility.peek and player.mobility.capsule_height > 1.4 and player.mobility.capsule_height < 1.6 and player.rig.action_pose == "cover_peek_idle", {"peek": player.mobility.peek, "height": player.mobility.capsule_height})
	check("low_peek_exposes_actual_target", observer.line_of_sight())
	player.camera.look_at(observer.global_position + Vector3.UP * 1.4)
	player.fire_held = true
	player.touch_move = Vector2.RIGHT
	var fire_start := player.position
	var fire_ammo: int = player.ammo
	await frames(20)
	check("low_cover_fire_preserves_lateral_movement", player.mobility.state == "cover" and player.position.x > fire_start.x + 0.55 and player.ammo < fire_ammo and player.rig.action_pose == "cover_peek_right" and player.mobility.capsule_height < 1.6,
		{"position": str(player.position), "height": player.mobility.capsule_height, "pose": player.rig.action_pose, "ammo": player.ammo})
	check("peek_weapon_clears_cover", player.muzzle.global_position.y > 1.22, player.muzzle.global_position.y)
	await capture("12-low-cover-moving-fire")
	player.fire_held = false
	player.touch_move = Vector2.ZERO
	await reset_at(Vector3(3, 0.04, 109.95))
	player.mobility.toggle_cover()
	await frames(20)
	player.aim_held = false
	await frames(12)
	var side_start: float = player.position.x
	player.touch_move = Vector2.RIGHT
	await frames(20)
	player.touch_move = Vector2.ZERO
	check("cover_strafe_preserves_face", player.mobility.state == "cover" and player.position.x > side_start + 0.7 and absf(player.position.z - 109.71) < 0.15, str(player.position))
	player.touch_move = Vector2.DOWN
	await frames(5)
	check("outward_movement_releases_cover", player.mobility.state == "free")
	await reset_at(Vector3(3, 0.04, 109.95))
	await action("cover")
	await frames(10)
	low.queue_free()
	await frames(5)
	check("removed_cover_releases_player", player.mobility.state == "free")
	var high := box(Vector3(3, 1.2, 109), Vector3(5, 2.4, 0.56))
	await reset_at(Vector3(3, 0.04, 109.95))
	await action("cover")
	await frames(12)
	player.aim_held = true
	await frames(8)
	check("high_cover_requires_edge_for_peek", player.mobility.state == "cover" and not player.mobility.cover_low and not player.mobility.peek)
	check("high_obstacle_rejects_vault", not player.mobility.try_vault())
	await reset_at(Vector3(5.15, 0.04, 109.95))
	await action("cover")
	player.aim_held = true
	observer.position = Vector3(8, 0.03, 105)
	await frames(15)
	check("high_cover_edge_peek_moves_real_capsule", player.mobility.state == "cover" and player.mobility.peek and player.mobility.peek_offset.length() > 0.5 and observer.line_of_sight(), {"offset": str(player.mobility.peek_offset), "state": player.mobility.state})
	player.aim_held = false
	await frames(12)
	check("edge_peek_returns_to_cover", player.mobility.peek_offset.length() < 0.05 and not player.mobility.peek)
	player.aim_held = false
	high.queue_free()
	await frames(5)
	low = box(Vector3(3, 0.57, 109), Vector3(5, 1.14, 0.56))
	await reset_at(Vector3(3, 0.04, 109.95))
	var overhang := box(Vector3(3, 1.90, 109), Vector3(4, 0.2, 3.5))
	await frames(4)
	check("vault_rejects_low_ceiling", not player.mobility.try_vault())
	overhang.queue_free()
	var landing_blocker := box(Vector3(3, 1, 107.9), Vector3(4, 2, 1.7))
	await frames(5)
	check("vault_rejects_blocked_landing", not player.mobility.try_vault())
	landing_blocker.queue_free()
	await frames(5)
	player.touch_move = Vector2(0,-1)
	var automatic_before: int = player.mobility.automatic_vaults
	await frames(12)
	check("movement_auto_vaults_without_jump_input", player.mobility.state == "vault" and player.mobility.automatic_vaults == automatic_before + 1, {"position": str(player.position), "reason": player.mobility.vault_reason})
	player.clear_input()
	await frames(40)
	check("automatic_vault_lands_with_collision", player.mobility.state == "free" and not player.mobility.vault_aborted and player.position.z < 108.4 and player.is_on_floor())
	await reset_at(Vector3(3, 0.04, 109.95))
	landing_blocker = box(Vector3(3, 1, 107.9), Vector3(4, 2, 1.7))
	await frames(3)
	player.touch_move = Vector2(0,-1)
	await frames(25)
	check("auto_vault_rejects_blocked_landing", player.mobility.state == "free" and player.position.z > 109.28 and player.mobility.automatic_vaults == automatic_before + 1)
	player.clear_input()
	landing_blocker.queue_free()
	await reset_at(Vector3(3, 0.04, 109.95))
	player.aim_held = true
	player.touch_move = Vector2(0,-1)
	await frames(20)
	check("aiming_does_not_auto_vault", player.mobility.state == "free" and player.mobility.automatic_vaults == automatic_before + 1)
	await reset_at(Vector3(3, 0.04, 109.95))
	await action("jump")
	await frames(10)
	check("jump_input_starts_swept_vault", player.mobility.state == "vault" and player.position.y > 0.8, {"position": str(player.position), "state": player.mobility.state, "reason": player.mobility.vault_reason})
	var vault_ammo: int = player.ammo
	player.shoot()
	check("vault_disables_fire", player.ammo == vault_ammo)
	await frames(38)
	check("vault_crosses_and_lands", player.mobility.state == "free" and not player.mobility.vault_aborted and player.position.z < 108.4 and player.position.y < 0.1 and player.is_on_floor(), str(player.position))
	await reset_at(Vector3(3, 0.04, 109.95))
	check("vault_accepted_before_dynamic_blocker", player.mobility.try_vault(), player.mobility.vault_reason)
	var late_blocker := box(Vector3(3, 2.0, 109), Vector3(3, 1, 1))
	await frames(40)
	check("dynamic_blocker_aborts_without_warp", player.mobility.vault_aborted and player.position.z > 109.28, str(player.position))
	late_blocker.queue_free()
	low.queue_free()
	await reset_at(Vector3(3, 0.04, 116))
	await action("jump")
	await frames(12)
	check("clear_ground_still_jumps", player.position.y > 0.8 and player.rig.action_pose == "jump")
	await frames(55)
	check("jump_lands_without_state_lock", player.is_on_floor() and player.mobility.state == "free")
	await reset_at(Vector3(3, 0.04, 116))
	await action("jump")
	var buffered_in_air := false
	for tick in range(60):
		await physics_frame
		if not player.is_on_floor() and player.velocity.y < -3 and player.position.y < 0.3:
			buffered_in_air = true
			player.jump_requested = true
			break
	await frames(10)
	check("jump_buffer_relaunches_on_landing", buffered_in_air and player.velocity.y > 0 and player.position.y > 0.2, {"height": player.position.y, "velocity": player.velocity.y})
	await frames(60)
	var ledge := box(Vector3(3, 0.25, 118), Vector3(2, 0.5, 2))
	await reset_at(Vector3(3, 0.54, 118))
	player.touch_move = Vector2.RIGHT
	var left_ledge := false
	for tick in range(45):
		await physics_frame
		if not player.is_on_floor(): left_ledge = true; break
	player.jump_requested = true
	await frames(5)
	check("coyote_jump_after_leaving_ledge", left_ledge and player.velocity.y > 4 and player.position.y > 0.7, str(player.position))
	ledge.queue_free()
	player.clear_input()
	await frames(60)
	var clips := ["cover_enter", "cover_idle", "cover_left", "cover_right", "cover_high", "cover_peek_idle", "cover_peek_left", "cover_peek_right", "crouch_idle", "crouch_walk", "slide", "vault", "jump", "land"]
	check("native_action_clips_exist", clips.all(func(clip): return player.rig.animation.has_animation(clip)))
	var hud = arena.hud
	hud.mobile = true
	var layouts := []
	for extent in [Vector2(1280,720), Vector2(960,540), Vector2(1920,864), Vector2(1024,768)]:
		hud.size = extent
		hud.update_layout()
		var valid := true
		for name_ in hud.ACTIONS:
			var rect: Rect2 = hud.button_rect(name_)
			if not Rect2(Vector2.ZERO, extent).encloses(rect): valid = false
			for other in hud.ACTIONS:
				if other != name_ and rect.intersects(hud.button_rect(other)): valid = false
		layouts.append({"size": str(extent), "ok": valid})
	check("hud_buttons_fit_without_overlap", layouts.all(func(item):return item.ok), layouts)
	hud.size = Vector2(1280,720)
	hud.update_layout()
	await reset_at(Vector3(-4.7, 0.04, 100.97))
	await action("cover")
	await frames(20)
	check("authored_foreground_cover_is_usable", player.mobility.state == "cover" and player.mobility.cover_low)
	await capture("07-low-cover-hud")
	await action("jump")
	await frames(19)
	check("authored_cover_supports_vault", player.mobility.state == "vault")
	await capture("08-cover-vault")
	await frames(28)
	await reset_at(Vector3(0, 0.04, 101))
	player.touch_move = Vector2(0,-1)
	player.touch_sprint = true
	await frames(20)
	await action("stance")
	await frames(12)
	await capture("09-slide-hud")
	player.clear_input()
	hud.clear_touch()
	check("pause_release_clears_inputs", not player.fire_held and not player.aim_held and player.touch_move == Vector2.ZERO and player.mobility.jump_buffer == 0)
	var report := {"ok": failures.is_empty(), "checks": checks, "failures": failures, "engine": Engine.get_version_info(), "limits": ["Linux engine evidence; no Android device FPS or comfort measurement"]}
	var path := directory.path_join("mobility-acceptance.json") if not directory.is_empty() else "user://mobility-acceptance.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("MOBILITY_ACCEPTANCE_RESULT " + JSON.stringify(report))
	player.end_playtest()
	OS.delay_msec(250)
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
