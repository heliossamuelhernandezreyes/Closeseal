@tool
extends RefCounted
const VISUALS=preload("res://src/prototype/map_visual_kit.gd")
const PRESENTATION=preload("res://src/shooter/sector_presentation.gd")
var prepared_meshes := 0
var mesh_cache: Dictionary={}
var material_cache: Dictionary={}
var texture_cache: Dictionary={}
var hidden_paths: Array[String]=[]
func run(context: SceneTree, arguments: Dictionary) -> Dictionary:
	var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://maps/nexo_combat_01.json"))
	var world:=Node3D.new();world.name="AuthoredCombatMap";context.root.add_child(world)
	var stats: Dictionary=VISUALS.new(world,contract).build();assert(stats.errors.is_empty(),str(stats))
	PRESENTATION.lighting(world)
	var details:=PRESENTATION.details(world)
	var reflections: Node3D=load("res://assets/shooter/sector_lighting.tscn").instantiate();world.add_child(reflections)
	var copies:=Node3D.new();copies.name="LightmappedGeometry";world.add_child(copies)
	# Primitive and imported meshes are copied into independent UV2 resources. Sources remain intact.
	for node in world.find_children("*","MeshInstance3D",true,false):
		var mesh_node:=node as MeshInstance3D
		if str(mesh_node.name)=="ground":mesh_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
		var bounds: AABB=mesh_node.global_transform*mesh_node.get_aabb()
		if bounds.size.x>80 or bounds.size.z>80 or not bounds.intersects(AABB(Vector3(-38,-1,52),Vector3(80,15,64))):continue
		if not mesh_node.visible or not mesh_node.mesh:continue
		var material: Material=mesh_node.get_active_material(0)
		if material is BaseMaterial3D and material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:continue
		var scaling:=mesh_node.global_basis.get_scale().abs()
		var cache_key: String=str(mesh_node.mesh.get_rid())+str(scaling)
		var mesh: ArrayMesh
		if mesh_cache.has(cache_key):mesh=mesh_cache[cache_key]
		else:
			mesh=ArrayMesh.new()
			for surface in mesh_node.mesh.get_surface_count():
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh_node.mesh.surface_get_arrays(surface))
				mesh.surface_set_material(surface,portable_material(context,mesh_node.mesh.surface_get_material(surface)))
			var texel: float=float(arguments.get("texel_size",0.35))
			assert(mesh.lightmap_unwrap(Transform3D(Basis.from_scale(scaling),Vector3.ZERO),texel)==OK,str(mesh_node.get_path()))
			var mesh_path: String=context.output_path("meshes/uv2-%04d.tres"%mesh_cache.size())
			assert(ResourceSaver.save(mesh,mesh_path)==OK)
			mesh.take_over_path(ProjectSettings.localize_path(mesh_path))
			mesh_cache[cache_key]=mesh
		var replacement:=MeshInstance3D.new();replacement.name="BakedAsset%04d"%prepared_meshes
		copies.add_child(replacement);replacement.global_transform=mesh_node.global_transform
		replacement.mesh=mesh;replacement.material_override=portable_material(context,mesh_node.material_override)
		replacement.gi_mode=GeometryInstance3D.GI_MODE_STATIC
		hidden_paths.append(str(world.get_path_to(mesh_node)));mesh_node.hide()
		prepared_meshes+=1
	# Limited courtyard patch receives indirect light; full-map ground does not inflate the atlas.
	var floor: MeshInstance3D=PRESENTATION.box(copies,"BakedCourtyardFloor",Vector3(0,-0.004,84),Vector3(26,0.08,56),load("res://assets/shooter/serious/materials/asphalt.tres"))
	floor.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var yard_material: StandardMaterial3D=floor.material_override.duplicate()
	yard_material.normal_enabled=false;yard_material.metallic_specular=0.12;yard_material.roughness=0.98
	floor.material_override=yard_material
	var floor_mesh:=ArrayMesh.new();floor_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,floor.mesh.get_mesh_arrays())
	assert(floor_mesh.lightmap_unwrap(floor.global_transform,0.40)==OK)
	var floor_path: String=context.output_path("meshes/courtyard.tres")
	assert(ResourceSaver.save(floor_mesh,floor_path)==OK)
	floor_mesh.take_over_path(ProjectSettings.localize_path(floor_path))
	floor.mesh=floor_mesh;floor.gi_mode=GeometryInstance3D.GI_MODE_STATIC
	var gi:=LightmapGI.new();gi.name="SectorIndirectLight";world.add_child(gi)
	gi.quality=LightmapGI.BAKE_QUALITY_MEDIUM;gi.bounces=2;gi.max_texture_size=2048
	gi.generate_probes_subdiv=LightmapGI.GENERATE_PROBES_SUBDIV_8
	gi.environment_mode=LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR
	gi.environment_custom_color=Color("a5b7c2");gi.environment_custom_energy=0.65
	gi.use_denoiser=true
	world.set_meta("visual_stats",stats)
	world.set_meta("presentation_details",details)
	world.set_meta("canonical_sha256",FileAccess.get_sha256("res://maps/nexo_combat_01.json"))
	world.set_meta("baked_mesh_count",prepared_meshes+1)
	world.set_meta("baked_replaced_paths",hidden_paths)
	assign_owner(world,world)
	context.register("sector_world",world)
	var packed:=PackedScene.new();assert(packed.pack(world)==OK)
	context.register("sector_scene",packed)
	# Bake only this sector. Node paths and transforms match the runtime scene exactly.
	var bake_world:=Node3D.new();bake_world.name="SectorBake";context.root.add_child(bake_world)
	bake_world.add_child(copies.duplicate())
	for node in world.find_children("*","Light3D",true,false):
		var light: Light3D=node.duplicate();light.global_transform=node.global_transform;bake_world.add_child(light)
	for environment in world.find_children("*","WorldEnvironment",true,false):bake_world.add_child(environment.duplicate())
	bake_world.add_child(gi.duplicate())
	assign_owner(bake_world,bake_world)
	var bake_packed:=PackedScene.new();assert(bake_packed.pack(bake_world)==OK)
	context.register("sector_bake",bake_packed)
	return {"prepared_meshes":prepared_meshes+1,"visual_stats":stats,"details":details,"canonical_sha256":world.get_meta("canonical_sha256")}

func assign_owner(node: Node, owner_: Node) -> void:
	for child in node.get_children():
		child.owner=owner_
		if child.scene_file_path.is_empty():assign_owner(child,owner_)

func portable_material(context: SceneTree, source: Material) -> Material:
	if not source:return null
	if material_cache.has(source.get_rid()):return material_cache[source.get_rid()]
	var material:=source.duplicate() as Material
	if material is BaseMaterial3D:
		for parameter in [BaseMaterial3D.TEXTURE_ALBEDO,BaseMaterial3D.TEXTURE_NORMAL,BaseMaterial3D.TEXTURE_ROUGHNESS,BaseMaterial3D.TEXTURE_METALLIC,BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION,BaseMaterial3D.TEXTURE_EMISSION]:
			var texture: Texture2D=material.get_texture(parameter)
			if not texture or (not texture.resource_path.is_empty() and not "::" in texture.resource_path):continue
			if not texture_cache.has(texture.get_rid()):
				var image:=texture.get_image()
				if image.is_compressed():assert(image.decompress()==OK)
				var path: String=context.output_path("textures/model-%03d.png"%texture_cache.size())
				assert(image.save_png(path)==OK)
				var copy:=ImageTexture.create_from_image(image);copy.take_over_path(ProjectSettings.localize_path(path))
				texture_cache[texture.get_rid()]=copy
			material.set_texture(parameter,texture_cache[texture.get_rid()])
	var material_path: String=context.output_path("materials/material-%03d.tres"%material_cache.size())
	assert(ResourceSaver.save(material,material_path)==OK)
	material.take_over_path(ProjectSettings.localize_path(material_path))
	material_cache[source.get_rid()]=material
	return material
