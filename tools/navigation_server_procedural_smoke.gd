extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var map_rid := NavigationServer3D.map_create()
    var region_rid := NavigationServer3D.region_create()
    NavigationServer3D.map_set_active(map_rid, true)
    NavigationServer3D.region_set_enabled(region_rid, true)
    NavigationServer3D.region_set_map(region_rid, map_rid)

    var navigation_mesh := NavigationMesh.new()
    navigation_mesh.vertices = PackedVector3Array([
        Vector3(-1.0, 0.0, 1.0),
        Vector3(1.0, 0.0, 1.0),
        Vector3(1.0, 0.0, -1.0),
        Vector3(-1.0, 0.0, -1.0),
    ])
    navigation_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
    NavigationServer3D.region_set_navigation_mesh(region_rid, navigation_mesh)

    for frame in range(1, 8):
        await physics_frame
        var iteration := NavigationServer3D.map_get_iteration_id(map_rid)
        var closest := NavigationServer3D.map_get_closest_point(map_rid, Vector3(0.5, 0.0, 0.5))
        var path := NavigationServer3D.map_get_path(map_rid, Vector3(-0.75, 0.0, 0.0), Vector3(0.75, 0.0, 0.0), true)
        print("NAV_MINIMAL frame=%d iteration=%d closest=%s path_points=%d" % [frame, iteration, str(closest), path.size()])
        if iteration > 0 and closest.distance_to(Vector3(0.5, 0.0, 0.5)) < 0.05 and path.size() >= 2:
            NavigationServer3D.region_set_map(region_rid, RID())
            NavigationServer3D.free_rid(region_rid)
            NavigationServer3D.free_rid(map_rid)
            print("NAVIGATION_SERVER_PROCEDURAL_OK")
            quit(0)
            return

    NavigationServer3D.region_set_map(region_rid, RID())
    NavigationServer3D.free_rid(region_rid)
    NavigationServer3D.free_rid(map_rid)
    push_error("NAVIGATION_SERVER_PROCEDURAL_FAIL")
    quit(60)
