@tool
extends RefCounted

static func apply(document: Dictionary, options: Dictionary) -> Dictionary:
    var result := document.duplicate(true)
    var field: Dictionary = {}
    for f in result.get("authoring", {}).get("heightfields", []):
        if f.get("id", "") == options.get("heightfield_id", ""):
            field = f
    if field.is_empty():
        return {}
    var columns := int(field["columns"])
    var rows := int(field["rows"])
    var heights: Array = field["heights"]
    var original := heights.duplicate()
    var spacing: Array = field.get("spacing", [1, 1])
    var origin: Array = field.get("position", [0, 0, 0])
    var center: Array = options.get("center", [])
    var radius := float(options.get("radius", 0))
    var strength := float(options.get("strength", 1))
    var mode := String(options.get("mode", ""))
    if center.size() != 2 or radius <= 0 or strength < 0 or mode not in ["raise", "lower", "flatten", "smooth", "paint", "hole", "fill"]:
        return {}
    var cell_mode := mode in ["paint", "hole", "fill"]
    var paint: Array = field.get("paint", [])
    var holes: Array = field.get("holes", [])
    if paint.is_empty():
        paint.resize((columns - 1) * (rows - 1))
        paint.fill(field.get("material", "earth_dark"))
    if holes.is_empty():
        holes.resize((columns - 1) * (rows - 1))
        holes.fill(false)
    var changed := 0
    for z in range(rows - 1 if cell_mode else rows):
        for x in range(columns - 1 if cell_mode else columns):
            var offset := 0.5 if cell_mode else 0.0
            var distance := Vector2(float(origin[0]) + (x + offset) * float(spacing[0]) - float(center[0]), float(origin[2]) + (z + offset) * float(spacing[1]) - float(center[1])).length()
            if distance >= radius:
                continue
            var weight := 1.0 - distance / radius
            if cell_mode:
                var index := z * (columns - 1) + x
                if mode == "paint":
                    paint[index] = options.get("material", "")
                else:
                    holes[index] = mode == "hole"
            else:
                var index := z * columns + x
                if mode in ["raise", "lower"]:
                    heights[index] = float(original[index]) + strength * weight * (1.0 if mode == "raise" else -1.0)
                else:
                    var value := float(options.get("height", 0))
                    if mode == "smooth":
                        value = 0
                        var count := 0
                        for nz in range(maxi(0, z - 1), mini(rows, z + 2)):
                            for nx in range(maxi(0, x - 1), mini(columns, x + 2)):
                                value += float(original[nz * columns + nx])
                                count += 1
                        value /= float(count)
                    heights[index] = float(original[index]) + (value - float(original[index])) * minf(strength, 1) * weight
            changed += 1
    if mode == "paint":
        field["paint"] = paint
    if mode in ["hole", "fill"]:
        field["holes"] = holes
    return result if changed > 0 else {}
