@tool
class_name CloseSealMapNavigationRuntime
extends RefCounted

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")

static func compile_route_surface(map_data: Dictionary) -> Dictionary:
    var vertices := PackedVector3Array()
    var polygons: Array[PackedInt32Array] = []
    var segment_count := 0
    var total_area := 0.0
    var route_surfaces: Dictionary = {}
    for route_value in map_data.get("routes", []):
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var points: Array = route.get("points", [])
        if points.size() < 2:
            continue
        var width: float = maxf(float(route.get("width", 0.0)), 0.25)
        var route_id := String(route.get("id", "route"))
        var valid_points: Array[Vector3] = []
        for point_value in points:
            var point := MAP_CONTRACT.vec3_from(point_value)
            if valid_points.is_empty() or valid_points[-1].distance_to(point) > 0.001:
                valid_points.append(point)
        if valid_points.size() < 2:
            continue

        var route_vertex_start := vertices.size()
        for i in range(valid_points.size()):
            var center: Vector3 = valid_points[i]
            var tangent := Vector3.ZERO
            if i > 0:
                tangent += (center - valid_points[i - 1]).normalized()
            if i + 1 < valid_points.size():
                tangent += (valid_points[i + 1] - center).normalized()
            tangent.y = 0.0
            if tangent.length_squared() <= 0.000001:
                tangent = Vector3.RIGHT
            tangent = tangent.normalized()
            var side := Vector3(-tangent.z, 0.0, tangent.x) * width * 0.5
            vertices.append(center - side)
            vertices.append(center + side)

        var route_segments := 0
        var route_area := 0.0
        for i in range(1, valid_points.size()):
            var previous_pair := route_vertex_start + (i - 1) * 2
            var current_pair := route_vertex_start + i * 2
            polygons.append(PackedInt32Array([
                previous_pair,
                previous_pair + 1,
                current_pair + 1,
                current_pair
            ]))
            var length := valid_points[i - 1].distance_to(valid_points[i])
            route_segments += 1
            segment_count += 1
            route_area += length * width
            total_area += length * width
        route_surfaces[route_id] = {
            "segments": route_segments,
            "vertices": valid_points.size() * 2,
            "width": width,
            "area_estimate": route_area
        }

    var navmesh := NavigationMesh.new()
    navmesh.vertices = vertices
    for polygon in polygons:
        navmesh.add_polygon(polygon)
    return {
        "ok": segment_count > 0,
        "navigation_mesh": navmesh,
        "segments": segment_count,
        "polygons": polygons.size(),
        "vertices": vertices.size(),
        "walkable_area_estimate": total_area,
        "route_surfaces": route_surfaces,
        "topology": "continuous_shared_vertices_per_route",
        "source": "canonical_route_corridors"
    }

static func route_graph(map_data: Dictionary) -> Dictionary:
    var graph: Dictionary = {}
    for route_value in map_data.get("routes", []):
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var points: Array = route.get("points", [])
        var length := 0.0
        for i in range(1, points.size()):
            length += MAP_CONTRACT.vec3_from(points[i - 1]).distance_to(MAP_CONTRACT.vec3_from(points[i]))
        graph[String(route.get("id", "route"))] = {
            "kind": String(route.get("kind", "unknown")),
            "length": length,
            "width": float(route.get("width", 0.0)),
            "points": points.size()
        }
    return graph

static func simulate_army_flow(map_data: Dictionary, army_sizes: Array[int] = [10, 50, 100, 500], unit_diameter: float = 0.9, spacing: float = 0.25) -> Dictionary:
    var routes: Array = map_data.get("routes", [])
    var results: Dictionary = {}
    var footprint := maxf(unit_diameter + spacing, 0.1)
    for route_value in routes:
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var route_id := String(route.get("id", "route"))
        var width := maxf(float(route.get("width", 0.0)), 0.1)
        var columns := maxi(1, int(floor(width / footprint)))
        var per_army: Dictionary = {}
        for army_size in army_sizes:
            var rows := int(ceil(float(army_size) / float(columns)))
            var depth := float(rows) * footprint
            var pressure := float(army_size) / float(columns)
            per_army[str(army_size)] = {
                "columns": columns,
                "rows": rows,
                "queue_depth_m": depth,
                "pressure_index": pressure,
                "classification": _pressure_class(pressure)
            }
        results[route_id] = per_army
    return {
        "unit_diameter": unit_diameter,
        "spacing": spacing,
        "routes": results,
        "model": "geometric corridor capacity; not agent runtime performance"
    }

static func _pressure_class(value: float) -> String:
    if value <= 4.0:
        return "free"
    if value <= 12.0:
        return "loaded"
    if value <= 30.0:
        return "congested"
    return "saturated"

static func format_simulation_report(map_data: Dictionary) -> String:
    var compiled := compile_route_surface(map_data)
    var flow := simulate_army_flow(map_data)
    var lines: Array[String] = [
        "[b]Compiled Navigation Surface[/b]",
        "Source: canonical route corridors",
        "Topology: %s" % String(compiled.get("topology", "unknown")),
        "Segments: %d • polygons: %d • vertices: %d" % [int(compiled.get("segments", 0)), int(compiled.get("polygons", 0)), int(compiled.get("vertices", 0))],
        "Walkable corridor area estimate: %.1f m²" % float(compiled.get("walkable_area_estimate", 0.0)),
        "",
        "[b]Army Flow Model[/b]"
    ]
    var routes: Dictionary = flow.get("routes", {})
    for route_id in routes.keys():
        lines.append("[b]%s[/b]" % String(route_id))
        var armies: Dictionary = routes[route_id]
        for size in [10, 50, 100, 500]:
            var state: Dictionary = armies.get(str(size), {})
            lines.append("  %3d units → %d columns • %d rows • %.1fm queue • %s" % [size, int(state.get("columns", 0)), int(state.get("rows", 0)), float(state.get("queue_depth_m", 0.0)), String(state.get("classification", "unknown"))])
    lines.append("")
    lines.append("[color=gray]This is deterministic geometry/capacity evidence. Runtime agent avoidance, CPU cost and actual traversal time still require executable agent tests.[/color]")
    return "\n".join(lines)
