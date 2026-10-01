@tool
extends VBoxContainer

signal document_edited(document: Dictionary)

const CONTRACT = preload("res://src/map/map_contract.gd")
const VISUAL_KIT = preload("res://src/prototype/map_visual_kit.gd")

var document: Dictionary = {}
var tree: Tree
var json_editor: TextEdit
var status: Label
var viewport: SubViewport
var container: SubViewportContainer
var world: Node3D
var camera: Camera3D
var content: Node3D
var handles: Array[Dictionary] = []
var selected_object: Array = []
var position_editors: Array[SpinBox] = []
var selected_vector_key := ""
var yaw := 0.65
var pitch := 0.8
var distance := 140.0
var focus := Vector3.ZERO
var syncing := false
var orbiting := false
var panning := false

func _ready() -> void:
    var toolbar := HBoxContainer.new()
    add_child(toolbar)
    _button(toolbar, "Frame", frame_map)
    _button(toolbar, "Refresh 3D", _rebuild_scene)
    _button(toolbar, "Apply JSON", _apply_json)
    var help := Label.new()
    help.text = "Select a marker • right-drag: orbit • wheel: zoom"
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(help)
    container = SubViewportContainer.new()
    container.custom_minimum_size = Vector2(340, 260)
    container.size_flags_vertical = Control.SIZE_EXPAND_FILL
    container.stretch = true
    add_child(container)
    viewport = SubViewport.new()
    viewport.size = Vector2i(640, 360)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    container.add_child(viewport)
    container.gui_input.connect(_viewport_input)
    world = Node3D.new()
    viewport.add_child(world)
    camera = Camera3D.new()
    camera.current = true
    camera.far = 10000
    viewport.add_child(camera)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-50, -30, 0)
    sun.light_energy = 1.5
    world.add_child(sun)
    var environment_node := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("17212d")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("b8c8d7")
    environment.ambient_light_energy = 0.65
    environment_node.environment = environment
    world.add_child(environment_node)
    tree = Tree.new()
    tree.custom_minimum_size = Vector2(340, 155)
    tree.hide_root = false
    tree.item_selected.connect(_tree_selected)
    add_child(tree)
    var position_bar := HBoxContainer.new()
    add_child(position_bar)
    for axis in ["X", "Y", "Z"]:
        var label := Label.new()
        label.text = axis
        position_bar.add_child(label)
        var editor := SpinBox.new()
        editor.min_value = -1000000
        editor.max_value = 1000000
        editor.step = 0.25
        editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        editor.value_changed.connect(_position_changed)
        position_bar.add_child(editor)
        position_editors.append(editor)
    json_editor = TextEdit.new()
    json_editor.custom_minimum_size = Vector2(340, 150)
    json_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    add_child(json_editor)
    status = Label.new()
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(status)
    set_document(document)

func _button(parent: Node, label: String, callback: Callable) -> void:
    var button := Button.new()
    button.text = label
    button.pressed.connect(callback)
    parent.add_child(button)

func set_document(value: Dictionary) -> void:
    document = value.duplicate(true)
    if tree == null:
        return
    _rebuild_tree()
    _rebuild_scene()
    _show_selection()

func _rebuild_tree() -> void:
    syncing = true
    tree.clear()
    var root_item := tree.create_item()
    root_item.set_text(0, "Complete map contract")
    root_item.set_metadata(0, [])
    if selected_object.is_empty():
        root_item.select(0)
    for collection_path in [["bases"], ["objectives"], ["routes"], ["regions"], ["authoring", "structure_guides"], ["authoring", "scatter_zones"], ["authoring", "terrain", "landforms"], ["authoring", "materials"], ["authoring", "geometry"], ["authoring", "instances"]]:
        var values = _get_at(document, collection_path)
        if not values is Array:
            continue
        var category := tree.create_item(root_item)
        category.set_text(0, String(collection_path[-1]).capitalize())
        category.set_metadata(0, collection_path)
        for index in range(values.size()):
            if not values[index] is Dictionary:
                continue
            var item := tree.create_item(category)
            item.set_text(0, String(values[index].get("id", str(index))))
            var path: Array = collection_path.duplicate()
            path.append(index)
            item.set_metadata(0, path)
            if path == selected_object:
                item.select(0)

    syncing = false

func _get_at(root_value, path: Array):
    var value = root_value
    for key in path:
        if value is Dictionary and value.has(key):
            value = value[key]
        elif value is Array and key is int and key >= 0 and key < value.size():
            value = value[key]
        else:
            return null
    return value

func _set_at(root_value: Dictionary, path: Array, value) -> bool:
    if path.is_empty():
        return false
    var parent = _get_at(root_value, path.slice(0, path.size() - 1))
    if parent is Dictionary or parent is Array:
        parent[path[-1]] = value
        return true
    return false

func _tree_selected() -> void:
    if syncing:
        return
    var item := tree.get_selected()
    if item != null:
        selected_object = item.get_metadata(0)
        _show_selection()

func _show_selection() -> void:
    if json_editor == null:
        return
    var value = _get_at(document, selected_object)
    json_editor.text = JSON.stringify(value, "  ")
    selected_vector_key = ""
    if value is Dictionary:
        for key in ["position", "center"]:
            if value.get(key) is Array:
                selected_vector_key = key
                break
    syncing = true
    var vector := Vector3.ZERO
    if not selected_vector_key.is_empty():
        vector = CONTRACT.vec3_from(value[selected_vector_key])
    for axis in range(position_editors.size()):
        position_editors[axis].editable = not selected_vector_key.is_empty()
        position_editors[axis].value = vector[axis]
    syncing = false

func _position_changed(_value: float) -> void:
    if syncing or selected_vector_key.is_empty():
        return
    var next := document.duplicate(true)
    var item = _get_at(next, selected_object)
    item[selected_vector_key] = [position_editors[0].value, position_editors[1].value, position_editors[2].value]
    _commit(next)

func _apply_json() -> void:
    var parsed = JSON.parse_string(json_editor.text)
    if parsed == null:
        status.text = "Invalid JSON. The map was not changed."
        return
    var next := document.duplicate(true)
    if selected_object.is_empty():
        if not parsed is Dictionary:
            status.text = "The map contract must be an object."
            return
        next = parsed
    elif not _set_at(next, selected_object, parsed):
        return
    _commit(next)

func _commit(next: Dictionary) -> void:
    var errors := CONTRACT.validate(next)
    if not errors.is_empty():
        status.text = "Edit rejected: " + "; ".join(errors)
        return
    document_edited.emit(next)
    status.text = "Edited canonical data. Save to publish the map; Undo remains available."

func _rebuild_scene() -> void:
    if world == null or document.is_empty():
        return
    if content != null:
        world.remove_child(content)
        content.free()
    content = Node3D.new()
    world.add_child(content)
    var kit = VISUAL_KIT.new(content, document)
    kit.build()
    handles.clear()
    for collection_path in [["bases"], ["objectives"], ["regions"], ["authoring", "structure_guides"], ["authoring", "scatter_zones"], ["authoring", "terrain", "landforms"], ["authoring", "geometry"], ["authoring", "instances"]]:
        var values = _get_at(document, collection_path)
        if not values is Array:
            continue
        for index in range(values.size()):
            var value = values[index]
            if not value is Dictionary:
                continue
            var path: Array = collection_path.duplicate()
            path.append(index)
            _handle(path, CONTRACT.vec3_from(value.get("position", value.get("center", []))))
    var routes: Array = document.get("routes", [])
    for index in range(routes.size()):
        var points: Array = routes[index].get("points", [])
        for point_index in range(points.size()):
            _handle(["routes", index], CONTRACT.vec3_from(points[point_index]))
    _update_camera()

func _handle(path: Array, position: Vector3) -> void:
    var marker := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = 0.5
    mesh.height = 1.0
    mesh.radial_segments = 8
    mesh.rings = 4
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("ffcc55")
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mesh.material = material
    marker.mesh = mesh
    marker.position = position + Vector3.UP * 0.8
    content.add_child(marker)
    handles.append({"path": path, "position": marker.position})

func frame_map() -> void:
    var bounds: Dictionary = document.get("bounds", {})
    distance = maxf(float(bounds.get("width", 96)), float(bounds.get("depth", 64))) * 1.5
    focus = Vector3.ZERO
    _update_camera()

func _update_camera() -> void:
    if camera == null:
        return
    camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
    camera.look_at(focus, Vector3.UP)

func _viewport_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_RIGHT:
            orbiting = event.pressed
        elif event.button_index == MOUSE_BUTTON_MIDDLE:
            panning = event.pressed
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            distance = maxf(distance * 0.88, 3.0)
            _update_camera()
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            distance *= 1.12
            _update_camera()
        elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
            var pixel: Vector2 = event.position * Vector2(viewport.size) / container.size
            var best := 18.0
            for handle in handles:
                var position: Vector3 = handle["position"]
                if camera.is_position_behind(position):
                    continue
                var delta := camera.unproject_position(position).distance_to(pixel)
                if delta < best:
                    best = delta
                    selected_object = handle["path"]
            _rebuild_tree()
            _show_selection()
    elif event is InputEventMouseMotion and orbiting:
        yaw -= event.relative.x * 0.008
        pitch = clampf(pitch + event.relative.y * 0.008, 0.1, 1.5)
        _update_camera()

    elif event is InputEventMouseMotion and panning:
        focus += (-camera.global_basis.x * event.relative.x + camera.global_basis.y * event.relative.y) * distance * 0.002
        _update_camera()
