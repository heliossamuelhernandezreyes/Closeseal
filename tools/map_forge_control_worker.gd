extends SceneTree

const CONTRACT = preload("res://src/map/map_contract.gd")
const BRIDGE = preload("res://addons/close_seal_map_forge/map_forge_provider_bridge.gd")
const NAVIGATION = preload("res://addons/close_seal_map_forge/map_forge_navigation_layer.gd")
const PHYSICAL = preload("res://src/map/map_physical_world.gd")
const VISUAL_KIT = preload("res://src/prototype/map_visual_kit.gd")

var response_path := ""

func _initialize() -> void:
    _run.call_deferred()

func _finish(result: Dictionary) -> void:
    var file := FileAccess.open(response_path, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(result, "  ") + "\n")
        file.close()
    print("MAP_FORGE_CONTROL_RESULT=" + JSON.stringify(result))
    quit(0 if bool(result.get("ok", false)) else 1)

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 2:
        quit(2)
        return
    response_path = args[1]
    var file := FileAccess.open(args[0], FileAccess.READ)
    if file == null:
        _finish({"ok": false, "error": "request missing"})
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary:
        _finish({"ok": false, "error": "request must be an object"})
        return
    var request: Dictionary = parsed
    var state: Dictionary = request.get("state", {})
    var data: Dictionary = state.get("map", {})
    var errors := CONTRACT.validate(data)
    if not errors.is_empty():
        _finish({"ok": false, "errors": errors})
        return
    var physical_value = state.get("physical", null)
    var physical: Dictionary = physical_value if physical_value is Dictionary else {}
    if String(request.get("operation", "")) == "materialize":
        var result := BRIDGE.build_authoring_scene(data)
        if bool(result.get("ok", false)):
            var navigation := NAVIGATION.augment_scene(String(result.get("scene_path", "")), data)
            result["navigation"] = navigation
            result["ok"] = bool(navigation.get("ok", false))
            if not physical.is_empty() and bool(result["ok"]):
                result["physical"] = PHYSICAL.augment_scene(String(result["scene_path"]), data, physical)
                result["ok"] = bool(result["physical"].get("ok", false))
        _finish(result)
        return
    var world := Node3D.new()
    root.add_child(world)
    var kit = VISUAL_KIT.new(world, data)
    var stats: Dictionary = kit.build()
    if not stats.get("errors", []).is_empty():
        _finish({"ok": false, "errors": stats["errors"]})
        return
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -32, 0)
    sun.light_energy = 1.5
    world.add_child(sun)
    var environment_node := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("17212d")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("b8c8d7")
    environment.ambient_light_energy = 0.6
    environment_node.environment = environment
    world.add_child(environment_node)
    var camera := Camera3D.new()
    world.add_child(camera)
    camera.current = true
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    var bounds: Dictionary = data.get("bounds", {})
    var span := maxf(float(bounds.get("width", 96)), float(bounds.get("depth", 64)))
    camera.size = span * 0.82
    camera.far = span * 8.0
    root.size = Vector2i(1280, 720)
    var options: Dictionary = request.get("options", {})
    var views: Array = options.get("views", ["tactical", "north", "east", "top"])
    var images: Array[String] = []
    var directions := {"tactical": Vector3(0.62, 1.1, 0.9), "north": Vector3(0, 0.8, -1), "east": Vector3(1, 0.8, 0), "top": Vector3(0, 1.4, 0.001)}
    for value in views:
        var view := String(value)
        if not directions.has(view):
            _finish({"ok": false, "error": "unknown capture view: " + view})
            return
        camera.position = directions[view] * span
        camera.look_at(Vector3.ZERO, Vector3.UP)
        await process_frame
        await process_frame
        await RenderingServer.frame_post_draw
        var image := root.get_texture().get_image()
        var output := response_path.get_base_dir().path_join(view + ".png")
        if image.save_png(output) != OK:
            _finish({"ok": false, "error": "image could not be saved"})
            return
        images.append(output)
    _finish({"ok": true, "images": images, "visual_stats": stats, "map_id": data.get("id"), "limits": ["visual evidence; target-device performance remains unmeasured"]})
