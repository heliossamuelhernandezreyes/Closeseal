extends SceneTree
## Trusted authoring bridge. No genre, node-class or plugin API allowlist.
## Built-in saves stay in the run bundle. Project scripts have ordinary Godot
## permissions and must use context.output_path for transactional output.

var _objects: Dictionary = {}
var _results: Array = []
var _scene: Node
var _output: String
var _response: String
var _error: String = ""
var _artifacts: Array = []

func _initialize() -> void:
    _run.call_deferred()

func _finish(result: Dictionary) -> void:
    var file := FileAccess.open(_response, FileAccess.WRITE)
    if file == null:
        push_error("Cannot write authoring response")
        quit(1)
        return
    file.store_string(JSON.stringify(result, "  "))
    print("ARCONT_AUTHORING_RESULT=" + JSON.stringify({"ok": result.get("ok", false), "steps": _results.size()}))
    for object in _objects.values():
        if object is Node and is_instance_valid(object) and object != _scene and object.get_parent() == null:
            object.free()
    if is_instance_valid(_scene):
        _scene.free()
    _objects.clear()
    quit(0 if result.get("ok", false) else 1)

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 2:
        quit(1)
        return
    _response = args[1]
    var request = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
    if not request is Dictionary:
        _finish({"ok": false, "error": "invalid request"})
        return
    _output = String(request["output_directory"]).replace("\\", "/")
    if request.get("operation") == "discover":
        _finish(_discover(request.get("options", {})))
        return
    var recipe: Dictionary = request.get("recipe", {})
    for step in recipe.get("steps", []):
        var started := Time.get_ticks_usec()
        var value = await _step(step)
        _results.append({"id": step.get("id", ""), "op": step.get("op", ""),
                         "value": _encode(value), "elapsed_ms": (Time.get_ticks_usec() - started) / 1000.0})
        if not _error.is_empty():
            _finish({"ok": false, "error": _error, "steps": _results, "artifacts": _artifacts})
            return
    _finish({"ok": true, "engine": Engine.get_version_info(), "steps": _results,
             "artifacts": _artifacts, "scene_tree": _tree(_scene),
             "limits": ["Linux authoring measurements do not establish Android performance"]})

func _discover(options: Dictionary) -> Dictionary:
    var inventory: Array = []
    _inventory("res://addons", inventory)
    var result := {"ok": true, "engine": Engine.get_version_info(),
                   "native_classes": ClassDB.get_class_list(), "singletons": Engine.get_singleton_list(),
                   "scripts": inventory, "providers": _read_json("res://third_party/map_authoring.lock.json"),
                   "operations": ["new", "load", "singleton", "node", "set", "call", "describe", "inspect", "attach", "remove", "wait", "assert", "save", "capture", "ray", "profile", "script"],
                   "variant_types": ["Vector2", "Vector3", "Vector4", "Vector2i", "Vector3i", "Color", "NodePath", "StringName", "Quaternion", "Basis", "Transform3D", "AABB", "Rect2", "Plane", "RID", "PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array", "PackedStringArray", "PackedVector2Array", "PackedVector3Array", "PackedColorArray"],
                   "extensions": "script step calls a trusted project GDScript run(context, arguments); context is this bridge"}
    if options.has("class"):
        var klass := String(options["class"])
        if not ClassDB.class_exists(klass):
            return {"ok": false, "error": "unknown native class: " + klass}
        result["api"] = {"class": klass, "properties": ClassDB.class_get_property_list(klass),
                         "methods": ClassDB.class_get_method_list(klass), "signals": ClassDB.class_get_signal_list(klass),
                         "constants": ClassDB.class_get_integer_constant_list(klass)}
    if options.has("script"):
        var script = load(String(options["script"]))
        if not script is Script or not script.can_instantiate():
            return {"ok": false, "error": "script is not instantiable"}
        result["api"] = {"script": options["script"], "base_class": script.get_instance_base_type(),
                         "properties": script.get_script_property_list(), "methods": script.get_script_method_list(),
                         "signals": script.get_script_signal_list(), "constants": _encode(script.get_script_constant_map())}
    return _encode(result)

func _inventory(path: String, result: Array) -> void:
    var directory := DirAccess.open(path)
    if directory == null:
        return
    for file in directory.get_files():
        if file.ends_with(".gd") or file == "plugin.cfg" or file.ends_with(".gdextension"):
            result.append({"path": path.path_join(file), "sha256": FileAccess.get_sha256(path.path_join(file))})
    for child in directory.get_directories():
        if not child.begins_with("."):
            _inventory(path.path_join(child), result)

func _read_json(path: String):
    return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null

func object(identifier: String):
    if not _objects.has(identifier):
        _error = "unknown object reference: " + identifier
        return null
    return _objects[identifier]

func register(identifier: String, value) -> void:
    if _objects.has(identifier):
        _error = "object reference already exists: " + identifier
        return
    _objects[identifier] = value

func output_path(relative: String) -> String:
    if relative.is_empty() or relative.is_absolute_path() or relative.begins_with("res://") or relative.begins_with("user://"):
        _error = "save requires a bundle-relative path"
        return ""
    var path := _output.path_join(relative).simplify_path()
    if not path.begins_with(_output + "/"):
        _error = "output path escapes bundle"
        return ""
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    return path

func _decode(value):
    if value is Array:
        var array: Array = []
        for item in value:
            array.append(_decode(item))
        return array
    if not value is Dictionary:
        return value
    if value.has("$ref"):
        return object(String(value["$ref"]))
    if value.has("$output"):
        return output_path(String(value["$output"]))
    if value.has("$type"):
        var raw = value.get("value", [])
        var v: Array = raw if raw is Array else []
        match String(value["$type"]):
            "Vector2": return Vector2(v[0], v[1])
            "Vector3": return Vector3(v[0], v[1], v[2])
            "Vector4": return Vector4(v[0], v[1], v[2], v[3])
            "Vector2i": return Vector2i(v[0], v[1])
            "Vector3i": return Vector3i(v[0], v[1], v[2])
            "Color": return Color(v[0], v[1], v[2], v[3] if v.size() > 3 else 1.0)
            "NodePath": return NodePath(String(value.get("value", "")))
            "StringName": return StringName(String(value.get("value", "")))
            "Quaternion": return Quaternion(v[0], v[1], v[2], v[3])
            "Basis": return Basis(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), Vector3(v[6], v[7], v[8]))
            "Transform3D": return Transform3D(_decode(v[0]), _decode(v[1]))
            "AABB": return AABB(_decode(v[0]), _decode(v[1]))
            "Rect2": return Rect2(_decode(v[0]), _decode(v[1]))
            "Plane": return Plane(_decode(v[0]), float(v[1]))
            "RID": return RID()
            "PackedByteArray": return PackedByteArray(v)
            "PackedInt32Array": return PackedInt32Array(v)
            "PackedInt64Array": return PackedInt64Array(v)
            "PackedFloat32Array": return PackedFloat32Array(v)
            "PackedFloat64Array": return PackedFloat64Array(v)
            "PackedStringArray": return PackedStringArray(v)
            "PackedVector2Array", "PackedVector3Array", "PackedColorArray":
                var decoded: Array = []
                for item in v: decoded.append(_decode(item))
                match String(value["$type"]):
                    "PackedVector2Array": return PackedVector2Array(decoded)
                    "PackedVector3Array": return PackedVector3Array(decoded)
                    "PackedColorArray": return PackedColorArray(decoded)
        _error = "unsupported variant type: " + String(value["$type"])
        return null
    var dictionary: Dictionary = {}
    for key in value:
        dictionary[key] = _decode(value[key])
    return dictionary

func _encode(value, depth: int = 0):
    if depth > 8:
        return {"truncated": true}
    if value is Object:
        if not is_instance_valid(value): return null
        var identity := {"class": value.get_class()}
        if value is Node: identity["name"] = String(value.name)
        if value is Resource: identity["resource_path"] = value.resource_path
        if value.get_script() != null: identity["script"] = value.get_script().resource_path
        return identity
    if value is Dictionary:
        var dictionary: Dictionary = {}
        for key in value: dictionary[String(key)] = _encode(value[key], depth + 1)
        return dictionary
    if value is Array or typeof(value) in [TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY]:
        var array: Array = []
        for item in value: array.append(_encode(item, depth + 1))
        return array
    match typeof(value):
        TYPE_VECTOR2, TYPE_VECTOR2I: return {"$type": type_string(typeof(value)), "value": [value.x, value.y]}
        TYPE_VECTOR3, TYPE_VECTOR3I: return {"$type": type_string(typeof(value)), "value": [value.x, value.y, value.z]}
        TYPE_VECTOR4, TYPE_QUATERNION: return {"$type": type_string(typeof(value)), "value": [value.x, value.y, value.z, value.w]}
        TYPE_COLOR: return {"$type": "Color", "value": [value.r, value.g, value.b, value.a]}
        TYPE_TRANSFORM3D: return {"$type": "Transform3D", "value": [_encode(value.basis), _encode(value.origin)]}
        TYPE_BASIS: return {"$type": "Basis", "value": [value.x.x, value.x.y, value.x.z, value.y.x, value.y.y, value.y.z, value.z.x, value.z.y, value.z.z]}
        TYPE_AABB: return {"$type": "AABB", "value": [_encode(value.position), _encode(value.size)]}
        TYPE_RECT2: return {"$type": "Rect2", "value": [_encode(value.position), _encode(value.size)]}
        TYPE_PLANE: return {"$type": "Plane", "value": [_encode(value.normal), value.d]}
        TYPE_RID: return {"$type": "RID", "valid": value.is_valid()}
        TYPE_STRING_NAME, TYPE_NODE_PATH: return String(value)
        TYPE_SIGNAL, TYPE_CALLABLE: return str(value)
    return value

func _set_properties(target: Object, properties: Dictionary) -> void:
    var names: Array = []
    for p in target.get_property_list(): names.append(String(p["name"]))
    for property in properties:
        if not String(property) in names:
            _error = "unknown property %s on %s" % [property, target.get_class()]
            return
        var value = _decode(properties[property])
        if not _error.is_empty(): return
        target.set(StringName(property), value)

func _step(step: Dictionary):
    var op := String(step.get("op", ""))
    var id := String(step.get("id", ""))
    match op:
        "new", "load", "singleton", "node":
            var value = null
            if op == "new":
                if step.has("script"):
                    var script = load(String(step["script"]))
                    if script is Script and script.can_instantiate(): value = script.new()
                elif ClassDB.can_instantiate(StringName(step.get("class", ""))):
                    value = ClassDB.instantiate(StringName(step["class"]))
            elif op == "load":
                var path = _decode(step["path"])
                value = ResourceLoader.load(String(path), "", ResourceLoader.CACHE_MODE_IGNORE)
                if step.get("instantiate", false) and value is PackedScene: value = value.instantiate()
            elif op == "singleton":
                if Engine.has_singleton(StringName(step["name"])): value = Engine.get_singleton(StringName(step["name"]))
            else:
                var parent = object(String(step["target"]))
                if parent is Node: value = parent.get_node_or_null(NodePath(step["path"]))
            if value == null or id.is_empty():
                _error = "cannot create/load/reference object: " + id
                return null
            _objects[id] = value
            if value is Node:
                if step.has("name"): value.name = String(step["name"])
                if _scene == null: _scene = value
                if step.has("parent"):
                    var parent = object(String(step["parent"]))
                    if parent is Node: parent.add_child(value)
                    else: _error = "parent must reference a Node"
            _set_properties(value, step.get("properties", {}))
            return value
        "set":
            var target = object(String(step["target"]))
            if target is Object: _set_properties(target, step.get("properties", {}))
            return target
        "call":
            var target = object(String(step["target"]))
            var method := StringName(step["method"])
            if not target is Object or not target.has_method(method):
                _error = "method not available: " + String(method)
                return null
            var arguments = _decode(step.get("args", []))
            if not _error.is_empty(): return null
            var value = await target.callv(method, arguments)
            if not id.is_empty(): _objects[id] = value
            return value
        "describe", "inspect":
            var target = object(String(step["target"]))
            if not target is Object: return null
            var values: Dictionary = {}
            for p in target.get_property_list():
                if int(p.get("usage", 0)) & PROPERTY_USAGE_STORAGE:
                    if step.get("properties", []).is_empty() or String(p["name"]) in step["properties"]:
                        values[String(p["name"])] = _encode(target.get(StringName(p["name"])))
            var result := {"object": _encode(target), "values": values}
            if op == "describe":
                result["properties"] = target.get_property_list()
                result["methods"] = target.get_method_list()
                result["signals"] = target.get_signal_list()
            if target is Node: result["tree"] = _tree(target)
            return result
        "attach":
            var target = object(String(step.get("target", "")))
            if not target is Node:
                _error = "attach requires Node"
                return null
            if target.get_parent() == null: root.add_child(target)
            return true
        "remove":
            var target = object(String(step["target"]))
            if target is Node:
                if target == _scene: _scene = null
                target.free()
            _objects.erase(String(step["target"]))
            return true
        "wait":
            for _frame in range(int(step.get("frames", 2))):
                if step.get("physics", false): await physics_frame
                else: await process_frame
            return true
        "assert":
            var actual = _decode(step.get("actual"))
            var expected = _decode(step.get("equals"))
            if _encode(actual) != _encode(expected): _error = String(step.get("message", "assertion failed"))
            return actual
        "save":
            var target = object(String(step["target"]))
            var path := output_path(String(step["path"]))
            if not _error.is_empty(): return null
            var resource: Resource
            if target is Node:
                _owners(target, target)
                var packed := PackedScene.new()
                if packed.pack(target) != OK:
                    _error = "scene packing failed"
                    return null
                resource = packed
            elif target is Resource: resource = target
            else:
                _error = "save requires Node or Resource"
                return null
            if ResourceSaver.save(resource, path) != OK: _error = "resource save failed"
            _artifacts.append(path)
            return path
        "capture":
            var camera = object(String(step["camera"]))
            if not camera is Camera3D:
                _error = "capture requires Camera3D"
                return null
            root.size = Vector2i(int(step.get("width", 1280)), int(step.get("height", 720)))
            camera.make_current()
            await process_frame
            await process_frame
            await RenderingServer.frame_post_draw
            var path := output_path(String(step.get("path", "capture.png")))
            if not _error.is_empty(): return null
            if root.get_texture().get_image().save_png(path) != OK: _error = "capture save failed"
            _artifacts.append(path)
            return path
        "ray":
            if not _scene is Node3D or not _scene.is_inside_tree():
                _error = "ray requires an attached Node3D scene"
                return null
            await physics_frame
            var query := PhysicsRayQueryParameters3D.create(_decode(step["from"]), _decode(step["to"]), int(step.get("mask", 1)))
            var hit: Dictionary = _scene.get_world_3d().direct_space_state.intersect_ray(query)
            if step.get("require_hit", false) and hit.is_empty(): _error = "required collision ray missed"
            return hit
        "profile":
            var samples: Array = []
            for _frame in range(int(step.get("frames", 60))):
                var started := Time.get_ticks_usec()
                await process_frame
                samples.append((Time.get_ticks_usec() - started) / 1000.0)
            return {"frame_wall_ms": samples, "objects": Performance.get_monitor(Performance.OBJECT_COUNT),
                    "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
                    "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
                    "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "scope": "authoring process; target hardware unmeasured"}
        "script":
            var script = load(String(step["path"]))
            if not script is Script or not script.can_instantiate():
                _error = "cannot load authoring script"
                return null
            var tool = script.new()
            if not tool.has_method("run"):
                _error = "authoring script requires run(context, arguments)"
                return null
            var value = await tool.call("run", self, _decode(step.get("args", {})))
            if not id.is_empty(): _objects[id] = value
            if value is Dictionary and value.get("ok", true) == false: _error = String(value.get("error", "authoring script failed"))
            if not tool is RefCounted: tool.free()
            return value
    _error = "unsupported recipe step: " + op
    return null

func _owners(node: Node, owner_root: Node) -> void:
    for child in node.get_children():
        child.owner = owner_root
        _owners(child, owner_root)

func _tree(node: Node):
    if not is_instance_valid(node): return null
    var children: Array = []
    for child in node.get_children(): children.append(_tree(child))
    return {"name": String(node.name), "class": node.get_class(), "script": node.get_script().resource_path if node.get_script() != null else "", "children": children}
