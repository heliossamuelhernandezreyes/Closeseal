@tool
class_name CloseSealMapNavigationProbe
extends RefCounted

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")

static func probe(tree: SceneTree, navigation_mesh: NavigationMesh, map_data: Dictionary, loads: Array[int] = [10, 50, 100, 500]) -> Dictionary:
    if navigation_mesh == null:
        return {"ok": false, "error": "navigation mesh is null"}
    var navigation_cfg: Dictionary = map_data.get("authoring", {}).get("navigation", {})
    var probe_speed: float = maxf(float(navigation_cfg.get("probe_speed", 4.0)), 0.1)
    var traffic_cell_size: float = maxf(float(navigation_cfg.get("traffic_cell_size", 1.0)), 0.1)
    var agent_radius: float = maxf(float(navigation_cfg.get("agent_radius", 0.45)), 0.01)

    var server := NavigationServer3D
    var map_rid: RID = server.map_create()
    var region_rid: RID = server.region_create()
    server.map_set_cell_size(map_rid, maxf(float(navigation_cfg.get("cell_size", 0.25)), 0.01))
    server.map_set_cell_height(map_rid, maxf(float(navigation_cfg.get("cell_height", 0.25)), 0.01))
    server.map_set_use_edge_connections(map_rid, true)
    server.map_set_edge_connection_margin(map_rid, maxf(float(navigation_cfg.get("edge_connection_margin", 1.0)), 0.01))
    server.map_set_active(map_rid, true)
    server.region_set_enabled(region_rid, true)
    server.region_set_map(region_rid, map_rid)
    server.region_set_navigation_mesh(region_rid, navigation_mesh)
    server.map_force_update(map_rid)

    var synchronization: Dictionary = await _wait_for_map_sync(tree, map_rid, 12)
    if not bool(synchronization.get("ok", false)):
        _free_navigation_region(server, region_rid, map_rid)
        return {
            "ok": false,
            "error": "navigation map did not synchronize",
            "synchronization": synchronization
        }

    var query_results: Dictionary = {}
    var traffic_cells: Dictionary = {}
    var all_queryable := true
    var route_count := 0
    var queryable_count := 0
    var total_path_length := 0.0
    var max_endpoint_snap := 0.0

    for route_value in map_data.get("routes", []):
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var points: Array = route.get("points", [])
        if points.size() < 2:
            continue
        route_count += 1
        var route_id := String(route.get("id", "route"))
        var requested_start: Vector3 = MAP_CONTRACT.vec3_from(points[0])
        var requested_finish: Vector3 = MAP_CONTRACT.vec3_from(points[points.size() - 1])
        var start: Vector3 = server.map_get_closest_point(map_rid, requested_start)
        var finish: Vector3 = server.map_get_closest_point(map_rid, requested_finish)
        var start_snap_distance := requested_start.distance_to(start)
        var finish_snap_distance := requested_finish.distance_to(finish)
        max_endpoint_snap = maxf(max_endpoint_snap, maxf(start_snap_distance, finish_snap_distance))
        var physical_path: PackedVector3Array = server.map_get_path(map_rid, start, finish, true)
        var queryable := physical_path.size() >= 2
        if not queryable:
            all_queryable = false
        else:
            queryable_count += 1
        var physical_length := _path_length(physical_path)
        var semantic_length := _semantic_route_length(points)
        total_path_length += physical_length
        var detour_ratio := 0.0
        if semantic_length > 0.001:
            detour_ratio = physical_length / semantic_length
        var load_states: Dictionary = {}
        var route_width := maxf(float(route.get("width", 0.0)), agent_radius * 2.0)
        var unit_diameter := agent_radius * 2.0
        var columns := maxi(1, int(floor(route_width / unit_diameter)))
        for load in loads:
            var rows := int(ceil(float(load) / float(columns)))
            var estimated_seconds := 0.0
            if queryable:
                estimated_seconds = physical_length / probe_speed
            load_states[str(load)] = {
                "columns": columns,
                "rows": rows,
                "estimated_travel_seconds": estimated_seconds,
                "derived_queue_depth_m": float(rows) * unit_diameter
            }
            if queryable:
                _accumulate_path_heat(traffic_cells, physical_path, traffic_cell_size, load)
        query_results[route_id] = {
            "queryable": queryable,
            "waypoints": physical_path.size(),
            "semantic_length_m": semantic_length,
            "physical_length_m": physical_length,
            "detour_ratio": detour_ratio,
            "estimated_travel_seconds": physical_length / probe_speed if queryable else 0.0,
            "requested_start": [requested_start.x, requested_start.y, requested_start.z],
            "requested_finish": [requested_finish.x, requested_finish.y, requested_finish.z],
            "snapped_start": [start.x, start.y, start.z],
            "snapped_finish": [finish.x, finish.y, finish.z],
            "start_snap_distance_m": start_snap_distance,
            "finish_snap_distance_m": finish_snap_distance,
            "loads": load_states,
            "path": _encode_path(physical_path)
        }

    _free_navigation_region(server, region_rid, map_rid)

    var max_cell_load := 0
    var total_cell_load := 0
    for value in traffic_cells.values():
        var cell_load := int(value)
        max_cell_load = maxi(max_cell_load, cell_load)
        total_cell_load += cell_load

    return {
        "ok": route_count > 0 and all_queryable,
        "probe_kind": "physical_path_queries",
        "route_count": route_count,
        "queryable_routes": queryable_count,
        "all_queryable": all_queryable,
        "probe_speed_mps": probe_speed,
        "loads": loads,
        "query_results": query_results,
        "traffic_grid": {
            "cell_size": traffic_cell_size,
            "visited_cells": traffic_cells.size(),
            "max_cell_load": max_cell_load,
            "total_cell_load": total_cell_load,
            "cells": traffic_cells
        },
        "total_physical_path_length_m": total_path_length,
        "max_endpoint_snap_distance_m": max_endpoint_snap,
        "synchronization": synchronization,
        "claim_boundary": "Physical NavigationServer3D path queries plus derived traffic load; not dynamic crowd simulation or avoidance performance."
    }

static func _wait_for_map_sync(tree: SceneTree, map_rid: RID, max_frames: int) -> Dictionary:
    var initial_iteration := NavigationServer3D.map_get_iteration_id(map_rid)
    for frame in range(1, max_frames + 1):
        await tree.physics_frame
        var iteration := NavigationServer3D.map_get_iteration_id(map_rid)
        if iteration > 0:
            return {
                "ok": true,
                "initial_iteration": initial_iteration,
                "iteration": iteration,
                "physics_frames_waited": frame
            }
    return {
        "ok": false,
        "initial_iteration": initial_iteration,
        "iteration": NavigationServer3D.map_get_iteration_id(map_rid),
        "physics_frames_waited": max_frames
    }

static func _free_navigation_region(server: Object, region_rid: RID, map_rid: RID) -> void:
    server.region_set_map(region_rid, RID())
    server.free_rid(region_rid)
    server.free_rid(map_rid)

static func export_telemetry(map_data: Dictionary, telemetry: Dictionary) -> String:
    var map_id := String(map_data.get("id", "map"))
    var directory := "res://maps/generated"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
    var path := "%s/%s_navigation_telemetry.json" % [directory, map_id]
    var payload: Dictionary = telemetry.duplicate(true)
    payload["schema_version"] = 1
    payload["map_id"] = map_id
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return ""
    file.store_string(JSON.stringify(payload, "  ", false) + "\n")
    file.close()
    return path

static func format_report(telemetry: Dictionary) -> String:
    if not bool(telemetry.get("ok", false)):
        var error := String(telemetry.get("error", "physical navigation probe failed"))
        return "[color=red][b]Physical navigation probe failed[/b][/color]\n%s\nQueryable routes: %d / %d" % [error, int(telemetry.get("queryable_routes", 0)), int(telemetry.get("route_count", 0))]
    var sync: Dictionary = telemetry.get("synchronization", {})
    var lines: Array[String] = [
        "[b]Physical Navigation Probe[/b]",
        "NavigationServer3D queryable routes: %d / %d" % [int(telemetry.get("queryable_routes", 0)), int(telemetry.get("route_count", 0))],
        "Map synchronized at iteration %d after %d physics frame(s)" % [int(sync.get("iteration", 0)), int(sync.get("physics_frames_waited", 0))]
    ]
    var results: Dictionary = telemetry.get("query_results", {})
    for route_id in results.keys():
        var state: Dictionary = results[route_id]
        lines.append("• %s: %.2fm physical / %.2fm semantic • %.2fs • %d waypoints • snap %.3fm/%.3fm" % [String(route_id), float(state.get("physical_length_m", 0.0)), float(state.get("semantic_length_m", 0.0)), float(state.get("estimated_travel_seconds", 0.0)), int(state.get("waypoints", 0)), float(state.get("start_snap_distance_m", 0.0)), float(state.get("finish_snap_distance_m", 0.0))])
    var grid: Dictionary = telemetry.get("traffic_grid", {})
    lines.append("")
    lines.append("[b]Derived Traffic Heatmap[/b]")
    lines.append("• Cells visited: %d" % int(grid.get("visited_cells", 0)))
    lines.append("• Peak accumulated load: %d" % int(grid.get("max_cell_load", 0)))
    lines.append("• Probe loads: %s" % str(telemetry.get("loads", [])))
    lines.append("")
    lines.append("[color=gray]%s[/color]" % String(telemetry.get("claim_boundary", "")))
    return "\n".join(lines)

static func _semantic_route_length(points: Array) -> float:
    var length := 0.0
    for i in range(1, points.size()):
        length += MAP_CONTRACT.vec3_from(points[i - 1]).distance_to(MAP_CONTRACT.vec3_from(points[i]))
    return length

static func _path_length(path: PackedVector3Array) -> float:
    var length := 0.0
    for i in range(1, path.size()):
        length += path[i - 1].distance_to(path[i])
    return length

static func _encode_path(path: PackedVector3Array) -> Array:
    var encoded: Array = []
    for point in path:
        encoded.append([point.x, point.y, point.z])
    return encoded

static func _accumulate_path_heat(cells: Dictionary, path: PackedVector3Array, cell_size: float, weight: int) -> void:
    for i in range(1, path.size()):
        var a := path[i - 1]
        var b := path[i]
        var segment_length := a.distance_to(b)
        var steps := maxi(1, int(ceil(segment_length / cell_size)))
        for step in range(steps + 1):
            var t := float(step) / float(steps)
            var point := a.lerp(b, t)
            var cx := int(floor(point.x / cell_size))
            var cz := int(floor(point.z / cell_size))
            var key := "%d:%d" % [cx, cz]
            cells[key] = int(cells.get(key, 0)) + weight
