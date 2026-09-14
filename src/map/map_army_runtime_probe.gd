@tool
class_name CloseSealMapArmyRuntimeProbe
extends RefCounted

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")
const NAV_RUNTIME = preload("res://src/map/map_navigation_runtime.gd")

class AvoidanceInbox:
    extends RefCounted
    var safe_velocity := Vector3.ZERO
    var callback_count := 0

    func accept(value: Vector3) -> void:
        safe_velocity = value
        callback_count += 1

static func run(tree: SceneTree, map_data: Dictionary, loads: Array[int] = [10, 50, 100, 500]) -> Dictionary:
    var compiled: Dictionary = NAV_RUNTIME.compile_route_surface(map_data)
    if not bool(compiled.get("ok", false)):
        return {"ok": false, "error": "navigation surface compilation failed"}
    var navigation_mesh: NavigationMesh = compiled.get("navigation_mesh")
    if navigation_mesh == null or navigation_mesh.get_polygon_count() <= 0:
        return {"ok": false, "error": "compiled navigation mesh is empty"}

    var cfg: Dictionary = map_data.get("authoring", {}).get("navigation", {})
    var map_rid: RID = _create_navigation_map(navigation_mesh, cfg)
    await tree.physics_frame
    await tree.physics_frame
    NavigationServer3D.map_force_update(map_rid)

    var route_results: Dictionary = {}
    var all_ok := true
    for route_value in map_data.get("routes", []):
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var route_id := String(route.get("id", "route"))
        var points: Array = route.get("points", [])
        if points.size() < 2:
            continue
        var requested_start: Vector3 = MAP_CONTRACT.vec3_from(points[0])
        var requested_finish: Vector3 = MAP_CONTRACT.vec3_from(points[points.size() - 1])
        var start: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, requested_start)
        var finish: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, requested_finish)
        var path: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, start, finish, true)
        if path.size() < 2:
            all_ok = false
            route_results[route_id] = {"ok": false, "error": "physical path unavailable"}
            continue
        var per_load: Dictionary = {}
        for load in loads:
            var result: Dictionary = await _simulate_load(tree, map_rid, route, path, load, cfg)
            per_load[str(load)] = result
            if not bool(result.get("ok", false)):
                all_ok = false
        route_results[route_id] = {
            "ok": true,
            "path_waypoints": path.size(),
            "path_length_m": _path_length(path),
            "loads": per_load
        }

    NavigationServer3D.free_rid(map_rid)
    return {
        "ok": all_ok and not route_results.is_empty(),
        "probe_kind": "navigation_server_avoidance_agents",
        "loads": loads,
        "routes": route_results,
        "claim_boundary": "Executable NavigationServer3D avoidance-agent flow on compiled route surfaces. It measures fixed-step synthetic crowd traversal in CI; it is not target-device frame-time performance or final gameplay AI."
    }

static func _create_navigation_map(navigation_mesh: NavigationMesh, cfg: Dictionary) -> RID:
    var map_rid: RID = NavigationServer3D.map_create()
    var region_rid: RID = NavigationServer3D.region_create()
    NavigationServer3D.map_set_cell_size(map_rid, maxf(float(cfg.get("cell_size", 0.25)), 0.01))
    NavigationServer3D.map_set_cell_height(map_rid, maxf(float(cfg.get("cell_height", 0.25)), 0.01))
    NavigationServer3D.map_set_use_edge_connections(map_rid, true)
    NavigationServer3D.map_set_edge_connection_margin(map_rid, maxf(float(cfg.get("edge_connection_margin", 1.0)), 0.01))
    NavigationServer3D.region_set_navigation_mesh(region_rid, navigation_mesh)
    NavigationServer3D.region_set_map(region_rid, map_rid)
    NavigationServer3D.map_set_active(map_rid, true)
    NavigationServer3D.map_force_update(map_rid)
    return map_rid

static func _simulate_load(tree: SceneTree, map_rid: RID, route: Dictionary, path: PackedVector3Array, load: int, cfg: Dictionary) -> Dictionary:
    var radius: float = maxf(float(cfg.get("agent_radius", 0.45)), 0.05)
    var height: float = maxf(float(cfg.get("agent_height", 1.8)), 0.1)
    var speed: float = maxf(float(cfg.get("runtime_probe_speed", cfg.get("probe_speed", 4.0))), 0.25)
    var fixed_dt: float = maxf(float(cfg.get("runtime_probe_step_seconds", 0.10)), 0.02)
    var spawn_interval: float = maxf(float(cfg.get("runtime_probe_spawn_interval_seconds", 0.20)), fixed_dt)
    var spawn_interval_steps: int = maxi(1, int(ceil(spawn_interval / fixed_dt)))
    var waypoint_distance: float = maxf(float(cfg.get("runtime_probe_waypoint_distance", 0.55)), radius)
    var target_distance: float = maxf(float(cfg.get("runtime_probe_target_distance", 0.65)), radius)
    var neighbor_distance: float = maxf(float(cfg.get("runtime_probe_neighbor_distance", radius * 5.0)), radius * 2.0)
    var max_neighbors: int = maxi(1, int(cfg.get("runtime_probe_max_neighbors", 10)))
    var max_sim_seconds: float = maxf(float(cfg.get("runtime_probe_max_seconds", 75.0)), 10.0)
    var max_steps: int = int(ceil(max_sim_seconds / fixed_dt))
    var route_width: float = maxf(float(route.get("width", radius * 2.0)), radius * 2.0)
    var footprint: float = radius * 2.0 + maxf(float(cfg.get("runtime_probe_spawn_spacing", 0.15)), 0.0)
    var columns: int = maxi(1, int(floor(route_width / footprint)))
    var launch_batch: int = columns
    var route_id := String(route.get("id", "route"))

    var states: Array[Dictionary] = []
    var created := 0
    var completed := 0
    var failed := 0
    var peak_active := 0
    var callback_count := 0
    var speed_samples := 0
    var speed_ratio_sum := 0.0
    var congested_samples := 0
    var congestion_cells: Dictionary = {}
    var travel_times: Array[float] = []
    var wall_start_usec := Time.get_ticks_usec()
    var step := 0

    while step < max_steps and completed + failed < load:
        if created < load and step % spawn_interval_steps == 0:
            var batch_count: int = mini(launch_batch, load - created)
            for slot in range(batch_count):
                var state := _spawn_agent(map_rid, path, created, slot, batch_count, radius, height, speed, neighbor_distance, max_neighbors, step)
                states.append(state)
                created += 1

        var active := 0
        for state in states:
            if bool(state.get("done", false)):
                continue
            active += 1
            var position: Vector3 = state.get("position", path[0])
            var waypoint_index: int = int(state.get("waypoint_index", 1))
            while waypoint_index < path.size() - 1 and position.distance_to(path[waypoint_index]) <= waypoint_distance:
                waypoint_index += 1
            state["waypoint_index"] = waypoint_index
            var target: Vector3 = path[waypoint_index]
            if waypoint_index >= path.size() - 1:
                target = path[path.size() - 1]
            var to_target := target - position
            to_target.y = 0.0
            var desired_velocity := Vector3.ZERO
            if to_target.length() > 0.001:
                desired_velocity = to_target.normalized() * speed
            var rid: RID = state.get("rid")
            NavigationServer3D.agent_set_position(rid, position)
            NavigationServer3D.agent_set_velocity(rid, desired_velocity)

        peak_active = maxi(peak_active, active)
        await tree.physics_frame

        for state in states:
            if bool(state.get("done", false)):
                continue
            var receiver: AvoidanceInbox = state.get("receiver")
            var safe_velocity: Vector3 = receiver.safe_velocity
            callback_count += receiver.callback_count - int(state.get("callback_count_seen", 0))
            state["callback_count_seen"] = receiver.callback_count
            var desired_speed: float = speed
            var safe_speed: float = safe_velocity.length()
            var ratio: float = clampf(safe_speed / desired_speed, 0.0, 1.5)
            speed_ratio_sum += ratio
            speed_samples += 1
            if ratio < 0.55:
                congested_samples += 1
                _accumulate_congestion_cell(congestion_cells, state.get("position", path[0]), float(cfg.get("traffic_cell_size", 1.0)))
            var position: Vector3 = state.get("position", path[0])
            var candidate := position + safe_velocity * fixed_dt
            var projected: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, candidate)
            state["distance_m"] = float(state.get("distance_m", 0.0)) + position.distance_to(projected)
            state["position"] = projected
            var rid: RID = state.get("rid")
            NavigationServer3D.agent_set_position(rid, projected)
            if projected.distance_to(path[path.size() - 1]) <= target_distance:
                state["done"] = true
                var launch_step: int = int(state.get("launch_step", step))
                var travel_seconds: float = float(step - launch_step + 1) * fixed_dt
                state["travel_seconds"] = travel_seconds
                travel_times.append(travel_seconds)
                completed += 1
                NavigationServer3D.agent_set_avoidance_callback(rid, Callable())
                NavigationServer3D.free_rid(rid)
                state["rid"] = RID()
        step += 1

    for state in states:
        if bool(state.get("done", false)):
            continue
        var rid: RID = state.get("rid")
        if rid.is_valid():
            NavigationServer3D.agent_set_avoidance_callback(rid, Callable())
            NavigationServer3D.free_rid(rid)
        failed += 1
        state["done"] = true

    travel_times.sort()
    var completion_ratio := float(completed) / float(maxi(load, 1))
    var mean_speed_ratio := speed_ratio_sum / float(maxi(speed_samples, 1))
    var congestion_ratio := float(congested_samples) / float(maxi(speed_samples, 1))
    var simulated_seconds := float(step) * fixed_dt
    var throughput := float(completed) / maxf(simulated_seconds, 0.001)
    var wall_ms := float(Time.get_ticks_usec() - wall_start_usec) / 1000.0
    var p50 := _percentile(travel_times, 0.50)
    var p95 := _percentile(travel_times, 0.95)
    var mean_travel := 0.0
    for value in travel_times:
        mean_travel += value
    if not travel_times.is_empty():
        mean_travel /= float(travel_times.size())

    return {
        "ok": completed == load and failed == 0 and callback_count > 0,
        "route_id": route_id,
        "requested_agents": load,
        "completed_agents": completed,
        "failed_agents": failed,
        "completion_ratio": completion_ratio,
        "columns": columns,
        "peak_active_agents": peak_active,
        "simulation_seconds": simulated_seconds,
        "wall_clock_ms": wall_ms,
        "throughput_agents_per_sim_second": throughput,
        "mean_travel_seconds": mean_travel,
        "p50_travel_seconds": p50,
        "p95_travel_seconds": p95,
        "mean_safe_velocity_ratio": mean_speed_ratio,
        "congested_sample_ratio": congestion_ratio,
        "avoidance_callback_count": callback_count,
        "congestion_grid": {
            "cell_size": float(cfg.get("traffic_cell_size", 1.0)),
            "visited_cells": congestion_cells.size(),
            "cells": congestion_cells
        }
    }

static func _spawn_agent(map_rid: RID, path: PackedVector3Array, index: int, slot: int, batch_count: int, radius: float, height: float, speed: float, neighbor_distance: float, max_neighbors: int, launch_step: int) -> Dictionary:
    var rid: RID = NavigationServer3D.agent_create()
    var receiver := AvoidanceInbox.new()
    NavigationServer3D.agent_set_map(rid, map_rid)
    NavigationServer3D.agent_set_avoidance_enabled(rid, true)
    NavigationServer3D.agent_set_radius(rid, radius)
    NavigationServer3D.agent_set_height(rid, height)
    NavigationServer3D.agent_set_neighbor_distance(rid, neighbor_distance)
    NavigationServer3D.agent_set_max_neighbors(rid, max_neighbors)
    NavigationServer3D.agent_set_max_speed(rid, speed)
    NavigationServer3D.agent_set_time_horizon_agents(rid, 1.0)
    NavigationServer3D.agent_set_time_horizon_obstacles(rid, 0.5)
    NavigationServer3D.agent_set_avoidance_callback(rid, Callable(receiver, "accept"))

    var forward := path[1] - path[0]
    forward.y = 0.0
    forward = forward.normalized()
    var side := Vector3(-forward.z, 0.0, forward.x)
    var centered_slot := float(slot) - float(batch_count - 1) * 0.5
    var position := path[0] + forward * (radius + 0.1) + side * centered_slot * (radius * 2.0 + 0.15)
    position = NavigationServer3D.map_get_closest_point(map_rid, position)
    NavigationServer3D.agent_set_position(rid, position)
    NavigationServer3D.agent_set_velocity_forced(rid, Vector3.ZERO)
    NavigationServer3D.agent_set_velocity(rid, forward * speed)
    return {
        "id": index,
        "rid": rid,
        "receiver": receiver,
        "position": position,
        "waypoint_index": 1,
        "launch_step": launch_step,
        "callback_count_seen": 0,
        "distance_m": 0.0,
        "done": false
    }

static func _path_length(path: PackedVector3Array) -> float:
    var result := 0.0
    for i in range(1, path.size()):
        result += path[i - 1].distance_to(path[i])
    return result

static func _percentile(values: Array[float], fraction: float) -> float:
    if values.is_empty():
        return 0.0
    var index := int(round(clampf(fraction, 0.0, 1.0) * float(values.size() - 1)))
    return values[index]

static func _accumulate_congestion_cell(cells: Dictionary, position: Vector3, cell_size_value: float) -> void:
    var cell_size := maxf(cell_size_value, 0.1)
    var cx := int(floor(position.x / cell_size))
    var cz := int(floor(position.z / cell_size))
    var key := "%d:%d" % [cx, cz]
    cells[key] = int(cells.get(key, 0)) + 1

static func export_telemetry(map_data: Dictionary, telemetry: Dictionary) -> String:
    var map_id := String(map_data.get("id", "map"))
    var directory := "res://maps/generated"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
    var path := "%s/%s_army_runtime_telemetry.json" % [directory, map_id]
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
    var lines: Array[String] = ["[b]Executable Army Flow[/b]"]
    if not bool(telemetry.get("ok", false)):
        lines.append("[color=red]At least one route/load failed to complete.[/color]")
    else:
        lines.append("[color=green]All requested route/load probes completed.[/color]")
    var routes: Dictionary = telemetry.get("routes", {})
    for route_id in routes.keys():
        var route: Dictionary = routes[route_id]
        lines.append("")
        lines.append("[b]%s[/b]" % String(route_id))
        var loads: Dictionary = route.get("loads", {})
        for load in [10, 50, 100, 500]:
            var state: Dictionary = loads.get(str(load), {})
            if state.is_empty():
                continue
            lines.append("  %3d → %d/%d complete • %.1fs p95 • %.2f agents/s • %.1f%% congestion" % [load, int(state.get("completed_agents", 0)), int(state.get("requested_agents", 0)), float(state.get("p95_travel_seconds", 0.0)), float(state.get("throughput_agents_per_sim_second", 0.0)), float(state.get("congested_sample_ratio", 0.0)) * 100.0])
    lines.append("")
    lines.append("[color=gray]%s[/color]" % String(telemetry.get("claim_boundary", "")))
    return "\n".join(lines)
