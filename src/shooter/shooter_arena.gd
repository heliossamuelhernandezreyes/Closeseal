extends Node3D
const VISUALS = preload("res://src/prototype/map_visual_kit.gd")
const PLAYER = preload("res://src/shooter/player.gd")
const ENEMY = preload("res://src/shooter/enemy.gd")
const HUD = preload("res://src/shooter/shooter_hud.gd")
var contract: Dictionary
var design: Dictionary
var world: Node3D
var navigation: NavigationRegion3D
var player: CharacterBody3D
var hud: Control
var enemies: Array[CharacterBody3D] = []
var beacons: Array[Node3D] = []
var pickups: Array[Node3D] = []
var secured: Array[String] = []
var rng := RandomNumberGenerator.new()
var playing := false
var started := false
var outcome := ""
var elapsed := 0.0
var kills := 0
var hit_marker := 0.0
var damage_flash := 0.0
var capture_id := ""
var capture_time := 0.0
var message := ""
var message_time := 0.0
var effect_count := 0
var sounds: Dictionary = {}
var visual_stats: Dictionary

func _ready() -> void:
	configure_input()
	rng.seed = 7326
	contract = JSON.parse_string(FileAccess.get_file_as_string("res://maps/nexo_combat_01.json"))
	design = contract.shooter_design
	world = Node3D.new()
	world.name = "AuthoredCombatMap"
	add_child(world)
	visual_stats = VISUALS.new(world, contract).build()
	assert(visual_stats.errors.is_empty(), str(visual_stats.errors))
	navigation = NavigationRegion3D.new()
	navigation.name = "CombatNavigation"
	add_child(navigation)
	NavigationServer3D.map_set_cell_size(navigation.get_navigation_map(), 0.4)
	NavigationServer3D.map_set_cell_height(navigation.get_navigation_map(), 0.2)
	if ResourceLoader.exists("res://assets/shooter/combat_navigation.tres"):
		navigation.navigation_mesh = load("res://assets/shooter/combat_navigation.tres")
	player = PLAYER.new()
	player.arena = self
	add_child(player)
	player.position = vec(design.player_spawn)
	for index in range(design.enemy_spawns.size()):
		var enemy := ENEMY.new()
		enemy.arena = self
		enemy.seed_index = index
		add_child(enemy)
		enemy.position = vec(design.enemy_spawns[index]) + Vector3.UP * 0.08
		enemy.home = enemy.position
		enemies.append(enemy)
	for definition in design.beacons:
		var beacon := Node3D.new()
		add_child(beacon)
		beacon.position = vec(definition.position)
		beacon.set_meta("id", definition.id)
		add_beacon_visual(beacon, definition.id, Color("44c4dc"))
		beacons.append(beacon)
	var extraction := Node3D.new()
	add_child(extraction)
	extraction.position = vec(design.extraction)
	add_beacon_visual(extraction, "SALIDA", Color("66dfac"))
	for position_value in design.pickups:
		var pickup: Node3D = load("res://assets/shooter/kenney/blasters/crate-medium.glb").instantiate()
		add_child(pickup)
		pickup.position = vec(position_value) + Vector3.UP * 0.45
		pickup.scale = Vector3.ONE * 1.7
		pickups.append(pickup)
	for sound_name in ["shot", "hit", "reload", "secure"]:
		sounds[sound_name] = load("res://assets/shooter/audio/" + sound_name + ".wav")
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUD.new()
	hud.arena = self
	layer.add_child(hud)
	DisplayServer.window_set_title("Closeseal · Nexo: zona de combate")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func configure_input() -> void:
	var keys := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "reload": KEY_R,
		"jump": KEY_SPACE, "sprint": KEY_SHIFT, "interact": KEY_E, "pause_game": KEY_ESCAPE}
	for action in keys:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)
	for action in ["fire", "aim"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT if action == "fire" else MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action, event)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and started and outcome.is_empty():
		playing = not playing
		player.clear_input()
		hud.clear_touch()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if playing and not hud.mobile else Input.MOUSE_MODE_VISIBLE
		hud.update_menu()

func begin() -> void:
	if not outcome.is_empty():
		get_tree().reload_current_scene()
		return
	started = true
	playing = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if hud.mobile else Input.MOUSE_MODE_CAPTURED
	hud.update_menu()

func finish(won: bool) -> void:
	playing = false
	outcome = "OPERACIÓN COMPLETADA" if won else "OPERACIÓN INTERRUMPIDA"
	player.clear_input()
	hud.clear_touch()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.update_menu()

func _process(delta: float) -> void:
	hit_marker = maxf(0.0, hit_marker - delta)
	damage_flash = maxf(0.0, damage_flash - delta)
	message_time = maxf(0.0, message_time - delta)
	if not playing: return
	elapsed += delta
	for pickup in pickups:
		if pickup.visible:
			pickup.rotation.y += delta * 0.4
			if pickup.global_position.distance_to(player.global_position + Vector3.UP * 0.45) < 2.0:
				pickup.hide()
				player.reserve += 48
				player.health = minf(100.0, player.health + 35)
				announce("+48 MUNICIÓN   ·   +35 SALUD")
	if not capture_id.is_empty():
		var definition: Dictionary = design.beacons.filter(func(item): return item.id == capture_id)[0]
		if player.global_position.distance_to(vec(definition.position)) > 3.8:
			capture_id = ""
			capture_time = 0
		else:
			capture_time += delta
			if capture_time >= 3.0:
				secured.append(capture_id)
				for beacon in beacons:
					if beacon.get_meta("id") == capture_id: beacon.get_node("Marker").modulate = Color("66dfac")
				announce("PUNTO " + capture_id + " ASEGURADO")
				sound("secure")
				capture_id = ""
				capture_time = 0
				if secured.size() == 3: announce("REGRESA A LA SALIDA PARA COMPLETAR LA OPERACIÓN")

func interact() -> void:
	if not playing: return
	if secured.size() == 3 and player.global_position.distance_to(vec(design.extraction)) < 4.5:
		finish(true)
		return
	for definition in design.beacons:
		if definition.id not in secured and player.global_position.distance_to(vec(definition.position)) < 3.8:
			capture_id = definition.id
			capture_time = 0
			return
	announce("ACÉRCATE A UN PUNTO A, B O C PARA ASEGURARLO")

func announce(value: String) -> void:
	message = value
	message_time = 3.5

func add_beacon_visual(node: Node3D, text: String, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.25
	cylinder.bottom_radius = 0.6
	cylinder.height = 1.0
	mesh.mesh = cylinder
	mesh.position.y = 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.35
	mesh.material_override = material
	node.add_child(mesh)
	var label := Label3D.new()
	label.name = "Marker"
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.012
	label.position.y = 3.5
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	node.add_child(label)

func tracer(start: Vector3, end: Vector3, color: Color) -> void:
	if effect_count > 40: return
	var mesh := MeshInstance3D.new()
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate.surface_add_vertex(start)
	immediate.surface_add_vertex(end)
	immediate.surface_end()
	mesh.mesh = immediate
	mesh.material_override = effect_material(color)
	add_child(mesh)
	effect_count += 1
	get_tree().create_timer(0.07).timeout.connect(func(): mesh.queue_free(); effect_count -= 1)

func impact(position_value: Vector3, normal: Vector3) -> void:
	if effect_count > 40: return
	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.045
	sphere.height = 0.09
	spark.mesh = sphere
	spark.material_override = effect_material(Color("ffbf72"))
	add_child(spark)
	spark.global_position = position_value + normal * 0.035
	effect_count += 1
	var tween := create_tween()
	tween.tween_property(spark, "scale", Vector3.ONE * 0.05, 0.2)
	tween.tween_callback(func(): spark.queue_free(); effect_count -= 1)

func effect_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func sound(sound_name: String) -> void:
	var speaker := AudioStreamPlayer.new()
	speaker.stream = sounds[sound_name]
	speaker.volume_db = -16 if sound_name == "shot" else -10
	add_child(speaker)
	speaker.finished.connect(speaker.queue_free)
	speaker.play()

static func vec(value: Array) -> Vector3: return Vector3(value[0], value[1], value[2])
