extends CharacterBody3D
const MAGAZINE := 24
const FIRE_INTERVAL := 0.125
var arena: Node3D
var camera: Camera3D
var gun: Node3D
var muzzle: Node3D
var flash: MeshInstance3D
var ammo := MAGAZINE
var reserve := 144
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
var look_pitch := 0.0
var recoil := 0.0
var step_phase := 0.0
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
	camera = Camera3D.new()
	camera.position.y = 1.65
	camera.fov = 78
	camera.near = 0.05
	add_child(camera)
	camera.current = true
	gun = load("res://assets/shooter/kenney/blasters/blaster-a.glb").instantiate()
	camera.add_child(gun)
	gun.position = Vector3(0.25, -0.22, -0.48)
	gun.scale = Vector3.ONE * 0.7
	muzzle = Node3D.new()
	gun.add_child(muzzle)
	muzzle.position.z = -0.38
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
	look_pitch = clampf(look_pitch - delta.y * 0.0028, -1.35, 1.35)

func _unhandled_input(event: InputEvent) -> void:
	if not arena.playing: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: look(event.relative)
	if event.is_action_pressed("reload"): start_reload()
	if event.is_action_pressed("jump"): jump_requested = true
	if event.is_action_pressed("interact"): arena.interact()

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
	if (Input.is_action_pressed("fire") or fire_held) and shot_cooldown == 0.0: shoot()
	move_input = Input.get_vector("left", "right", "forward", "back") + touch_move
	move_input = move_input.limit_length()
	var sprint := (Input.is_action_pressed("sprint") or touch_sprint) and not is_aiming()
	var speed := 9.0 if sprint else 3.4 if is_aiming() else 5.4
	var direction := global_basis * Vector3(move_input.x, 0, move_input.y)
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * 32.0)
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * 32.0)
	if not is_on_floor(): velocity.y -= 22.0 * delta
	if jump_requested and is_on_floor(): velocity.y = 7.2
	jump_requested = false
	move_and_slide()
	if hurt_time == 0.0: health = minf(100.0, health + delta * 6)
	if global_position.y < -10: take_damage(100)

func _process(delta: float) -> void:
	if not is_instance_valid(camera): return
	recoil = move_toward(recoil, 0.0, delta * 5.0)
	step_phase += delta * Vector2(velocity.x, velocity.z).length() * 1.8
	camera.rotation.x = look_pitch + recoil * 0.025
	camera.fov = lerpf(camera.fov, 55.0 if is_aiming() else 78.0, minf(1.0, delta * 12))
	var sway := sin(step_phase) * 0.012 if is_on_floor() else 0.0
	var target := Vector3(0.0, -0.15, -0.40) if is_aiming() else Vector3(0.25, -0.22 + sway, -0.48)
	gun.position = gun.position.lerp(target + Vector3(0, 0, recoil * 0.055), minf(1.0, delta * 14))
	gun.rotation.x = -recoil * 0.10 + sin(reload_remaining / 1.6 * PI) * 0.70
	gun.rotation.z = sin(reload_remaining / 1.6 * PI) * -0.25
	flash.visible = shot_cooldown > FIRE_INTERVAL - 0.04

func is_aiming() -> bool: return aim_held or Input.is_action_pressed("aim")

func start_reload() -> bool:
	if reload_remaining > 0.0 or ammo >= MAGAZINE or reserve <= 0: return false
	reload_remaining = 1.6
	arena.sound("reload")
	return true

func shoot() -> Dictionary:
	if ammo <= 0:
		start_reload()
		return {}
	if reload_remaining > 0.0: return {}
	ammo -= 1
	shot_cooldown = FIRE_INTERVAL
	recoil = minf(recoil + 0.6, 1.4)
	var origin := camera.global_position
	var end := origin - camera.global_basis.z * 180.0
	var sight := ray(origin, end)
	if not sight.is_empty(): end = sight.position
	# A second ray from the actual muzzle prevents shooting through nearby cover.
	last_hit = ray(muzzle.global_position, end + (end - origin).normalized() * 0.03)
	if not last_hit.is_empty():
		end = last_hit.position
		var victim: Node = last_hit.collider
		if victim.has_method("take_damage"):
			var headshot: bool = end.y > victim.global_position.y + 1.45
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

func take_damage(amount: float) -> void:
	if not arena.playing: return
	health = maxf(0, health - amount)
	hurt_time = 5.0
	arena.damage_flash = 0.35
	if health == 0.0: arena.finish(false)

func clear_input() -> void:
	fire_held = false
	aim_held = false
	touch_move = Vector2.ZERO
	touch_sprint = false
	jump_requested = false
