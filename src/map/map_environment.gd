@tool
extends RefCounted

var root: Node3D
var authoring: Dictionary
var materials: Dictionary
var nodes: Dictionary = {}
var stats := {"heightfields": 0, "terrain_triangles": 0, "environment_objects": 0, "authored_lights": 0}

static func vec(value, fallback := Vector3.ZERO) -> Vector3:
    return Vector3(float(value[0]), float(value[1]), float(value[2])) if valid_vector(value) else fallback

static func valid_vector(value, length := 3, positive := false) -> bool:
    if not value is Array or value.size() != length:
        return false
    for n in value:
        if typeof(n) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(n)) or (positive and float(n) <= 0):
            return false
    return true

static func validate(a: Dictionary) -> Array[String]:
    var errors: Array[String] = []
    var ids: Dictionary = {}
    var objects: Dictionary = {}
    var material_ids: Dictionary = {}
    for m in a.get("materials", []):
        if m is Dictionary:
            material_ids[m.get("id", "")] = true
    for label in ["heightfields", "objects", "lights"]:
        var values = a.get(label, [])
        if not values is Array:
            errors.append(label + " must be an array")
            continue
        for v in values:
            if not v is Dictionary:
                errors.append(label + " entries must be objects")
                continue
            var identity := String(v.get("id", ""))
            if identity.is_empty() or ids.has(identity):
                errors.append(label + " requires unique nonempty ids")
            ids[identity] = true
            for key in ["position", "rotation_degrees", "scale"]:
                if v.has(key) and not valid_vector(v[key], 3, key == "scale"):
                    errors.append(identity + " has invalid " + key)
            if label == "heightfields":
                var columns := int(v.get("columns", 0))
                var rows := int(v.get("rows", 0))
                if columns < 2 or rows < 2 or columns > 2049 or rows > 2049 or float(columns) != float(v.get("columns", 0)) or float(rows) != float(v.get("rows", 0)):
                    errors.append("invalid heightfield dimensions")
                    continue
                var heights = v.get("heights")
                if not heights is Array or heights.size() != columns * rows:
                    errors.append("heightfield heights must match dimensions")
                elif not valid_vector(heights, heights.size()):
                    errors.append("heightfield heights must be finite")
                if not valid_vector(v.get("spacing", [1, 1]), 2, true):
                    errors.append("heightfield spacing must be positive")
                for key in ["paint", "holes"]:
                    if v.has(key) and (not v[key] is Array or v[key].size() != (columns - 1) * (rows - 1)):
                        errors.append("heightfield " + key + " must match cells")
                for key in ["rotation_degrees", "scale", "parent"]:
                    if v.has(key):
                        errors.append("heightfields use axis-aligned world spacing")
                if not material_ids.has(v.get("material", "")):
                    errors.append("heightfield material must exist")
                if v.get("paint", []) is Array:
                    for m in v.get("paint", []):
                        if not m is String or not material_ids.has(m):
                            errors.append("paint requires existing material ids")
                            break
                if v.get("holes", []) is Array:
                    for h in v.get("holes", []):
                        if not h is bool:
                            errors.append("holes must be booleans")
                            break
            if label == "objects":
                objects[identity] = v
                if v.get("type", "") not in ["group", "box", "sphere", "cylinder", "capsule", "plane", "prism", "torus"] or not valid_vector(v.get("size", [1, 1, 1]), 3, true):
                    errors.append("invalid primitive type or size")
            if label == "lights":
                if v.get("type", "") not in ["directional", "omni", "spot"]:
                    errors.append("unsupported light type")
                for key in ["energy", "range", "angle"]:
                    if v.has(key) and (typeof(v[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(v[key])) or float(v[key]) < 0 or (key == "angle" and float(v[key]) >= 90)):
                        errors.append("invalid light " + key)
    for identity in objects:
        var seen := {identity: true}
        var parent := String(objects[identity].get("parent", ""))
        while not parent.is_empty():
            if not objects.has(parent) or seen.has(parent):
                errors.append("object parent missing or cyclic")
                break
            seen[parent] = true
            parent = String(objects[parent].get("parent", ""))
    for label in ["geometry", "instances", "lights"]:
        if not a.get(label, []) is Array:
            continue
        for v in a.get(label, []):
            if v is Dictionary and v.has("parent") and not objects.has(v["parent"]):
                errors.append(label + " parent must name an authored object")
    if not a.get("environment", {}) is Dictionary:
        errors.append("environment must be an object")
    for g in a.get("geometry", []):
        if g is Dictionary and g.has("uvs"):
            if not g["uvs"] is Array or g["uvs"].size() != g.get("vertices", []).size():
                errors.append("geometry uvs must match vertices")
            else:
                for uv in g["uvs"]:
                    if not valid_vector(uv, 2):
                        errors.append("invalid geometry uv")
    return errors

func _init(target: Node3D, definitions: Dictionary, material_library: Dictionary) -> void:
    root = target
    authoring = definitions
    materials = material_library

func parent_for(definition: Dictionary, fallback: Node3D) -> Node3D:
    return nodes.get(definition.get("parent", ""), fallback)

func transform(node: Node3D, v: Dictionary) -> void:
    node.position = vec(v.get("position", [0, 0, 0]))
    node.rotation_degrees = vec(v.get("rotation_degrees", [0, 0, 0]))
    node.scale = vec(v.get("scale", [1, 1, 1]), Vector3.ONE)
    node.visible = bool(v.get("visible", true))

func build() -> Dictionary:
    for v in authoring.get("objects", []):
        var node: Node3D = Node3D.new() if v["type"] == "group" else MeshInstance3D.new()
        node.name = String(v["id"])
        root.add_child(node)
        nodes[v["id"]] = node
        if node is MeshInstance3D:
            node.mesh = primitive(v)
            node.material_override = materials.get(v.get("material", "earth_dark"))
            if bool(v.get("collision", false)):
                node.create_trimesh_collision()
            stats["environment_objects"] += 1
    for v in authoring.get("objects", []):
        var node: Node3D = nodes[v["id"]]
        var parent := parent_for(v, root)
        if node.get_parent() != parent:
            node.reparent(parent, false)
        transform(node, v)
    for v in authoring.get("heightfields", []):
        heightfield(v)
    for v in authoring.get("lights", []):
        var light: Light3D
        match v["type"]:
            "directional": light = DirectionalLight3D.new()
            "omni": light = OmniLight3D.new()
            "spot": light = SpotLight3D.new()
        light.name = String(v["id"])
        light.light_color = Color(String(v.get("color", "ffffff")))
        light.light_energy = float(v.get("energy", 1))
        light.shadow_enabled = bool(v.get("shadows", false))
        if light is OmniLight3D:
            light.omni_range = float(v.get("range", 20))
        if light is SpotLight3D:
            light.spot_range = float(v.get("range", 20))
            light.spot_angle = float(v.get("angle", 35))
        parent_for(v, root).add_child(light)
        transform(light, v)
        stats["authored_lights"] += 1
    return stats

func primitive(v: Dictionary) -> PrimitiveMesh:
    var size := vec(v.get("size", [1, 1, 1]), Vector3.ONE)
    var mesh: PrimitiveMesh
    match v["type"]:
        "box":
            mesh = BoxMesh.new()
            mesh.size = size
        "prism":
            mesh = PrismMesh.new()
            mesh.size = size
        "sphere":
            mesh = SphereMesh.new()
            mesh.radius = size.x * 0.5
            mesh.height = size.y
        "cylinder":
            mesh = CylinderMesh.new()
            mesh.bottom_radius = size.x * 0.5
            mesh.top_radius = float(v.get("top_radius", size.x * 0.5))
            mesh.height = size.y
        "capsule":
            mesh = CapsuleMesh.new()
            mesh.radius = minf(size.x * 0.5, size.y * 0.5)
            mesh.height = size.y
        "plane":
            mesh = PlaneMesh.new()
            mesh.size = Vector2(size.x, size.z)
        "torus":
            mesh = TorusMesh.new()
            mesh.inner_radius = size.x * 0.25
            mesh.outer_radius = size.x * 0.5
    return mesh

func heightfield(v: Dictionary) -> void:
    var columns := int(v["columns"])
    var rows := int(v["rows"])
    var heights: Array = v["heights"]
    var spacing: Array = v.get("spacing", [1, 1])
    var paint: Array = v.get("paint", [])
    var holes: Array = v.get("holes", [])
    var surfaces: Dictionary = {}
    for z in range(rows - 1):
        for x in range(columns - 1):
            var cell := z * (columns - 1) + x
            if not holes.is_empty() and holes[cell]:
                continue
            var material := String(paint[cell]) if not paint.is_empty() else String(v["material"])
            if not surfaces.has(material):
                surfaces[material] = {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array()}
            var surface: Dictionary = surfaces[material]
            for point in [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x, z + 1), Vector2i(x + 1, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]:
                var index: int = point.y * columns + point.x
                var left: float = heights[point.y * columns + maxi(0, point.x - 1)]
                var right: float = heights[point.y * columns + mini(columns - 1, point.x + 1)]
                var above: float = heights[maxi(0, point.y - 1) * columns + point.x]
                var below: float = heights[mini(rows - 1, point.y + 1) * columns + point.x]
                surface["vertices"].append(Vector3(point.x * float(spacing[0]), float(heights[index]), point.y * float(spacing[1])))
                surface["normals"].append(Vector3((left - right) / (2.0 * float(spacing[0])), 1, (above - below) / (2.0 * float(spacing[1]))).normalized())
                surface["uvs"].append(Vector2(float(point.x) / float(columns - 1), float(point.y) / float(rows - 1)))
            stats["terrain_triangles"] += 2
    var mesh := ArrayMesh.new()
    for material in surfaces:
        var arrays: Array = []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = surfaces[material]["vertices"]
        arrays[Mesh.ARRAY_NORMAL] = surfaces[material]["normals"]
        arrays[Mesh.ARRAY_TEX_UV] = surfaces[material]["uvs"]
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        mesh.surface_set_material(mesh.get_surface_count() - 1, materials.get(material))
    var node := MeshInstance3D.new()
    node.name = String(v["id"])
    node.mesh = mesh
    node.position = vec(v.get("position", [0, 0, 0]))
    root.add_child(node)
    if bool(v.get("collision", true)) and mesh.get_surface_count() > 0:
        node.create_trimesh_collision()
    stats["heightfields"] += 1

static func configure_world(target: Node3D, a: Dictionary) -> void:
    var settings: Dictionary = a.get("environment", {})
    var environment_node := WorldEnvironment.new()
    environment_node.name = "AuthoredEnvironment"
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(String(settings.get("background_color", "17212d")))
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(String(settings.get("ambient_color", "b8c8d7")))
    environment.ambient_light_energy = float(settings.get("ambient_energy", 0.6))
    environment.fog_enabled = bool(settings.get("fog_enabled", false))
    environment.fog_density = float(settings.get("fog_density", 0.01))
    environment.fog_light_color = Color(String(settings.get("fog_color", "808080")))
    environment_node.environment = environment
    target.add_child(environment_node)
    if a.get("lights", []).is_empty():
        var sun := DirectionalLight3D.new()
        sun.name = "DefaultSun"
        sun.rotation_degrees = Vector3(-48, -32, 0)
        sun.light_energy = 1.5
        target.add_child(sun)
