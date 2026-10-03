extends Node
## Bounded observations of the actual running build. No device result is inferred.
var arena: Node3D
var enabled := false
var frames_ms: Array[float] = []
var samples: Array[Dictionary] = []
var timer := 0.0
var seconds := 0.0
var fps := 0.0
var memory_mib := 0.0
var last_saved := ""
const MAX_FRAMES := 18000

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		enabled = not enabled

func _process(delta: float) -> void:
	if not is_instance_valid(arena) or not arena.playing: return
	seconds += delta
	timer += delta
	if frames_ms.size() < MAX_FRAMES: frames_ms.append(delta * 1000)
	if timer >= 1.0:
		timer = 0
		fps = Engine.get_frames_per_second()
		memory_mib = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		if samples.size() < 600:
			samples.append({"second": seconds, "fps": fps, "static_memory_mib": memory_mib,
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"render_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)})

func save_session() -> Dictionary:
	var ordered := frames_ms.duplicate()
	ordered.sort()
	var p95: float = ordered[mini(ordered.size() - 1, int(ordered.size() * 0.95))] if not ordered.is_empty() else 0.0
	var report := {"scope": "android-device" if OS.get_name() == "Android" else "desktop-runtime",
		"os": OS.get_name(), "device": OS.get_model_name(), "engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_video_adapter_name(), "renderer_vendor": RenderingServer.get_video_adapter_vendor(),
		"resolution": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"seconds": seconds, "frames_recorded": frames_ms.size(), "frame_ms": frames_ms, "p95_ms": p95,
		"samples": samples, "mission": arena.mission_mode,
		"limits": ["wall-frame intervals; static memory is not total process/GPU memory", "fresh session includes loading/warmup; no thermal or touch-latency measurement"]}
	last_saved = "user://nexo-performance-latest.json"
	var file := FileAccess.open(last_saved, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report))
		file.close()
	return report
