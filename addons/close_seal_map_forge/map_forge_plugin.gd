@tool
extends EditorPlugin

const CANVAS_SCRIPT = preload("res://addons/close_seal_map_forge/map_forge_canvas.gd")

var dock: VBoxContainer
var map_picker: OptionButton
var map_canvas: Control
var selection_label: Label
var dirty_label: Label
var width_editor: SpinBox
var audit_label: RichTextLabel
var provider_label: RichTextLabel
var current_map_path := ""
var current_map: Dictionary = {}
var map_paths: Array[String] = []
var selected_path: Array = []
var selected_kind := ""
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _dirty := false
var _updating_inspector := false

const PROVIDERS := [
    {"name":"Terrain3D", "class":"Terrain3D", "path":"res://addons/terrain_3d/plugin.cfg", "role":"Terrain"},
    {"name":"Cyclops", "class":"CyclopsLevelBuilder", "path":"res://addons/cyclops_level_builder/plugin.cfg", "role":"Structures"},
    {"name":"ProtonScatter", "class":"ProtonScatter", "path":"res://addons/proton_scatter/plugin.cfg", "role":"Scatter"},
    {"name":"FuncGodot", "class":"FuncGodotMap", "path":"res://addons/func_godot/plugin.cfg", "role":"Import"},
]

func _enter_tree() -> void:
    dock = VBoxContainer.new()
    dock.name = "Map Forge"
    dock.custom_minimum_size = Vector2(390, 560)
    var title := Label.new()
    title.text = "CLOSE SEAL — MAP FORGE 0.3"
    title.add_theme_font_size_override("font_size", 18)
    dock.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "Direct tactical authoring • audit • provider-neutral maps"
    subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    dock.add_child(subtitle)
    var toolbar := HBoxContainer.new()
    dock.add_child(toolbar)
    map_picker = OptionButton.new()
    map_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    map_picker.item_selected.connect(_on_map_selected)
    toolbar.add_child(map_picker)
    _add_button(toolbar, "Reload", _reload_everything, "Discard unsaved in-memory edits and reload files")
    _add_button(toolbar, "Frame", _frame_map, "Reset tactical preview pan and zoom")
    var editbar := HBoxContainer.new()
    dock.add_child(editbar)
    _add_button(editbar, "Save", _save_current_map, "Validate and save canonical JSON")
    _add_button(editbar, "Undo", _undo, "Undo last Map Forge edit")
    _add_button(editbar, "Redo", _redo, "Redo last Map Forge edit")
    _add_button(editbar, "Sym X", _enforce_x_symmetry, "Enforce competitive X-axis symmetry")
    var addbar := HBoxContainer.new()
    dock.add_child(addbar)
    _add_button(addbar, "+ Objective", _add_objective, "Add a center objective, then drag it")
    _add_button(addbar, "+ Choke", _add_choke, "Add a center choke region, then drag it")
    dirty_label = Label.new()
    dirty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    dirty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    addbar.add_child(dirty_label)
    var tabs := TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    dock.add_child(tabs)
    var map_tab := VBoxContainer.new()
    map_tab.name = "Map"
    tabs.add_child(map_tab)
    map_canvas = CANVAS_SCRIPT.new()
    map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    map_canvas.selection_changed.connect(_on_feature_selected)
    map_canvas.edit_started.connect(_begin_edit)
    map_canvas.feature_moved.connect(_on_feature_moved)
    map_tab.add_child(map_canvas)
    selection_label = Label.new()
    selection_label.text = "Selection: none"
    selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    map_tab.add_child(selection_label)
    var inspect_row := HBoxContainer.new()
    map_tab.add_child(inspect_row)
    var width_label := Label.new()
    width_label.text = "Width / formation"
    inspect_row.add_child(width_label)
    width_editor = SpinBox.new()
    width_editor.min_value = 0.5
    width_editor.max_value = 50.0
    width_editor.step = 0.1
    width_editor.value = 6.0
    width_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    width_editor.value_changed.connect(_on_width_changed)
    inspect_row.add_child(width_editor)
    var audit_tab := VBoxContainer.new()
    audit_tab.name = "Audit"
    tabs.add_child(audit_tab)
    var audit_toolbar := HBoxContainer.new()
    audit_tab.add_child(audit_toolbar)
    _add_button(audit_toolbar, "Audit current", _refresh_audit)
    _add_button(audit_toolbar, "Validate all", _validate_all_maps)
    audit_label = RichTextLabel.new()
    audit_label.bbcode_enabled = true
    audit_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    audit_label.fit_content = false
    audit_tab.add_child(audit_label)
    var providers_tab := VBoxContainer.new()
    providers_tab.name = "Providers"
    tabs.add_child(providers_tab)
    _add_button(providers_tab, "Refresh providers", _refresh_provider_status)
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

func _add_button(parent: Node, text: String, callback: Callable, tooltip := "") -> Button:
    var button := Button.new()
    button.text = text
    button.tooltip_text = tooltip
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

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
    selected_path.clear()
    selected_kind = ""
    _undo_stack.clear()
    _redo_stack.clear()
    _dirty = false
    map_canvas.set_map_data(current_map)
    selection_label.text = "Selection: none"
    _update_dirty_label()
    _refresh_audit()

func _frame_map() -> void:
    if map_canvas:
        map_canvas.frame_map()

func _on_feature_selected(id: String, kind: String, path: Array) -> void:
    selected_path = path.duplicate(true)
    selected_kind = kind
    selection_label.text = "Selection: %s  •  %s" % [id, kind]
    _sync_width_editor()

func _sync_width_editor() -> void:
    _updating_inspector = true
    var width := 6.0
    if selected_path.size() >= 2:
        if selected_path[0] == "routes":
            var routes: Array = current_map.get("routes", [])
            var route: Dictionary = routes[int(selected_path[1])]
            width = float(route.get("width", 6.0))
        elif selected_path[0] == "regions":
            var regions: Array = current_map.get("regions", [])
            var region: Dictionary = regions[int(selected_path[1])]
            width = float(region.get("width", 6.0))
    width_editor.value = width
    map_canvas.set_formation_width(width)
    _updating_inspector = false

func _begin_edit() -> void:
    _push_undo_snapshot()

func _push_undo_snapshot() -> void:
    _undo_stack.append(current_map.duplicate(true))
    if _undo_stack.size() > 64:
        _undo_stack.pop_front()
    _redo_stack.clear()

func _on_feature_moved(path: Array, world_position: Vector3) -> void:
    if _set_vector_path(path, world_position):
        _mark_dirty()
        map_canvas.refresh()
        _refresh_audit()

func _set_vector_path(path: Array, value: Vector3) -> bool:
    var encoded := [value.x, value.y, value.z]
    if path.size() == 3 and path[0] == "bases":
        var bases: Array = current_map.get("bases", [])
        var bi := int(path[1])
        if bi < 0 or bi >= bases.size(): return false
        var base: Dictionary = bases[bi]
        base[String(path[2])] = encoded
        return true
    if path.size() == 3 and path[0] == "objectives":
        var objectives: Array = current_map.get("objectives", [])
        var oi := int(path[1])
        if oi < 0 or oi >= objectives.size(): return false
        var objective: Dictionary = objectives[oi]
        objective[String(path[2])] = encoded
        return true
    if path.size() == 3 and path[0] == "regions":
        var regions: Array = current_map.get("regions", [])
        var rgi := int(path[1])
        if rgi < 0 or rgi >= regions.size(): return false
        var region: Dictionary = regions[rgi]
        region[String(path[2])] = encoded
        return true
    if path.size() == 4 and path[0] == "routes" and path[2] == "points":
        var routes: Array = current_map.get("routes", [])
        var ri := int(path[1])
        var pi := int(path[3])
        if ri < 0 or ri >= routes.size(): return false
        var route: Dictionary = routes[ri]
        var points: Array = route.get("points", [])
        if pi < 0 or pi >= points.size(): return false
        points[pi] = encoded
        return true
    return false

func _on_width_changed(value: float) -> void:
    if _updating_inspector or current_map.is_empty():
        return
    map_canvas.set_formation_width(value)
    if selected_path.size() < 2:
        return
    if selected_path[0] == "routes":
        _push_undo_snapshot()
        var routes: Array = current_map.get("routes", [])
        var route: Dictionary = routes[int(selected_path[1])]
        route["width"] = value
        _mark_dirty()
    elif selected_path[0] == "regions":
        _push_undo_snapshot()
        var regions: Array = current_map.get("regions", [])
        var region: Dictionary = regions[int(selected_path[1])]
        region["width"] = value
        _mark_dirty()
    map_canvas.refresh()
    _refresh_audit()

func _undo() -> void:
    if _undo_stack.is_empty(): return
    _redo_stack.append(current_map.duplicate(true))
    current_map = _undo_stack.pop_back()
    map_canvas.set_map_data(current_map)
    _mark_dirty()
    _refresh_audit()

func _redo() -> void:
    if _redo_stack.is_empty(): return
    _undo_stack.append(current_map.duplicate(true))
    current_map = _redo_stack.pop_back()
    map_canvas.set_map_data(current_map)
    _mark_dirty()
    _refresh_audit()

func _add_objective() -> void:
    _push_undo_snapshot()
    var objectives: Array = current_map.get("objectives", [])
    var id := _unique_id(objectives, "objective")
    objectives.append({"id": id, "type": "seal", "position": [0.0, 0.0, 0.0], "radius": 3.0})
    current_map["objectives"] = objectives
    _mark_dirty()
    map_canvas.refresh()
    _refresh_audit()

func _add_choke() -> void:
    _push_undo_snapshot()
    var regions: Array = current_map.get("regions", [])
    var id := _unique_id(regions, "choke")
    regions.append({"id": id, "kind": "choke", "center": [0.0, 0.0, 0.0], "width": 6.0})
    current_map["regions"] = regions
    _mark_dirty()
    map_canvas.refresh()
    _refresh_audit()

func _unique_id(items: Array, prefix: String) -> String:
    var used: Dictionary = {}
    for value in items:
        if typeof(value) == TYPE_DICTIONARY:
            used[String(value.get("id", ""))] = true
    var index := 1
    while used.has("%s_%02d" % [prefix, index]):
        index += 1
    return "%s_%02d" % [prefix, index]

func _mirror_vector_x(value) -> Array:
    var v := CloseSealMapContract.vec3_from(value)
    return [-v.x, v.y, v.z]

func _enforce_x_symmetry() -> void:
    if current_map.is_empty(): return
    _push_undo_snapshot()
    var bases: Array = current_map.get("bases", [])
    if bases.size() >= 2 and typeof(bases[0]) == TYPE_DICTIONARY and typeof(bases[1]) == TYPE_DICTIONARY:
        var source: Dictionary = bases[0]
        var target: Dictionary = bases[1]
        target["position"] = _mirror_vector_x(source.get("position", []))
        if source.has("hero_spawn"):
            target["hero_spawn"] = _mirror_vector_x(source.get("hero_spawn", []))
    var routes: Array = current_map.get("routes", [])
    for route_value in routes:
        if typeof(route_value) != TYPE_DICTIONARY: continue
        var route: Dictionary = route_value
        var points: Array = route.get("points", [])
        var count := points.size()
        var half_count := int(count / 2)
        for i in range(half_count):
            points[count - 1 - i] = _mirror_vector_x(points[i])
        if count % 2 == 1:
            var center_index := half_count
            var center := CloseSealMapContract.vec3_from(points[center_index])
            points[center_index] = [0.0, center.y, center.z]
    var regions: Array = current_map.get("regions", [])
    var by_id: Dictionary = {}
    for region_value in regions:
        if typeof(region_value) == TYPE_DICTIONARY:
            by_id[String(region_value.get("id", ""))] = region_value
    for key in by_id.keys():
        var id := String(key)
        if id.contains("west"):
            var east_id := id.replace("west", "east")
            if by_id.has(east_id):
                var west: Dictionary = by_id[id]
                var east: Dictionary = by_id[east_id]
                east["center"] = _mirror_vector_x(west.get("center", []))
                if west.has("width"):
                    east["width"] = west["width"]
    _mark_dirty()
    map_canvas.refresh()
    _refresh_audit()

func _save_current_map() -> void:
    if current_map_path.is_empty() or current_map.is_empty(): return
    var errors := CloseSealMapContract.validate(current_map)
    if not errors.is_empty():
        audit_label.text = "[color=red][b]Save blocked: contract errors[/b][/color]\n• " + "\n• ".join(errors)
        return
    var file := FileAccess.open(current_map_path, FileAccess.WRITE)
    if file == null:
        audit_label.text = "[color=red]Save failed: cannot write %s[/color]" % current_map_path
        return
    file.store_string(JSON.stringify(current_map, "  ", false) + "\n")
    file.close()
    _dirty = false
    _update_dirty_label()
    audit_label.text = "[color=green]Saved and validated:[/color] %s\n\n%s" % [current_map_path.get_file(), CloseSealMapAnalyzer.format_report(current_map)]
    get_editor_interface().get_resource_filesystem().scan()

func _mark_dirty() -> void:
    _dirty = true
    _update_dirty_label()

func _update_dirty_label() -> void:
    if dirty_label:
        dirty_label.text = "● UNSAVED" if _dirty else "✓ SAVED"

func _refresh_audit() -> void:
    if not audit_label: return
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
    if ClassDB.class_exists(StringName(provider.class)): return true
    return FileAccess.file_exists(provider.path)

func _refresh_provider_status() -> void:
    if not provider_label: return
    var lines: Array[String] = ["[b]Provider status[/b]"]
    var ready := 0
    for provider in PROVIDERS:
        var available := _provider_available(provider)
        if available: ready += 1
        var state := "[color=green]READY[/color]" if available else "[color=gray]OPTIONAL / NOT INSTALLED[/color]"
        lines.append("• %s — %s — %s" % [provider.name, provider.role, state])
    lines.append("")
    lines.append("%d / %d providers available" % [ready, PROVIDERS.size()])
    lines.append("")
    lines.append("[b]Canonical layers[/b]")
    lines.append("Terrain • Structures • Scatter • Gameplay • Navigation • Balance")
    provider_label.text = "\n".join(lines)
