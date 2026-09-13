@tool
extends EditorPlugin

const CANVAS_SCRIPT = preload("res://addons/close_seal_map_forge/map_forge_canvas.gd")

var dock: VBoxContainer
var map_picker: OptionButton
var map_canvas: Control
var selection_label: Label
var audit_label: RichTextLabel
var provider_label: RichTextLabel
var current_map_path := ""
var current_map: Dictionary = {}
var map_paths: Array[String] = []

const PROVIDERS := [
    {"name":"Terrain3D", "class":"Terrain3D", "path":"res://addons/terrain_3d/plugin.cfg", "role":"Terrain"},
    {"name":"Cyclops", "class":"CyclopsLevelBuilder", "path":"res://addons/cyclops_level_builder/plugin.cfg", "role":"Structures"},
    {"name":"ProtonScatter", "class":"ProtonScatter", "path":"res://addons/proton_scatter/plugin.cfg", "role":"Scatter"},
    {"name":"FuncGodot", "class":"FuncGodotMap", "path":"res://addons/func_godot/plugin.cfg", "role":"Import"},
]

func _enter_tree() -> void:
    dock = VBoxContainer.new()
    dock.name = "Map Forge"
    dock.custom_minimum_size = Vector2(360, 520)

    var title := Label.new()
    title.text = "CLOSE SEAL — MAP FORGE 0.2"
    title.add_theme_font_size_override("font_size", 18)
    dock.add_child(title)

    var subtitle := Label.new()
    subtitle.text = "Author • inspect • audit tactical maps without provider lock-in"
    subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    dock.add_child(subtitle)

    var toolbar := HBoxContainer.new()
    dock.add_child(toolbar)

    map_picker = OptionButton.new()
    map_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    map_picker.item_selected.connect(_on_map_selected)
    toolbar.add_child(map_picker)

    var reload := Button.new()
    reload.text = "Reload"
    reload.tooltip_text = "Reload map files and provider state"
    reload.pressed.connect(_reload_everything)
    toolbar.add_child(reload)

    var frame := Button.new()
    frame.text = "Frame"
    frame.tooltip_text = "Reset tactical preview pan and zoom"
    frame.pressed.connect(_frame_map)
    toolbar.add_child(frame)

    var tabs := TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    dock.add_child(tabs)

    var map_tab := VBoxContainer.new()
    map_tab.name = "Map"
    tabs.add_child(map_tab)

    map_canvas = CANVAS_SCRIPT.new()
    map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    map_canvas.selection_changed.connect(_on_feature_selected)
    map_tab.add_child(map_canvas)

    selection_label = Label.new()
    selection_label.text = "Selection: none"
    selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    map_tab.add_child(selection_label)

    var audit_tab := VBoxContainer.new()
    audit_tab.name = "Audit"
    tabs.add_child(audit_tab)

    var audit_toolbar := HBoxContainer.new()
    audit_tab.add_child(audit_toolbar)
    var validate_current := Button.new()
    validate_current.text = "Audit current"
    validate_current.pressed.connect(_refresh_audit)
    audit_toolbar.add_child(validate_current)
    var validate_all := Button.new()
    validate_all.text = "Validate all"
    validate_all.pressed.connect(_validate_all_maps)
    audit_toolbar.add_child(validate_all)

    audit_label = RichTextLabel.new()
    audit_label.bbcode_enabled = true
    audit_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    audit_label.fit_content = false
    audit_tab.add_child(audit_label)

    var providers_tab := VBoxContainer.new()
    providers_tab.name = "Providers"
    tabs.add_child(providers_tab)
    var refresh_providers := Button.new()
    refresh_providers.text = "Refresh providers"
    refresh_providers.pressed.connect(_refresh_provider_status)
    providers_tab.add_child(refresh_providers)

    provider_label = RichTextLabel.new()
    provider_label.fit_content = true
    provider_label.bbcode_enabled = true
    provider_label.custom_minimum_size = Vector2(320, 250)
    providers_tab.add_child(provider_label)

    var note := Label.new()
    note.text = "Canonical gameplay topology remains provider-neutral. Terrain3D, Cyclops, ProtonScatter and FuncGodot are authoring providers, never owners of Close Seal gameplay data."
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    providers_tab.add_child(note)

    add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
    _reload_everything()

func _exit_tree() -> void:
    if dock:
        remove_control_from_docks(dock)
        dock.queue_free()

func _reload_everything() -> void:
    _discover_maps()
    _refresh_provider_status()
    if map_picker.item_count > 0:
        _load_map(map_paths[map_picker.selected])

func _discover_maps() -> void:
    var previous := current_map_path
    map_paths.clear()
    map_picker.clear()
    var dir := DirAccess.open("res://maps")
    if dir == null:
        return
    dir.list_dir_begin()
    while true:
        var file_name := dir.get_next()
        if file_name.is_empty():
            break
        if dir.current_is_dir() or not file_name.ends_with(".json"):
            continue
        map_paths.append("res://maps/" + file_name)
    dir.list_dir_end()
    map_paths.sort()
    var selected_index := 0
    for i in range(map_paths.size()):
        var path := map_paths[i]
        var display := path.get_file().get_basename().replace("_", " ").capitalize()
        map_picker.add_item(display)
        if path == previous:
            selected_index = i
    if map_picker.item_count > 0:
        map_picker.select(selected_index)

func _on_map_selected(index: int) -> void:
    if index >= 0 and index < map_paths.size():
        _load_map(map_paths[index])

func _load_map(path: String) -> void:
    current_map_path = path
    current_map = CloseSealMapContract.load_file(path)
    map_canvas.set_map_data(current_map)
    selection_label.text = "Selection: none"
    _refresh_audit()

func _frame_map() -> void:
    if map_canvas:
        map_canvas.frame_map()

func _on_feature_selected(id: String, kind: String) -> void:
    selection_label.text = "Selection: %s  •  %s" % [id, kind]

func _refresh_audit() -> void:
    if not audit_label:
        return
    if current_map.is_empty():
        audit_label.text = "[color=red]Current map could not be loaded or failed structural validation.[/color]"
        return
    audit_label.text = CloseSealMapAnalyzer.format_report(current_map)

func _validate_all_maps() -> void:
    var lines: Array[String] = ["[b]All map contracts[/b]", ""]
    var valid := 0
    for path in map_paths:
        var file := FileAccess.open(path, FileAccess.READ)
        if file == null:
            lines.append("[color=red]FAIL[/color] %s — unreadable" % path.get_file())
            continue
        var parsed = JSON.parse_string(file.get_as_text())
        if typeof(parsed) != TYPE_DICTIONARY:
            lines.append("[color=red]FAIL[/color] %s — invalid JSON root" % path.get_file())
            continue
        var errors := CloseSealMapContract.validate(parsed)
        if errors.is_empty():
            valid += 1
            lines.append("[color=green]PASS[/color] %s" % path.get_file())
        else:
            lines.append("[color=red]FAIL[/color] %s" % path.get_file())
            for error in errors:
                lines.append("  • " + String(error))
    lines.append("")
    lines.append("%d / %d maps structurally valid" % [valid, map_paths.size()])
    audit_label.text = "\n".join(lines)

func _provider_available(provider: Dictionary) -> bool:
    if ClassDB.class_exists(StringName(provider.class)):
        return true
    return FileAccess.file_exists(provider.path)

func _refresh_provider_status() -> void:
    if not provider_label:
        return
    var lines: Array[String] = []
    lines.append("[b]Provider status[/b]")
    var ready := 0
    for provider in PROVIDERS:
        var available := _provider_available(provider)
        if available:
            ready += 1
        var state := "[color=green]READY[/color]" if available else "[color=gray]OPTIONAL / NOT INSTALLED[/color]"
        lines.append("• %s — %s — %s" % [provider.name, provider.role, state])
    lines.append("")
    lines.append("%d / %d providers available" % [ready, PROVIDERS.size()])
    lines.append("")
    lines.append("[b]Canonical layers[/b]")
    lines.append("Terrain • Structures • Scatter • Gameplay • Navigation • Balance")
    provider_label.text = "\n".join(lines)
