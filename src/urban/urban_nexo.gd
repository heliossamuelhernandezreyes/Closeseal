extends Node3D

const VISUALS = preload("res://src/prototype/map_visual_kit.gd")
const EXPLORER = preload("res://src/urban/urban_explorer.gd")
var player: CharacterBody3D
var aerial: Camera3D
var label: Label
var checkpoints: Array
var checkpoint_index := 0
var overview := false

func _ready() -> void:
    var file := FileAccess.open("res://maps/urban_nexo_01.json", FileAccess.READ)
    var data: Dictionary = JSON.parse_string(file.get_as_text())
    var world := Node3D.new()
    world.name = "DistritoNexo"
    add_child(world)
    var stats: Dictionary = VISUALS.new(world,data).build()
    if not stats.get("errors",[]).is_empty():
        push_error("Urban assets unavailable: import the project before running")
        return
    checkpoints = data["urban_design"]["checkpoints"]
    player = EXPLORER.new()
    player.name = "Explorer"
    player.position = Vector3(25,0.35,25)
    add_child(player)
    player.rotation.y = deg_to_rad(45)
    aerial = Camera3D.new()
    aerial.name = "CityOverview"
    aerial.position = Vector3(470,370,470)
    aerial.fov = 52
    aerial.far = 1800
    add_child(aerial)
    aerial.look_at(Vector3(0,10,0))
    var ui := CanvasLayer.new()
    add_child(ui)
    var panel := PanelContainer.new()
    panel.position = Vector2(20,20)
    ui.add_child(panel)
    label = Label.new()
    label.add_theme_font_size_override("font_size",18)
    panel.add_child(label)
    _update_label()
    var crosshair := Label.new()
    crosshair.text = "+"
    crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    ui.add_child(crosshair)

func _update_label() -> void:
    label.text = "  DISTRITO NEXO  |  512 x 512 m\n  WASD caminar · Shift correr · Espacio saltar\n  R volver a plaza · G visitar distrito · Tab vista general · Esc liberar raton\n  " + String(checkpoints[checkpoint_index]["label"]) + "  "

func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.physical_keycode == KEY_TAB:
        overview = not overview
        player.enabled = not overview
        if overview:
            aerial.make_current()
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        else:
            player.camera.make_current()
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    elif event.physical_keycode in [KEY_G,KEY_R]:
        checkpoint_index = (checkpoint_index+1)%checkpoints.size() if event.physical_keycode == KEY_G else 0
        var p: Array = checkpoints[checkpoint_index]["position"]
        player.teleport(Vector3(float(p[0]),float(p[1]),float(p[2])))
        _update_label()
