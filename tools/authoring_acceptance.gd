extends RefCounted
## Acceptance checks and an explicit procedural sound, executed through the
## general bridge's project-script extension. This is not a map generator.

func run(context, arguments: Dictionary) -> Dictionary:
    if arguments.get("stage") == "audio":
        var pcm := PackedByteArray()
        var samples := 22050
        pcm.resize(samples * 2)
        var energy := 0.0
        for i in range(samples):
            var time := float(i) / samples
            var fade := minf(time * 12.0, (1.0 - time) * 12.0)
            var sample := (sin(TAU * 110.0 * time) * 0.16 + sin(TAU * 220.0 * time) * 0.04) * clampf(fade, 0, 1)
            energy += sample * sample
            pcm.encode_s16(i * 2, int(sample * 32767))
        var stream := AudioStreamWAV.new()
        stream.format = AudioStreamWAV.FORMAT_16_BITS
        stream.mix_rate = samples
        stream.stereo = false
        stream.data = pcm
        stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
        stream.loop_begin = 0
        stream.loop_end = samples
        context.register("ambience_stream", stream)
        var path: String = context.output_path("audio/industrial_hum.wav")
        var error := stream.save_to_wav(path)
        return {"ok": error == OK, "sample_rate": samples, "samples": samples, "rms": sqrt(energy / samples), "wav": path}

    var world: Node3D = context.object("city")
    var scatter = context.object("scatter")
    if scatter.transforms == null or scatter.transforms.size() != 24:
        return {"ok": false, "error": "ProtonScatter did not create the requested 24 transforms"}
    var output: Node = scatter.output_root
    var multimeshes: Array = []
    _multimeshes(output, multimeshes)
    var instance_count := 0
    for node in multimeshes:
        instance_count += node.multimesh.instance_count
    if instance_count != 24:
        return {"ok": false, "error": "ProtonScatter rendered instance count differs"}

    var region: NavigationRegion3D = context.object("navigation")
    region.bake_navigation_mesh(false)
    var rid := region.get_navigation_map()
    NavigationServer3D.map_force_update(rid)
    for _attempt in range(20):
        await context.physics_frame
    var start := NavigationServer3D.map_get_closest_point(rid, Vector3(-10, 0.15, 8))
    var finish := NavigationServer3D.map_get_closest_point(rid, Vector3(10, 0.15, 8))
    var route := NavigationServer3D.map_get_path(rid, start, finish, true)
    if region.navigation_mesh.get_polygon_count() == 0 or route.size() < 2 or start.distance_to(finish) < 18:
        return {"ok": false, "error": "actual scene geometry navigation test failed"}

    var direct := world.get_world_3d().direct_space_state
    var hit := direct.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 4, 8), Vector3(0, -2, 8)))
    if hit.is_empty():
        return {"ok": false, "error": "saved geometry has no ground collision"}
    var actor := CharacterBody3D.new()
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.35
    capsule.height = 1.8
    shape.shape = capsule
    shape.position.y = 0.9
    actor.add_child(shape)
    actor.position = Vector3(-10, 0.6, 8)
    world.add_child(actor)
    for _frame in range(50):
        await context.physics_frame
        actor.velocity = Vector3(0, -3, 0)
        actor.move_and_slide()
    if not actor.is_on_floor():
        actor.free()
        return {"ok": false, "error": "capsule does not stand on the authored ground"}
    var origin := actor.position
    for _frame in range(60):
        await context.physics_frame
        actor.velocity = Vector3(4, -3, 0)
        actor.move_and_slide()
    var walked := actor.position.distance_to(origin)
    actor.free()
    if walked < 3.5:
        return {"ok": false, "error": "capsule movement failed"}
    var stream: AudioStreamWAV = context.object("ambience_stream")
    var audio: AudioStreamPlayer3D = context.object("sound")
    audio.play()
    await context.process_frame
    if not audio.playing or stream.data.size() != 44100:
        return {"ok": false, "error": "authored spatial audio cannot start"}

    # Determinism is checked through the actual pinned provider, not a stand-in.
    var original: Array = scatter.transforms.list.duplicate()
    scatter.full_rebuild()
    for _frame in range(10): await context.process_frame
    if scatter.transforms.list != original:
        return {"ok": false, "error": "scatter seed failed deterministic rebuild"}
    var result := {"ok": true, "provider": "ProtonScatter", "transforms": scatter.transforms.size(),
                   "rendered_instances": instance_count, "deterministic_rebuild": true,
                   "navigation_polygons": region.navigation_mesh.get_polygon_count(),
                   "path_points": route.size(), "capsule_walked_m": walked, "spatial_audio_playing": audio.playing,
                   "sound_seconds": stream.get_length(), "audio_limit": "source PCM verified; speaker/room acoustics unmeasured"}
    # Reopen the bundle scene in a fresh tree, then verify resources, collider
    # and cached provider output instead of trusting PackedScene.pack alone.
    if arguments.get("stage") == "reopen":
        var packed: PackedScene = ResourceLoader.load(context.output_path("scenes/urban_workbench.tscn"), "", ResourceLoader.CACHE_MODE_IGNORE)
        if packed == null: return {"ok": false, "error": "saved scene cannot reopen"}
        var reopened: Node3D = packed.instantiate()
        context.root.add_child(reopened)
        await context.physics_frame
        await context.physics_frame
        var fresh_scatter = reopened.get_node("Navigation/PocketTrees")
        var fresh_output: Array = []
        _multimeshes(fresh_scatter.get_node("ScatterOutput"), fresh_output)
        var reopened_count := 0
        for node in fresh_output: reopened_count += node.multimesh.instance_count
        var fresh_audio: AudioStreamPlayer3D = reopened.get_node("Navigation/IndustrialHum")
        var reopened_ray := reopened.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 4, 8), Vector3(0, -2, 8)))
        var ground: MeshInstance3D = reopened.get_node("Navigation/Ground")
        if reopened_count != 24 or fresh_audio.stream == null or fresh_audio.stream.data.size() != 44100 or reopened_ray.is_empty() or ground.material_override == null:
            reopened.free()
            return {"ok": false, "error": "save/reopen lost scatter, sound, material or collision"}
        result["reopened_instances"] = reopened_count
        result["reopened_audio_bytes"] = fresh_audio.stream.data.size()
        result["reopened_material_roughness"] = ground.material_override.roughness
        reopened.free()
    return result

func _multimeshes(node: Node, result: Array) -> void:
    if node is MultiMeshInstance3D: result.append(node)
    for child in node.get_children(): _multimeshes(child, result)
