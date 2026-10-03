extends Control
var arena: Node3D
var font: Font
var menu_button: Button
var credits_button: Button
var credits: PopupPanel
var mobile := OS.has_feature("mobile")
var stick_index := -1
var look_index := -1
var stick_origin := Vector2.ZERO
var stick_point := Vector2.ZERO
var touch_buttons: Dictionary = {}
var ink := Color("e9f2f4")
var cyan := Color("5fcfe0")
var muted := Color("9fb4bf")
var panel := Color(0.025, 0.045, 0.058, 0.68)
var ui_scale := 1.0
var ui_offset := Vector2.ZERO
const ACTIONS = ["fire", "aim", "reload", "jump", "interact", "cover", "stance", "shoulder", "pause"]

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
	credits_button = Button.new()
	credits_button.text = "CRÉDITOS"
	credits_button.add_theme_font_size_override("font_size", 18)
	add_child(credits_button)
	credits = PopupPanel.new()
	add_child(credits)
	var credit_text := RichTextLabel.new()
	credit_text.position = Vector2(22, 20)
	credit_text.size = Vector2(666, 390)
	credit_text.add_theme_font_size_override("normal_font_size", 18)
	credit_text.text = "NEXO INDUSTRIAL — 0.4 / MOVILIDAD TÁCTICA\n\nSoldado: Irondust — CC0\nopengameart.org/content/sci-fi-soldier\n\nAKM: LonesomeDucky — CC0\nopengameart.org/content/weathered-akm-rifle\n\nEntorno, materiales y cielo: Poly Haven — CC0\npolyhaven.com\n\nRecarga: SpringySpringo — CC0\nopengameart.org/content/gun-reload-sounds\n\nDisparo: Copyright (c) 2009 Vincent Sevedge (Tabasco)\nCC BY 3.0 — creativecommons.org/licenses/by/3.0/\nopengameart.org/content/gunshot-sounds\nFragmento SKS recortado, filtrado y convertido a mono.\n\nAnimación, mapa y otros efectos: Closeseal / Arcont.\nLicencias y procedencia completas incluidas en el proyecto."
	credits.add_child(credit_text)
	var close_button := Button.new()
	close_button.text = "CERRAR"
	close_button.position = Vector2(490, 425)
	close_button.size = Vector2(180, 48)
	credits.add_child(close_button)
	close_button.pressed.connect(credits.hide)
	credits_button.pressed.connect(func(): credits.popup_centered(Vector2i(710, 490)))
	update_menu()

func update_menu() -> void:
	menu_button.visible = not arena.playing
	credits_button.visible = not arena.playing
	menu_button.text = "REINTENTAR OPERACIÓN" if not arena.outcome.is_empty() else "CONTINUAR" if arena.started else "INICIAR OPERACIÓN"

func update_layout() -> void:
	ui_scale = minf(size.x / 1280.0, size.y / 720.0)
	ui_offset = (size - Vector2(1280, 720) * ui_scale) * 0.5

func _process(_delta: float) -> void:
	update_layout()
	menu_button.position = ui_offset + Vector2(48, 594) * ui_scale
	menu_button.size = Vector2(330, 62) * ui_scale
	credits_button.position = ui_offset + Vector2(410, 594) * ui_scale
	credits_button.size = Vector2(190, 62) * ui_scale
	queue_redraw()

func label_at(text: String, point: Vector2, pixels := 18, color := Color("e9f2f4")) -> void:
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, color)

func _draw() -> void:
	if not is_instance_valid(arena.player): return
	update_layout()
	draw_set_transform(ui_offset, 0, Vector2.ONE * ui_scale)
	var w := 1280.0
	var h := 720.0
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
			label_at("4 dedos: palanca + mirada + fuego + mira" if mobile else "WASD mover   ·   Ratón mirar   ·   Clic disparar", Vector2(48, 450), 18)
			label_at("Extiende la palanca: correr · CUBRIR: pegarse a una pared" if mobile else "R recargar   ·   E asegurar   ·   Espacio saltar", Vector2(48, 480), 18, muted)
			label_at("DESLIZAR al correr · PASAR para saltar cobertura" if mobile else "Shift correr · Ctrl deslizar/agachar · C cubrir · Espacio pasar", Vector2(48, 510), 18, muted)
		if w > 1000: draw_map(Vector2(w - 340, 170), 270)
		label_at("NEXO 0.4   /   MOVILIDAD TÁCTICA", Vector2(48, h - 28), 13, muted)
		return
	var player = arena.player
	var movement = player.mobility
	# Compact mission ribbon: status, three targets and clock share one region.
	draw_style_box(card(), Rect2(30, 28, 330, 100))
	draw_rect(Rect2(30, 28, 3, 100), cyan)
	label_at("NEXO  /  SECTOR 07", Vector2(48, 54), 14, cyan)
	label_at("ASEGURAR Y EXTRAER", Vector2(48, 76), 17)
	for index in range(3):
		var id: String = ["A", "B", "C"][index]
		var secured: bool = id in arena.secured
		var color := Color("75ddb1") if secured else muted
		draw_circle(Vector2(60 + index * 52, 106), 12, Color(color, 0.16))
		label_at(id, Vector2(54 + index * 52, 111), 14, color)
	label_at("%02d:%02d  ·  %02d BAJAS" % [int(arena.elapsed) / 60, int(arena.elapsed) % 60, arena.kills], Vector2(217, 111), 12, muted)
	draw_map(Vector2(1036, 28), 144)
	var center := Vector2(w, h) * 0.5
	var unavailable: bool = movement.state in ["vault", "slide"] or (movement.state == "cover" and not movement.cover_low and not movement.peek)
	var cross_color := Color("ffbd78") if arena.hit_marker > 0 else Color(ink, 0.4) if unavailable else ink
	var spread := 5.0 if player.is_aiming() else 8.0 + minf(6, Vector2(player.velocity.x, player.velocity.z).length() * 0.6)
	draw_circle(center, 1.7, cross_color)
	if not unavailable:
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]: draw_line(center + dir * spread, center + dir * (spread + 6), cross_color, 1.6, true)
	if arena.hit_marker > 0:
		for dir in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]: draw_line(center + dir * 8, center + dir * 14, cross_color, 2, true)
	if arena.damage_flash > 0:
		var local_source: Vector3 = player.global_basis.inverse() * player.damage_direction
		var angle := atan2(local_source.z, local_source.x)
		draw_arc(center, 90, angle - 0.32, angle + 0.32, 18, Color(1, 0.35, 0.27, arena.damage_flash * 2.2), 5, true)
		draw_rect(Rect2(0, 0, w, 3), Color(0.9, 0.15, 0.10, arena.damage_flash))
	var health_origin := Vector2(36, 154) if mobile else Vector2(36, 616)
	label_at("+", health_origin + Vector2(0, 23), 25, Color("ff977f") if player.health < 30 else cyan)
	label_at("%03d" % int(player.health), health_origin + Vector2(26, 23), 23)
	draw_rect(Rect2(health_origin + Vector2(80, 8), Vector2(135, 4)), Color(ink, 0.2))
	draw_rect(Rect2(health_origin + Vector2(80, 8), Vector2(135 * player.health / 100, 4)), Color("ff977f") if player.health < 30 else cyan)
	label_at("REGENERANDO" if player.hurt_time == 0 and player.health < 100 else "SALUD", health_origin + Vector2(80, 29), 10, muted)
	var ammo_origin := Vector2(1002, 355) if mobile else Vector2(1036, 618)
	draw_style_box(card(), Rect2(ammo_origin, Vector2(200, 63)))
	label_at("AKM  /  AUTOMÁTICO", ammo_origin + Vector2(13, 18), 10, muted)
	label_at("%02d" % player.ammo, ammo_origin + Vector2(12, 49), 31, Color("ffbd78") if player.ammo < 8 else ink)
	label_at("/ %03d" % player.reserve, ammo_origin + Vector2(67, 47), 16, muted)
	if player.reload_remaining > 0:
		label_at("RECARGA", ammo_origin + Vector2(133, 45), 10, cyan)
		draw_rect(Rect2(ammo_origin + Vector2(12, 55), Vector2(176 * (1.0 - player.reload_remaining / 1.6), 3)), cyan)
	var mode: String = {"free": "AGACHADO" if movement.capsule_height < 1.8 else "CORRIENDO" if Vector2(player.velocity.x, player.velocity.z).length() > 6 else "", "cover": "ASOMADO" if movement.peek else "EN COBERTURA", "vault": "PASANDO COBERTURA", "slide": "DESLIZANDO"}[movement.state]
	if not mode.is_empty(): label_centered(mode, Vector2(640, 580), 12, cyan)
	if movement.state == "cover": label_centered("MIRA PARA ASOMARTE  ·  SALTO PARA PASAR" if movement.cover_low else "MUÉVETE AL BORDE PARA ASOMARTE", Vector2(640, 603), 11, muted)
	elif not movement.candidate.is_empty(): label_centered("CUBRIR" if mobile else "[C] CUBRIR   [ESPACIO] PASAR", Vector2(640, 603), 12, cyan)
	if arena.message_time > 0: label_centered(arena.message, Vector2(640, 161), 16, cyan)
	if not arena.capture_id.is_empty():
		label_centered("ASEGURANDO " + arena.capture_id, center + Vector2(0, 77), 16, cyan)
		draw_rect(Rect2(center.x - 90, center.y + 90, 180, 4), panel)
		draw_rect(Rect2(center.x - 90, center.y + 90, 180 * arena.capture_time / 3, 4), cyan)
	else:
		for definition in arena.design.beacons:
			if definition.id not in arena.secured and player.global_position.distance_to(arena.vec(definition.position)) < 3.8: label_centered("USAR / ASEGURAR " + definition.id if mobile else "[E] ASEGURAR " + definition.id, center + Vector2(0, 77), 16, cyan)
	if arena.secured.size() == 3: label_centered("3/3 ASEGURADOS  ·  REGRESA A SALIDA", Vector2(640, 60), 15, Color("75ddb1"))
	draw_objective_markers()
	if mobile: draw_touch()
	else: label_centered("SHIFT CORRER   CTRL DESLIZAR / AGACHAR   C CUBRIR   ESPACIO PASAR   Q HOMBRO   E USAR", Vector2(640, 696), 11, muted)

func card() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = panel
	style.set_corner_radius_all(7)
	return style

func label_centered(text: String, point: Vector2, pixels := 16, color := Color("e9f2f4")) -> void:
	label_at(text, point - Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x * 0.5, 0), pixels, color)

func draw_objective_markers() -> void:
	for definition in arena.design.beacons:
		if definition.id in arena.secured: continue
		var target: Vector3 = arena.vec(definition.position) + Vector3.UP * 2.7
		if arena.player.camera.is_position_behind(target): continue
		var point: Vector2 = (arena.player.camera.unproject_position(target) - ui_offset) / ui_scale
		if not Rect2(390, 190, 530, 280).has_point(point): continue
		var distance: float = arena.player.global_position.distance_to(target)
		if distance < 6: continue
		draw_arc(point, 10, 0, TAU, 24, Color(cyan, 0.6), 1.2, true)
		label_centered(definition.id, point + Vector2(0, 5), 12, cyan)
		label_centered("%d m" % int(distance), point + Vector2(0, 27), 11, muted)

func draw_map(origin: Vector2, extent: float) -> void:
	draw_rect(Rect2(origin, Vector2.ONE * extent), panel)
	var factor := extent / 256.0
	var center := origin + Vector2.ONE * extent * 0.5
	for object in arena.contract.authoring.objects:
		if object.id.begins_with("factory_solid_") or object.id.begins_with("barrier_collision_") or object.id.begins_with("command_") or object.id.begins_with("hangar_") or object.id.begins_with("hero_east_") or object.id.begins_with("hero_west_"):
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

func design_button_rect(action: String) -> Rect2:
	var positions := {"fire": Rect2(48, 244, 92, 92), "aim": Rect2(1082, 244, 92, 92),
		"reload": Rect2(1140, 432, 78, 66), "cover": Rect2(1037, 444, 82, 80),
		"stance": Rect2(938, 461, 80, 72), "jump": Rect2(1126, 574, 92, 82),
		"interact": Rect2(1015, 581, 86, 72), "shoulder": Rect2(1077, 186, 110, 39), "pause": Rect2(1200, 28, 44, 40)}
	return positions[action]

func button_rect(action: String) -> Rect2:
	update_layout()
	var rect := design_button_rect(action)
	return Rect2(ui_offset + rect.position * ui_scale, rect.size * ui_scale)

func touch_title(action: String) -> String:
	var movement = arena.player.mobility
	return {"fire": "FUEGO", "aim": "MIRA", "reload": "CARGAR", "jump": "PASAR" if movement.state == "cover" and movement.cover_low else "SALTO",
		"interact": "USAR", "cover": "SALIR" if movement.state == "cover" else "CUBRIR",
		"stance": "DESLIZAR" if Vector2(arena.player.velocity.x, arena.player.velocity.z).length() > 6 else "LEVANTAR" if movement.capsule_height < 1.8 else "AGACHAR", "shoulder": "HOMBRO", "pause": "II"}[action]

func draw_touch() -> void:
	var origin := (stick_origin - ui_offset) / ui_scale if stick_index >= 0 else Vector2(155, 575)
	var point := (stick_point - ui_offset) / ui_scale if stick_index >= 0 else origin
	draw_circle(origin, 73, Color(0.08, 0.12, 0.16, 0.32))
	draw_arc(origin, 73, 0, TAU, 64, Color(cyan if arena.player.touch_sprint else ink, 0.4), 1.5, true)
	draw_circle(point, 26, Color(0.75, 0.87, 0.9, 0.35))
	label_centered("CORRER ↑" if arena.player.touch_sprint else "EXTIENDE ↑ PARA CORRER", origin + Vector2(0, -90), 10, cyan if arena.player.touch_sprint else muted)
	for action in ACTIONS:
		var rect := design_button_rect(action)
		var pressed: bool = action in touch_buttons.values()
		var available: bool = action != "cover" or arena.player.mobility.state == "cover" or not arena.player.mobility.candidate.is_empty()
		var color := cyan if pressed else ink if available else muted
		if action in ["fire", "aim", "cover", "jump"]:
			draw_circle(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.5, Color(0.025, 0.05, 0.07, 0.42))
			draw_arc(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.5, 0, TAU, 48, Color(color, 0.8 if pressed else 0.5), 2 if pressed else 1.2, true)
		else:
			draw_style_box(card(), rect)
			if pressed: draw_rect(rect, cyan, false, 2)
		label_centered(touch_title(action), rect.get_center() + Vector2(0, 5), 12 if action != "pause" else 16, color)

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
		for action in ACTIONS:
			if button_rect(action).has_point(event.position):
				touch_buttons[event.index] = action
				match action:
					"fire": arena.player.fire_held = true
					"aim": arena.player.aim_held = true
					"reload": arena.player.start_reload()
					"jump": arena.player.jump_requested = true
					"interact": arena.interact()
					"cover": arena.player.mobility.toggle_cover()
					"stance": arena.player.mobility.stance()
					"shoulder": arena.player.shoulder *= -1.0
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
			var radius := 73.0 * ui_scale
			var offset: Vector2 = (event.position - stick_origin).limit_length(radius)
			stick_point = stick_origin + offset
			arena.player.touch_move = offset / radius
			arena.player.touch_sprint = offset.length() > radius * 0.92 and offset.y < -radius * 0.65
		elif event.index == look_index: arena.player.look(event.relative * (0.95 if arena.player.is_aiming() else 1.45) / ui_scale)
		get_viewport().set_input_as_handled()
