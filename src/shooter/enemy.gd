extends CharacterBody3D
const RIG = preload("res://src/shooter/character_rig.gd")
var arena: Node3D
var rig: Node3D
var agent: NavigationAgent3D
var home := Vector3.ZERO
var health := 90.0
var dead := false
var alert := false
var repath := 0.0
var fire_timer := 1.0
var reload_timer := 0.0
var shots := 0
var seed_index := 0
var distance_travelled := 0.0
var search_time := 0.0
var last_seen := Vector3.ZERO
var cover_time := 0.0
var cover_target := Vector3.ZERO
var state := "patrol"
var flank_time := 0.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	floor_snap_length = 0.5
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.85
	shape.shape = capsule
	shape.position.y = 0.925
	add_child(shape)
	rig = RIG.new()
	rig.skin_name = "hostile" if seed_index % 3 else "military"
	add_child(rig)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.7
	agent.target_desired_distance = 1.0
	agent.radius = 0.42
	agent.height = 1.9
	add_child(agent)
	home = global_position
	repath = float(seed_index) * 0.07
	fire_timer = 0.9 + float(seed_index % 5) * 0.15

func _physics_process(delta: float) -> void:
	if dead or not arena.playing: return
	var player: CharacterBody3D = arena.player
	var distance := global_position.distance_to(player.global_position)
	var sees := distance < 46.0 and line_of_sight()
	if sees:
		last_seen = player.global_position
		search_time = 7.0
	else: search_time = maxf(0, search_time - delta)
	alert = search_time > 0
	cover_time = maxf(0, cover_time - delta)
	flank_time = maxf(0, flank_time - delta)
	state = "cover" if cover_time > 0 else "attack" if sees else "search" if alert else "patrol"
	repath -= delta
	if repath <= 0:
		repath = 0.55
		if cover_time > 0:
			agent.target_position = cover_target
		elif alert and (not sees or distance > 15.0 or (arena.mission_mode == "sector07" and seed_index % 3 == 1)):
			var target := last_seen
			if seed_index % 3 == 1 and sees:
				var approach := (last_seen - global_position).normalized()
				var desired := target + Vector3(-approach.z, 0, approach.x) * 8.0
				var map := agent.get_navigation_map()
				var nearest := NavigationServer3D.map_get_closest_point(map, desired)
				var path := NavigationServer3D.map_get_path(map, global_position, nearest, true)
				if nearest.distance_to(desired) < 1.5 and path.size() > 1:
					target = nearest
					flank_time = 1.0
			agent.target_position = target
		elif not alert:
			var phase: float = arena.elapsed * 0.13 + seed_index
			agent.target_position = home + Vector3(sin(phase) * 5, 0, cos(phase) * 5)
		else: agent.target_position = global_position
	var direction := Vector3.ZERO
	if not agent.is_navigation_finished() and (cover_time > 0 or not sees or distance > 15.0 or flank_time > 0):
		direction = agent.get_next_path_position() - global_position
		direction.y = 0
		direction = direction.normalized()
	var speed := 3.8 if alert else 1.8
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * 18)
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * 18)
	if not is_on_floor(): velocity.y -= 22 * delta
	var previous := global_position
	move_and_slide()
	distance_travelled += previous.distance_to(global_position)
	var facing := last_seen - global_position if sees else direction
	facing.y = 0
	if facing.length_squared() > 0.01:
		var target_yaw := atan2(-facing.x, -facing.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, target_yaw, minf(1, delta * 10))
	var local_motion: Vector3 = rig.global_basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	rig.set_motion(Vector2(velocity.x, velocity.z).length(), not is_on_floor(), Vector2(local_motion.x, local_motion.z))
	rig.aim_pitch = clampf(atan2((global_position.y + 1.4) - (player.global_position.y + player.target_height()), maxf(distance, 0.01)), -0.55, 0.55) if sees else 0.0
	fire_timer -= delta
	reload_timer = maxf(0, reload_timer - delta)
	if sees and fire_timer <= 0 and reload_timer == 0:
		fire_timer = 0.65 + arena.rng.randf_range(0, 0.35)
		fire_at_player()

func line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.4,
		arena.player.target_point(), 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == arena.player

func fire_at_player() -> void:
	rig.fire()
	arena.sound_at("shot", rig.muzzle.global_position)
	var origin: Vector3 = rig.muzzle.global_position
	var target: Vector3 = arena.player.target_point()
	var distance := origin.distance_to(target)
	target += Vector3(arena.rng.randf_range(-1, 1), arena.rng.randf_range(-0.6, 0.6), 0) * maxf(0.2, distance * 0.027)
	var direction := (target - origin).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 90, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var endpoint := origin + direction * 90
	if not hit.is_empty():
		endpoint = hit.position
		if hit.collider == arena.player: arena.player.take_damage(6.0, origin)
		arena.impact(endpoint, hit.normal)
	arena.tracer(origin, endpoint, Color("ff8961"))
	shots += 1
	if shots % 8 == 0:
		reload_timer = 1.6
		rig.reload()

func take_damage(amount: float) -> void:
	if dead: return
	alert = true
	health -= amount
	rig.hit()
	search_time = 7.0
	last_seen = arena.player.global_position
	if health > 0 and health < 65 and cover_time == 0: seek_cover()
	if health <= 0:
		dead = true
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		rig.die()
		arena.kills += 1
		arena.kill_marker = 0.3

func seek_cover() -> void:
	var best_distance := 18.0
	for value in arena.design.get("cover_points", []):
		var centre: Vector3 = arena.vec(value) - Vector3(0, 0, 1.4)
		var away: Vector3 = (centre - arena.player.global_position).normalized()
		away.y = 0
		var target: Vector3 = centre + away * 1.7
		var distance := global_position.distance_to(target)
		if distance > best_distance or distance < 1: continue
		var ray := PhysicsRayQueryParameters3D.create(target + Vector3.UP * 1.1,
			arena.player.target_point(), 1)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		var path := NavigationServer3D.map_get_path(agent.get_navigation_map(), global_position, target, true)
		if path.size() < 2 or path[-1].distance_to(target) > 1.2: continue
		cover_target = target
		best_distance = distance
		cover_time = 3.0
		state = "cover"
