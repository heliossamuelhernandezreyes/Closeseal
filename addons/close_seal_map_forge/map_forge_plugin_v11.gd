@tool
extends "res://addons/close_seal_map_forge/map_forge_plugin_v10.gd"

const WORLD_VIEW = preload("res://addons/close_seal_map_forge/map_forge_world_view.gd")

var world_view: VBoxContainer
var control_request: TextEdit
var control_status: Label
var control_tool: LineEdit
var control_timer: Timer
var control_pid := -1
var control_output := ""
var control_mode: OptionButton
var control_response: TextEdit
var control_last_result: Dictionary = {}

func _enter_tree() -> void:
    super._enter_tree()
    if dock == null:
        return
    var tabs: TabContainer = null
    for child in dock.get_children():
        if child is TabContainer:
            tabs = child
            break
    if tabs == null:
        return
    world_view = WORLD_VIEW.new()
    world_view.document_edited.connect(_accept_world_edit)
    var world_tab := ScrollContainer.new()
    world_tab.name = "World 3D"
    world_tab.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    tabs.add_child(world_tab)
    world_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    world_tab.add_child(world_view)
    world_view.set_document(current_map)
    world_view.frame_map()
    _install_control_tab(tabs)
    var heading := dock.get_child(0)
    if heading is Label:
        heading.text = "CLOSE SEAL — MAP FORGE 1.3"

func _load_map(path: String) -> void:
    super._load_map(path)
    _refresh_world()

func _refresh_audit() -> void:
    super._refresh_audit()
    _refresh_world()

func _refresh_world() -> void:
    if world_view != null:
        world_view.set_document(current_map)

func _accept_world_edit(document: Dictionary) -> void:
    _push_undo_snapshot()
    current_map = document.duplicate(true)
    map_canvas.set_map_data(current_map)
    _mark_dirty()
    _refresh_audit()

func _install_control_tab(tabs: TabContainer) -> void:
    var panel := VBoxContainer.new()
    panel.name = "Control"
    tabs.add_child(panel)
    var note := Label.new()
    note.text = "Editor control for a human or assistant. You supply every design decision; no generative model or API key is used."
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    panel.add_child(note)
    control_mode = OptionButton.new()
    control_mode.add_item("Map contract")
    control_mode.add_item("Godot nodes, resources and provider APIs")
    control_mode.item_selected.connect(_select_control_mode)
    panel.add_child(control_mode)
    control_tool = LineEdit.new()
    control_tool.placeholder_text = "Absolute path to Arcont/tools/map_forge_control.py"
    var arcont_root := OS.get_environment("ARCONT_ROOT")
    if not arcont_root.is_empty():
        control_tool.text = arcont_root.path_join("tools/map_forge_control.py")
    panel.add_child(control_tool)
    control_request = TextEdit.new()
    control_request.custom_minimum_size = Vector2(340, 260)
    control_request.text = JSON.stringify({"protocol_version": 1, "operation": "capabilities"}, "  ")
    panel.add_child(control_request)
    var bar := HBoxContainer.new()
    panel.add_child(bar)
    _add_button(bar, "Run request", _run_control_request)
    _add_button(bar, "Inspect map", _inspect_control_map)
    var tool_bar := HBoxContainer.new()
    panel.add_child(tool_bar)
    _add_button(tool_bar, "Discover tools", _discover_authoring_tools)
    _add_button(tool_bar, "Open built scene", _open_authoring_scene)
    control_status = Label.new()
    control_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    panel.add_child(control_status)
    control_response = TextEdit.new()
    control_response.editable = false
    control_response.custom_minimum_size = Vector2(340, 220)
    panel.add_child(control_response)
    control_timer = Timer.new()
    control_timer.wait_time = 0.25
    control_timer.timeout.connect(_poll_control_request)
    panel.add_child(control_timer)

func _select_control_mode(index: int) -> void:
    var filename := "godot_authoring_control.py" if index == 1 else "map_forge_control.py"
    var arcont_root := OS.get_environment("ARCONT_ROOT")
    if not arcont_root.is_empty():
        control_tool.text = arcont_root.path_join("tools/" + filename)
    elif not control_tool.text.is_empty():
        control_tool.text = control_tool.text.get_base_dir().path_join(filename)
    control_tool.placeholder_text = "Absolute path to Arcont/tools/" + filename
    control_request.text = JSON.stringify({"protocol_version": 1, "operation": "capabilities"}, "  ")

func _discover_authoring_tools() -> void:
    if control_pid > 0:
        return
    control_mode.select(1)
    _select_control_mode(1)
    control_request.text = JSON.stringify({"protocol_version": 1, "operation": "discover"}, "  ")
    _run_control_request()

func _open_authoring_scene() -> void:
    if control_pid > 0:
        return
    var result: Dictionary = control_last_result.get("result", {})
    for path in result.get("artifacts", []):
        if String(path).ends_with(".tscn") and FileAccess.file_exists(String(path)):
            get_editor_interface().open_scene_from_path(ProjectSettings.localize_path(String(path)))
            return
    control_status.text = "Run a successful scene recipe with a save step first."

func _inspect_control_map() -> void:
    if control_pid > 0:
        return
    control_mode.select(0)
    _select_control_mode(0)
    control_request.text = JSON.stringify({"protocol_version": 1, "operation": "inspect", "map_id": current_map.get("id", "")}, "  ")
    _run_control_request()

func _run_control_request() -> void:
    if control_pid > 0:
        return
    if _dirty:
        control_status.text = "Save pending visual edits before using external editor control."
        return
    if not FileAccess.file_exists(control_tool.text):
        control_status.text = "Set the Arcont control tool path or ARCONT_ROOT."
        return
    var request = JSON.parse_string(control_request.text)
    if not request is Dictionary:
        control_status.text = "Request must be a JSON object."
        return
    var directory := ProjectSettings.globalize_path("res://.mapforge/control")
    DirAccess.make_dir_recursive_absolute(directory)
    var input := directory.path_join("editor-request.json")
    control_output = directory.path_join("editor-response.json")
    if FileAccess.file_exists(control_output):
        DirAccess.remove_absolute(control_output)
    var file := FileAccess.open(input, FileAccess.WRITE)
    if file == null:
        control_status.text = "Request could not be written."
        return
    file.store_string(JSON.stringify(request))
    file.close()
    if OS.get_environment("GODOT_BIN").is_empty():
        OS.set_environment("GODOT_BIN", OS.get_executable_path())
    control_pid = OS.create_process("python3", [control_tool.text, "--project", ProjectSettings.globalize_path("res://"), "--request", input, "--output", control_output])
    if control_pid < 0:
        control_status.text = "Python could not be started."
        return
    control_status.text = "Editor control is running…"
    control_timer.start()

func _poll_control_request() -> void:
    if OS.is_process_running(control_pid):
        return
    control_timer.stop()
    control_pid = -1
    if not FileAccess.file_exists(control_output):
        control_status.text = "Control process ended without a response."
        return
    var file := FileAccess.open(control_output, FileAccess.READ)
    var result = JSON.parse_string(file.get_as_text())
    if not result is Dictionary:
        control_status.text = "Invalid control response."
        return
    control_last_result = result
    control_response.text = JSON.stringify(result, "  ")
    if result.get("ok", false):
        control_status.text = "Completed. " + ("Published revision." if result.get("committed", false) else "Source unchanged.")
    else:
        control_status.text = String(result.get("error", "Request failed; read the response."))
    if bool(result.get("committed", false)):
        get_editor_interface().get_resource_filesystem().scan()
        _reload_everything()
