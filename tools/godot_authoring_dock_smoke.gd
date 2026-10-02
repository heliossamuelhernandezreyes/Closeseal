extends SceneTree
const PLUGIN = preload("res://addons/close_seal_map_forge/map_forge_plugin_v11.gd")

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    for _frame in range(5): await process_frame
    while EditorInterface.get_resource_filesystem().is_scanning():
        await process_frame
    var report = JSON.parse_string(FileAccess.get_file_as_string("res://.arcont/authoring-smoke.json"))
    if not report is Dictionary or not report.get("ok", false):
        push_error("AUTHORING_DOCK: successful engine evidence required")
        quit(1)
        return
    var panel := TabContainer.new()
    root.add_child(panel)
    var plugin = PLUGIN.new()
    plugin._install_control_tab(panel)
    plugin._select_control_mode(1)
    if not plugin.control_tool.text.ends_with("godot_authoring_control.py") or plugin.control_response.editable:
        push_error("AUTHORING_DOCK: general tool selection or response inspector failed")
        quit(1)
        return
    var scene := ProjectSettings.globalize_path("res://" + String(report["captures_directory"]) + "/scenes/urban_workbench.tscn")
    plugin.control_last_result = {"result": {"artifacts": [scene]}}
    plugin._open_authoring_scene()
    for _frame in range(20): await process_frame
    var edited := EditorInterface.get_edited_scene_root()
    if edited == null or String(edited.name) != "UrbanWorkbench" or edited.get_node_or_null("Navigation/PocketTrees/ScatterOutput") == null:
        push_error("AUTHORING_DOCK: accepted bundle scene did not open in the actual editor")
        quit(1)
        return
    plugin.free()
    panel.free()
    print("ARCONT_AUTHORING_DOCK_OK general_control=true accepted_scene_opened=true")
    quit(0)
