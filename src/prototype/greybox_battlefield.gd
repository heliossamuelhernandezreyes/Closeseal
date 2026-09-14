extends Node3D

const TacticalHUD = preload("res://src/prototype/tactical_hud.gd")
const MapContract = preload("res://src/map/map_contract.gd")
const MapVisualKit = preload("res://src/prototype/map_visual_kit.gd")
const DEFAULT_MAP := "res://maps/competitive_lab_01.json"

var map_data: Dictionary = {}
var visual_kit: RefCounted

func _ready() -> void:
    map_data = MapContract.load_file(DEFAULT_MAP)
    if map_data.is_empty():
        push_warning("Map Forge contract failed to load; prototype will use safe fallback geometry")
    visual_kit = MapVisualKit.new(self, map_data)
    var visual_stats: Dictionary = visual_kit.build()
    print("CLOSESEAL_MAP_VISUAL_KIT=%s" % JSON.stringify(visual_stats))
    _build_combat_showcase()
    _build_lighting_and_camera()
    var hud := TacticalHUD.new()
    add_child(hud)
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

func _material(color: Color, metallic := 0.0, roughness := 0.78, emission := Color.BLACK) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.metallic = metallic
    material.roughness = roughness
    if emission != Color.BLACK:
        material.emission_enabled = true
        material.emission = emission
        material.emission_energy_multiplier = 2.4
    return material

func _mesh(mesh: PrimitiveMesh, name_: String, pos: Vector3, color: Color, rot := Vector3.ZERO, metallic := 0.0, emission := Color.BLACK) -> MeshInstance3D:
    mesh.material = _material(color, metallic, 0.76, emission)
    var node := MeshInstance3D.new()
    node.name = name_
    node.mesh = mesh
    node.position = pos
    node.rotation_degrees = rot
    add_child(node)
    return node

func _box(name_: String, pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO, metallic := 0.0) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    return _mesh(mesh, name_, pos, color, rot, metallic)

func _cylinder(name_: String, pos: Vector3, radius: float, height: float, color: Color, metallic := 0.0) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 10
    return _mesh(mesh, name_, pos, color, Vector3.ZERO, metallic)

func _sphere(name_: String, pos: Vector3, radius: float, color: Color, emission := Color.BLACK) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.radial_segments = 10
    mesh.rings = 5
    return _mesh(mesh, name_, pos, color, Vector3.ZERO, 0.0, emission)

func _prism(name_: String, pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
    var mesh := PrismMesh.new()
    mesh.size = size
    return _mesh(mesh, name_, pos, color, rot)

func _soldier(name_: String, pos: Vector3, team: Color, ranged := false, support := false, scale_ := 1.0) -> void:
    _cylinder(name_ + "_legs", pos + Vector3(0, 0.42, 0) * scale_, 0.27 * scale_, 0.72 * scale_, Color("1b2328"))
    _prism(name_ + "_torso", pos + Vector3(0, 1.02, 0) * scale_, Vector3(0.82, 0.92, 0.52) * scale_, team)
    _sphere(name_ + "_head", pos + Vector3(0, 1.65, 0) * scale_, 0.25 * scale_, Color("c6b8a0"))
    _box(name_ + "_pauldron_l", pos + Vector3(-0.46, 1.2, 0) * scale_, Vector3(0.28, 0.28, 0.62) * scale_, team.lightened(0.12))
    _box(name_ + "_pauldron_r", pos + Vector3(0.46, 1.2, 0) * scale_, Vector3(0.28, 0.28, 0.62) * scale_, team.lightened(0.12))
    if ranged:
        _box(name_ + "_weapon", pos + Vector3(0.58, 1.0, -0.15) * scale_, Vector3(0.12, 0.12, 1.35) * scale_, Color("273239"), Vector3(-12, 0, 0), 0.7)
    elif support:
        _sphere(name_ + "_focus", pos + Vector3(0.62, 1.08, 0) * scale_, 0.18 * scale_, team.lightened(0.35), team.lightened(0.2))
    else:
        _box(name_ + "_shield", pos + Vector3(-0.55, 0.95, 0) * scale_, Vector3(0.16, 0.9, 0.72) * scale_, team.darkened(0.12), Vector3(0, 0, 8), 0.35)

func _hero(pos: Vector3) -> void:
    var gold := Color("d7a83d")
    _cylinder("HeroLegs", pos + Vector3(0, 0.55, 0), 0.38, 0.95, Color("20282c"))
    _prism("HeroTorso", pos + Vector3(0, 1.35, 0), Vector3(1.15, 1.35, 0.72), gold)
    _sphere("HeroHead", pos + Vector3(0, 2.22, 0), 0.34, Color("d0b99b"))
    _box("HeroMantle", pos + Vector3(0, 1.55, 0.36), Vector3(1.35, 0.85, 0.14), Color("5d2630"), Vector3(-8, 0, 0))
    _box("HeroBlade", pos + Vector3(0.78, 1.18, -0.1), Vector3(0.14, 0.14, 1.85), Color("b9d8df"), Vector3(-18, 0, -8), 0.8)
    _sphere("HeroSeal", pos + Vector3(0, 1.52, -0.42), 0.18, Color("f6dc78"), Color("f0b83f"))
    _cylinder("HeroRing", pos + Vector3(0, 0.035, 0), 1.05, 0.055, Color("e8bd54"), 0.45)

func _creep(name_: String, pos: Vector3, team: Color) -> void:
    _cylinder(name_ + "_body", pos + Vector3(0, 0.38, 0), 0.27, 0.62, team.darkened(0.1))
    _sphere(name_ + "_core", pos + Vector3(0, 0.82, 0), 0.24, team, team)
    _box(name_ + "_fin", pos + Vector3(0, 0.78, 0.28), Vector3(0.12, 0.52, 0.52), team.lightened(0.12), Vector3(25, 0, 0))

func _build_combat_showcase() -> void:
    var blue := Color("3f78c9")
    var red := Color("b54843")
    _hero(Vector3(-11.5, 0, 4.8))
    for row in range(2):
        for col in range(5):
            _soldier("BlueVanguard_%d_%d" % [row, col], Vector3(-16.0 + col * 1.35, 0, 1.7 + row * 1.45), blue, false, false, 1.08)
            _soldier("RedVanguard_%d_%d" % [row, col], Vector3(16.0 - col * 1.35, 0, -1.7 - row * 1.45), red, false, false, 1.08)
    for col in range(4):
        _soldier("BlueRanged_%d" % col, Vector3(-17.0 + col * 1.55, 0, 5.0), Color("3e9eaa"), true, false, 1.05)
        _soldier("RedRanged_%d" % col, Vector3(17.0 - col * 1.55, 0, -5.0), Color("bd6a43"), true, false, 1.05)
    _soldier("BlueSupport", Vector3(-17.8, 0, 5.0), Color("7b62b8"), false, true, 1.08)
    _soldier("RedSupport", Vector3(17.8, 0, -5.0), Color("aa477e"), false, true, 1.08)
    for index in range(7):
        _creep("BlueCreep_%02d" % index, Vector3(-8.8 + index * 1.2, 0, -0.72), Color("4aaee8"))
        _creep("RedCreep_%02d" % index, Vector3(8.8 - index * 1.2, 0, 0.72), Color("e95750"))

func _build_lighting_and_camera() -> void:
    var key := DirectionalLight3D.new()
    key.name = "SunKey"
    key.rotation_degrees = Vector3(-58, -38, 0)
    key.light_color = Color("ffe0b0")
    key.light_energy = 1.35
    key.shadow_enabled = true
    key.directional_shadow_max_distance = 140.0
    add_child(key)
    var fill := DirectionalLight3D.new()
    fill.name = "SkyFill"
    fill.rotation_degrees = Vector3(-42, 142, 0)
    fill.light_color = Color("87b9d8")
    fill.light_energy = 0.38
    fill.shadow_enabled = false
    add_child(fill)
    var world := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("081117")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("7895a1")
    environment.ambient_light_energy = 0.52
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world.environment = environment
    add_child(world)
    var camera := Camera3D.new()
    camera.name = "TacticalCamera"
    camera.position = Vector3(0, 70, 68)
    camera.rotation_degrees = Vector3(-46, 0, 0)
    camera.fov = 43
    camera.current = true
    add_child(camera)
