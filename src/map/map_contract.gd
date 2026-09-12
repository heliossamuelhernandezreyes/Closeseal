class_name CloseSealMapContract
extends RefCounted

const VERSION := 1
const REQUIRED_TOP_LEVEL := ["version", "id", "bounds", "bases", "objectives", "routes", "regions"]

static func load_file(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Map contract missing: " + path)
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
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
    var bounds = map_data.get("bounds", {})
    if typeof(bounds) != TYPE_DICTIONARY or not bounds.has("width") or not bounds.has("depth"):
        errors.append("bounds requires width and depth")
    var bases = map_data.get("bases", [])
    if typeof(bases) != TYPE_ARRAY or bases.size() < 2:
        errors.append("at least two bases are required")
    return errors

static func vec3_from(value, fallback := Vector3.ZERO) -> Vector3:
    if typeof(value) != TYPE_ARRAY or value.size() < 3:
        return fallback
    return Vector3(float(value[0]), float(value[1]), float(value[2]))
