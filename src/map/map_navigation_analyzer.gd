class_name CloseSealMapNavigationAnalyzer
extends RefCounted

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")

static func analyze(map_data: Dictionary, formation_width: float = 6.0) -> Dictionary:
    var result := {
        "routes": {},
        "chokes": [],
        "warnings": [],
        "metrics": {}
    }
    var routes: Dictionary = result["routes"]
    var warnings: Array = result["warnings"]
    var metrics: Dictionary = result["metrics"]
    var authoring: Dictionary = map_data.get("authoring", {})
    var structures: Array = authoring.get("structure_guides", [])
    var scatter_zones: Array = authoring.get("scatter_zones", [])

    var traversable := 0
    var total := 0
    var min_route_capacity := 999999
    for value in map_data.get("routes", []):
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = value
        var route_id := String(route.get("id", "route"))
        var width := maxf(float(route.get("width", 0.0)), 0.001)
        var points: Array = route.get("points", [])
        var structure_hits: Array[String] = []
        var scatter_hits: Array[String] = []
        for structure_value in structures:
            if typeof(structure_value) != TYPE_DICTIONARY:
                continue
            var structure: Dictionary = structure_value
            if _polyline_intersects_box(points, structure):
                structure_hits.append(String(structure.get("id", "structure")))
        for zone_value in scatter_zones:
            if typeof(zone_value) != TYPE_DICTIONARY:
                continue
            var zone: Dictionary = zone_value
            if bool(zone.get("blocks_navigation", false)) and _polyline_intersects_box(points, zone):
                scatter_hits.append(String(zone.get("id", "scatter")))

        var capacity := int(floor(width / maxf(formation_width, 0.1)))
        var clear := structure_hits.is_empty() and scatter_hits.is_empty()
        if clear:
            traversable += 1
        total += 1
        min_route_capacity = mini(min_route_capacity, capacity)
        routes[route_id] = {
            "width": width,
            "formation_width": formation_width,
            "formation_capacity": capacity,
            "structure_intersections": structure_hits,
            "blocking_scatter_intersections": scatter_hits,
            "semantic_clear": clear
        }
        if not clear:
            warnings.append("Route '%s' intersects authoring blockers: %s" % [route_id, ", ".join(structure_hits + scatter_hits)])
        if capacity < 1:
            warnings.append("Route '%s' is narrower than the tested formation (%.2f m < %.2f m)" % [route_id, width, formation_width])

    var choke_results: Array = result["chokes"]
    for region_value in map_data.get("regions", []):
        if typeof(region_value) != TYPE_DICTIONARY:
            continue
        var region: Dictionary = region_value
        if String(region.get("kind", "")) != "choke":
            continue
        var width := maxf(float(region.get("width", 0.0)), 0.0)
        var capacity := int(floor(width / maxf(formation_width, 0.1)))
        choke_results.append({
            "id": String(region.get("id", "choke")),
            "width": width,
            "formation_capacity": capacity
        })
        if capacity < 1:
            warnings.append("Choke '%s' cannot fit the tested formation width" % String(region.get("id", "choke")))

    metrics["route_count"] = total
    metrics["semantically_clear_routes"] = traversable
    metrics["route_clear_ratio"] = float(traversable) / float(total) if total > 0 else 0.0
    metrics["tested_formation_width"] = formation_width
    metrics["minimum_route_formation_capacity"] = 0 if min_route_capacity == 999999 else min_route_capacity
    return result

static func format_report(map_data: Dictionary, formation_width: float = 6.0) -> String:
    var audit := analyze(map_data, formation_width)
    var lines: Array[String] = []
    lines.append("[b]Navigation / formation audit[/b]")
    lines.append("Test formation width: %.2f m" % formation_width)
    var metrics: Dictionary = audit.get("metrics", {})
    lines.append("Semantic route clearance: %.1f%%" % (float(metrics.get("route_clear_ratio", 0.0)) * 100.0))
    lines.append("")
    for route_id in audit.get("routes", {}).keys():
        var route: Dictionary = audit["routes"][route_id]
        var state := "CLEAR" if bool(route.get("semantic_clear", false)) else "BLOCKED/RISK"
        lines.append("• %s — %s — width %.2f m — formations across: %d" % [String(route_id), state, float(route.get("width", 0.0)), int(route.get("formation_capacity", 0))])
    var chokes: Array = audit.get("chokes", [])
    if not chokes.is_empty():
        lines.append("")
        lines.append("[b]Chokepoints[/b]")
        for choke in chokes:
            lines.append("• %s — %.2f m — formations across: %d" % [String(choke.get("id", "choke")), float(choke.get("width", 0.0)), int(choke.get("formation_capacity", 0))])
    var warnings: Array = audit.get("warnings", [])
    if not warnings.is_empty():
        lines.append("")
        lines.append("[b][color=yellow]Navigation warnings[/color][/b]")
        for warning in warnings:
            lines.append("• " + String(warning))
    return "\n".join(lines)

static func _polyline_intersects_box(points: Array, box_data: Dictionary) -> bool:
    if points.size() < 2:
        return false
    var center := MAP_CONTRACT.vec3_from(box_data.get("position", box_data.get("center", [])))
    var size := MAP_CONTRACT.vec3_from(box_data.get("size", []), Vector3(1.0, 1.0, 1.0))
    var half := Vector2(absf(size.x) * 0.5, absf(size.z) * 0.5)
    for i in range(1, points.size()):
        var a3 := MAP_CONTRACT.vec3_from(points[i - 1])
        var b3 := MAP_CONTRACT.vec3_from(points[i])
        if _segment_hits_aabb_2d(Vector2(a3.x, a3.z), Vector2(b3.x, b3.z), Vector2(center.x, center.z), half):
            return true
    return false

static func _segment_hits_aabb_2d(a: Vector2, b: Vector2, center: Vector2, half: Vector2) -> bool:
    var minp := center - half
    var maxp := center + half
    if _point_in_aabb(a, minp, maxp) or _point_in_aabb(b, minp, maxp):
        return true
    var edges := [
        [Vector2(minp.x, minp.y), Vector2(maxp.x, minp.y)],
        [Vector2(maxp.x, minp.y), Vector2(maxp.x, maxp.y)],
        [Vector2(maxp.x, maxp.y), Vector2(minp.x, maxp.y)],
        [Vector2(minp.x, maxp.y), Vector2(minp.x, minp.y)]
    ]
    for edge in edges:
        if Geometry2D.segment_intersects_segment(a, b, edge[0], edge[1]) != null:
            return true
    return false

static func _point_in_aabb(point: Vector2, minp: Vector2, maxp: Vector2) -> bool:
    return point.x >= minp.x and point.x <= maxp.x and point.y >= minp.y and point.y <= maxp.y
