extends SceneTree
const BRUSH = preload("res://src/map/map_terrain_brush.gd")

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var file := FileAccess.open("res://tests/fixtures/terrain_brush_parity.json", FileAccess.READ)
    var fixture: Dictionary = JSON.parse_string(file.get_as_text())
    var actual: Dictionary = fixture["initial"]
    for operation in fixture["operations"]:
        actual = BRUSH.apply(actual, operation)
    var field: Dictionary = actual["authoring"]["heightfields"][0]
    var expected: Dictionary = fixture["expected"]["authoring"]["heightfields"][0]
    for index in range(field["heights"].size()):
        if absf(float(field["heights"][index]) - float(expected["heights"][index])) > 0.000001:
            push_error("BRUSH_PARITY: height mismatch")
            quit(1)
            return
    if field["paint"] != expected["paint"] or field["holes"] != expected["holes"]:
        push_error("BRUSH_PARITY: paint or holes mismatch")
        quit(2)
        return
    var packed: PackedScene = load("res://maps/generated/environment_interior_lab_authoring.tscn")
    var scene: Node3D = packed.instantiate()
    root.add_child(scene)
    await physics_frame
    var region: NavigationRegion3D = scene.get_node("NavigationBakeTarget")
    var map_rid := region.get_navigation_map()
    for _attempt in range(60):
        await physics_frame
        if NavigationServer3D.map_get_iteration_id(map_rid) > 0:
            break
    var from := NavigationServer3D.map_get_closest_point(map_rid, Vector3(-9, 0, 0))
    var to := NavigationServer3D.map_get_closest_point(map_rid, Vector3(9, 0, 0))
    var path := NavigationServer3D.map_get_path(map_rid, from, to, true)
    var centre := NavigationServer3D.map_get_closest_point(map_rid, Vector3.ZERO)
    print("WORLD_NAVIGATION_QUERY " + JSON.stringify({"path": Array(path), "centre": centre, "iteration": NavigationServer3D.map_get_iteration_id(map_rid), "editor": Engine.is_editor_hint()}))
    if path.size() <= 2 or Vector2(centre.x, centre.z).length() < 2.2:
        push_error("WORLD_NAVIGATION: path did not avoid the actual central collider")
        quit(3)
        return
    var query := PhysicsRayQueryParameters3D.create(Vector3(0, 10, 0), Vector3(0, -2, 0))
    var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty() or String(hit["collider"].get_parent().name) != "centre_pillar":
        push_error("WORLD_COLLISION: authored collider missing")
        quit(4)
        return
    var output := {"ok": true, "brush_modes": fixture["operations"].size(), "path_points": path.size(), "centre_obstacle_clearance": Vector2(centre.x, centre.z).length(), "collision_hit": "centre_pillar"}
    var evidence := FileAccess.open("res://.mapforge/environment-probe.json", FileAccess.WRITE)
    evidence.store_string(JSON.stringify(output, "  "))
    print("MAP_FORGE_ENVIRONMENT_PROBE_OK " + JSON.stringify(output))
    scene.free()
    quit(0)
