@tool
class_name CloseSealMapNavigationRuntime
extends RefCounted

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")

static func compile_route_surface(map_data: Dictionary) -> Dictionary:
    var vertices := PackedVector3Array()
    var polygons: Array[PackedInt32Array] = []
    var segment_count := 0
    var total_area := 0.0
    for route_value in map_data.get("routes", []):
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var points: Array = route.get("points", [])
        var width := maxf(float(route.get("width", 0.0)), 0.25)
        for i in range(1, points.size()):
            var a := MAP_CONTRACT.vec3_from(points[i - 1])
            var b := MAP_CONTRACT.vec3_from(points[i])
            var delta := b - a
            delta.y = 0.0
            var length := delta.length()
            if length <= 0.001:
                continue
            var side := Vector3(-delta.z, 0.0, delta.x).normalized() * width * 0.5
            var base_index := vertices.size()
            vertices.append(a - side)
            vertices.append(a + side)
            vertices.append(b + side)
            vertices.append(b - side)
            polygons.append(PackedInt32Array([base_index, base_index + 1, base_index + 2, base_index + 3]))
            segment_count += 1
            total_area += length * width
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
