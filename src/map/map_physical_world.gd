@tool
class_name CloseSealMapPhysicalWorld
extends RefCounted

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")

static func analyze(map_data: Dictionary) -> Dictionary:
    var errors: Array[String] = []
    var warnings: Array[String] = []
    var terrain: Dictionary = map_data.get("authoring", {}).get("terrain", {})
    var landforms: Array = terrain.get("landforms", [])
    var blocking := 0
    var tactical := 0
    var visual_only := 0
    for value in landforms:
        if typeof(value) != TYPE_DICTIONARY:
            errors.append("terrain landform must be a dictionary")
            continue
        var landform: Dictionary = value
        var id := String(landform.get("id", "")).strip_edges()
        if id.is_empty():
            errors.append("terrain landform requires id")
        if not _finite_vec3_array(landform.get("center", null)):
            errors.append("landform '%s' requires finite center [x,y,z]" % id)
        if not _positive_vec3_array(landform.get("size", null)):
            errors.append("landform '%s' requires positive size [x,y,z]" % id)
        if float(landform.get("height", 0.0)) <= 0.0:
            errors.append("landform '%s' requires positive height" % id)
        var blocks := bool(landform.get("blocks_navigation", false))
        var role := String(landform.get("navigation_role", "visual_boundary"))
        if blocks:
            blocking += 1
        if role in ["tactical_boundary", "blocking_cliff", "pass_wall"]:
            tactical += 1
        elif role == "visual_boundary":
            visual_only += 1

    var navigation: Dictionary = map_data.get("authoring", {}).get("navigation", {})
    var unit_diameter := float(navigation.get("formation_unit_diameter", 0.9))
    var spacing := float(navigation.get("formation_spacing", 0.25))
    var footprint := maxf(unit_diameter + spacing, 0.1)
    var route_capacity: Dictionary = {}
    for value in map_data.get("routes", []):
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = value
        var route_id := String(route.get("id", "route"))
        var width := float(route.get("width", 0.0))
        var required := float(route.get("formation_width", width))
        var columns := maxi(1, int(floor(width / footprint)))
        route_capacity[route_id] = {"width": width, "formation_width": required, "columns": columns}
        if width + 0.001 < required:
            errors.append("route '%s' is narrower than its declared formation width" % route_id)
        if columns < 3:
            warnings.append("route '%s' supports fewer than three formation columns" % route_id)

    var budgets: Dictionary = map_data.get("authoring", {}).get("performance_budget", {})
    if budgets.is_empty():
        warnings.append("authoring.performance_budget is not declared")
    else:
        if int(budgets.get("target_fps", 0)) <= 0:
            errors.append("performance_budget.target_fps must be positive")
        if int(budgets.get("max_active_units", 0)) <= 0:
            errors.append("performance_budget.max_active_units must be positive")
        if int(budgets.get("max_visible_scatter_instances", 0)) <= 0:
            errors.append("performance_budget.max_visible_scatter_instances must be positive")

    if not landforms.is_empty() and tactical == 0 and blocking == 0:
        warnings.append("all terrain landforms are presentation-only; no tactical terrain is declared")

    return {
        "ok": errors.is_empty(),
        "errors": errors,
        "warnings": warnings,
        "landforms": {"total": landforms.size(), "blocking": blocking, "tactical": tactical, "visual_only": visual_only},
        "route_capacity": route_capacity,
        "performance_budget": budgets,
        "model": "semantic-to-physical readiness gate; runtime benchmark remains required"
    }

static func _finite_vec3_array(value) -> bool:
    if typeof(value) != TYPE_ARRAY or value.size() < 3:
        return false
    return is_finite(float(value[0])) and is_finite(float(value[1])) and is_finite(float(value[2]))

static func _positive_vec3_array(value) -> bool:
    return _finite_vec3_array(value) and float(value[0]) > 0.0 and float(value[1]) > 0.0 and float(value[2]) > 0.0
