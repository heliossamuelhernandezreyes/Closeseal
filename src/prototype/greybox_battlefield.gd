extends Node3D

const TacticalHUD = preload("res://src/prototype/tactical_hud.gd")
const MapContract = preload("res://src/map/map_contract.gd")
const DEFAULT_MAP := "res://maps/competitive_lab_01.json"

var map_data: Dictionary = {}

func _ready() -> void:
    map_data = MapContract.load_file(DEFAULT_MAP)
    if map_data.is_empty():
        push_warning("Map Forge contract failed to load; prototype will use safe fallback geometry")
    _build_environment()
    _build_lane()
    _build_blue_force()
    _build_red_force()
    _build_objectives()
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

func _map_bounds() -> Vector2:
    var bounds: Dictionary = map_data.get("bounds", {})
    return Vector2(maxf(float(bounds.get("width", 44.0)), 8.0), maxf(float(bounds.get("depth", 29.0)), 8.0))

func _base_for_team(team: String) -> Dictionary:
    for value in map_data.get("bases", []):
        if typeof(value) == TYPE_DICTIONARY:
            var base: Dictionary = value
            if String(base.get("team", "")) == team:
                return base
    if team == "blue":
        return {"position": [-13.4, 0.0, 0.0], "hero_spawn": [-10.2, 0.0, 5.0]}
    return {"position": [13.4, 0.0, 0.0], "hero_spawn": [10.2, 0.0, -5.0]}

func _primary_route() -> Dictionary:
    for value in map_data.get("routes", []):
        if typeof(value) == TYPE_DICTIONARY:
            var route: Dictionary = value
            if String(route.get("kind", "")) == "primary":
                return route
    return {"width": 6.6, "points": [[-13.4,0.0,0.0],[0.0,0.0,0.0],[13.4,0.0,0.0]]}

func _mat(color: Color, metallic := 0.0, roughness := 0.78, emission := Color.BLACK) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.metallic = metallic
    m.roughness = roughness
    if emission != Color.BLACK:
        m.emission_enabled = true
        m.emission = emission
        m.emission_energy_multiplier = 2.2
    return m

func _mesh(mesh: PrimitiveMesh, name_: String, pos: Vector3, color: Color, rot := Vector3.ZERO, metallic := 0.0, emission := Color.BLACK) -> MeshInstance3D:
    var n := MeshInstance3D.new()
    n.name = name_
    n.mesh = mesh
    n.position = pos
    n.rotation_degrees = rot
    n.material_override = _mat(color, metallic, 0.76, emission)
    add_child(n)
    return n

func _box(name_: String, pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO, metallic := 0.0) -> MeshInstance3D:
    var b := BoxMesh.new(); b.size = size
    return _mesh(b, name_, pos, color, rot, metallic)

func _cylinder(name_: String, pos: Vector3, radius: float, height: float, color: Color, metallic := 0.0) -> MeshInstance3D:
    var c := CylinderMesh.new(); c.top_radius = radius; c.bottom_radius = radius; c.height = height
    return _mesh(c, name_, pos, color, Vector3.ZERO, metallic)

func _sphere(name_: String, pos: Vector3, radius: float, color: Color, emission := Color.BLACK) -> MeshInstance3D:
    var s := SphereMesh.new(); s.radius = radius; s.height = radius * 2.0
    return _mesh(s, name_, pos, color, Vector3.ZERO, 0.0, emission)

func _prism(name_: String, pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
    var p := PrismMesh.new(); p.size = size
    return _mesh(p, name_, pos, color, rot)

func _soldier(name_: String, pos: Vector3, team: Color, ranged := false, support := false, scale_ := 1.0) -> void:
    _cylinder(name_ + "_legs", pos + Vector3(0, .42, 0), .27 * scale_, .72 * scale_, Color("1b2328"))
    _prism(name_ + "_torso", pos + Vector3(0, 1.02 * scale_, 0), Vector3(.82, .92, .52) * scale_, team)
    _sphere(name_ + "_head", pos + Vector3(0, 1.65 * scale_, 0), .25 * scale_, Color("c6b8a0"))
    _box(name_ + "_pauldron_l", pos + Vector3(-.46, 1.2, 0) * scale_, Vector3(.28, .28, .62) * scale_, team.lightened(.12))
    _box(name_ + "_pauldron_r", pos + Vector3(.46, 1.2, 0) * scale_, Vector3(.28, .28, .62) * scale_, team.lightened(.12))
    if ranged:
        _box(name_ + "_weapon", pos + Vector3(.58, 1.0, -.15) * scale_, Vector3(.12, .12, 1.35) * scale_, Color("273239"), Vector3(-12, 0, 0), .7)
    elif support:
        _sphere(name_ + "_focus", pos + Vector3(.62, 1.08, 0) * scale_, .18 * scale_, team.lightened(.35), team.lightened(.2))
    else:
        _box(name_ + "_shield", pos + Vector3(-.55, .95, 0) * scale_, Vector3(.16, .9, .72) * scale_, team.darkened(.12), Vector3(0, 0, 8), .35)

func _hero(pos: Vector3) -> void:
    var gold := Color("d7a83d")
    _cylinder("HeroLegs", pos + Vector3(0,.55,0), .38, .95, Color("20282c"))
    _prism("HeroTorso", pos + Vector3(0,1.35,0), Vector3(1.15,1.35,.72), gold)
    _sphere("HeroHead", pos + Vector3(0,2.22,0), .34, Color("d0b99b"))
    _box("HeroMantle", pos + Vector3(0,1.55,.36), Vector3(1.35,.85,.14), Color("5d2630"), Vector3(-8,0,0))
    _box("HeroBlade", pos + Vector3(.78,1.18,-.1), Vector3(.14,.14,1.85), Color("b9d8df"), Vector3(-18,0,-8), .8)
    _sphere("HeroSeal", pos + Vector3(0,1.52,-.42), .18, Color("f6dc78"), Color("f0b83f"))
    _cylinder("HeroRing", pos + Vector3(0,.035,0), 1.05, .055, Color("e8bd54"), .45)

func _creep(name_: String, pos: Vector3, team: Color) -> void:
    _cylinder(name_ + "_body", pos + Vector3(0,.38,0), .27, .62, team.darkened(.1))
    _sphere(name_ + "_core", pos + Vector3(0,.82,0), .24, team, team)
    _box(name_ + "_fin", pos + Vector3(0,.78,.28), Vector3(.12,.52,.52), team.lightened(.12), Vector3(25,0,0))

func _tower(name_: String, pos: Vector3, team: Color) -> void:
    _cylinder(name_ + "_foundation", pos + Vector3(0,.25,0), 1.6, .5, Color("20292c"))
    _cylinder(name_ + "_base", pos + Vector3(0,.85,0), 1.15, 1.25, team.darkened(.25), .25)
    _prism(name_ + "_keep", pos + Vector3(0,1.95,0), Vector3(1.7,1.45,1.55), team)
    for sx in [-.82,.82]:
        _box(name_ + "_wing", pos + Vector3(sx,1.65,0), Vector3(.32,1.25,1.9), team.darkened(.12), Vector3(0,0,-sx*9.0))
    _sphere(name_ + "_seal", pos + Vector3(0,2.95,0), .38, team.lightened(.3), team.lightened(.15))

func _build_environment() -> void:
    var bounds: Vector2 = _map_bounds()
    var route: Dictionary = _primary_route()
    var lane_width: float = maxf(float(route.get("width", 6.6)), 2.0)
    var inner_width: float = maxf(bounds.x - 5.0, 4.0)
    var inner_depth: float = maxf(bounds.y - 6.0, 4.0)
    var lane_length: float = maxf(bounds.x - 6.0, 6.0)
    _box("Ground", Vector3(0,-.42,0), Vector3(bounds.x,.7,bounds.y), Color("17221f"))
    _box("InnerGround", Vector3(0,-.04,0), Vector3(inner_width,.08,inner_depth), Color("26342d"))
    _box("Lane", Vector3(0,.015,0), Vector3(lane_length,.07,lane_width), Color("665f50"))
    _box("LaneCore", Vector3(0,.06,0), Vector3(lane_length,.035,maxf(lane_width * .17, .4)), Color("87734e"))
    var wall_x: float = bounds.x * 0.5 - 3.8
    for x in [-wall_x, wall_x]:
        _box("Wall", Vector3(float(x),.75,0), Vector3(1.1,1.6,maxf(bounds.y - 15.5, 8.0)), Color("303a3b"))
        for z in range(-6,7,3):
            _box("Buttress", Vector3(float(x)-signf(float(x))*.7,.75,float(z)), Vector3(.65,1.7,1.0), Color("485052"))
    var cliff_z: float = bounds.y * 0.5 - 2.8
    for z in [-cliff_z, cliff_z]:
        _box("Cliff", Vector3(0,.65,float(z)), Vector3(bounds.x,1.35,2.2), Color("242e2b"))
        for x in range(-18,19,6):
            _box("CliffStone", Vector3(float(x),1.05,float(z)-signf(float(z))*.65), Vector3(3.6,.65,.85), Color("3c4742"), Vector3(0,float(x % 9),0))
    for i in range(5):
        var fraction: float = (float(i) - 2.0) / 2.0
        _cylinder("LaneMarker", Vector3(fraction * bounds.x * .318,.1,0), .48, .05, Color("b58d43"), .4)
    var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-58,-38,0); light.light_energy = 1.45; light.shadow_enabled = true; add_child(light)
    var world := WorldEnvironment.new(); var env := Environment.new()
    env.background_mode = Environment.BG_COLOR; env.background_color = Color("0b1114")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color("789099"); env.ambient_light_energy = .48
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world.environment = env; add_child(world)
    var camera := Camera3D.new(); camera.position = Vector3(0,22.5,23.5); camera.rotation_degrees = Vector3(-44,0,0); camera.fov = 44; camera.current = true; add_child(camera)

func _build_lane() -> void:
    var blue_base: Vector3 = MapContract.vec3_from(_base_for_team("blue").get("position", []), Vector3(-13.4,0,0))
    var red_base: Vector3 = MapContract.vec3_from(_base_for_team("red").get("position", []), Vector3(13.4,0,0))
    var center: Vector3 = (blue_base + red_base) * 0.5
    var span: float = maxf(blue_base.distance_to(red_base) * .33, 7.0)
    for i in range(7):
        var t: float = float(i) / 6.0
        var x: float = lerpf(center.x - span * .5, center.x + span * .5, t)
        _creep("BlueCreep%d" % i, Vector3(x,0,-.72), Color("4aaee8"))
        _creep("RedCreep%d" % i, Vector3(-x,0,.72), Color("e95750"))

func _build_blue_force() -> void:
    var base: Dictionary = _base_for_team("blue")
    var hero_spawn: Vector3 = MapContract.vec3_from(base.get("hero_spawn", []), Vector3(-10.2,0,5.0))
    var tower_pos: Vector3 = MapContract.vec3_from(base.get("position", []), Vector3(-13.4,0,0))
    _hero(hero_spawn)
    for row in range(2):
        for col in range(4):
            _soldier("BlueFront%d_%d" % [row,col], hero_spawn + Vector3(2.8+col*1.3,0,-1.6+row*1.45), Color("3f78c9"))
    for col in range(4):
        _soldier("BlueRanged%d" % col, hero_spawn + Vector3(2.5+col*1.35,0,2.0), Color("3e9eaa"), true)
    _soldier("BlueSupport", hero_spawn + Vector3(.9,0,2.05), Color("7b62b8"), false, true)
    _tower("BlueTower", tower_pos, Color("3469ae"))

func _build_red_force() -> void:
    var base: Dictionary = _base_for_team("red")
    var hero_spawn: Vector3 = MapContract.vec3_from(base.get("hero_spawn", []), Vector3(10.2,0,-5.0))
    var tower_pos: Vector3 = MapContract.vec3_from(base.get("position", []), Vector3(13.4,0,0))
    for row in range(2):
        for col in range(4):
            _soldier("RedFront%d_%d" % [row,col], hero_spawn + Vector3(-2.8-col*1.3,0,1.6-row*1.45), Color("a84443"))
    for col in range(4):
        _soldier("RedRanged%d" % col, hero_spawn + Vector3(-2.5-col*1.35,0,-2.0), Color("bb6247"), true)
    _tower("RedTower", tower_pos, Color("923c42"))

func _build_objectives() -> void:
    var index := 0
    for value in map_data.get("objectives", []):
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var objective: Dictionary = value
        var pos: Vector3 = MapContract.vec3_from(objective.get("position", []))
        var radius: float = maxf(float(objective.get("radius", 2.0)), .5)
        _cylinder("ObjectiveRing%d" % index, pos + Vector3(0,.045,0), radius, .06, Color("8951c8"), .3)
        _sphere("ObjectiveCore%d" % index, pos + Vector3(0,.45,0), .24, Color("cf8cff"), Color("8f54c9"))
        index += 1
