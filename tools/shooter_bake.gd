extends SceneTree
const VISUALS = preload("res://src/prototype/map_visual_kit.gd")

func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/nexo_combat_01.json"))
	var stats: Dictionary = VISUALS.new(world, data).build()
	assert(stats.errors.is_empty(), str(stats))
	await process_frame
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.agent_radius = 0.45
	mesh.agent_height = 1.9
	mesh.agent_max_climb = 0.35
	mesh.agent_max_slope = 40
	mesh.cell_size = 0.4
	mesh.cell_height = 0.2
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, world)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	assert(mesh.get_polygon_count() > 0)
	var result := ResourceSaver.save(mesh, "res://assets/shooter/combat_navigation.tres")
	assert(result == OK)
	print("SHOOTER_BAKE_OK " + JSON.stringify({"polygons": mesh.get_polygon_count(), "vertices": mesh.vertices.size(), "visual_stats": stats}))
	world.queue_free()
	await process_frame
	quit(0)
