@tool
class_name CloseSealMapForgeNavigationLayer
extends RefCounted

const NAV_RUNTIME = preload("res://src/map/map_navigation_runtime.gd")

static func augment_scene(scene_path: String, map_data: Dictionary) -> Dictionary:
    if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
        return {"ok": false, "error": "generated authoring scene missing"}
    var packed = load(scene_path)
    if packed == null or not packed is PackedScene:
        return {"ok": false, "error": "authoring scene is not a PackedScene"}
    var root = packed.instantiate()
    if root == null or not root is Node3D:
        return {"ok": false, "error": "authoring scene cannot instantiate as Node3D"}

    var root3d: Node3D = root
    var existing := root3d.get_node_or_null("NavigationBakeTarget")
    if existing != null:
        root3d.remove_child(existing)
        existing.free()

    var compiled: Dictionary = NAV_RUNTIME.compile_route_surface(map_data)
    if not bool(compiled.get("ok", false)):
        root3d.free()
        return {"ok": false, "error": "canonical route surface could not be compiled"}

    var region := NavigationRegion3D.new()
    region.name = "NavigationBakeTarget"
    var navmesh: NavigationMesh = compiled.get("navigation_mesh")
    var navigation_cfg: Dictionary = map_data.get("authoring", {}).get("navigation", {})
    navmesh.agent_radius = float(navigation_cfg.get("agent_radius", 0.45))
    navmesh.agent_height = float(navigation_cfg.get("agent_height", 1.8))
    navmesh.agent_max_climb = float(navigation_cfg.get("agent_max_climb", 0.45))
    navmesh.agent_max_slope = float(navigation_cfg.get("agent_max_slope", 45.0))
    navmesh.cell_size = float(navigation_cfg.get("cell_size", 0.25))
    navmesh.cell_height = float(navigation_cfg.get("cell_height", 0.25))
    region.navigation_mesh = navmesh
    region.set_meta("map_forge_role", "navigation_surface")
    region.set_meta("map_forge_status", "compiled_route_surface")
    region.set_meta("semantic_routes", map_data.get("routes", []).size())
    region.set_meta("compiled_segments", int(compiled.get("segments", 0)))
    region.set_meta("walkable_area_estimate", float(compiled.get("walkable_area_estimate", 0.0)))
    root3d.add_child(region)
    region.owner = root3d

    var route_markers := Node3D.new()
    route_markers.name = "NavigationRouteMarkers"
    region.add_child(route_markers)
    route_markers.owner = root3d
    for route_value in map_data.get("routes", []):
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var points: Array = route.get("points", [])
        for i in range(points.size()):
            var point = points[i]
            if typeof(point) != TYPE_ARRAY or point.size() < 3:
                continue
            var marker := Marker3D.new()
            marker.name = "%s_%02d" % [String(route.get("id", "route")), i]
            marker.position = Vector3(float(point[0]), float(point[1]), float(point[2]))
            marker.set_meta("route_id", String(route.get("id", "route")))
            marker.set_meta("route_width", float(route.get("width", 0.0)))
            route_markers.add_child(marker)
            marker.owner = root3d

    var repacked := PackedScene.new()
    var pack_error := repacked.pack(root3d)
    if pack_error != OK:
        root3d.free()
        return {"ok": false, "error": "navigation repack failed: %s" % pack_error}
    var save_error := ResourceSaver.save(repacked, scene_path)
    root3d.free()
    if save_error != OK:
        return {"ok": false, "error": "navigation scene save failed: %s" % save_error}
    return {
        "ok": true,
        "scene_path": scene_path,
        "status": "compiled_route_surface",
        "agent_radius": navmesh.agent_radius,
        "agent_height": navmesh.agent_height,
        "cell_size": navmesh.cell_size,
        "segments": int(compiled.get("segments", 0)),
        "polygons": int(compiled.get("polygons", 0)),
        "vertices": int(compiled.get("vertices", 0)),
        "walkable_area_estimate": float(compiled.get("walkable_area_estimate", 0.0))
    }
