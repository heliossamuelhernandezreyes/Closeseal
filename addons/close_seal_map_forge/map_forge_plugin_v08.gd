@tool
extends "res://addons/close_seal_map_forge/map_forge_plugin_physical_sync.gd"

const ARMY_RUNTIME = preload("res://src/map/map_army_runtime_probe.gd")

func _enter_tree() -> void:
    super._enter_tree()
    if dock == null:
        return
    var children := dock.get_children()
    if children.size() > 0 and children[0] is Label:
        var title: Label = children[0]
        title.text = "CLOSE SEAL — MAP FORGE 0.8"
    if children.size() > 1 and children[1] is Label:
        var subtitle: Label = children[1]
        subtitle.text = "World authoring • physical navigation • executable army flow • congestion telemetry"
    _install_army_runtime_controls()

func _install_army_runtime_controls() -> void:
    var tabs: TabContainer = null
    for child in dock.get_children():
        if child is TabContainer:
            tabs = child
            break
    if tabs == null:
        return
    var nav_tab := tabs.get_node_or_null("Navigation")
    if nav_tab == null or not nav_tab is VBoxContainer:
        return
    var bar := HBoxContainer.new()
    bar.name = "ArmyRuntimeToolbar"
    _add_button(bar, "Army Runtime", _run_army_runtime, "Run executable NavigationServer3D avoidance agents for 10/50/100/500-unit flow")
    _add_button(bar, "Export Crowd", _export_army_runtime, "Export executable crowd traversal and congestion telemetry JSON")
    nav_tab.add_child(bar)
    nav_tab.move_child(bar, mini(3, nav_tab.get_child_count() - 1))

func _run_army_runtime() -> Dictionary:
    if current_map.is_empty():
        return {"ok": false, "error": "no map loaded"}
    if navigation_label:
        navigation_label.text = "[b]Executable Army Flow[/b]\nRunning 10 / 50 / 100 / 500 avoidance-agent probes..."
    var telemetry: Dictionary = await ARMY_RUNTIME.run(get_tree(), current_map, [10, 50, 100, 500])
    if navigation_label:
        navigation_label.text = ARMY_RUNTIME.format_report(telemetry)
    return telemetry

func _export_army_runtime() -> void:
    var telemetry: Dictionary = await _run_army_runtime()
    if not bool(telemetry.get("ok", false)):
        return
    var path := ARMY_RUNTIME.export_telemetry(current_map, telemetry)
    if navigation_label:
        navigation_label.text += "\n\n[color=green]Crowd telemetry exported:[/color] %s" % path
    get_editor_interface().get_resource_filesystem().scan()
