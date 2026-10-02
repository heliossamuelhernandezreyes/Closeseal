extends Control
var arena: Node3D
var font: Font
var menu_button: Button
var mobile := OS.has_feature("mobile")
var stick_index := -1
var look_index := -1
var stick_origin := Vector2.ZERO
var stick_point := Vector2.ZERO
var touch_buttons: Dictionary = {}
var ink := Color("e9f2f4")
var cyan := Color("5fcfe0")
var muted := Color("9fb4bf")
var panel := Color(0.035, 0.075, 0.105, 0.89)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	menu_button = Button.new()
	menu_button.text = "INICIAR OPERACIÓN"
	menu_button.add_theme_font_size_override("font_size", 21)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("4dc5d9")
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	menu_button.add_theme_stylebox_override("normal", style)
	menu_button.add_theme_color_override("font_color", Color("09232c"))
	add_child(menu_button)
	menu_button.pressed.connect(arena.begin)
	update_menu()

func update_menu() -> void:
	menu_button.visible = not arena.playing
	menu_button.text = "REINTENTAR OPERACIÓN" if not arena.outcome.is_empty() else "CONTINUAR" if arena.started else "INICIAR OPERACIÓN"

func _process(_delta: float) -> void:
	menu_button.position = Vector2(48, size.y - 126)
	menu_button.size = Vector2(330, 62)
	queue_redraw()

func label_at(text: String, point: Vector2, pixels := 18, color := Color("e9f2f4")) -> void:
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, color)

func _draw() -> void:
	if not is_instance_valid(arena.player): return
	var w := size.x
	var h := size.y
	if not arena.playing:
		draw_rect(Rect2(0, 0, w, h), Color(0.025, 0.065, 0.092, 0.92))
		draw_rect(Rect2(48, 43, 42, 4), cyan)
		label_at("CLOSESEAL    /    OPERACIÓN 01", Vector2(48, 80), 16, cyan)
		label_at("NEXO", Vector2(44, 196), 92)
		label_at("ZONA DE COMBATE", Vector2(48, 245), 30, muted)
		label_at("Asegura tres puntos. Sobrevive. Regresa a la salida.", Vector2(48, 306), 20)
		label_at("256 × 256 m   ·   16 hostiles   ·   Rutas de flanqueo", Vector2(48, 344), 17, muted)
		label_at("Puesto elevado, hangar abierto y patios con cobertura.", Vector2(48, 378), 17, muted)
		if not arena.outcome.is_empty():
			label_at(arena.outcome, Vector2(48, 445), 25, cyan)
			label_at("%d bajas   ·   %d/3 puntos   ·   %02d:%02d" % [arena.kills, arena.secured.size(), int(arena.elapsed) / 60, int(arena.elapsed) % 60], Vector2(48, 482), 18)
		else:
			label_at("Táctil: palanca izquierda + mirada a la derecha" if mobile else "WASD mover   ·   Ratón mirar   ·   Clic disparar", Vector2(48, 450), 18)
			label_at("Botones: disparar, apuntar, recargar, saltar e interactuar" if mobile else "R recargar   ·   E asegurar   ·   Espacio saltar", Vector2(48, 480), 18, muted)
			label_at("Doble toque en palanca: correr" if mobile else "Shift correr   ·   Clic derecho apuntar   ·   Esc pausa", Vector2(48, 510), 18, muted)
		if w > 1000: draw_map(Vector2(w - 340, 170), 270)
		label_at("ASSETS 3D CC0 / KENNEY   ·   AUTORÍA CON ARCONT", Vector2(48, h - 28), 13, muted)
		return
	draw_rect(Rect2(24, 20, 365, 76), panel)
	draw_rect(Rect2(24, 20, 4, 76), cyan)
	label_at("NEXO / ASEGURAR Y EXTRAER", Vector2(42, 47), 17, cyan)
	label_at("%d/3 puntos   ·   %d/16 bajas   ·   %02d:%02d" % [arena.secured.size(), arena.kills, int(arena.elapsed) / 60, int(arena.elapsed) % 60], Vector2(42, 78), 18)
	for index in range(3):
		var id: String = ["A", "B", "C"][index]
		var x := 24 + index * 126
		draw_rect(Rect2(x, 105, 116, 35), panel)
		label_at(id + ("  ASEGURADO" if id in arena.secured else "  PENDIENTE"), Vector2(x + 9, 128), 13, Color("66dfac") if id in arena.secured else muted)
	draw_map(Vector2(w - 192, 24), 164)
	var center := Vector2(w, h) * 0.5
	var cross_color := Color("ffbb68") if arena.hit_marker > 0 else ink
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + dir * 5, center + dir * 12, cross_color, 2)
	if arena.hit_marker > 0:
		for dir in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]: draw_line(center + dir * 8, center + dir * 15, cross_color, 2)
	if arena.damage_flash > 0:
		var damage_color := Color(0.9, 0.13, 0.08, arena.damage_flash)
		draw_rect(Rect2(0, 0, w, 8), damage_color)
		draw_rect(Rect2(0, h - 8, w, 8), damage_color)
		draw_rect(Rect2(0, 0, 8, h), damage_color)
		draw_rect(Rect2(w - 8, 0, 8, h), damage_color)
	var health_x := 24.0
	var health_y := h - 90 if not mobile else 165.0
	draw_rect(Rect2(health_x, health_y, 220, 65), panel)
	label_at("SALUD  %03d" % int(arena.player.health), Vector2(health_x + 15, health_y + 28), 20)
	draw_rect(Rect2(health_x + 15, health_y + 43, 190, 5), Color("304757"))
	draw_rect(Rect2(health_x + 15, health_y + 43, 190 * arena.player.health / 100, 5), cyan)
	var ammo_y := h - 94 if not mobile else h - 335
	draw_rect(Rect2(w - 260, ammo_y, 236, 69), panel)
	label_at("%02d" % arena.player.ammo, Vector2(w - 242, ammo_y + 44), 36)
	label_at("/ %03d   ·   NX-24" % arena.player.reserve, Vector2(w - 184, ammo_y + 39), 15, muted)
	if arena.player.reload_remaining > 0: label_at("RECARGANDO", Vector2(w - 243, ammo_y + 61), 12, cyan)
	if arena.message_time > 0: label_at(arena.message, Vector2(w * 0.5 - 220, 175), 17, cyan)
	if not arena.capture_id.is_empty():
		label_at("ASEGURANDO " + arena.capture_id, center + Vector2(-85, 76), 17, cyan)
		draw_rect(Rect2(center.x - 100, center.y + 90, 200, 5), panel)
		draw_rect(Rect2(center.x - 100, center.y + 90, 200 * arena.capture_time / 3, 5), cyan)
	else:
		for definition in arena.design.beacons:
			if definition.id not in arena.secured and arena.player.global_position.distance_to(arena.vec(definition.position)) < 3.8:
				label_at("INTERACTUAR / ASEGURAR " + definition.id if mobile else "[E] ASEGURAR " + definition.id, center + Vector2(-135, 76), 18, cyan)
		if arena.secured.size() == 3: label_at("REGRESA A SALIDA · INTERACTUAR", Vector2(410, 46), 17, Color("66dfac"))
	if mobile: draw_touch()
	else: label_at("R RECARGAR    E INTERACTUAR    SHIFT CORRER    ESC PAUSA", Vector2(w * 0.5 - 235, h - 33), 13, muted)

func draw_map(origin: Vector2, extent: float) -> void:
	draw_rect(Rect2(origin, Vector2.ONE * extent), panel)
	var factor := extent / 256.0
	var center := origin + Vector2.ONE * extent * 0.5
	for object in arena.contract.authoring.objects:
		if object.id.ends_with("_collision") or object.id.begins_with("cover_") or object.id.begins_with("command_") or object.id.begins_with("hangar_"):
			var point := center + Vector2(object.position[0], object.position[2]) * factor
			var dimensions := Vector2(object.size[0], object.size[2]) * factor
			draw_rect(Rect2(point - dimensions * 0.5, dimensions), Color("355166"))
	for definition in arena.design.beacons:
		var point := center + Vector2(definition.position[0], definition.position[2]) * factor
		draw_circle(point, 5, Color("66dfac") if definition.id in arena.secured else cyan)
		label_at(definition.id, point + Vector2(7, 4), 13, ink)
	for enemy in arena.enemies:
		if not enemy.dead and enemy.global_position.distance_to(arena.player.global_position) < 35:
			draw_circle(center + Vector2(enemy.global_position.x, enemy.global_position.z) * factor, 2, Color("ed856a"))
	var p := center + Vector2(arena.player.global_position.x, arena.player.global_position.z) * factor
	draw_circle(p, 4, ink)
	draw_line(p, p + Vector2(-sin(arena.player.rotation.y), -cos(arena.player.rotation.y)) * 12, ink, 2)
	draw_rect(Rect2(origin, Vector2.ONE * extent), Color("51748a"), false, 1)

func button_rect(action: String) -> Rect2:
	var locations := {"fire": Vector2(size.x - 130, size.y - 165), "aim": Vector2(size.x - 245, size.y - 158),
		"reload": Vector2(size.x - 130, size.y - 270), "jump": Vector2(size.x - 360, size.y - 158),
		"interact": Vector2(size.x - 245, size.y - 270), "pause": Vector2(size.x - 80, 203)}
	return Rect2(locations[action], Vector2(92, 80) if action != "pause" else Vector2(56, 45))

func draw_touch() -> void:
	var origin := stick_origin if stick_index >= 0 else Vector2(140, size.y - 145)
	draw_circle(origin, 75, Color(0.08, 0.16, 0.21, 0.6))
	draw_arc(origin, 75, 0, TAU, 64, muted, 2)
	draw_circle(stick_point if stick_index >= 0 else origin, 28, Color(0.36, 0.75, 0.81, 0.7))
	for action in ["fire", "aim", "reload", "jump", "interact", "pause"]:
		var rect := button_rect(action)
		draw_rect(rect, panel)
		draw_rect(rect, cyan if action == "fire" else muted, false, 2)
		var title: String = {"fire": "FUEGO", "aim": "MIRA", "reload": "CARGAR", "jump": "SALTO", "interact": "USAR", "pause": "II"}[action]
		label_at(title, rect.position + Vector2(13, rect.size.y / 2 + 6), 15, ink)

func clear_touch() -> void:
	stick_index = -1
	look_index = -1
	touch_buttons.clear()
	arena.player.clear_input()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		mobile = true
		if not event.pressed:
			if event.index == stick_index:
				stick_index = -1
				arena.player.touch_move = Vector2.ZERO
				arena.player.touch_sprint = false
			if event.index == look_index: look_index = -1
			if touch_buttons.has(event.index):
				var action: String = touch_buttons[event.index]
				if action == "fire": arena.player.fire_held = false
				if action == "aim": arena.player.aim_held = false
				touch_buttons.erase(event.index)
			return
		if not arena.playing:
			if menu_button.get_rect().has_point(event.position):
				arena.begin()
				get_viewport().set_input_as_handled()
			return
		for action in ["fire", "aim", "reload", "jump", "interact", "pause"]:
			if button_rect(action).has_point(event.position):
				touch_buttons[event.index] = action
				match action:
					"fire": arena.player.fire_held = true
					"aim": arena.player.aim_held = true
					"reload": arena.player.start_reload()
					"jump": arena.player.jump_requested = true
					"interact": arena.interact()
					"pause":
						arena.playing = false
						clear_touch()
						update_menu()
				get_viewport().set_input_as_handled()
				return
		if event.position.x < size.x * 0.4 and event.position.y > size.y * 0.4 and stick_index < 0:
			stick_index = event.index
			stick_origin = event.position
			stick_point = event.position
			arena.player.touch_sprint = event.double_tap
		elif look_index < 0: look_index = event.index
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and arena.playing:
		if event.index == stick_index:
			var offset: Vector2 = (event.position - stick_origin).limit_length(75)
			stick_point = stick_origin + offset
			arena.player.touch_move = offset / 75.0
		elif event.index == look_index: arena.player.look(event.relative * 1.6)
		get_viewport().set_input_as_handled()
