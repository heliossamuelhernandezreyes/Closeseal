extends SceneTree
## Exercises physical corner/transfer paths, the actual upper route and mission.
var arena: Node3D
var player: CharacterBody3D
var checks := {}
var failures: Array[String] = []
var directory := ""

func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for tick in range(count): await physics_frame
func check(name_: String, passed: bool, detail: Variant = null) -> void:
	checks[name_] = {"ok": passed, "details": detail}
	if not passed: failures.append(name_)
func reset_at(point: Vector3) -> void:
	player.clear_input()
	player.mobility.reset()
	player.position = point
	player.rotation = Vector3.ZERO
	player.rig.rotation = Vector3.ZERO
	player.look_pitch = -0.12
	await frames(8)
func box(point: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = dimensions
	body.add_child(shape)
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
	root.size = Vector2i(1280,720)
	RenderingServer.render_loop_enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--captures="): directory = arg.trim_prefix("--captures=")
	if not directory.is_empty(): DirAccess.make_dir_recursive_absolute(directory)
	arena = load("res://src/shooter/shooter_arena.tscn").instantiate()
	root.add_child(arena)
	await frames(6)
	player = arena.player
	arena.begin()
	for enemy in arena.enemies: enemy.set_physics_process(false)
	var corner := box(Vector3(3,1.1,115),Vector3(4,2.2,2))
	await reset_at(Vector3(4.5,0.04,116.5))
	check("corner_fixture_attaches", player.mobility.toggle_cover())
	await frames(16)
	player.touch_move = Vector2.RIGHT
	for tick in range(20):
		await physics_frame
		if player.mobility.state == "corner": break
	check("strafe_enters_corner_path",player.mobility.state == "corner")
	player.touch_move = Vector2.ZERO
	var corner_ammo: int = player.ammo
	player.shoot()
	check("corner_blocks_weapon",player.ammo == corner_ammo)
	await frames(45)
	check("corner_changes_face_with_collision",player.mobility.completed_corners == 1 and player.mobility.state == "cover" and player.mobility.cover_normal.dot(Vector3.RIGHT) > 0.95 and player.position.x > 5.4,
		{"position":str(player.position),"state":player.mobility.state,"normal":str(player.mobility.cover_normal)})
	await reset_at(Vector3(4.5,0.04,116.5))
	player.mobility.toggle_cover()
	await frames(16)
	var obstruction := box(Vector3(5.5,1.0,116.5),Vector3(0.5,2,1.0))
	await frames(3)
	var before := player.position
	check("blocked_corner_rejected_without_warp",not player.mobility.try_corner(-1) and player.position.distance_to(before) < 0.001)
	obstruction.queue_free()
	await frames(4)
	check("corner_retry_after_clearance",player.mobility.try_corner(-1))
	var late_blocker := box(Vector3(5.4,1.0,116.0),Vector3(0.5,2,1.0))
	await frames(35)
	check("dynamic_corner_blocker_aborts",player.mobility.transition_aborted and player.mobility.state == "free")
	late_blocker.queue_free()
	corner.queue_free()
	await frames(4)
	var left := box(Vector3(-4,0.57,116),Vector3(4,1.14,0.56))
	var right := box(Vector3(2,0.57,116),Vector3(4,1.14,0.56))
	await reset_at(Vector3(-3,0.04,116.85))
	player.mobility.toggle_cover()
	await frames(16)
	var transfer: Dictionary = player.mobility.nearby_transfer(Vector3.RIGHT)
	check("adjacent_cover_candidate_found",not transfer.is_empty())
	player.mobility.transfer_candidate = transfer
	var transfer_ok: bool = not transfer.is_empty() and player.mobility.toggle_cover() and player.mobility.state == "transfer"
	check("cover_dash_accepted",transfer_ok)
	await frames(50)
	check("cover_dash_attaches_to_destination",player.mobility.state == "cover" and player.mobility.completed_transfers == 1 and player.mobility.cover_body.get_ref() == right and player.position.x > 0,
		{"position":str(player.position),"state":player.mobility.state})
	await reset_at(Vector3(-3,0.04,116.85))
	player.mobility.toggle_cover()
	await frames(16)
	obstruction = box(Vector3(-1,0.8,116.75),Vector3(0.8,1.6,1))
	await frames(3)
	check("blocked_cover_gap_rejected",player.mobility.nearby_transfer(Vector3.RIGHT).is_empty())
	obstruction.queue_free()
	left.queue_free()
	right.queue_free()
	await frames(4)
	# Verify the authored ramp with the real player, not just a navigation query.
	await reset_at(Vector3(31,0.04,89))
	player.touch_move = Vector2(0,-1)
	await frames(170)
	player.clear_input()
	await frames(10)
	check("workshop_ramp_actual_ascent",player.position.y > 3.0 and player.position.z < 76 and player.is_on_floor(),str(player.position))
	player.look_pitch = -0.05
	await capture("10-mezzanine")
	await reset_at(Vector3(31,1.6,82))
	await frames(24)
	var contact: SkeletonModifier3D = player.rig.ground_contact
	check("slope_pose_correction_bounded", contact.offsets.length() > 0.001 and absf(contact.offsets.x) <= 0.181 and absf(contact.offsets.y) <= 0.181 and contact.contact_errors.length() < 0.12,
		{"offsets":str(contact.offsets),"errors":str(contact.contact_errors)})
	player.jump_requested = true
	await frames(14)
	check("airborne_disables_ground_correction",not player.is_on_floor() and contact.offsets == Vector2.ZERO)
	var map: RID = arena.navigation.get_navigation_map()
	var paths := []
	for route in arena.design.slice.navigation_checks:
		var start: Vector3 = arena.vec(route[0])
		var end: Vector3 = arena.vec(route[1])
		var path := NavigationServer3D.map_get_path(map,start,end,true)
		paths.append({"points":path.size(),"reaches":path.size()>1 and path[-1].distance_to(end)<0.8})
	check("slice_routes_baked_and_reachable",paths.all(func(p):return p.reaches),paths)
	# Start the new operation from the actual menu entry on a fresh scene.
	player.end_playtest()
	arena.queue_free()
	await frames(3)
	arena = load("res://src/shooter/shooter_arena.tscn").instantiate()
	root.add_child(arena)
	await frames(6)
	player = arena.player
	arena.begin_slice()
	for enemy in arena.enemies: enemy.set_physics_process(false)
	await frames(5)
	check("sector_menu_starts_focused_operation",arena.mission_mode == "sector07" and arena.design.enemy_spawns.size() == 6 and arena.enemies.filter(func(e):return not e.dead).size() == 6)
	var spawn_details := []
	for point in arena.design.enemy_spawns:
		var spawn: Vector3 = arena.vec(point)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = CapsuleShape3D.new()
		query.shape.radius = 0.36
		query.shape.height = 1.85
		query.transform = Transform3D(Basis.IDENTITY,spawn+Vector3.UP*0.985)
		query.collision_mask = 1
		var overlaps := arena.get_world_3d().direct_space_state.intersect_shape(query)
		var route := NavigationServer3D.map_get_path(arena.navigation.get_navigation_map(),arena.vec(arena.design.player_spawn),spawn,true)
		spawn_details.append({"position":str(spawn),"overlaps":overlaps.size(),"ok":overlaps.is_empty() and route.size()>1 and route[-1].distance_to(spawn)<0.8})
		query = null
	check("six_sector_spawns_clear_and_reachable",spawn_details.all(func(s):return s.ok),spawn_details)
	await reset_at(Vector3(0,0.04,98))
	var flanker: CharacterBody3D = arena.enemies[1]
	var flanker_home := flanker.position
	flanker.position = Vector3(2,0.04,90)
	flanker.repath = 0.0
	flanker.set_physics_process(true)
	await frames(140)
	check("sector_flanker_uses_navigation_and_fires",flanker.distance_travelled > 1 and flanker.flank_time > 0 and flanker.shots > 0,
		{"travelled":flanker.distance_travelled,"target":str(flanker.agent.target_position),"shots":flanker.shots})
	flanker.set_physics_process(false)
	flanker.position = flanker_home
	player.health = 100
	# Capture actual incomplete mission state, before the objective replay below.
	arena.hud.mobile = true
	await reset_at(Vector3(26,0.04,95))
	player.rotation.y = -0.30
	player.look_pitch = -0.02
	await frames(10)
	await capture("11-workshop-combat")
	await reset_at(Vector3(29,3.15,73.5))
	player.rotation.y = 0.65
	player.look_pitch = -0.10
	await frames(10)
	await capture("12-upper-route")
	await reset_at(Vector3(0,0.04,67))
	arena.interact()
	check("slice_enforces_objective_order",arena.capture_id.is_empty())
	for definition in arena.design.beacons:
		await reset_at(arena.vec(definition.position)+Vector3.UP*0.05)
		arena.interact()
		await frames(195)
		check("slice_secures_"+definition.id,definition.id in arena.secured)
	await reset_at(arena.vec(arena.design.extraction)+Vector3.UP*0.05)
	arena.interact()
	check("slice_extracts_after_three_objectives",arena.outcome == "OPERACIÓN COMPLETADA" and not arena.playing)
	var observation: Dictionary = arena.metrics.save_session()
	check("runtime_observation_records_real_frames",observation.frames_recorded > 0 and observation.scope == "desktop-runtime" and observation.p95_ms > 0 and observation.seconds > 0)
	var report := {"ok":failures.is_empty(),"checks":checks,"failures":failures,"engine":Engine.get_version_info(),
		"limits":["Linux engine/collision evidence; 3–5 minute target needs human playtest; Android device unmeasured"]}
	var path := directory.path_join("slice-acceptance.json") if not directory.is_empty() else "user://slice-acceptance.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("SLICE_ACCEPTANCE_RESULT "+JSON.stringify(report))
	player.end_playtest()
	arena.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
