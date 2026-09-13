extends RefCounted

const MapContract = preload("res://src/map/map_contract.gd")

var root: Node3D
var map_data: Dictionary
var layers: Dictionary = {}
var materials: Dictionary = {}
var stats := {
    "route_segments": 0,
    "structures": 0,
    "objectives": 0,
    "scatter_instances": 0,
}

func _init(target: Node3D, contract: Dictionary) -> void:
    root = target
    map_data = contract

func build() -> Dictionary:
    _create_layers()
    _load_materials()
    _build_terrain()
    _build_routes()
    _build_structures()
    _build_objectives()
    _build_scatter()
    _build_map_frame()
    return stats.duplicate(true)

func _create_layers() -> void:
    for layer_name in ["VisualTerrain", "VisualRoutes", "VisualStructures", "VisualObjectives", "VisualScatter", "VisualDetails"]:
        var layer := Node3D.new()
        layer.name = layer_name
        root.add_child(layer)
        layers[layer_name] = layer

func _load_materials() -> void:
    var definitions: Array = map_data.get("authoring", {}).get("materials", [])
    for value in definitions:
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var definition: Dictionary = value
        var id := String(definition.get("id", "material"))
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(String(definition.get("albedo", "#808080")))
        material.roughness = float(definition.get("roughness", 0.8))
        material.metallic = float(definition.get("metallic", 0.0))
        if definition.has("emission"):
            material.emission_enabled = true
            material.emission = Color(String(definition.get("emission", "#000000")))
            material.emission_energy_multiplier = 2.5
        materials[id] = material
    _ensure_material("earth_dark", Color("17231f"), 0.98, 0.0)
    _ensure_material("grass_basin", Color("294331"), 0.96, 0.0)
    _ensure_material("lane_stone", Color("71644d"), 0.88, 0.03)
    _ensure_material("flank_stone", Color("526052"), 0.92, 0.01)
    _ensure_material("water_dark", Color("163b46"), 0.2, 0.25, Color("17566b"))
    _ensure_material("pine_needles", Color("173626"), 0.94, 0.0)
    _ensure_material("pine_highlight", Color("28563a"), 0.92, 0.0)
    _ensure_material("banner_blue", Color("1f72bd"), 0.52, 0.42)
    _ensure_material("banner_red", Color("b5362e"), 0.52, 0.42)

func _ensure_material(id: String, color: Color, roughness: float, metallic: float, emission := Color.BLACK) -> void:
    if materials.has(id):
        return
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    if emission != Color.BLACK:
        material.emission_enabled = true
        material.emission = emission
        material.emission_energy_multiplier = 1.8
    materials[id] = material

func _material(id: String) -> StandardMaterial3D:
    if materials.has(id):
        return materials[id]
    return materials.get("weathered_stone", materials.get("earth_dark"))

func _mesh(parent: Node3D, mesh: PrimitiveMesh, name_: String, pos: Vector3, material_id: String, rot := Vector3.ZERO, scale_ := Vector3.ONE) -> MeshInstance3D:
    mesh.material = _material(material_id)
    var node := MeshInstance3D.new()
    node.name = name_
    node.mesh = mesh
    node.position = pos
    node.rotation_degrees = rot
    node.scale = scale_
    parent.add_child(node)
    return node

func _box(parent: Node3D, name_: String, pos: Vector3, size: Vector3, material_id: String, rot := Vector3.ZERO) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    return _mesh(parent, mesh, name_, pos, material_id, rot)

func _cylinder(parent: Node3D, name_: String, pos: Vector3, radius: float, height: float, material_id: String, sides := 12, top_scale := 1.0) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.bottom_radius = radius
    mesh.top_radius = radius * top_scale
    mesh.height = height
    mesh.radial_segments = sides
    return _mesh(parent, mesh, name_, pos, material_id)

func _sphere(parent: Node3D, name_: String, pos: Vector3, radius: float, material_id: String) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.radial_segments = 12
    mesh.rings = 6
    return _mesh(parent, mesh, name_, pos, material_id)

func _prism(parent: Node3D, name_: String, pos: Vector3, size: Vector3, material_id: String, rot := Vector3.ZERO) -> MeshInstance3D:
    var mesh := PrismMesh.new()
    mesh.size = size
    return _mesh(parent, mesh, name_, pos, material_id, rot)

func _build_terrain() -> void:
    var layer: Node3D = layers["VisualTerrain"]
    var bounds: Dictionary = map_data.get("bounds", {})
    var width := maxf(float(bounds.get("width", 96.0)), 16.0)
    var depth := maxf(float(bounds.get("depth", 64.0)), 16.0)
    _box(layer, "DeepEarth", Vector3(0, -0.75, 0), Vector3(width + 8.0, 1.4, depth + 8.0), "earth_dark")
    _box(layer, "TacticalBasin", Vector3(0, -0.08, 0), Vector3(width, 0.18, depth), "grass_basin")

    # Raised edge terraces communicate the low-basin terrain profile without changing navigation geometry.
    for side in [-1.0, 1.0]:
        _box(layer, "Rim_%s" % side, Vector3(0, 0.32, side * (depth * 0.5 - 2.1)), Vector3(width - 5.0, 0.72, 4.2), "moss_stone")
        _box(layer, "RimCap_%s" % side, Vector3(0, 0.72, side * (depth * 0.5 - 2.8)), Vector3(width - 12.0, 0.18, 2.4), "weathered_stone")
    for side in [-1.0, 1.0]:
        _box(layer, "SideTerrace_%s" % side, Vector3(side * (width * 0.5 - 1.5), 0.22, 0), Vector3(3.0, 0.52, depth - 10.0), "moss_stone")

    # Two shallow magical rills make the bridge markers visually meaningful.
    for z in [-12.0, 12.0]:
        _box(layer, "Rill_%s" % z, Vector3(0, 0.015, z), Vector3(13.0, 0.045, 2.2), "water_dark")
        for x in [-6.8, 6.8]:
            _box(layer, "RillBank_%s_%s" % [z, x], Vector3(x, 0.13, z), Vector3(1.2, 0.28, 3.0), "weathered_stone", Vector3(0, 12.0 * signf(x * z), 0))

func _build_routes() -> void:
    var layer: Node3D = layers["VisualRoutes"]
    for route_value in map_data.get("routes", []):
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var id := String(route.get("id", "route"))
        var kind := String(route.get("kind", "secondary"))
        var width := maxf(float(route.get("width", 4.0)), 1.0)
        var material_id := "lane_stone" if kind == "primary" else ("earth_dark" if kind == "jungle" else "flank_stone")
        var points: Array = route.get("points", [])
        for index in range(1, points.size()):
            var a := MapContract.vec3_from(points[index - 1])
            var b := MapContract.vec3_from(points[index])
            var delta := b - a
            var length := Vector2(delta.x, delta.z).length()
            if length <= 0.01:
                continue
            var center := (a + b) * 0.5 + Vector3(0, 0.04, 0)
            var rotation_y := -rad_to_deg(atan2(delta.z, delta.x))
            _box(layer, "%s_Segment_%02d" % [id, index], center, Vector3(length + 0.25, 0.11, width), material_id, Vector3(0, rotation_y, 0))
            if kind == "primary":
                _box(layer, "%s_Inlay_%02d" % [id, index], center + Vector3(0, 0.065, 0), Vector3(length, 0.025, 0.34), "ancient_gold", Vector3(0, rotation_y, 0))
            stats["route_segments"] = int(stats["route_segments"]) + 1

func _build_structures() -> void:
    for value in map_data.get("authoring", {}).get("structure_guides", []):
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var guide: Dictionary = value
        var kind := String(guide.get("kind", "structure"))
        match kind:
            "fortress": _build_fortress(guide)
            "gate": _build_gatehouse(guide)
            "tower", "turret": _build_tower(guide)
            "ruin": _build_ruin(guide)
            "obelisk": _build_obelisk(guide)
            "pillar": _build_pillar(guide)
            "bridge": _build_bridge(guide)
            _: _build_simple_structure(guide)
        stats["structures"] = int(stats["structures"]) + 1

func _guide_values(guide: Dictionary) -> Dictionary:
    var size := MapContract.vec3_from(guide.get("size", []), Vector3(2, 2, 2))
    var center := MapContract.vec3_from(guide.get("position", []), Vector3.ZERO)
    return {
        "id": String(guide.get("id", "structure")),
        "center": center,
        "size": size,
        "ground": center.y - size.y * 0.5,
        "material": String(guide.get("material", "fortress_stone")),
    }

func _build_fortress(guide: Dictionary) -> void:
    var v := _guide_values(guide)
    var layer: Node3D = layers["VisualStructures"]
    var id: String = v["id"]
    var center: Vector3 = v["center"]
    var size: Vector3 = v["size"]
    var ground: float = v["ground"]
    var team_material: String = v["material"]
    var facing := -1.0 if center.x > 0.0 else 1.0
    _box(layer, id + "_Foundation", Vector3(center.x, ground + 0.3, center.z), Vector3(size.x + 1.0, 0.6, size.z + 1.0), "obsidian")
    _box(layer, id + "_Keep", Vector3(center.x, ground + size.y * 0.62, center.z), Vector3(size.x * 0.58, size.y * 1.24, size.z * 0.45), "fortress_stone")
    _prism(layer, id + "_Roof", Vector3(center.x, ground + size.y * 1.37, center.z), Vector3(size.x * 0.68, size.y * 0.28, size.z * 0.52), team_material, Vector3(0, 90, 0))
    for z_side in [-1.0, 1.0]:
        for x_side in [-1.0, 1.0]:
            var tower_pos := Vector3(center.x + x_side * size.x * 0.36, ground + size.y * 0.58, center.z + z_side * size.z * 0.38)
            _cylinder(layer, "%s_Corner_%s_%s" % [id, x_side, z_side], tower_pos, size.x * 0.17, size.y * 1.15, "fortress_stone", 10, 0.82)
            _cylinder(layer, "%s_Crown_%s_%s" % [id, x_side, z_side], tower_pos + Vector3(0, size.y * 0.63, 0), size.x * 0.22, 0.28, team_material, 10)
    for z_side in [-1.0, 1.0]:
        _box(layer, "%s_Wall_%s" % [id, z_side], Vector3(center.x, ground + size.y * 0.38, center.z + z_side * size.z * 0.42), Vector3(size.x * 0.72, size.y * 0.72, 0.55), "fortress_stone")
    _box(layer, id + "_Banner", Vector3(center.x + facing * size.x * 0.31, ground + size.y * 0.92, center.z), Vector3(0.12, size.y * 0.82, size.z * 0.22), "banner_blue" if team_material == "blue_iron" else "banner_red")
    _sphere(layer, id + "_Seal", Vector3(center.x, ground + size.y * 1.62, center.z), 0.48, "crystal_blue" if team_material == "blue_iron" else "crystal_violet")

func _build_gatehouse(guide: Dictionary) -> void:
    var v := _guide_values(guide)
    var layer: Node3D = layers["VisualStructures"]
    var id: String = v["id"]
    var center: Vector3 = v["center"]
    var size: Vector3 = v["size"]
    var ground: float = v["ground"]
    var team_material: String = v["material"]
    for z_side in [-1.0, 1.0]:
        _cylinder(layer, "%s_Tower_%s" % [id, z_side], Vector3(center.x, ground + size.y * 0.5, center.z + z_side * size.z * 0.38), size.x * 0.38, size.y, "fortress_stone", 10, 0.88)
        _cylinder(layer, "%s_Crown_%s" % [id, z_side], Vector3(center.x, ground + size.y + 0.12, center.z + z_side * size.z * 0.38), size.x * 0.46, 0.3, team_material, 10)
    _box(layer, id + "_Lintel", Vector3(center.x, ground + size.y * 0.82, center.z), Vector3(size.x * 0.7, size.y * 0.36, size.z * 0.62), "fortress_stone")
    _box(layer, id + "_Gate", Vector3(center.x + (-0.02 if center.x > 0 else 0.02), ground + size.y * 0.34, center.z), Vector3(0.16, size.y * 0.62, size.z * 0.46), "wood_dark")
    for z in [-2.0, -1.0, 0.0, 1.0, 2.0]:
        _box(layer, "%s_Portcullis_%s" % [id, z], Vector3(center.x, ground + size.y * 0.34, center.z + z * size.z * 0.075), Vector3(0.24, size.y * 0.65, 0.08), "ancient_gold")

func _build_tower(guide: Dictionary) -> void:
    var v := _guide_values(guide)
    var layer: Node3D = layers["VisualStructures"]
    var id: String = v["id"]
    var center: Vector3 = v["center"]
    var size: Vector3 = v["size"]
    var ground: float = v["ground"]
    var team_material: String = v["material"]
    var radius := minf(size.x, size.z) * 0.5
    _cylinder(layer, id + "_Foot", Vector3(center.x, ground + 0.22, center.z), radius * 1.18, 0.44, "obsidian", 12)
    _cylinder(layer, id + "_Shaft", Vector3(center.x, ground + size.y * 0.48, center.z), radius * 0.72, size.y * 0.92, "fortress_stone", 12, 0.8)
    _cylinder(layer, id + "_Crown", Vector3(center.x, ground + size.y * 0.94, center.z), radius, 0.52, team_material, 12)
    for index in range(8):
        var angle := TAU * float(index) / 8.0
        var battlement_pos := Vector3(center.x + cos(angle) * radius * 0.78, ground + size.y * 1.08, center.z + sin(angle) * radius * 0.78)
        _box(layer, "%s_Merlon_%02d" % [id, index], battlement_pos, Vector3(0.32, 0.42, 0.32), "fortress_stone", Vector3(0, -rad_to_deg(angle), 0))
    _sphere(layer, id + "_Core", Vector3(center.x, ground + size.y * 1.25, center.z), radius * 0.26, "crystal_blue" if team_material == "blue_iron" else "crystal_violet")

func _build_ruin(guide: Dictionary) -> void:
    var v := _guide_values(guide)
    var layer: Node3D = layers["VisualStructures"]
    var id: String = v["id"]
    var center: Vector3 = v["center"]
    var size: Vector3 = v["size"]
    var ground: float = v["ground"]
    var material_id: String = v["material"]
    var pieces := 5
    for index in range(pieces):
        var t := (float(index) + 0.5) / float(pieces)
        var x := center.x - size.x * 0.5 + t * size.x
        var height := size.y * (0.42 + 0.13 * float((index * 3) % 4))
        var z_offset := 0.16 * sin(float(index) * 2.4)
        _box(layer, "%s_Block_%02d" % [id, index], Vector3(x, ground + height * 0.5, center.z + z_offset), Vector3(size.x / float(pieces) * 0.92, height, size.z), material_id, Vector3(0, float((index % 3) - 1) * 4.0, float((index % 2) * 2 - 1) * 2.5))
    _cylinder(layer, id + "_EndPillar", Vector3(center.x - size.x * 0.47, ground + size.y * 0.48, center.z), size.z * 0.48, size.y * 0.96, "moss_stone", 8, 0.86)

func _build_obelisk(guide: Dictionary) -> void:
    var v := _guide_values(guide)
    var layer: Node3D = layers["VisualStructures"]
    var id: String = v["id"]
    var center: Vector3 = v["center"]
    var size: Vector3 = v["size"]
    var ground: float = v["ground"]
    _cylinder(layer, id + "_Plinth", Vector3(center.x, ground + 0.18, center.z), size.x * 0.72, 0.36, "obsidian", 8)
    _cylinder(layer, id + "_Step", Vector3(center.x, ground + 0.42, center.z), size.x * 0.52, 0.28, "ancient_gold", 8)
    _box(layer, id + "_Body", Vector3(center.x, ground + size.y * 0.52, center.z), Vector3(size.x * 0.48, size.y * 0.78, size.z * 0.48), "obsidian", Vector3(0, 45, 0))
    _prism(layer, id + "_Point", Vector3(center.x, ground + size.y * 0.98, center.z), Vector3(size.x * 0.72, size.y * 0.28, size.z * 0.72), String(v["material"]), Vector3(0, 45, 0))
    _sphere(layer, id + "_Rune", Vector3(center.x, ground + size.y * 0.66, center.z - size.z * 0.36), size.x * 0.16, String(v["material"]))

func _build_pillar(guide: Dictionary) -> void:
    var v := _guide_values(guide)
    var layer: Node3D = layers["VisualStructures"]
    var id: String = v["id"]
    var center: Vector3 = v["center"]
    var size: Vector3 = v["size"]
    var ground: float = v["ground"]
    _cylinder(layer, id + "_Base", Vector3(center.x, ground + 0.18, center.z), size.x * 0.55, 0.36, "weathered_stone", 8)
    _cylinder(layer, id + "_Shaft", Vector3(center.x, ground + size.y * 0.5, center.z), size.x * 0.32, size.y * 0.78, String(v["material"]), 8, 0.82)
    _box(layer, id + "_Capital", Vector3(center.x, ground + size.y * 0.91, center.z), Vector3(size.x * 0.78, 0.32, size.z * 0.78), "weathered_stone", Vector3(0, 45, 0))

func _build_bridge(guide: Dictionary) -> void:
    var v := _guide_values(guide)
    var layer: Node3D = layers["VisualStructures"]
    var id: String = v["id"]
    var center: Vector3 = v["center"]
    var size: Vector3 = v["size"]
    var ground: float = v["ground"]
    _box(layer, id + "_Deck", center, size, String(v["material"]))
    for z_side in [-1.0, 1.0]:
        _box(layer, "%s_Rail_%s" % [id, z_side], Vector3(center.x, ground + size.y + 0.38, center.z + z_side * size.z * 0.48), Vector3(size.x, 0.72, 0.18), "ancient_gold")
    for x_side in [-1.0, 1.0]:
        _cylinder(layer, "%s_Pier_%s" % [id, x_side], Vector3(center.x + x_side * size.x * 0.37, ground, center.z), 0.28, size.y * 1.8, "fortress_stone", 8)

func _build_simple_structure(guide: Dictionary) -> void:
    var v := _guide_values(guide)
    _box(layers["VisualStructures"], String(v["id"]), v["center"], v["size"], String(v["material"]))

func _build_objectives() -> void:
    var layer: Node3D = layers["VisualObjectives"]
    for value in map_data.get("objectives", []):
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var objective: Dictionary = value
        var id := String(objective.get("id", "objective"))
        var kind := String(objective.get("type", "seal"))
        var pos := MapContract.vec3_from(objective.get("position", []))
        var radius := maxf(float(objective.get("radius", 2.0)), 0.8)
        var material_id := String(objective.get("material", "crystal_violet"))
        _cylinder(layer, id + "_OuterRing", pos + Vector3(0, 0.10, 0), radius, 0.20, "obsidian", 20)
        _cylinder(layer, id + "_InnerRing", pos + Vector3(0, 0.22, 0), radius * 0.74, 0.08, material_id, 20)
        if kind == "seal":
            _cylinder(layer, id + "_Dais", pos + Vector3(0, 0.36, 0), radius * 0.34, 0.52, "ancient_gold", 8)
            _sphere(layer, id + "_Core", pos + Vector3(0, 1.18, 0), 0.52, material_id)
            for index in range(6):
                var angle := TAU * float(index) / 6.0
                _box(layer, "%s_Rune_%02d" % [id, index], pos + Vector3(cos(angle) * radius * 0.72, 0.31, sin(angle) * radius * 0.72), Vector3(0.8, 0.08, 0.24), material_id, Vector3(0, -rad_to_deg(angle), 0))
        elif kind == "ward":
            for index in range(3):
                var angle := TAU * float(index) / 3.0
                _cylinder(layer, "%s_Ward_%02d" % [id, index], pos + Vector3(cos(angle) * radius * 0.48, 0.62, sin(angle) * radius * 0.48), 0.18, 1.15, "ancient_gold", 8, 0.72)
            _sphere(layer, id + "_Core", pos + Vector3(0, 0.95, 0), 0.34, "crystal_blue")
        else:
            _cylinder(layer, id + "_Beacon", pos + Vector3(0, 0.75, 0), 0.32, 1.35, "ancient_gold", 8, 0.72)
            _sphere(layer, id + "_Light", pos + Vector3(0, 1.62, 0), 0.32, material_id)
        stats["objectives"] = int(stats["objectives"]) + 1

func _build_scatter() -> void:
    for value in map_data.get("authoring", {}).get("scatter_zones", []):
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var zone: Dictionary = value
        var kind := String(zone.get("kind", "forest"))
        if kind == "forest":
            _scatter_forest(zone)
        elif kind == "rock_field":
            _scatter_rocks(zone)
        elif kind == "rune_field":
            _scatter_runes(zone)

func _zone_transforms(zone: Dictionary, count: int, vertical_offset: float, min_scale: float, max_scale: float) -> Array[Transform3D]:
    var transforms: Array[Transform3D] = []
    var center := MapContract.vec3_from(zone.get("center", []))
    var size := MapContract.vec3_from(zone.get("size", []), Vector3(4, 2, 4))
    var rng := RandomNumberGenerator.new()
    rng.seed = abs(hash(String(map_data.get("id", "map")) + ":" + String(zone.get("id", "zone"))))
    for index in range(count):
        var pos := center + Vector3(rng.randf_range(-size.x * 0.5, size.x * 0.5), vertical_offset, rng.randf_range(-size.z * 0.5, size.z * 0.5))
        var scale_value := rng.randf_range(min_scale, max_scale)
        var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale_value, scale_value * rng.randf_range(0.88, 1.14), scale_value))
        transforms.append(Transform3D(basis, pos))
    return transforms

func _multimesh(name_: String, mesh: PrimitiveMesh, material_id: String, transforms: Array[Transform3D]) -> void:
    if transforms.is_empty():
        return
    mesh.material = _material(material_id)
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for index in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])
    var node := MultiMeshInstance3D.new()
    node.name = name_
    node.multimesh = multimesh
    layers["VisualScatter"].add_child(node)
    stats["scatter_instances"] = int(stats["scatter_instances"]) + transforms.size()

func _scatter_forest(zone: Dictionary) -> void:
    var size := MapContract.vec3_from(zone.get("size", []), Vector3(8, 3, 8))
    var density := clampf(float(zone.get("density", 0.5)), 0.0, 1.0)
    var count := clampi(int(size.x * size.z * density * 0.11), 7, 46)
    var is_dead := String(zone.get("asset", "")).contains("dead_tree")
    var transforms := _zone_transforms(zone, count, 0.95, 0.72, 1.34)
    var trunk := CylinderMesh.new()
    trunk.bottom_radius = 0.17
    trunk.top_radius = 0.11
    trunk.height = 1.9
    trunk.radial_segments = 7
    _multimesh(String(zone.get("id", "forest")) + "_Trunks", trunk, "wood_dark", transforms)
    if not is_dead:
        var canopy_transforms: Array[Transform3D] = []
        for transform in transforms:
            var canopy_transform := transform
            canopy_transform.origin.y += 1.72 * transform.basis.get_scale().y
            canopy_transforms.append(canopy_transform)
        var canopy := CylinderMesh.new()
        canopy.bottom_radius = 0.92
        canopy.top_radius = 0.04
        canopy.height = 2.5
        canopy.radial_segments = 8
        _multimesh(String(zone.get("id", "forest")) + "_Canopies", canopy, "pine_needles", canopy_transforms)

func _scatter_rocks(zone: Dictionary) -> void:
    var size := MapContract.vec3_from(zone.get("size", []), Vector3(8, 3, 5))
    var density := clampf(float(zone.get("density", 0.4)), 0.0, 1.0)
    var count := clampi(int(size.x * size.z * density * 0.14), 5, 24)
    var transforms := _zone_transforms(zone, count, 0.34, 0.42, 1.08)
    var rock := SphereMesh.new()
    rock.radius = 0.58
    rock.height = 0.82
    rock.radial_segments = 7
    rock.rings = 4
    _multimesh(String(zone.get("id", "rocks")) + "_Stones", rock, "weathered_stone", transforms)

func _scatter_runes(zone: Dictionary) -> void:
    var size := MapContract.vec3_from(zone.get("size", []), Vector3(8, 2, 4))
    var density := clampf(float(zone.get("density", 0.5)), 0.0, 1.0)
    var count := clampi(int(size.x * size.z * density * 0.13), 5, 18)
    var transforms := _zone_transforms(zone, count, 0.085, 0.45, 0.9)
    var rune := CylinderMesh.new()
    rune.bottom_radius = 0.34
    rune.top_radius = 0.34
    rune.height = 0.07
    rune.radial_segments = 6
    _multimesh(String(zone.get("id", "runes")) + "_Glyphs", rune, "crystal_violet", transforms)

func _build_map_frame() -> void:
    var layer: Node3D = layers["VisualDetails"]
    var bounds: Dictionary = map_data.get("bounds", {})
    var width := float(bounds.get("width", 96.0))
    var depth := float(bounds.get("depth", 64.0))
    for x in range(-int(width * 0.5) + 6, int(width * 0.5) - 5, 8):
        for z_side in [-1.0, 1.0]:
            var z: float = float(z_side) * (depth * 0.5 - 1.7)
            _cylinder(layer, "RimPillar_%s_%s" % [x, z_side], Vector3(float(x), 1.05, z), 0.42, 2.1, "weathered_stone", 8, 0.76)
            if x % 16 == 0:
                _sphere(layer, "RimRune_%s_%s" % [x, z_side], Vector3(float(x), 2.24, z), 0.19, "crystal_blue")
