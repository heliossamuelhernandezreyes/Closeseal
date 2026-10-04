extends SceneTree
const RETARGET=preload("res://tools/shooter_rest_retarget.gd")
var checks: Dictionary={}
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(name_: String,passed: bool,value: Variant=null) -> void:
	checks[name_]={"ok":passed,"value":value}
	if not passed:failures.append(name_)
func run() -> void:
	var directory:="user://combat-polish-review"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):directory=argument.trim_prefix("--captures=")
	DirAccess.make_dir_recursive_absolute(directory)
	RenderingServer.render_loop_enabled=false
	var source:=Skeleton3D.new();var target:=Skeleton3D.new()
	root.add_child(source);root.add_child(target)
	source.add_bone("root-motion");target.add_bone("pelvis")
	source.set_bone_rest(0,Transform3D.IDENTITY)
	target.set_bone_rest(0,Transform3D(Basis.IDENTITY.scaled(Vector3(1.2,1.4,1.6)),Vector3(2,0,0)))
	source.reset_bone_poses();target.reset_bone_poses()
	source.set_bone_pose_position(0,Vector3(.3,.1,0))
	var transfer: Dictionary=RETARGET.transfer(source,target,{"root-motion":"pelvis"},2.0,"root-motion")
	check("explicit_renamed_root_translation",transfer.ok and target.get_bone_global_pose(0).origin.is_equal_approx(Vector3(2.6,.2,0)),target.get_bone_global_pose(0).origin)
	check("target_scale_preserved",target.get_bone_global_pose(0).basis.get_scale().is_equal_approx(Vector3(1.2,1.4,1.6)))
	check("unmapped_translation_rejected",not RETARGET.transfer(source,target,{"root-motion":"pelvis"},1.0,"absent").ok)
	source.free();target.free()
	var arena: Node3D=load("res://src/shooter/shooter_arena.tscn").instantiate();root.add_child(arena)
	for tick in 8:await physics_frame
	arena.begin_slice()
	for enemy in arena.enemies:enemy.set_physics_process(false)
	var player: CharacterBody3D=arena.player
	player.set_physics_process(false);player.set_process(false)
	var rig: Node3D=player.rig
	rig.set_process(false);rig.transition.active=false;rig.combat.active=false;rig.ground_contact.active=false
	rig.tree.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.set_motion(0);rig.turn_lean=0;rig.acceleration_lean=0
	for case in [["60fps",[1.0/60.0]],["30fps",[1.0/30.0]],["variable",[1.0/120.0,1.0/60.0,1.0/30.0,0.045]]]:
		rig.transition.previous_positions.clear();rig.transition.previous_rotations.clear();rig.transition.previous_velocities.clear()
		rig.transition.previous_inputs.clear();rig.transition.position_offsets.clear();rig.transition.rotation_offsets.clear();rig.transition.velocity_offsets.clear()
		rig.action_pose="";rig.action_weight=0
		rig._process(1.0/60.0);rig.tree.advance(1.0/60.0);rig.transition.apply_pose(1.0/60.0)
		var hips: int=rig.skeleton.find_bone("hips")
		var previous: Vector3=rig.skeleton.get_bone_global_pose(hips).origin
		var maximum:=0.0
		for index in 100:
			var delta: float=case[1][index%case[1].size()]
			rig.action_pose="crouch_idle" if index<50 else ""
			rig._process(delta);rig.tree.advance(delta);rig.transition.apply_pose(delta)
			var position: Vector3=rig.skeleton.get_bone_global_pose(hips).origin
			maximum=maxf(maximum,position.distance_to(previous));previous=position
		check("crouch_transition_"+case[0],maximum<0.085,maximum)
	var meshes: Array=rig.weapon.find_children("*","MeshInstance3D",true,false)
	var material_details: Array=[]
	for mesh in meshes:
		for surface in mesh.mesh.get_surface_count():
			var material: Material=mesh.get_active_material(surface)
			material_details.append({"mesh":str(mesh.name),"material":material.get_class() if material else "null","fade":material.distance_fade_mode if material is BaseMaterial3D else -1})
	check("all_weapon_surfaces_fade",meshes.all(func(mesh):
		for surface in mesh.mesh.get_surface_count():
			var material: Material=mesh.get_active_material(surface)
			if not material is BaseMaterial3D or material.distance_fade_mode!=BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER:return false
		return true),material_details)
	check("audio_bank_closure",arena.sounds.has("shot_indoor") and arena.sounds.shot_indoor.size()==3 and arena.sounds.step_metal.size()==4)
	arena.effects.audio_events.clear()
	player.ammo=0;player.reload_remaining=0;player.start_reload()
	# Freeze movement while exercising the same physics reload path.
	for tick in 125:player._physics_process(1.0/60.0)
	check("empty_reload_routes_three_phases",arena.effects.audio_events.get("reload_out",0)==1 and arena.effects.audio_events.get("reload_in",0)==1 and arena.effects.audio_events.get("reload_charge",0)==1,arena.effects.audio_events)
	check("voices_stay_bounded",arena.effects.local_voices.size()==8 and arena.effects.spatial_voices.size()==16)
	var record: Dictionary={"ok":failures.is_empty(),"engine":Engine.get_version_info(),"checks":checks,"failures":failures,"limits":["Controlled native motion/audio routing; does not establish handset FPS or human sound quality."]}
	var file:=FileAccess.open(directory.path_join("combat-polish-acceptance.json"),FileAccess.WRITE);file.store_string(JSON.stringify(record,"  "));file.close()
	print("COMBAT_POLISH_ACCEPTANCE ",JSON.stringify(record))
	meshes.clear();player.end_playtest();rig.tree.active=false
	RenderingServer.render_loop_enabled=true
	for frame in 8:await process_frame;await RenderingServer.frame_post_draw
	OS.delay_msec(250);await create_timer(0.1).timeout
	arena.queue_free();RenderingServer.render_loop_enabled=true
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	await create_timer(0.25).timeout
	quit(0 if failures.is_empty() else 1)
