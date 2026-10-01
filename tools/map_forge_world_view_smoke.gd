extends SceneTree

const VIEW = preload("res://addons/close_seal_map_forge/map_forge_world_view.gd")
const CONTRACT = preload("res://src/map/map_contract.gd")

var edits := 0

func _initialize() -> void:
    _run.call_deferred()

func _edited(_document: Dictionary) -> void:
    edits += 1

func _run() -> void:
    var view = VIEW.new()
    root.add_child(view)
    view.document_edited.connect(_edited)
    var data := CONTRACT.load_file("res://maps/competitive_lab_01.json")
    view.set_document(data)
    view.frame_map()
    await process_frame
    if view.handles.size() < 30 or view.content.get_node_or_null("VisualStructures") == null:
        push_error("WORLD_VIEW: canonical map did not materialize")
        quit(1)
        return
    view.selected_object = ["authoring", "terrain", "landforms", 0]
    view._show_selection()
    var edited := data.duplicate(true)
    edited["authoring"]["terrain"]["landforms"][0]["height"] = 18
    view.json_editor.text = JSON.stringify(edited["authoring"]["terrain"]["landforms"][0])
    view._apply_json()
    if edits != 1:
        push_error("WORLD_VIEW: valid 3D edit was not emitted")
        quit(2)
        return
    view.selected_object = []
    view.json_editor.text = "{}"
    view._apply_json()
    if edits != 1:
        push_error("WORLD_VIEW: invalid edit was accepted")
        quit(3)
        return
    print("MAP_FORGE_WORLD_VIEW_OK handles=%d edits=%d" % [view.handles.size(), edits])
    quit(0)
