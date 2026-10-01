extends SceneTree
const EXPLORER = preload("res://src/urban/urban_explorer.gd")

func _initialize() -> void:
    _run.call_deferred()

func _fail(message: String) -> void:
    push_error("URBAN_NEXO: " + message)
    quit(1)

func _run() -> void:
    var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/urban_nexo_01.json"))
    var packed: PackedScene = load("res://maps/generated/urban_nexo_01_authoring.tscn")
    var world: Node3D = packed.instantiate()
    root.add_child(world)
    await physics_frame
    await physics_frame
    var region: NavigationRegion3D = world.get_node("NavigationBakeTarget")
    var rid := region.get_navigation_map()
    NavigationServer3D.map_force_update(rid)
    for _attempt in range(60):
        await physics_frame
        if NavigationServer3D.map_get_closest_point(rid,Vector3(25,0.2,25)).distance_to(Vector3(25,0.2,25)) < 1:
            break
    var direct := world.get_world_3d().direct_space_state
    var routes: Array = []
    var checkpoints: Array = data["urban_design"]["checkpoints"]
    var start := NavigationServer3D.map_get_closest_point(rid,Vector3(25,0.2,25))
    for index in range(1,checkpoints.size()):
        var p: Array = checkpoints[index]["position"]
        var requested := Vector3(p[0],p[1],p[2])
        var finish := NavigationServer3D.map_get_closest_point(rid,requested)
        var path := NavigationServer3D.map_get_path(rid,start,finish,true)
        if path.size()<2 or finish.distance_to(requested)>1.5 or path[path.size()-1].distance_to(finish)>1:
            _fail("unreachable checkpoint " + String(checkpoints[index]["id"]))
            return
        var length := 0.0
        var highest := 0.0
        for n in range(path.size()-1):
            length += path[n].distance_to(path[n+1])
            highest = maxf(highest,path[n].y)
            var ray := PhysicsRayQueryParameters3D.create(path[n]+Vector3(0,1.3,0),path[n+1]+Vector3(0,1.3,0))
            var hit := direct.intersect_ray(ray)
            if not hit.is_empty():
                _fail("path crosses actual collider " + String(hit["collider"].get_parent().name) + " on " + String(checkpoints[index]["id"]))
                return
        if index==5 and highest<7.5:
            _fail("viaduct path did not ascend its collision ramp")
            return
        routes.append({"destination":checkpoints[index]["id"],"points":path.size(),"length_m":length,"highest_m":highest,"head_ray_clear":true})
    var left := NavigationServer3D.map_get_closest_point(rid,Vector3(-18,0.2,0))
    var right := NavigationServer3D.map_get_closest_point(rid,Vector3(18,0.2,0))
    var detour := NavigationServer3D.map_get_path(rid,left,right,true)
    var lateral := 0.0
    for point in detour:
        lateral = maxf(lateral,absf(point.z))
    if detour.size()<3 or lateral<11:
        _fail("fountain detour missing")
        return
    var hits: Array = []
    for identity in ["fountain_base","block_01_office_0_collision","block_04_home_0_collision","viaduct_deck"]:
        var node := world.find_child(identity,true,false) as Node3D
        if node==null:
            _fail("collider fixture missing: "+identity)
            return
        # Sample the fountain rim, away from the sculpture stacked above its centre.
        var sample := node.global_position + (Vector3(8,0,0) if identity=="fountain_base" else Vector3.ZERO)
        var hit := direct.intersect_ray(PhysicsRayQueryParameters3D.create(sample+Vector3(0,150,0),sample-Vector3(0,150,0)))
        if hit.is_empty() or String(hit["collider"].get_parent().name)!=identity:
            _fail("collision ray did not hit "+identity)
            return
        hits.append(identity)
    var actor: CharacterBody3D = EXPLORER.new()
    actor.enabled = false
    actor.position = Vector3(25,0.5,25)
    root.add_child(actor)
    for frame in range(45):
        await physics_frame
        actor.velocity = Vector3(0,-4,0)
        actor.move_with_steps(1.0/60.0)
    if not actor.is_on_floor() or absf(actor.position.y-0.2)>0.1:
        _fail("explorer cannot stand on plaza")
        return
    var origin := actor.position
    for frame in range(60):
        await physics_frame
        actor.velocity = Vector3(6,-4,0)
        actor.move_with_steps(1.0/60.0)
    var walked := actor.position.distance_to(origin)
    if walked<4.5 or not actor.is_on_floor():
        _fail("explorer failed walking collision test")
        return
    actor.position = Vector3(18,0.5,0)
    for frame in range(120):
        await physics_frame
        actor.velocity = Vector3(-6,-4,0)
        actor.move_with_steps(1.0/60.0)
    if actor.position.x<11.6:
        _fail("explorer entered fountain collider")
        return
    var stopped_x := actor.position.x
    actor.position = Vector3(-140,0.5,108)
    for frame in range(45):
        await physics_frame
        actor.velocity = Vector3(0,-4,0)
        actor.move_with_steps(1.0/60.0)
    for frame in range(120):
        await physics_frame
        actor.velocity = Vector3(6,-4,0)
        actor.move_with_steps(1.0/60.0)
    if actor.position.x < -129 or absf(actor.position.y-0.2)>0.1:
        _fail("explorer could not step onto 0.2 metre sidewalk")
        return
    var curb_position := actor.position
    actor.position = Vector3(241,1,216)
    for frame in range(45):
        await physics_frame
        actor.velocity = Vector3(0,-4,0)
        actor.move_with_steps(1.0/60.0)
    for frame in range(660):
        await physics_frame
        actor.velocity = Vector3(-6,-4,0)
        actor.move_with_steps(1.0/60.0)
    if actor.position.x>180 or actor.position.y<7.8 or not actor.is_on_floor():
        _fail("explorer could not climb bridge collision ramp")
        return
    var report := {"ok":true,"navigation_polygons":region.navigation_mesh.get_polygon_count(),"routes":routes,"fountain_detour_points":detour.size(),"fountain_detour_offset":lateral,"collision_hits":hits,"explorer_walked_m":walked,"explorer_stopped_x":stopped_x,"curb_position":curb_position,"bridge_position":actor.position}
    var out := FileAccess.open("res://.mapforge/urban-probe.json",FileAccess.WRITE)
    out.store_string(JSON.stringify(report,"  "))
    print("URBAN_NEXO_PROBE_OK "+JSON.stringify(report))
    actor.free()
    world.free()
    quit(0)
