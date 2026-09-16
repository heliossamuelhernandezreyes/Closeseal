extends SceneTree

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")
const PROVIDER_BRIDGE = preload("res://addons/close_seal_map_forge/map_forge_provider_bridge.gd")
const NAV_LAYER = preload("res://addons/close_seal_map_forge/map_forge_navigation_layer.gd")
const PHYSICAL_WORLD = preload("res://src/map/map_physical_world.gd")

func _initialize() -> void:
    var map_data := MAP_CONTRACT.load_file("res://maps/competitive_lab_01.json")
    if map_data.is_empty(): quit(10); return
    var audit := PHYSICAL_WORLD.analyze(map_data)
    if not bool(audit.get("ok", false)):
        push_error("PHYSICAL_WORLD_AUDIT_FAILED %s" % JSON.stringify(audit)); quit(11); return
    var build := PROVIDER_BRIDGE.build_authoring_scene(map_data)
    if not bool(build.get("ok", false)): quit(12); return
    var scene_path := String(build.get("scene_path", ""))
    var nav := NAV_LAYER.augment_scene(scene_path, map_data)
    if not bool(nav.get("ok", false)): quit(13); return
    var physical := PHYSICAL_WORLD.augment_scene(scene_path, map_data)
    if not bool(physical.get("ok", false)): quit(14); return
    var packed = load(scene_path)
    if packed == null or not packed is PackedScene: quit(15); return
    var root = packed.instantiate()
    var layer = root.get_node_or_null("PhysicalWorld")
    if layer == null: root.free(); quit(16); return
    var bodies := 0
    var passes := 0
    for child in layer.get_children():
        if child is StaticBody3D: bodies += 1
        elif child is Marker3D and String(child.get_meta("map_forge_role", "")) == "tactical_pass": passes += 1
    if bodies < 8 or passes < 4:
        push_error("PHYSICAL_WORLD_INCOMPLETE bodies=%d passes=%d" % [bodies, passes]); root.free(); quit(17); return
    print("MAP_FORGE_PHYSICAL_WORLD_OK blockers=%d passes=%d polygons=%d" % [bodies, passes, int(nav.get("polygons", 0))])
    print("MAP_FORGE_PHYSICAL_WORLD_AUDIT=%s" % JSON.stringify(audit))
    root.free(); quit(0)
