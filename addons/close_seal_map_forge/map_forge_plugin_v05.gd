@tool
extends "res://addons/close_seal_map_forge/map_forge_plugin_v04.gd"

const NAV_ANALYZER = preload("res://src/map/map_navigation_analyzer.gd")
const NAV_LAYER = preload("res://addons/close_seal_map_forge/map_forge_navigation_layer.gd")
const NAV_RUNTIME = preload("res://src/map/map_navigation_runtime.gd")

var navigation_label: RichTextLabel
var formation_width_editor: SpinBox

func _enter_tree() -> void:
    super._enter_tree()
    if dock == null:
        return
    var children := dock.get_children()
    if children.size() > 0 and children[0] is Label:
        var title: Label = children[0]
        title.text = "CLOSE SEAL — MAP FORGE 0.6"
    if children.size() > 1 and children[1] is Label:
        var subtitle: Label = children[1]
        subtitle.text = "World authoring • compiled navigation surface • formation/army-flow diagnostics"
    _install_navigation_tab()

func _install_navigation_tab() -> void:
    var tabs: TabContainer = null
    for child in dock.get_children():
        if child is TabContainer:
            tabs = child
            break
    if tabs == null:
        return
    var nav_tab := VBoxContainer.new()
    nav_tab.name = "Navigation"
    tabs.add_child(nav_tab)

    var toolbar := HBoxContainer.new()
    nav_tab.add_child(toolbar)
    var formation_label := Label.new()
    formation_label.text = "Formation width"
    toolbar.add_child(formation_label)
    formation_width_editor = SpinBox.new()
    formation_width_editor.min_value = 0.5
    formation_width_editor.max_value = 30.0
    formation_width_editor.step = 0.25
    formation_width_editor.value = 6.0
    toolbar.add_child(formation_width_editor)
    _add_button(toolbar, "Analyze", _run_navigation_audit, "Analyze route clearance and formation fit against semantic blockers")
    _add_button(toolbar, "Army Flow", _run_army_flow, "Simulate geometric corridor capacity for 10/50/100/500 units")

    var worldbar := HBoxContainer.new()
    nav_tab.add_child(worldbar)
    _add_button(worldbar, "Compile World", _build_world_06, "Build provider workspace and compile canonical route corridors into a real NavigationMesh surface")
    _add_button(worldbar, "Compile + Open", _build_world_and_open_06, "Compile the 0.6 world and open the generated authoring scene")

    navigation_label = RichTextLabel.new()
    navigation_label.bbcode_enabled = true
    navigation_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    navigation_label.fit_content = false
    navigation_label.custom_minimum_size = Vector2(320, 280)
    nav_tab.add_child(navigation_label)

    var note := Label.new()
    note.text = "Map Forge 0.6 compiles canonical route corridors into NavigationMesh polygons and models formation/army capacity. This is stronger than a configured-empty bake target, but it still does not claim dynamic avoidance, device performance or terrain-derived walkability until runtime agent tests exist."
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    nav_tab.add_child(note)
    _run_navigation_audit()

func _run_navigation_audit() -> void:
    if navigation_label == null:
        return
    if current_map.is_empty():
        navigation_label.text = "[color=red]No valid map loaded.[/color]"
        return
    var formation_width := 6.0
    if formation_width_editor != null:
        formation_width = float(formation_width_editor.value)
    navigation_label.text = NAV_ANALYZER.format_report(current_map, formation_width)

func _run_army_flow() -> void:
    if navigation_label == null or current_map.is_empty():
        return
    navigation_label.text = NAV_RUNTIME.format_simulation_report(current_map)

func _build_world_06() -> Dictionary:
    var result: Dictionary = _build_provider_workspace()
    if not bool(result.get("ok", false)):
        return result
    var scene_path := String(result.get("scene_path", ""))
    var nav_result: Dictionary = NAV_LAYER.augment_scene(scene_path, current_map)
    result["navigation"] = nav_result
    if not bool(nav_result.get("ok", false)):
        if navigation_label:
            navigation_label.text = "[color=red][b]Navigation compilation failed[/b][/color]\n%s" % String(nav_result.get("error", "unknown"))
        return result
    get_editor_interface().get_resource_filesystem().scan()
    if navigation_label:
        navigation_label.text = NAV_RUNTIME.format_simulation_report(current_map)
        navigation_label.text += "\n\n[color=green][b]Navigation surface compiled[/b][/color]\n%d segments • %d polygons • %d vertices • %.1f m² corridor area" % [int(nav_result.get("segments", 0)), int(nav_result.get("polygons", 0)), int(nav_result.get("vertices", 0)), float(nav_result.get("walkable_area_estimate", 0.0))]
    return result

func _build_world_and_open_06() -> void:
    var result := _build_world_06()
    if not bool(result.get("ok", false)):
        return
    var scene_path := String(result.get("scene_path", ""))
    if not scene_path.is_empty():
        get_editor_interface().open_scene_from_path(scene_path)
