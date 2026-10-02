extends RefCounted
## Real physics/navigation and separate saved-scene acceptance.

func run(context, arguments: Dictionary) -> Dictionary:
    var world: Node3D = context.object("world")
    var manager: RoadManager = context.object("road_manager")
    if arguments.get("stage") == "reopen":
        return await _reopen(context, world, manager)
    var checks := await _check(context, world, manager)
    if not checks.get("ok", false): return checks
    var region: NavigationRegion3D = context.object("navigation")
    region.bake_navigation_mesh(false)
    var rid := region.get_navigation_map()
    NavigationServer3D.map_force_update(rid)
    for _i in range(10): await context.physics_frame
    var routes := {}
    for road in manager.get_containers():
        var points := road.get_roadpoints()
        var start := points[0].global_position + points[0].global_basis.z * 3.0
        var finish := points[-1].global_position - points[-1].global_basis.z * 3.0
        var route := NavigationServer3D.map_get_path(rid, NavigationServer3D.map_get_closest_point(rid, start), NavigationServer3D.map_get_closest_point(rid, finish), true)
        if route.size() < 2 or route[0].distance_to(start) > 2.0 or route[-1].distance_to(finish) > 2.0:
            return {"ok": false, "error": "actual road navigation failed: " + String(road.name)}
        var maximum_height := 0.0
        for point in route: maximum_height = maxf(maximum_height, point.y)
        if road.name == "flyover" and maximum_height < 7.5:
            return {"ok": false, "error": "bridge route did not use the elevated deck"}
        routes[String(road.name)] = {"points": route.size(), "max_height_m": maximum_height,
                                   "start": start, "finish": finish}
    checks["navigation_polygons"] = region.navigation_mesh.get_polygon_count()
    checks["routes"] = routes
    # Explicit capsule traverses the real curved road and the ascent, using
    # sampled actual provider curves only for steering, never teleporting.
    var curve_walk := await _walk(context, world, manager.get_node("boulevard"), 1, 28.0)
    if not curve_walk.get("ok", false): return curve_walk
    var ramp_walk := await _walk(context, world, manager.get_node("flyover"), 0, 57.0)
    if not ramp_walk.get("ok", false): return ramp_walk
    if ramp_walk["final_height_m"] < 7.3:
        return {"ok": false, "error": "capsule did not climb the ramp", "walk": ramp_walk}
    checks["capsule_curve"] = curve_walk
    checks["capsule_ramp"] = ramp_walk
    return checks

func _check(context, world: Node3D, manager: RoadManager, mask: int = 4) -> Dictionary:
    for _i in range(3): await context.physics_frame
    var count := 0
    var length := 0.0
    var lanes := 0
    var continuity := 0
    var direct := world.get_world_3d().direct_space_state
    for container in manager.get_containers():
        var segments := container.get_segments()
        if segments.size() != container.get_roadpoints().size() - 1:
            return {"ok": false, "error": "provider lost a road segment"}
        for segment in segments:
            count += 1
            length += segment.curve.get_baked_length()
            for fraction in [0.05, 0.5, 0.95]:
                var position: Vector3 = segment.to_global(segment.curve.sample_baked(segment.curve.get_baked_length() * fraction))
                var hit := direct.intersect_ray(PhysicsRayQueryParameters3D.create(position + Vector3.UP * 2, position - Vector3.UP * 2, mask))
                if hit.is_empty() or not manager.is_ancestor_of(hit["collider"]) or absf(hit["position"].y - position.y) > 0.3:
                    return {"ok": false, "error": "road collision continuity failed", "position": position}
                continuity += 1
            for lane in segment.get_lanes():
                lanes += 1
                if lane.curve == null or lane.curve.get_baked_length() < 1:
                    return {"ok": false, "error": "lane curve missing"}
                for key in ["lane_next", "lane_prior"]:
                    var link: NodePath = lane.get(key)
                    if not link.is_empty() and lane.get_node_or_null(link) == null:
                        return {"ok": false, "error": "lane connection is broken"}
        # Every internal RoadPoint seam is probed immediately before/after.
        var points := container.get_roadpoints()
        for i in range(1, points.size() - 1):
            for offset in [-0.12, 0.12]:
                var position: Vector3 = points[i].global_position + points[i].global_basis.z * offset
                var hit := direct.intersect_ray(PhysicsRayQueryParameters3D.create(position + Vector3.UP * 2, position - Vector3.UP * 2, mask))
                if hit.is_empty() or not manager.is_ancestor_of(hit["collider"]):
                    return {"ok": false, "error": "joint collision gap"}
                continuity += 1
    return {"ok": true, "segments": count, "length_m": length, "lanes": lanes,
            "collision_samples": continuity, "lane_links_valid": true}

func _walk(context, world: Node3D, container: RoadContainer, segment_index: int, distance: float) -> Dictionary:
    var segment = container.get_segments()[segment_index]
    var curve: Curve3D = segment.curve
    var actor := CharacterBody3D.new()
    actor.collision_mask = 4
    actor.floor_snap_length = 0.6
    var collision := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = 0.35
    shape.height = 1.8
    collision.shape = shape
    collision.position.y = 0.9
    actor.add_child(collision)
    world.add_child(actor)
    actor.global_position = segment.to_global(curve.sample_baked(2.0)) + Vector3.UP * 0.4
    for _i in range(25):
        await context.physics_frame
        actor.velocity = Vector3(0, -4, 0)
        actor.move_and_slide()
    var started := actor.global_position
    var progress := 2.0
    var travelled := 0.0
    var on_floor_frames := 0
    var end_progress := minf(curve.get_baked_length() - 1.5, 2.0 + distance)
    for _i in range(700):
        await context.physics_frame
        var local: Vector3 = segment.to_local(actor.global_position)
        progress = maxf(progress, curve.get_closest_offset(local))
        if progress >= end_progress - 0.4: break
        var goal: Vector3 = segment.to_global(curve.sample_baked(minf(progress + 2.0, end_progress)))
        var direction := goal - actor.global_position
        direction.y = 0
        actor.velocity = direction.normalized() * 12.0 + Vector3(0, -4, 0)
        var prior := actor.global_position
        actor.move_and_slide()
        travelled += prior.distance_to(actor.global_position)
        if actor.is_on_floor(): on_floor_frames += 1
    var result := {"ok": progress >= end_progress - 0.5 and on_floor_frames > 10,
                   "distance_m": travelled, "progress_m": progress - 2.0, "on_floor_frames": on_floor_frames,
                   "initial_height_m": started.y, "final_height_m": actor.global_position.y,
                   "capsule_height_m": 1.8}
    actor.free()
    if not result["ok"]: result["error"] = "capsule stalled or fell off authored road"
    return result

func _layer(node: Node, layer: int) -> void:
    if node is CollisionObject3D: node.collision_layer = layer
    for child in node.get_children(): _layer(child, layer)

func _counts(node: Node, counts: Dictionary) -> void:
    if node is MeshInstance3D and node.mesh != null:
        counts["meshes"] += 1
        counts["triangles"] += node.mesh.get_faces().size() / 3
    if node is CollisionObject3D: counts["colliders"] += 1
    if node is Path3D: counts["lanes"] += 1
    for child in node.get_children(): _counts(child, counts)

func _reopen(context, original: Node3D, manager: RoadManager) -> Dictionary:
    var editable_path: String = context.output_path("scenes/urban_roads_editable.tscn")
    var baked_path: String = context.output_path("scenes/urban_roads_baked.tscn")
    var editable: Node3D = ResourceLoader.load(editable_path, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
    context.root.add_child(editable)
    for _i in range(8): await context.process_frame
    var fresh: RoadManager = editable.get_node("Navigation/RoadNetwork")
    _layer(fresh, 8)
    var source_check := await _check(context, editable, fresh, 8)
    if not source_check.get("ok", false):
        editable.free()
        return source_check
    # Negative control: remove all road collision and deliberately put nearby
    # scenery/ground on the probe mask. The ground must not substitute for roads.
    var scenery: Node3D = editable.get_node("Scenery")
    _layer(fresh, 0)
    _layer(scenery, 8)
    var missing_collision := await _check(context, editable, fresh, 8)
    var segment = fresh.get_node("boulevard").get_segments()[0]
    var position: Vector3 = segment.to_global(segment.curve.sample_baked(segment.curve.get_baked_length() * 0.5))
    var ground_hit := editable.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position + Vector3.UP * 2, position - Vector3.UP * 2, 8))
    if missing_collision.get("ok", false) or ground_hit.is_empty() or not scenery.is_ancestor_of(ground_hit["collider"]):
        editable.free()
        return {"ok": false, "error": "missing road collision negative control did not reject nearby ground"}
    source_check["missing_road_collision_rejected"] = true
    source_check["ground_on_probe_layer_verified"] = true
    var original_signature := _signature(manager)
    var comparison := _compare_geometry(manager, fresh)
    if not comparison.get("ok", false):
        editable.free()
        return {"ok": false, "error": "editable scene changed point geometry or mesh on reopen", "comparison": comparison}
    editable.free()
    for _i in range(3): await context.process_frame
    var baked: Node3D = ResourceLoader.load(baked_path, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
    context.root.add_child(baked)
    var baked_roads: Node3D = baked.get_node("BakedRoads")
    _layer(baked_roads, 16)
    for _i in range(3): await context.physics_frame
    var counts := {"meshes": 0, "triangles": 0, "colliders": 0, "lanes": 0}
    _counts(baked.get_node("BakedRoads"), counts)
    var hit := baked.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 12, 12), Vector3(0, 6, 12), 16))
    var lower := baked.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 6, 12), Vector3(0, -2, 12), 16))
    var ok: bool = counts["meshes"] == 7 and counts["colliders"] == 7 and counts["lanes"] == 22 and not hit.is_empty() and not lower.is_empty()
    ok = ok and baked_roads.is_ancestor_of(hit.get("collider")) and baked_roads.is_ancestor_of(lower.get("collider"))
    var result := {"ok": ok, "editable": source_check, "editable_geometry_signature": original_signature,
                   "reopen_geometry_comparison": comparison,
                   "baked": counts, "upper_height_m": hit.get("position", Vector3.ZERO).y,
                   "lower_height_m": lower.get("position", Vector3.ZERO).y, "separate_collision_layers": true}
    baked.free()
    for _i in range(3): await context.process_frame
    if not ok: result["error"] = "baked scene lost mesh, lanes, collision or grade separation"
    return result

func _compare_geometry(first: RoadManager, second: RoadManager) -> Dictionary:
    # TSCN text round-trips floating-point bases; use a measured 0.1mm
    # tolerance, while preserving exact identities, connectivity and topology.
    var maximum := 0.0
    for container in first.get_containers():
        var other: RoadContainer = second.get_node_or_null(NodePath(container.name))
        if other == null or container.get_roadpoints().size() != other.get_roadpoints().size():
            return {"ok": false, "reason": "source point topology differs"}
        for point in container.get_roadpoints():
            var fresh: RoadPoint = other.get_node_or_null(NodePath(point.name))
            if fresh == null or point.traffic_dir != fresh.traffic_dir or point.prior_pt_init != fresh.prior_pt_init or point.next_pt_init != fresh.next_pt_init:
                return {"ok": false, "reason": "identity, ordered lanes or links differ"}
            maximum = maxf(maximum, point.position.distance_to(fresh.position))
            for axis in range(3): maximum = maxf(maximum, point.basis[axis].distance_to(fresh.basis[axis]))
            for property in ["prior_mag", "next_mag", "lane_width", "shoulder_width_l", "shoulder_width_r"]:
                maximum = maxf(maximum, absf(float(point.get(property)) - float(fresh.get(property))))
        if container.get_segments().size() != other.get_segments().size():
            return {"ok": false, "reason": "segment topology differs"}
        for segment in container.get_segments():
            var fresh_segment = null
            for candidate in other.get_segments():
                if candidate.start_point.name == segment.start_point.name and candidate.end_point.name == segment.end_point.name:
                    fresh_segment = candidate
                    break
            if fresh_segment == null: return {"ok": false, "reason": "segment endpoints differ"}
            var faces: PackedVector3Array = segment.road_mesh.mesh.get_faces()
            var fresh_faces: PackedVector3Array = fresh_segment.road_mesh.mesh.get_faces()
            if faces.size() != fresh_faces.size(): return {"ok": false, "reason": "mesh topology differs"}
            for i in range(faces.size()): maximum = maxf(maximum, faces[i].distance_to(fresh_faces[i]))
    return {"ok": maximum <= 0.0001, "max_numeric_delta": maximum, "tolerance": 0.0001,
            "identities_links_lanes_and_mesh_topology_exact": true}

func _signature(manager: RoadManager) -> String:
    var data := PackedByteArray()
    for container in manager.get_containers():
        for point in container.get_roadpoints():
            data.append_array(var_to_bytes([point.name, point.transform, point.lane_width, point.traffic_dir]))
        for segment in container.get_segments():
            data.append_array(var_to_bytes(segment.road_mesh.mesh.get_faces()))
    return data.hex_encode().sha256_text()
