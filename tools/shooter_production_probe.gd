extends RefCounted
## Game-owned native adapter for ARCONT production profiles. No canonical map edits.

func failure(message: String) -> Dictionary: return {"ok": false, "error": message}

func measured_device() -> String:
	return OS.get_processor_name() + " / " + RenderingServer.get_video_adapter_vendor() + " / " + RenderingServer.get_video_adapter_name()

func write_json(context, path: String, value: Dictionary) -> void:
	var file := FileAccess.open(context.output_path(path), FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  "))

func world(context) -> Node3D:
	context.root.size = Vector2i(1280, 720)
	var scene: Node3D = context.object("review_root")
	scene.name = "ProductionReview"
	context.register("production_world", scene)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.5
	scene.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("253744")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b9cbdf")
	environment.environment.ambient_light_energy = 0.65
	scene.add_child(environment)
	var camera := Camera3D.new()
	camera.name = "ReviewCamera"
	scene.add_child(camera)
	camera.position = Vector3(7, 6, 9)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.current = true
	context.register("production_camera", camera)
	return scene

func geometry(node: Node3D, relative: Transform3D, result: Dictionary) -> void:
	var transform := relative * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var bounds: AABB = transform * node.get_aabb()
		result.bounds = bounds if not result.has("bounds") else result.bounds.merge(bounds)
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var indices = arrays[Mesh.ARRAY_INDEX]
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			result.triangles += (indices.size() if indices != null and indices.size() > 0 else vertices.size()) / 3
	for child in node.get_children():
		if child is Node3D: geometry(child, transform, result)

func asset_review(context, arguments: Dictionary) -> Dictionary:
	var bundle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arguments.bundle))
	var scene := world(context)
	var measurements: Array = []
	var index := 0
	for asset in bundle.assets:
		var path: String = arguments.bundle.get_base_dir().path_join(asset.inspection.path)
		var packed = load(path)
		if not packed is PackedScene: return failure("candidate model did not import: " + path)
		var model: Node3D = packed.instantiate()
		# Pack the review as a native snapshot, without inherited imported scene nodes.
		model.scene_file_path = ""
		scene.add_child(model)
		var measured := {"triangles": 0}
		geometry(model, Transform3D.IDENTITY, measured)
		if not measured.has("bounds") or measured.triangles <= 0:
			return failure("candidate contains no rendered geometry")
		if measured.triangles > asset.budget.triangles_max or measured.triangles != asset.inspection.triangles:
			return failure("native geometry differs from the accepted budget: " + asset.id)
		var size: Vector3 = measured.bounds.size
		var extent: float = maxf(size.x, maxf(size.y, size.z))
		var profile: Dictionary = asset.engine_profile
		if extent < float(profile.get("extent_min_m", 0.01)) or extent > float(profile.get("extent_max_m", 100)):
			return failure("candidate extent violates profile: " + asset.id)
		if asset.inspection.skins > 0 and model.find_child("Skeleton3D", true, false) == null:
			return failure("import lost character skeleton")
		measurements.append({"id": asset.id, "native_triangles": measured.triangles, "extent_m": extent,
			"bounds_size": [size.x, size.y, size.z], "loaded_from_bundle": true})
		model.position.x = (index - 1) * 2.2
		if asset.id == "weapon.akm": model.position.y = 0.8
		index += 1
	var display := StandardMaterial3D.new()
	display.albedo_color = Color("65717a")
	display.roughness = 0.85
	box(scene, "DisplayFloor", Vector3(0, -0.1, 0), Vector3(8, 0.2, 4), display)
	var camera: Camera3D = context.object("production_camera")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.2
	camera.position = Vector3(4, 2.8, 6)
	camera.look_at(Vector3(0, 0.8, 0))
	var result := {"ok": true, "device": measured_device(), "assets": measurements, "bundle_sha256": bundle.bundle_sha256,
		"limits": ["native import and rendered review; no mobile performance claim"]}
	write_json(context, "asset-review.json", result)
	return result

func retarget(source: Skeleton3D, target: Skeleton3D, library: AnimationLibrary, profile: Dictionary) -> Dictionary:
	var mapping: Dictionary = profile.bone_map
	for name_ in mapping:
		var source_index := source.find_bone(name_)
		var target_index := target.find_bone(mapping[name_])
		if source_index < 0 or target_index < 0: return failure("mapped bone is missing: " + name_)
		var parent := source.get_bone_parent(source_index)
		var target_parent := target.get_bone_parent(target_index)
		if parent >= 0:
			var source_parent := source.get_bone_name(parent)
			if not mapping.has(source_parent) or target_parent < 0 or target.get_bone_name(target_parent) != mapping[source_parent]:
				return failure("retarget requires matching parent topology")
		elif target_parent >= 0: return failure("retarget root topology differs")
	var output := AnimationLibrary.new()
	var total_keys := 0
	for clip in profile.clips:
		if not library.has_animation(clip): return failure("source clip missing: " + clip)
		var animation: Animation = library.get_animation(clip).duplicate(true)
		for track in animation.get_track_count():
			var node_path: NodePath = animation.track_get_path(track)
			if node_path.get_subname_count() != 1: return failure("only skeletal tracks are supported")
			var bone := String(node_path.get_subname(0))
			if not mapping.has(bone): return failure("animated bone has no mapping: " + bone)
			var source_rest := source.get_bone_rest(source.find_bone(bone))
			var target_rest := target.get_bone_rest(target.find_bone(mapping[bone]))
			var correction := target_rest.basis.get_rotation_quaternion() * source_rest.basis.get_rotation_quaternion().inverse()
			animation.track_set_path(track, NodePath(String(profile.target_skeleton_path) + ":" + String(mapping[bone])))
			for key in animation.track_get_key_count(track):
				var value = animation.track_get_key_value(track, key)
				match animation.track_get_type(track):
					Animation.TYPE_POSITION_3D:
						value = target_rest.origin + correction * ((value - source_rest.origin) * float(profile.translation_scale))
					Animation.TYPE_ROTATION_3D: value = (correction * value).normalized()
					_: return failure("unsupported animated track type")
				animation.track_set_key_value(track, key, value)
				total_keys += 1
		output.add_animation(clip, animation)
	return {"ok": true, "library": output, "keys": total_keys}

func rotation_error(a: Quaternion, b: Quaternion) -> float:
	# atan2 avoids acos(dot) precision loss near identical single-precision poses.
	var relative := (a.normalized().inverse() * b.normalized()).normalized()
	return 2.0 * atan2(Vector3(relative.x, relative.y, relative.z).length(), absf(relative.w))

func animation_review(context, profile: Dictionary) -> Dictionary:
	var packed: PackedScene = load(profile.source_model)
	var model: Node3D = packed.instantiate()
	var source: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var target_model: Node3D = load(profile.target_model).instantiate()
	var target: Skeleton3D = target_model.find_child("Skeleton3D", true, false)
	var library: AnimationLibrary = load(profile.source_library)
	var converted := retarget(source, target, library, profile)
	if not converted.ok:
		model.free(); target_model.free()
		return converted
	var output: AnimationLibrary = converted.library
	var destination: String = context.output_path("retargeted-motion.res")
	if ResourceSaver.save(output, destination, ResourceSaver.FLAG_COMPRESS) != OK:
		model.free(); target_model.free(); return failure("retargeted library save failed")
	var reopened: AnimationLibrary = ResourceLoader.load(destination, "", ResourceLoader.CACHE_MODE_IGNORE)
	reopened.take_over_path(ProjectSettings.localize_path(destination))
	var max_error := 0.0
	for clip in profile.clips:
		var a: Animation = library.get_animation(clip)
		var b: Animation = reopened.get_animation(clip)
		if absf(a.length - b.length) > 0.000001 or a.loop_mode != b.loop_mode:
			model.free(); target_model.free(); return failure("retarget changed animation timing")
		for track in a.get_track_count():
			for key in a.track_get_key_count(track):
				var old_value = a.track_get_key_value(track, key)
				var new_value = b.track_get_key_value(track, key)
				if old_value is Vector3: max_error = maxf(max_error, old_value.distance_to(new_value))
				elif old_value is Quaternion: max_error = maxf(max_error, rotation_error(old_value, new_value))
	# Identity rest-map is the Nexo baseline; different proportions require review.
	if profile.get("identity_baseline", false) and max_error > 0.001:
		model.free(); target_model.free(); return failure("identity retarget altered accepted poses: " + str(max_error))
	var missing := profile.duplicate(true)
	missing.bone_map.erase("hips")
	var missing_rejected: bool = not retarget(source, target, library, missing).ok
	# Native renamed/different-rest fixture exercises mapping and rest correction.
	var fixture: Skeleton3D = target.duplicate()
	var fixture_profile := profile.duplicate(true)
	fixture_profile.target_skeleton_path = "RetargetFixture"
	for bone in fixture.get_bone_count():
		var name_ := fixture.get_bone_name(bone)
		fixture.set_bone_name(bone, "mapped_" + name_)
		fixture_profile.bone_map[name_] = "mapped_" + name_
		var rest := fixture.get_bone_rest(bone)
		rest.basis = Basis(Vector3.UP, 0.1) * rest.basis
		rest.origin += Vector3(0.03, 0.04, 0.05)
		fixture.set_bone_rest(bone, rest)
	var fixture_result := retarget(source, fixture, library, fixture_profile)
	var fixture_passed: bool = fixture_result.ok
	if fixture_passed:
		var original: Animation = library.get_animation(profile.clips[0])
		var changed: Animation = fixture_result.library.get_animation(profile.clips[0])
		var old_q: Quaternion = original.track_get_key_value(1, 0)
		var new_q: Quaternion = changed.track_get_key_value(1, 0)
		fixture_passed = rotation_error(new_q, (Quaternion(Vector3.UP, 0.1) * old_q).normalized()) < 0.001 and String(changed.track_get_path(1)).contains("mapped_")
		var position_bone := String(original.track_get_path(0).get_subname(0))
		var source_origin := source.get_bone_rest(source.find_bone(position_bone)).origin
		var target_origin := fixture.get_bone_rest(fixture.find_bone("mapped_" + position_bone)).origin
		var old_position: Vector3 = original.track_get_key_value(0, 0)
		var new_position: Vector3 = changed.track_get_key_value(0, 0)
		fixture_passed = fixture_passed and new_position.distance_to(target_origin + Quaternion(Vector3.UP, 0.1) * (old_position - source_origin)) < 0.001
	fixture.free()
	model.free()
	if not missing_rejected or not fixture_passed:
		target_model.free(); return failure("retarget negative/rest-space acceptance failed")
	var scene := world(context)
	target_model.scene_file_path = ""
	scene.add_child(target_model)
	var player := AnimationPlayer.new()
	target_model.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("", reopened)
	player.play("cover_idle")
	player.advance(0.3)
	var camera: Camera3D = context.object("production_camera")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	camera.position = Vector3(1.8, 1.6, 4)
	camera.look_at(Vector3(0, 0.75, 0))
	var result := {"ok": true, "device": measured_device(), "clips": profile.clips.size(), "keys": converted.keys,
		"identity_pose_error": max_error, "missing_mapping_rejected": missing_rejected,
		"renamed_rest_fixture": fixture_passed, "library": destination,
		"limits": ["explicit matching bone topology; no automatic humanoid inference",
			"different proportions require new contact/visual acceptance; no motion-capture claim"]}
	write_json(context, "animation-review.json", result)
	return result

func box(scene: Node3D, name_: String, point: Vector3, size: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = name_
	body.position = point
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.material_override = material
	body.add_child(mesh)
	scene.add_child(body)

func sector_review(context, recipe: Dictionary) -> Dictionary:
	var scene := world(context)
	var ground: Material = load("res://assets/shooter/serious/materials/asphalt.tres")
	var concrete: Material = load("res://assets/shooter/serious/materials/concrete.tres")
	box(scene, "Floor", Vector3(0, -0.15, 0), Vector3(recipe.floor.size[0], 0.3, recipe.floor.size[1]), ground)
	for cover in recipe.covers:
		box(scene, cover.id, Vector3(cover.position[0], cover.size[1] * 0.5, cover.position[1]), Vector3(cover.size[0], cover.size[1], cover.size[2]), concrete)
	var navigation := NavigationMesh.new()
	navigation.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation.geometry_collision_mask = 1
	navigation.agent_radius = 0.45
	navigation.agent_height = 1.9
	navigation.cell_size = 0.15
	navigation.cell_height = 0.1
	navigation.agent_max_climb = 0.2
	await context.physics_frame
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navigation, source, scene)
	NavigationServer3D.bake_from_source_geometry_data(navigation, source)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = navigation
	scene.add_child(region)
	var map: RID = region.get_navigation_map()
	NavigationServer3D.map_set_active(map, true)
	await context.physics_frame
	await context.physics_frame
	await context.process_frame
	NavigationServer3D.map_force_update(map)
	# The server publishes baked map iterations asynchronously.
	for _attempt in range(30):
		await context.physics_frame
		await context.process_frame
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return failure("navigation map did not publish a baked iteration")
	var route_results: Array = []
	for route in recipe.routes:
		var mover := CharacterBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = CapsuleShape3D.new()
		shape.shape.radius = 0.33
		shape.shape.height = 1.85
		shape.position.y = 0.925
		mover.add_child(shape)
		scene.add_child(mover)
		mover.position = Vector3(route.points[0][0], 0.03, route.points[0][1])
		var blocked := false
		for index in range(1, route.points.size()):
			var next := Vector3(route.points[index][0], 0.03, route.points[index][1])
			var delta: Vector3 = next - mover.position
			if mover.test_move(mover.global_transform, delta): blocked = true
			else: mover.position = next
		var start := Vector3(route.points[0][0], 0, route.points[0][1])
		var last: Array = route.points[-1]
		var end := Vector3(last[0], 0, last[1])
		var path := NavigationServer3D.map_get_path(map, start, end, true)
		var reachable: bool = not path.is_empty() and path[-1].distance_to(end) < 0.5
		route_results.append({"id": route.id, "capsule_clear": not blocked, "navigation_reachable": reachable})
		mover.free()
		if blocked or not reachable:
			return failure("native sector route failed: %s; blocked=%s path_points=%s polygons=%s active=%s regions=%s nearest=%s" % [route.id, blocked, path.size(), navigation.get_polygon_count(), NavigationServer3D.map_is_active(map), NavigationServer3D.map_get_regions(map).size(), NavigationServer3D.map_get_closest_point(map, start)])
	var checks: Array = []
	for cover in recipe.covers:
		var from := Vector3(cover.position[0], 0.5, cover.position[1] + 2)
		var to := Vector3(cover.position[0], 0.5, cover.position[1] - 2)
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or String(hit.collider.name) != String(cover.id):
			return failure("cover collision missing: " + cover.id)
		checks.append(cover.id)
	var camera: Camera3D = context.object("production_camera")
	var colors := [Color("4fc6fa"), Color("f6b951"), Color("79df9c")]
	for index in recipe.routes.size():
		var route: Dictionary = recipe.routes[index]
		for segment in range(1, route.points.size()):
			var start := Vector3(route.points[segment - 1][0], 0.03, route.points[segment - 1][1])
			var end := Vector3(route.points[segment][0], 0.03, route.points[segment][1])
			var marker := MeshInstance3D.new()
			marker.name = "Route_" + String(route.id) + "_" + str(segment)
			marker.mesh = BoxMesh.new()
			marker.mesh.size = Vector3(0.12, 0.025, start.distance_to(end))
			var material := StandardMaterial3D.new()
			material.albedo_color = colors[index % colors.size()]
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			marker.material_override = material
			scene.add_child(marker)
			marker.position = (start + end) * 0.5
			marker.rotation.y = atan2(end.x - start.x, end.z - start.z)
	camera.position = Vector3(17, 18, 22)
	camera.look_at(Vector3.ZERO)
	var result := {"ok": true, "device": measured_device(), "routes": route_results, "cover_colliders": checks, "navigation_polygons": navigation.get_polygon_count(),
		"limits": ["separate editable sector recipe; canonical Nexo map unchanged",
			"capsule sweeps and navigation; production input controller tested by existing shooter replay"]}
	write_json(context, "sector-review.json", result)
	return result

func run(context, arguments: Dictionary) -> Dictionary:
	match String(arguments.operation):
		"assets": return await asset_review(context, arguments)
		"animation": return await animation_review(context, arguments.profile)
		"sector": return await sector_review(context, arguments.recipe)
	return failure("unknown production review operation")
