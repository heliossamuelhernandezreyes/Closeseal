@tool
extends EditorPlugin

var dock: VBoxContainer
var status_label: RichTextLabel

const PROVIDERS := [
    {"name":"Terrain3D", "class":"Terrain3D", "path":"res://addons/terrain_3d/plugin.cfg", "role":"Terrain"},
    {"name":"Cyclops", "class":"CyclopsLevelBuilder", "path":"res://addons/cyclops_level_builder/plugin.cfg", "role":"Structures"},
    {"name":"ProtonScatter", "class":"ProtonScatter", "path":"res://addons/proton_scatter/plugin.cfg", "role":"Scatter"},
    {"name":"FuncGodot", "class":"FuncGodotMap", "path":"res://addons/func_godot/plugin.cfg", "role":"Import"},
]

func _enter_tree() -> void:
    dock = VBoxContainer.new()
    dock.name = "Map Forge"
    var title := Label.new()
    title.text = "CLOSE SEAL — MAP FORGE"
    title.add_theme_font_size_override("font_size", 18)
    dock.add_child(title)

    var subtitle := Label.new()
    subtitle.text = "Canonical RTS map contract + optional authoring providers"
    subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    dock.add_child(subtitle)

    var refresh := Button.new()
    refresh.text = "Refresh providers"
    refresh.pressed.connect(_refresh_status)
    dock.add_child(refresh)

    status_label = RichTextLabel.new()
    status_label.fit_content = true
    status_label.bbcode_enabled = true
    status_label.custom_minimum_size = Vector2(300, 220)
    dock.add_child(status_label)

    var note := Label.new()
    note.text = "Gameplay metadata stays plugin-neutral. Missing providers fall back to native Godot workflows."
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    dock.add_child(note)

    add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
    _refresh_status()

func _exit_tree() -> void:
    if dock:
        remove_control_from_docks(dock)
        dock.queue_free()

func _provider_available(provider: Dictionary) -> bool:
    if ClassDB.class_exists(StringName(provider.class)):
        return true
    return FileAccess.file_exists(provider.path)

func _refresh_status() -> void:
    if not status_label:
        return
    var lines: Array[String] = []
    lines.append("[b]Provider status[/b]")
    for provider in PROVIDERS:
        var available := _provider_available(provider)
        var state := "READY" if available else "OPTIONAL / NOT INSTALLED"
        lines.append("• %s — %s — %s" % [provider.name, provider.role, state])
    lines.append("")
    lines.append("[b]Canonical layers[/b]")
    lines.append("Terrain • Structures • Scatter • Gameplay • Navigation • Balance")
    status_label.text = "\n".join(lines)
