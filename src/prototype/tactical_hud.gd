extends CanvasLayer

var selected_formation := "LINE"
var selected_squad := 1
var status_label: Label

var panel_tex: Texture2D
var ability_tex: Texture2D
var joystick_tex: Texture2D
var minimap_tex: Texture2D

func _ready() -> void:
    layer = 10
    # SVG textures are imported resources. Loading them at runtime avoids a
    # fresh-checkout parser dependency on Godot having imported them already.
    panel_tex = load("res://assets/ui/ornate_panel.svg") as Texture2D
    ability_tex = load("res://assets/ui/ability_ring.svg") as Texture2D
    joystick_tex = load("res://assets/ui/joystick_frame.svg") as Texture2D
    minimap_tex = load("res://assets/ui/minimap_frame.svg") as Texture2D
    _build_hud()

func _tex(parent: Node, texture: Texture2D, pos: Vector2, size_: Vector2, mouse := Control.MOUSE_FILTER_IGNORE) -> TextureRect:
    var t := TextureRect.new()
    t.texture = texture
    t.position = pos
    t.size = size_
    t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    t.mouse_filter = mouse
    parent.add_child(t)
    return t

func _label(parent: Node, text_: String, pos: Vector2, size_: Vector2, font_size := 16, align := HORIZONTAL_ALIGNMENT_LEFT, color := Color("f3e5bd")) -> Label:
    var l := Label.new()
    l.text = text_
    l.position = pos
    l.size = size_
    l.horizontal_alignment = align
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_shadow_color", Color(0,0,0,.75))
    l.add_theme_constant_override("shadow_offset_x", 1)
    l.add_theme_constant_override("shadow_offset_y", 2)
    parent.add_child(l)
    return l

func _glass_button(parent: Node, text_: String, pos: Vector2, size_: Vector2) -> Button:
    var b := Button.new()
    b.text = text_
    b.position = pos
    b.size = size_
    b.focus_mode = Control.FOCUS_NONE
    b.add_theme_font_size_override("font_size", 12)
    b.add_theme_color_override("font_color", Color("f5e9c8"))
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.025,0.055,0.08,0.88)
    normal.border_color = Color("a87935")
    normal.set_border_width_all(2)
    normal.set_corner_radius_all(7)
    var hover := normal.duplicate()
    hover.bg_color = Color(0.05,0.18,0.29,0.94)
    hover.border_color = Color("e8c263")
    var pressed := normal.duplicate()
    pressed.bg_color = Color(0.04,0.27,0.46,0.98)
    pressed.border_color = Color("79c9ff")
    b.add_theme_stylebox_override("normal", normal)
    b.add_theme_stylebox_override("hover", hover)
    b.add_theme_stylebox_override("pressed", pressed)
    parent.add_child(b)
    return b

func _ability(parent: Node, text_: String, pos: Vector2, diameter: float) -> Button:
    _tex(parent, ability_tex, pos, Vector2(diameter, diameter))
    var b := Button.new()
    b.text = text_
    b.position = pos
    b.size = Vector2(diameter, diameter)
    b.focus_mode = Control.FOCUS_NONE
    b.flat = true
    b.add_theme_font_size_override("font_size", int(max(10.0, diameter * .13)))
    b.add_theme_color_override("font_color", Color.WHITE)
    b.add_theme_color_override("font_hover_color", Color("9cdbff"))
    b.add_theme_color_override("font_pressed_color", Color("ffd978"))
    parent.add_child(b)
    return b

func _panel_art(parent: Node, pos: Vector2, size_: Vector2) -> Control:
    var root := Control.new()
    root.position = pos
    root.size = size_
    parent.add_child(root)
    _tex(root, panel_tex, Vector2.ZERO, size_)
    return root

func _build_hud() -> void:
    var vp := get_viewport().get_visible_rect().size

    var objective := _panel_art(self, Vector2(vp.x * .34, 10), Vector2(vp.x * .32, 78))
    _label(objective, "BREAK THE ENEMY SEAL", Vector2(20,10), Vector2(objective.size.x-40,30), 19, HORIZONTAL_ALIGNMENT_CENTER)
    status_label = _label(objective, "SQUAD 1  •  LINE", Vector2(24,40), Vector2(objective.size.x-48,22), 12, HORIZONTAL_ALIGNMENT_CENTER, Color("8ed5ff"))

    var command := _panel_art(self, Vector2(14, 12), Vector2(304, 252))
    _label(command, "FORMATIONS", Vector2(18,12), Vector2(268,24), 15, HORIZONTAL_ALIGNMENT_CENTER)
    var names := ["LINE", "PHALANX", "WEDGE", "CRESCENT", "SQUARE", "DISPERSE"]
    for i in range(names.size()):
        var row := i / 2
        var col := i % 2
        var b := _glass_button(command, names[i], Vector2(20 + col*133, 45 + row*42), Vector2(120,34))
        b.pressed.connect(_on_formation_pressed.bind(names[i]))
    _label(command, "SQUADS", Vector2(18,174), Vector2(86,18), 11)
    for i in range(3):
        var sb := _glass_button(command, "S%d" % (i+1), Vector2(18+i*58,196), Vector2(50,34))
        sb.pressed.connect(_on_squad_pressed.bind(i+1))
    var split := _glass_button(command, "SPLIT", Vector2(198,196), Vector2(82,34))
    split.pressed.connect(_on_split_pressed)

    var joy_size := 176.0
    var joy_pos := Vector2(28, vp.y-joy_size-26)
    _tex(self, joystick_tex, joy_pos, Vector2(joy_size,joy_size))
    var joy_hit := Control.new()
    joy_hit.position = joy_pos
    joy_hit.size = Vector2(joy_size,joy_size)
    joy_hit.mouse_filter = Control.MOUSE_FILTER_STOP
    joy_hit.gui_input.connect(_on_joystick_input)
    add_child(joy_hit)

    var map_size := 184.0
    var map_pos := Vector2((vp.x-map_size)/2.0, vp.y-map_size-16)
    _tex(self, minimap_tex, map_pos, Vector2(map_size,map_size))
    var map_hit := Control.new()
    map_hit.position = map_pos + Vector2(18,18)
    map_hit.size = Vector2(map_size-36,map_size-36)
    map_hit.mouse_filter = Control.MOUSE_FILTER_STOP
    map_hit.gui_input.connect(_on_minimap_input)
    add_child(map_hit)

    var action_root := Control.new()
    action_root.position = Vector2(vp.x-330, vp.y-244)
    action_root.size = Vector2(310,220)
    add_child(action_root)
    _label(action_root, "HERO", Vector2(96,0), Vector2(120,24), 13, HORIZONTAL_ALIGNMENT_CENTER)
    var attack := _ability(action_root, "ATTACK", Vector2(196,82), 108)
    var dash := _ability(action_root, "DASH", Vector2(118,118), 72)
    var a1 := _ability(action_root, "I", Vector2(132,36), 66)
    var a2 := _ability(action_root, "II", Vector2(202,20), 64)
    var summon := _ability(action_root, "SUMMON", Vector2(48,104), 76)
    attack.pressed.connect(_action_feedback.bind("ATTACK"))
    dash.pressed.connect(_action_feedback.bind("DASH"))
    a1.pressed.connect(_action_feedback.bind("ABILITY I"))
    a2.pressed.connect(_action_feedback.bind("ABILITY II"))
    summon.pressed.connect(_action_feedback.bind("SUMMON"))

    var hero := _panel_art(self, Vector2(16, vp.y-238), Vector2(260,52))
    _label(hero, "SEALBEARER  •  LV 15", Vector2(18,6), Vector2(224,18), 12)
    _label(hero, "2350 / 2350     620 / 620", Vector2(18,25), Vector2(224,17), 11, HORIZONTAL_ALIGNMENT_CENTER, Color("8fd8ff"))

func _on_formation_pressed(name_: String) -> void:
    selected_formation = name_
    _refresh_status()

func _on_squad_pressed(index: int) -> void:
    selected_squad = index
    _refresh_status()

func _on_split_pressed() -> void:
    selected_squad = min(selected_squad + 1, 3)
    status_label.text = "ARMY SPLIT  •  %d SQUADS" % selected_squad

func _action_feedback(action_name: String) -> void:
    status_label.text = "HERO  •  " + action_name

func _on_joystick_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch and event.pressed:
        status_label.text = "HERO MOVEMENT"
    elif event is InputEventMouseButton and event.pressed:
        status_label.text = "HERO MOVEMENT"

func _on_minimap_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch and event.pressed:
        status_label.text = "CAMERA  •  MINIMAP"
    elif event is InputEventMouseButton and event.pressed:
        status_label.text = "CAMERA  •  MINIMAP"

func _refresh_status() -> void:
    status_label.text = "SQUAD %d  •  %s" % [selected_squad, selected_formation]
