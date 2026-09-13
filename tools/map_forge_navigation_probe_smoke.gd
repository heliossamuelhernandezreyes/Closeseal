extends SceneTree

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")
const NAV_RUNTIME = preload("res://src/map/map_navigation_runtime.gd")
const NAV_PROBE = preload("res://src/map/map_navigation_probe.gd")
const MAP_PATH := "res://maps/competitive_lab_01.json"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var map_data: Dictionary = MAP_CONTRACT.load_file(MAP_PATH)
    if map_data.is_empty():
        push_error("MAP_FORGE_NAV_PROBE: failed to load canonical map")
        quit(30)
        return

    var routes: Array = map_data.get("routes", [])
    for route_value in routes:
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var isolated_map: Dictionary = map_data.duplicate(true)
        isolated_map["routes"] = [route.duplicate(true)]
        var isolated_compiled: Dictionary = NAV_RUNTIME.compile_route_surface(isolated_map)
        var isolated_mesh: NavigationMesh = isolated_compiled.get("navigation_mesh")
        var isolated_telemetry: Dictionary = await NAV_PROBE.probe(self, isolated_mesh, isolated_map, [10])
        print("MAP_FORGE_ROUTE_ISOLATION id=%s polygons=%d vertices=%d ok=%s telemetry=%s" % [String(route.get("id", "route")), int(isolated_compiled.get("polygons", 0)), int(isolated_compiled.get("vertices", 0)), str(isolated_telemetry.get("ok", false)), JSON.stringify(isolated_telemetry)])
        if not bool(isolated_telemetry.get("ok", false)):
            push_error("MAP_FORGE_NAV_PROBE: isolated compiled route failed: %s" % String(route.get("id", "route")))
            quit(31)
            return

    var compiled: Dictionary = NAV_RUNTIME.compile_route_surface(map_data)
    if not bool(compiled.get("ok", false)):
        push_error("MAP_FORGE_NAV_PROBE: route surface compilation failed")
        quit(32)
        return
    var navmesh: NavigationMesh = compiled.get("navigation_mesh")
    if navmesh == null or navmesh.get_polygon_count() <= 0:
        push_error("MAP_FORGE_NAV_PROBE: compiled navmesh has no polygons")
        quit(33)
        return
    var telemetry: Dictionary = await NAV_PROBE.probe(self, navmesh, map_data)
    if not bool(telemetry.get("ok", false)):
        push_error("MAP_FORGE_NAV_PROBE: at least one semantic route is not physically queryable: %s" % JSON.stringify(telemetry))
        quit(34)
        return
    if int(telemetry.get("route_count", 0)) < 3 or int(telemetry.get("queryable_routes", 0)) != int(telemetry.get("route_count", 0)):
        push_error("MAP_FORGE_NAV_PROBE: route query coverage incomplete")
        quit(35)
        return
    var synchronization: Dictionary = telemetry.get("synchronization", {})
    if not bool(synchronization.get("ok", false)) or int(synchronization.get("iteration", 0)) <= 0:
        push_error("MAP_FORGE_NAV_PROBE: NavigationServer map was not synchronized")
        quit(36)
        return
    var loads: Array = telemetry.get("loads", [])
    for expected in [10, 50, 100, 500]:
        if not loads.has(expected):
            push_error("MAP_FORGE_NAV_PROBE: missing load %d" % expected)
            quit(37)
            return
    var grid: Dictionary = telemetry.get("traffic_grid", {})
    if int(grid.get("visited_cells", 0)) <= 0 or int(grid.get("total_cell_load", 0)) <= 0:
        push_error("MAP_FORGE_NAV_PROBE: traffic heatmap is empty")
        quit(38)
        return
    var results: Dictionary = telemetry.get("query_results", {})
    for route_id in results.keys():
        var route: Dictionary = results[route_id]
        var ratio := float(route.get("detour_ratio", 0.0))
        if ratio < 0.85 or ratio > 1.20:
            push_error("MAP_FORGE_NAV_PROBE: semantic/physical route divergence too large for %s: %.3f" % [String(route_id), ratio])
            quit(39)
            return
        if float(route.get("start_snap_distance_m", 999.0)) > 0.05 or float(route.get("finish_snap_distance_m", 999.0)) > 0.05:
            push_error("MAP_FORGE_NAV_PROBE: endpoint snap unexpectedly large for %s" % String(route_id))
            quit(40)
            return
    var telemetry_path := NAV_PROBE.export_telemetry(map_data, telemetry)
    if telemetry_path.is_empty() or not FileAccess.file_exists(telemetry_path):
        push_error("MAP_FORGE_NAV_PROBE: telemetry export failed")
        quit(41)
        return
    print("MAP_FORGE_PHYSICAL_NAVIGATION_OK routes=%d cells=%d sync_iteration=%d telemetry=%s" % [int(telemetry.get("route_count", 0)), int(grid.get("visited_cells", 0)), int(synchronization.get("iteration", 0)), telemetry_path])
    print("MAP_FORGE_PHYSICAL_NAVIGATION_TELEMETRY=%s" % JSON.stringify(telemetry))
    quit(0)
