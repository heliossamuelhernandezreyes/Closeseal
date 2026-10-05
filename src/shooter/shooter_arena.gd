extends Node3D
const VISUALS = preload("res://src/prototype/map_visual_kit.gd")
const PLAYER = preload("res://src/shooter/player.gd")
const ENEMY = preload("res://src/shooter/enemy.gd")
const HUD = preload("res://src/shooter/shooter_hud.gd")
const METRICS = preload("res://src/shooter/runtime_metrics.gd")
const EFFECTS = preload("res://src/shooter/combat_effects.gd")
const PRESENTATION = preload("res://src/shooter/sector_presentation.gd")
var contract: Dictionary
var design: Dictionary
var world: Node3D
var navigation: NavigationRegion3D
var player: CharacterBody3D
var hud: Control
var enemies: Array[CharacterBody3D] = []
var beacons: Array[Node3D] = []
var extraction_marker: Node3D
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
var mission_mode := "full"
var metrics: Node
var kill_marker := 0.0
var effects: Node3D

func _ready() -> void:
	configure_input()
	rng.seed = 7326
	contract = JSON.parse_string(FileAccess.get_file_as_string("res://maps/nexo_combat_01.json"))
	design = contract.shooter_design
	if ResourceLoader.exists("res://assets/shooter/sector07/sector_world.tscn"):
		world=load("res://assets/shooter/sector07/sector_world.tscn").instantiate()
		if world.get_meta("canonical_sha256")!=FileAccess.get_sha256("res://maps/nexo_combat_01.json"):
			world.free()
			push_error("Rebuild the derived sector scene after changing its canonical map")
			get_tree().quit(1)
			return
		add_child(world)
		visual_stats=world.get_meta("visual_stats")
		for path in world.get_meta("baked_replaced_paths",[]):world.get_node(path).hide()
	else:
		world = Node3D.new()
		world.name = "AuthoredCombatMap"
		add_child(world)
		visual_stats = VISUALS.new(world, contract).build()
	assert(visual_stats.errors.is_empty(), str(visual_stats.errors))
	configure_presentation()
	navigation = NavigationRegion3D.new()
	navigation.name = "CombatNavigation"
	add_child(navigation)
	NavigationServer3D.map_set_cell_size(navigation.get_navigation_map(), 0.4)
	NavigationServer3D.map_set_cell_height(navigation.get_navigation_map(), 0.2)
	if ResourceLoader.exists("res://assets/shooter/combat_navigation.tres"):
		navigation.navigation_mesh = load("res://assets/shooter/combat_navigation.tres")
	player = PLAYER.new()
	player.name = "Player"
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
	extraction_marker = extraction
	add_beacon_visual(extraction, "SALIDA", Color("66dfac"))
	for position_value in design.pickups:
		var pickup: Node3D = load("res://assets/shooter/serious/polyhaven/old_military_crate/old_military_crate.gltf").instantiate()
		add_child(pickup)
		pickup.position = vec(position_value)
		pickup.scale = Vector3.ONE * 1.3
		pickups.append(pickup)
	for sound_name in ["shot", "hit", "reload", "secure", "step"]:
		sounds[sound_name] = load("res://assets/shooter/audio/" + sound_name + ".wav")
	var bank: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/shooter/audio/banks/bank.json"))
	for category in bank.banks:
		var variants: Array=[]
		for filename in bank.banks[category]:variants.append(load("res://assets/shooter/audio/banks/"+filename))
		sounds[category]=variants
	effects=EFFECTS.new();effects.arena=self;add_child(effects)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUD.new()
	hud.arena = self
	layer.add_child(hud)
	metrics = METRICS.new()
	metrics.arena = self
	add_child(metrics)
	DisplayServer.window_set_title("Closeseal · Nexo: zona de combate")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func configure_input() -> void:
	var keys := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "reload": KEY_R,
		"jump": KEY_SPACE, "sprint": KEY_SHIFT, "interact": KEY_E, "swap_shoulder": KEY_Q,
		"cover": KEY_C, "stance": KEY_CTRL, "pause_game": KEY_ESCAPE}
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
		if not playing: metrics.save_session()

func begin_slice() -> void:
	if started:
		begin()
		return
	var slice: Dictionary = design.get("slice", {})
	if slice.is_empty(): begin(); return
	mission_mode = "sector07"
	design = design.duplicate(true)
	for key in ["beacons", "pickups", "extraction", "enemy_spawns", "navigation_checks"]: design[key] = slice[key]
	extraction_marker.position = vec(design.extraction)
	for node in beacons + pickups: node.queue_free()
	beacons.clear()
	pickups.clear()
	for definition in design.beacons:
		var beacon := Node3D.new()
		add_child(beacon)
		beacon.position = vec(definition.position)
		beacon.set_meta("id", definition.id)
		add_beacon_visual(beacon, definition.id, Color("44c4dc"))
		beacons.append(beacon)
	for index in enemies.size():
		var enemy := enemies[index]
		if index >= design.enemy_spawns.size():
			enemy.dead = true
			enemy.hide()
			enemy.collision_layer = 0
			enemy.collision_mask = 0
			enemy.set_physics_process(false)
		else:
			enemy.position = vec(design.enemy_spawns[index]) + Vector3.UP * 0.08
			enemy.home = enemy.position
	for point in design.pickups:
		var pickup: Node3D = load("res://assets/shooter/serious/polyhaven/old_military_crate/old_military_crate.gltf").instantiate()
		add_child(pickup)
		pickup.position = vec(point)
		pickup.scale = Vector3.ONE * 1.3
		pickups.append(pickup)
	begin()
	announce("SECTOR 07 · ASEGURA SUMINISTROS, RELE Y ACCESO")

func begin() -> void:
	if not outcome.is_empty():
		get_tree().reload_current_scene()
		return
	if not started: metrics.reset_session()
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
	metrics.save_session()

func _process(delta: float) -> void:
	hit_marker = maxf(0.0, hit_marker - delta)
	kill_marker = maxf(0.0, kill_marker - delta)
	damage_flash = maxf(0.0, damage_flash - delta)
	message_time = maxf(0.0, message_time - delta)
	if not playing: return
	# Sector 07 starts on the extraction point. Its decorative console/label
	# must not cover the player; objective position and interaction stay intact.
	extraction_marker.visible = extraction_marker.global_position.distance_to(player.global_position) > 2.0
	elapsed += delta
	for pickup in pickups:
		if pickup.visible:
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
	if player.playtest_active: player.playtest_interactions += 1
	if secured.size() == 3 and player.global_position.distance_to(vec(design.extraction)) < 4.5:
		finish(true)
		return
	for definition in design.beacons:
		if definition.id not in secured and player.global_position.distance_to(vec(definition.position)) < 3.8:
			if mission_mode == "sector07" and design.beacons[secured.size()].id != definition.id:
				announce("ASEGURA PRIMERO " + design.beacons[secured.size()].name.to_upper())
				return
			capture_id = definition.id
			capture_time = 0
			return
	announce("ACÉRCATE A UN PUNTO A, B O C PARA ASEGURARLO")

func announce(value: String) -> void:
	message = value
	message_time = 3.5

func add_beacon_visual(node: Node3D, text: String, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var cabinet := BoxMesh.new()
	cabinet.size = Vector3(0.60, 1.25, 0.45)
	mesh.mesh = cabinet
	mesh.position.y = 0.625
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("263338")
	material.roughness = 0.6
	material.metallic = 0.3
	mesh.material_override = material
	node.add_child(mesh)
	var screen := MeshInstance3D.new()
	var panel := BoxMesh.new()
	panel.size = Vector3(0.43, 0.30, 0.02)
	screen.mesh = panel
	screen.position = Vector3(0, 0.97, 0.24)
	var screen_material := StandardMaterial3D.new()
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_material.albedo_color = color * 0.55
	screen.material_override = screen_material
	node.add_child(screen)
	var label := Label3D.new()
	label.name = "Marker"
	label.text = text
	label.font_size = 72
	label.pixel_size = 0.005
	label.position.y = 2.25
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	node.add_child(label)

func configure_presentation() -> void:
	if not world.has_meta("presentation_details"):
		PRESENTATION.lighting(world)
		world.set_meta("presentation_details",PRESENTATION.details(world))
		var reflections: Node3D=load("res://assets/shooter/sector_lighting.tscn").instantiate()
		world.add_child(reflections)
	for definition in design.get("zone_labels", []):
		if str(definition.get("id","")).begins_with("hero_"):continue
		var label := Label3D.new()
		label.text = definition.text
		label.font_size = 64
		label.pixel_size = 0.008
		label.modulate = Color("d0c6aa")
		label.outline_size = 6
		world.add_child(label)
		label.position = vec(definition.position)
		label.rotation.y = PI if definition.text.begins_with("NEXO") else 0

func tracer(start: Vector3, end: Vector3, color: Color) -> void:
	effects.tracer(start,end,color==Color("ff8961"))

func impact(position_value: Vector3, normal: Vector3, surface := "concrete") -> void:
	effects.impact(position_value,normal,surface)
	effects.sound("hit",position_value,-25.0,1.3 if surface=="metal" else 0.72 if surface=="concrete" else 0.92)

func surface_kind(collider: Object) -> String:
	if not is_instance_valid(collider):return "concrete"
	if collider.has_method("take_damage"):return "flesh"
	var node := collider as Node
	while node:
		var name_: String=node.name.to_lower()
		if "pipe" in name_ or "steel" in name_ or "rail" in name_ or "mezz" in name_ or "ramp" in name_ or "hangar" in name_:return "metal"
		if "ground" in name_ or "yard" in name_ or "asphalt" in name_:return "ground"
		node=node.get_parent()
	return "concrete"

func effect_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func sound(sound_name: String) -> void:
	if sound_name=="shot":sound_name="shot_indoor" if is_indoor(player.global_position+Vector3.UP*1.4) else "shot_outdoor"
	effects.sound(sound_name,Vector3.INF,-14.0 if sound_name.begins_with("shot") else -10.0)

func is_indoor(point: Vector3) -> bool:
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.2,point+Vector3.UP*8.0,1,[player.get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func sound_at(sound_name: String, point: Vector3, volume := -9.0, pitch := 1.0) -> void:
	effects.sound(sound_name,point,volume,pitch*rng.randf_range(0.97,1.03))

static func vec(value: Array) -> Vector3: return Vector3(value[0], value[1], value[2])
