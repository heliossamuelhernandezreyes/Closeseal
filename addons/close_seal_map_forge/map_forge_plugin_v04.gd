@tool
extends "res://addons/close_seal_map_forge/map_forge_plugin.gd"

const PROVIDER_BRIDGE = preload("res://addons/close_seal_map_forge/map_forge_provider_bridge.gd")

func _enter_tree() -> void:
    super._enter_tree()
    if dock == null:
        return
    var children := dock.get_children()
    if children.size() > 0 and children[0] is Label:
        var title: Label = children[0]
        title.text = "CLOSE SEAL — MAP FORGE 0.4"
    if children.size() > 1 and children[1] is Label:
        var subtitle: Label = children[1]
        subtitle.text = "Direct tactical authoring • physical provider bridge • runtime truth"
    _install_provider_bridge_controls()

func _install_provider_bridge_controls() -> void:
    var tabs: TabContainer = null
    for child in dock.get_children():
        if child is TabContainer:
            tabs = child
            break
    if tabs == null:
        return
    var providers_tab := tabs.get_node_or_null("Providers")
    if providers_tab == null or not providers_tab is VBoxContainer:
        return

    var bridge_bar := HBoxContainer.new()
    bridge_bar.name = "ProviderBridgeToolbar"
    _add_button(bridge_bar, "Build workspace", _build_provider_workspace, "Materialize provider-ready authoring scene from the current canonical map")
    _add_button(bridge_bar, "Build + Open", _build_and_open_provider_workspace, "Build provider workspace and open the generated scene in the Godot editor")
    providers_tab.add_child(bridge_bar)
    providers_tab.move_child(bridge_bar, 1)

    var bridge_note := Label.new()
    bridge_note.name = "ProviderBridgeNote"
    bridge_note.text = "Terrain3D is bootstrapped as an editable terrain node; ProtonScatter receives real zone shapes; Cyclops receives a dedicated workspace plus structure guides; FuncGodot gets an import socket. Generated data never replaces the canonical map contract."
    bridge_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    providers_tab.add_child(bridge_note)
    providers_tab.move_child(bridge_note, 2)

func _build_provider_workspace() -> Dictionary:
    if current_map.is_empty():
        if provider_label:
            provider_label.text = "[color=red]Provider bridge: no valid map loaded.[/color]"
        return {"ok": false}
    var result: Dictionary = PROVIDER_BRIDGE.build_authoring_scene(current_map)
    if not bool(result.get("ok", false)):
        if provider_label:
            var errors: Array = result.get("errors", [])
            provider_label.text = "[color=red][b]Provider workspace failed[/b][/color]\n• " + "\n• ".join(errors)
        return result
    get_editor_interface().get_resource_filesystem().scan()
    _refresh_provider_status()
    if provider_label:
        var scene_path := String(result.get("scene_path", ""))
        var providers: Dictionary = result.get("providers", {})
        var lines: Array[String] = [
            "[color=green][b]Provider workspace generated[/b][/color]",
            scene_path,
            "",
            "Terrain3D: %s" % _bridge_state(providers.get("terrain3d", {})),
            "Cyclops: %s" % _bridge_state(providers.get("cyclops", {})),
            "ProtonScatter: %s" % _bridge_state(providers.get("proton_scatter", {})),
            "FuncGodot: %s" % _bridge_state(providers.get("func_godot", {})),
            "",
            "The canonical JSON remains the source of truth."
        ]
        provider_label.text = "\n".join(lines)
    return result

func _build_and_open_provider_workspace() -> void:
    var result := _build_provider_workspace()
    if not bool(result.get("ok", false)):
        return
    var scene_path := String(result.get("scene_path", ""))
    if not scene_path.is_empty():
        get_editor_interface().open_scene_from_path(scene_path)

func _bridge_state(value) -> String:
    if typeof(value) != TYPE_DICTIONARY:
        return "unknown"
    var state: Dictionary = value
    if bool(state.get("materialized", false)):
        return "READY / %s" % String(state.get("mode", "materialized"))
    if bool(state.get("available", false)):
        return "AVAILABLE / %s" % String(state.get("mode", "not materialized"))
    return "FALLBACK / %s" % String(state.get("mode", "native"))
