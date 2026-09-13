@tool
extends Control

signal selection_changed(id: String, kind: String)

var map_data: Dictionary = {}
var zoom := 1.0
var pan := Vector2.ZERO
var _dragging := false
var _drag_origin := Vector2.ZERO
var _pan_origin := Vector2.ZERO
var _features: Array[Dictionary] = []

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    custom_minimum_size = Vector2(320, 280)
    clip_contents = true

func set_map_data(value: Dictionary) -> void:
    map_data = value
    zoom = 1.0
    pan = Vector2.ZERO
    queue_redraw()

func frame_map() -> void:
    zoom = 1.0
    pan = Vector2.ZERO
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.025, 0.04, 1.0), true)
    draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), Color(0.12, 0.25, 0.34, 0.55), false, 1.0)
    _features.clear()
    if map_data.is_empty():
        _draw_center_text("No map loaded")
        return

    var bounds: Dictionary = map_data.get("bounds", {})
    var width := max(float(bounds.get("width", 1.0)), 1.0)
    var depth := max(float(bounds.get("depth", 1.0)), 1.0)
    var top_left := _world_to_canvas(Vector3(-width * 0.5, 0.0, -depth * 0.5))
    var bottom_right := _world_to_canvas(Vector3(width * 0.5, 0.0, depth * 0.5))
    draw_rect(Rect2(top_left, bottom_right - top_left), Color(0.035, 0.07, 0.08, 0.8), true)
    draw_rect(Rect2(top_left, bottom_right - top_left), Color(0.45, 0.67, 0.73, 0.7), false, 2.0)

    _draw_regions()
    _draw_routes()
    _draw_objectives()
    _draw_bases()
    _draw_legend()

func _draw_regions() -> void:
    for value in map_data.get("regions", []):
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var region: Dictionary = value
        var center := CloseSealMapContract.vec3_from(region.get("center", []))
        var p := _world_to_canvas(center)
        var kind := String(region.get("kind", "region"))
        var color := Color(0.2, 0.65, 0.95, 0.18)
        if kind == "choke":
            color = Color(1.0, 0.62, 0.18, 0.23)
        var size_value = region.get("size", [float(region.get("width", 4.0)), 0.0, float(region.get("width", 4.0))])
        var world_size := CloseSealMapContract.vec3_from(size_value, Vector3(4, 0, 4))
        var px := _world_scale()
        var rect_size := Vector2(max(world_size.x, float(region.get("width", 0.0))), max(world_size.z, float(region.get("width", 0.0)))) * px
        var rect := Rect2(p - rect_size * 0.5, rect_size)
        draw_rect(rect, color, true)
        draw_rect(rect, Color(color.r, color.g, color.b, 0.8), false, 1.0)
        _features.append({"id": String(region.get("id", "region")), "kind": kind, "position": p})

func _draw_routes() -> void:
    for value in map_data.get("routes", []):
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = value
        var points: PackedVector2Array = []
        for point in route.get("points", []):
            points.append(_world_to_canvas(CloseSealMapContract.vec3_from(point)))
        if points.size() < 2:
            continue
        var kind := String(route.get("kind", "primary"))
        var color := Color(0.35, 0.8, 1.0, 0.9) if kind == "primary" else Color(0.35, 0.75, 0.5, 0.8)
        var thickness := clamp(float(route.get("width", 4.0)) * _world_scale() * 0.20, 2.0, 8.0)
        draw_polyline(points, Color(0.0, 0.0, 0.0, 0.65), thickness + 3.0, true)
        draw_polyline(points, color, thickness, true)
        for p in points:
            draw_circle(p, 3.0, color)
        _features.append({"id": String(route.get("id", "route")), "kind": kind, "position": points[int(points.size() / 2)]})

func _draw_objectives() -> void:
    for value in map_data.get("objectives", []):
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var objective: Dictionary = value
        var p := _world_to_canvas(CloseSealMapContract.vec3_from(objective.get("position", [])))
        var radius := max(float(objective.get("radius", 1.0)) * _world_scale(), 7.0)
        draw_circle(p, radius, Color(0.7, 0.25, 1.0, 0.20))
        draw_arc(p, radius, 0.0, TAU, 40, Color(0.85, 0.55, 1.0, 0.95), 2.0, true)
        draw_circle(p, 4.0, Color(0.95, 0.85, 1.0, 1.0))
        _features.append({"id": String(objective.get("id", "objective")), "kind": "objective", "position": p})

func _draw_bases() -> void:
    for value in map_data.get("bases", []):
        if typeof(value) != TYPE_DICTIONARY:
            continue
        var base: Dictionary = value
        var p := _world_to_canvas(CloseSealMapContract.vec3_from(base.get("position", [])))
        var team := String(base.get("team", "neutral"))
        var color := Color(0.15, 0.6, 1.0, 1.0) if team == "blue" else Color(1.0, 0.22, 0.18, 1.0)
        draw_circle(p, 12.0, Color(color.r, color.g, color.b, 0.25))
        draw_arc(p, 12.0, 0.0, TAU, 24, color, 3.0, true)
        draw_circle(p, 5.0, color)
        _features.append({"id": String(base.get("id", "base")), "kind": "base", "position": p})
        if base.has("hero_spawn"):
            var spawn := _world_to_canvas(CloseSealMapContract.vec3_from(base.get("hero_spawn", [])))
            draw_circle(spawn, 5.0, Color(color.r, color.g, color.b, 0.35))
            draw_arc(spawn, 5.0, 0.0, TAU, 18, color, 1.5, true)
            _features.append({"id": String(base.get("id", "base")) + ":hero_spawn", "kind": "spawn", "position": spawn})

func _draw_legend() -> void:
    var font := ThemeDB.fallback_font
    draw_string(font, Vector2(10, 20), "MAP FORGE • tactical topology", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.78, 0.9, 1.0))
    draw_string(font, Vector2(10, size.y - 10), "Wheel: zoom  •  RMB/MMB: pan  •  LMB: select", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.66, 0.72))

func _draw_center_text(text: String) -> void:
    var font := ThemeDB.fallback_font
    var width := font.get_string_size(text).x
    draw_string(font, Vector2((size.x - width) * 0.5, size.y * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.7, 0.75))

func _world_scale() -> float:
    var bounds: Dictionary = map_data.get("bounds", {})
    var width := max(float(bounds.get("width", 1.0)), 1.0)
    var depth := max(float(bounds.get("depth", 1.0)), 1.0)
    var fit := min(max(size.x - 30.0, 1.0) / width, max(size.y - 50.0, 1.0) / depth)
    return fit * zoom

func _world_to_canvas(world: Vector3) -> Vector2:
    var scale := _world_scale()
    return Vector2(size.x * 0.5, size.y * 0.5) + pan + Vector2(world.x, world.z) * scale

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            zoom = clamp(zoom * 1.12, 0.5, 3.0)
            queue_redraw()
            accept_event()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            zoom = clamp(zoom / 1.12, 0.5, 3.0)
            queue_redraw()
            accept_event()
        elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
            _dragging = event.pressed
            if _dragging:
                _drag_origin = event.position
                _pan_origin = pan
            accept_event()
        elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            _select_at(event.position)
            accept_event()
    elif event is InputEventMouseMotion and _dragging:
        pan = _pan_origin + event.position - _drag_origin
        queue_redraw()
        accept_event()

func _select_at(point: Vector2) -> void:
    var best_distance := 28.0
    var best: Dictionary = {}
    for feature in _features:
        var distance := point.distance_to(feature.position)
        if distance < best_distance:
            best_distance = distance
            best = feature
    if not best.is_empty():
        selection_changed.emit(String(best.id), String(best.kind))
