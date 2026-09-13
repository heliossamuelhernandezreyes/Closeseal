class_name CloseSealMapAnalyzer
extends RefCounted

const NAV_ANALYZER = preload("res://src/map/map_navigation_analyzer.gd")

static func analyze(map_data: Dictionary) -> Dictionary:
    var result: Dictionary = {
        "errors": [],
        "warnings": [],
        "metrics": {},
        "scores": {},
        "navigation": {}
    }
    if map_data.is_empty():
        result["errors"].append("Map data is empty")
        return result

    var bounds: Dictionary = map_data.get("bounds", {})
    var width: float = float(bounds.get("width", 0.0))
    var depth: float = float(bounds.get("depth", 0.0))
    var metrics: Dictionary = result["metrics"]
    var scores: Dictionary = result["scores"]
    var warnings: Array = result["warnings"]
    var errors: Array = result["errors"]
    metrics["area"] = width * depth
    metrics["route_count"] = map_data.get("routes", []).size()
    metrics["region_count"] = map_data.get("regions", []).size()
    metrics["objective_count"] = map_data.get("objectives", []).size()

    var bases: Array = map_data.get("bases", [])
    if bases.size() >= 2:
        var a: Vector3 = CloseSealMapContract.vec3_from(bases[0].get("position", []))
        var b: Vector3 = CloseSealMapContract.vec3_from(bases[1].get("position", []))
        metrics["base_distance"] = a.distance_to(b)
        var midpoint: Vector3 = (a + b) * 0.5
        var midpoint_offset: float = Vector2(midpoint.x, midpoint.z).length()
        metrics["base_midpoint_offset"] = midpoint_offset
        if midpoint_offset > maxf(width, depth) * 0.03:
            warnings.append("Primary bases are not centered around the map origin")

    var route_lengths: Dictionary = {}
    var routes: Array = map_data.get("routes", [])
    for route_value in routes:
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var points: Array = route.get("points", [])
        var length: float = 0.0
        for i in range(1, points.size()):
            var from_point: Vector3 = CloseSealMapContract.vec3_from(points[i - 1])
            var to_point: Vector3 = CloseSealMapContract.vec3_from(points[i])
            length += from_point.distance_to(to_point)
        route_lengths[String(route.get("id", "route"))] = length
    metrics["route_lengths"] = route_lengths

    var north: float = float(route_lengths.get("north_flank", -1.0))
    var south: float = float(route_lengths.get("south_flank", -1.0))
    if north > 0.0 and south > 0.0:
        var denom: float = maxf(north, south)
        var flank_delta: float = absf(north - south) / denom
        metrics["flank_length_delta"] = flank_delta
        scores["route_symmetry"] = clampf(1.0 - flank_delta, 0.0, 1.0)
        if flank_delta > 0.08:
            warnings.append("North/south flank travel lengths differ by more than 8%")

    var objective_balance: float = 1.0
    if bases.size() >= 2:
        var base_a: Vector3 = CloseSealMapContract.vec3_from(bases[0].get("position", []))
        var base_b: Vector3 = CloseSealMapContract.vec3_from(bases[1].get("position", []))
        var objective_values: Array = map_data.get("objectives", [])
        for objective_value in objective_values:
            if typeof(objective_value) != TYPE_DICTIONARY:
                continue
            var objective: Dictionary = objective_value
            var p: Vector3 = CloseSealMapContract.vec3_from(objective.get("position", []))
            var da: float = p.distance_to(base_a)
            var db: float = p.distance_to(base_b)
            var maxd: float = maxf(da, db)
            if maxd > 0.001:
                objective_balance = minf(objective_balance, 1.0 - absf(da - db) / maxd)
    scores["objective_distance_balance"] = clampf(objective_balance, 0.0, 1.0)
    if objective_balance < 0.92:
        warnings.append("At least one objective has a meaningful base-distance bias")

    var choke_widths: Array[float] = []
    var region_values: Array = map_data.get("regions", [])
    for region_value in region_values:
        if typeof(region_value) != TYPE_DICTIONARY:
            continue
        var region: Dictionary = region_value
        if String(region.get("kind", "")) == "choke":
            var choke_width: float = float(region.get("width", 0.0))
            if choke_width > 0.0:
                choke_widths.append(choke_width)
    metrics["choke_widths"] = choke_widths
    if not choke_widths.is_empty():
        metrics["minimum_choke_width"] = choke_widths.min()
        metrics["maximum_choke_width"] = choke_widths.max()

    var nav_audit: Dictionary = NAV_ANALYZER.analyze(map_data, 6.0)
    result["navigation"] = nav_audit
    var nav_metrics: Dictionary = nav_audit.get("metrics", {})
    metrics["semantic_route_clearance"] = float(nav_metrics.get("route_clear_ratio", 0.0))
    scores["semantic_route_clearance"] = float(nav_metrics.get("route_clear_ratio", 0.0))
    for warning in nav_audit.get("warnings", []):
        warnings.append(String(warning))

    var hard_errors: Array[String] = CloseSealMapContract.validate(map_data)
    errors.append_array(hard_errors)
    scores["structural_health"] = 1.0 if errors.is_empty() else 0.0
    return result

static func format_report(map_data: Dictionary) -> String:
    var audit: Dictionary = analyze(map_data)
    var lines: Array[String] = []
    lines.append("[b]%s[/b]" % String(map_data.get("display_name", map_data.get("id", "Unnamed map"))))
    lines.append("")
    lines.append("[b]Metrics[/b]")
    var metrics: Dictionary = audit.get("metrics", {})
    lines.append("• Area: %.1f" % float(metrics.get("area", 0.0)))
    lines.append("• Bases: %.2f apart" % float(metrics.get("base_distance", 0.0)))
    lines.append("• Routes: %d" % int(metrics.get("route_count", 0)))
    lines.append("• Objectives: %d" % int(metrics.get("objective_count", 0)))
    lines.append("• Regions: %d" % int(metrics.get("region_count", 0)))
    lines.append("• Semantic route clearance: %.1f%%" % (float(metrics.get("semantic_route_clearance", 0.0)) * 100.0))
    var route_lengths: Dictionary = metrics.get("route_lengths", {})
    for id in route_lengths.keys():
        lines.append("  ↳ %s: %.2f m" % [String(id), float(route_lengths[id])])
    lines.append("")
    lines.append("[b]Balance scores[/b]")
    var scores: Dictionary = audit.get("scores", {})
    for key in scores.keys():
        lines.append("• %s: %.1f%%" % [String(key).replace("_", " ").capitalize(), float(scores[key]) * 100.0])

    lines.append("")
    lines.append(NAV_ANALYZER.format_report(map_data, 6.0))

    var warnings: Array = audit.get("warnings", [])
    if not warnings.is_empty():
        lines.append("")
        lines.append("[b][color=yellow]Warnings[/color][/b]")
        for warning in warnings:
            lines.append("• " + String(warning))
    var errors: Array = audit.get("errors", [])
    if not errors.is_empty():
        lines.append("")
        lines.append("[b][color=red]Errors[/color][/b]")
        for error in errors:
            lines.append("• " + String(error))
    if errors.is_empty() and warnings.is_empty():
        lines.append("")
        lines.append("[color=green]No structural warnings detected.[/color]")
    return "\n".join(lines)
