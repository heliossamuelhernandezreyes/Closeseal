extends Node3D
const POSE = preload("res://src/shooter/combat_pose.gd")
var skeleton: Skeleton3D
var animation: AnimationPlayer
var combat: SkeletonModifier3D
var weapon: Node3D
var muzzle: Node3D
var death_time := 0.0
var reload_time := 0.0
var recoil := 0.0
var motion_speed := 0.0
var clip := ""
var skin_name := "survivorFemaleA"

func _ready() -> void:
	var model: Node3D = load("res://assets/shooter/kenney/survivors/Model/characterMedium.fbx").instantiate()
	model.name = "Model"
	model.scale = Vector3.ONE * 0.5
	# The source FBX faces +Z; the combat convention is -Z.
	model.rotation.y = PI
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false)
	apply_skin(model)
	animation = AnimationPlayer.new()
	add_child(animation)
	animation.root_node = NodePath("../Model")
	var library := AnimationLibrary.new()
	for source in ["idle", "run", "jump"]:
		var imported: Node = load("res://assets/shooter/kenney/survivors/Animations/" + source + ".fbx").instantiate()
		var source_player: AnimationPlayer = imported.find_child("AnimationPlayer", true, false)
		var source_name: String = "Root|" + source.capitalize()
		var anim: Animation = source_player.get_animation(source_name).duplicate(true)
		anim.loop_mode = Animation.LOOP_NONE if source == "jump" else Animation.LOOP_LINEAR
		library.add_animation(source, anim)
		imported.free()
	animation.add_animation_library("", library)
	weapon = load("res://assets/shooter/kenney/blasters/blaster-d.glb").instantiate()
	weapon.name = "Weapon"
	add_child(weapon)
	weapon.position = Vector3(0.08, 1.18, -0.28)
	muzzle = Node3D.new()
	weapon.add_child(muzzle)
	muzzle.position.z = -0.46
	combat = POSE.new()
	combat.rig = self
	skeleton.add_child(combat)
	set_motion(0.0)

func apply_skin(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load("res://assets/shooter/kenney/survivors/Skins/" + skin_name + ".png")
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.roughness = 0.88
		node.material_override = mat
	for child in node.get_children(): apply_skin(child)

func set_motion(speed: float, airborne := false) -> void:
	motion_speed = speed
	if death_time > 0.0: return
	var next := "jump" if airborne else "run" if speed > 0.3 else "idle"
	if next != clip:
		clip = next
		animation.play(clip, 0.16)
	animation.speed_scale = clampf(speed / 4.2, 0.6, 1.65) if clip == "run" else 1.0

func fire() -> void: recoil = 1.0
func reload() -> void: reload_time = 1.6
func die() -> void:
	death_time = 0.001
	animation.pause()

func _process(delta: float) -> void:
	recoil = move_toward(recoil, 0.0, delta * 7.0)
	reload_time = maxf(0.0, reload_time - delta)
	if death_time > 0.0:
		death_time += delta
		weapon.visible = death_time < 0.6
	weapon.position = Vector3(0.08, 1.18, -0.28 + recoil * 0.06)
	weapon.rotation.x = -recoil * 0.13 + sin(reload_time / 1.6 * PI) * 0.45
