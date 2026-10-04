extends RefCounted
## Saved per-device controls. Rejected edits preserve the last usable layout.
var look_sensitivity := 1.0
var ads_sensitivity := 1.0
var opacity := 0.8
var layouts := {}
const PATH := "user://nexo-controls.cfg"

func load_saved() -> void:
	var config := ConfigFile.new()
	if config.load(PATH)!=OK:return
	look_sensitivity=clampf(float(config.get_value("controls","look",1.0)),0.4,2.5)
	ads_sensitivity=clampf(float(config.get_value("controls","ads",1.0)),0.4,2.5)
	opacity=clampf(float(config.get_value("controls","opacity",0.8)),0.35,1.0)
	var stored: Variant=config.get_value("controls","layouts",{})
	if stored is Dictionary:
		for action in stored:
			if stored[action] is Rect2:layouts[action]=stored[action]

func save() -> Error:
	var config := ConfigFile.new()
	config.set_value("controls","look",look_sensitivity)
	config.set_value("controls","ads",ads_sensitivity)
	config.set_value("controls","opacity",opacity)
	config.set_value("controls","layouts",layouts)
	return config.save(PATH)

func rect(action: String, defaults: Dictionary) -> Rect2:
	return layouts.get(action,defaults[action])

func update_button(action: String, value: Rect2, defaults: Dictionary) -> bool:
	if not defaults.has(action) or value.size.x<34 or value.size.y<30:return false
	if not Rect2(12,12,1256,644).encloses(value):return false
	for other in defaults:
		if other!=action and value.grow(4).intersects(rect(other,defaults)):return false
	layouts[action]=value
	return true

func validate_saved(defaults: Dictionary) -> void:
	var stored:=layouts.duplicate()
	layouts.clear()
	for action in stored:update_button(action,stored[action],defaults)
