extends RefCounted
## Reopen a verified scene, replay InputEvents, observe completed physics ticks.

func run(context, arguments: Dictionary) -> Dictionary:
    var session: Dictionary = arguments["session"]
    var world: Node3D = context.object(String(arguments["world"]))
    var actor: Node = world.get_node_or_null(NodePath(session["actor"]))
    if actor == null or not actor.has_signal("playtest_tick") or not actor.has_method("playtest_snapshot") or not actor.has_method("begin_playtest") or not actor.has_method("end_playtest"):
        return {"ok": false, "error": "actor lacks playtest tick/snapshot lifecycle interface"}
    for command in session["commands"]:
        for action in command.get("actions", {}):
            if not InputMap.has_action(action):
                return {"ok": false, "error": "unknown InputMap action: " + String(action)}
        if command.has("capture") and not world.get_node_or_null(NodePath(command["capture"])) is Camera3D:
            return {"ok": false, "error": "capture requires an existing scene Camera3D"}
    seed(int(session.get("seed", 0)))
    for _frame in range(8): await context.process_frame
    var region: NavigationRegion3D = world.get_node_or_null("Navigation")
    var navigation := {"available": false}
    if region != null:
        NavigationServer3D.map_set_cell_size(region.get_navigation_map(), region.navigation_mesh.cell_size)
        NavigationServer3D.map_set_cell_height(region.get_navigation_map(), region.navigation_mesh.cell_height)
        region.bake_navigation_mesh(false)
        NavigationServer3D.map_force_update(region.get_navigation_map())
        for _frame in range(3): await context.physics_frame
        var target: Node3D = world.get_node_or_null("Navigation/Workshop/Terminal")
        if target != null:
            var start: Vector3 = actor.global_position
            var finish: Vector3 = target.global_position
            var route := NavigationServer3D.map_get_path(region.get_navigation_map(), start, finish, true)
            navigation = {"available": true, "polygons": region.navigation_mesh.get_polygon_count(),
                          "path_points": route.size(), "reaches_terminal": route.size() > 1 and route[-1].distance_to(finish) < 2.0}
    var prior_pause: bool = context.paused
    var held: Dictionary = {}
    var checkpoints: Array = []
    var captures: Array = []
    var passed := true
    var trace := FileAccess.open(context.output_path("playtest/trace.jsonl"), FileAccess.WRITE)
    if trace == null: return {"ok": false, "error": "cannot save playtest trace"}
    actor.call("begin_playtest")
    for command in session["commands"]:
        context.paused = false
        _release(held)
        held = command.get("actions", {}).duplicate()
        for action in held: _event(action, float(held[action]))
        actor.set_physics_process(true)
        var snapshot: Dictionary = {}
        for _frame in range(int(command["frames"])):
            snapshot = await Signal(actor, "playtest_tick")
            trace.store_line(JSON.stringify({"command": command["id"], "input": held, "state": snapshot}))
        actor.set_physics_process(false)
        context.paused = true
        var checks := _expect(snapshot, command.get("expect", {}))
        var checkpoint := {"id": command["id"], "state": snapshot, "checks": checks, "passed": checks["passed"]}
        checkpoints.append(checkpoint)
        _write(context.output_path("playtest/checkpoint.json"), checkpoint)
        if command.has("capture"):
            var camera: Camera3D = world.get_node(command["capture"])
            var path: String = context.output_path("playtest/" + String(command["id"]) + ".png")
            context.root.size = Vector2i(1280, 720)
            camera.make_current()
            await context.process_frame
            await context.process_frame
            await RenderingServer.frame_post_draw
            if context.root.get_texture().get_image().save_png(path) != OK:
                _release(held)
                actor.call("end_playtest")
                context.paused = prior_pause
                return {"ok": false, "error": "playtest capture failed"}
            captures.append({"checkpoint": command["id"], "camera": command["capture"], "path": path,
                             "physics_tick": snapshot["tick"]})
        if not checks["passed"]:
            passed = false
            if session.get("stop_on_failure", true): break
    _release(held)
    actor.call("end_playtest")
    context.paused = prior_pause
    # Leave the actor's tick signal stack before the worker frees the reopened scene.
    await context.process_frame
    trace.flush()
    trace.close()
    var final_state: Dictionary = actor.call("playtest_snapshot")
    var report := {"ok": true, "passed": passed, "session_id": session["id"], "seed": session.get("seed", 0),
                   "physics_hz": Engine.physics_ticks_per_second, "physics_frames": final_state["tick"],
                   "checkpoints": checkpoints, "final_state": final_state, "captures": captures,
                   "navigation": navigation, "input_method": "Input.parse_input_event(InputEventAction)",
                   "input_released": _released(session),
                   "source_scene_reopened": true, "scope": "instrumented fixture, bounded batch input replay; no cross-platform determinism/device FPS claim"}
    _write(context.output_path("playtest/report.json"), report)
    print("ARCONT_PLAYTEST_SESSION " + JSON.stringify({"passed": passed, "frames": final_state["tick"]}))
    return report

func _event(action: String, strength: float) -> void:
    var event := InputEventAction.new()
    event.action = action
    event.pressed = strength > 0
    event.strength = strength
    Input.parse_input_event(event)
    # Apply the event before the next measured tick, including release while paused.
    Input.flush_buffered_events()

func _release(actions: Dictionary) -> void:
    for action in actions: _event(action, 0)

func _released(session: Dictionary) -> bool:
    for command in session["commands"]:
        for action in command.get("actions", {}):
            if Input.is_action_pressed(action): return false
    return true

func _expect(state: Dictionary, expected: Dictionary) -> Dictionary:
    var result := {"passed": true}
    if expected.has("position"):
        var actual: Array = state["position"]
        var target: Array = expected["position"]
        var distance := Vector3(actual[0], actual[1], actual[2]).distance_to(Vector3(target[0], target[1], target[2]))
        result["position_distance_m"] = distance
        result["passed"] = distance <= float(expected.get("tolerance_m", 0.6))
    if expected.has("height_min"):
        result["height_reached"] = state["position"][1] >= float(expected["height_min"])
        result["passed"] = result["passed"] and result["height_reached"]
    if expected.has("interactions_min"):
        result["interaction_reached"] = state["interactions"] >= int(expected["interactions_min"])
        result["passed"] = result["passed"] and result["interaction_reached"]
    return result

func _write(path: String, value: Dictionary) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify(value, "  "))
