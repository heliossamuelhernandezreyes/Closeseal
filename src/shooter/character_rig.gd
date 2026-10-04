extends Node3D
const POSE = preload("res://src/shooter/combat_pose.gd")
const GROUND_POSE = preload("res://src/shooter/ground_pose.gd")
var skeleton: Skeleton3D
var animation: AnimationPlayer
var tree: AnimationTree
var combat: SkeletonModifier3D
var ground_contact: SkeletonModifier3D
var weapon: Node3D
var muzzle: Node3D
var magazine: MeshInstance3D
var magazine_rest := Transform3D.IDENTITY
var death_time := 0.0
var reload_time := 0.0
var recoil := 0.0
var motion_speed := 0.0
var motion_blend := 0.0
var motion_direction := Vector2(0, -1)
var airborne := false
var aim_target := Vector3.ZERO
var target_enabled := false
var skin_name := "military"
var clip := "idle"
var aim_pitch := 0.0
var hit_weight := 0.0
var stance_weight := 0.0
var cover_peeking := false
var action_pose := ""
var action_phase := 0.0
var action_weight := 0.0
var current_action := ""
var vault_hand_target := Vector3.ZERO

func _ready() -> void:
	var model: Node3D = load("res://assets/shooter/serious/soldier.glb").instantiate()
	model.name = "Model"
	model.rotation.y = PI
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false)
	apply_skin(model, skin_name)
	animation = AnimationPlayer.new()
	animation.name = "CombatAnimations"
	add_child(animation)
	animation.root_node = NodePath("../Model")
	animation.add_animation_library("", load("res://assets/shooter/serious/combat_motion.res"))
	var blend := AnimationNodeBlendSpace2D.new()
	for definition in [["idle", Vector2.ZERO], ["walk", Vector2(0, -1)], ["run", Vector2(0, -2)],
		["walk_back", Vector2(0, 1)], ["walk_left", Vector2(-1, 0)], ["walk_right", Vector2(1, 0)]]:
		var node := AnimationNodeAnimation.new()
		node.animation = definition[0]
		blend.add_blend_point(node, definition[1], -1, definition[0])
	blend.min_space = Vector2(-1, -2)
	blend.max_space = Vector2(1, 1)
	blend.sync = true
	var graph := AnimationNodeBlendTree.new()
	graph.add_node("Gait", blend)
	graph.add_node("Cadence", AnimationNodeTimeScale.new())
	graph.connect_node("Cadence", 0, "Gait")
	var action := AnimationNodeAnimation.new()
	action.animation = "crouch_idle"
	graph.add_node("ActionClip", action)
	graph.add_node("ActionTime", AnimationNodeTimeSeek.new())
	graph.add_node("ActionCadence", AnimationNodeTimeScale.new())
	graph.add_node("ActionBlend", AnimationNodeBlend2.new())
	graph.connect_node("ActionTime", 0, "ActionClip")
	graph.connect_node("ActionBlend", 0, "Cadence")
	graph.connect_node("ActionCadence", 0, "ActionTime")
	graph.connect_node("ActionBlend", 1, "ActionCadence")
	graph.connect_node("output", 0, "ActionBlend")
	tree = AnimationTree.new()
	tree.name = "LocomotionBlend"
	add_child(tree)
	tree.anim_player = NodePath("../CombatAnimations")
	tree.tree_root = graph
	tree.active = true
	weapon = load("res://assets/shooter/serious/akm.glb").instantiate()
	weapon.name = "Weapon"
	add_child(weapon)
	weapon.position = Vector3(0.14, 1.42, -0.42)
	magazine = weapon.find_child("Magazine", true, false)
	magazine_rest = magazine.transform
	muzzle = Node3D.new()
	weapon.add_child(muzzle)
	muzzle.position = Vector3(0, 0.0, -0.49)
	combat = POSE.new()
	combat.rig = self
	skeleton.add_child(combat)
	ground_contact = GROUND_POSE.new()
	ground_contact.rig = self
	skeleton.add_child(ground_contact)

static func apply_skin(node: Node, variant: String) -> void:
	var material := StandardMaterial3D.new()
	var prefix := "res://assets/shooter/serious/skins/" + variant + "_"
	material.albedo_texture = load(prefix + "albedo.jpg")
	material.normal_enabled = true
	material.normal_texture = load(prefix + "normal.jpg")
	material.normal_scale = 0.75
	material.roughness = 0.85
	material.roughness_texture = load(prefix + "roughness.jpg")
	material.ao_enabled = true
	material.ao_texture = load(prefix + "ao.jpg")
	material.metallic = 0.08
	material.emission_enabled = true
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	material.emission_texture = load(prefix + "emission.jpg")
	material.emission = Color("8ac4d1") if variant == "military" else Color("d98763")
	material.emission_energy_multiplier = 0.65
	_bind_material(node, material)

static func _bind_material(node: Node, material: Material) -> void:
	if node is MeshInstance3D: node.material_override = material
	for child in node.get_children(): _bind_material(child, material)

func set_motion(speed: float, in_air := false, direction := Vector2(0, -1)) -> void:
	motion_speed = speed
	motion_direction = direction.normalized() if direction.length() > 0.1 else Vector2(0, -1)
	airborne = in_air
	clip = "run" if speed > 2.6 else "walk" if speed > 0.2 else "idle"

func fire() -> void: recoil = 1.0
func reload() -> void: reload_time = 1.6
func hit() -> void: hit_weight = 1.0
func die() -> void:
	death_time = 0.001
	tree.active = false
	animation.play("death", 0.12)

func _process(delta: float) -> void:
	recoil = move_toward(recoil, 0.0, delta * 9)
	hit_weight = move_toward(hit_weight, 0, delta * 6)
	reload_time = maxf(0, reload_time - delta)
	if death_time > 0:
		death_time += delta
		weapon.visible = death_time < 0.55
		return
	motion_blend = move_toward(motion_blend, motion_speed, delta * 12)
	var magnitude := minf(motion_blend / 1.8, 1.0) if motion_blend < 1.8 else 1.0 + clampf((motion_blend - 4.3) / 2.9, 0, 1)
	var direction := motion_direction
	# Sprint is forward; aiming uses the directional walk clips.
	if direction.y > -0.8: magnitude = minf(magnitude, 1.0)
	tree.set("parameters/Gait/blend_position", direction * magnitude if not airborne else Vector2.ZERO)
	var gait_speed := lerpf(1.83, 3.81, maxf(0, magnitude - 1))
	tree.set("parameters/Cadence/scale", clampf(motion_speed / gait_speed, 0.65, 2.6) if motion_speed > 0.2 else 1.0)
	if not action_pose.is_empty() and action_pose != current_action:
		var action: AnimationNodeAnimation = tree.tree_root.get_node("ActionClip")
		action.animation = action_pose
		current_action = action_pose
		tree.set("parameters/ActionTime/seek_request", 0.0)
	elif action_pose.is_empty(): current_action = ""
	if action_pose in ["vault", "slide", "cover_enter"]:
		tree.set("parameters/ActionTime/seek_request", action_phase * animation.get_animation(action_pose).length)
	var strafing := action_pose in ["cover_left", "cover_right", "cover_peek_left", "cover_peek_right"]
	tree.set("parameters/ActionCadence/scale", clampf(motion_speed / (0.78 if cover_peeking else 1.37 if strafing else 1.22), 0.7, 2.7) if strafing or action_pose == "crouch_walk" else 1.0)
	action_weight = lerpf(action_weight, 0.0 if action_pose.is_empty() else 1.0, 1.0 - exp(-delta * 18))
	tree.set("parameters/ActionBlend/blend_amount", action_weight)
	var phase := 1.0 - reload_time / 1.6
	var reload_curve := sin(phase * PI) if reload_time > 0 else 0.0
	weapon.position = Vector3(0.14, 1.42 - stance_weight * 0.52, -0.42 + recoil * 0.04)
	if cover_peeking: weapon.position.y += 0.17
	if action_pose == "vault": weapon.position = Vector3(0.28, 0.96, -0.18)
	weapon.rotation = Vector3(aim_pitch - recoil * 0.08 + reload_curve * 0.28, 0, -reload_curve * 0.12)
	if target_enabled and weapon.global_position.distance_to(aim_target) > 0.5:
		weapon.look_at(aim_target, Vector3.UP)
		weapon.rotate_object_local(Vector3.RIGHT, -recoil * 0.08 + reload_curve * 0.28)
		weapon.rotate_object_local(Vector3.FORWARD, reload_curve * 0.12)
	magazine.transform = magazine_rest
	if reload_time > 0 and phase > 0.18 and phase < 0.80:
		var removal := sin(inverse_lerp(0.18, 0.80, phase) * PI)
		magazine.position += Vector3(-0.12, -0.30, 0.02) * removal
