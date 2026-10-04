extends SceneTree
## Native clip/contact measurements plus meaningful late-session and UI regression checks.
var arena: Node3D
var directory := ""
var checks := {}
var failures: Array[String] = []
func _initialize() -> void:call_deferred("run")
func check(id: String, passed: bool, detail: Variant=null) -> void:
	checks[id]={"ok":passed,"details":detail}
	if not passed:failures.append(id)
func xyz(v: Vector3) -> Array:return [v.x,v.y,v.z]
func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):directory=argument.trim_prefix("--captures=")
	if directory.is_empty():directory="user://finish-evidence"
	DirAccess.make_dir_recursive_absolute(directory)
	RenderingServer.render_loop_enabled=false
	arena=load("res://src/shooter/shooter_arena.tscn").instantiate()
	root.add_child(arena)
	for tick in range(6):await physics_frame
	arena.begin()
	for enemy in arena.enemies:enemy.set_physics_process(false)
	var player: CharacterBody3D=arena.player
	player.position=Vector3(3,0.04,116)
	for tick in range(8):await physics_frame
	player.set_physics_process(false);player.set_process(false)
	var rig: Node3D=player.rig
	rig.set_process(false);rig.tree.active=false;rig.combat.active=false;rig.ground_contact.active=false
	var skeleton: Skeleton3D=rig.skeleton
	var start:=player.position
	var floor_query:=PhysicsRayQueryParameters3D.create(start+Vector3.UP*0.4,start-Vector3.UP*0.4,1)
	var floor_hit:=player.get_world_3d().direct_space_state.intersect_ray(floor_query)
	if not floor_hit.is_empty():start.y=floor_hit.position.y
	player.position=start
	var record: Dictionary={"version":1,"scope":"godot-native-controlled-motion","engine":Engine.get_version_info(),
		"source_hashes":{},"cadence":[],"contacts":[],"grips":[],
		"visual_review":{"reviewer":"Codex engine/visual review","notes":"Matched 0.7/0.8 poses and the rendered runtime were inspected. Source rotations are adapted to project foot paths and rifle IK. Cover feet stay separated and grips remain aligned; nearby body and weapon materials now fade progressively. Pose weight, reload detail and sky/material cohesion still need art work. Native contacts and synthetic recorder checks do not approve AAA finish or handset performance."}}
	for path in ["src/shooter/motion_profile.gd","src/shooter/ground_pose.gd","src/shooter/character_rig.gd","tools/shooter_bake_animations.gd","assets/shooter/serious/combat_motion.res"]:
		record.source_hashes[path]=FileAccess.get_sha256("res://"+path)
	for definition in [["walk",1.8,Vector3.FORWARD],["run",8.8,Vector3.FORWARD],
		["cover_left",3.2,Vector3.LEFT],["cover_right",3.2,Vector3.RIGHT],
		["cover_peek_left",2.4,Vector3.LEFT],["cover_peek_right",2.4,Vector3.RIGHT],
		["crouch_walk",2.7,Vector3.FORWARD],["crouch_run",6.8,Vector3.FORWARD]]:
		var clip: String=definition[0]
		var speed: float=definition[1]
		var axis: Vector3=definition[2]
		rig.rotation=Vector3.ZERO
		rig.action_pose=clip if clip.begins_with("cover_") or clip.begins_with("crouch_") else ""
		rig.cover_peeking=clip.begins_with("cover_peek")
		rig.motion_blend=speed
		rig.set_motion(speed,false,Vector2(axis.x,axis.z))
		rig._process(1.0/60.0)
		var scale: float=rig.tree.get("parameters/ActionCadence/scale" if not rig.action_pose.is_empty() else "parameters/Cadence/scale")
		var animation: Animation=rig.animation.get_animation(clip)
		var points: Array[Vector3]=[]
		player.position=start
		for phase in [0.02,0.48]:
			skeleton.reset_bone_poses();rig.animation.play(clip);rig.animation.seek(animation.length*phase,true)
			points.append(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("foot.L")).origin))
		var displacement:=points[1]-points[0]
		var velocity:=axis*speed
		var sample_seconds:=animation.length*0.46
		var residual:=velocity+displacement/sample_seconds*scale
		record.cadence.append({"case":clip,"body_velocity_xz":[velocity.x,velocity.z],"foot_displacement_xz":[displacement.x,displacement.z],"sample_seconds":sample_seconds,"time_scale":scale})
		check(clip+"_signed_cadence",Vector2(residual.x,residual.z).length()/speed<0.015,Vector2(residual.x,residual.z).length()/speed)
		rig.ground_contact.reset_contacts()
		var drift:=0.0
		var count:=0
		for sample in range(240):
			var elapsed:=float(sample)*animation.length/scale/120.0
			player.position=start+velocity*elapsed
			skeleton.reset_bone_poses();rig.animation.play(clip);rig.animation.seek(fposmod(elapsed*scale,animation.length),true)
			rig.ground_contact._process_modification()
			for index in range(2):
				if not rig.ground_contact.planted[index]:continue
				var side: String="L" if index==0 else "R"
				var point: Vector3=skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("foot."+side)).origin)
				var anchor: Vector3=rig.ground_contact.anchors[index]
				drift=maxf(drift,point.distance_to(anchor));count+=1
				record.contacts.append({"case":clip,"foot":side,"position":xyz(point),"anchor":xyz(anchor),"time_s":elapsed})
		check(clip+"_planted_contacts",count>=20 and drift<=0.03,{"samples":count,"maximum_drift_m":drift})
	player.position=start
	rig.ground_contact.reset_contacts()
	rig.set_motion(0);rig.turn_lean=0;rig.acceleration_lean=0
	for definition in [["idle",0.0],["cover_idle",1.0],["cover_peek_idle",0.443]]:
		rig.action_pose=definition[0] if definition[0]!="idle" else ""
		rig.stance_weight=definition[1];rig.cover_peeking=definition[0]=="cover_peek_idle"
		for sample in range(30):
			rig._process(1.0/60.0)
			skeleton.reset_bone_poses();rig.animation.play(definition[0]);rig.animation.seek(float(sample)/30.0*rig.animation.get_animation(definition[0]).length,true)
			rig.combat._process_modification()
			for hand in range(2):record.grips.append({"case":definition[0],"hand":"R" if hand==0 else "L","error_m":rig.combat.grip_errors[hand]})
	var maximum_grip:=0.0
	for value in record.grips:maximum_grip=maxf(maximum_grip,value.error_m)
	check("weapon_grips_in_three_stances",maximum_grip<=0.04,maximum_grip)
	var meter=load("res://src/shooter/runtime_metrics.gd").new()
	meter.arena=arena;root.add_child(meter);meter.set_process(false)
	for sample in range(36000):meter.record_frame(1.0/60.0)
	for sample in range(18000):meter.record_frame(1.0/30.0)
	var performance: Dictionary=meter.report(false)
	check("recorder_counts_all_twenty_minutes",performance.frames_recorded==54000 and performance.seconds>1199.0,{"frames":performance.frames_recorded,"seconds":performance.seconds})
	check("warm_tail_detects_synthetic_slowdown",performance.windows[-1].p95_ms>30.0 and performance.p95_ms>30.0,performance.windows[-1])
	check("recent_raw_buffer_is_bounded",meter.frames_ms.size()==meter.MAX_FRAMES,meter.frames_ms.size())
	meter.reset_session();check("new_session_discards_old_samples",meter.total_frames==0 and meter.windows.is_empty())
	meter.queue_free()
	var hud: Control=arena.hud
	var old_layouts: Dictionary=hud.preferences.layouts.duplicate()
	check("editable_touch_position",hud.preferences.update_button("fire",Rect2(220,240,92,92),hud.DEFAULT_BUTTONS))
	check("overlapping_touch_edit_rejected",not hud.preferences.update_button("fire",hud.design_button_rect("aim"),hud.DEFAULT_BUTTONS))
	check("offscreen_touch_edit_rejected",not hud.preferences.update_button("fire",Rect2(-50,240,92,92),hud.DEFAULT_BUTTONS))
	hud.safe_area_override=Rect2(60,0,1160,720);hud.update_layout()
	check("safe_area_keeps_buttons_inside",Rect2(60,0,1160,720).encloses(hud.button_rect("pause")))
	hud.safe_area_override=Rect2();hud.preferences.layouts=old_layouts
	var effects: Node3D=arena.effects
	var nodes_before:=effects.get_child_count()
	for sample in range(200):effects.impact(start,Vector3.UP,"metal")
	check("effects_pool_is_bounded",effects.get_child_count()==nodes_before and effects.entries.size()==64,effects.get_child_count())
	effects._process(6.0)
	check("expired_pool_slots_are_reusable",effects.acquire(0.1,"ffc878",Vector3.ONE*0.02,start)!=null)
	player.ammo=10;player.reload_remaining=0;player.start_reload()
	check("tactical_reload_duration",is_equal_approx(player.reload_remaining,1.6))
	player.ammo=0;player.reload_remaining=0;player.start_reload()
	check("empty_reload_has_charge_phase",is_equal_approx(player.reload_remaining,1.95) and rig.reload_empty)
	var enemy: CharacterBody3D=arena.enemies[0]
	enemy.cover_time=3.0;enemy.cover_target=enemy.global_position;arena.elapsed=0
	enemy._physics_process(1.0/60.0)
	check("hostile_cover_has_physical_crouch",enemy.cover_crouched and enemy.body_shape.shape.height<1.1 and enemy.rig.action_pose=="cover_idle")
	check("all_enemies_use_hostile_skin",arena.enemies.all(func(item):return item.rig.skin_name=="hostile"))
	var file:=FileAccess.open(directory.path_join("finish-record.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"  "));file.close()
	var result: Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"engine":Engine.get_version_info(),
		"scope":"Native controlled motion and functional checks; recorder slowdown is synthetic, not device performance."}
	file=FileAccess.open(directory.path_join("finish-acceptance.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("FINISH_ACCEPTANCE_RESULT "+JSON.stringify(result))
	arena.effects.stop_audio()
	OS.delay_msec(250)
	await create_timer(0.1).timeout
	arena.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
