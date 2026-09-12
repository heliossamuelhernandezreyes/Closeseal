extends Node3D

# Close Seal first visual prototype. Uses only Godot primitives so the scene
# remains lightweight and immediately runnable while production art is absent.

func _ready() -> void:
    _build_environment()
    _build_lane()
    _build_blue_force()
    _build_red_force()
    if OS.has_environment("CLOSESEAL_CAPTURE"):
        _capture_for_ci.call_deferred()

func _capture_for_ci() -> void:
    await get_tree().process_frame
    await get_tree().process_frame
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    var output := OS.get_environment("CLOSESEAL_CAPTURE")
    var error := image.save_png(output)
    if error != OK:
        push_error("Failed to save screenshot: %s" % error)
        get_tree().quit(1)
        return
    print("CLOSESEAL_SCREENSHOT_SAVED=" + output)
    get_tree().quit()

func _mat(color: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.82
    return m

func _box(name_: String, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
    var n := MeshInstance3D.new()
    n.name = name_
    var mesh := BoxMesh.new()
    mesh.size = size
    n.mesh = mesh
    n.position = pos
    n.material_override = _mat(color)
    add_child(n)
    return n

func _cylinder(name_: String, pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
    var n := MeshInstance3D.new()
    n.name = name_
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    n.mesh = mesh
    n.position = pos
    n.material_override = _mat(color)
    add_child(n)
    return n

func _unit(name_: String, pos: Vector3, color: Color, scale_: float = 1.0) -> void:
    _cylinder(name_ + "_body", pos + Vector3(0, 0.65 * scale_, 0), 0.32 * scale_, 1.05 * scale_, color)
    var head := MeshInstance3D.new()
    head.name = name_ + "_head"
    var sphere := SphereMesh.new()
    sphere.radius = 0.27 * scale_
    sphere.height = 0.54 * scale_
    head.mesh = sphere
    head.position = pos + Vector3(0, 1.38 * scale_, 0)
    head.material_override = _mat(color.lightened(0.12))
    add_child(head)

func _tower(name_: String, pos: Vector3, color: Color) -> void:
    _cylinder(name_ + "_base", pos + Vector3(0, 0.65, 0), 1.25, 1.3, color.darkened(0.2))
    _box(name_ + "_keep", pos + Vector3(0, 1.75, 0), Vector3(1.55, 1.3, 1.55), color)
    _cylinder(name_ + "_crystal", pos + Vector3(0, 2.75, 0), 0.35, 0.8, Color(0.25, 0.9, 1.0))

func _build_environment() -> void:
    _box("Ground", Vector3(0, -0.35, 0), Vector3(42, 0.7, 27), Color("26332d"))
    _box("Lane", Vector3(0, 0.03, 0), Vector3(38, 0.08, 6.4), Color("746c5b"))
    for x in [-17.5, 17.5]:
        _box("Fortification", Vector3(x, 0.7, 0), Vector3(1.2, 1.4, 10.0), Color("42484b"))
    for z in [-11.0, 11.0]:
        _box("Cliff", Vector3(0, 0.75, z), Vector3(42, 1.5, 2.0), Color("343d39"))

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -32, 0)
    light.light_energy = 1.2
    light.shadow_enabled = true
    add_child(light)

    var world := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("11191c")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("8ba2aa")
    env.ambient_light_energy = 0.55
    world.environment = env
    add_child(world)

    var camera := Camera3D.new()
    camera.position = Vector3(0, 23, 22)
    camera.rotation_degrees = Vector3(-46, 0, 0)
    camera.fov = 47
    camera.current = true
    add_child(camera)

func _build_lane() -> void:
    for i in range(7):
        _unit("BlueCreep%d" % i, Vector3(-9.0 + i * 1.15, 0, -0.6), Color("5ab9ff"), 0.72)
        _unit("RedCreep%d" % i, Vector3(9.0 - i * 1.15, 0, 0.6), Color("ff665f"), 0.72)

func _build_blue_force() -> void:
    _unit("Hero", Vector3(-10.0, 0, 5.3), Color("e9c65b"), 1.35)
    for row in range(2):
        for col in range(4):
            _unit("BlueFront%d_%d" % [row, col], Vector3(-7.5 + col * 1.15, 0, 3.7 + row * 1.25), Color("4d8fff"))
    for col in range(4):
        _unit("BlueRanged%d" % col, Vector3(-8.0 + col * 1.25, 0, 7.0), Color("67d6e5"), 0.9)
    _unit("BlueSupport", Vector3(-9.3, 0, 7.1), Color("b88cff"), 1.0)
    _tower("BlueTower", Vector3(-13.2, 0, 0), Color("3979d8"))

func _build_red_force() -> void:
    for row in range(2):
        for col in range(4):
            _unit("RedFront%d_%d" % [row, col], Vector3(7.5 - col * 1.15, 0, -3.7 - row * 1.25), Color("df514c"))
    for col in range(4):
        _unit("RedRanged%d" % col, Vector3(8.0 - col * 1.25, 0, -7.0), Color("f28b63"), 0.9)
    _tower("RedTower", Vector3(13.2, 0, 0), Color("b83e43"))
