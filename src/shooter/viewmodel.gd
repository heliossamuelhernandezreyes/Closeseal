extends Node3D
const SKIN = preload("res://src/shooter/character_rig.gd")
const POSE = preload("res://src/shooter/combat_pose.gd")
var weapon: Node3D
var muzzle: Node3D
var skeleton: Skeleton3D
var combat: SkeletonModifier3D
var magazine: MeshInstance3D
var magazine_rest := Transform3D.IDENTITY
var reload_time := 0.0
var death_time := 0.0
var recoil := 0.0
var phase := 0.0
var aim_blend := 0.0
var player: CharacterBody3D

func _ready() -> void:
	var arms: Node3D = load("res://assets/shooter/serious/arms.glb").instantiate()
	arms.name = "ArmoredArms"
	arms.rotation.y = PI
	arms.position = Vector3(0, -1.90, -0.16)
	add_child(arms)
	SKIN.apply_skin(arms, "military")
	skeleton = arms.find_child("Skeleton3D", true, false)
	weapon = load("res://assets/shooter/serious/akm.glb").instantiate()
	add_child(weapon)
	weapon.position = Vector3(0.12, -0.19, -0.34)
	magazine = weapon.find_child("Magazine", true, false)
	magazine_rest = magazine.transform
	muzzle = Node3D.new()
	weapon.add_child(muzzle)
	muzzle.position = Vector3(0, 0, -0.49)
	combat = POSE.new()
	combat.rig = self
	combat.first_person = true
	skeleton.add_child(combat)
	for mesh in find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(delta: float) -> void:
	if not is_instance_valid(player): return
	reload_time = player.reload_remaining
	recoil = player.recoil
	phase += delta * Vector2(player.velocity.x, player.velocity.z).length() * 1.7
	aim_blend = move_toward(aim_blend, 1.0 if player.is_aiming() else 0.0, delta * 7)
	var bob := Vector3(sin(phase) * 0.006, cos(phase * 2) * 0.004, 0) * (1 - aim_blend) if player.is_on_floor() else Vector3.ZERO
	var base := Vector3(0.12, -0.19, -0.34).lerp(Vector3(0, -0.049, -0.30), aim_blend)
	var reload_phase := 1.0 - reload_time / 1.6
	var reload_curve := sin(reload_phase * PI) if reload_time > 0 else 0.0
	weapon.position = base + bob + Vector3(0, -reload_curve * 0.065, recoil * 0.035)
	weapon.rotation = Vector3(-recoil * 0.05 + reload_curve * 0.24, reload_curve * -0.18, reload_curve * -0.35)
	magazine.transform = magazine_rest
	if reload_time > 0 and reload_phase > 0.18 and reload_phase < 0.80:
		var removal := sin(inverse_lerp(0.18, 0.80, reload_phase) * PI)
		magazine.position += Vector3(-0.11, -0.28, 0.01) * removal
