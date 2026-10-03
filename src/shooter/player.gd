extends CharacterBody3D
const MAGAZINE := 30
const FIRE_INTERVAL := 0.125
const MOBILITY = preload("res://src/shooter/mobility.gd")
var mobility: RefCounted
var body_shape: CollisionShape3D
var damage_direction := Vector3.ZERO
var arena: Node3D
var camera: Camera3D
var camera_pivot: Node3D
var spring_arm: SpringArm3D
var rig: Node3D
var gun: Node3D
var muzzle: Node3D
var flash: MeshInstance3D
var ammo := MAGAZINE
var reserve := 180
var health := 100.0
var reload_remaining := 0.0
var shot_cooldown := 0.0
var hurt_time := 0.0
var fire_held := false
var aim_held := false
var jump_requested := false
var move_input := Vector2.ZERO
var touch_move := Vector2.ZERO
var touch_sprint := false
var look_pitch := -0.12
var shoulder := 1.0
var playtest_active := false
var playtest_ticks := 0
var playtest_interactions := 0
signal playtest_tick(snapshot: Dictionary)
var recoil := 0.0
var step_phase := 0.0
var step_distance := 0.0
var last_hit: Dictionary = {}

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.85
	shape.shape = capsule
	shape.position.y = 0.925
	add_child(shape)
	body_shape = shape
	body_shape.name = "BodyCollider"
	mobility = MOBILITY.new(self)
	rig = load("res://src/shooter/character_rig.gd").new()
	rig.name = "Character"
	add_child(rig)
	gun = rig.weapon
	muzzle = rig.muzzle
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position.y = 1.55
	add_child(camera_pivot)
	spring_arm = SpringArm3D.new()
	spring_arm.name = "ShoulderArm"
	spring_arm.position.x = 0.62
	spring_arm.spring_length = 3.5
	spring_arm.margin = 0.12
	spring_arm.collision_mask = 1 | 4
	var camera_volume := SphereShape3D.new()
	camera_volume.radius = 0.22
	spring_arm.shape = camera_volume
	camera_pivot.add_child(spring_arm)
	spring_arm.add_excluded_object(get_rid())
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 65
	camera.near = 0.12
	spring_arm.add_child(camera)
	camera.current = true
	flash = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.055
	ball.height = 0.11
	flash.mesh = ball
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 0.85, 0.25)
	flash.material_override = material
	muzzle.add_child(flash)
	flash.visible = false

func look(delta: Vector2) -> void:
	rotation.y -= delta.x * 0.0028
	# Orbit freely without dragging the idle character around with the camera.
	rig.rotation.y += delta.x * 0.0028
	look_pitch = clampf(look_pitch - delta.y * 0.0028, -1.05, 1.05)

func _unhandled_input(event: InputEvent) -> void:
	if not arena.playing: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: look(event.relative)
	if event.is_action_pressed("reload"): start_reload()
	if event.is_action_pressed("jump"): jump_requested = true
	if event.is_action_pressed("interact"): arena.interact()
	if event.is_action_pressed("swap_shoulder"): shoulder *= -1.0
	if event.is_action_pressed("cover") and not event.is_echo(): mobility.toggle_cover()
	if event.is_action_pressed("stance") and not event.is_echo(): mobility.stance()

func _physics_process(delta: float) -> void:
	if not arena.playing: return
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	hurt_time = maxf(0.0, hurt_time - delta)
	if reload_remaining > 0.0:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		if reload_remaining == 0.0:
			var count := mini(MAGAZINE - ammo, reserve)
			ammo += count
			reserve -= count
	move_input = Input.get_vector("left", "right", "forward", "back") + touch_move
	move_input = move_input.limit_length()
	var sprint := (Input.is_action_pressed("sprint") or touch_sprint) and not is_aiming()
	var direction := global_basis * Vector3(move_input.x, 0, move_input.y)
	if jump_requested: mobility.request_jump()
	jump_requested = false
	var previous := global_position
	var cover_aim: bool = is_aiming() or ((fire_held or Input.is_action_pressed("fire")) and mobility.state == "cover")
	if not mobility.tick(delta, direction, sprint, cover_aim): move_and_slide()
	var moving := Vector2(velocity.x, velocity.z).length()
	var facing := 0.0 if is_aiming() or fire_held or Input.is_action_pressed("fire") else atan2(-move_input.x, -move_input.y)
	if mobility.state == "corner":
		var progress: float = mobility.path_progress / maxf(mobility.path_distance, 0.001)
		var normal: Vector3 = mobility.cover_normal.lerp(mobility.path_end_normal, progress).normalized()
		facing = atan2(-normal.x, -normal.z) - rotation.y
	elif mobility.state == "transfer":
		facing = atan2(-velocity.x, -velocity.z) - rotation.y
	elif mobility.state == "cover" and not cover_aim:
		facing = atan2(-mobility.cover_normal.x, -mobility.cover_normal.z) - rotation.y
	elif mobility.state == "vault":
		var heading: Vector3 = mobility.vault_end - mobility.vault_start
		facing = atan2(-heading.x, -heading.z) - rotation.y
	elif mobility.state == "slide":
		facing = atan2(-mobility.slide_direction.x, -mobility.slide_direction.z) - rotation.y
	if moving > 0.15 or cover_aim or mobility.state != "free": rig.rotation.y = lerp_angle(rig.rotation.y, facing, minf(1.0, delta * 18))
	var local_motion: Vector3 = rig.global_basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	rig.set_motion(moving, not is_on_floor(), Vector2(local_motion.x, local_motion.z))
	rig.stance_weight = mobility.crouch_weight
	rig.position = global_basis.inverse() * mobility.peek_offset
	rig.action_pose = mobility.pose_name()
	rig.action_phase = clampf(mobility.elapsed / (0.68 if mobility.state == "vault" else 0.62), 0, 1)
	if mobility.state == "vault": rig.position.y -= sin(rig.action_phase * PI) * 0.40
	if mobility.state == "cover" and mobility.cover_enter > 0: rig.action_phase = 1.0 - mobility.cover_enter / 0.22
	rig.vault_hand_target = mobility.vault_hand
	camera_pivot.position.y = lerpf(camera_pivot.position.y, 1.55 - mobility.crouch_weight * 0.50, minf(1, delta * 14))
	camera_pivot.rotation.x = look_pitch + recoil * 0.025
	var shoulder_target := camera_pivot.to_global(Vector3(0.62 * shoulder, 0, 0))
	var lateral_hit := ray(camera_pivot.global_position, shoulder_target)
	var lateral_distance := 0.62
	if not lateral_hit.is_empty(): lateral_distance = maxf(0.0, camera_pivot.global_position.distance_to(lateral_hit.position) - 0.24)
	spring_arm.position.x = lerpf(spring_arm.position.x, lateral_distance * shoulder, minf(1.0, delta * 16))
	# Retraction is immediate even while swapping shoulders beside a side wall.
	var offset_hit := ray(camera_pivot.global_position, camera_pivot.to_global(Vector3(spring_arm.position.x, 0, 0)))
	if not offset_hit.is_empty():
		spring_arm.position.x = signf(spring_arm.position.x) * maxf(0.0, camera_pivot.global_position.distance_to(offset_hit.position) - 0.24)
	spring_arm.spring_length = lerpf(spring_arm.spring_length, 2.25 if is_aiming() else 3.5, minf(1.0, delta * 12))
	rig.aim_target = aim_point()
	rig.target_enabled = is_aiming() or fire_held or Input.is_action_pressed("fire") or shot_cooldown > 0.0
	if (Input.is_action_pressed("fire") or fire_held) and shot_cooldown == 0.0: shoot()
	if is_on_floor():
		step_distance += Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
		if step_distance > (1.6 if sprint else 1.1):
			step_distance = 0
			arena.sound("step")
	if hurt_time == 0.0: health = minf(100.0, health + delta * 6)
	if global_position.y < -10: take_damage(100)
	if playtest_active:
		playtest_ticks += 1
		playtest_tick.emit(playtest_snapshot())

func _process(delta: float) -> void:
	if not is_instance_valid(camera): return
	recoil = move_toward(recoil, 0.0, delta * 5.0)
	step_phase += delta * Vector2(velocity.x, velocity.z).length() * 1.8
	var fast := Vector2(velocity.x, velocity.z).length() > 6.0
	camera.fov = lerpf(camera.fov, 52.0 if is_aiming() else 73.0 if fast else 65.0, minf(1.0, delta * 10))
	# Hide the body only if a tight obstruction brings the camera into its mesh.
	rig.visible = camera.global_position.distance_to(global_position + Vector3.UP) > 0.95
	flash.visible = shot_cooldown > FIRE_INTERVAL - 0.04

func is_aiming() -> bool: return aim_held or Input.is_action_pressed("aim")

func start_reload() -> bool:
	if reload_remaining > 0.0 or ammo >= MAGAZINE or reserve <= 0: return false
	reload_remaining = 1.6
	rig.reload()
	arena.sound("reload")
	return true

func shoot() -> Dictionary:
	if mobility.state in ["vault", "slide", "corner", "transfer"]: return {}
	if ammo <= 0:
		start_reload()
		return {}
	if reload_remaining > 0.0: return {}
	ammo -= 1
	shot_cooldown = FIRE_INTERVAL
	recoil = minf(recoil + 0.6, 1.4)
	rig.rotation.y = 0.0
	rig.fire()
	var origin := camera.global_position
	var end := aim_point()
	gun.look_at(end, Vector3.UP)
	# Check the whole barrel: its tip can extend through a wall while the capsule
	# remains outside. Then resolve the shot from the actual muzzle to the reticle.
	last_hit = ray(rig.global_position + Vector3.UP * gun.position.y, muzzle.global_position)
	if last_hit.is_empty(): last_hit = ray(muzzle.global_position, end + (end - origin).normalized() * 0.03)
	if not last_hit.is_empty():
		end = last_hit.position
		var victim: Node = last_hit.collider
		if victim.has_method("take_damage"):
			var headshot: bool = end.y > victim.global_position.y + 1.68
			victim.take_damage(60.0 if headshot else 34.0)
			arena.hit_marker = 0.18
			arena.sound("hit")
		arena.impact(end, last_hit.normal)
	arena.tracer(muzzle.global_position, end, Color("ffda7d"))
	arena.sound("shot")
	return last_hit

func ray(start: Vector3, end: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end, 1 | 4, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)

func aim_point() -> Vector3:
	var origin := camera.global_position
	var end := origin - camera.global_basis.z * 180.0
	var sight := ray(origin, end)
	return sight.position if not sight.is_empty() else end

func take_damage(amount: float, source := Vector3.ZERO) -> void:
	if not arena.playing: return
	health = maxf(0, health - amount)
	hurt_time = 5.0
	arena.damage_flash = 0.35
	if source != Vector3.ZERO: damage_direction = (source - global_position).normalized()
	if health == 0.0:
		rig.die()
		arena.finish(false)

func clear_input() -> void:
	fire_held = false
	aim_held = false
	touch_move = Vector2.ZERO
	touch_sprint = false
	jump_requested = false
	if is_instance_valid(mobility): mobility.jump_buffer = 0

func target_height() -> float: return mobility.capsule_height * 0.68
func target_point() -> Vector3: return global_position + mobility.peek_offset + Vector3.UP * target_height()

func begin_playtest() -> void:
	playtest_active = true
	playtest_ticks = 0
	playtest_interactions = 0
	arena.begin()

func end_playtest() -> void:
	playtest_active = false
	clear_input()
	arena.playing = false
	for speaker in arena.get_children():
		if speaker is AudioStreamPlayer or speaker is AudioStreamPlayer3D:
			speaker.stop()
			speaker.stream = null
			speaker.queue_free()

func playtest_snapshot() -> Dictionary:
	return {"tick": playtest_ticks, "position": [global_position.x, global_position.y, global_position.z],
		"velocity": [velocity.x, velocity.y, velocity.z], "health": health, "ammo": ammo,
		"interactions": playtest_interactions, "camera_distance": spring_arm.get_hit_length(),
		"perspective": "third_person", "on_floor": is_on_floor(), "movement_state": mobility.state,
		"crouched": mobility.capsule_height < 1.8, "cover_low": mobility.cover_low,
		"peek": mobility.peek, "vault_aborted": mobility.vault_aborted,
		"completed_corners": mobility.completed_corners, "completed_transfers": mobility.completed_transfers,
		"transition_aborted": mobility.transition_aborted}
