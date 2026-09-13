class_name CloseSealMapContract
extends RefCounted

const VERSION := 1
const REQUIRED_TOP_LEVEL := ["version", "id", "bounds", "bases", "objectives", "routes", "regions"]
const VALID_ROUTE_KINDS := ["primary", "flank", "secondary", "jungle", "connector"]
const VALID_REGION_KINDS := ["formation_space", "choke", "objective_zone", "spawn_zone", "hazard", "cover", "neutral"]

static func load_file(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Map contract missing: " + path)
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Map contract could not be opened: " + path)
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Map contract is not a dictionary: " + path)
        return {}
    var map_data: Dictionary = parsed
    var errors := validate(map_data)
    if not errors.is_empty():
        for error in errors:
            push_error("Map contract: " + error)
        return {}
    return map_data

static func validate(map_data: Dictionary) -> Array[String]:
    var errors: Array[String] = []
    for key in REQUIRED_TOP_LEVEL:
        if not map_data.has(key):
            errors.append("missing top-level key '%s'" % key)

    if map_data.get("version", -1) != VERSION:
        errors.append("unsupported version %s (expected %s)" % [map_data.get("version", -1), VERSION])

    var map_id := String(map_data.get("id", "")).strip_edges()
    if map_id.is_empty():
        errors.append("id must be a non-empty string")

    var bounds = map_data.get("bounds", {})
    if typeof(bounds) != TYPE_DICTIONARY or not bounds.has("width") or not bounds.has("depth"):
        errors.append("bounds requires width and depth")
    else:
        if float(bounds.get("width", 0.0)) <= 0.0 or float(bounds.get("depth", 0.0)) <= 0.0:
            errors.append("bounds width and depth must be positive")

    var seen_ids: Dictionary = {}
    _validate_collection_ids(map_data.get("bases", []), "base", seen_ids, errors)
    _validate_collection_ids(map_data.get("objectives", []), "objective", seen_ids, errors)
    _validate_collection_ids(map_data.get("routes", []), "route", seen_ids, errors)
    _validate_collection_ids(map_data.get("regions", []), "region", seen_ids, errors)

    var bases = map_data.get("bases", [])
    if typeof(bases) != TYPE_ARRAY or bases.size() < 2:
        errors.append("at least two bases are required")
    else:
        for i in range(bases.size()):
            if typeof(bases[i]) != TYPE_DICTIONARY:
                errors.append("base %d must be a dictionary" % i)
                continue
            var base: Dictionary = bases[i]
            if not _is_vec3_array(base.get("position", null)):
                errors.append("base '%s' requires position [x,y,z]" % String(base.get("id", i)))
            if base.has("hero_spawn") and not _is_vec3_array(base.get("hero_spawn")):
                errors.append("base '%s' hero_spawn must be [x,y,z]" % String(base.get("id", i)))

    var objectives = map_data.get("objectives", [])
    if typeof(objectives) != TYPE_ARRAY:
        errors.append("objectives must be an array")
    else:
        for objective_value in objectives:
            if typeof(objective_value) != TYPE_DICTIONARY:
                errors.append("objective entries must be dictionaries")
                continue
            var objective: Dictionary = objective_value
            if not _is_vec3_array(objective.get("position", null)):
                errors.append("objective '%s' requires position [x,y,z]" % String(objective.get("id", "?")))
            if float(objective.get("radius", 0.0)) < 0.0:
                errors.append("objective '%s' radius cannot be negative" % String(objective.get("id", "?")))

    var routes = map_data.get("routes", [])
    if typeof(routes) != TYPE_ARRAY:
        errors.append("routes must be an array")
    else:
        for route_value in routes:
            if typeof(route_value) != TYPE_DICTIONARY:
                errors.append("route entries must be dictionaries")
                continue
            var route: Dictionary = route_value
            var route_id := String(route.get("id", "?"))
            var kind := String(route.get("kind", ""))
            if not VALID_ROUTE_KINDS.has(kind):
                errors.append("route '%s' has unsupported kind '%s'" % [route_id, kind])
            var points = route.get("points", [])
            if typeof(points) != TYPE_ARRAY or points.size() < 2:
                errors.append("route '%s' requires at least two points" % route_id)
            else:
                for point in points:
                    if not _is_vec3_array(point):
                        errors.append("route '%s' contains an invalid point" % route_id)
                        break
            if float(route.get("width", 0.0)) <= 0.0:
                errors.append("route '%s' width must be positive" % route_id)

    var regions = map_data.get("regions", [])
    if typeof(regions) != TYPE_ARRAY:
        errors.append("regions must be an array")
    else:
        for region_value in regions:
            if typeof(region_value) != TYPE_DICTIONARY:
                errors.append("region entries must be dictionaries")
                continue
            var region: Dictionary = region_value
            var region_id := String(region.get("id", "?"))
            var kind := String(region.get("kind", ""))
            if not VALID_REGION_KINDS.has(kind):
                errors.append("region '%s' has unsupported kind '%s'" % [region_id, kind])
            if not _is_vec3_array(region.get("center", null)):
                errors.append("region '%s' requires center [x,y,z]" % region_id)
            if kind == "choke" and float(region.get("width", 0.0)) <= 0.0:
                errors.append("choke region '%s' width must be positive" % region_id)

    return errors

static func _validate_collection_ids(value, label: String, seen_ids: Dictionary, errors: Array[String]) -> void:
    if typeof(value) != TYPE_ARRAY:
        return
    for entry_value in value:
        if typeof(entry_value) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_value
        var id := String(entry.get("id", "")).strip_edges()
        if id.is_empty():
            errors.append("%s is missing a non-empty id" % label)
        elif seen_ids.has(id):
            errors.append("duplicate id '%s'" % id)
        else:
            seen_ids[id] = true

static func _is_vec3_array(value) -> bool:
    return typeof(value) == TYPE_ARRAY and value.size() >= 3

static func vec3_from(value, fallback := Vector3.ZERO) -> Vector3:
    if not _is_vec3_array(value):
        return fallback
    return Vector3(float(value[0]), float(value[1]), float(value[2]))
