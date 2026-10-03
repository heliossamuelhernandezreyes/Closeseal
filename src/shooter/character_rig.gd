extends Node3D
const POSE = preload("res://src/shooter/combat_pose.gd")
var skeleton: Skeleton3D
var animation: AnimationPlayer
var tree: AnimationTree
var combat: SkeletonModifier3D
var weapon: Node3D
var muzzle: Node3D
var magazine: MeshInstance3D
var magazine_rest := Transform3D.IDENTITY
var death_time := 0.0
var reload_time := 0.0
var recoil := 0.0
var motion_speed := 0.0
var motion_blend := 0.0
var skin_name := "military"
var clip := "idle"
var aim_pitch := 0.0
var hit_weight := 0.0

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
	animation.add_animation_library("", load("res://assets/shooter/serious/combat_motion.tres"))
	var blend := AnimationNodeBlendSpace1D.new()
	for definition in [["idle", 0.0], ["walk", 1.8], ["run", 3.8]]:
		var node := AnimationNodeAnimation.new()
		node.animation = definition[0]
		blend.add_blend_point(node, definition[1], -1, definition[0])
	blend.min_space = 0
	blend.max_space = 3.8
	blend.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE
	tree = AnimationTree.new()
	tree.name = "LocomotionBlend"
	add_child(tree)
	tree.anim_player = NodePath("../CombatAnimations")
	tree.tree_root = blend
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
	material.metallic = 0.45
	material.emission_enabled = true
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	material.emission_texture = load(prefix + "emission.jpg")
	material.emission = Color("8ac4d1") if variant == "military" else Color("d98763")
	material.emission_energy_multiplier = 0.65
	_bind_material(node, material)

static func _bind_material(node: Node, material: Material) -> void:
	if node is MeshInstance3D: node.material_override = material
	for child in node.get_children(): _bind_material(child, material)

func set_motion(speed: float, _airborne := false) -> void:
	motion_speed = speed
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
	tree.set("parameters/blend_position", motion_blend)
	var phase := 1.0 - reload_time / 1.6
	var reload_curve := sin(phase * PI) if reload_time > 0 else 0.0
	weapon.position = Vector3(0.14, 1.42, -0.42 + recoil * 0.04)
	weapon.rotation = Vector3(aim_pitch - recoil * 0.08 + reload_curve * 0.28, 0, -reload_curve * 0.12)
	magazine.transform = magazine_rest
	if reload_time > 0 and phase > 0.18 and phase < 0.80:
		var removal := sin(inverse_lerp(0.18, 0.80, phase) * PI)
		magazine.position += Vector3(-0.12, -0.30, 0.02) * removal
