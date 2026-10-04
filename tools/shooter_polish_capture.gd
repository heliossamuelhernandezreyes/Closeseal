extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var directory:="user://polish-captures"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):directory=argument.trim_prefix("--captures=")
	DirAccess.make_dir_recursive_absolute(directory)
	root.size=Vector2i(1280,720)
	var arena: Node3D=load("res://src/shooter/shooter_arena.tscn").instantiate();root.add_child(arena)
	for frame in 8:await physics_frame
	arena.begin_slice();arena.hud.hide()
	for enemy in arena.enemies:enemy.set_physics_process(false)
	var player: CharacterBody3D=arena.player
	player.position=Vector3(3,0.04,116)
	for frame in 12:await physics_frame
	player.set_physics_process(false);player.set_process(false)
	var rig: Node3D=player.rig
	rig.rotation=Vector3.ZERO;rig.set_process(false);rig.tree.active=false
	rig.transition.active=false;rig.combat.active=false;rig.ground_contact.active=false
	rig.animation.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var camera:=Camera3D.new();arena.add_child(camera);camera.current=true;camera.fov=43
	camera.global_position=player.global_position+Vector3(2.7,1.65,3.9)
	camera.look_at(player.global_position+Vector3(0,0.92,0))
	for definition in [["01-idle","idle",0.0,0.30,0.0],["02-crouch","crouch_idle",1.0,0.30,0.0],["03-reload","idle",0.0,0.30,0.9],["04-run","run",0.0,0.72,0.0]]:
		rig.action_pose=definition[1] if definition[1]!="idle" else ""
		rig.stance_weight=definition[2];rig.reload_time=definition[4]
		rig.target_enabled=false;rig.aim_pitch=0;rig.turn_lean=0;rig.acceleration_lean=0
		rig.skeleton.reset_bone_poses();rig._process(1.0/60.0)
		rig.animation.play(definition[1]);rig.animation.seek(rig.animation.get_animation(definition[1]).length*definition[3],true)
		rig.combat._process_modification()
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join(definition[0]+".png"))
	print("POLISH_CAPTURES_OK")
	player.end_playtest();arena.queue_free()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	await create_timer(0.25).timeout;quit()
