extends SceneTree

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")
const ARMY_RUNTIME = preload("res://src/map/map_army_runtime_probe_v2.gd")
const MAP_PATH := "res://maps/competitive_lab_01.json"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var map_data: Dictionary = MAP_CONTRACT.load_file(MAP_PATH)
    if map_data.is_empty():
        push_error("MAP_FORGE_ARMY_RUNTIME: failed to load canonical map")
        quit(40)
        return

    var telemetry: Dictionary = await ARMY_RUNTIME.run(self, map_data, [10, 50, 100, 500])
    if not bool(telemetry.get("ok", false)):
        push_error("MAP_FORGE_ARMY_RUNTIME: executable crowd probe failed: %s" % JSON.stringify(telemetry))
        quit(41)
        return

    var sync: Dictionary = telemetry.get("synchronization", {})
    if not bool(sync.get("ok", false)) or int(sync.get("iteration", 0)) <= 0:
        push_error("MAP_FORGE_ARMY_RUNTIME: navigation map did not synchronize")
        quit(42)
        return

    var routes: Dictionary = telemetry.get("routes", {})
    if routes.size() < 3:
        push_error("MAP_FORGE_ARMY_RUNTIME: expected at least three tested routes")
        quit(43)
        return

    for route_id in routes.keys():
        var route: Dictionary = routes[route_id]
        if not bool(route.get("ok", false)):
            push_error("MAP_FORGE_ARMY_RUNTIME: route path unavailable: %s" % String(route_id))
            quit(44)
            return
        var loads: Dictionary = route.get("loads", {})
        for expected in [10, 50, 100, 500]:
            var state: Dictionary = loads.get(str(expected), {})
            if state.is_empty():
                push_error("MAP_FORGE_ARMY_RUNTIME: missing load %d for %s" % [expected, String(route_id)])
                quit(45)
                return
            if int(state.get("completed_agents", 0)) != expected or int(state.get("failed_agents", 0)) != 0:
                push_error("MAP_FORGE_ARMY_RUNTIME: incomplete traversal for %s load %d" % [String(route_id), expected])
                quit(46)
                return
            if int(state.get("avoidance_callback_count", 0)) <= 0:
                push_error("MAP_FORGE_ARMY_RUNTIME: no avoidance callbacks for %s load %d" % [String(route_id), expected])
                quit(47)
                return
            if float(state.get("throughput_agents_per_sim_second", 0.0)) <= 0.0:
                push_error("MAP_FORGE_ARMY_RUNTIME: invalid throughput for %s load %d" % [String(route_id), expected])
                quit(48)
                return
            if float(state.get("p95_travel_seconds", 0.0)) <= 0.0:
                push_error("MAP_FORGE_ARMY_RUNTIME: invalid p95 travel time for %s load %d" % [String(route_id), expected])
                quit(49)
                return

    var output_path := ARMY_RUNTIME.export_telemetry(map_data, telemetry)
    if output_path.is_empty() or not FileAccess.file_exists(output_path):
        push_error("MAP_FORGE_ARMY_RUNTIME: telemetry export failed")
        quit(50)
        return

    print("MAP_FORGE_ARMY_RUNTIME_OK routes=%d sync_iteration=%d telemetry=%s" % [routes.size(), int(sync.get("iteration", 0)), output_path])
    print("MAP_FORGE_ARMY_RUNTIME_TELEMETRY=%s" % JSON.stringify(telemetry))
    quit(0)
