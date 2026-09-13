@tool
class_name CloseSealMapForgeProviderBridge
extends RefCounted

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")

const TERRAIN3D_PLUGIN := "res://addons/terrain_3d/plugin.cfg"
const CYCLOPS_ROOT_SCRIPT := "res://addons/cyclops_level_builder/nodes/cyclops_blocks.gd"
const PROTON_SCATTER_SCRIPT := "res://addons/proton_scatter/src/scatter.gd"
const PROTON_SHAPE_SCRIPT := "res://addons/proton_scatter/src/scatter_shape.gd"
const PROTON_BOX_SHAPE_SCRIPT := "res://addons/proton_scatter/src/shapes/box_shape.gd"
const FUNCGODOT_PLUGIN := "res://addons/func_godot/plugin.cfg"

static func generated_scene_path(map_id: String) -> String:
    return "res://maps/generated/%s_authoring.tscn" % map_id

static func generated_manifest_path(map_id: String) -> String:
    return "res://maps/generated/%s_authoring.manifest.json" % map_id

static func build_authoring_scene(map_data: Dictionary) -> Dictionary:
    var errors := MAP_CONTRACT.validate(map_data)
    if not errors.is_empty():
        return {"ok": false, "errors": errors}

    var map_id := String(map_data.get("id", "map"))
    _ensure_dir("res://maps/generated")
    _ensure_dir("res://maps/generated/terrain/%s" % map_id)

    var root := Node3D.new()
    root.name = "MapForgeAuthoring_%s" % map_id
    root.set_meta("map_forge_generated", true)
    root.set_meta("map_id", map_id)
    root.set_meta("contract_version", int(map_data.get("version", 1)))

    var provider_state: Dictionary = {}
    var terrain_root := _build_terrain_layer(root, map_data, map_id, provider_state)
    var structures_root := _build_structure_layer(root, map_data, provider_state)
    var scatter_root := _build_scatter_layer(root, map_data, provider_state)
    var gameplay_root := _build_gameplay_guides(root, map_data)
    var navigation_root := _build_navigation_guides(root, map_data)
    var import_root := _build_import_socket(root, provider_state)

    for child in [terrain_root, structures_root, scatter_root, gameplay_root, navigation_root, import_root]:
        if child != null:
            _assign_owner_recursive(child, root)

    var packed := PackedScene.new()
    var pack_error := packed.pack(root)
    if pack_error != OK:
        root.free()
        return {"ok": false, "errors": ["PackedScene.pack failed: %s" % pack_error]}

    var scene_path := generated_scene_path(map_id)
    var save_error := ResourceSaver.save(packed, scene_path)
    root.free()
    if save_error != OK:
        return {"ok": false, "errors": ["ResourceSaver.save failed: %s" % save_error]}

    var manifest := {
        "map_id": map_id,
        "contract_version": int(map_data.get("version", 1)),
        "scene": scene_path,
        "providers": provider_state,
        "generated_layers": ["terrain", "structures", "scatter", "gameplay", "navigation", "import"],
        "ownership": "Close Seal canonical map contract",
        "generated": true
    }
    _write_json(generated_manifest_path(map_id), manifest)

    return {
        "ok": true,
        "scene_path": scene_path,
        "manifest_path": generated_manifest_path(map_id),
        "providers": provider_state
    }

static func _build_terrain_layer(root: Node3D, map_data: Dictionary, map_id: String, provider_state: Dictionary) -> Node3D:
    var layer := Node3D.new()
    layer.name = "Terrain"
    root.add_child(layer)

    var authoring: Dictionary = map_data.get("authoring", {})
    var terrain_cfg: Dictionary = authoring.get("terrain", {})
    var bounds: Dictionary = map_data.get("bounds", {})
    var width := float(bounds.get("width", 44.0))
    var depth := float(bounds.get("depth", 29.0))

    if ClassDB.class_exists(&"Terrain3D"):
        var terrain_object = ClassDB.instantiate(&"Terrain3D")
        if terrain_object is Node:
            var terrain_node: Node = terrain_object
            terrain_node.name = "Terrain3D"
            var data_dir := String(terrain_cfg.get("data_directory", "res://maps/generated/terrain/%s" % map_id))
            if _has_property(terrain_node, "data_directory"):
                terrain_node.set("data_directory", data_dir)
            if _has_property(terrain_node, "vertex_spacing"):
                terrain_node.set("vertex_spacing", float(terrain_cfg.get("vertex_spacing", 1.0)))
            if _has_property(terrain_node, "region_size"):
                terrain_node.set("region_size", int(terrain_cfg.get("region_size", 64)))
            terrain_node.set_meta("map_forge_role", "terrain_provider")
            terrain_node.set_meta("map_forge_bounds", Vector2(width, depth))
            layer.add_child(terrain_node)
            provider_state["terrain3d"] = {"available": true, "materialized": true, "mode": "editable_provider_node"}
        else:
            provider_state["terrain3d"] = {"available": true, "materialized": false, "mode": "instantiate_failed"}
            _add_terrain_envelope(layer, width, depth)
    else:
        provider_state["terrain3d"] = {"available": FileAccess.file_exists(TERRAIN3D_PLUGIN), "materialized": false, "mode": "native_fallback"}
        _add_terrain_envelope(layer, width, depth)

    var boundary := _box_mesh("TerrainBoundsGuide", Vector3(0.0, -0.34, 0.0), Vector3(width, 0.08, depth), Color(0.16, 0.33, 0.24, 0.18))
    boundary.set_meta("map_forge_role", "terrain_bounds_guide")
    layer.add_child(boundary)
    return layer

static func _add_terrain_envelope(parent: Node3D, width: float, depth: float) -> void:
    var ground := _box_mesh("NativeTerrainFallback", Vector3(0.0, -0.4, 0.0), Vector3(width, 0.6, depth), Color(0.12, 0.2, 0.16, 1.0))
    ground.set_meta("map_forge_role", "terrain_native_fallback")
    parent.add_child(ground)

static func _build_structure_layer(root: Node3D, map_data: Dictionary, provider_state: Dictionary) -> Node3D:
    var layer := Node3D.new()
    layer.name = "Structures"
    root.add_child(layer)

    var cyclops_workspace: Node = null
    if FileAccess.file_exists(CYCLOPS_ROOT_SCRIPT):
        var script = load(CYCLOPS_ROOT_SCRIPT)
        if script != null:
            var instance = script.new()
            if instance is Node:
                cyclops_workspace = instance
                cyclops_workspace.name = "CyclopsWorkspace"
                cyclops_workspace.set_meta("map_forge_role", "cyclops_workspace")
                layer.add_child(cyclops_workspace)
    provider_state["cyclops"] = {
        "available": FileAccess.file_exists(CYCLOPS_ROOT_SCRIPT),
        "materialized": cyclops_workspace != null,
        "mode": "workspace_plus_provider_neutral_guides" if cyclops_workspace != null else "native_fallback_guides"
    }

    var guides := Node3D.new()
    guides.name = "StructureGuides"
    layer.add_child(guides)
    var authoring: Dictionary = map_data.get("authoring", {})
    var structure_guides: Array = authoring.get("structure_guides", [])
    for value in structure_guides:
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var item: Dictionary = value
        var id := String(item.get("id", "structure"))
        var pos := MAP_CONTRACT.vec3_from(item.get("position", []))
        var size := MAP_CONTRACT.vec3_from(item.get("size", []), Vector3(2.0, 2.0, 2.0))
        var mesh := _box_mesh(id, pos, size, Color(0.36, 0.42, 0.45, 0.65))
        mesh.set_meta("map_forge_role", "structure_guide")
        mesh.set_meta("structure_kind", String(item.get("kind", "block")))
        mesh.set_meta("provider_target", "cyclops")
        guides.add_child(mesh)

    for base_value in map_data.get("bases", []):
        if typeof(base_value) != TYPE_DICTIONARY:
            continue
        var base: Dictionary = base_value
        var base_pos := MAP_CONTRACT.vec3_from(base.get("position", []))
        var marker := Marker3D.new()
        marker.name = "%s_StructureSocket" % String(base.get("id", "base"))
        marker.position = base_pos
        marker.set_meta("map_forge_role", "fortress_socket")
        marker.set_meta("team", String(base.get("team", "neutral")))
        guides.add_child(marker)
    return layer

static func _build_scatter_layer(root: Node3D, map_data: Dictionary, provider_state: Dictionary) -> Node3D:
    var layer := Node3D.new()
    layer.name = "Scatter"
    root.add_child(layer)

    var authoring: Dictionary = map_data.get("authoring", {})
    var zones: Array = authoring.get("scatter_zones", [])
    var provider_ok := FileAccess.file_exists(PROTON_SCATTER_SCRIPT) and FileAccess.file_exists(PROTON_SHAPE_SCRIPT) and FileAccess.file_exists(PROTON_BOX_SHAPE_SCRIPT)
    var scatter_node: Node = null
    if provider_ok:
        var scatter_script = load(PROTON_SCATTER_SCRIPT)
        if scatter_script != null:
            var scatter_instance = scatter_script.new()
            if scatter_instance is Node:
                scatter_node = scatter_instance
                scatter_node.name = "ProtonScatter"
                if _has_property(scatter_node, "enabled"):
                    scatter_node.set("enabled", false)
                scatter_node.set_meta("map_forge_role", "scatter_provider")
                layer.add_child(scatter_node)

    var materialized_shapes := 0
    for value in zones:
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var zone: Dictionary = value
        var center := MAP_CONTRACT.vec3_from(zone.get("center", []))
        var size := MAP_CONTRACT.vec3_from(zone.get("size", []), Vector3(6.0, 3.0, 6.0))
        if scatter_node != null:
            var shape_script = load(PROTON_SHAPE_SCRIPT)
            var box_script = load(PROTON_BOX_SHAPE_SCRIPT)
            if shape_script != null and box_script != null:
                var shape_instance = shape_script.new()
                var box_resource = box_script.new()
                if shape_instance is Node and box_resource is Resource:
                    var shape_node: Node = shape_instance
                    shape_node.name = String(zone.get("id", "scatter_zone"))
                    shape_node.position = center
                    box_resource.set("size", size)
                    shape_node.set("shape", box_resource)
                    shape_node.set_meta("map_forge_role", "scatter_zone")
                    shape_node.set_meta("environment_kind", String(zone.get("kind", "environment")))
                    shape_node.set_meta("density", float(zone.get("density", 0.5)))
                    scatter_node.add_child(shape_node)
                    materialized_shapes += 1
                    continue
        var guide := _box_mesh(String(zone.get("id", "scatter_zone")), center, size, Color(0.12, 0.48, 0.2, 0.2))
        guide.set_meta("map_forge_role", "scatter_zone_fallback")
        guide.set_meta("environment_kind", String(zone.get("kind", "environment")))
        layer.add_child(guide)

    provider_state["proton_scatter"] = {
        "available": provider_ok,
        "materialized": scatter_node != null,
        "zone_shapes": materialized_shapes,
        "mode": "disabled_provider_ready_for_items_and_modifiers" if scatter_node != null else "native_fallback_guides"
    }
    return layer

static func _build_gameplay_guides(root: Node3D, map_data: Dictionary) -> Node3D:
    var layer := Node3D.new()
    layer.name = "GameplayGuides"
    root.add_child(layer)

    for base_value in map_data.get("bases", []):
        if typeof(base_value) != TYPE_DICTIONARY:
            continue
        var base: Dictionary = base_value
        var pos := MAP_CONTRACT.vec3_from(base.get("position", []))
        var marker := _cylinder_mesh(String(base.get("id", "base")), pos + Vector3(0.0, 0.06, 0.0), 1.3, 0.12, Color(0.2, 0.55, 1.0, 0.45) if String(base.get("team", "")) == "blue" else Color(1.0, 0.25, 0.2, 0.45))
        marker.set_meta("map_forge_role", "base")
        layer.add_child(marker)
        if base.has("hero_spawn"):
            var spawn_pos := MAP_CONTRACT.vec3_from(base.get("hero_spawn", []))
            var spawn := _cylinder_mesh("%s_HeroSpawn" % String(base.get("id", "base")), spawn_pos + Vector3(0.0, 0.04, 0.0), 0.7, 0.08, Color(0.85, 0.7, 0.2, 0.55))
            spawn.set_meta("map_forge_role", "hero_spawn")
            layer.add_child(spawn)

    for objective_value in map_data.get("objectives", []):
        if typeof(objective_value) != TYPE_DICTIONARY:
            continue
        var objective: Dictionary = objective_value
        var pos := MAP_CONTRACT.vec3_from(objective.get("position", []))
        var radius := maxf(float(objective.get("radius", 2.0)), 0.25)
        var marker := _cylinder_mesh(String(objective.get("id", "objective")), pos + Vector3(0.0, 0.045, 0.0), radius, 0.09, Color(0.7, 0.3, 0.95, 0.32))
        marker.set_meta("map_forge_role", "objective")
        layer.add_child(marker)
    return layer

static func _build_navigation_guides(root: Node3D, map_data: Dictionary) -> Node3D:
    var layer := Node3D.new()
    layer.name = "NavigationGuides"
    root.add_child(layer)

    for route_value in map_data.get("routes", []):
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var points: Array = route.get("points", [])
        var width := maxf(float(route.get("width", 2.0)), 0.25)
        for i in range(1, points.size()):
            var a := MAP_CONTRACT.vec3_from(points[i - 1])
            var b := MAP_CONTRACT.vec3_from(points[i])
            var segment := _route_segment("%s_%02d" % [String(route.get("id", "route")), i - 1], a, b, width)
            segment.set_meta("map_forge_role", "route_corridor")
            segment.set_meta("route_kind", String(route.get("kind", "primary")))
            layer.add_child(segment)

    for region_value in map_data.get("regions", []):
        if typeof(region_value) != TYPE_DICTIONARY:
            continue
        var region: Dictionary = region_value
        if String(region.get("kind", "")) != "choke":
            continue
        var center := MAP_CONTRACT.vec3_from(region.get("center", []))
        var width := maxf(float(region.get("width", 2.0)), 0.25)
        var guide := _box_mesh(String(region.get("id", "choke")), center + Vector3(0.0, 0.05, 0.0), Vector3(width, 0.1, 1.0), Color(1.0, 0.55, 0.12, 0.38))
        guide.set_meta("map_forge_role", "choke_guide")
        layer.add_child(guide)
    return layer

static func _build_import_socket(root: Node3D, provider_state: Dictionary) -> Node3D:
    var layer := Node3D.new()
    layer.name = "Import"
    root.add_child(layer)
    var marker := Marker3D.new()
    marker.name = "FuncGodotImportSocket"
    marker.set_meta("map_forge_role", "import_socket")
    marker.set_meta("provider", "FuncGodot")
    layer.add_child(marker)
    provider_state["func_godot"] = {
        "available": FileAccess.file_exists(FUNCGODOT_PLUGIN),
        "materialized": FileAccess.file_exists(FUNCGODOT_PLUGIN),
        "mode": "import_socket"
    }
    return layer

static func _route_segment(node_name: String, a: Vector3, b: Vector3, width: float) -> MeshInstance3D:
    var delta := b - a
    var length := Vector2(delta.x, delta.z).length()
    var midpoint := (a + b) * 0.5 + Vector3(0.0, 0.035, 0.0)
    var node := _box_mesh(node_name, midpoint, Vector3(maxf(length, 0.1), 0.07, width), Color(0.2, 0.7, 0.95, 0.18))
    node.rotation.y = -atan2(delta.z, delta.x)
    return node

static func _box_mesh(node_name: String, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = node_name
    node.position = position
    var mesh := BoxMesh.new()
    mesh.size = size
    node.mesh = mesh
    node.material_override = _material(color)
    return node

static func _cylinder_mesh(node_name: String, position: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = node_name
    node.position = position
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    node.mesh = mesh
    node.material_override = _material(color)
    return node

static func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.9
    if color.a < 0.999:
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    return material

static func _assign_owner_recursive(node: Node, root: Node) -> void:
    node.owner = root
    for child in node.get_children():
        _assign_owner_recursive(child, root)

static func _has_property(object: Object, property_name: String) -> bool:
    for property in object.get_property_list():
        if String(property.get("name", "")) == property_name:
            return true
    return false

static func _ensure_dir(path: String) -> void:
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute)

static func _write_json(path: String, data: Dictionary) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(data, "  ", false) + "\n")
        file.close()
