extends RefCounted
## Compose an existing canonical map inside a candidate document. No generated
## map files are overwritten; subsequent bridge edits affect the derived scene.
const CONTRACT = preload("res://src/map/map_contract.gd")
const VISUAL_KIT = preload("res://src/prototype/map_visual_kit.gd")

func run(context, arguments: Dictionary) -> Dictionary:
    var path := String(arguments.get("source", ""))
    if not path.begins_with("res://maps/") or not path.ends_with(".json") or not FileAccess.file_exists(path):
        return {"ok": false, "error": "source requires an existing canonical map JSON"}
    var data = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not data is Dictionary:
        return {"ok": false, "error": "invalid source map"}
    var errors: Array[String] = CONTRACT.validate(data)
    if not errors.is_empty():
        return {"ok": false, "error": "source contract failed", "errors": errors}
    var target = context.object(String(arguments.get("target", "world")))
    if not target is Node3D:
        return {"ok": false, "error": "map target must be a Node3D"}
    var kit = VISUAL_KIT.new(target, data)
    var stats: Dictionary = kit.build()
    if not stats.get("errors", []).is_empty():
        return {"ok": false, "error": "map resources failed", "stats": stats}
    for material_id in kit.materials:
        context.register("map_material_" + String(material_id), kit.materials[material_id])
    return {"ok": true, "source": path, "source_sha256": FileAccess.get_sha256(path),
            "map_id": data["id"], "stats": stats, "ownership": "derived scene; canonical source unchanged"}
