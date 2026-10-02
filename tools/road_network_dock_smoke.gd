extends SceneTree
const PLUGIN = preload("res://addons/close_seal_map_forge/map_forge_plugin_v11.gd")

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    for _i in range(5): await process_frame
    while EditorInterface.get_resource_filesystem().is_scanning(): await process_frame
    var report = JSON.parse_string(FileAccess.get_file_as_string("res://.arcont/road-network-smoke.json"))
    if not report is Dictionary or not report.get("ok", false):
        push_error("ROAD_DOCK: successful provider evidence required")
        quit(1)
        return
    var panel := TabContainer.new()
    root.add_child(panel)
    var plugin = PLUGIN.new()
    plugin._install_control_tab(panel)
    plugin._select_control_mode(1)
    var scene := ProjectSettings.globalize_path("res://" + String(report["bundle"]) + "/scenes/urban_roads_editable.tscn")
    plugin.control_last_result = {"result": {"artifacts": [scene]}}
    plugin._open_authoring_scene()
    for _i in range(30): await process_frame
    var edited := EditorInterface.get_edited_scene_root()
    var points: RoadContainer = edited.get_node_or_null("Navigation/RoadNetwork/boulevard") if edited != null else null
    if edited == null or edited.name != "UrbanRoads" or points == null or points.get_roadpoints().size() != 5 or points.get_segments().size() != 4:
        push_error("ROAD_DOCK: editable source did not open/rebuild in actual editor")
        quit(1)
        return
    plugin.free()
    panel.free()
    print("ARCONT_ROAD_DOCK_OK points_editable=true real_segments_rebuilt=true")
    quit(0)
