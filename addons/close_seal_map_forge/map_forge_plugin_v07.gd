@tool
extends "res://addons/close_seal_map_forge/map_forge_plugin_v05.gd"

const NAV_PROBE = preload("res://src/map/map_navigation_probe.gd")

func _enter_tree() -> void:
    super._enter_tree()
    if dock == null:
        return
    var children := dock.get_children()
    if children.size() > 0 and children[0] is Label:
        var title: Label = children[0]
        title.text = "CLOSE SEAL — MAP FORGE 0.7"
    if children.size() > 1 and children[1] is Label:
        var subtitle: Label = children[1]
        subtitle.text = "World authoring • physical path queries • traffic telemetry • formation diagnostics"
    _install_probe_controls()

func _install_probe_controls() -> void:
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
    bar.name = "PhysicalProbeToolbar"
    _add_button(bar, "Physical Probe", _run_physical_probe, "Query NavigationServer3D against the compiled NavigationMesh")
    _add_button(bar, "Export Traffic", _export_physical_probe, "Export deterministic physical path-query traffic telemetry JSON")
    nav_tab.add_child(bar)
    nav_tab.move_child(bar, 2)

func _run_physical_probe() -> Dictionary:
    if current_map.is_empty():
        return {"ok": false, "error": "no map loaded"}
    var compiled: Dictionary = NAV_RUNTIME.compile_route_surface(current_map)
    if not bool(compiled.get("ok", false)):
        if navigation_label:
            navigation_label.text = "[color=red]Navigation surface compilation failed.[/color]"
        return compiled
    var navmesh: NavigationMesh = compiled.get("navigation_mesh")
    var telemetry: Dictionary = NAV_PROBE.probe(navmesh, current_map)
    if navigation_label:
        navigation_label.text = NAV_PROBE.format_report(telemetry)
    return telemetry

func _export_physical_probe() -> void:
    var telemetry: Dictionary = _run_physical_probe()
    if not bool(telemetry.get("ok", false)):
        return
    var path := NAV_PROBE.export_telemetry(current_map, telemetry)
    if navigation_label:
        navigation_label.text += "\n\n[color=green]Telemetry exported:[/color] %s" % path
    get_editor_interface().get_resource_filesystem().scan()
