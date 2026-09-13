class_name CloseSealMapAnalyzer
extends RefCounted

static func analyze(map_data: Dictionary) -> Dictionary:
    var result := {
        "errors": [],
        "warnings": [],
        "metrics": {},
        "scores": {}
    }
    if map_data.is_empty():
        result.errors.append("Map data is empty")
        return result

    var bounds: Dictionary = map_data.get("bounds", {})
    var width := float(bounds.get("width", 0.0))
    var depth := float(bounds.get("depth", 0.0))
    result.metrics["area"] = width * depth
    result.metrics["route_count"] = map_data.get("routes", []).size()
    result.metrics["region_count"] = map_data.get("regions", []).size()
    result.metrics["objective_count"] = map_data.get("objectives", []).size()

    var bases: Array = map_data.get("bases", [])
    if bases.size() >= 2:
        var a := CloseSealMapContract.vec3_from(bases[0].get("position", []))
        var b := CloseSealMapContract.vec3_from(bases[1].get("position", []))
        result.metrics["base_distance"] = a.distance_to(b)
        var midpoint := (a + b) * 0.5
        result.metrics["base_midpoint_offset"] = Vector2(midpoint.x, midpoint.z).length()
        if result.metrics["base_midpoint_offset"] > max(width, depth) * 0.03:
            result.warnings.append("Primary bases are not centered around the map origin")

    var route_lengths: Dictionary = {}
    var routes: Array = map_data.get("routes", [])
    for route_value in routes:
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var points: Array = route.get("points", [])
        var length := 0.0
        for i in range(1, points.size()):
            length += CloseSealMapContract.vec3_from(points[i - 1]).distance_to(CloseSealMapContract.vec3_from(points[i]))
        route_lengths[String(route.get("id", "route"))] = length
    result.metrics["route_lengths"] = route_lengths

    var north := float(route_lengths.get("north_flank", -1.0))
    var south := float(route_lengths.get("south_flank", -1.0))
    if north > 0.0 and south > 0.0:
        var denom := max(north, south)
        var flank_delta := abs(north - south) / denom
        result.metrics["flank_length_delta"] = flank_delta
        result.scores["route_symmetry"] = clamp(1.0 - flank_delta, 0.0, 1.0)
        if flank_delta > 0.08:
            result.warnings.append("North/south flank travel lengths differ by more than 8%")

    var objective_balance := 1.0
    if bases.size() >= 2:
        var base_a := CloseSealMapContract.vec3_from(bases[0].get("position", []))
        var base_b := CloseSealMapContract.vec3_from(bases[1].get("position", []))
        for objective_value in map_data.get("objectives", []):
            if typeof(objective_value) != TYPE_DICTIONARY:
                continue
            var objective: Dictionary = objective_value
            var p := CloseSealMapContract.vec3_from(objective.get("position", []))
            var da := p.distance_to(base_a)
            var db := p.distance_to(base_b)
            var maxd := max(da, db)
            if maxd > 0.001:
                objective_balance = min(objective_balance, 1.0 - abs(da - db) / maxd)
    result.scores["objective_distance_balance"] = clamp(objective_balance, 0.0, 1.0)
    if objective_balance < 0.92:
        result.warnings.append("At least one objective has a meaningful base-distance bias")

    var choke_widths: Array[float] = []
    for region_value in map_data.get("regions", []):
        if typeof(region_value) != TYPE_DICTIONARY:
            continue
        var region: Dictionary = region_value
        if String(region.get("kind", "")) == "choke":
            var choke_width := float(region.get("width", 0.0))
            if choke_width > 0.0:
                choke_widths.append(choke_width)
    result.metrics["choke_widths"] = choke_widths
    if not choke_widths.is_empty():
        result.metrics["minimum_choke_width"] = choke_widths.min()
        result.metrics["maximum_choke_width"] = choke_widths.max()

    var hard_errors := CloseSealMapContract.validate(map_data)
    result.errors.append_array(hard_errors)
    result.scores["structural_health"] = 1.0 if result.errors.is_empty() else 0.0
    return result

static func format_report(map_data: Dictionary) -> String:
    var audit := analyze(map_data)
    var lines: Array[String] = []
    lines.append("[b]%s[/b]" % String(map_data.get("display_name", map_data.get("id", "Unnamed map"))))
    lines.append("")
    lines.append("[b]Metrics[/b]")
    var metrics: Dictionary = audit.metrics
    lines.append("• Area: %.1f" % float(metrics.get("area", 0.0)))
    lines.append("• Bases: %.2f apart" % float(metrics.get("base_distance", 0.0)))
    lines.append("• Routes: %d" % int(metrics.get("route_count", 0)))
    lines.append("• Objectives: %d" % int(metrics.get("objective_count", 0)))
    lines.append("• Regions: %d" % int(metrics.get("region_count", 0)))
    var route_lengths: Dictionary = metrics.get("route_lengths", {})
    for id in route_lengths.keys():
        lines.append("  ↳ %s: %.2f m" % [String(id), float(route_lengths[id])])
    lines.append("")
    lines.append("[b]Balance scores[/b]")
    for key in audit.scores.keys():
        lines.append("• %s: %.1f%%" % [String(key).replace("_", " ").capitalize(), float(audit.scores[key]) * 100.0])
    if not audit.warnings.is_empty():
        lines.append("")
        lines.append("[b][color=yellow]Warnings[/color][/b]")
        for warning in audit.warnings:
            lines.append("• " + String(warning))
    if not audit.errors.is_empty():
        lines.append("")
        lines.append("[b][color=red]Errors[/color][/b]")
        for error in audit.errors:
            lines.append("• " + String(error))
    if audit.errors.is_empty() and audit.warnings.is_empty():
        lines.append("")
        lines.append("[color=green]No structural warnings detected.[/color]")
    return "\n".join(lines)
