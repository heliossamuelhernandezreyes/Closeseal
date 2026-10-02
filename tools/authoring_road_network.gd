extends RefCounted
## Explicit authored chains -> actual pinned RoadGenerator nodes. No model call.
const MANAGER = preload("res://addons/road-generator/nodes/road_manager.gd")
const CONTAINER = preload("res://addons/road-generator/nodes/road_container.gd")
const POINT = preload("res://addons/road-generator/nodes/road_point.gd")

func run(context, arguments: Dictionary) -> Dictionary:
    if arguments.get("stage", "build") == "save":
        return await _save(context, arguments)
    var network: Dictionary = arguments.get("network", {})
    var target: Node3D = context.object(String(arguments.get("target", "world")))
    if target == null or not target.is_inside_tree() or network.get("version") != 1 or network.get("roads", []).is_empty():
        return {"ok": false, "error": "requires attached world and explicit version-1 road network"}
    var manager := MANAGER.new()
    manager.name = "RoadNetwork"
    manager.auto_refresh = false
    manager.collision_layer = 4
    manager.collision_mask = 1
    manager.collider_meta_name = "arcont_road"
    var underside := StandardMaterial3D.new()
    underside.albedo_color = Color(0.37, 0.40, 0.43)
    underside.roughness = 0.9
    manager.material_underside = underside
    target.add_child(manager)
    context.register("road_manager", manager)
    var expected_segments := 0
    var points := 0
    for road in network["roads"]:
        var container := CONTAINER.new()
        container.name = String(road["id"])
        container.density = float(road.get("density", 2.0))
        container.underside_thickness = float(road.get("thickness", 0.3))
        container.generate_ai_lanes = true
        container.create_edge_curves = true
        container.flatten_terrain = false
        container.set_meta("source_road_id", road["id"])
        manager.add_child(container)
        container._auto_refresh = false
        context.register(String(road["id"]), container)
        var chain: Array[RoadPoint] = []
        for data in road["points"]:
            var point := POINT.new()
            point.name = String(data["id"])
            point.position = _vector(data["position"])
            point.basis = Basis.looking_at(-_vector(data["tangent"]).normalized(), Vector3.UP)
            point.prior_mag = float(data.get("handle_in", 12.0))
            point.next_mag = float(data.get("handle_out", 12.0))
            point.lane_width = float(road.get("lane_width", 3.5))
            point.shoulder_width_l = float(road.get("shoulder_width", 1.0))
            point.shoulder_width_r = point.shoulder_width_l
            point.gutter_profile = Vector2(0.25, -0.10)
            point.flatten_terrain = false
            point.traffic_dir.clear()
            for direction in road["lanes"]:
                point.traffic_dir.append(POINT.LaneDir.FORWARD if direction == "forward" else POINT.LaneDir.REVERSE)
            point.assign_lanes()
            container.add_child(point)
            chain.append(point)
            context.register(String(data["id"]), point)
            points += 1
        for i in range(chain.size() - 1):
            if not chain[i].connect_roadpoint(POINT.PointInit.NEXT, chain[i + 1], POINT.PointInit.PRIOR):
                return {"ok": false, "error": "provider could not connect authored points"}
        if road.get("closed", false):
            if not chain[-1].connect_roadpoint(POINT.PointInit.NEXT, chain[0], POINT.PointInit.PRIOR):
                return {"ok": false, "error": "provider could not close chain"}
        expected_segments += chain.size() if road.get("closed", false) else chain.size() - 1
        container.rebuild_segments()
    manager.auto_refresh = true
    for _i in range(5): await context.process_frame
    var stats := _stats(manager)
    if stats["segments"] != expected_segments or stats["triangles"] == 0 or stats["colliders"] < expected_segments:
        return {"ok": false, "error": "provider output missing geometry or collision", "stats": stats}
    stats["ok"] = true
    stats["points"] = points
    stats["provider"] = "RoadGenerator"
    stats["source"] = network
    return stats

func _vector(value: Array) -> Vector3:
    return Vector3(value[0], value[1], value[2])

func _stats(manager: RoadManager) -> Dictionary:
    var stats := {"segments": 0, "triangles": 0, "colliders": 0, "lanes": 0, "length_m": 0.0}
    for container in manager.get_containers():
        for segment in container.get_segments():
            stats["segments"] += 1
            stats["length_m"] += segment.curve.get_baked_length()
            if segment.road_mesh != null and segment.road_mesh.mesh != null:
                stats["triangles"] += segment.road_mesh.mesh.get_faces().size() / 3
            stats["lanes"] += segment.get_lanes().size()
        stats["colliders"] += container.get_collision_nodes().size()
    return stats

func _owners(node: Node, root_node: Node, source: bool) -> void:
    for child in node.get_children():
        # Provider segments need a constructor argument and are runtime cache.
        # Save RoadPoints/connections, rebuild segments on source scene reopen.
        if source and child.has_method("is_road_segment"):
            child.owner = null
            continue
        child.owner = root_node
        _owners(child, root_node, source)

func _write_scene(node: Node, path: String, source: bool) -> Error:
    _owners(node, node, source)
    var packed := PackedScene.new()
    var error := packed.pack(node)
    return error if error != OK else ResourceSaver.save(packed, path)

func _save(context, arguments: Dictionary) -> Dictionary:
    var world: Node3D = context.object(String(arguments.get("target", "world")))
    var manager: RoadManager = context.object("road_manager")
    var source_path: String = context.output_path("scenes/urban_roads_editable.tscn")
    var baked_path: String = context.output_path("scenes/urban_roads_baked.tscn")
    if _write_scene(world, source_path, true) != OK:
        return {"ok": false, "error": "editable road scene save failed"}
    var baked := Node3D.new()
    baked.name = "UrbanRoadsBaked"
    # Retain authored scenery/environment/navigation; no provider scripts are
    # needed in the baked scene. Mesh and collision come from real output.
    for child in world.get_children():
        if child != manager:
            if child is NavigationRegion3D:
                var region := NavigationRegion3D.new()
                region.name = child.name
                region.transform = child.transform
                region.navigation_mesh = child.navigation_mesh.duplicate(true)
                baked.add_child(region)
            else:
                baked.add_child(child.duplicate())
    var roads := Node3D.new()
    roads.name = "BakedRoads"
    baked.add_child(roads)
    var lane_index := 0
    for container in manager.get_containers():
        var group := Node3D.new()
        group.name = container.name
        group.transform = container.transform
        roads.add_child(group)
        for segment in container.get_segments():
            var mesh := MeshInstance3D.new()
            mesh.name = "Segment_%d" % group.get_child_count()
            mesh.mesh = segment.road_mesh.mesh
            mesh.transform = container.global_transform.affine_inverse() * segment.road_mesh.global_transform
            group.add_child(mesh)
            mesh.create_trimesh_collision()
            for body in mesh.get_children():
                if body is CollisionObject3D:
                    body.collision_layer = 4
                    body.set_meta("arcont_road", true)
            for lane in segment.get_lanes():
                var path := Path3D.new()
                path.name = "Lane_%d" % lane_index
                lane_index += 1
                path.curve = lane.curve.duplicate(true)
                path.transform = container.global_transform.affine_inverse() * lane.global_transform
                path.set_meta("source_path", String(world.get_path_to(lane)))
                for key in ["lane_next", "lane_prior", "lane_next_tag", "lane_prior_tag"]:
                    path.set_meta(key, String(lane.get(key)))
                group.add_child(path)
    var error := _write_scene(baked, baked_path, false)
    baked.free()
    return {"ok": error == OK, "editable_scene": source_path, "baked_scene": baked_path,
            "baked_lanes": lane_index, "editable_source_retained": true,
            "baked_lane_metadata": "provider-relative links retained as metadata; no traffic simulation"}
