@tool
class_name CloseSealMapNavigationRuntime
extends RefCounted

const MAP_CONTRACT = preload("res://src/map/map_contract.gd")

static func compile_route_surface(map_data: Dictionary) -> Dictionary:
    var navigation_cfg: Dictionary = map_data.get("authoring", {}).get("navigation", {})
    var source_result := build_route_source_geometry(map_data, navigation_cfg)
    if not bool(source_result.get("ok", false)):
        return source_result

    var navmesh := NavigationMesh.new()
    _configure_navigation_mesh(navmesh, navigation_cfg)
    var source_geometry: NavigationMeshSourceGeometryData3D = source_result.get("source_geometry")
    NavigationMeshGenerator.bake_from_source_geometry_data(navmesh, source_geometry)

    var baked_polygons := navmesh.get_polygon_count()
    var baked_vertices := navmesh.vertices.size()
    return {
        "ok": baked_polygons > 0 and baked_vertices > 0,
        "navigation_mesh": navmesh,
        "segments": int(source_result.get("segments", 0)),
        "polygons": baked_polygons,
        "vertices": baked_vertices,
        "source_triangles": int(source_result.get("source_triangles", 0)),
        "source_vertices": int(source_result.get("source_vertices", 0)),
        "walkable_area_estimate": float(source_result.get("walkable_area_estimate", 0.0)),
        "route_surfaces": source_result.get("route_surfaces", {}),
        "diagnostics": source_result.get("diagnostics", {}),
        "topology": "godot_recast_bake_from_procedural_triangle_source_geometry",
        "source": "canonical_route_corridors",
        "pipeline": "semantic_routes -> procedural_triangle_faces -> NavigationMeshSourceGeometryData3D -> NavigationMeshGenerator.bake_from_source_geometry_data (Godot 4.7 public API)"
    }

static func build_route_source_geometry(map_data: Dictionary, navigation_cfg: Dictionary = {}) -> Dictionary:
    var faces := PackedVector3Array()
    var segment_count := 0
    var triangle_count := 0
    var total_area := 0.0
    var route_surfaces: Dictionary = {}
    var errors: Array[String] = []
    var warnings: Array[String] = []
    var min_triangle_area := INF
    var min_edge_length := INF
    var cell_size := maxf(float(navigation_cfg.get("cell_size", 0.25)), 0.001)
    var source_depth := maxf(float(navigation_cfg.get("source_depth", 0.25)), 0.01)

    for route_value in map_data.get("routes", []):
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var points: Array = route.get("points", [])
        if points.size() < 2:
            continue
        var width: float = maxf(float(route.get("width", 0.0)), 0.25)
        var route_id := String(route.get("id", "route"))
        var valid_points: Array[Vector3] = []
        for point_value in points:
            var point := MAP_CONTRACT.vec3_from(point_value)
            if not _is_finite_vec3(point):
                errors.append("%s contains a non-finite route point" % route_id)
                continue
            if valid_points.is_empty() or valid_points[-1].distance_to(point) > 0.001:
                valid_points.append(point)
        if valid_points.size() < 2:
            errors.append("%s has fewer than two distinct finite points" % route_id)
            continue

        var left: Array[Vector3] = []
        var right: Array[Vector3] = []
        for i in range(valid_points.size()):
            var center: Vector3 = valid_points[i]
            var tangent := Vector3.ZERO
            if i > 0:
                tangent += (center - valid_points[i - 1]).normalized()
            if i + 1 < valid_points.size():
                tangent += (valid_points[i + 1] - center).normalized()
            tangent.y = 0.0
            if tangent.length_squared() <= 0.000001:
                tangent = Vector3.RIGHT
            tangent = tangent.normalized()
            var side := Vector3(-tangent.z, 0.0, tangent.x) * width * 0.5
            left.append(center - side)
            right.append(center + side)

        var route_segments := 0
        var route_triangles := 0
        var route_area := 0.0
        for i in range(1, valid_points.size()):
            var a: Vector3 = left[i - 1]
            var b: Vector3 = right[i - 1]
            var c: Vector3 = right[i]
            var d: Vector3 = left[i]
            var triangle_a := [a, b, c]
            var triangle_b := [a, c, d]
            for triangle in [triangle_a, triangle_b]:
                var area := _triangle_area(triangle[0], triangle[1], triangle[2])
                min_triangle_area = minf(min_triangle_area, area)
                min_edge_length = minf(min_edge_length, _minimum_triangle_edge(triangle[0], triangle[1], triangle[2]))
                if area <= 0.000001:
                    errors.append("%s segment %d produced a degenerate source triangle" % [route_id, i - 1])
                    continue
                # add_faces() expects clockwise faces. Keep the canonical
                # corridor surface at y, and add only a minimal vertical envelope
                # so Recast receives a finite 3D source volume. The envelope
                # preserves the same walkable top surface and route semantics.
                # A/B: add_faces() reverses vertices 1 and 2 internally.
                # This input order yields an upward Recast normal after that
                # engine-side conversion.
                faces.append(triangle[0])
                faces.append(triangle[2])
                faces.append(triangle[1])
                triangle_count += 1
                route_triangles += 1
            var a2 := a - Vector3(0.0, source_depth, 0.0)
            var b2 := b - Vector3(0.0, source_depth, 0.0)
            var c2 := c - Vector3(0.0, source_depth, 0.0)
            var d2 := d - Vector3(0.0, source_depth, 0.0)
            for side_triangle in [[a, b, b2], [a, b2, a2], [b, c, c2], [b, c2, b2], [c, d, d2], [c, d2, c2], [d, a, a2], [d, a2, d2]]:
                faces.append(side_triangle[0])
                faces.append(side_triangle[1])
                faces.append(side_triangle[2])
                triangle_count += 1
                route_triangles += 1
            var length := valid_points[i - 1].distance_to(valid_points[i])
            route_segments += 1
            segment_count += 1
            route_area += length * width
            total_area += length * width
        route_surfaces[route_id] = {
            "segments": route_segments,
            "source_triangles": route_triangles,
            "centerline_points": valid_points.size(),
            "width": width,
            "area_estimate": route_area
        }

    if min_edge_length < cell_size * 0.5:
        warnings.append("minimum source edge %.4fm is below half the navigation cell size %.4fm" % [min_edge_length, cell_size])

    if not errors.is_empty() or faces.is_empty():
        return {
            "ok": false,
            "error": "route source geometry validation failed",
            "errors": errors,
            "warnings": warnings,
            "diagnostics": {
                "cell_size": cell_size,
                "minimum_triangle_area": 0.0 if min_triangle_area == INF else min_triangle_area,
                "minimum_edge_length": 0.0 if min_edge_length == INF else min_edge_length
            }
        }

    var source_geometry := NavigationMeshSourceGeometryData3D.new()
    source_geometry.add_faces(faces, Transform3D.IDENTITY)
    return {
        "ok": source_geometry.has_data(),
        "source_geometry": source_geometry,
        "segments": segment_count,
        "source_triangles": triangle_count,
        "source_vertices": faces.size(),
        "walkable_area_estimate": total_area,
        "route_surfaces": route_surfaces,
        "diagnostics": {
            "cell_size": cell_size,
            "source_depth": source_depth,
            "minimum_triangle_area": min_triangle_area,
            "minimum_edge_length": min_edge_length,
            "warnings": warnings,
            "errors": errors
        }
    }

static func compile_route_surface_legacy_direct_polygons(map_data: Dictionary) -> Dictionary:
    var vertices := PackedVector3Array()
    var polygons: Array[PackedInt32Array] = []
    var segment_count := 0
    var total_area := 0.0
    var route_surfaces: Dictionary = {}
    for route_value in map_data.get("routes", []):
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var points: Array = route.get("points", [])
        if points.size() < 2:
            continue
        var width: float = maxf(float(route.get("width", 0.0)), 0.25)
        var route_id := String(route.get("id", "route"))
        var valid_points: Array[Vector3] = []
        for point_value in points:
            var point := MAP_CONTRACT.vec3_from(point_value)
            if valid_points.is_empty() or valid_points[-1].distance_to(point) > 0.001:
                valid_points.append(point)
        if valid_points.size() < 2:
            continue

        var route_vertex_start := vertices.size()
        for i in range(valid_points.size()):
            var center: Vector3 = valid_points[i]
            var tangent := Vector3.ZERO
            if i > 0:
                tangent += (center - valid_points[i - 1]).normalized()
            if i + 1 < valid_points.size():
                tangent += (valid_points[i + 1] - center).normalized()
            tangent.y = 0.0
            if tangent.length_squared() <= 0.000001:
                tangent = Vector3.RIGHT
            tangent = tangent.normalized()
            var side := Vector3(-tangent.z, 0.0, tangent.x) * width * 0.5
            vertices.append(center - side)
            vertices.append(center + side)

        var route_segments := 0
        var route_area := 0.0
        for i in range(1, valid_points.size()):
            var previous_pair := route_vertex_start + (i - 1) * 2
            var current_pair := route_vertex_start + i * 2
            polygons.append(PackedInt32Array([
                previous_pair,
                previous_pair + 1,
                current_pair + 1,
                current_pair
            ]))
            var length := valid_points[i - 1].distance_to(valid_points[i])
            route_segments += 1
            segment_count += 1
            route_area += length * width
            total_area += length * width
        route_surfaces[route_id] = {
            "segments": route_segments,
            "vertices": valid_points.size() * 2,
            "width": width,
            "area_estimate": route_area
        }

    var navmesh := NavigationMesh.new()
    navmesh.vertices = vertices
    for polygon in polygons:
        navmesh.add_polygon(polygon)
    return {
        "ok": segment_count > 0,
        "navigation_mesh": navmesh,
        "segments": segment_count,
        "polygons": polygons.size(),
        "vertices": vertices.size(),
        "walkable_area_estimate": total_area,
        "route_surfaces": route_surfaces,
        "topology": "legacy_continuous_shared_vertices_per_route",
        "source": "canonical_route_corridors",
        "claim_boundary": "Diagnostic legacy path retained because it produced an observed physical-query failure in Godot 4.7.2 CI."
    }

static func _configure_navigation_mesh(navmesh: NavigationMesh, navigation_cfg: Dictionary) -> void:
    navmesh.set_agent_radius(maxf(float(navigation_cfg.get("agent_radius", 0.45)), 0.01))
    navmesh.set_agent_height(maxf(float(navigation_cfg.get("agent_height", 1.8)), 0.1))
    navmesh.set_agent_max_climb(maxf(float(navigation_cfg.get("agent_max_climb", 0.45)), 0.0))
    navmesh.set_agent_max_slope(clampf(float(navigation_cfg.get("agent_max_slope", 45.0)), 0.0, 90.0))
    navmesh.set_cell_size(maxf(float(navigation_cfg.get("cell_size", 0.25)), 0.01))
    navmesh.set_cell_height(maxf(float(navigation_cfg.get("cell_height", 0.25)), 0.01))

static func _is_finite_vec3(value: Vector3) -> bool:
    return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

static func _triangle_area(a: Vector3, b: Vector3, c: Vector3) -> float:
    return (b - a).cross(c - a).length() * 0.5

static func _minimum_triangle_edge(a: Vector3, b: Vector3, c: Vector3) -> float:
    return minf(a.distance_to(b), minf(b.distance_to(c), c.distance_to(a)))

static func route_graph(map_data: Dictionary) -> Dictionary:
    var graph: Dictionary = {}
    for route_value in map_data.get("routes", []):
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var points: Array = route.get("points", [])
        var length := 0.0
        for i in range(1, points.size()):
            length += MAP_CONTRACT.vec3_from(points[i - 1]).distance_to(MAP_CONTRACT.vec3_from(points[i]))
        graph[String(route.get("id", "route"))] = {
            "kind": String(route.get("kind", "unknown")),
            "length": length,
            "width": float(route.get("width", 0.0)),
            "points": points.size()
        }
    return graph

static func simulate_army_flow(map_data: Dictionary, army_sizes: Array[int] = [10, 50, 100, 500], unit_diameter: float = 0.9, spacing: float = 0.25) -> Dictionary:
    var routes: Array = map_data.get("routes", [])
    var results: Dictionary = {}
    var footprint := maxf(unit_diameter + spacing, 0.1)
    for route_value in routes:
        if typeof(route_value) != TYPE_DICTIONARY:
            continue
        var route: Dictionary = route_value
        var route_id := String(route.get("id", "route"))
        var width := maxf(float(route.get("width", 0.0)), 0.1)
        var columns := maxi(1, int(floor(width / footprint)))
        var per_army: Dictionary = {}
        for army_size in army_sizes:
            var rows := int(ceil(float(army_size) / float(columns)))
            var depth := float(rows) * footprint
            var pressure := float(army_size) / float(columns)
            per_army[str(army_size)] = {
                "columns": columns,
                "rows": rows,
                "queue_depth_m": depth,
                "pressure_index": pressure,
                "classification": _pressure_class(pressure)
            }
        results[route_id] = per_army
    return {
        "unit_diameter": unit_diameter,
        "spacing": spacing,
        "routes": results,
        "model": "geometric corridor capacity; not agent runtime performance"
    }

static func _pressure_class(value: float) -> String:
    if value <= 4.0:
        return "free"
    if value <= 12.0:
        return "loaded"
    if value <= 30.0:
        return "congested"
    return "saturated"

static func format_simulation_report(map_data: Dictionary) -> String:
    var compiled := compile_route_surface(map_data)
    var flow := simulate_army_flow(map_data)
    var lines: Array[String] = [
        "[b]Compiled Navigation Surface[/b]",
        "Source: canonical route corridors",
        "Topology: %s" % String(compiled.get("topology", "unknown")),
        "Segments: %d • baked polygons: %d • baked vertices: %d" % [int(compiled.get("segments", 0)), int(compiled.get("polygons", 0)), int(compiled.get("vertices", 0))],
        "Source triangles: %d • source vertices: %d" % [int(compiled.get("source_triangles", 0)), int(compiled.get("source_vertices", 0))],
        "Walkable corridor area estimate: %.1f m²" % float(compiled.get("walkable_area_estimate", 0.0)),
        "",
        "[b]Army Flow Model[/b]"
    ]
    var routes: Dictionary = flow.get("routes", {})
    for route_id in routes.keys():
        lines.append("[b]%s[/b]" % String(route_id))
        var armies: Dictionary = routes[route_id]
        for size in [10, 50, 100, 500]:
            var state: Dictionary = armies.get(str(size), {})
            lines.append("  %3d units → %d columns • %d rows • %.1fm queue • %s" % [size, int(state.get("columns", 0)), int(state.get("rows", 0)), float(state.get("queue_depth_m", 0.0)), String(state.get("classification", "unknown"))])
    lines.append("")
    lines.append("[color=gray]Navigation topology is produced by Godot/Recast from procedural source triangles. Army capacity remains geometric until executable avoidance-agent probes pass.[/color]")
    return "\n".join(lines)
