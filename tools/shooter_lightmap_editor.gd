@tool
extends EditorPlugin
## Native editor bake adapter: Godot 4.7.2 does not expose LightmapGI.bake to GDScript.
func _enter_tree() -> void:call_deferred("bake_scene")
func bake_scene() -> void:
	var scene_path:=OS.get_environment("NEXO_BAKE_SCENE")
	if scene_path.is_empty():return
	var filesystem:=EditorInterface.get_resource_filesystem()
	while filesystem.is_scanning():await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	EditorInterface.open_scene_from_path(scene_path)
	await get_tree().create_timer(0.6).timeout
	if OS.get_environment("NEXO_BAKE_WARMUP")=="1":
		# 3D texture detection queues imports only after the scene is opened in the editor.
		await get_tree().create_timer(3.0).timeout
		while filesystem.is_scanning():await get_tree().process_frame
		await get_tree().create_timer(1.0).timeout
		get_tree().quit();return
	EditorInterface.set_main_screen_editor("3D")
	var scene:=EditorInterface.get_edited_scene_root()
	var lightmap:=scene.find_child("*",true,false) as LightmapGI
	for child in scene.find_children("*","LightmapGI",true,false):lightmap=child;break
	assert(is_instance_valid(lightmap),"scene has no LightmapGI")
	lightmap.light_data=LightmapGIData.new()
	var data_path:=scene_path.get_basename()+".lmbake"
	assert(ResourceSaver.save(lightmap.light_data,data_path,ResourceSaver.FLAG_CHANGE_PATH)==OK)
	lightmap.light_data.take_over_path(data_path)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(lightmap)
	EditorInterface.edit_node(lightmap)
	await get_tree().create_timer(0.6).timeout
	var button: Button
	for control in EditorInterface.get_base_control().find_children("*","Button",true,false):
		if control.text=="Bake Lightmaps" and control.is_visible_in_tree():button=control;break
	assert(is_instance_valid(button),"native bake toolbar unavailable")
	print("NEXO_LIGHTMAP_EDITOR_BEGIN ",scene_path)
	print("NEXO_LIGHTMAP_DATA_PATH ",lightmap.light_data.resource_path)
	print("NEXO_LIGHTMAP_BUTTON ",button.get_global_rect()," ",button.disabled)
	print("NEXO_LIGHTMAP_SELECTION ",lightmap.get_path()," ",EditorInterface.get_selection().get_selected_nodes().size())
	print("NEXO_LIGHTMAP_ACTION_CONNECTIONS ",button.get_signal_connection_list("pressed"))
	# Invoke the toolbar's bound native action; synthetic pointer events depend on focus.
	button.pressed.emit()
	print("NEXO_LIGHTMAP_ACTION_RETURN ",lightmap.light_data.get("lightmap_textures").size())
	for tick in range(20):
		if not lightmap.light_data.get("lightmap_textures").is_empty():break
		await get_tree().create_timer(1.0).timeout
	for dialog in EditorInterface.get_base_control().find_children("*","AcceptDialog",true,false):
		if dialog.visible:print("NEXO_BAKE_DIALOG ",dialog.dialog_text)
	while filesystem.is_scanning():await get_tree().process_frame
	if lightmap.light_data.get("lightmap_textures").is_empty():
		print("NEXO_LIGHTMAP_EMPTY_OUTPUT")
		get_tree().quit(1);return
	assert(not lightmap.light_data.get("lightmap_textures").is_empty(),"bake produced no light textures")
	assert(not lightmap.light_data.get("user_data").is_empty(),"bake produced no mesh bindings")
	assert(ResourceSaver.save(lightmap.light_data,scene_path.get_basename()+"-light.tres",ResourceSaver.FLAG_CHANGE_PATH)==OK)
	lightmap.light_data.take_over_path(scene_path.get_basename()+"-light.tres")
	EditorInterface.save_scene()
	if scene_path.ends_with("sector_bake.tscn"):
		var runtime_path:=scene_path.get_base_dir()+"/sector_world.tscn"
		var runtime: Node3D=load(runtime_path).instantiate()
		var runtime_gi: LightmapGI=runtime.find_child("SectorIndirectLight",true,false)
		runtime_gi.light_data=lightmap.light_data
		var packed:=PackedScene.new();assert(packed.pack(runtime)==OK)
		assert(ResourceSaver.save(packed,runtime_path)==OK)
		runtime.free()
	var properties: Dictionary={"textures":lightmap.light_data.get("lightmap_textures").size(),"mesh_binding_fields":lightmap.light_data.get("user_data").size(),"probes":lightmap.light_data.get("probe_data").points.size()}
	var file:=FileAccess.open(scene_path.get_basename()+"-bake.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info(),"scope":"native-editor-lightmap-bake","scene":scene_path,"properties":properties},"  "));file.close()
	print("NEXO_LIGHTMAP_EDITOR_DONE ",JSON.stringify(properties))
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
