@tool
extends "res://addons/close_seal_map_forge/map_forge_plugin_v08.gd"

const PHYSICAL_WORLD = preload("res://src/map/map_physical_world.gd")

func _enter_tree() -> void:
    super._enter_tree()
    if dock == null: return
    var children := dock.get_children()
    if children.size() > 0 and children[0] is Label:
        children[0].text = "CLOSE SEAL — MAP FORGE 1.0"
    if children.size() > 1 and children[1] is Label:
        children[1].text = "Physical world • tactical terrain • formation navigation • mobile budgets • executable evidence"
    _install_physical_world_controls()

func _install_physical_world_controls() -> void:
    var tabs: TabContainer = null
    for child in dock.get_children():
        if child is TabContainer:
            tabs = child
            break
    if tabs == null: return
    var nav_tab := tabs.get_node_or_null("Navigation")
    if nav_tab == null or not nav_tab is VBoxContainer: return
    var bar := HBoxContainer.new()
    bar.name = "PhysicalWorld10Toolbar"
    _add_button(bar, "Physical Audit", _run_physical_world_audit, "Validate tactical blockers, passes, formation capacity and mobile budgets")
    _add_button(bar, "Build Physical", _build_physical_world, "Build provider workspace, navigation and collision-backed physical constraints")
    nav_tab.add_child(bar)
    nav_tab.move_child(bar, mini(4, nav_tab.get_child_count() - 1))

func _run_physical_world_audit() -> Dictionary:
    if current_map.is_empty(): return {"ok": false, "error": "no map loaded"}
    var result := PHYSICAL_WORLD.analyze(current_map)
    if navigation_label: navigation_label.text = PHYSICAL_WORLD.format_report(result)
    return result

func _build_physical_world() -> Dictionary:
    var result: Dictionary = _build_world_06()
    if not bool(result.get("ok", false)): return result
    var scene_path := String(result.get("scene_path", ""))
    var physical: Dictionary = PHYSICAL_WORLD.augment_scene(scene_path, current_map)
    result["physical_world"] = physical
    if navigation_label: navigation_label.text = PHYSICAL_WORLD.format_report(physical)
    if bool(physical.get("ok", false)):
        get_editor_interface().get_resource_filesystem().scan()
    return result
