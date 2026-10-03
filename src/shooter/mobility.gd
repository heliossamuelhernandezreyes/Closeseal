extends RefCounted
## Game-owned movement state. Physics decides clearance; animation consumes state.
const WALK := 5.4
const SPRINT := 8.8
const AIM := 3.25
const STANDING := 1.85
const CROUCHED := 1.06
const VAULT_SECONDS := 0.68
var actor: CharacterBody3D
var state := "free"
var crouched := false
var crouch_weight := 0.0
var capsule_height := STANDING
var floor_grace := 0.0
var jump_buffer := 0.0
var cooldown := 0.0
var elapsed := 0.0
var landed := 0.0
var was_grounded := false
var cover_normal := Vector3.ZERO
var cover_body: WeakRef
var cover_low := false
var cover_enter := 0.0
var peek := false
var edge := false
var peek_offset := Vector3.ZERO
var candidate: Dictionary = {}
var scan_time := 0.0
var slide_direction := Vector3.ZERO
var vault_start := Vector3.ZERO
var vault_end := Vector3.ZERO
var vault_top := 0.0
var vault_hand := Vector3.ZERO
var vault_aborted := false
var vault_reason := ""
var cover_path: Array[Vector3] = []
var path_distance := 0.0
var path_progress := 0.0
var path_end_normal := Vector3.ZERO
var path_end_body: WeakRef
var path_end_low := false
var transition_aborted := false
var completed_corners := 0
var completed_transfers := 0
var transfer_candidate: Dictionary = {}

func _init(player: CharacterBody3D) -> void: actor = player

func world_ray(from: Vector3, to: Vector3) -> Dictionary:
	return actor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1, [actor.get_rid()]))

func clear_at(feet: Vector3, height: float) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.33
	shape.height = height - 0.02
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (height * 0.5 + 0.025))
	query.collision_mask = 1 | 4
	query.exclude = [actor.get_rid()]
	return actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func set_height(height: float) -> bool:
	if height > capsule_height and not clear_at(actor.global_position + peek_offset, height): return false
	capsule_height = height
	actor.body_shape.shape.height = height
	actor.body_shape.position = actor.global_basis.inverse() * peek_offset + Vector3.UP * height * 0.5
	return true

func forward() -> Vector3:
	var direction := -actor.global_basis.z
	direction.y = 0
	return direction.normalized()

func find_cover(direction: Vector3) -> Dictionary:
	if direction.length() < 0.2: direction = forward()
	for angle in [0.0, -0.32, 0.32]:
		var heading: Vector3 = direction.rotated(Vector3.UP, angle).normalized()
		var start := actor.global_position + Vector3.UP * 0.60
		var hit := world_ray(start, start + heading * 1.25)
		if hit.is_empty() or absf(hit.normal.y) > 0.2: continue
		var normal: Vector3 = hit.normal.normalized()
		# Reject poles, narrow edges and faces without support for both shoulders.
		var tangent := normal.cross(Vector3.UP).normalized()
		var supported := true
		for offset in [-0.28, 0.28]:
			var side: Vector3 = hit.position + normal * 0.3 + tangent * offset
			var probe := world_ray(side, side - normal * 0.6)
			if probe.is_empty() or probe.collider != hit.collider: supported = false
		if not supported: continue
		var high_start := actor.global_position + Vector3.UP * 1.5
		var high := world_ray(high_start, high_start - normal * 1.35)
		return {"normal": normal, "point": hit.position, "body": hit.collider,
			"low": high.is_empty(), "distance": start.distance_to(hit.position)}
	return {}

func toggle_cover() -> bool:
	if state == "cover":
		if not transfer_candidate.is_empty() and start_cover_path(transfer_candidate, "transfer"): return true
		leave_cover()
		return true
	if state != "free" or not actor.is_on_floor() or cooldown > 0.0: return false
	var found := find_cover(forward())
	if found.is_empty(): return false
	cover_normal = found.normal
	cover_body = weakref(found.body)
	cover_low = found.low
	cover_enter = 0.22
	crouched = false
	state = "cover"
	actor.velocity.x = 0
	actor.velocity.z = 0
	return true

func leave_cover() -> void:
	state = "free"
	cover_body = null
	peek = false
	edge = false
	peek_offset = Vector3.ZERO
	cooldown = 0.18
	transfer_candidate = {}

func valid_cover_path(points: Array[Vector3]) -> bool:
	var previous := actor.global_position
	for point in points:
		var floor_hit := world_ray(point + Vector3.UP * 0.35, point - Vector3.UP * 0.4)
		if floor_hit.is_empty() or floor_hit.normal.y < 0.8 or absf(floor_hit.position.y - point.y) > 0.2: return false
		if not clear_at(point, capsule_height): return false
		if actor.test_move(Transform3D(actor.global_basis, previous), point - previous): return false
		previous = point
	return true

func start_cover_path(found: Dictionary, kind: String) -> bool:
	if cooldown > 0 or not valid_cover_path(found.points): return false
	cover_path = found.points.duplicate()
	path_end_normal = found.normal
	path_end_body = weakref(found.body)
	path_end_low = found.low
	path_distance = 0
	var previous := actor.global_position
	cover_path.push_front(previous)
	for point in cover_path:
		path_distance += previous.distance_to(point)
		previous = point
	path_progress = 0
	transition_aborted = false
	peek = false
	peek_offset = Vector3.ZERO
	set_height(CROUCHED if cover_low else STANDING)
	actor.velocity = Vector3.ZERO
	state = kind
	return true

func nearby_transfer(direction: Vector3) -> Dictionary:
	if state != "cover" or direction.length() < 0.3 or not is_instance_valid(cover_body.get_ref()): return {}
	var tangent := cover_normal.cross(Vector3.UP).normalized()
	var axis := direction.dot(tangent)
	if absf(axis) < 0.45: return {}
	var heading := tangent * signf(axis)
	for distance in [1.6, 2.4, 3.2, 4.0, 4.8, 5.6]:
		var origin: Vector3 = actor.global_position + heading * distance + Vector3.UP * 0.6
		var hit := world_ray(origin, origin - cover_normal * 1.35)
		if hit.is_empty() or hit.collider == cover_body.get_ref() or hit.normal.dot(cover_normal) < 0.95: continue
		var target: Vector3 = hit.position + hit.normal * 0.43 - Vector3.UP * 0.6
		var supported := true
		for offset in [-0.35, 0.35]:
			var side: Vector3 = target + tangent * offset + Vector3.UP * 0.6
			var shoulder_hit := world_ray(side, side - hit.normal * 0.8)
			if shoulder_hit.is_empty() or shoulder_hit.collider != hit.collider: supported = false
		if not supported: continue
		var points: Array[Vector3] = []
		for sample in range(1, 17): points.append(actor.global_position.lerp(target, sample / 16.0))
		if not valid_cover_path(points): continue
		var high_start := target + Vector3.UP * 1.5
		return {"points": points, "normal": hit.normal, "body": hit.collider,
			"low": world_ray(high_start, high_start - hit.normal * 0.8).is_empty()}
	return {}

func try_corner(axis: float) -> bool:
	if cooldown > 0 or absf(axis) < 0.55 or peek: return false
	var heading := cover_normal.cross(Vector3.UP).normalized() * signf(axis)
	var from := actor.global_position + Vector3.UP * 0.6
	var outside := from + heading * 0.65
	if not world_ray(outside, outside - cover_normal * 0.9).is_empty(): return false
	# Locate the actual face edge, then verify the adjoining convex face.
	var inside_distance := 0.0
	var outside_distance := 0.65
	for sample in range(9):
		var middle := (inside_distance + outside_distance) * 0.5
		var probe := from + heading * middle
		var hit := world_ray(probe, probe - cover_normal * 0.9)
		if not hit.is_empty() and hit.collider == cover_body.get_ref(): inside_distance = middle
		else: outside_distance = middle
	var face := world_ray(from, from - cover_normal * 0.9)
	if face.is_empty(): return false
	var corner: Vector3 = face.position + heading * inside_distance - Vector3.UP * 0.6
	var side_probe := corner + heading * 0.8 - cover_normal * 0.22 + Vector3.UP * 0.6
	var side_hit := world_ray(side_probe, side_probe - heading * 1.1)
	if side_hit.is_empty() or side_hit.collider != cover_body.get_ref() or side_hit.normal.dot(heading) < 0.95: return false
	var angle := cover_normal.signed_angle_to(side_hit.normal, Vector3.UP)
	var points: Array[Vector3] = [corner + cover_normal * 0.46]
	for sample in range(1, 13): points.append(corner + cover_normal.rotated(Vector3.UP, angle * sample / 12.0) * 0.46)
	points.append(corner + side_hit.normal * 0.46 - cover_normal * 0.22)
	var high_start := points[-1] + Vector3.UP * 1.5
	return start_cover_path({"points": points, "normal": side_hit.normal, "body": side_hit.collider,
		"low": world_ray(high_start, high_start - side_hit.normal * 0.8).is_empty()}, "corner")

func advance_cover_path(delta: float) -> void:
	if not is_instance_valid(path_end_body.get_ref()):
		transition_aborted = true
		leave_cover()
		return
	path_progress = minf(path_distance, path_progress + delta * (6.8 if state == "transfer" else 2.6))
	var remaining := path_progress
	var point: Vector3 = cover_path[-1]
	for index in range(1, cover_path.size()):
		var length := cover_path[index - 1].distance_to(cover_path[index])
		if remaining <= length:
			point = cover_path[index - 1].lerp(cover_path[index], remaining / maxf(length, 0.0001))
			break
		remaining -= length
	var motion := point - actor.global_position
	actor.velocity = motion / maxf(delta, 0.0001)
	if not clear_at(point, capsule_height) or actor.move_and_collide(motion):
		transition_aborted = true
		leave_cover()
		actor.velocity = Vector3.ZERO
		return
	if path_progress >= path_distance:
		if state == "corner": completed_corners += 1
		else: completed_transfers += 1
		cover_normal = path_end_normal
		cover_body = path_end_body
		cover_low = path_end_low
		state = "cover"
		cover_enter = 0.12
		cooldown = 0.3
		actor.velocity = Vector3.ZERO

func stance() -> void:
	if state in ["vault", "slide", "corner", "transfer"]: return
	if state == "cover": leave_cover(); return
	if actor.is_on_floor() and Vector2(actor.velocity.x, actor.velocity.z).length() > 6.0 and not actor.is_aiming():
		state = "slide"
		elapsed = 0
		slide_direction = Vector3(actor.velocity.x, 0, actor.velocity.z).normalized()
		crouched = false
	else: crouched = not crouched

func request_jump() -> void:
	if state in ["vault", "corner", "transfer"]: return
	if state == "slide": state = "free"
	if try_vault(): return
	if state == "cover": leave_cover()
	crouched = false
	jump_buffer = 0.13

func vault_point(progress: float) -> Vector3:
	var raised_start := Vector3(vault_start.x, vault_top + 0.08, vault_start.z)
	var raised_end := Vector3(vault_end.x, vault_top + 0.08, vault_end.z)
	if progress < 0.28: return vault_start.lerp(raised_start, smoothstep(0, 0.28, progress))
	if progress < 0.78: return raised_start.lerp(raised_end, smoothstep(0.28, 0.78, progress))
	return raised_end.lerp(vault_end, smoothstep(0.78, 1, progress))

func try_vault() -> bool:
	vault_reason = ""
	if state not in ["free", "cover"] or not actor.is_on_floor() or cooldown > 0.0: vault_reason = "state_or_floor"; return false
	var heading := -cover_normal if state == "cover" else forward()
	var start := actor.global_position + Vector3.UP * 0.6
	var face := world_ray(start, start + heading * 1.5)
	if face.is_empty() or absf(face.normal.y) > 0.15: vault_reason = "no_face"; return false
	var top := world_ray(face.position + heading * 0.18 + Vector3.UP * 1.6, face.position + heading * 0.18 - Vector3.UP * 0.3)
	if top.is_empty() or top.normal.y < 0.8: vault_reason = "no_top"; return false
	var height: float = top.position.y - actor.global_position.y
	if height < 0.45 or height > 1.35: vault_reason = "height_" + str(height); return false
	var landing := Vector3.ZERO
	var found_landing := false
	for index in range(3, 11):
		var probe: Vector3 = face.position + heading * (index * 0.2)
		var floor_hit := world_ray(Vector3(probe.x, top.position.y + 0.1, probe.z), Vector3(probe.x, actor.global_position.y - 0.45, probe.z))
		if floor_hit.is_empty() or floor_hit.normal.y < 0.8 or absf(floor_hit.position.y - actor.global_position.y) > 0.35: continue
		var feet: Vector3 = floor_hit.position + Vector3.UP * 0.02
		if not clear_at(feet, STANDING): continue
		landing = feet
		found_landing = true
		break
	if not found_landing: vault_reason = "landing_blocked"; return false
	vault_start = actor.global_position
	vault_end = landing
	vault_top = top.position.y
	vault_hand = top.position
	# Sweep the complete path before accepting. No disabling collision or warp.
	var saved_height := capsule_height
	set_height(0.85)
	var previous := vault_start
	for index in range(1, 21):
		var next := vault_point(index / 20.0)
		var contact := KinematicCollision3D.new()
		if actor.test_move(Transform3D(actor.global_basis, previous), next - previous, contact):
			vault_reason = "sweep_%d_%s_%s" % [index, str(contact.get_collider().name), str(contact.get_normal())]
			set_height(saved_height)
			return false
		previous = next
	state = "vault"
	elapsed = 0
	peek = false
	crouched = false
	vault_aborted = false
	actor.velocity = Vector3.ZERO
	return true

func tick(delta: float, direction: Vector3, sprint: bool, aiming: bool) -> bool:
	cooldown = maxf(0, cooldown - delta)
	landed = maxf(0, landed - delta)
	var grounded := actor.is_on_floor()
	if state in ["corner", "transfer"]:
		advance_cover_path(delta)
		return true
	if grounded:
		floor_grace = 0.10
		if not was_grounded and actor.velocity.y < -3.0: landed = 0.18
	else: floor_grace = maxf(0, floor_grace - delta)
	was_grounded = grounded
	jump_buffer = maxf(0, jump_buffer - delta)
	scan_time -= delta
	if scan_time <= 0:
		candidate = find_cover(direction)
		transfer_candidate = nearby_transfer(direction)
		scan_time = 0.10
	if state == "vault":
		elapsed += delta
		var next := vault_point(minf(1, elapsed / VAULT_SECONDS))
		var collision := actor.move_and_collide(next - actor.global_position)
		if collision:
			state = "free"
			vault_aborted = true
			cooldown = 0.25
		elif elapsed >= VAULT_SECONDS:
			state = "free"
			landed = 0.18
			cooldown = 0.15
		crouch_weight = move_toward(crouch_weight, 1.0, delta * 12)
		return true
	var speed := AIM if aiming else SPRINT if sprint and direction.length() > 0.2 else WALK
	var target := direction * speed
	var desired_peek := Vector3.ZERO
	if state == "cover":
		if not is_instance_valid(cover_body.get_ref()) or not grounded or direction.dot(cover_normal) > 0.55 or (sprint and direction.length() > 0.3):
			leave_cover()
		else:
			var from := actor.global_position + Vector3.UP * 0.6
			var face := world_ray(from, from - cover_normal * 1.3)
			if face.is_empty() or face.collider != cover_body.get_ref(): leave_cover()
			else:
				var tangent := cover_normal.cross(Vector3.UP).normalized()
				var axis := direction.dot(tangent)
				var side: Vector3 = from + tangent * (signf(axis) if absf(axis) > 0.1 else -actor.shoulder) * 0.65
				edge = world_ray(side, side - cover_normal * 1.3).is_empty()
				peek = aiming and (cover_low or edge)
				if not aiming and try_corner(axis): return true
				if peek and not cover_low:
					var side_sign: float = signf(axis) if absf(axis) > 0.1 else -actor.shoulder
					desired_peek = tangent * side_sign * 0.65
					for sample in range(1, 5):
						if not clear_at(actor.global_position + desired_peek * sample / 4.0, STANDING): desired_peek = Vector3.ZERO; peek = false; break
				var distance: float = from.distance_to(face.position)
				target = tangent * axis * (2.4 if aiming else 3.2) + cover_normal * clampf((0.43 - distance) * 12, -3.0, 3.0)
				cover_enter = maxf(0, cover_enter - delta)
	peek_offset = peek_offset.move_toward(desired_peek, delta * 5)
	if state == "slide":
		elapsed += delta
		var motion := slide_direction * lerpf(10.2, 4.2, clampf(elapsed / 0.62, 0, 1))
		actor.velocity.x = motion.x
		actor.velocity.z = motion.z
		if elapsed >= 0.62 or not grounded or aiming:
			state = "free"
			crouched = not clear_at(actor.global_position, STANDING)
	else:
		if crouched: target *= 0.5
		var acceleration := 52.0 if grounded else 16.0
		if direction.length() < 0.1: acceleration = 64.0 if grounded else 8.0
		var horizontal := Vector2(actor.velocity.x, actor.velocity.z).move_toward(Vector2(target.x, target.z), delta * acceleration)
		actor.velocity.x = horizontal.x
		actor.velocity.z = horizontal.y
	var low := crouched or state == "slide" or (state == "cover" and cover_low and not peek)
	if not set_height(0.85 if state == "slide" else CROUCHED if low else STANDING): low = true
	crouch_weight = move_toward(crouch_weight, 1.0 if low else 0.0, delta * 10)
	if not grounded: actor.velocity.y -= 22.0 * delta
	if jump_buffer > 0 and floor_grace > 0 and capsule_height > 1.8:
		actor.velocity.y = 7.4
		jump_buffer = 0
		floor_grace = 0
	return false

func pose_name() -> String:
	if state == "corner": return "cover_left" if cover_low else "walk"
	if state == "transfer": return "crouch_walk" if cover_low else "run"
	if state == "vault" or state == "slide": return state
	if state == "cover":
		if cover_enter > 0: return "cover_enter" if cover_low else "cover_high"
		if peek: return "crouch_walk" if capsule_height < 1.8 else ""
		if not cover_low: return "" if Vector2(actor.velocity.x, actor.velocity.z).length() > 0.3 else "cover_high"
		if Vector2(actor.velocity.x, actor.velocity.z).length() < 0.3: return "cover_idle"
		return "cover_left" if (cover_normal.cross(Vector3.UP)).dot(actor.velocity) > 0 else "cover_right"
	if not actor.is_on_floor(): return "jump"
	if landed > 0: return "land"
	if capsule_height < 1.8: return "crouch_walk" if Vector2(actor.velocity.x, actor.velocity.z).length() > 0.2 else "crouch_idle"
	return ""

func reset() -> void:
	state = "free"
	crouched = false
	peek = false
	peek_offset = Vector3.ZERO
	cover_body = null
	cover_path.clear()
	transfer_candidate = {}
	transition_aborted = false
	jump_buffer = 0
	cooldown = 0
	actor.velocity = Vector3.ZERO
	set_height(STANDING)
