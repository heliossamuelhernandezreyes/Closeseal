extends SceneTree

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")
const PROVIDER_BRIDGE = preload("res://addons/close_seal_map_forge/map_forge_provider_bridge.gd")
const MAP_PATH := "res://maps/competitive_lab_01.json"

func _initialize() -> void:
    var map_data := MAP_CONTRACT.load_file(MAP_PATH)
    if map_data.is_empty():
        push_error("MAP_FORGE_SMOKE: failed to load canonical map")
        quit(10)
        return

    var result: Dictionary = PROVIDER_BRIDGE.build_authoring_scene(map_data)
    if not bool(result.get("ok", false)):
        push_error("MAP_FORGE_SMOKE: bridge failed: %s" % result.get("errors", []))
        quit(11)
        return

    var scene_path := String(result.get("scene_path", ""))
    if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
        push_error("MAP_FORGE_SMOKE: generated scene missing: %s" % scene_path)
        quit(12)
        return

    var packed = load(scene_path)
    if packed == null or not packed is PackedScene:
        push_error("MAP_FORGE_SMOKE: generated resource is not PackedScene")
        quit(13)
        return

    var instance = packed.instantiate()
    if instance == null or not instance is Node:
        push_error("MAP_FORGE_SMOKE: generated scene cannot instantiate")
        quit(14)
        return

    var root: Node = instance
    for required in ["Terrain", "Structures", "Scatter", "GameplayGuides", "NavigationGuides", "Import"]:
        if root.get_node_or_null(required) == null:
            push_error("MAP_FORGE_SMOKE: missing generated layer %s" % required)
            root.free()
            quit(15)
            return

    var providers: Dictionary = result.get("providers", {})
    var required_providers := ["terrain3d", "cyclops", "proton_scatter", "func_godot"]
    for provider_id in required_providers:
        if not providers.has(provider_id):
            push_error("MAP_FORGE_SMOKE: missing provider status %s" % provider_id)
            root.free()
            quit(16)
            return

    if ClassDB.class_exists(&"Terrain3D") and not bool(providers.get("terrain3d", {}).get("materialized", false)):
        push_error("MAP_FORGE_SMOKE: Terrain3D available but not materialized")
        root.free()
        quit(17)
        return

    if FileAccess.file_exists("res://addons/proton_scatter/src/scatter.gd"):
        var proton: Dictionary = providers.get("proton_scatter", {})
        if not bool(proton.get("materialized", false)) or int(proton.get("zone_shapes", 0)) < 4:
            push_error("MAP_FORGE_SMOKE: ProtonScatter zones did not materialize")
            root.free()
            quit(18)
            return

    if FileAccess.file_exists("res://addons/cyclops_level_builder/nodes/cyclops_blocks.gd") and not bool(providers.get("cyclops", {}).get("materialized", false)):
        push_error("MAP_FORGE_SMOKE: Cyclops workspace did not materialize")
        root.free()
        quit(19)
        return

    print("MAP_FORGE_PROVIDER_BRIDGE_OK scene=%s" % scene_path)
    print("MAP_FORGE_PROVIDER_STATE=%s" % JSON.stringify(providers))
    root.free()
    quit(0)
