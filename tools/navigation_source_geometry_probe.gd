extends SceneTree

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")
const NAV_RUNTIME = preload("res://src/map/map_navigation_runtime.gd")
const MAP_PATH := "res://maps/competitive_lab_01.json"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var map_data: Dictionary = MAP_CONTRACT.load_file(MAP_PATH)
    var route: Dictionary = map_data.get("routes", [])[0]
    var isolated: Dictionary = map_data.duplicate(true)
    isolated["routes"] = [route]
    var source_result: Dictionary = NAV_RUNTIME.build_route_source_geometry(isolated, isolated.get("authoring", {}).get("navigation", {}))
    var source: NavigationMeshSourceGeometryData3D = source_result.get("source_geometry")
    print("NAV_SOURCE_PROBE result=%s triangles=%d vertices=%d indices=%d" % [JSON.stringify(source_result.get("diagnostics", {})), int(source_result.get("source_triangles", 0)), source.get_vertices().size(), source.get_indices().size()])
    var source_vertices = source.get_vertices()
    var source_indices: PackedInt32Array = source.get_indices()
    for i in range(source_vertices.size()):
        print("NAV_SOURCE_VERTEX i=%d value=%s" % [i, str(source_vertices[i])])
    for i in range(0, source_indices.size(), 3):
        print("NAV_SOURCE_TRIANGLE i=%d indices=%d,%d,%d" % [i / 3, source_indices[i], source_indices[i + 1], source_indices[i + 2]])
    var compiled: Dictionary = NAV_RUNTIME.compile_route_surface(isolated)
    var mesh: NavigationMesh = compiled.get("navigation_mesh")
    print("NAV_BAKED_RESULT polygons=%d vertices=%d" % [mesh.get_polygon_count(), mesh.vertices.size()])
    for i in range(mesh.vertices.size()):
        print("NAV_BAKED_VERTEX i=%d value=%s" % [i, str(mesh.vertices[i])])
    for i in range(mesh.get_polygon_count()):
        print("NAV_BAKED_POLYGON i=%d value=%s" % [i, str(mesh.get_polygon(i))])
    print("NAV_SOURCE_PROBE_OK")
    quit(0)
