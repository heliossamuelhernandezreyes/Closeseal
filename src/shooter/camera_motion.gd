extends RefCounted
## Immediate obstruction response, damped return, bounded locomotion and shoulder motion.
var actor: CharacterBody3D
var distance := 3.5
var was_initialized := false
var shoulder_distance := 0.62
var bob_time := 0.0
var bob_weight := 0.0
var sphere := SphereShape3D.new()

func _init(player: CharacterBody3D) -> void:
	actor = player
	sphere.radius = 0.22

func physics_tick(delta: float) -> void:
	var pivot: Node3D = actor.camera_pivot
	var target_height: float = 1.55 - actor.mobility.crouch_weight * 0.50
	pivot.position.y = lerpf(pivot.position.y, target_height, 1.0-exp(-delta*14.0))
	pivot.rotation.x = actor.look_pitch + actor.recoil * 0.025
	pivot.rotation.y = actor.recoil_yaw
	var target: float = 0.62 * actor.shoulder
	var clear := clear_shoulder(target)
	shoulder_distance = lerpf(shoulder_distance, clear, 1.0-exp(-delta*16.0))
	# Sweep the intermediate shoulder too: a swap must not interpolate through a wall.
	shoulder_distance = clear_shoulder(shoulder_distance)
	actor.spring_arm.position.x = shoulder_distance
	actor.spring_arm.spring_length = lerpf(actor.spring_arm.spring_length, 2.25 if actor.is_aiming() else 3.5, 1.0-exp(-delta*12.0))

func clear_shoulder(offset: float) -> float:
	if absf(offset) < 0.001:return 0.0
	var pivot: Node3D = actor.camera_pivot
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, pivot.global_position)
	query.motion = pivot.global_basis.x * offset
	query.collision_mask = 1 | 4
	query.exclude = [actor.get_rid()]
	query.margin = 0.015
	var sweep := actor.get_world_3d().direct_space_state.cast_motion(query)
	return signf(offset)*maxf(0.0,absf(offset)*sweep[0]-(0.02 if sweep[0]<1.0 else 0.0))

func render_tick(delta: float) -> void:
	var allowed: float = maxf(0.0, actor.spring_arm.get_hit_length())
	if not was_initialized or allowed < distance:
		distance = allowed
		was_initialized = true
	else:
		distance = lerpf(distance, allowed, 1.0-exp(-delta*9.0))
	# SpringArm3D writes the child's absolute local Z, not an extra parent offset.
	# Keep the rendered camera at the smoothed distance inside the swept segment.
	actor.camera.position.z = distance
	var speed := Vector2(actor.velocity.x, actor.velocity.z).length()
	var moving: bool = actor.arena.playing and actor.is_on_floor() and actor.mobility.state == "free"
	bob_weight = lerpf(bob_weight, minf(speed/7.2,1.0) if moving else 0.0, 1.0-exp(-delta*10.0))
	bob_time += delta * clampf(speed*1.4,0.0,10.0)
	# Screen framing stays stable in ADS. Sway is below a centimetre and never changes aim yaw.
	actor.camera.h_offset = sin(bob_time) * bob_weight * (0.001 if actor.is_aiming() else 0.005)
	actor.camera.v_offset = cos(bob_time*2.0) * bob_weight * (0.001 if actor.is_aiming() else 0.007)
	actor.camera.fov = lerpf(actor.camera.fov, 52.0 if actor.is_aiming() else 70.0 if speed>6.0 else 65.0, 1.0-exp(-delta*10.0))

func reset() -> void:
	was_initialized = false
	bob_weight = 0.0
	actor.camera.position = Vector3.ZERO
