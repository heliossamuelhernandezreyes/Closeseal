extends SceneTree
## Render actual runtime inputs at a fixed simulation step; this is visual evidence, not FPS.
var arena: Node3D
var directory := "user://finish-review"
var index := 0
var trace: Array[Dictionary] = []
func _initialize() -> void:call_deferred("run")
func frames(count: int) -> void:
	for tick in range(count):await physics_frame
func snapshot(name_: String) -> void:
	RenderingServer.render_loop_enabled=true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("%03d.png"%index))
	trace.append({"frame":index,"label":name_,"snapshot":arena.player.playtest_snapshot()})
	index+=1
	RenderingServer.render_loop_enabled=false
func sequence(name_: String, count: int) -> void:
	for sample in range(count):
		await frames(5)
		await snapshot(name_)
func run() -> void:
	root.size=Vector2i(1280,720)
	root.gui_embed_subwindows=true
	RenderingServer.render_loop_enabled=false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captures="):directory=argument.trim_prefix("--captures=")
	DirAccess.make_dir_recursive_absolute(directory)
	arena=load("res://src/shooter/shooter_arena.tscn").instantiate();root.add_child(arena)
	await frames(8);arena.begin()
	for enemy in arena.enemies:enemy.set_physics_process(false)
	var fixture:=StaticBody3D.new();fixture.name="SteelCoverReviewFixture"
	var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(8,1.1,1);fixture.add_child(shape)
	var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();mesh.mesh.size=Vector3(8,1.1,1)
	mesh.material_override=load("res://assets/shooter/serious/materials/oxide.tres");fixture.add_child(mesh)
	arena.add_child(fixture);fixture.position=Vector3(3,0.55,109)
	var player: CharacterBody3D=arena.player
	player.position=Vector3(3,0.04,116);player.rotation=Vector3.ZERO;player.rig.rotation=Vector3.ZERO
	player.look_pitch=-0.08
	await sequence("idle",5)
	player.touch_move=Vector2(0,-1)
	await sequence("start-walk",8)
	player.touch_move=Vector2.ZERO
	await sequence("stop",5)
	player.touch_move=Vector2.RIGHT
	await sequence("strafe",8)
	player.touch_move=Vector2.ZERO
	player.look(Vector2(160,0))
	await sequence("turn-and-settle",5)
	player.position=Vector3(3,0.04,110.15);player.rotation=Vector3.ZERO;player.rig.rotation=Vector3.ZERO
	player.mobility.reset();await frames(10)
	player.mobility.toggle_cover()
	await sequence("cover-entry",7)
	player.touch_move=Vector2.RIGHT;player.aim_held=true
	await sequence("cover-peek-strafe",10)
	player.touch_move=Vector2.ZERO
	for shot in range(4):
		player.shoot();await snapshot("fire");await sequence("fire-recovery",2)
	player.ammo=0;player.start_reload()
	await sequence("empty-reload",23)
	player.clear_input();arena.hud.mobile=true
	await snapshot("touch-layout")
	arena.playing=false;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	arena.hud.update_menu();arena.hud.settings.popup_centered(Vector2i(440,460))
	await snapshot("settings")
	var f:=FileAccess.open(directory.path_join("review-trace.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"scope":"fixed-step Linux runtime visual review; output video sampled at 10 fps, not a performance measurement","engine":Engine.get_version_info(),"frames":trace},"  "));f.close()
	arena.effects.stop_audio();OS.delay_msec(250)
	arena.queue_free();await process_frame
	quit()
