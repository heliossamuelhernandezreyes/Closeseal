extends CanvasLayer

var selected_formation := "LINE"
var selected_squad := 1
var status_label: Label
var formation_buttons: Array[Button] = []
var squad_buttons: Array[Button] = []

func _ready() -> void:
    layer = 10
    _build_hud()

func _panel(rect: Rect2, color: Color, radius := 12.0) -> Panel:
    var p := Panel.new()
    p.position = rect.position
    p.size = rect.size
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = Color(0.75, 0.82, 0.86, 0.18)
    style.set_border_width_all(1)
    style.corner_radius_top_left = int(radius)
    style.corner_radius_top_right = int(radius)
    style.corner_radius_bottom_left = int(radius)
    style.corner_radius_bottom_right = int(radius)
    p.add_theme_stylebox_override("panel", style)
    add_child(p)
    return p

func _label(parent: Node, text_: String, pos: Vector2, size_: Vector2, font_size := 16, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
    var l := Label.new()
    l.text = text_
    l.position = pos
    l.size = size_
    l.horizontal_alignment = align
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", Color("e7edf1"))
    parent.add_child(l)
    return l

func _button(parent: Node, text_: String, pos: Vector2, size_: Vector2) -> Button:
    var b := Button.new()
    b.text = text_
    b.position = pos
    b.size = size_
    b.focus_mode = Control.FOCUS_NONE
    b.add_theme_font_size_override("font_size", 13)
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.08,0.11,0.13,0.92)
    normal.border_color = Color(0.45,0.55,0.60,0.45)
    normal.set_border_width_all(1)
    normal.set_corner_radius_all(9)
    var hover := normal.duplicate()
    hover.bg_color = Color(0.16,0.21,0.24,0.95)
    var pressed := normal.duplicate()
    pressed.bg_color = Color(0.72,0.53,0.20,0.98)
    b.add_theme_stylebox_override("normal", normal)
    b.add_theme_stylebox_override("hover", hover)
    b.add_theme_stylebox_override("pressed", pressed)
    parent.add_child(b)
    return b

func _build_hud() -> void:
    var viewport_size := get_viewport().get_visible_rect().size

    # Top command/status ribbon.
    var top := _panel(Rect2(Vector2(viewport_size.x * 0.34, 16), Vector2(viewport_size.x * 0.32, 54)), Color(0.035,0.05,0.06,0.90), 14)
    _label(top, "CLOSE SEAL", Vector2(14,4), Vector2(140,22), 18)
    status_label = _label(top, "SQUAD 1  •  LINE", Vector2(14,25), Vector2(top.size.x-28,22), 13, HORIZONTAL_ALIGNMENT_CENTER)

    # Formation command cluster — upper left.
    var forms := _panel(Rect2(Vector2(20, 22), Vector2(290, 168)), Color(0.035,0.05,0.06,0.88), 14)
    _label(forms, "FORMATIONS", Vector2(14,8), Vector2(170,24), 14)
    var names := ["LINE", "PHALANX", "WEDGE", "CRESCENT", "SQUARE", "DISPERSE"]
    for i in range(names.size()):
        var row := i / 2
        var col := i % 2
        var b := _button(forms, names[i], Vector2(14 + col * 132, 38 + row * 38), Vector2(120, 32))
        b.pressed.connect(_on_formation_pressed.bind(names[i]))
        formation_buttons.append(b)

    # Squad selection / split strip.
    var squads := _panel(Rect2(Vector2(20, 202), Vector2(290, 112)), Color(0.035,0.05,0.06,0.86), 14)
    _label(squads, "SQUADS", Vector2(14,6), Vector2(120,22), 13)
    for i in range(3):
        var sb := _button(squads, "S%d" % (i+1), Vector2(14 + i*64, 34), Vector2(54, 32))
        sb.pressed.connect(_on_squad_pressed.bind(i+1))
        squad_buttons.append(sb)
    var split := _button(squads, "SPLIT 1 / 2 / 3", Vector2(14,72), Vector2(178,28))
    split.pressed.connect(_on_split_pressed)
    var role := _button(squads, "BY ROLE", Vector2(198,72), Vector2(78,28))
    role.pressed.connect(_on_role_split_pressed)

    # Virtual joystick — lower left.
    var joy := _panel(Rect2(Vector2(42, viewport_size.y - 184), Vector2(146,146)), Color(0.03,0.045,0.055,0.72), 73)
    var ring := ColorRect.new()
    ring.position = Vector2(31,31)
    ring.size = Vector2(84,84)
    ring.color = Color(0.25,0.34,0.38,0.36)
    joy.add_child(ring)
    var nub := ColorRect.new()
    nub.position = Vector2(54,54)
    nub.size = Vector2(38,38)
    nub.color = Color(0.78,0.84,0.86,0.72)
    joy.add_child(nub)
    _label(joy, "MOVE", Vector2(36,112), Vector2(74,22), 12, HORIZONTAL_ALIGNMENT_CENTER)

    # Tactical minimap — lower center.
    var map_w := 300.0
    var minimap := _panel(Rect2(Vector2((viewport_size.x-map_w)/2.0, viewport_size.y-132), Vector2(map_w,104)), Color(0.025,0.038,0.04,0.94), 10)
    _label(minimap, "TACTICAL MAP", Vector2(8,2), Vector2(map_w-16,18), 11, HORIZONTAL_ALIGNMENT_CENTER)
    var field := ColorRect.new()
    field.position = Vector2(12,24)
    field.size = Vector2(map_w-24,68)
    field.color = Color("1d322b")
    minimap.add_child(field)
    var lane := ColorRect.new()
    lane.position = Vector2(18,51)
    lane.size = Vector2(map_w-36,14)
    lane.color = Color("77684f")
    minimap.add_child(lane)
    for px in [34,56,78,100]:
        var dot := ColorRect.new(); dot.position = Vector2(px,47); dot.size = Vector2(7,7); dot.color = Color("58b8ff"); minimap.add_child(dot)
    for px in [196,218,240,262]:
        var dot := ColorRect.new(); dot.position = Vector2(px,57); dot.size = Vector2(7,7); dot.color = Color("ff675f"); minimap.add_child(dot)
    var cam := ColorRect.new(); cam.position = Vector2(125,38); cam.size = Vector2(52,34); cam.color = Color(1,1,1,0.12); minimap.add_child(cam)

    # Hero actions — lower right.
    var actions := _panel(Rect2(Vector2(viewport_size.x-330, viewport_size.y-206), Vector2(306,180)), Color(0.035,0.05,0.06,0.82), 18)
    _label(actions, "HERO", Vector2(14,8), Vector2(80,20), 13)
    var attack := _button(actions, "ATTACK", Vector2(198,82), Vector2(90,72)); attack.add_theme_font_size_override("font_size", 14)
    var dash := _button(actions, "DASH", Vector2(116,102), Vector2(72,52))
    var a1 := _button(actions, "A1", Vector2(188,30), Vector2(52,44))
    var a2 := _button(actions, "A2", Vector2(244,30), Vector2(44,44))
    var summon := _button(actions, "SUMMON", Vector2(14,114), Vector2(92,40))
    attack.pressed.connect(_action_feedback.bind("ATTACK"))
    dash.pressed.connect(_action_feedback.bind("DASH"))
    a1.pressed.connect(_action_feedback.bind("ABILITY 1"))
    a2.pressed.connect(_action_feedback.bind("ABILITY 2"))
    summon.pressed.connect(_action_feedback.bind("SUMMON"))

    # Objective/readability marker.
    var objective := _panel(Rect2(Vector2(viewport_size.x-286, 22), Vector2(262,72)), Color(0.035,0.05,0.06,0.86), 12)
    _label(objective, "OBJECTIVE", Vector2(12,6), Vector2(100,20), 11)
    _label(objective, "BREAK THE ENEMY SEAL", Vector2(12,28), Vector2(238,28), 15)

func _on_formation_pressed(name_: String) -> void:
    selected_formation = name_
    _refresh_status()

func _on_squad_pressed(index: int) -> void:
    selected_squad = index
    _refresh_status()

func _on_split_pressed() -> void:
    selected_squad = min(selected_squad + 1, 3)
    status_label.text = "ARMY SPLIT  •  %d SQUADS" % selected_squad

func _on_role_split_pressed() -> void:
    status_label.text = "ROLE SPLIT  •  FRONT / RANGE / SUPPORT"

func _action_feedback(action_name: String) -> void:
    status_label.text = "HERO  •  " + action_name

func _refresh_status() -> void:
    status_label.text = "SQUAD %d  •  %s" % [selected_squad, selected_formation]
