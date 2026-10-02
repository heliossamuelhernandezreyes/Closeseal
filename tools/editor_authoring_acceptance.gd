extends RefCounted
## Opt-in CI assertions inside the normal editor, using its installed panel.
## This does not override Godot's editor MainLoop or its shutdown lifecycle.

func run(tree: SceneTree, plugin, mode: String) -> void:
    for _i in range(5): await tree.process_frame
    while EditorInterface.get_resource_filesystem().is_scanning(): await tree.process_frame
    if mode == "world":
        var view = plugin.world_view
        var data := CloseSealMapContract.load_file("res://maps/competitive_lab_01.json")
        view.set_document(data)
        view.frame_map()
        for _i in range(3): await tree.process_frame
        if view.handles.size() < 30 or view.content.get_node_or_null("VisualStructures") == null:
            _fail(tree, "WORLD_VIEW: canonical map did not materialize")
            return
        view.selected_object = ["authoring", "terrain", "landforms", 0]
        view._show_selection()
        var edited := data.duplicate(true)
        edited["authoring"]["terrain"]["landforms"][0]["height"] = 18
        view.json_editor.text = JSON.stringify(edited["authoring"]["terrain"]["landforms"][0])
        view._apply_json()
        if plugin.current_map["authoring"]["terrain"]["landforms"][0]["height"] != 18:
            _fail(tree, "WORLD_VIEW: valid 3D edit did not reach installed editor")
            return
        var accepted: Dictionary = plugin.current_map.duplicate(true)
        view.selected_object = []
        view.json_editor.text = "{}"
        view._apply_json()
        if accepted != plugin.current_map:
            _fail(tree, "WORLD_VIEW: invalid edit was accepted")
            return
        print("MAP_FORGE_WORLD_VIEW_OK installed_editor=true")
    else:
        var report_path := "res://.arcont/road-network-smoke.json" if mode == "roads" else "res://.arcont/authoring-smoke.json"
        var report = JSON.parse_string(FileAccess.get_file_as_string(report_path))
        if not report is Dictionary or not report.get("ok", false):
            _fail(tree, "EDITOR_AUTHORING: successful provider evidence required")
            return
        plugin._select_control_mode(1)
        if not plugin.control_tool.text.ends_with("godot_authoring_control.py") or plugin.control_response.editable:
            _fail(tree, "EDITOR_AUTHORING: general control configuration failed")
            return
        var directory := String(report["bundle"] if mode == "roads" else report["captures_directory"])
        var filename := "urban_roads_editable.tscn" if mode == "roads" else "urban_workbench.tscn"
        var scene := ProjectSettings.globalize_path("res://" + directory + "/scenes/" + filename)
        plugin.control_last_result = {"result": {"artifacts": [scene]}}
        plugin._open_authoring_scene()
        for _i in range(30): await tree.process_frame
        var edited := EditorInterface.get_edited_scene_root()
        if mode == "roads":
            var points: RoadContainer = edited.get_node_or_null("Navigation/RoadNetwork/boulevard") if edited != null else null
            if points == null or points.get_roadpoints().size() != 5 or points.get_segments().size() != 4:
                _fail(tree, "ROAD_DOCK: source did not reopen/rebuild in editor")
                return
            var point: RoadPoint = points.get_node("west_bend")
            EditorInterface.edit_node(point)
            var faces: PackedVector3Array = points.get_segments()[0].road_mesh.mesh.get_faces()
            var width := point.lane_width
            point.lane_width = width + 0.25
            for _i in range(12): await tree.process_frame
            if faces == points.get_segments()[0].road_mesh.mesh.get_faces():
                _fail(tree, "ROAD_DOCK: real point edit did not rebuild mesh")
                return
            point.lane_width = width
            for _i in range(12): await tree.process_frame
            print("ARCONT_ROAD_DOCK_OK installed_panel=true point_edit_rebuild=true")
        else:
            if edited == null or edited.name != "UrbanWorkbench" or edited.get_node_or_null("Navigation/PocketTrees/ScatterOutput") == null:
                _fail(tree, "AUTHORING_DOCK: accepted scene did not open in actual editor")
                return
            print("ARCONT_AUTHORING_DOCK_OK installed_panel=true accepted_scene_opened=true")
    EditorInterface.get_selection().clear()
    while not EditorInterface.get_open_scenes().is_empty():
        if EditorInterface.close_scene() != OK: break
        for _i in range(5): await tree.process_frame
    for _i in range(5): await tree.process_frame
    tree.quit(0)

func _fail(tree: SceneTree, message: String) -> void:
    push_error(message)
    tree.quit(1)
